-- Schema chunk 5 - run only after the previous chunk succeeded.
-- Generated from supabase/migrations in filename order. Do not reorder.


-- ===== 20260622000009_fix_refresh_filter_loop.sql =====
-- Fix refresh_dashboard_data_agg JSONB filter loop.
--
-- FOR v_filter IN SELECT jsonb_array_elements(...) doesn't reliably assign
-- a scalar JSONB variable in PL/pgSQL — the loop body executes but v_filter
-- contains a row record, not the jsonb value, so ->>'field' returns NULL
-- and none of the IF branches match, silently skipping all filters.
--
-- Fix: use generate_series over the array indices and access elements by index.

CREATE OR REPLACE FUNCTION rep_portal.refresh_dashboard_data_agg()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET statement_timeout = 0
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_metric      rep_portal.metric_config%ROWTYPE;
  v_sql         TEXT;
  v_filter      JSONB;
  v_field       TEXT;
  v_op          TEXT;
  v_val         TEXT;
  v_i           INT;
BEGIN
  TRUNCATE rep_portal.dashboard_data_agg;

  FOR v_metric IN
    SELECT * FROM rep_portal.metric_config
    WHERE enabled = true
    ORDER BY sort_order, metric_name
  LOOP
    IF v_metric.geography_level = 'school' THEN
      v_sql := format(
        'INSERT INTO rep_portal.dashboard_data_agg (country, province, district, school, year, metric, value)
         SELECT country, province, district, school_name, %I, %L, ',
        v_metric.year_field, v_metric.metric_name
      );
    ELSE
      v_sql := format(
        'INSERT INTO rep_portal.dashboard_data_agg (country, province, district, school, year, metric, value)
         SELECT country, province, district, ''District Total'', %I, %L, ',
        v_metric.year_field, v_metric.metric_name
      );
    END IF;

    IF v_metric.value_agg = 'sum' THEN
      v_sql := v_sql || format('ROUND(SUM(COALESCE(%I::numeric, 0)))::int', v_metric.value_field);
    ELSE
      v_sql := v_sql || 'COUNT(*)::int';
    END IF;

    v_sql := v_sql || format(' FROM rep_warehouse.%I WHERE TRUE', v_metric.source_view);

    -- NULL guards
    v_sql := v_sql || format(' AND %I IS NOT NULL AND country IS NOT NULL', v_metric.year_field);
    IF v_metric.geography_level = 'school' THEN
      v_sql := v_sql || ' AND school_name IS NOT NULL';
    ELSE
      v_sql := v_sql || ' AND district IS NOT NULL';
    END IF;

    -- JSONB filters — iterate by index to reliably extract each element
    IF v_metric.filters IS NOT NULL AND jsonb_array_length(v_metric.filters) > 0 THEN
      FOR v_i IN 0 .. jsonb_array_length(v_metric.filters) - 1
      LOOP
        v_filter := v_metric.filters -> v_i;
        v_field  := v_filter->>'field';
        v_op     := v_filter->>'op';
        v_val    := v_filter->>'value';

        IF v_op = 'eq' THEN
          v_sql := v_sql || format(' AND %I = %L', v_field, v_val);
        ELSIF v_op = 'ilike' THEN
          v_sql := v_sql || format(' AND %I ILIKE %L', v_field, v_val);
        ELSIF v_op = 'bool_true' THEN
          v_sql := v_sql || format(' AND %I = true', v_field);
        ELSIF v_op = 'not_null' THEN
          v_sql := v_sql || format(' AND %I IS NOT NULL', v_field);
        END IF;
      END LOOP;
    END IF;

    -- GROUP BY
    IF v_metric.geography_level = 'school' THEN
      v_sql := v_sql || format(' GROUP BY country, province, district, school_name, %I', v_metric.year_field);
    ELSE
      v_sql := v_sql || format(' GROUP BY country, province, district, %I', v_metric.year_field);
    END IF;

    EXECUTE v_sql;
  END LOOP;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.refresh_dashboard_data_agg() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.refresh_dashboard_data_agg() TO service_role;


-- ===== 20260622000010_fix_refresh_exception_handling.sql =====
-- Fix refresh_dashboard_data_agg to handle per-metric errors gracefully.
--
-- If one metric's dynamic SQL fails (e.g. a column name doesn't exist in the
-- source view), the previous version would ROLLBACK the entire TRUNCATE+INSERT,
-- leaving the table empty. Now each metric is wrapped in a savepoint so a
-- single failure skips that metric and continues with the rest.
--
-- Also moves TRUNCATE outside the loop so a per-metric failure doesn't wipe data.

CREATE OR REPLACE FUNCTION rep_portal.refresh_dashboard_data_agg()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET statement_timeout = 0
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_metric      rep_portal.metric_config%ROWTYPE;
  v_sql         TEXT;
  v_filter      JSONB;
  v_field       TEXT;
  v_op          TEXT;
  v_val         TEXT;
  v_i           INT;
  v_rows        BIGINT;
BEGIN
  -- Build into a staging table first, then swap, so a mid-run failure
  -- doesn't leave the live table empty.
  DROP TABLE IF EXISTS rep_portal.dashboard_data_agg_new;
  CREATE TABLE rep_portal.dashboard_data_agg_new (LIKE rep_portal.dashboard_data_agg INCLUDING ALL);

  FOR v_metric IN
    SELECT * FROM rep_portal.metric_config
    WHERE enabled = true
    ORDER BY sort_order, metric_name
  LOOP
    BEGIN
      IF v_metric.geography_level = 'school' THEN
        v_sql := format(
          'INSERT INTO rep_portal.dashboard_data_agg_new (country, province, district, school, year, metric, value)
           SELECT country, province, district, school_name, %I, %L, ',
          v_metric.year_field, v_metric.metric_name
        );
      ELSE
        v_sql := format(
          'INSERT INTO rep_portal.dashboard_data_agg_new (country, province, district, school, year, metric, value)
           SELECT country, province, district, ''District Total'', %I, %L, ',
          v_metric.year_field, v_metric.metric_name
        );
      END IF;

      IF v_metric.value_agg = 'sum' THEN
        v_sql := v_sql || format('ROUND(SUM(COALESCE(%I::numeric, 0)))::int', v_metric.value_field);
      ELSE
        v_sql := v_sql || 'COUNT(*)::int';
      END IF;

      v_sql := v_sql || format(' FROM rep_warehouse.%I WHERE TRUE', v_metric.source_view);

      -- NULL guards
      v_sql := v_sql || format(' AND %I IS NOT NULL AND country IS NOT NULL', v_metric.year_field);
      IF v_metric.geography_level = 'school' THEN
        v_sql := v_sql || ' AND school_name IS NOT NULL';
      ELSE
        v_sql := v_sql || ' AND district IS NOT NULL';
      END IF;

      -- JSONB filters — iterate by index
      IF v_metric.filters IS NOT NULL AND jsonb_array_length(v_metric.filters) > 0 THEN
        FOR v_i IN 0 .. jsonb_array_length(v_metric.filters) - 1
        LOOP
          v_filter := v_metric.filters -> v_i;
          v_field  := v_filter->>'field';
          v_op     := v_filter->>'op';
          v_val    := v_filter->>'value';

          IF v_op = 'eq' THEN
            v_sql := v_sql || format(' AND %I = %L', v_field, v_val);
          ELSIF v_op = 'ilike' THEN
            v_sql := v_sql || format(' AND %I ILIKE %L', v_field, v_val);
          ELSIF v_op = 'bool_true' THEN
            v_sql := v_sql || format(' AND %I = true', v_field);
          ELSIF v_op = 'not_null' THEN
            v_sql := v_sql || format(' AND %I IS NOT NULL', v_field);
          END IF;
        END LOOP;
      END IF;

      -- GROUP BY
      IF v_metric.geography_level = 'school' THEN
        v_sql := v_sql || format(' GROUP BY country, province, district, school_name, %I', v_metric.year_field);
      ELSE
        v_sql := v_sql || format(' GROUP BY country, province, district, %I', v_metric.year_field);
      END IF;

      EXECUTE v_sql;
      GET DIAGNOSTICS v_rows = ROW_COUNT;

    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'refresh_dashboard_data_agg: skipping metric "%" — % (SQL: %)',
        v_metric.metric_name, SQLERRM, v_sql;
    END;
  END LOOP;

  -- Swap new table into place atomically
  TRUNCATE rep_portal.dashboard_data_agg;
  INSERT INTO rep_portal.dashboard_data_agg SELECT * FROM rep_portal.dashboard_data_agg_new;
  DROP TABLE rep_portal.dashboard_data_agg_new;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.refresh_dashboard_data_agg() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.refresh_dashboard_data_agg() TO service_role;


-- ===== 20260622182849_add_deceased_columns_contacts_guides.sql =====
-- Add deceased-flag columns needed to close recon gaps identified in
-- docs/count-recon-2026-06-19.md / scripts/recon-contact.js / scripts/recon-guides.js.
-- These are landing-zone TEXT columns; filtering happens in etl_stage_*().

ALTER TABLE rep_raw.contacts ADD COLUMN contact_deceased TEXT;  -- Contact_Deceased__c
ALTER TABLE rep_raw.contacts ADD COLUMN npsp_deceased    TEXT;  -- npsp__Deceased__c
ALTER TABLE rep_raw.contacts ADD COLUMN full_name        TEXT;  -- Name (used for CAMA "not on list" exclusion)

ALTER TABLE rep_raw.guides ADD COLUMN contact_npsp_deceased TEXT;  -- Contact__r.npsp__Deceased__c


-- ===== 20260622182953_filter_contacts_guides_academic_record_deceased_archive.sql =====
-- Close three recon gaps from docs/count-recon-2026-06-19.md /
-- scripts/recon-contact.js / scripts/recon-guides.js / scripts/recon-academic-record.js:
--   * Contact:          exclude deceased (Contact_Deceased__c, npsp__Deceased__c) and blank country
--   * Guide_Role__c:    exclude Archive Contact (contact_record_type) and deceased contact
--   * Academic_Record__c (and its Post School split): exclude Archive Contact (contact_record_type)
--
-- NULL-safety: a NULL/blank deceased flag or contact_record_type is treated as
-- "not deceased" / "not Archive Contact" (passes the filter) -- only an explicit
-- positive match excludes a row. Blank country on contacts is the one exception:
-- the Salesforce report itself targets blank country as exclusion-worthy, so a
-- NULL/blank country_name is excluded here. This blank-country check is added
-- only to etl_stage_contacts(), not to the shared country_is_excluded() helper,
-- since no other recon found a blank-country gap for schools/districts/guides/
-- grants/loans/academic_record.

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_contacts()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.contacts;
    CREATE TABLE rep_staging.contacts AS
    SELECT
        salesforce_id,
        record_type_id,
        gender,
        country_id,
        country_name,
        district_id,
        wg_difficulty_overall,
        (lg_social_support_recipient = 'true') AS lg_social_support_recipient,
        (active_on_bursary = 'true')           AS active_on_bursary,
        date_joined_cama,
        school_id,
        orphan_status,
        donor_activity_id,
        donor_code_id,
        project_code_id
    FROM rep_raw.contacts
    WHERE salesforce_id IS NOT NULL
      AND NOT rep_warehouse.country_is_excluded(country_name)
      AND country_name IS NOT NULL
      AND country_name != ''
      AND coalesce(contact_deceased, 'false') = 'false'
      AND coalesce(npsp_deceased, 'false') = 'false';
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_academic_record()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.academic_record;
    CREATE TABLE rep_staging.academic_record AS
    SELECT
        row_id,
        salesforce_id,
        person_id                              AS contact_id,
        school_institution_id                  AS school_id,
        district_id,
        district_name                          AS district,
        country_name                            AS country,
        contact_record_type,
        form,
        year::smallint                         AS year,
        (received_financial_support = 'true')  AS received_financial_support,
        (repeated = 'true')                    AS repeated,
        (attendance_issues = 'true')           AS attendance_issues,
        accommodation,
        donor_code_id,
        project_code_id,
        donor_activity_id,
        start_date,
        end_date
    FROM rep_raw.academic_record
    WHERE person_id IS NOT NULL
      AND academic_record_type IN ('School', 'Step Up Fund')
      AND year ~ '^\d{4}$'
      AND year::smallint >= 2020
      AND coalesce(contact_record_type, '') != 'Archive Contact'
      AND NOT rep_warehouse.country_is_excluded(country_name);
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_post_school_clients()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.post_school_clients;
    CREATE TABLE rep_staging.post_school_clients AS
    SELECT
        row_id,
        salesforce_id,
        person_id                              AS contact_id,
        district_id,
        district_name                          AS district,
        country_name                            AS country,
        contact_record_type,
        form,
        year::smallint                         AS year,
        (received_financial_support = 'true') AS received_financial_support,
        accommodation,
        donor_code_id,
        start_date,
        end_date
    FROM rep_raw.academic_record
    WHERE person_id IS NOT NULL
      AND academic_record_type = 'Post School'
      AND year ~ '^\d{4}$'
      AND year::smallint >= 2020
      AND coalesce(contact_record_type, '') != 'Archive Contact'
      AND NOT rep_warehouse.country_is_excluded(country_name);
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_guides()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.guides;
    CREATE TABLE rep_staging.guides AS
    SELECT
        g.row_id,
        g.salesforce_id,
        g.contact_id,
        g.school_id,
        g.district_id,
        g.contact_record_type,
        g.guide_type,
        g.guide_status,
        g.guide_specialty,
        g.guide_dropout_reason,
        g.date_joined_guide_programme::timestamp    AS date_joined_guide_programme,
        g.date_completed_guide_programme::timestamp AS date_left_guide_programme,
        (g.trained_in_climate_education = 'true')   AS trained_in_climate_education,
        g.donor_id
    FROM rep_raw.guides g
    LEFT JOIN rep_raw.schools rs   ON rs.salesforce_id = g.school_id
    LEFT JOIN rep_raw.districts rd ON rd.salesforce_id = g.district_id
    WHERE g.contact_id IS NOT NULL
      AND g.guide_type IN ('Learner Guide', 'Learner Mentor', 'Transition Guide', 'Agriculture Guide', 'Business Guide')
      AND g.date_joined_guide_programme::date >= '2013-01-01'
      AND coalesce(g.contact_record_type, '') != 'Archive Contact'
      AND coalesce(g.contact_npsp_deceased, 'false') = 'false'
      AND NOT rep_warehouse.country_is_excluded(COALESCE(rs.country, rd.country_name));
END;
$$;


-- ===== 20260622185700_apply_recon_cama_filters.sql =====
-- Close the fact_cama_membership recon gap identified in scripts/recon-cama.js:
-- the Salesforce CAMA report applies three filters beyond
-- RecordType.Name = 'Cama' that etl_stage_cama_members() does not:
--   * Contact_Deceased__c = false   (rep_raw.contacts.contact_deceased)
--   * npsp__Deceased__c = false     (rep_raw.contacts.npsp_deceased)
--   * Name NOT LIKE '%not on list%' (rep_raw.contacts.full_name)
--   * Contact_Gender__c = 'Female'  (rep_raw.contacts.gender)
--
-- NULL-safety: a NULL/blank deceased flag or name is treated as "not deceased" /
-- "not a placeholder" (passes the filter) -- only an explicit positive match
-- excludes a row, consistent with the contacts/guides/academic_record filters
-- added in 20260622182953. The school-join (still INNER JOIN, dropping no-school
-- CAMA members) is left untouched -- that is a separate, still-open gap noted in
-- docs/count-recon-2026-06-19.md.

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_cama_members()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.cama_members;
    CREATE TABLE rep_staging.cama_members AS
    SELECT
        c.row_id,
        c.salesforce_id                              AS contact_id,
        c.school_id,
        sc.school_name,
        sc.district,
        c.country_name                               AS country,
        NULLIF(c.date_joined_cama, '')::TIMESTAMP    AS date_joined_cama,
        sc.active_partner_school                     AS partner_school
    FROM rep_raw.contacts c
    JOIN rep_staging.schools sc ON sc.school_id = c.school_id
    WHERE c.salesforce_id IS NOT NULL
      AND c.record_type_name = 'Cama'
      AND coalesce(c.contact_deceased, 'false') = 'false'
      AND coalesce(c.npsp_deceased, 'false') = 'false'
      AND coalesce(c.full_name, '') NOT ILIKE '%not on list%'
      AND c.gender = 'Female'
      AND NOT rep_warehouse.country_is_excluded(c.country_name);
END;
$$;


-- ===== 20260622192558_fix_contacts_full_name_column_drift.sql =====
-- Migration 20260622182849 added contact_deceased, npsp_deceased, and full_name
-- to rep_raw.contacts. On the linked remote project the first two columns landed
-- but full_name did not (drift between migration history and actual schema).
-- IF NOT EXISTS makes this a no-op locally (column already present) while
-- repairing remote.
ALTER TABLE rep_raw.contacts ADD COLUMN IF NOT EXISTS full_name TEXT;  -- Name (used for CAMA "not on list" exclusion)


-- ===== 20260622222110_allow_cama_members_without_school.sql =====
-- Restore the no-school CAMA member grain, lost in two separate places:
--
--   1. etl_stage_cama_members() (20260622185700) still does an INNER JOIN against
--      rep_staging.schools, so any CAMA contact with no school_id never reaches
--      staging at all.
--   2. etl_load_fact_cama_membership() was rewritten by 20260612103953 (geography
--      join consolidation) as a single INSERT with `WHERE s.school_id IS NOT NULL`,
--      silently dropping the second "no-school" INSERT that 20260609210744 had
--      added (and the uix_fact_cm_no_school partial unique index it created is
--      unused as a result).
--
-- Per docs/count-recon-2026-06-19.md, ~22,657 CAMA contacts have no school_id --
-- this is the majority of the recon gap on fact_cama_membership.

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_cama_members()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.cama_members;
    CREATE TABLE rep_staging.cama_members AS
    SELECT
        c.row_id,
        c.salesforce_id                              AS contact_id,
        c.school_id,
        sc.school_name,
        sc.district,
        c.country_name                               AS country,
        NULLIF(c.date_joined_cama, '')::TIMESTAMP    AS date_joined_cama,
        sc.active_partner_school                     AS partner_school
    FROM rep_raw.contacts c
    LEFT JOIN rep_staging.schools sc ON sc.school_id = c.school_id
    WHERE c.salesforce_id IS NOT NULL
      AND c.record_type_name = 'Cama'
      AND coalesce(c.contact_deceased, 'false') = 'false'
      AND coalesce(c.npsp_deceased, 'false') = 'false'
      AND coalesce(c.full_name, '') NOT ILIKE '%not on list%'
      AND c.gender = 'Female'
      AND NOT rep_warehouse.country_is_excluded(c.country_name);
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_fact_cama_membership()
RETURNS void LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
SET statement_timeout = 0 AS $$
BEGIN
    -- CAMA members with a school
    INSERT INTO rep_warehouse.fact_cama_membership
        (source_contact_id, contact_id, source_school_id, school_id, geography_id,
         date_joined_cama, date_joined_id, partner_school,
         lin_is_current, lin_change_type, lin_source_system, lin_source_file,
         lin_load_batch_id, lin_inserted_at, lin_source_row_number)
    SELECT
        s.contact_id, dct.id,
        s.school_id,  ds.id,
        COALESCE(ds.geography_id, dg_sd.id),
        s.date_joined_cama, dd.id,
        s.partner_school,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        NOW(),
        s.row_id
    FROM rep_staging.cama_members s
    LEFT JOIN rep_warehouse.dim_contact   dct   ON dct.source_contact_id = s.contact_id AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_school    ds    ON ds.source_school_id   = s.school_id  AND ds.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date      dd    ON dd.id = TO_CHAR(s.date_joined_cama::timestamp, 'YYYYMMDD')::integer
    LEFT JOIN rep_warehouse.dim_geography dg_sd ON dg_sd.country = s.country AND dg_sd.district = s.district AND dg_sd.scd_is_current = true
    WHERE s.contact_id IS NOT NULL
      AND s.school_id IS NOT NULL
    ON CONFLICT (source_contact_id, source_school_id)
    WHERE source_contact_id IS NOT NULL AND source_school_id IS NOT NULL
    DO UPDATE SET
        contact_id        = EXCLUDED.contact_id,
        school_id         = EXCLUDED.school_id,
        geography_id      = EXCLUDED.geography_id,
        date_joined_cama  = EXCLUDED.date_joined_cama,
        date_joined_id    = EXCLUDED.date_joined_id,
        partner_school    = EXCLUDED.partner_school,
        lin_change_type   = 'UPDATE',
        lin_load_batch_id = EXCLUDED.lin_load_batch_id,
        lin_source_system = EXCLUDED.lin_source_system,
        lin_source_file   = EXCLUDED.lin_source_file;

    -- CAMA members without a school association
    INSERT INTO rep_warehouse.fact_cama_membership
        (source_contact_id, contact_id, source_school_id, school_id, geography_id,
         date_joined_cama, date_joined_id, partner_school,
         lin_is_current, lin_change_type, lin_source_system, lin_source_file,
         lin_load_batch_id, lin_inserted_at, lin_source_row_number)
    SELECT
        s.contact_id, dct.id,
        NULL, NULL,
        dg_country.id,
        s.date_joined_cama, dd.id,
        s.partner_school,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        NOW(),
        s.row_id
    FROM rep_staging.cama_members s
    LEFT JOIN rep_warehouse.dim_contact    dct        ON dct.source_contact_id = s.contact_id AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date       dd         ON dd.id = TO_CHAR(s.date_joined_cama::timestamp, 'YYYYMMDD')::integer
    LEFT JOIN rep_warehouse.dim_geography  dg_country ON dg_country.country = s.country
        AND dg_country.province IS NULL AND dg_country.district IS NULL AND dg_country.scd_is_current = true
    WHERE s.contact_id IS NOT NULL
      AND s.school_id IS NULL
    ON CONFLICT (source_contact_id)
    WHERE source_contact_id IS NOT NULL AND source_school_id IS NULL
    DO UPDATE SET
        contact_id        = EXCLUDED.contact_id,
        geography_id      = EXCLUDED.geography_id,
        date_joined_cama  = EXCLUDED.date_joined_cama,
        date_joined_id    = EXCLUDED.date_joined_id,
        partner_school    = EXCLUDED.partner_school,
        lin_change_type   = 'UPDATE',
        lin_load_batch_id = EXCLUDED.lin_load_batch_id,
        lin_source_system = EXCLUDED.lin_source_system,
        lin_source_file   = EXCLUDED.lin_source_file;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.etl_load_fact_cama_membership() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_warehouse.etl_load_fact_cama_membership() TO service_role;

REVOKE EXECUTE ON FUNCTION rep_warehouse.etl_stage_cama_members() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_warehouse.etl_stage_cama_members() TO service_role;


-- ===== 20260623105727_fix_guide_geography_fallback_chain.sql =====
-- Fix Guide geography resolution. Confirmed priority order (CAMFED): Guide Role's own
-- District__c -> Guide Role's School -> Contact's District/Country of Residence.
--
-- Two bugs fixed:
--   1. rep_staging.contacts.district_id is a raw Salesforce lookup ID (District__c), never
--      resolved to a district name. dim_contact.district_of_residence stored that raw ID, so
--      etl_load_fact_guide_assignment()'s fallback join against dim_geography.district (which
--      holds names) never matched -- the Contact-residence fallback was always NULL.
--   2. rep_staging.guides.district_id (the Guide Role's own District__c) was never resolved to
--      a name at all, and was never used in geography resolution -- only the School was used.
--
-- dim_geography is keyed by (country, district) names, so both IDs are resolved via
-- rep_raw.districts before joining.

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_guides()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.guides;
    CREATE TABLE rep_staging.guides AS
    SELECT
        g.row_id,
        g.salesforce_id,
        g.contact_id,
        g.school_id,
        g.district_id,
        rd.district_name AS guide_district_name,
        rd.country_name   AS guide_country_name,
        g.contact_record_type,
        g.guide_type,
        g.guide_status,
        g.guide_specialty,
        g.guide_dropout_reason,
        g.date_joined_guide_programme::timestamp    AS date_joined_guide_programme,
        g.date_completed_guide_programme::timestamp AS date_left_guide_programme,
        (g.trained_in_climate_education = 'true')   AS trained_in_climate_education,
        g.donor_id
    FROM rep_raw.guides g
    LEFT JOIN rep_raw.schools rs   ON rs.salesforce_id = g.school_id
    LEFT JOIN rep_raw.districts rd ON rd.salesforce_id = g.district_id
    WHERE g.contact_id IS NOT NULL
      AND g.guide_type IN ('Learner Guide', 'Learner Mentor', 'Transition Guide', 'Agriculture Guide', 'Business Guide')
      AND g.date_joined_guide_programme::date >= '2013-01-01'
      AND coalesce(g.contact_record_type, '') != 'Archive Contact'
      AND coalesce(g.contact_npsp_deceased, 'false') = 'false'
      AND NOT rep_warehouse.country_is_excluded(COALESCE(rs.country, rd.country_name));
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_contacts()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.contacts;
    CREATE TABLE rep_staging.contacts AS
    SELECT
        c.salesforce_id,
        c.record_type_id,
        c.gender,
        c.country_id,
        c.country_name,
        c.district_id,
        rd.district_name AS district_of_residence_name,
        rd.country_name   AS district_of_residence_country,
        c.wg_difficulty_overall,
        (c.lg_social_support_recipient = 'true') AS lg_social_support_recipient,
        (c.active_on_bursary = 'true')           AS active_on_bursary,
        c.date_joined_cama,
        c.school_id,
        c.orphan_status,
        c.donor_activity_id,
        c.donor_code_id,
        c.project_code_id
    FROM rep_raw.contacts c
    LEFT JOIN rep_raw.districts rd ON rd.salesforce_id = c.district_id
    WHERE c.salesforce_id IS NOT NULL
      AND NOT rep_warehouse.country_is_excluded(c.country_name)
      AND c.country_name IS NOT NULL
      AND c.country_name != ''
      AND coalesce(c.contact_deceased, 'false') = 'false'
      AND coalesce(c.npsp_deceased, 'false') = 'false';
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_dim_contact()
RETURNS void LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.dim_contact
        (source_contact_id, country, gender, wg_difficulty_overall,
         lg_social_support_recipient, active_on_bursary, orphan_status,
         district_of_residence,
         roc_donor_id, roc_project_code_id, roc_donor_activity_id,
         scd_effective_from, scd_is_current, scd_version,
         lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT
        i.contact_id,
        i.country, i.gender, i.wg_difficulty_overall,
        i.lg_social_support_recipient, i.active_on_bursary, i.orphan_status,
        i.district,
        d3.id, d2.id, d4.id,
        CURRENT_DATE, true, 1,
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM (
        -- Priority ordering: contacts > academic_record > guides > cama_members > grant_recipients.
        -- DISTINCT ON keeps the first row per contact_id (lowest priority number).
        SELECT DISTINCT ON (contact_id)
            contact_id, country, gender, wg_difficulty_overall,
            lg_social_support_recipient, active_on_bursary, orphan_status,
            district, donor_code_id, project_code_id, donor_activity_id
        FROM (
            SELECT 1                              AS priority,
                salesforce_id                     AS contact_id,
                COALESCE(district_of_residence_country, country_name) AS country,
                gender,
                wg_difficulty_overall,
                lg_social_support_recipient,
                active_on_bursary,
                orphan_status,
                district_of_residence_name        AS district,
                donor_code_id,
                project_code_id,
                donor_activity_id
            FROM rep_staging.contacts
            WHERE salesforce_id IS NOT NULL
            UNION ALL
            SELECT 2,
                contact_id,
                country,
                NULL, NULL, NULL, NULL, NULL,
                district_id,
                donor_code_id,
                project_code_id,
                donor_activity_id
            FROM rep_staging.academic_record
            WHERE contact_id IS NOT NULL
            UNION ALL
            SELECT 3,
                contact_id,
                guide_country_name,
                NULL, NULL, NULL, NULL, NULL,
                guide_district_name,
                NULL, NULL, NULL
            FROM rep_staging.guides
            WHERE contact_id IS NOT NULL
            UNION ALL
            SELECT 4,
                contact_id,
                country,
                NULL, NULL, NULL, NULL, NULL,
                district,
                NULL, NULL, NULL
            FROM rep_staging.cama_members
            WHERE contact_id IS NOT NULL
            UNION ALL
            SELECT 5,
                contact_id,
                country,
                NULL, NULL, NULL, NULL, NULL,
                district,
                NULL, NULL, NULL
            FROM rep_staging.grant_recipients
            WHERE contact_id IS NOT NULL
        ) all_sources
        ORDER BY contact_id, priority
    ) i
    LEFT JOIN rep_warehouse.dim_roc_donor          d3 ON d3.source_roc_id = i.donor_code_id     AND d3.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_roc_project_code   d2 ON d2.source_roc_id = i.project_code_id   AND d2.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_roc_donor_activity d4 ON d4.source_roc_id = i.donor_activity_id AND d4.scd_is_current = true
    ON CONFLICT (source_contact_id) WHERE scd_is_current = true
    DO UPDATE SET
        country                     = EXCLUDED.country,
        gender                      = EXCLUDED.gender,
        wg_difficulty_overall       = EXCLUDED.wg_difficulty_overall,
        lg_social_support_recipient = EXCLUDED.lg_social_support_recipient,
        active_on_bursary           = EXCLUDED.active_on_bursary,
        orphan_status               = EXCLUDED.orphan_status,
        district_of_residence       = EXCLUDED.district_of_residence,
        roc_donor_id                = EXCLUDED.roc_donor_id,
        roc_project_code_id         = EXCLUDED.roc_project_code_id,
        roc_donor_activity_id       = EXCLUDED.roc_donor_activity_id,
        scd_effective_from          = EXCLUDED.scd_effective_from,
        lin_load_batch_id           = EXCLUDED.lin_load_batch_id,
        lin_source_system           = EXCLUDED.lin_source_system,
        lin_source_file             = EXCLUDED.lin_source_file;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_fact_guide_assignment()
RETURNS void LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.fact_guide_assignment
        (source_guide_id, source_contact_id, contact_id,
         source_school_id, school_id, geography_id,
         date_joined_guide_programme, date_joined_id,
         date_left_guide_programme,   date_left_id,
         guide_type, guide_status, guide_specialty, guide_dropout_reason,
         trained_in_climate_education, roc_donor_id,
         lin_is_current, lin_change_type, lin_source_system, lin_source_file,
         lin_load_batch_id, lin_inserted_at, lin_source_row_number)
    SELECT
        s.salesforce_id,
        s.contact_id, dct.id,
        s.school_id,  ds.id,
        COALESCE(dg_gd.id, ds.geography_id, dg_cd.id),
        s.date_joined_guide_programme, dd_joined.id,
        s.date_left_guide_programme,   dd_left.id,
        s.guide_type, s.guide_status, s.guide_specialty, s.guide_dropout_reason,
        s.trained_in_climate_education,
        d3.id,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        NOW(),
        s.row_id
    FROM rep_staging.guides s
    LEFT JOIN rep_warehouse.dim_contact   dct      ON dct.source_contact_id = s.contact_id AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_school    ds        ON ds.source_school_id   = s.school_id  AND ds.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date      dd_joined ON dd_joined.id = TO_CHAR(s.date_joined_guide_programme, 'YYYYMMDD')::integer
    LEFT JOIN rep_warehouse.dim_date      dd_left   ON dd_left.id   = TO_CHAR(s.date_left_guide_programme,   'YYYYMMDD')::integer
    LEFT JOIN rep_warehouse.dim_roc_donor d3         ON d3.source_roc_id = s.donor_id       AND d3.scd_is_current = true
    -- priority 1: Guide Role's own District__c
    LEFT JOIN rep_warehouse.dim_geography dg_gd     ON dg_gd.country  = s.guide_country_name
                                                    AND dg_gd.district = s.guide_district_name
                                                    AND dg_gd.scd_is_current = true
    -- priority 3 fallback: Contact's District/Country of Residence (only used when neither
    -- the Guide Role's own district nor its school resolved geography)
    LEFT JOIN rep_warehouse.dim_geography dg_cd     ON dg_cd.country  = dct.country
                                                    AND dg_cd.district = dct.district_of_residence
                                                    AND dg_cd.scd_is_current = true
    WHERE s.salesforce_id IS NOT NULL
    ON CONFLICT (source_guide_id)
    WHERE source_guide_id IS NOT NULL
    DO UPDATE SET
        contact_id                   = EXCLUDED.contact_id,
        school_id                    = EXCLUDED.school_id,
        geography_id                 = EXCLUDED.geography_id,
        date_left_guide_programme    = EXCLUDED.date_left_guide_programme,
        date_left_id                 = EXCLUDED.date_left_id,
        guide_status                 = EXCLUDED.guide_status,
        guide_specialty              = EXCLUDED.guide_specialty,
        guide_dropout_reason         = EXCLUDED.guide_dropout_reason,
        trained_in_climate_education = EXCLUDED.trained_in_climate_education,
        roc_donor_id                 = EXCLUDED.roc_donor_id,
        lin_change_type              = 'UPDATE',
        lin_load_batch_id            = EXCLUDED.lin_load_batch_id,
        lin_source_system            = EXCLUDED.lin_source_system,
        lin_source_file              = EXCLUDED.lin_source_file;
END;
$$;


-- ===== 20260623132435_add_guide_contact_deceased_filter.sql =====
-- etl_stage_guides() only excluded guides whose Contact has npsp__Deceased__c = true,
-- never Contact_Deceased__c -- the latter wasn't even ingested for guides (only for
-- contacts). A guide whose linked Contact has Contact_Deceased__c = true but
-- npsp__Deceased__c = false therefore still passed staging, even though the same
-- Contact is excluded from rep_staging.contacts (which checks both flags). Add the
-- missing column and align the guide filter with the contacts filter.

ALTER TABLE rep_raw.guides ADD COLUMN contact_deceased TEXT;  -- Contact__r.Contact_Deceased__c

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_guides()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.guides;
    CREATE TABLE rep_staging.guides AS
    SELECT
        g.row_id,
        g.salesforce_id,
        g.contact_id,
        g.school_id,
        g.district_id,
        rd.district_name AS guide_district_name,
        rd.country_name   AS guide_country_name,
        g.contact_record_type,
        g.guide_type,
        g.guide_status,
        g.guide_specialty,
        g.guide_dropout_reason,
        g.date_joined_guide_programme::timestamp    AS date_joined_guide_programme,
        g.date_completed_guide_programme::timestamp AS date_left_guide_programme,
        (g.trained_in_climate_education = 'true')   AS trained_in_climate_education,
        g.donor_id
    FROM rep_raw.guides g
    LEFT JOIN rep_raw.schools rs   ON rs.salesforce_id = g.school_id
    LEFT JOIN rep_raw.districts rd ON rd.salesforce_id = g.district_id
    WHERE g.contact_id IS NOT NULL
      AND g.guide_type IN ('Learner Guide', 'Learner Mentor', 'Transition Guide', 'Agriculture Guide', 'Business Guide')
      AND g.date_joined_guide_programme::date >= '2013-01-01'
      AND coalesce(g.contact_record_type, '') != 'Archive Contact'
      AND coalesce(g.contact_npsp_deceased, 'false') = 'false'
      AND coalesce(g.contact_deceased, 'false') = 'false'
      AND NOT rep_warehouse.country_is_excluded(COALESCE(rs.country, rd.country_name));
END;
$$;


-- ===== 20260627165748_milestone_upload.sql =====
-- Migration: milestone_upload
-- Creates the milestones ETL pipeline:
--   rep_raw.milestones (landing)
--   rep_raw.milestone_upload_log (audit)
--   rep_warehouse.fact_kpi_milestone (warehouse fact)
--   rep_warehouse.view_kpi_milestones (pre-joined view)
--   rep_warehouse.milestone_upload() (ETL + validation function)

-- ── rep_raw landing table ─────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS rep_raw.milestones (
  id              BIGSERIAL PRIMARY KEY,
  batch_id        TEXT      NOT NULL,
  row_id          INTEGER,
  kpi_no          TEXT,
  indicator       TEXT,
  disaggregation1 TEXT,
  disaggregation2 TEXT,
  country         TEXT,
  year            TEXT,
  value           TEXT,
  value_type      TEXT
);

CREATE INDEX IF NOT EXISTS milestones_batch_id_idx ON rep_raw.milestones (batch_id);

-- ── rep_raw audit log ─────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS rep_raw.milestone_upload_log (
  id                 BIGSERIAL    PRIMARY KEY,
  batch_id           TEXT         NOT NULL,
  source_file        TEXT,
  uploaded_by        TEXT,
  rows_loaded        INTEGER,
  status             TEXT,
  error_msg          TEXT,
  inserted_at        TIMESTAMPTZ  NOT NULL DEFAULT NOW()
);

-- ── rep_warehouse fact table ──────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS rep_warehouse.fact_kpi_milestone (
  id                       BIGSERIAL    PRIMARY KEY,
  kpi_id                   INTEGER      REFERENCES rep_warehouse.dim_kpi(id),
  geography_id             INTEGER      REFERENCES rep_warehouse.dim_geography(id),
  year                     SMALLINT,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  value                    NUMERIC,
  value_type               TEXT,
  lin_source_system        TEXT,
  lin_source_file          TEXT,
  lin_load_batch_id        TEXT,
  lin_inserted_at          TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
  lin_source_row_number    INTEGER
);

CREATE UNIQUE INDEX IF NOT EXISTS fact_kpi_milestone_key
  ON rep_warehouse.fact_kpi_milestone (
    kpi_id,
    COALESCE(geography_id, -1),
    year,
    COALESCE(disaggregation_level_one, ''),
    COALESCE(disaggregation_level_two, '')
  );

CREATE INDEX IF NOT EXISTS fact_kpi_milestone_kpi_id_idx
  ON rep_warehouse.fact_kpi_milestone (kpi_id);

CREATE INDEX IF NOT EXISTS fact_kpi_milestone_geography_id_idx
  ON rep_warehouse.fact_kpi_milestone (geography_id);

-- ── rep_warehouse view ────────────────────────────────────────────────────────

CREATE OR REPLACE VIEW rep_warehouse.view_kpi_milestones AS
SELECT
  m.id,
  k.source_kpi_id            AS kpi_no,
  k.kpi_group,
  k.indicator,
  g.country             AS country,
  m.year,
  m.disaggregation_level_one,
  m.disaggregation_level_two,
  m.value,
  m.value_type,
  m.lin_load_batch_id,
  m.lin_inserted_at
FROM rep_warehouse.fact_kpi_milestone m
JOIN rep_warehouse.dim_kpi       k ON k.id = m.kpi_id       AND k.scd_is_current = true
JOIN rep_warehouse.dim_geography g ON g.id = m.geography_id AND g.scd_is_current = true;

-- ── ETL + validation function ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_warehouse.milestone_upload(
  p_batch_id    TEXT,
  p_source_file TEXT,
  p_uploaded_by TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, rep_raw, pg_temp
AS $$
DECLARE
  v_row_count      INTEGER;
  v_unmatched_kpis TEXT[];
  v_unmatched_geos TEXT[];
  v_rows_loaded    INTEGER;
BEGIN
  -- 1. Ensure rows exist for this batch
  SELECT COUNT(*) INTO v_row_count
  FROM rep_raw.milestones
  WHERE batch_id = p_batch_id;

  IF v_row_count = 0 THEN
    INSERT INTO rep_raw.milestone_upload_log
      (batch_id, source_file, uploaded_by, rows_loaded, status, error_msg)
    VALUES (p_batch_id, p_source_file, p_uploaded_by, 0, 'FAILED', 'No rows found for batch_id');
    RETURN jsonb_build_object('status', 'FAILED', 'error', 'No rows found for batch_id');
  END IF;

  -- 2. Validate KPI Nos against dim_kpi (hard error — no partial loads)
  SELECT ARRAY_AGG(DISTINCT TRIM(kpi_no) ORDER BY TRIM(kpi_no))
  INTO v_unmatched_kpis
  FROM rep_raw.milestones m
  WHERE m.batch_id = p_batch_id
    AND TRIM(COALESCE(m.kpi_no, '')) <> ''
    AND NOT EXISTS (
      SELECT 1 FROM rep_warehouse.dim_kpi k
      WHERE k.source_kpi_id = TRIM(m.kpi_no)
        AND k.scd_is_current = true
    );

  IF v_unmatched_kpis IS NOT NULL AND ARRAY_LENGTH(v_unmatched_kpis, 1) > 0 THEN
    INSERT INTO rep_raw.milestone_upload_log
      (batch_id, source_file, uploaded_by, rows_loaded, status, error_msg)
    VALUES (p_batch_id, p_source_file, p_uploaded_by, 0, 'FAILED',
            'Unmatched KPI Nos: ' || ARRAY_TO_STRING(v_unmatched_kpis, ', '));
    RETURN jsonb_build_object(
      'status',            'FAILED',
      'error',             'Unmatched KPI Nos — upload rejected',
      'unmatched_kpi_nos', TO_JSONB(v_unmatched_kpis)
    );
  END IF;

  -- 3. Validate countries against dim_geography (hard error — no partial loads)
  SELECT ARRAY_AGG(DISTINCT TRIM(country) ORDER BY TRIM(country))
  INTO v_unmatched_geos
  FROM rep_raw.milestones m
  WHERE m.batch_id = p_batch_id
    AND TRIM(COALESCE(m.country, '')) <> ''
    AND NOT EXISTS (
      SELECT 1 FROM rep_warehouse.dim_geography g
      WHERE g.country      = TRIM(m.country)
        AND g.province     IS NULL
        AND g.district     IS NULL
        AND g.scd_is_current = true
    );

  IF v_unmatched_geos IS NOT NULL AND ARRAY_LENGTH(v_unmatched_geos, 1) > 0 THEN
    INSERT INTO rep_raw.milestone_upload_log
      (batch_id, source_file, uploaded_by, rows_loaded, status, error_msg)
    VALUES (p_batch_id, p_source_file, p_uploaded_by, 0, 'FAILED',
            'Unmatched countries: ' || ARRAY_TO_STRING(v_unmatched_geos, ', '));
    RETURN jsonb_build_object(
      'status',              'FAILED',
      'error',               'Unmatched countries — upload rejected',
      'unmatched_countries', TO_JSONB(v_unmatched_geos)
    );
  END IF;

  -- 4. All validations passed — full replace
  TRUNCATE rep_warehouse.fact_kpi_milestone;

  INSERT INTO rep_warehouse.fact_kpi_milestone (
    kpi_id,
    geography_id,
    year,
    disaggregation_level_one,
    disaggregation_level_two,
    value,
    value_type,
    lin_source_system,
    lin_source_file,
    lin_load_batch_id,
    lin_source_row_number
  )
  SELECT
    k.id,
    g.id,
    TRIM(m.year)::SMALLINT,
    NULLIF(TRIM(COALESCE(m.disaggregation1, '')), ''),
    NULLIF(TRIM(COALESCE(m.disaggregation2, '')), ''),
    REPLACE(TRIM(m.value), ' ', '')::NUMERIC,
    NULLIF(TRIM(COALESCE(m.value_type, '')), ''),
    'Milestones',
    p_source_file,
    p_batch_id,
    m.row_id
  FROM rep_raw.milestones m
  JOIN rep_warehouse.dim_kpi       k ON k.source_kpi_id = TRIM(m.kpi_no)  AND k.scd_is_current = true
  JOIN rep_warehouse.dim_geography g
    ON g.country      = TRIM(m.country)
   AND g.province     IS NULL
   AND g.district     IS NULL
   AND g.scd_is_current = true
  WHERE m.batch_id = p_batch_id
    AND TRIM(COALESCE(m.kpi_no,  '')) <> ''
    AND TRIM(COALESCE(m.country, '')) <> ''
    AND TRIM(COALESCE(m.value,   '')) <> '';

  GET DIAGNOSTICS v_rows_loaded = ROW_COUNT;

  -- 5. Log and return
  INSERT INTO rep_raw.milestone_upload_log
    (batch_id, source_file, uploaded_by, rows_loaded, status)
  VALUES (p_batch_id, p_source_file, p_uploaded_by, v_rows_loaded, 'OK');

  RETURN jsonb_build_object('status', 'OK', 'rows_loaded', v_rows_loaded);

EXCEPTION WHEN OTHERS THEN
  INSERT INTO rep_raw.milestone_upload_log
    (batch_id, source_file, uploaded_by, rows_loaded, status, error_msg)
  VALUES (p_batch_id, p_source_file, p_uploaded_by, 0, 'FAILED', SQLERRM);
  RETURN jsonb_build_object('status', 'FAILED', 'error', SQLERRM);
END;
$$;

REVOKE ALL ON FUNCTION rep_warehouse.milestone_upload(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_warehouse.milestone_upload(TEXT, TEXT, TEXT) TO service_role;

-- ── rep_portal API: upload log ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.get_milestone_upload_log()
RETURNS TABLE (
  batch_id    TEXT,
  source_file TEXT,
  uploaded_by TEXT,
  rows_loaded INTEGER,
  status      TEXT,
  error_msg   TEXT,
  inserted_at TIMESTAMPTZ
)
LANGUAGE sql
SECURITY DEFINER SET search_path = rep_portal, rep_raw, public
AS $$
  SELECT batch_id, source_file, uploaded_by, rows_loaded, status, error_msg, inserted_at
  FROM rep_raw.milestone_upload_log
  ORDER BY inserted_at DESC
  LIMIT 100;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_milestone_upload_log() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_milestone_upload_log() TO authenticated;


-- ===== 20260627172212_milestone_upload_fix_geo_join.sql =====
-- Fix: milestone_upload geography join was matching all rows (country + province + district)
-- instead of country-level rows only. Add province IS NULL AND district IS NULL filter
-- to both the validation check and the INSERT, matching the pattern used by kpi_upload_all.

CREATE OR REPLACE FUNCTION rep_warehouse.milestone_upload(
  p_batch_id    TEXT,
  p_source_file TEXT,
  p_uploaded_by TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, rep_raw, pg_temp
AS $$
DECLARE
  v_row_count      INTEGER;
  v_unmatched_kpis TEXT[];
  v_unmatched_geos TEXT[];
  v_rows_loaded    INTEGER;
BEGIN
  -- 1. Ensure rows exist for this batch
  SELECT COUNT(*) INTO v_row_count
  FROM rep_raw.milestones
  WHERE batch_id = p_batch_id;

  IF v_row_count = 0 THEN
    INSERT INTO rep_raw.milestone_upload_log
      (batch_id, source_file, uploaded_by, rows_loaded, status, error_msg)
    VALUES (p_batch_id, p_source_file, p_uploaded_by, 0, 'FAILED', 'No rows found for batch_id');
    RETURN jsonb_build_object('status', 'FAILED', 'error', 'No rows found for batch_id');
  END IF;

  -- 2. Validate KPI Nos against dim_kpi (hard error — no partial loads)
  SELECT ARRAY_AGG(DISTINCT TRIM(kpi_no) ORDER BY TRIM(kpi_no))
  INTO v_unmatched_kpis
  FROM rep_raw.milestones m
  WHERE m.batch_id = p_batch_id
    AND TRIM(COALESCE(m.kpi_no, '')) <> ''
    AND NOT EXISTS (
      SELECT 1 FROM rep_warehouse.dim_kpi k
      WHERE k.source_kpi_id = TRIM(m.kpi_no)
        AND k.scd_is_current = true
    );

  IF v_unmatched_kpis IS NOT NULL AND ARRAY_LENGTH(v_unmatched_kpis, 1) > 0 THEN
    INSERT INTO rep_raw.milestone_upload_log
      (batch_id, source_file, uploaded_by, rows_loaded, status, error_msg)
    VALUES (p_batch_id, p_source_file, p_uploaded_by, 0, 'FAILED',
            'Unmatched KPI Nos: ' || ARRAY_TO_STRING(v_unmatched_kpis, ', '));
    RETURN jsonb_build_object(
      'status',            'FAILED',
      'error',             'Unmatched KPI Nos — upload rejected',
      'unmatched_kpi_nos', TO_JSONB(v_unmatched_kpis)
    );
  END IF;

  -- 3. Validate countries against dim_geography country-level rows only
  SELECT ARRAY_AGG(DISTINCT TRIM(country) ORDER BY TRIM(country))
  INTO v_unmatched_geos
  FROM rep_raw.milestones m
  WHERE m.batch_id = p_batch_id
    AND TRIM(COALESCE(m.country, '')) <> ''
    AND NOT EXISTS (
      SELECT 1 FROM rep_warehouse.dim_geography g
      WHERE g.country     = TRIM(m.country)
        AND g.province    IS NULL
        AND g.district    IS NULL
        AND g.scd_is_current = true
    );

  IF v_unmatched_geos IS NOT NULL AND ARRAY_LENGTH(v_unmatched_geos, 1) > 0 THEN
    INSERT INTO rep_raw.milestone_upload_log
      (batch_id, source_file, uploaded_by, rows_loaded, status, error_msg)
    VALUES (p_batch_id, p_source_file, p_uploaded_by, 0, 'FAILED',
            'Unmatched countries: ' || ARRAY_TO_STRING(v_unmatched_geos, ', '));
    RETURN jsonb_build_object(
      'status',              'FAILED',
      'error',               'Unmatched countries — upload rejected',
      'unmatched_countries', TO_JSONB(v_unmatched_geos)
    );
  END IF;

  -- 4. All validations passed — full replace
  TRUNCATE rep_warehouse.fact_kpi_milestone;

  INSERT INTO rep_warehouse.fact_kpi_milestone (
    kpi_id,
    geography_id,
    year,
    disaggregation_level_one,
    disaggregation_level_two,
    value,
    value_type,
    lin_source_system,
    lin_source_file,
    lin_load_batch_id,
    lin_source_row_number
  )
  SELECT
    k.id,
    g.id,
    TRIM(m.year)::SMALLINT,
    NULLIF(TRIM(COALESCE(m.disaggregation1, '')), ''),
    NULLIF(TRIM(COALESCE(m.disaggregation2, '')), ''),
    REPLACE(TRIM(m.value), ' ', '')::NUMERIC,
    NULLIF(TRIM(COALESCE(m.value_type, '')), ''),
    'Milestones',
    p_source_file,
    p_batch_id,
    m.row_id
  FROM rep_raw.milestones m
  JOIN rep_warehouse.dim_kpi k
    ON k.source_kpi_id = TRIM(m.kpi_no)
   AND k.scd_is_current = true
  JOIN rep_warehouse.dim_geography g
    ON g.country        = TRIM(m.country)
   AND g.province       IS NULL
   AND g.district       IS NULL
   AND g.scd_is_current = true
  WHERE m.batch_id = p_batch_id
    AND TRIM(COALESCE(m.kpi_no,  '')) <> ''
    AND TRIM(COALESCE(m.country, '')) <> ''
    AND TRIM(COALESCE(m.value,   '')) <> '';

  GET DIAGNOSTICS v_rows_loaded = ROW_COUNT;

  -- 5. Log and return
  INSERT INTO rep_raw.milestone_upload_log
    (batch_id, source_file, uploaded_by, rows_loaded, status)
  VALUES (p_batch_id, p_source_file, p_uploaded_by, v_rows_loaded, 'OK');

  RETURN jsonb_build_object('status', 'OK', 'rows_loaded', v_rows_loaded);

EXCEPTION WHEN OTHERS THEN
  INSERT INTO rep_raw.milestone_upload_log
    (batch_id, source_file, uploaded_by, rows_loaded, status, error_msg)
  VALUES (p_batch_id, p_source_file, p_uploaded_by, 0, 'FAILED', SQLERRM);
  RETURN jsonb_build_object('status', 'FAILED', 'error', SQLERRM);
END;
$$;

REVOKE ALL ON FUNCTION rep_warehouse.milestone_upload(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_warehouse.milestone_upload(TEXT, TEXT, TEXT) TO service_role;


-- ===== 20260707170002_join_loans_to_contact.sql =====
-- Join fact_loans to dim_contact.
--
-- fact_loans.contact_record_id (Salesforce Contact_Record_ID__c) is an autonumber
-- display value ("CON-83880"), not a Salesforce record ID, so it can never match
-- dim_contact.source_contact_id (18-char SF ID). The actual Contact lookup is
-- Client_ID__c, already fetched by ingest-loan-recipients as `client_id` but
-- dropped in staging. This mirrors the existing, working fact_grants pattern
-- (Person__c -> person_id -> contact_id).

ALTER TABLE rep_warehouse.fact_loans
    ADD COLUMN source_contact_id TEXT,
    ADD COLUMN contact_id        INTEGER REFERENCES rep_warehouse.dim_contact(id);

CREATE INDEX idx_fact_lo_contact_id ON rep_warehouse.fact_loans (contact_id);

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_loan_recipients()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.loan_recipients;
    CREATE TABLE rep_staging.loan_recipients AS
    SELECT
        row_id,
        salesforce_id                 AS loan_id,
        client_id                     AS contact_id,
        contact_record_type,
        district,
        country,
        loan_type_id                  AS loan_type,
        record_type_id                AS record_type,
        status,
        loan_status,
        disbursal_date,
        loan_value,
        currency_iso_code,
        contact_record_id,
        donor_code_id
    FROM rep_raw.loan_recipients
    WHERE salesforce_id IS NOT NULL;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_fact_loans()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.fact_loans
        (source_loan_id, source_contact_id, contact_id, geography_id, loan_type, status, loan_status,
         disbursal_date, disbursal_date_id,
         loan_value, currency_iso_code, contact_record_id, roc_donor_id,
         lin_is_current, lin_change_type, lin_source_system, lin_source_file,
         lin_load_batch_id, lin_business_hash, lin_source_row_number)
    SELECT
        s.loan_id,
        s.contact_id, dct.id,
        COALESCE(
            (SELECT id FROM rep_warehouse.dim_geography
             WHERE country = s.country AND district = s.district AND scd_is_current = true LIMIT 1),
            (SELECT id FROM rep_warehouse.dim_geography
             WHERE country = s.country AND province IS NULL AND district IS NULL LIMIT 1)
        ),
        s.loan_type, s.status, s.loan_status,
        s.disbursal_date::timestamp, dd.id,
        s.loan_value::numeric,
        s.currency_iso_code,
        s.contact_record_id,
        d3.id,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        MD5(COALESCE(s.loan_id, '')),
        s.row_id
    FROM rep_staging.loan_recipients s
    LEFT JOIN rep_warehouse.dim_contact  dct ON dct.source_contact_id = s.contact_id AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = TO_CHAR(s.disbursal_date::timestamp, 'YYYYMMDD')::integer
    LEFT JOIN rep_warehouse.dim_roc_donor d3 ON d3.source_roc_id = s.donor_code_id AND d3.scd_is_current = true
    ON CONFLICT (source_loan_id) DO NOTHING;
END;
$$;

-- CREATE OR REPLACE VIEW requires pre-existing columns to keep their name and
-- position, so the new contact columns are appended at the end.
CREATE OR REPLACE VIEW rep_warehouse.view_loans
WITH (security_invoker = on) AS
SELECT
    f.id,
    f.source_loan_id,
    f.loan_type,
    f.status                        AS loan_status_raw,
    f.loan_status,
    f.loan_value,
    f.currency_iso_code,
    f.contact_record_id,
    f.disbursal_date,
    dd.year                         AS disbursal_year,
    dd.month                        AS disbursal_month,
    dd.month_name                   AS disbursal_month_name,
    dd.quarter                      AS disbursal_quarter,
    d3.name                         AS donor_name,
    d3.reporting_code               AS donor_code,
    g.district,
    g.province,
    g.country,
    f.source_contact_id,
    ct.gender,
    ct.wg_difficulty_overall
FROM rep_warehouse.fact_loans f
LEFT JOIN rep_warehouse.dim_contact  ct ON ct.id = f.contact_id
LEFT JOIN rep_warehouse.dim_geography g  ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = f.disbursal_date_id
LEFT JOIN rep_warehouse.dim_roc_donor d3 ON d3.id = f.roc_donor_id;


-- ===== 20260707175142_whatsapp_district_report_metrics.sql =====
-- Phase 1 needs-assessment metrics for the WhatsApp bot's district reports.
--
-- Adds/changes:
--   1. district_report_children — drops latest-year auto-detection in favour of an
--      optional p_year param (NULL = all time); drops school_count/top_schools
--      (moved to the new Schools report); adds total_boys, bursary_girls/boys,
--      tertiary_girls.
--   2. district_report_schools (NEW) — active partner schools count + the
--      top-5-schools list (moved from district_report_children, now ranked by
--      total children supported instead of girls-only).
--   3. district_report_guides_by_type (NEW) — active guide count grouped by
--      guide_type, for the People report.
--   4. district_report_finance — drops latest-year auto-detection in favour of
--      an optional p_year param; adds grants/loans girls/boys counts.
--
-- The old 1-arg district_report_children(TEXT) / district_report_finance(TEXT)
-- overloads are dropped explicitly — CREATE OR REPLACE would otherwise create a
-- second overload alongside them rather than replacing them, since the argument
-- list is changing.

-- ── 1. district_report_children ───────────────────────────────────────────────

DROP FUNCTION IF EXISTS rep_warehouse.district_report_children(TEXT);
DROP FUNCTION IF EXISTS rep_portal.district_report_children(TEXT);

CREATE FUNCTION rep_warehouse.district_report_children(p_district TEXT, p_year INTEGER DEFAULT NULL)
RETURNS TABLE (
  total_girls    BIGINT,
  total_boys     BIGINT,
  bursary_girls  BIGINT,
  bursary_boys   BIGINT,
  tertiary_girls BIGINT
) LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT
    (SELECT COUNT(*) FROM rep_warehouse.view_children_supported
       WHERE district = p_district AND gender = 'Female'
         AND (p_year IS NULL OR year = p_year))::BIGINT,
    (SELECT COUNT(*) FROM rep_warehouse.view_children_supported
       WHERE district = p_district AND gender = 'Male'
         AND (p_year IS NULL OR year = p_year))::BIGINT,
    (SELECT COUNT(*) FROM rep_warehouse.view_children_supported
       WHERE district = p_district AND contact_record_type = 'Bursary Pupil' AND gender = 'Female'
         AND (p_year IS NULL OR year = p_year))::BIGINT,
    (SELECT COUNT(*) FROM rep_warehouse.view_children_supported
       WHERE district = p_district AND contact_record_type = 'Bursary Pupil' AND gender = 'Male'
         AND (p_year IS NULL OR year = p_year))::BIGINT,
    (SELECT COUNT(*) FROM rep_warehouse.view_post_school_support
       WHERE district = p_district AND gender = 'Female'
         AND (p_year IS NULL OR year = p_year))::BIGINT;
$$;

GRANT EXECUTE ON FUNCTION rep_warehouse.district_report_children(TEXT, INTEGER) TO service_role;

CREATE FUNCTION rep_portal.district_report_children(p_district TEXT, p_year INTEGER DEFAULT NULL)
RETURNS TABLE (
  total_girls    BIGINT,
  total_boys     BIGINT,
  bursary_girls  BIGINT,
  bursary_boys   BIGINT,
  tertiary_girls BIGINT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
  SELECT * FROM rep_warehouse.district_report_children(p_district, p_year);
$$;

GRANT EXECUTE ON FUNCTION rep_portal.district_report_children(TEXT, INTEGER) TO service_role;

-- ── 2. district_report_schools (NEW) ──────────────────────────────────────────
-- Active partner schools count (dim_school.active_partner_school, current SCD
-- row only) + top-5 schools by total children supported (all time, all genders).

CREATE FUNCTION rep_warehouse.district_report_schools(p_district TEXT)
RETURNS TABLE (
  active_partner_schools BIGINT,
  top_schools            TEXT
) LANGUAGE sql SECURITY DEFINER STABLE AS $$
  WITH per_school AS (
    SELECT school_name, COUNT(*) AS n
    FROM rep_warehouse.view_children_supported
    WHERE district = p_district AND school_name IS NOT NULL
    GROUP BY school_name
  ),
  top AS (
    SELECT string_agg('• ' || school_name || ': ' || n::TEXT, E'\n' ORDER BY n DESC) AS top_schools
    FROM (SELECT school_name, n FROM per_school ORDER BY n DESC LIMIT 5) t
  )
  SELECT
    (SELECT COUNT(*)
       FROM rep_warehouse.dim_school s
       JOIN rep_warehouse.dim_geography g ON g.id = s.geography_id AND g.scd_is_current = true
       WHERE s.scd_is_current = true AND s.active_partner_school = true AND g.district = p_district)::BIGINT,
    top.top_schools
  FROM top;
$$;

GRANT EXECUTE ON FUNCTION rep_warehouse.district_report_schools(TEXT) TO service_role;

CREATE FUNCTION rep_portal.district_report_schools(p_district TEXT)
RETURNS TABLE (
  active_partner_schools BIGINT,
  top_schools            TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
  SELECT * FROM rep_warehouse.district_report_schools(p_district);
$$;

GRANT EXECUTE ON FUNCTION rep_portal.district_report_schools(TEXT) TO service_role;

-- ── 3. district_report_guides_by_type (NEW) ───────────────────────────────────

CREATE FUNCTION rep_warehouse.district_report_guides_by_type(p_district TEXT)
RETURNS TABLE (
  guide_type   TEXT,
  active_count BIGINT
) LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT guide_type, COUNT(*)::BIGINT AS active_count
  FROM rep_warehouse.view_guide_assignment
  WHERE district = p_district AND guide_status = 'Active'
  GROUP BY guide_type
  ORDER BY active_count DESC;
$$;

GRANT EXECUTE ON FUNCTION rep_warehouse.district_report_guides_by_type(TEXT) TO service_role;

CREATE FUNCTION rep_portal.district_report_guides_by_type(p_district TEXT)
RETURNS TABLE (
  guide_type   TEXT,
  active_count BIGINT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
  SELECT * FROM rep_warehouse.district_report_guides_by_type(p_district);
$$;

GRANT EXECUTE ON FUNCTION rep_portal.district_report_guides_by_type(TEXT) TO service_role;

-- ── 4. district_report_finance ────────────────────────────────────────────────

DROP FUNCTION IF EXISTS rep_warehouse.district_report_finance(TEXT);
DROP FUNCTION IF EXISTS rep_portal.district_report_finance(TEXT);

CREATE FUNCTION rep_warehouse.district_report_finance(p_district TEXT, p_year INTEGER DEFAULT NULL)
RETURNS TABLE (
  grants_count BIGINT,
  grants_total NUMERIC,
  grants_girls BIGINT,
  grants_boys  BIGINT,
  loans_count  BIGINT,
  loans_total  NUMERIC,
  loans_girls  BIGINT,
  loans_boys   BIGINT
) LANGUAGE sql SECURITY DEFINER STABLE AS $$
  SELECT
    (SELECT COUNT(*) FROM rep_warehouse.view_grants
       WHERE district = p_district AND (p_year IS NULL OR grant_year = p_year))::BIGINT,
    (SELECT COALESCE(SUM(amount_given), 0) FROM rep_warehouse.view_grants
       WHERE district = p_district AND (p_year IS NULL OR grant_year = p_year)),
    (SELECT COUNT(*) FROM rep_warehouse.view_grants
       WHERE district = p_district AND gender = 'Female' AND (p_year IS NULL OR grant_year = p_year))::BIGINT,
    (SELECT COUNT(*) FROM rep_warehouse.view_grants
       WHERE district = p_district AND gender = 'Male' AND (p_year IS NULL OR grant_year = p_year))::BIGINT,
    (SELECT COUNT(*) FROM rep_warehouse.view_loans
       WHERE district = p_district AND (p_year IS NULL OR disbursal_year = p_year))::BIGINT,
    (SELECT COALESCE(SUM(loan_value), 0) FROM rep_warehouse.view_loans
       WHERE district = p_district AND (p_year IS NULL OR disbursal_year = p_year)),
    (SELECT COUNT(*) FROM rep_warehouse.view_loans
       WHERE district = p_district AND gender = 'Female' AND (p_year IS NULL OR disbursal_year = p_year))::BIGINT,
    (SELECT COUNT(*) FROM rep_warehouse.view_loans
       WHERE district = p_district AND gender = 'Male' AND (p_year IS NULL OR disbursal_year = p_year))::BIGINT;
$$;

GRANT EXECUTE ON FUNCTION rep_warehouse.district_report_finance(TEXT, INTEGER) TO service_role;

CREATE FUNCTION rep_portal.district_report_finance(p_district TEXT, p_year INTEGER DEFAULT NULL)
RETURNS TABLE (
  grants_count BIGINT,
  grants_total NUMERIC,
  grants_girls BIGINT,
  grants_boys  BIGINT,
  loans_count  BIGINT,
  loans_total  NUMERIC,
  loans_girls  BIGINT,
  loans_boys   BIGINT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
  SELECT * FROM rep_warehouse.district_report_finance(p_district, p_year);
$$;

GRANT EXECUTE ON FUNCTION rep_portal.district_report_finance(TEXT, INTEGER) TO service_role;

-- ── 5. Permission: Schools report ──────────────────────────────────────────────

INSERT INTO rep_portal.permissions (key, label, category)
VALUES ('wa_report:schools', 'Schools', 'wa_report')
ON CONFLICT (key) DO NOTHING;


-- ===== 20260710102034_whatsapp_kpi_report.sql =====
-- WhatsApp bot: KPI report flow.
--
-- Adds:
--   1. dim_kpi.short_label — hand-curated <=24-char labels for WhatsApp list row
--      titles (row titles are capped at 24 chars; several indicator names are
--      50-95 chars). The final report message always uses the full `indicator`
--      text; short_label is only ever used for list row titles.
--   2. kpi_report_country / kpi_report_years / kpi_report_groups /
--      kpi_report_indicators / kpi_report_indicator_detail — the RPC chain
--      backing the bot's district -> year -> group -> indicator drill-down.
--      kpi_report_indicator_detail reads from view_observed_kpi (not
--      view_kpi_detail) to preserve raw text `value` for value_type = 'Text'
--      rows, which view_kpi_detail's numeric cast otherwise nulls out.
--   3. wa_report:kpis permission.

-- ── 1. dim_kpi.short_label ──────────────────────────────────────────────────

ALTER TABLE rep_warehouse.dim_kpi ADD COLUMN IF NOT EXISTS short_label TEXT;

UPDATE rep_warehouse.dim_kpi SET short_label = 'Supported exam pass rate'
  WHERE indicator = 'Supported girls'' exam pass rates (with benchmarks and trends reported where available)';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Promotion rate (all)'
  WHERE indicator = 'Promotion rate of supported students between all grades';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Girls supported by CAMA'
  WHERE indicator = 'Number of girls supported to go to school by CAMA';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Completion rate'
  WHERE indicator = 'Completion rate for supported students';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Number of Learner Guides'
  WHERE indicator = 'Number of Learner Guides';

UPDATE rep_warehouse.dim_kpi SET short_label = 'Jobs created (EDP)'
  WHERE indicator = 'Number of jobs created through the Enterprise Development Programme (including self-employment)';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Active Guides'
  WHERE indicator = 'Number of active Guides (Transition Guides, Agriculture Guides, Business Guides)';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Businesses supported'
  WHERE indicator = 'Number of businesses supported by the Enterprise Guides (BGs and AGs)';

UPDATE rep_warehouse.dim_kpi SET short_label = 'Schools w/ LG sessions'
  WHERE indicator = 'Number of schools with timetabled Learner Guide sessions and active Learner Guides';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Schools w/ policies'
  WHERE indicator = 'Number of schools with active structures and policies for delivery of strategies';

UPDATE rep_warehouse.dim_kpi SET short_label = 'Community Champions'
  WHERE indicator = 'Community Champions';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Completion rate (natl.)'
  WHERE indicator = 'Completion rates, national, disaggregated by gender';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Drop out rate (natl.)'
  WHERE indicator = 'Drop out rate, national, disaggregated by gender and reason';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Exam pass rate, national'
  WHERE indicator = 'Exam pass rate, national';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Exam pass rate (partner)'
  WHERE indicator = 'Exam pass rate, partner schools';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Exam pass rate (supp.)'
  WHERE indicator = 'Exam pass rate, supported students';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Promotion rate (natl.)'
  WHERE indicator = 'Promotion rates, national, disaggregated by gender';

UPDATE rep_warehouse.dim_kpi SET short_label = 'Govt monitoring (joint)'
  WHERE indicator = 'Joint CAMFED-Government monitoring initiatives active in each country';
UPDATE rep_warehouse.dim_kpi SET short_label = 'CAMA Philanthropy value'
  WHERE indicator = 'Estimated value of CAMA Philanthropy generated annually';

-- ── 2a. kpi_report_country ───────────────────────────────────────────────────
-- Resolves the country for a district, same join rep_portal.get_bot_districts uses.

CREATE FUNCTION rep_warehouse.kpi_report_country(p_district TEXT)
RETURNS TEXT
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT g.country
  FROM rep_warehouse.dim_geography g
  WHERE g.district = p_district AND g.scd_is_current = true
  LIMIT 1;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.kpi_report_country(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_warehouse.kpi_report_country(TEXT) TO service_role;

CREATE FUNCTION rep_portal.kpi_report_country(p_district TEXT)
RETURNS TEXT
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT rep_warehouse.kpi_report_country(p_district);
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_report_country(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_report_country(TEXT) TO service_role;

-- ── 2b. kpi_report_years ─────────────────────────────────────────────────────

CREATE FUNCTION rep_warehouse.kpi_report_years(p_country TEXT)
RETURNS TABLE (year INTEGER)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT DISTINCT year
  FROM rep_warehouse.view_kpi_detail
  WHERE country = p_country
  ORDER BY year DESC;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.kpi_report_years(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_warehouse.kpi_report_years(TEXT) TO service_role;

CREATE FUNCTION rep_portal.kpi_report_years(p_country TEXT)
RETURNS TABLE (year INTEGER)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT * FROM rep_warehouse.kpi_report_years(p_country);
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_report_years(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_report_years(TEXT) TO service_role;

-- ── 2c. kpi_report_groups ────────────────────────────────────────────────────

CREATE FUNCTION rep_warehouse.kpi_report_groups(p_country TEXT, p_year INTEGER)
RETURNS TABLE (kpi_group TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT DISTINCT kpi_group
  FROM rep_warehouse.view_kpi_detail
  WHERE country = p_country AND year = p_year
  ORDER BY kpi_group;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.kpi_report_groups(TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_warehouse.kpi_report_groups(TEXT, INTEGER) TO service_role;

CREATE FUNCTION rep_portal.kpi_report_groups(p_country TEXT, p_year INTEGER)
RETURNS TABLE (kpi_group TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT * FROM rep_warehouse.kpi_report_groups(p_country, p_year);
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_report_groups(TEXT, INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_report_groups(TEXT, INTEGER) TO service_role;

-- ── 2d. kpi_report_indicators ────────────────────────────────────────────────

CREATE FUNCTION rep_warehouse.kpi_report_indicators(p_country TEXT, p_year INTEGER, p_kpi_group TEXT)
RETURNS TABLE (indicator TEXT, short_label TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT DISTINCT d.indicator, COALESCE(k.short_label, d.indicator)
  FROM rep_warehouse.view_kpi_detail d
  LEFT JOIN rep_warehouse.dim_kpi k ON k.indicator = d.indicator AND k.scd_is_current = true
  WHERE d.country = p_country AND d.year = p_year AND d.kpi_group = p_kpi_group
  ORDER BY d.indicator;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.kpi_report_indicators(TEXT, INTEGER, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_warehouse.kpi_report_indicators(TEXT, INTEGER, TEXT) TO service_role;

CREATE FUNCTION rep_portal.kpi_report_indicators(p_country TEXT, p_year INTEGER, p_kpi_group TEXT)
RETURNS TABLE (indicator TEXT, short_label TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT * FROM rep_warehouse.kpi_report_indicators(p_country, p_year, p_kpi_group);
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_report_indicators(TEXT, INTEGER, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_report_indicators(TEXT, INTEGER, TEXT) TO service_role;

-- ── 2e. kpi_report_indicator_detail ──────────────────────────────────────────
-- Reads view_observed_kpi (pre-numeric-cast) to preserve raw text `value` for
-- value_type = 'Text' rows; view_kpi_detail's regex cast would null these out.

CREATE FUNCTION rep_warehouse.kpi_report_indicator_detail(p_country TEXT, p_year INTEGER, p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  value_type TEXT,
  value TEXT,
  definition TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT disaggregation_level_one, disaggregation_level_two, value_type, value, definition
  FROM rep_warehouse.view_observed_kpi
  WHERE row_scope = 'DETAIL'
    AND country = p_country AND year = p_year
    AND kpi_group = p_kpi_group AND indicator = p_indicator
    AND value IS NOT NULL
  ORDER BY disaggregation_level_one, disaggregation_level_two;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.kpi_report_indicator_detail(TEXT, INTEGER, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_warehouse.kpi_report_indicator_detail(TEXT, INTEGER, TEXT, TEXT) TO service_role;

CREATE FUNCTION rep_portal.kpi_report_indicator_detail(p_country TEXT, p_year INTEGER, p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  value_type TEXT,
  value TEXT,
  definition TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT * FROM rep_warehouse.kpi_report_indicator_detail(p_country, p_year, p_kpi_group, p_indicator);
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_report_indicator_detail(TEXT, INTEGER, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_report_indicator_detail(TEXT, INTEGER, TEXT, TEXT) TO service_role;

-- ── 3. Permission: KPIs report ───────────────────────────────────────────────

INSERT INTO rep_portal.permissions (key, label, category)
VALUES ('wa_report:kpis', 'KPIs', 'wa_report')
ON CONFLICT (key) DO NOTHING;


-- ===== 20260710141954_disable_dynamic_data_metrics.sql =====
-- Disable a set of Dynamic Data metrics globally (applied directly via SQL
-- editor on remote earlier; codifying here so local resets / version control
-- stay in sync).
--
-- refresh_dashboard_data_agg() only aggregates rows where enabled = true, so
-- disabling here stops future refreshes from re-populating these metrics.
-- Also delete any existing rows for these metrics from dashboard_data_agg so
-- the change takes effect immediately, without waiting for the next ETL run.

UPDATE rep_portal.metric_config
SET enabled = false
WHERE metric_name IN (
  'Children Supported — Step Up Fund',
  'Children Supported — Repeated Year',
  'Children Supported — Received Financial Support',
  'Guides — Trained in Climate Education',
  'CAMA Members — Partner School',
  'Post-School Support — Received Financial Support'
);

DELETE FROM rep_portal.dashboard_data_agg
WHERE metric IN (
  'Children Supported — Step Up Fund',
  'Children Supported — Repeated Year',
  'Children Supported — Received Financial Support',
  'Guides — Trained in Climate Education',
  'CAMA Members — Partner School',
  'Post-School Support — Received Financial Support'
);


-- ===== 20260710154248_fix_cumulative_kpi_dashboard_metrics.sql =====
-- Fix all five "Children Supported in School with Education Bursaries" Data
-- Dashboard variants (base/Annual year cards + Cumulative since 2020/2024/
-- all-time), which have returned no data since the June 22 dashboard_data_agg
-- refactor.
--
-- Root cause 1 (label drift, Cumulative only): the original logic filtered on
-- disaggregation_level_one = 'Cumulative (2020-2030)' / 'Cumulative (2024-2030)' /
-- 'Cumulative (all-time)', but the actual uploaded KPI data stores this column as
-- 'Cumulative since 2020' / 'Cumulative since 2024' / 'Cumulative all-time'
-- (confirmed against rep_warehouse.fact_observed_kpi). The filter never matched.
-- The base/Annual variants' labels ('Newly supported' / 'Annual') did not drift.
--
-- Root cause 2 (pipeline gap, all five variants): rep_portal.refresh_dashboard_
-- data_agg() was rewritten in 20260622000007 to rebuild dashboard_data_agg
-- entirely from rep_portal.metric_config, which only covers Salesforce
-- fact-based metrics. All five KPI-sourced variants of this metric (not just
-- the Cumulative ones) were dropped and never carried over.
--
-- Fix: restore the three cumulative metric blocks (unchanged shape — grouped by
-- country/year, sourced from rep_warehouse.view_observed_kpi, a KPI-sourced view
-- unrelated to Salesforce) with the corrected disaggregation_level_one text,
-- appended directly inside refresh_dashboard_data_agg() after the metric_config
-- loop. Each is wrapped in its own exception handler so a failure here can't
-- wipe the rest of the refresh.
--
-- Also filters on kpi_id = '1.1' instead of indicator ILIKE '%girls receiving
-- CAMF%' — kpi_id is dim_kpi's stable identifier, not free-text that can drift
-- across uploads the way disaggregation_level_one already had.
--
-- Note: 'Cumulative 2024-2030' still returns no rows after this fix — confirmed
-- via direct query that no fact_observed_kpi row exists under kpi_id = '1.1'
-- for disaggregation_level_one = 'Cumulative since 2024'. That's a genuine gap
-- in the uploaded KPI data (that period's upload never included this
-- indicator), not a filter/label bug — needs a corrected KPI upload, not a
-- code fix.

CREATE OR REPLACE FUNCTION rep_portal.refresh_dashboard_data_agg()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET statement_timeout = 0
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_metric      rep_portal.metric_config%ROWTYPE;
  v_sql         TEXT;
  v_filter      JSONB;
  v_field       TEXT;
  v_op          TEXT;
  v_val         TEXT;
  v_i           INT;
  v_rows        BIGINT;
BEGIN
  -- Build into a staging table first, then swap, so a mid-run failure
  -- doesn't leave the live table empty.
  DROP TABLE IF EXISTS rep_portal.dashboard_data_agg_new;
  CREATE TABLE rep_portal.dashboard_data_agg_new (LIKE rep_portal.dashboard_data_agg INCLUDING ALL);

  FOR v_metric IN
    SELECT * FROM rep_portal.metric_config
    WHERE enabled = true
    ORDER BY sort_order, metric_name
  LOOP
    BEGIN
      IF v_metric.geography_level = 'school' THEN
        v_sql := format(
          'INSERT INTO rep_portal.dashboard_data_agg_new (country, province, district, school, year, metric, value)
           SELECT country, province, district, school_name, %I, %L, ',
          v_metric.year_field, v_metric.metric_name
        );
      ELSE
        v_sql := format(
          'INSERT INTO rep_portal.dashboard_data_agg_new (country, province, district, school, year, metric, value)
           SELECT country, province, district, ''District Total'', %I, %L, ',
          v_metric.year_field, v_metric.metric_name
        );
      END IF;

      IF v_metric.value_agg = 'sum' THEN
        v_sql := v_sql || format('ROUND(SUM(COALESCE(%I::numeric, 0)))::int', v_metric.value_field);
      ELSE
        v_sql := v_sql || 'COUNT(*)::int';
      END IF;

      v_sql := v_sql || format(' FROM rep_warehouse.%I WHERE TRUE', v_metric.source_view);

      -- NULL guards
      v_sql := v_sql || format(' AND %I IS NOT NULL AND country IS NOT NULL', v_metric.year_field);
      IF v_metric.geography_level = 'school' THEN
        v_sql := v_sql || ' AND school_name IS NOT NULL';
      ELSE
        v_sql := v_sql || ' AND district IS NOT NULL';
      END IF;

      -- JSONB filters — iterate by index
      IF v_metric.filters IS NOT NULL AND jsonb_array_length(v_metric.filters) > 0 THEN
        FOR v_i IN 0 .. jsonb_array_length(v_metric.filters) - 1
        LOOP
          v_filter := v_metric.filters -> v_i;
          v_field  := v_filter->>'field';
          v_op     := v_filter->>'op';
          v_val    := v_filter->>'value';

          IF v_op = 'eq' THEN
            v_sql := v_sql || format(' AND %I = %L', v_field, v_val);
          ELSIF v_op = 'ilike' THEN
            v_sql := v_sql || format(' AND %I ILIKE %L', v_field, v_val);
          ELSIF v_op = 'bool_true' THEN
            v_sql := v_sql || format(' AND %I = true', v_field);
          ELSIF v_op = 'not_null' THEN
            v_sql := v_sql || format(' AND %I IS NOT NULL', v_field);
          END IF;
        END LOOP;
      END IF;

      -- GROUP BY
      IF v_metric.geography_level = 'school' THEN
        v_sql := v_sql || format(' GROUP BY country, province, district, school_name, %I', v_metric.year_field);
      ELSE
        v_sql := v_sql || format(' GROUP BY country, province, district, %I', v_metric.year_field);
      END IF;

      EXECUTE v_sql;
      GET DIAGNOSTICS v_rows = ROW_COUNT;

    EXCEPTION WHEN OTHERS THEN
      RAISE WARNING 'refresh_dashboard_data_agg: skipping metric "%" — % (SQL: %)',
        v_metric.metric_name, SQLERRM, v_sql;
    END;
  END LOOP;

  -- ── KPI-sourced metrics for "Children Supported in School with Education
  --    Bursaries" (not in metric_config — country-level only, grouped by
  --    country/year, same shape as before the June 22 refactor). Includes the
  --    base/Annual variants (used by the regular year-by-year cards, dropped
  --    by the same refactor as Cumulative — their disaggregation_level_one
  --    text ('Newly supported' / 'Annual') did not drift, unlike Cumulative's) ──

  BEGIN
    INSERT INTO rep_portal.dashboard_data_agg_new (country, province, district, school, year, metric, value)
    SELECT country, 'National', 'National', 'National', year,
           'Children Supported in School with Education Bursaries',
           ROUND(SUM(COALESCE(value::numeric, 0)))::int
    FROM rep_warehouse.view_observed_kpi
    WHERE disaggregation_level_one = 'Newly supported'
      AND disaggregation_level_two = 'Girls Total'
      AND kpi_id = '1.1'
      AND year IS NOT NULL AND country IS NOT NULL
    GROUP BY country, year;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'refresh_dashboard_data_agg: skipping Children Supported bursaries (base) — %', SQLERRM;
  END;

  BEGIN
    INSERT INTO rep_portal.dashboard_data_agg_new (country, province, district, school, year, metric, value)
    SELECT country, 'National', 'National', 'National', year,
           'Children Supported in School with Education Bursaries — Annual',
           ROUND(SUM(COALESCE(value::numeric, 0)))::int
    FROM rep_warehouse.view_observed_kpi
    WHERE disaggregation_level_one = 'Annual'
      AND disaggregation_level_two = 'Girls Total'
      AND kpi_id = '1.1'
      AND year IS NOT NULL AND country IS NOT NULL
    GROUP BY country, year;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'refresh_dashboard_data_agg: skipping Children Supported bursaries (Annual) — %', SQLERRM;
  END;

  BEGIN
    INSERT INTO rep_portal.dashboard_data_agg_new (country, province, district, school, year, metric, value)
    SELECT country, 'National', 'National', 'National', year,
           'Children Supported in School with Education Bursaries — Cumulative 2020-2030',
           ROUND(SUM(COALESCE(value::numeric, 0)))::int
    FROM rep_warehouse.view_observed_kpi
    WHERE disaggregation_level_one = 'Cumulative since 2020'
      AND disaggregation_level_two = 'Girls Total'
      AND kpi_id = '1.1'
      AND year IS NOT NULL AND country IS NOT NULL
    GROUP BY country, year;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'refresh_dashboard_data_agg: skipping Cumulative 2020-2030 — %', SQLERRM;
  END;

  BEGIN
    INSERT INTO rep_portal.dashboard_data_agg_new (country, province, district, school, year, metric, value)
    SELECT country, 'National', 'National', 'National', year,
           'Children Supported in School with Education Bursaries — Cumulative 2024-2030',
           ROUND(SUM(COALESCE(value::numeric, 0)))::int
    FROM rep_warehouse.view_observed_kpi
    WHERE disaggregation_level_one = 'Cumulative since 2024'
      AND disaggregation_level_two = 'Girls Total'
      AND kpi_id = '1.1'
      AND year IS NOT NULL AND country IS NOT NULL
    GROUP BY country, year;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'refresh_dashboard_data_agg: skipping Cumulative 2024-2030 — %', SQLERRM;
  END;

  BEGIN
    INSERT INTO rep_portal.dashboard_data_agg_new (country, province, district, school, year, metric, value)
    SELECT country, 'National', 'National', 'National', year,
           'Children Supported in School with Education Bursaries — Cumulative all-time',
           ROUND(SUM(COALESCE(value::numeric, 0)))::int
    FROM rep_warehouse.view_observed_kpi
    WHERE disaggregation_level_one = 'Cumulative all-time'
      AND disaggregation_level_two = 'Girls Total'
      AND kpi_id = '1.1'
      AND year IS NOT NULL AND country IS NOT NULL
    GROUP BY country, year;
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'refresh_dashboard_data_agg: skipping Cumulative all-time — %', SQLERRM;
  END;

  -- Swap new table into place atomically
  TRUNCATE rep_portal.dashboard_data_agg;
  INSERT INTO rep_portal.dashboard_data_agg SELECT * FROM rep_portal.dashboard_data_agg_new;
  DROP TABLE rep_portal.dashboard_data_agg_new;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.refresh_dashboard_data_agg() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.refresh_dashboard_data_agg() TO service_role;

-- Populate immediately so the fix is visible right away, not just after the
-- next ETL run or KPI upload.
SELECT rep_portal.refresh_dashboard_data_agg();


-- ===== 20260712071101_kpi_report_show_null_rows.sql =====
-- kpi_report_indicator_detail was dropping rows where value IS NULL, silently
-- hiding disaggregation combinations that genuinely exist in the source data but
-- have no value entered — distinct from placeholder text like 'Not available'/
-- 'Not applicable', which are non-NULL strings and already display correctly.
-- The WhatsApp bot should show every disaggregation row for an indicator, with
-- NULLs rendered as '—' by the edge function rather than omitted.

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_report_indicator_detail(p_country TEXT, p_year INTEGER, p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  value_type TEXT,
  value TEXT,
  definition TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT disaggregation_level_one, disaggregation_level_two, value_type, value, definition
  FROM rep_warehouse.view_observed_kpi
  WHERE row_scope = 'DETAIL'
    AND country = p_country AND year = p_year
    AND kpi_group = p_kpi_group AND indicator = p_indicator
  ORDER BY disaggregation_level_one, disaggregation_level_two;
$$;


-- ===== 20260712071342_kpi_report_all_row_scopes.sql =====
-- kpi_report_years / kpi_report_groups / kpi_report_indicators all queried
-- view_kpi_detail, which hardcodes `WHERE row_scope = 'DETAIL'` at the view
-- level. Most Level 1 (and likely other) indicators have zero DETAIL rows —
-- their real values live under ANNUAL/CUMULATIVE/SUBTOTAL instead — so whole
-- indicators (not just individual rows) were invisible in the WhatsApp bot.
-- e.g. Malawi 2025 has 14 total Level 1 indicators; only 5 have any DETAIL
-- rows. Switch all four functions to the unfiltered view_observed_kpi so every
-- indicator and every disaggregation row shows, regardless of row_scope —
-- the bot is a plain listing, not an aggregation, so there's no double-count
-- risk in showing ANNUAL/CUMULATIVE/SUBTOTAL/BENCHMARK rows alongside DETAIL.

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_report_years(p_country TEXT)
RETURNS TABLE (year INTEGER)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT DISTINCT year
  FROM rep_warehouse.view_observed_kpi
  WHERE country = p_country
  ORDER BY year DESC;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_report_groups(p_country TEXT, p_year INTEGER)
RETURNS TABLE (kpi_group TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT DISTINCT kpi_group
  FROM rep_warehouse.view_observed_kpi
  WHERE country = p_country AND year = p_year
  ORDER BY kpi_group;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_report_indicators(p_country TEXT, p_year INTEGER, p_kpi_group TEXT)
RETURNS TABLE (indicator TEXT, short_label TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT DISTINCT d.indicator, COALESCE(k.short_label, d.indicator)
  FROM rep_warehouse.view_observed_kpi d
  LEFT JOIN rep_warehouse.dim_kpi k ON k.indicator = d.indicator AND k.scd_is_current = true
  WHERE d.country = p_country AND d.year = p_year AND d.kpi_group = p_kpi_group
  ORDER BY d.indicator;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_report_indicator_detail(p_country TEXT, p_year INTEGER, p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  value_type TEXT,
  value TEXT,
  definition TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT disaggregation_level_one, disaggregation_level_two, value_type, value, definition
  FROM rep_warehouse.view_observed_kpi
  WHERE country = p_country AND year = p_year
    AND kpi_group = p_kpi_group AND indicator = p_indicator
  ORDER BY disaggregation_level_one, disaggregation_level_two;
$$;


-- ===== 20260712072056_dim_kpi_remaining_short_labels.sql =====
-- Backfill short_label for the 56 indicators that only became visible in the
-- WhatsApp KPI report after 20260712071342 removed the row_scope = 'DETAIL'
-- restriction. The original 20260710102034 migration only labeled the 19
-- indicators found via the (DETAIL-only) view_kpi_detail at the time, so
-- these fell back to COALESCE(short_label, indicator) — the full, sometimes
-- 100+ character indicator name, truncated to 24 chars for list row titles.

-- Level 1
UPDATE rep_warehouse.dim_kpi SET short_label = 'Girls agency/self-belief'
  WHERE indicator = '% of girls receiving social and learning support report increased self belief, leadership potential and agency';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Dropout - pregnancy'
  WHERE indicator = '% of supported girls dropping out due to pregnancy or early marriage (< age 18 yrs)';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Children soc/learn supp'
  WHERE indicator = 'Number of children receiving social and learning support';
UPDATE rep_warehouse.dim_kpi SET short_label = 'MBW curriculum support'
  WHERE indicator = 'Number of children receiving social and learning support from integration of MBW principles into national curricula';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Children supp via LGs'
  WHERE indicator = 'Number of children receiving social and learning support through Learner Guides';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Girls bursary support'
  WHERE indicator = 'Number of girls receiving CAMFED bursary support';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Girls supp: CAMA+comm.'
  WHERE indicator = 'Number of girls supported to go to school by CAMA and community support';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Girls supp: all sources'
  WHERE indicator = 'Number of girls supported to go to school by CAMFED, CAMA and community support';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Girls supp: community'
  WHERE indicator = 'Number of girls supported to go to school by community support';

-- Level 2
UPDATE rep_warehouse.dim_kpi SET short_label = 'CAMA marriage age gap'
  WHERE indicator = 'Average # of years later a CAMA member is getting married compared to peers';
UPDATE rep_warehouse.dim_kpi SET short_label = 'CAMA first-child age gap'
  WHERE indicator = 'Average # of years later a CAMA member is having their first child compared to peers';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Grants distributed'
  WHERE indicator = 'Number and value of grants distributed';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Loans distributed'
  WHERE indicator = 'Number and value of loans distributed';
UPDATE rep_warehouse.dim_kpi SET short_label = 'CAMA leadership roles'
  WHERE indicator = 'Number of CAMA members who take on leadership roles in education systems and the wider community';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Successful entrepreneurs'
  WHERE indicator = 'Number of female entrepreneurs that succeed in setting up a business';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Entrepreneurs w/ +income'
  WHERE indicator = 'Number of female entrepreneurs with increased incomes after participating in CAMFED''s Enterprise Development Programme';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Women supp by Trans. Gds'
  WHERE indicator = 'Number of young women supported by Transition Guides';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Women in tertiary educ.'
  WHERE indicator = 'Number of young women supported in tertiary or further education';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Entrepreneurs profitable'
  WHERE indicator = 'Percentage of female entrepreneurs making a profit with incomes that exceed the local poverty line after participating in CAMFED''s Enterprise Development Programme';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Women secure livelihood'
  WHERE indicator = 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Business survival rate'
  WHERE indicator = 'Survival rate of businesses after participating in CAMFED''s Enterprise Development Programme';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Total CAMA members'
  WHERE indicator = 'Total number of CAMA members';

-- Level 3
UPDATE rep_warehouse.dim_kpi SET short_label = 'Govt % of LG resources'
  WHERE indicator = '% of resources for the Learner Guide program contributed by government';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Children in better envt.'
  WHERE indicator = 'Children benefitting from improved learning environment (number of students in partner schools)';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Girls dropout (marriage)'
  WHERE indicator = 'Drop-out rate for girls attributed to early marriage or pregnancy';
UPDATE rep_warehouse.dim_kpi SET short_label = 'System transformation'
  WHERE indicator = 'Indicators of system transformation';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Margin. girls completion'
  WHERE indicator = 'Marginalised girls secondary completion rates';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Margin. girls promotion'
  WHERE indicator = 'Marginalised girls secondary promotion rates';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Number of districts'
  WHERE indicator = 'Number of districts';

-- Programme Metrics
UPDATE rep_warehouse.dim_kpi SET short_label = 'Clients ext. monitored'
  WHERE indicator = '% of clients receiving external monitoring';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Schools ext. monitored'
  WHERE indicator = '% of schools hosting clients which received external monitoring visits';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Drop out rate (clients)'
  WHERE indicator = 'Drop out rate clients, disaggregated by grade/form and reason';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Govt MOUs'
  WHERE indicator = 'Number (and list) of MOUs with government partners';
UPDATE rep_warehouse.dim_kpi SET short_label = 'CAMA District Committees'
  WHERE indicator = 'Number of CAMA District Committees';
UPDATE rep_warehouse.dim_kpi SET short_label = 'CAMA grads joining CAMA'
  WHERE indicator = 'Number of CAMA-supported graduates joining CAMA';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Primary supp (CAMFED)'
  WHERE indicator = 'Number of children supported to go to school by CAMFED at primary level';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Secondary supp (CAMFED)'
  WHERE indicator = 'Number of children supported to go to school by CAMFED at secondary level';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Children supp: all srcs'
  WHERE indicator = 'Number of children supported to go to school by CAMFED, and by CAMA philanthropy and community support';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Community reached by AGs'
  WHERE indicator = 'Number of community members reached by Agriculture Guides';
UPDATE rep_warehouse.dim_kpi SET short_label = 'District entrep. cttees'
  WHERE indicator = 'Number of district level committees to coordinate support for female entrepreneurs';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Entrepreneurs w/ linkage'
  WHERE indicator = 'Number of female entrepreneurs linked by CAMFED to additional forms of support for businesses';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Girls: targeted LG supp'
  WHERE indicator = 'Number of girls receiving targeted social support from Learner Guides';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Schools hosting bursary'
  WHERE indicator = 'Number of schools hosting bursary clients';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Schools: LG climate ed.'
  WHERE indicator = 'Number of schools where Learner Guides deliver climate education';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Women joining CAMA (new)'
  WHERE indicator = 'Number of young women joining CAMA without receiving previous support (shared value system)';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Grads joining CAMA (%)'
  WHERE indicator = 'Percentage of CAMFED-supported graduates joining CAMA annually';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Student retention rate'
  WHERE indicator = 'Retention rate of supported students';

-- Research bank indicators
UPDATE rep_warehouse.dim_kpi SET short_label = 'CAMA post-sec qualif.'
  WHERE indicator = '% of CAMA members who gain a post-secondary qualification after participating in the LG programme';
UPDATE rep_warehouse.dim_kpi SET short_label = 'CSA techniques used'
  WHERE indicator = 'Climate Smart Agriculture (CSA) techniques used';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Increased yields (AGP)'
  WHERE indicator = 'Increased yields since receiving support from AGP/ adopting CSA techniques';
UPDATE rep_warehouse.dim_kpi SET short_label = 'CAMA in dignified work'
  WHERE indicator = 'Number of CAMA members in dignified & fulfilling work';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Children climate educ.'
  WHERE indicator = 'Number of children receiving climate education from Learner Guides';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Community climate reach'
  WHERE indicator = 'Number of community members reached with information and techniques for improved climate-resilience';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Entrep. supp by CAMA'
  WHERE indicator = 'Number of female entrepreneurs who have received economic support from another CAMA member';
UPDATE rep_warehouse.dim_kpi SET short_label = 'Entrep. +food consump.'
  WHERE indicator = 'Percentage of female entrepreneurs reporting an increased household consumption of food since participating in CAMFED''s enterprise development programme';
UPDATE rep_warehouse.dim_kpi SET short_label = 'LGs w/ increased agency'
  WHERE indicator = 'Percentage of LGs who report increased sense of agency';


-- ===== 20260712073202_kpi_report_indicator_detail_distinct.sql =====
-- fact_observed_kpi has no row-level dedup on insert (year-scoped replace:
-- DELETE then plain INSERT), so a duplicate row in a KPI upload spreadsheet
-- produces two literally identical fact rows (same kpi_id, geography_id,
-- year_date_id, disaggregation, and value). Confirmed for Zambia/2024/
-- "Number of girls supported to go to school by CAMA" — e.g. fact rows
-- 120305 and 120323 are exact duplicates. Add DISTINCT so the WhatsApp bot
-- doesn't show the same disaggregation/value line twice. This only collapses
-- exact duplicates (same value_type/value); it does not address the separate
-- question of how much total volume to show across row_scope.

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_report_indicator_detail(p_country TEXT, p_year INTEGER, p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  value_type TEXT,
  value TEXT,
  definition TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT DISTINCT disaggregation_level_one, disaggregation_level_two, value_type, value, definition
  FROM rep_warehouse.view_observed_kpi
  WHERE country = p_country AND year = p_year
    AND kpi_group = p_kpi_group AND indicator = p_indicator
  ORDER BY disaggregation_level_one, disaggregation_level_two;
$$;


-- ===== 20260712074041_kpi_report_add_source_kpi_id.sql =====
-- Add source_kpi_id (e.g. '1.2a') to kpi_report_indicators and
-- kpi_report_indicator_detail so the WhatsApp bot can show the underlying KPI
-- code alongside the indicator name, both in the indicator picker and the
-- detail message — useful for verifying exactly which KPI code a given
-- indicator/row maps to (came up while investigating whether "girls supported
-- by CAMA" data was mixing in rows from the related-but-distinct 1.2 / 1.2b
-- codes; it wasn't, but the code wasn't visible anywhere in the bot output).
-- view_observed_kpi.kpi_id is already dim_kpi.source_kpi_id (see its
-- definition: `k.source_kpi_id AS kpi_id`), so no extra join is needed.
--
-- Return type changes require DROP + CREATE rather than CREATE OR REPLACE.

DROP FUNCTION IF EXISTS rep_portal.kpi_report_indicators(TEXT, INTEGER, TEXT);
DROP FUNCTION IF EXISTS rep_warehouse.kpi_report_indicators(TEXT, INTEGER, TEXT);

CREATE FUNCTION rep_warehouse.kpi_report_indicators(p_country TEXT, p_year INTEGER, p_kpi_group TEXT)
RETURNS TABLE (indicator TEXT, short_label TEXT, source_kpi_id TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT DISTINCT d.indicator, COALESCE(k.short_label, d.indicator), d.kpi_id
  FROM rep_warehouse.view_observed_kpi d
  LEFT JOIN rep_warehouse.dim_kpi k ON k.indicator = d.indicator AND k.scd_is_current = true
  WHERE d.country = p_country AND d.year = p_year AND d.kpi_group = p_kpi_group
  ORDER BY d.indicator;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.kpi_report_indicators(TEXT, INTEGER, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_warehouse.kpi_report_indicators(TEXT, INTEGER, TEXT) TO service_role;

CREATE FUNCTION rep_portal.kpi_report_indicators(p_country TEXT, p_year INTEGER, p_kpi_group TEXT)
RETURNS TABLE (indicator TEXT, short_label TEXT, source_kpi_id TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT * FROM rep_warehouse.kpi_report_indicators(p_country, p_year, p_kpi_group);
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_report_indicators(TEXT, INTEGER, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_report_indicators(TEXT, INTEGER, TEXT) TO service_role;

DROP FUNCTION IF EXISTS rep_portal.kpi_report_indicator_detail(TEXT, INTEGER, TEXT, TEXT);
DROP FUNCTION IF EXISTS rep_warehouse.kpi_report_indicator_detail(TEXT, INTEGER, TEXT, TEXT);

CREATE FUNCTION rep_warehouse.kpi_report_indicator_detail(p_country TEXT, p_year INTEGER, p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  value_type TEXT,
  value TEXT,
  definition TEXT,
  source_kpi_id TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT DISTINCT disaggregation_level_one, disaggregation_level_two, value_type, value, definition, kpi_id
  FROM rep_warehouse.view_observed_kpi
  WHERE country = p_country AND year = p_year
    AND kpi_group = p_kpi_group AND indicator = p_indicator
  ORDER BY disaggregation_level_one, disaggregation_level_two;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.kpi_report_indicator_detail(TEXT, INTEGER, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_warehouse.kpi_report_indicator_detail(TEXT, INTEGER, TEXT, TEXT) TO service_role;

CREATE FUNCTION rep_portal.kpi_report_indicator_detail(p_country TEXT, p_year INTEGER, p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  value_type TEXT,
  value TEXT,
  definition TEXT,
  source_kpi_id TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT * FROM rep_warehouse.kpi_report_indicator_detail(p_country, p_year, p_kpi_group, p_indicator);
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_report_indicator_detail(TEXT, INTEGER, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_report_indicator_detail(TEXT, INTEGER, TEXT, TEXT) TO service_role;


-- ===== 20260712074556_kpi_report_indicators_join_by_group.sql =====
-- kpi_report_indicators joined dim_kpi on indicator text alone (plus
-- scd_is_current) to fetch short_label, without also matching kpi_group.
-- dim_kpi's uniqueness key is (source_kpi_id, scd_version) — not
-- (source_kpi_id, kpi_group) — so nothing in the schema actually guarantees a
-- given indicator/source_kpi_id can't appear under two different kpi_group
-- values (e.g. via reclassification across SCD versions). Confirmed no such
-- case exists in current data, but the join should match on kpi_group
-- defensively so it can't silently pick the wrong row's short_label if that
-- ever changes. kpi_report_indicator_detail already filters view_observed_kpi
-- directly by kpi_group, so it wasn't affected by this gap.

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_report_indicators(p_country TEXT, p_year INTEGER, p_kpi_group TEXT)
RETURNS TABLE (indicator TEXT, short_label TEXT, source_kpi_id TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT DISTINCT d.indicator, COALESCE(k.short_label, d.indicator), d.kpi_id
  FROM rep_warehouse.view_observed_kpi d
  LEFT JOIN rep_warehouse.dim_kpi k
    ON k.indicator = d.indicator AND k.kpi_group = d.kpi_group AND k.scd_is_current = true
  WHERE d.country = p_country AND d.year = p_year AND d.kpi_group = p_kpi_group
  ORDER BY d.indicator;
$$;


-- ===== 20260712075556_kpi_report_order_by_kpi_id_and_row_number.sql =====
-- Reorder the WhatsApp KPI report:
--   - Indicator picker: order by source_kpi_id (kpi code) instead of
--     alphabetically by indicator name.
--   - Indicator detail rows: order by the source spreadsheet's row number
--     (lin_source_row_number, exposed by view_observed_kpi) instead of
--     alphabetically by disaggregation label, so rows appear in the same
--     order as the original upload.
--
-- lin_source_row_number is unique per disaggregation cell, not per indicator —
-- the known Zambia/2024 duplicate (fact ids 120305 vs 120323) has row numbers
-- 34 and 364 respectively (the whole block genuinely repeats later in the
-- source file). Plain `SELECT DISTINCT` including row_number would therefore
-- undo the dedup fix from 20260712073202, since the two duplicate rows differ
-- in that one column. Dedupe first (DISTINCT ON the content columns, picking
-- the earliest row_number as representative), then order the deduped set by
-- that row_number.

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_report_indicators(p_country TEXT, p_year INTEGER, p_kpi_group TEXT)
RETURNS TABLE (indicator TEXT, short_label TEXT, source_kpi_id TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT DISTINCT d.indicator, COALESCE(k.short_label, d.indicator), d.kpi_id
  FROM rep_warehouse.view_observed_kpi d
  LEFT JOIN rep_warehouse.dim_kpi k
    ON k.indicator = d.indicator AND k.kpi_group = d.kpi_group AND k.scd_is_current = true
  WHERE d.country = p_country AND d.year = p_year AND d.kpi_group = p_kpi_group
  ORDER BY d.kpi_id, d.indicator;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_report_indicator_detail(p_country TEXT, p_year INTEGER, p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  value_type TEXT,
  value TEXT,
  definition TEXT,
  source_kpi_id TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT disaggregation_level_one, disaggregation_level_two, value_type, value, definition, kpi_id
  FROM (
    SELECT DISTINCT ON (disaggregation_level_one, disaggregation_level_two, value_type, value)
      disaggregation_level_one, disaggregation_level_two, value_type, value, definition, kpi_id, lin_source_row_number
    FROM rep_warehouse.view_observed_kpi
    WHERE country = p_country AND year = p_year
      AND kpi_group = p_kpi_group AND indicator = p_indicator
    ORDER BY disaggregation_level_one, disaggregation_level_two, value_type, value, lin_source_row_number
  ) deduped
  ORDER BY lin_source_row_number;
$$;


-- ===== 20260712093848_grant_wa_report_kpis_permission.sql =====
-- Grant wa_report:kpis to every role that already has a wa_report:* permission
-- (children/people/finance), so the WhatsApp bot report menu shows the KPIs
-- option consistently with the other report types.
insert into rep_portal.role_permissions (role_id, permission_id)
select distinct rp.role_id, p_kpis.id
from rep_portal.role_permissions rp
join rep_portal.permissions p on p.id = rp.permission_id
cross join (select id from rep_portal.permissions where key = 'wa_report:kpis') p_kpis
where p.category = 'wa_report'
  and p.key <> 'wa_report:kpis'
on conflict (role_id, permission_id) do nothing;


-- ===== 20260712102309_add_kpi_coverage_summary_rpc.sql =====
-- Lightweight KPI coverage snapshot for the admin Overview page.
-- Aggregates rep_portal.kpi_coverage_data (already deduped one row per
-- kpi_id/country/year, preferring SUBTOTAL then ANNUAL row_scope) instead of
-- shipping the full row set to the client, as coverageQueries.ts does for
-- the detailed /admin/coverage page.
CREATE OR REPLACE FUNCTION rep_portal.get_kpi_coverage_summary()
RETURNS TABLE (
    total_kpis         BIGINT,
    kpis_with_data      BIGINT,
    countries_covered   BIGINT,
    years_covered       BIGINT,
    last_updated        DATE
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$

    WITH parsed AS (
        SELECT
            kpi_id,
            country,
            year,
            updated_date,
            CASE
                WHEN regexp_replace(value, '[$,£€]', '', 'g') ~ '^-?[0-9]+(\.[0-9]+)?$'
                THEN regexp_replace(value, '[$,£€]', '', 'g')::numeric
                ELSE 0
            END AS num_value
        FROM rep_portal.kpi_coverage_data
    )
    SELECT
        (SELECT COUNT(DISTINCT kpi_id)  FROM parsed)                        AS total_kpis,
        (SELECT COUNT(DISTINCT kpi_id)  FROM parsed WHERE num_value <> 0)   AS kpis_with_data,
        (SELECT COUNT(DISTINCT country) FROM parsed WHERE num_value <> 0)   AS countries_covered,
        (SELECT COUNT(DISTINCT year)    FROM parsed WHERE num_value <> 0)   AS years_covered,
        (SELECT MAX(updated_date)       FROM parsed WHERE num_value <> 0)   AS last_updated

$$;

REVOKE EXECUTE ON FUNCTION rep_portal.get_kpi_coverage_summary() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_kpi_coverage_summary() TO authenticated;


-- ===== 20260712131244_add_portal_page_views.sql =====
-- Portal usage tracking: page views for Dashboard, Dynamic Data, Map.
--
-- Detail log (portal_page_views) is time-limited (90-day retention, purged
-- by a monthly cron job) so it never grows unbounded. A monthly per-user
-- rollup table (portal_usage_monthly) is kept indefinitely for long-term
-- trend/history beyond the detail retention window.

-- ── Detail log ────────────────────────────────────────────────────────────────

CREATE TABLE rep_portal.portal_page_views (
  id          BIGSERIAL    PRIMARY KEY,
  user_id     UUID         NOT NULL,   -- auth.uid(), captured server-side
  user_email  TEXT,                    -- snapshot from auth.users at insert time, for admin display
  page        TEXT         NOT NULL,   -- 'dashboard' | 'dynamic' | 'map'
  occurred_at TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX ON rep_portal.portal_page_views (occurred_at DESC);
CREATE INDEX ON rep_portal.portal_page_views (page, occurred_at DESC);
CREATE INDEX ON rep_portal.portal_page_views (user_id, occurred_at DESC);

ALTER TABLE rep_portal.portal_page_views ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin_select_portal_page_views"
  ON rep_portal.portal_page_views
  FOR SELECT TO authenticated
  USING (rep_warehouse.is_admin());

-- No GRANT INSERT to any role — all inserts go through log_page_view() below
-- (SECURITY DEFINER function owner bypasses RLS).

CREATE OR REPLACE FUNCTION rep_portal.log_page_view(p_page TEXT)
RETURNS VOID
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = rep_portal, auth, public
AS $$
BEGIN
  IF p_page NOT IN ('dashboard', 'dynamic', 'map') THEN
    RAISE EXCEPTION 'Invalid page: %', p_page;
  END IF;

  INSERT INTO rep_portal.portal_page_views (user_id, user_email, page)
  SELECT auth.uid(), u.email, p_page
  FROM auth.users u WHERE u.id = auth.uid();
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.log_page_view(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.log_page_view(TEXT) TO authenticated;

-- ── Monthly rollup (kept indefinitely) + retention purge ───────────────────────

CREATE TABLE rep_portal.portal_usage_monthly (
  usage_month DATE         NOT NULL,   -- first-of-month, e.g. 2026-07-01
  page        TEXT         NOT NULL,
  user_id     UUID         NOT NULL,
  user_email  TEXT,
  view_count  INTEGER      NOT NULL,
  PRIMARY KEY (usage_month, page, user_id)
);

ALTER TABLE rep_portal.portal_usage_monthly ENABLE ROW LEVEL SECURITY;

CREATE POLICY "admin_select_portal_usage_monthly"
  ON rep_portal.portal_usage_monthly
  FOR SELECT TO authenticated
  USING (rep_warehouse.is_admin());

-- Aggregates one completed month of detail rows into the monthly table.
-- Idempotent: safe to re-run for the same month (e.g. manual backfill).
CREATE OR REPLACE FUNCTION rep_portal.rollup_portal_usage_monthly(p_month DATE)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = rep_portal, public
AS $$
BEGIN
  INSERT INTO rep_portal.portal_usage_monthly (usage_month, page, user_id, user_email, view_count)
  SELECT date_trunc('month', occurred_at)::date, page, user_id, max(user_email), count(*)
  FROM rep_portal.portal_page_views
  WHERE occurred_at >= date_trunc('month', p_month)
    AND occurred_at <  date_trunc('month', p_month) + INTERVAL '1 month'
  GROUP BY 1, 2, 3
  ON CONFLICT (usage_month, page, user_id)
  DO UPDATE SET view_count = EXCLUDED.view_count, user_email = EXCLUDED.user_email;
END;
$$;

-- Purges detail rows past the retention window. Best-effort — mirrors the
-- BEGIN...EXCEPTION WHEN OTHERS THEN NULL pattern used for ETL scratch
-- cleanup (20260609201900_cleanup_raw_staging_after_etl.sql).
CREATE OR REPLACE FUNCTION rep_portal.purge_portal_page_views(p_retention_days INT DEFAULT 90)
RETURNS VOID LANGUAGE plpgsql SECURITY DEFINER
SET search_path = rep_portal, public
AS $$
BEGIN
  DELETE FROM rep_portal.portal_page_views
  WHERE occurred_at < now() - (p_retention_days || ' days')::interval;
EXCEPTION WHEN OTHERS THEN NULL;
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.rollup_portal_usage_monthly(DATE) FROM PUBLIC;
REVOKE ALL ON FUNCTION rep_portal.purge_portal_page_views(INT) FROM PUBLIC;
-- No GRANT TO authenticated — these are cron/service-role only, never called from the browser.

-- 03:00 UTC on the 1st of each month: roll up the previous completed month,
-- then purge detail rows past the retention window. No net.http_post/vault
-- hop needed (unlike the ingest/mat-view cron jobs) — a bounded monthly
-- DELETE + aggregate has no meaningful statement-timeout risk.
SELECT cron.schedule(
  'portal-usage-monthly-rollup',
  '0 3 1 * *',
  $$
    SELECT rep_portal.rollup_portal_usage_monthly((date_trunc('month', now()) - INTERVAL '1 month')::date);
    SELECT rep_portal.purge_portal_page_views(90);
  $$
);

-- ── Analytics views + read RPCs ─────────────────────────────────────────────────

CREATE VIEW rep_portal.view_usage_daily AS
SELECT
  (occurred_at AT TIME ZONE 'UTC')::date  AS day,
  page,
  COUNT(DISTINCT user_id)                 AS unique_users,
  COUNT(*)                                AS total_views
FROM rep_portal.portal_page_views
WHERE occurred_at >= now() - INTERVAL '60 days'
GROUP BY 1, 2
ORDER BY 1 DESC;

GRANT SELECT ON rep_portal.view_usage_daily TO authenticated;

CREATE VIEW rep_portal.view_usage_by_page AS
SELECT
  page,
  COUNT(DISTINCT user_id)  AS unique_users,
  COUNT(*)                 AS total_views
FROM rep_portal.portal_page_views
WHERE occurred_at >= now() - INTERVAL '30 days'
GROUP BY page
ORDER BY total_views DESC;

GRANT SELECT ON rep_portal.view_usage_by_page TO authenticated;

CREATE VIEW rep_portal.view_usage_by_user AS
SELECT
  user_id,
  max(user_email)                                              AS user_email,
  max(occurred_at)                                              AS last_seen,
  COUNT(*) FILTER (WHERE page = 'dashboard')                    AS dashboard_views,
  COUNT(*) FILTER (WHERE page = 'dynamic')                      AS dynamic_views,
  COUNT(*) FILTER (WHERE page = 'map')                          AS map_views,
  COUNT(*)                                                      AS total_views
FROM rep_portal.portal_page_views
GROUP BY user_id
ORDER BY total_views DESC;

GRANT SELECT ON rep_portal.view_usage_by_user TO authenticated;

CREATE VIEW rep_portal.view_usage_monthly AS
SELECT
  usage_month,
  page,
  COUNT(DISTINCT user_id)   AS unique_users,
  SUM(view_count)           AS total_views
FROM rep_portal.portal_usage_monthly
GROUP BY usage_month, page
ORDER BY usage_month DESC;

GRANT SELECT ON rep_portal.view_usage_monthly TO authenticated;

-- Wrap views in SECURITY DEFINER RPCs (mirrors get_wa_* in
-- 20250201000035_wa_analytics_rpc_wrappers.sql) — views are security_invoker
-- so `authenticated` needs its own admin check since it has no direct grant
-- on the base tables.

CREATE OR REPLACE FUNCTION rep_portal.get_usage_daily()
RETURNS TABLE (
  day          DATE,
  page         TEXT,
  unique_users BIGINT,
  total_views  BIGINT
) LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = rep_portal, public
AS $$
BEGIN
  IF rep_warehouse.is_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Admin privileges required';
  END IF;
  RETURN QUERY SELECT v.day, v.page, v.unique_users, v.total_views
               FROM rep_portal.view_usage_daily v;
END;
$$;

CREATE OR REPLACE FUNCTION rep_portal.get_usage_by_page()
RETURNS TABLE (
  page         TEXT,
  unique_users BIGINT,
  total_views  BIGINT
) LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = rep_portal, public
AS $$
BEGIN
  IF rep_warehouse.is_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Admin privileges required';
  END IF;
  RETURN QUERY SELECT v.page, v.unique_users, v.total_views
               FROM rep_portal.view_usage_by_page v;
END;
$$;

CREATE OR REPLACE FUNCTION rep_portal.get_usage_by_user()
RETURNS TABLE (
  user_id         UUID,
  user_email      TEXT,
  last_seen       TIMESTAMPTZ,
  dashboard_views BIGINT,
  dynamic_views   BIGINT,
  map_views       BIGINT,
  total_views     BIGINT
) LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = rep_portal, public
AS $$
BEGIN
  IF rep_warehouse.is_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Admin privileges required';
  END IF;
  RETURN QUERY SELECT v.user_id, v.user_email, v.last_seen,
                      v.dashboard_views, v.dynamic_views, v.map_views, v.total_views
               FROM rep_portal.view_usage_by_user v;
END;
$$;

CREATE OR REPLACE FUNCTION rep_portal.get_usage_monthly()
RETURNS TABLE (
  usage_month  DATE,
  page         TEXT,
  unique_users BIGINT,
  total_views  BIGINT
) LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = rep_portal, public
AS $$
BEGIN
  IF rep_warehouse.is_admin() IS NOT TRUE THEN
    RAISE EXCEPTION 'Admin privileges required';
  END IF;
  RETURN QUERY SELECT v.usage_month, v.page, v.unique_users, v.total_views
               FROM rep_portal.view_usage_monthly v;
END;
$$;

GRANT EXECUTE ON FUNCTION rep_portal.get_usage_daily()    TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_usage_by_page()  TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_usage_by_user()  TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_usage_monthly()  TO authenticated;


-- ===== 20260713182841_kpi_definitions_key_by_group.sql =====
-- dim_kpi's identity key was source_kpi_id alone, but rep_raw.all_kpis
-- genuinely reuses kpi_no across different kpi_group values (e.g. 1.2a/1.2b
-- appear under both "Level 1" and "Programme Metrics" with different
-- indicators, every year 2020-2025). Because kpi_definitions_load() and
-- kpi_upload_all() both matched dim_kpi on source_kpi_id only, uploading a
-- definitions row for one group silently overwrote/absorbed the other
-- group's row (kpi_definitions_load does a plain in-place UPDATE keyed on
-- source_kpi_id), and the fact-load join then mapped ALL of that kpi_no's
-- raw rows -- regardless of group -- onto whichever definition happened to
-- be current.
--
-- Fix: make (source_kpi_id, kpi_group) the identity key throughout.
-- This migration does NOT touch existing dim_kpi/fact_observed_kpi rows --
-- the historical backfill (adding the missing Level 1 dim_kpi rows and
-- re-running kpi_upload_all per year to remap facts) is a separate,
-- deliberate step.

-- ── 1. dim_kpi indexes: key by (source_kpi_id, kpi_group) ───────────────────

ALTER TABLE rep_warehouse.dim_kpi DROP CONSTRAINT IF EXISTS dim_kpi_source_kpi_id_scd_version_key;
DROP INDEX IF EXISTS rep_warehouse.idx_dim_kpi_source_id;

CREATE UNIQUE INDEX dim_kpi_source_kpi_id_group_scd_version_key
    ON rep_warehouse.dim_kpi (source_kpi_id, kpi_group, scd_version);

CREATE UNIQUE INDEX idx_dim_kpi_source_id_group
    ON rep_warehouse.dim_kpi (source_kpi_id, kpi_group)
    WHERE scd_is_current = true;

-- ── 2. kpi_definitions_load: lookup/update scoped to (source_kpi_id, kpi_group) ──

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_definitions_load(
    p_batch_id    TEXT,
    p_rows        JSONB,
    p_source_file TEXT,
    p_uploaded_by TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path   = rep_warehouse, pg_temp
SET statement_timeout = 0
AS $$
DECLARE
    v_inserted  INTEGER := 0;
    v_updated   INTEGER := 0;
    v_skipped   INTEGER := 0;
    v_total     INTEGER := 0;
    v_row       JSONB;
    v_src_id    TEXT;
    v_group     TEXT;
    v_indicator TEXT;
    v_freq      TEXT;
    v_start     TEXT;
    v_defn      TEXT;
    v_new_hash  TEXT;
    v_cur_hash  TEXT;
BEGIN
    PERFORM set_config('app.batch_id',      p_batch_id,     true);
    PERFORM set_config('app.source_system', 'Excel_CAMFED', true);
    PERFORM set_config('app.source_file',   p_source_file,  true);

    v_total := jsonb_array_length(p_rows);

    FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_src_id    := TRIM(v_row->>'source_kpi_id');
        v_group     := TRIM(v_row->>'kpi_group');
        v_indicator := TRIM(v_row->>'indicator');
        v_freq      := NULLIF(TRIM(v_row->>'indicator_frequency'), '');
        v_start     := NULLIF(TRIM(v_row->>'indicator_start'),     '');
        v_defn      := NULLIF(TRIM(v_row->>'definition'),          '');

        IF v_src_id IS NULL OR v_src_id = '' THEN
            CONTINUE;
        END IF;

        v_new_hash := MD5(concat_ws('||',
            COALESCE(v_src_id,    ''),
            COALESCE(v_group,     ''),
            COALESCE(v_indicator, ''),
            COALESCE(v_freq,      ''),
            COALESCE(v_start,     ''),
            COALESCE(v_defn,      '')
        ));

        SELECT lin_business_hash INTO v_cur_hash
          FROM rep_warehouse.dim_kpi
         WHERE source_kpi_id = v_src_id AND kpi_group = v_group AND scd_is_current = true
         LIMIT 1;

        IF NOT FOUND THEN
            INSERT INTO rep_warehouse.dim_kpi
                (source_kpi_id, kpi_group, indicator,
                 indicator_frequency, indicator_start, definition,
                 scd_effective_from, scd_is_current, scd_version,
                 lin_business_hash, lin_load_batch_id,
                 lin_source_system, lin_source_file, lin_inserted_at)
            VALUES
                (v_src_id, v_group, v_indicator,
                 v_freq, v_start, v_defn,
                 CURRENT_DATE, true, 1,
                 v_new_hash, p_batch_id,
                 'Excel_CAMFED', p_source_file, NOW());

            v_inserted := v_inserted + 1;

        ELSIF v_cur_hash = v_new_hash THEN
            v_skipped := v_skipped + 1;

        ELSE
            UPDATE rep_warehouse.dim_kpi
               SET indicator           = v_indicator,
                   indicator_frequency = v_freq,
                   indicator_start     = v_start,
                   definition          = v_defn,
                   lin_business_hash   = v_new_hash,
                   lin_load_batch_id   = p_batch_id,
                   lin_source_file     = p_source_file
             WHERE source_kpi_id = v_src_id AND kpi_group = v_group AND scd_is_current = true;

            v_updated := v_updated + 1;
        END IF;
    END LOOP;

    RETURN jsonb_build_object(
        'status',        'SUCCESS',
        'total',         v_total,
        'rows_inserted', v_inserted,
        'rows_updated',  v_updated,
        'rows_skipped',  v_skipped
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('status', 'FAILED', 'error', SQLERRM);
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.kpi_definitions_load(TEXT, JSONB, TEXT, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_warehouse.kpi_definitions_load(TEXT, JSONB, TEXT, TEXT) TO authenticated;

-- ── 3. kpi_upload_all: precheck and fact join scoped to (source_kpi_id, kpi_group) ──

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_upload_all(
    p_batch_id    TEXT,
    p_year        INTEGER,
    p_source_file TEXT,
    p_uploaded_by TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path   = rep_warehouse, rep_staging, rep_raw, public
SET statement_timeout = 0
AS $$
DECLARE
    v_row_count         INTEGER := 0;
    v_total_staged      INTEGER := 0;
    v_rows_loaded       INTEGER := 0;
    v_rows_dup          INTEGER := 0;
    v_missing_countries TEXT;
    v_missing_kpis      TEXT;
    v_update_quarter    TEXT;
BEGIN
    PERFORM set_config('app.batch_id',      p_batch_id,        true);
    PERFORM set_config('app.source_system', 'Excel_CAMFED',    true);
    PERFORM set_config('app.source_file',   p_source_file,     true);

    -- One successful upload per year
    IF EXISTS (
        SELECT 1 FROM rep_raw.upload_log
        WHERE year = p_year AND status = 'SUCCESS'
    ) THEN
        INSERT INTO rep_raw.upload_log
            (batch_id, year, row_count, rows_loaded, rows_unmatched, rows_duplicate,
             status, error_msg, uploaded_by, source_file)
        VALUES
            (p_batch_id, p_year, 0, 0, 0, 0, 'FAILED',
             format('Year %s already has a successful upload. Delete the existing data before uploading again.', p_year),
             p_uploaded_by, p_source_file);

        RETURN jsonb_build_object(
            'status', 'FAILED',
            'error',  format('Year %s already has a successful upload. Delete the existing data before uploading again.', p_year)
        );
    END IF;

    SELECT COUNT(*) INTO v_row_count
    FROM rep_raw.all_kpis
    WHERE batch_id = p_batch_id
      AND year_of_kpis IS NOT NULL
      AND year_of_kpis::integer = p_year;

    -- Capture distinct update_quarter values from this batch
    SELECT STRING_AGG(DISTINCT update_quarter, ', ' ORDER BY update_quarter)
    INTO v_update_quarter
    FROM rep_raw.all_kpis
    WHERE batch_id = p_batch_id
      AND update_quarter IS NOT NULL
      AND year_of_kpis IS NOT NULL
      AND year_of_kpis::integer = p_year;

    -- Rebuild all_kpis staging from all raw rows
    PERFORM rep_warehouse.etl_stage_all_kpis();

    -- Geography pre-check (batch-scoped)
    SELECT STRING_AGG(DISTINCT s.country, ', ' ORDER BY s.country)
    INTO v_missing_countries
    FROM rep_staging.all_kpis s
    INNER JOIN rep_raw.all_kpis r ON r.row_id = s.row_id AND r.batch_id = p_batch_id
    WHERE s.year = p_year
      AND LOWER(s.country) != 'total'
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_geography g
          WHERE g.country = s.country AND g.province IS NULL AND g.district IS NULL
      );

    IF v_missing_countries IS NOT NULL THEN
        INSERT INTO rep_raw.upload_log
            (batch_id, year, row_count, rows_loaded, rows_unmatched, rows_duplicate,
             status, error_msg, uploaded_by, source_file)
        VALUES
            (p_batch_id, p_year, v_row_count, 0, 0, 0, 'FAILED',
             'Countries not found in geography dimension (run Salesforce ingest first): ' || v_missing_countries,
             p_uploaded_by, p_source_file);

        RETURN jsonb_build_object(
            'status', 'FAILED',
            'error',  'Countries not found in geography dimension (run Salesforce ingest first): ' || v_missing_countries
        );
    END IF;

    -- KPI pre-check (batch-scoped, matched on kpi_no + group)
    SELECT STRING_AGG(DISTINCT r.kpi_no || ' / ' || r.indicator_group, ', ' ORDER BY r.kpi_no || ' / ' || r.indicator_group)
    INTO v_missing_kpis
    FROM rep_raw.all_kpis r
    WHERE r.batch_id = p_batch_id
      AND r.kpi_no IS NOT NULL
      AND r.year_of_kpis IS NOT NULL
      AND r.year_of_kpis::integer = p_year
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_kpi dk
          WHERE dk.source_kpi_id = r.kpi_no AND dk.kpi_group = r.indicator_group AND dk.scd_is_current = true
      );

    IF v_missing_kpis IS NOT NULL THEN
        INSERT INTO rep_raw.upload_log
            (batch_id, year, row_count, rows_loaded, rows_unmatched, rows_duplicate,
             status, error_msg, uploaded_by, source_file)
        VALUES
            (p_batch_id, p_year, v_row_count, 0, 0, 0, 'FAILED',
             'KPI ID / group combinations not found in definitions (upload kpi-definitions.xlsx first): ' || v_missing_kpis,
             p_uploaded_by, p_source_file);

        RETURN jsonb_build_object(
            'status', 'FAILED',
            'error',  'KPI ID / group combinations not found in definitions (upload kpi-definitions.xlsx first): ' || v_missing_kpis
        );
    END IF;

    SELECT COUNT(*) INTO v_total_staged
    FROM rep_staging.all_kpis s
    INNER JOIN rep_raw.all_kpis r ON r.row_id = s.row_id AND r.batch_id = p_batch_id
    WHERE s.year = p_year;

    -- Duplicate detection: exact match on all data columns (countries compared as JSONB text).
    INSERT INTO rep_raw.duplicate_rows
        (batch_id, kpi_id, kpi_group, year,
         disaggregation_level_one, disaggregation_level_two,
         row_scope, occurrences, row_ids)
    SELECT
        p_batch_id,
        kpi_no,
        indicator_group,
        year_of_kpis::integer,
        disaggregation1,
        disaggregation2,
        CASE
            WHEN disaggregation1 ILIKE '%cumulative%'
              OR disaggregation2 ILIKE '%cumulative%'                     THEN 'CUMULATIVE'
            WHEN disaggregation2 ILIKE 'benchmark'
              OR disaggregation2 ILIKE '%poverty line%'                   THEN 'BENCHMARK'
            WHEN disaggregation1 = 'Total'
              OR disaggregation2 = 'Total'
              OR disaggregation2 ILIKE '%total'
              OR disaggregation2 ILIKE 'overall'
              OR disaggregation2 ILIKE 'combined'
              OR disaggregation2 ILIKE '%total%'                          THEN 'SUBTOTAL'
            WHEN disaggregation1 IN ('Annual','Newly supported','Newly reached',
                                     'New since last year','Annual reach per LG')
              OR disaggregation2 = 'Annual'                               THEN 'ANNUAL'
            ELSE                                                                'DETAIL'
        END,
        COUNT(*),
        array_agg(row_id::text ORDER BY row_id::integer)
    FROM rep_raw.all_kpis
    WHERE batch_id        = p_batch_id
      AND year_of_kpis IS NOT NULL
      AND year_of_kpis::integer = p_year
    GROUP BY
        kpi_no, indicator_group, indicator,
        disaggregation1, disaggregation2,
        value_type, year_of_kpis, updated_date, update_quarter,
        countries::text, total
    HAVING COUNT(*) > 1;

    -- Year-scoped replace (batch-scoped staging join)
    DELETE FROM rep_warehouse.fact_observed_kpi WHERE year = p_year;

    WITH batch_staged AS (
        SELECT s.*
        FROM rep_staging.all_kpis s
        INNER JOIN rep_raw.all_kpis r ON r.row_id = s.row_id AND r.batch_id = p_batch_id
        WHERE s.year = p_year
    ),
    deduped AS (
        SELECT DISTINCT ON (
            s.year, s.country, s.kpi_id, s.kpi_group,
            s.disaggregation_level_one, s.disaggregation_level_two, s.row_scope
        )
            s.row_id, s.year, s.country, s.kpi_id, s.kpi_group,
            s.disaggregation_level_one, s.disaggregation_level_two,
            s.value_type, s.row_scope, s.value, s.updated_date, s.update_quarter
        FROM batch_staged s
        ORDER BY
            s.year, s.country, s.kpi_id, s.kpi_group,
            s.disaggregation_level_one, s.disaggregation_level_two, s.row_scope,
            s.row_id DESC
    )
    INSERT INTO rep_warehouse.fact_observed_kpi
        (kpi_id, geography_id, year, year_date_id,
         disaggregation_level_one, disaggregation_level_two, value_type, row_scope,
         value, updated_date, update_quarter,
         lin_is_current, lin_change_type,
         lin_source_system, lin_source_file, lin_load_batch_id, lin_source_row_number)
    SELECT
        dk.id, dg.id, s.year, dd.id,
        s.disaggregation_level_one, s.disaggregation_level_two,
        s.value_type, s.row_scope, s.value,
        NULLIF(s.updated_date, '')::date,
        s.update_quarter,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        s.row_id
    FROM deduped s
    INNER JOIN rep_warehouse.dim_kpi dk
           ON dk.source_kpi_id = s.kpi_id AND dk.kpi_group = s.kpi_group AND dk.scd_is_current = true
    INNER JOIN rep_warehouse.dim_geography dg
           ON dg.country = s.country AND dg.province IS NULL AND dg.district IS NULL
    LEFT  JOIN rep_warehouse.dim_date dd
           ON dd.id = ((s.year::text || '0101')::integer);

    GET DIAGNOSTICS v_rows_loaded = ROW_COUNT;

    SELECT COALESCE(SUM(occurrences - 1), 0) INTO v_rows_dup
    FROM rep_raw.duplicate_rows
    WHERE batch_id = p_batch_id;

    INSERT INTO rep_raw.upload_log
        (batch_id, year, row_count, rows_loaded, rows_unmatched, rows_duplicate,
         status, update_quarter, uploaded_by, source_file)
    VALUES
        (p_batch_id, p_year, v_row_count, v_rows_loaded, 0, v_rows_dup,
         'SUCCESS', v_update_quarter, p_uploaded_by, p_source_file);

    RETURN jsonb_build_object(
        'status',                 'SUCCESS',
        'batch_id',               p_batch_id,
        'year',                   p_year,
        'total_staged',           v_total_staged,
        'rows_loaded',            v_rows_loaded,
        'rows_unmatched_kpi',     0,
        'rows_skipped_duplicate', v_rows_dup,
        'update_quarter',         v_update_quarter
    );

EXCEPTION WHEN OTHERS THEN
    INSERT INTO rep_raw.upload_log
        (batch_id, year, row_count, rows_loaded, rows_unmatched, rows_duplicate,
         status, error_msg, uploaded_by, source_file)
    VALUES
        (p_batch_id, p_year, 0, 0, 0, 0, 'FAILED', SQLERRM, p_uploaded_by, p_source_file);

    RETURN jsonb_build_object('status', 'FAILED', 'error', SQLERRM);
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.kpi_upload_all(TEXT, INTEGER, TEXT, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_warehouse.kpi_upload_all(TEXT, INTEGER, TEXT, TEXT) TO service_role;


-- ===== 20260714124614_grant_kpi_report_authenticated.sql =====
-- The kpi_report_* RPC chain (added in 20260710102034_whatsapp_kpi_report.sql and
-- patched in later migrations) was granted to service_role only, for the WhatsApp
-- bot. The new frontend "KPI report" page needs to call the rep_portal wrappers
-- directly as an authenticated user, so grant those four (kpi_report_country is
-- district-based and not used by the frontend picker, so left as service_role-only).

GRANT EXECUTE ON FUNCTION rep_portal.kpi_report_years(TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_report_groups(TEXT, INTEGER) TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_report_indicators(TEXT, INTEGER, TEXT) TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_report_indicator_detail(TEXT, INTEGER, TEXT, TEXT) TO authenticated;

-- rep_portal.kpi_report_indicators / kpi_report_indicator_detail each wrap their
-- rep_warehouse counterpart with a bare `SELECT * FROM fn(...)` and no ORDER BY
-- at the outer level. For kpi_report_indicator_detail this matters: row order
-- IS the source spreadsheet's row order (lin_source_row_number, per
-- 20260712075556_kpi_report_order_by_kpi_id_and_row_number.sql), and neither
-- the frontend nor the WhatsApp bot re-sorts it — they render rows as
-- received. PostgreSQL does not guarantee that a nested function call's
-- internal ORDER BY survives through an outer SELECT with no ORDER BY of its
-- own, and PostgREST serializes rows independently of planner internals.
-- Pin the order explicitly with WITH ORDINALITY so the guarantee holds
-- regardless of query-plan choices.

CREATE OR REPLACE FUNCTION rep_portal.kpi_report_indicators(p_country TEXT, p_year INTEGER, p_kpi_group TEXT)
RETURNS TABLE (indicator TEXT, short_label TEXT, source_kpi_id TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT indicator, short_label, source_kpi_id
  FROM rep_warehouse.kpi_report_indicators(p_country, p_year, p_kpi_group)
       WITH ORDINALITY AS t(indicator, short_label, source_kpi_id, ord)
  ORDER BY ord;
$$;

CREATE OR REPLACE FUNCTION rep_portal.kpi_report_indicator_detail(p_country TEXT, p_year INTEGER, p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  value_type TEXT,
  value TEXT,
  definition TEXT,
  source_kpi_id TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT disaggregation_level_one, disaggregation_level_two, value_type, value, definition, source_kpi_id
  FROM rep_warehouse.kpi_report_indicator_detail(p_country, p_year, p_kpi_group, p_indicator)
       WITH ORDINALITY AS t(disaggregation_level_one, disaggregation_level_two, value_type, value, definition, source_kpi_id, ord)
  ORDER BY ord;
$$;


-- ===== 20260714140053_add_kpi_report_indicator_trend.sql =====
-- Adds kpi_report_indicator_trend: given a country/kpi_group/indicator, returns
-- every (year, disaggregation_level_one, disaggregation_level_two) value across
-- every year on file, for the frontend KPI report page's trend sparklines.
--
-- Only ANNUAL and DETAIL row_scope rows are included — those are genuinely
-- independent per-year measurements. CUMULATIVE/SUBTOTAL rows are running
-- totals recalculated on every upload, so a multi-year line of those would
-- just show monotonic growth and can include revised-history artifacts; the
-- frontend shows those as a single "as of latest year" figure instead.
--
-- Dedup mirrors kpi_report_indicator_detail (20260712075556_...): within a
-- given year, the same duplicate-fact-key issue can occur, so DISTINCT ON the
-- content columns per year, picking the earliest lin_source_row_number.

CREATE FUNCTION rep_warehouse.kpi_report_indicator_trend(p_country TEXT, p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  year INTEGER,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  value_type TEXT,
  value TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT year, disaggregation_level_one, disaggregation_level_two, value_type, value
  FROM (
    SELECT DISTINCT ON (year, disaggregation_level_one, disaggregation_level_two, value_type, value)
      year, disaggregation_level_one, disaggregation_level_two, value_type, value, lin_source_row_number
    FROM rep_warehouse.view_observed_kpi
    WHERE country = p_country AND kpi_group = p_kpi_group AND indicator = p_indicator
      AND row_scope IN ('ANNUAL', 'DETAIL')
    ORDER BY year, disaggregation_level_one, disaggregation_level_two, value_type, value, lin_source_row_number
  ) deduped
  ORDER BY year, lin_source_row_number;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.kpi_report_indicator_trend(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_warehouse.kpi_report_indicator_trend(TEXT, TEXT, TEXT) TO service_role;

-- rep_portal wrapper, pinned to authenticated (frontend caller — no bot usage
-- yet). Uses WITH ORDINALITY for the same reason as the other kpi_report_*
-- wrappers (20260714124614_grant_kpi_report_authenticated.sql): a bare
-- `SELECT * FROM fn(...)` gives no ordering guarantee through the wrapper.
CREATE FUNCTION rep_portal.kpi_report_indicator_trend(p_country TEXT, p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  year INTEGER,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  value_type TEXT,
  value TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT year, disaggregation_level_one, disaggregation_level_two, value_type, value
  FROM rep_warehouse.kpi_report_indicator_trend(p_country, p_kpi_group, p_indicator)
       WITH ORDINALITY AS t(year, disaggregation_level_one, disaggregation_level_two, value_type, value, ord)
  ORDER BY ord;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_report_indicator_trend(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_report_indicator_trend(TEXT, TEXT, TEXT) TO authenticated;


-- ===== 20260714143342_add_kpi_report_indicator_trend_all_countries.sql =====
-- Cross-country variant of kpi_report_indicator_trend (20260714140053_...):
-- given a kpi_group/indicator (no country filter), returns every country's
-- year/disaggregation values on file, for the frontend Trends page's
-- "By Indicator" cross-country comparison view.
--
-- Same ANNUAL/DETAIL-only row_scope restriction and dedup pattern as the
-- single-country version — see that migration for the reasoning.

CREATE FUNCTION rep_warehouse.kpi_report_indicator_trend_all_countries(p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  country TEXT,
  year INTEGER,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  value_type TEXT,
  value TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT country, year, disaggregation_level_one, disaggregation_level_two, value_type, value
  FROM (
    SELECT DISTINCT ON (country, year, disaggregation_level_one, disaggregation_level_two, value_type, value)
      country, year, disaggregation_level_one, disaggregation_level_two, value_type, value, lin_source_row_number
    FROM rep_warehouse.view_observed_kpi
    WHERE kpi_group = p_kpi_group AND indicator = p_indicator
      AND row_scope IN ('ANNUAL', 'DETAIL')
    ORDER BY country, year, disaggregation_level_one, disaggregation_level_two, value_type, value, lin_source_row_number
  ) deduped
  ORDER BY country, year, lin_source_row_number;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.kpi_report_indicator_trend_all_countries(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_warehouse.kpi_report_indicator_trend_all_countries(TEXT, TEXT) TO service_role;

CREATE FUNCTION rep_portal.kpi_report_indicator_trend_all_countries(p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  country TEXT,
  year INTEGER,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  value_type TEXT,
  value TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT country, year, disaggregation_level_one, disaggregation_level_two, value_type, value
  FROM rep_warehouse.kpi_report_indicator_trend_all_countries(p_kpi_group, p_indicator)
       WITH ORDINALITY AS t(country, year, disaggregation_level_one, disaggregation_level_two, value_type, value, ord)
  ORDER BY ord;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_report_indicator_trend_all_countries(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_report_indicator_trend_all_countries(TEXT, TEXT) TO authenticated;


-- ===== 20260714145033_add_kpi_report_all_groups_and_indicators.sql =====
-- kpi_report_groups/kpi_report_indicators are scoped to a specific
-- country+year (they read view_observed_kpi WHERE country=... AND year=...),
-- which is correct for the KPI Report snapshot page but wrong for the Trends
-- page's indicator picker: an indicator a country stopped reporting, or only
-- reported in an earlier year, silently disappears from the list.
--
-- The indicator catalog itself doesn't depend on country or year at all —
-- dim_kpi already holds the full (kpi_group, indicator) catalog independent
-- of what's actually been uploaded. These two RPCs read dim_kpi directly.

CREATE FUNCTION rep_warehouse.kpi_report_all_groups()
RETURNS TABLE (kpi_group TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT DISTINCT kpi_group
  FROM rep_warehouse.dim_kpi
  WHERE scd_is_current = true
  ORDER BY kpi_group;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.kpi_report_all_groups() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_warehouse.kpi_report_all_groups() TO service_role;

CREATE FUNCTION rep_portal.kpi_report_all_groups()
RETURNS TABLE (kpi_group TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT kpi_group
  FROM rep_warehouse.kpi_report_all_groups() WITH ORDINALITY AS t(kpi_group, ord)
  ORDER BY ord;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_report_all_groups() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_report_all_groups() TO authenticated;

CREATE FUNCTION rep_warehouse.kpi_report_all_indicators(p_kpi_group TEXT)
RETURNS TABLE (indicator TEXT, short_label TEXT, source_kpi_id TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT indicator, short_label, source_kpi_id
  FROM rep_warehouse.dim_kpi
  WHERE kpi_group = p_kpi_group AND scd_is_current = true
  ORDER BY source_kpi_id, indicator;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.kpi_report_all_indicators(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_warehouse.kpi_report_all_indicators(TEXT) TO service_role;

CREATE FUNCTION rep_portal.kpi_report_all_indicators(p_kpi_group TEXT)
RETURNS TABLE (indicator TEXT, short_label TEXT, source_kpi_id TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT indicator, short_label, source_kpi_id
  FROM rep_warehouse.kpi_report_all_indicators(p_kpi_group)
       WITH ORDINALITY AS t(indicator, short_label, source_kpi_id, ord)
  ORDER BY ord;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_report_all_indicators(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_report_all_indicators(TEXT) TO authenticated;


-- ===== 20260714161702_add_kpi_milestone_report.sql =====
-- KPI Milestones page: "Number of X" style actual-vs-milestone bar charts,
-- matching CAMFED's own "Spotlight KPIs" deck format — all countries for one
-- indicator/disaggregation/year, no country filter (deck has none either).
--
-- Milestone/actual join nuance (confirmed against the real Spotlight deck
-- numbers): some KPIs set a single combined milestone at
-- disaggregation_level_one = 'Total' while actuals are split into sub-
-- categories (e.g. "CAMFED trained" / "Government trained" for Learner
-- Guides). Matching row-for-row would silently miss those — when the
-- milestone's level_one is 'Total', the actual side must be summed across
-- all level_one values for the same level_two instead of joined 1:1.
--
-- Actuals are deduped per (country, level_one, level_two) by earliest
-- lin_source_row_number first, mirroring kpi_report_indicator_detail's
-- existing dedup approach, before any rollup — otherwise a known duplicate
-- fact key would double-count under the 'Total' sum path.

CREATE FUNCTION rep_warehouse.kpi_milestone_years()
RETURNS TABLE (year INTEGER)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT DISTINCT year
  FROM rep_warehouse.fact_kpi_milestone
  ORDER BY year DESC;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.kpi_milestone_years() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_warehouse.kpi_milestone_years() TO service_role;

CREATE FUNCTION rep_portal.kpi_milestone_years()
RETURNS TABLE (year INTEGER)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT year
  FROM rep_warehouse.kpi_milestone_years() WITH ORDINALITY AS t(year, ord)
  ORDER BY ord;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_milestone_years() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_milestone_years() TO authenticated;

CREATE FUNCTION rep_warehouse.kpi_milestone_report(p_year INTEGER, p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  country TEXT,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  milestone_value NUMERIC,
  actual_value NUMERIC,
  value_type TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  WITH milestone AS (
    SELECT g.country, fm.disaggregation_level_one AS d1, fm.disaggregation_level_two AS d2,
           fm.value AS milestone_value, fm.value_type
    FROM rep_warehouse.fact_kpi_milestone fm
    JOIN rep_warehouse.dim_kpi k ON k.id = fm.kpi_id AND k.scd_is_current = true
    JOIN rep_warehouse.dim_geography g ON g.id = fm.geography_id
    WHERE fm.year = p_year AND k.kpi_group = p_kpi_group AND k.indicator = p_indicator
  ),
  actual_raw AS (
    SELECT a.country, a.disaggregation_level_one AS d1, a.disaggregation_level_two AS d2,
           a.value, a.lin_source_row_number
    FROM rep_warehouse.view_observed_kpi a
    WHERE a.kpi_group = p_kpi_group AND a.indicator = p_indicator AND a.year = p_year
      AND a.row_scope IN ('ANNUAL', 'DETAIL')
      AND a.value ~ '^-?[0-9.]+$'
  ),
  actual_dedup AS (
    SELECT DISTINCT ON (country, d1, d2) country, d1, d2, value::NUMERIC AS value
    FROM actual_raw
    ORDER BY country, d1, d2, lin_source_row_number
  ),
  actual_rollup AS (
    SELECT country, d2, SUM(value) AS total_value
    FROM actual_dedup
    GROUP BY country, d2
  )
  SELECT m.country, m.d1, m.d2, m.milestone_value,
    CASE WHEN m.d1 = 'Total' THEN ar.total_value ELSE ad.value END AS actual_value,
    m.value_type
  FROM milestone m
  LEFT JOIN actual_rollup ar ON ar.country = m.country AND ar.d2 = m.d2 AND m.d1 = 'Total'
  LEFT JOIN actual_dedup ad ON ad.country = m.country AND ad.d1 = m.d1 AND ad.d2 = m.d2 AND m.d1 <> 'Total'
  ORDER BY m.d1, m.d2, m.country;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.kpi_milestone_report(INTEGER, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_warehouse.kpi_milestone_report(INTEGER, TEXT, TEXT) TO service_role;

CREATE FUNCTION rep_portal.kpi_milestone_report(p_year INTEGER, p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  country TEXT,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  milestone_value NUMERIC,
  actual_value NUMERIC,
  value_type TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT country, disaggregation_level_one, disaggregation_level_two, milestone_value, actual_value, value_type
  FROM rep_warehouse.kpi_milestone_report(p_year, p_kpi_group, p_indicator)
       WITH ORDINALITY AS t(country, disaggregation_level_one, disaggregation_level_two, milestone_value, actual_value, value_type, ord)
  ORDER BY ord;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_milestone_report(INTEGER, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_milestone_report(INTEGER, TEXT, TEXT) TO authenticated;


-- ===== 20260714161924_fix_kpi_milestone_report_include_actual_only_countries.sql =====
-- kpi_milestone_report previously drove the result set from the milestone
-- side only (LEFT JOIN actual), so a country reporting actual data but with
-- no milestone at all (e.g. Kenya, a newer market not yet given IP targets)
-- was silently omitted. The Spotlight deck shows Kenya's actual with an
-- explicit "N/A" milestone instead of hiding the country — match that.
--
-- Now driven from the union of every country appearing in either milestone
-- or actual data for this indicator/year, crossed with the distinct
-- disaggregation "slides" (level_one, level_two) the milestone side defines,
-- and only kept where at least one side has a value.

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_milestone_report(p_year INTEGER, p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  country TEXT,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  milestone_value NUMERIC,
  actual_value NUMERIC,
  value_type TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  WITH milestone AS (
    SELECT g.country, fm.disaggregation_level_one AS d1, fm.disaggregation_level_two AS d2,
           fm.value AS milestone_value, fm.value_type
    FROM rep_warehouse.fact_kpi_milestone fm
    JOIN rep_warehouse.dim_kpi k ON k.id = fm.kpi_id AND k.scd_is_current = true
    JOIN rep_warehouse.dim_geography g ON g.id = fm.geography_id
    WHERE fm.year = p_year AND k.kpi_group = p_kpi_group AND k.indicator = p_indicator
  ),
  milestone_keys AS (
    SELECT DISTINCT ON (d1, d2) d1, d2, value_type
    FROM milestone
    ORDER BY d1, d2
  ),
  actual_raw AS (
    SELECT a.country, a.disaggregation_level_one AS d1, a.disaggregation_level_two AS d2,
           a.value, a.lin_source_row_number
    FROM rep_warehouse.view_observed_kpi a
    WHERE a.kpi_group = p_kpi_group AND a.indicator = p_indicator AND a.year = p_year
      AND a.row_scope IN ('ANNUAL', 'DETAIL')
      AND a.value ~ '^-?[0-9.]+$'
  ),
  actual_dedup AS (
    SELECT DISTINCT ON (country, d1, d2) country, d1, d2, value::NUMERIC AS value
    FROM actual_raw
    ORDER BY country, d1, d2, lin_source_row_number
  ),
  actual_rollup AS (
    SELECT country, d2, SUM(value) AS total_value
    FROM actual_dedup
    GROUP BY country, d2
  ),
  all_countries AS (
    SELECT country FROM milestone
    UNION
    SELECT country FROM actual_dedup
  ),
  combos AS (
    SELECT c.country, k.d1, k.d2, k.value_type
    FROM all_countries c CROSS JOIN milestone_keys k
  )
  SELECT co.country, co.d1, co.d2, m.milestone_value,
    CASE WHEN co.d1 = 'Total' THEN ar.total_value ELSE ad.value END AS actual_value,
    co.value_type
  FROM combos co
  LEFT JOIN milestone m ON m.country = co.country AND m.d1 = co.d1 AND m.d2 = co.d2
  LEFT JOIN actual_rollup ar ON ar.country = co.country AND ar.d2 = co.d2 AND co.d1 = 'Total'
  LEFT JOIN actual_dedup ad ON ad.country = co.country AND ad.d1 = co.d1 AND ad.d2 = co.d2 AND co.d1 <> 'Total'
  WHERE m.milestone_value IS NOT NULL
     OR (CASE WHEN co.d1 = 'Total' THEN ar.total_value ELSE ad.value END) IS NOT NULL
  ORDER BY co.d1, co.d2, co.country;
$$;


-- ===== 20260714162959_fix_kpi_milestone_report_include_subtotal_rows.sql =====
-- kpi_milestone_report was filtering actuals to row_scope IN ('ANNUAL','DETAIL'),
-- carried over from the Trends page where that filter prevents double-counting
-- when *aggregating* multiple disaggregation rows into one multi-year line.
--
-- Milestone comparison does the opposite: it looks up the ONE actual row whose
-- disaggregation label matches what the milestone itself defines (or sums a
-- 'Total' rollup), so there's no double-counting risk from including SUBTOTAL
-- rows. Excluding them was wrong — many KPIs set their milestone against a
-- combined "Girls Total"-style SUBTOTAL row (e.g. "Number of girls receiving
-- CAMFED bursary support": milestone disaggregation is Annual / Girls Total,
-- and the matching actual row is also Annual / Girls Total, but classified
-- SUBTOTAL because its disaggregation text contains "Total"). Dropping the
-- row_scope filter — every ETL-classified scope is fair game for an exact or
-- 'Total'-rollup disaggregation match here.

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_milestone_report(p_year INTEGER, p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  country TEXT,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  milestone_value NUMERIC,
  actual_value NUMERIC,
  value_type TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  WITH milestone AS (
    SELECT g.country, fm.disaggregation_level_one AS d1, fm.disaggregation_level_two AS d2,
           fm.value AS milestone_value, fm.value_type
    FROM rep_warehouse.fact_kpi_milestone fm
    JOIN rep_warehouse.dim_kpi k ON k.id = fm.kpi_id AND k.scd_is_current = true
    JOIN rep_warehouse.dim_geography g ON g.id = fm.geography_id
    WHERE fm.year = p_year AND k.kpi_group = p_kpi_group AND k.indicator = p_indicator
  ),
  milestone_keys AS (
    SELECT DISTINCT ON (d1, d2) d1, d2, value_type
    FROM milestone
    ORDER BY d1, d2
  ),
  actual_raw AS (
    SELECT a.country, a.disaggregation_level_one AS d1, a.disaggregation_level_two AS d2,
           a.value, a.lin_source_row_number
    FROM rep_warehouse.view_observed_kpi a
    WHERE a.kpi_group = p_kpi_group AND a.indicator = p_indicator AND a.year = p_year
      AND a.value ~ '^-?[0-9.]+$'
  ),
  actual_dedup AS (
    SELECT DISTINCT ON (country, d1, d2) country, d1, d2, value::NUMERIC AS value
    FROM actual_raw
    ORDER BY country, d1, d2, lin_source_row_number
  ),
  actual_rollup AS (
    SELECT country, d2, SUM(value) AS total_value
    FROM actual_dedup
    GROUP BY country, d2
  ),
  all_countries AS (
    SELECT country FROM milestone
    UNION
    SELECT country FROM actual_dedup
  ),
  combos AS (
    SELECT c.country, k.d1, k.d2, k.value_type
    FROM all_countries c CROSS JOIN milestone_keys k
  )
  SELECT co.country, co.d1, co.d2, m.milestone_value,
    CASE WHEN co.d1 = 'Total' THEN ar.total_value ELSE ad.value END AS actual_value,
    co.value_type
  FROM combos co
  LEFT JOIN milestone m ON m.country = co.country AND m.d1 = co.d1 AND m.d2 = co.d2
  LEFT JOIN actual_rollup ar ON ar.country = co.country AND ar.d2 = co.d2 AND co.d1 = 'Total'
  LEFT JOIN actual_dedup ad ON ad.country = co.country AND ad.d1 = co.d1 AND ad.d2 = co.d2 AND co.d1 <> 'Total'
  WHERE m.milestone_value IS NOT NULL
     OR (CASE WHEN co.d1 = 'Total' THEN ar.total_value ELSE ad.value END) IS NOT NULL
  ORDER BY co.d1, co.d2, co.country;
$$;


-- ===== 20260714163202_fix_kpi_milestone_report_normalize_disaggregation_matching.sql =====
-- Two more real matching gaps found by comparing every milestone-defined
-- indicator against its actual disaggregation vocabulary:
--
-- 1. disaggregation_level_two is sometimes literally the string '0' on the
--    actual side, meaning "no second disaggregation" (same placeholder
--    already handled by disaggregationLabel() in the frontend), while the
--    matching milestone row correctly has a NULL level_two. Exact string
--    equality treated '0' <> NULL as a mismatch. Normalize '0' to NULL
--    before comparing.
-- 2. "Number of girls supported to go to school by CAMA and community
--    support": milestone stores level_two as "Girls total", actual stores
--    it as "Girls Total" — a case difference. Compare case-insensitively.
--
-- Matching now happens on a normalized (lower/trim, '0' -> NULL) key on
-- both country/level_one/level_two, while the milestone's original casing
-- is still what gets returned/displayed.

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_milestone_report(p_year INTEGER, p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  country TEXT,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  milestone_value NUMERIC,
  actual_value NUMERIC,
  value_type TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  WITH milestone AS (
    SELECT g.country, fm.disaggregation_level_one AS d1, fm.disaggregation_level_two AS d2,
           fm.value AS milestone_value, fm.value_type
    FROM rep_warehouse.fact_kpi_milestone fm
    JOIN rep_warehouse.dim_kpi k ON k.id = fm.kpi_id AND k.scd_is_current = true
    JOIN rep_warehouse.dim_geography g ON g.id = fm.geography_id
    WHERE fm.year = p_year AND k.kpi_group = p_kpi_group AND k.indicator = p_indicator
  ),
  milestone_keys AS (
    SELECT DISTINCT ON (d1, d2) d1, d2, value_type,
      lower(trim(d1)) AS mk_d1, NULLIF(lower(trim(d2)), '0') AS mk_d2
    FROM milestone
    ORDER BY d1, d2
  ),
  actual_raw AS (
    SELECT a.country, a.disaggregation_level_one AS d1, a.disaggregation_level_two AS d2,
           a.value, a.lin_source_row_number
    FROM rep_warehouse.view_observed_kpi a
    WHERE a.kpi_group = p_kpi_group AND a.indicator = p_indicator AND a.year = p_year
      AND a.value ~ '^-?[0-9.]+$'
  ),
  actual_dedup AS (
    SELECT DISTINCT ON (country, mk_d1, mk_d2) country, mk_d1, mk_d2, value::NUMERIC AS value
    FROM (
      SELECT *, lower(trim(d1)) AS mk_d1, NULLIF(lower(trim(d2)), '0') AS mk_d2
      FROM actual_raw
    ) x
    ORDER BY country, mk_d1, mk_d2, lin_source_row_number
  ),
  actual_rollup AS (
    SELECT country, mk_d2, SUM(value) AS total_value
    FROM actual_dedup
    GROUP BY country, mk_d2
  ),
  all_countries AS (
    SELECT country FROM milestone
    UNION
    SELECT country FROM actual_dedup
  ),
  combos AS (
    SELECT c.country, k.d1, k.d2, k.value_type, k.mk_d1, k.mk_d2
    FROM all_countries c CROSS JOIN milestone_keys k
  )
  SELECT co.country, co.d1, co.d2, m.milestone_value,
    CASE WHEN co.mk_d1 = 'total' THEN ar.total_value ELSE ad.value END AS actual_value,
    co.value_type
  FROM combos co
  LEFT JOIN milestone m ON m.country = co.country AND lower(trim(m.d1)) = co.mk_d1
    AND COALESCE(NULLIF(lower(trim(m.d2)), '0'), '') = COALESCE(co.mk_d2, '')
  LEFT JOIN actual_rollup ar ON ar.country = co.country
    AND COALESCE(ar.mk_d2, '') = COALESCE(co.mk_d2, '') AND co.mk_d1 = 'total'
  LEFT JOIN actual_dedup ad ON ad.country = co.country AND ad.mk_d1 = co.mk_d1
    AND COALESCE(ad.mk_d2, '') = COALESCE(co.mk_d2, '') AND co.mk_d1 <> 'total'
  WHERE m.milestone_value IS NOT NULL
     OR (CASE WHEN co.mk_d1 = 'total' THEN ar.total_value ELSE ad.value END) IS NOT NULL
  ORDER BY co.d1, co.d2, co.country;
$$;


-- ===== 20260714163706_add_kpi_milestone_groups_and_indicators.sql =====
-- The KPI Milestones page's group/indicator picker must only surface
-- indicators that actually have a milestone set — most of the KPI catalog
-- (from kpi_report_all_groups/kpi_report_all_indicators) has no milestone at
-- all, which would otherwise list an indicator only to show every country as
-- "N/A" once selected. Scope both the group tabs and the indicator list to
-- dim_kpi rows that have at least one fact_kpi_milestone row.

CREATE FUNCTION rep_warehouse.kpi_milestone_groups()
RETURNS TABLE (kpi_group TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT DISTINCT k.kpi_group
  FROM rep_warehouse.dim_kpi k
  WHERE k.scd_is_current = true
    AND EXISTS (SELECT 1 FROM rep_warehouse.fact_kpi_milestone fm WHERE fm.kpi_id = k.id)
  ORDER BY k.kpi_group;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.kpi_milestone_groups() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_warehouse.kpi_milestone_groups() TO service_role;

CREATE FUNCTION rep_portal.kpi_milestone_groups()
RETURNS TABLE (kpi_group TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT kpi_group
  FROM rep_warehouse.kpi_milestone_groups() WITH ORDINALITY AS t(kpi_group, ord)
  ORDER BY ord;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_milestone_groups() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_milestone_groups() TO authenticated;

CREATE FUNCTION rep_warehouse.kpi_milestone_indicators(p_kpi_group TEXT)
RETURNS TABLE (indicator TEXT, short_label TEXT, source_kpi_id TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  SELECT DISTINCT k.indicator, k.short_label, k.source_kpi_id
  FROM rep_warehouse.dim_kpi k
  WHERE k.kpi_group = p_kpi_group AND k.scd_is_current = true
    AND EXISTS (SELECT 1 FROM rep_warehouse.fact_kpi_milestone fm WHERE fm.kpi_id = k.id)
  ORDER BY k.source_kpi_id, k.indicator;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.kpi_milestone_indicators(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_warehouse.kpi_milestone_indicators(TEXT) TO service_role;

CREATE FUNCTION rep_portal.kpi_milestone_indicators(p_kpi_group TEXT)
RETURNS TABLE (indicator TEXT, short_label TEXT, source_kpi_id TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT indicator, short_label, source_kpi_id
  FROM rep_warehouse.kpi_milestone_indicators(p_kpi_group)
       WITH ORDINALITY AS t(indicator, short_label, source_kpi_id, ord)
  ORDER BY ord;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_milestone_indicators(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_milestone_indicators(TEXT) TO authenticated;


-- ===== 20260714170028_fix_kpi_milestone_report_avoid_double_counting_total_row.sql =====
-- Double-counting bug found on "Number of Learner Guides" (newly trained):
-- the actual side already has its own pre-aggregated 'Total' disaggregation
-- row (CAMFED trained 3,248 + Government trained 122 = Total 3,370 for
-- Ghana 2025), but the 'Total'-rollup path summed EVERY disaggregation_level_one
-- value for the matching level_two — including that pre-aggregated Total row
-- on top of its own components (3,248 + 122 + 3,370 = 6,740, exactly double
-- the correct 3,370).
--
-- Fix: when the milestone's level_one is 'Total', prefer an exact actual
-- 'Total' row if the source data already has one; only fall back to summing
-- the non-Total component rows when no pre-aggregated Total row exists on
-- the actual side (the case that motivated the rollup in the first place,
-- e.g. CAMA membership milestones with no matching 'Total' actual row).

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_milestone_report(p_year INTEGER, p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  country TEXT,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  milestone_value NUMERIC,
  actual_value NUMERIC,
  value_type TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
  WITH milestone AS (
    SELECT g.country, fm.disaggregation_level_one AS d1, fm.disaggregation_level_two AS d2,
           fm.value AS milestone_value, fm.value_type
    FROM rep_warehouse.fact_kpi_milestone fm
    JOIN rep_warehouse.dim_kpi k ON k.id = fm.kpi_id AND k.scd_is_current = true
    JOIN rep_warehouse.dim_geography g ON g.id = fm.geography_id
    WHERE fm.year = p_year AND k.kpi_group = p_kpi_group AND k.indicator = p_indicator
  ),
  milestone_keys AS (
    SELECT DISTINCT ON (d1, d2) d1, d2, value_type,
      lower(trim(d1)) AS mk_d1, NULLIF(lower(trim(d2)), '0') AS mk_d2
    FROM milestone
    ORDER BY d1, d2
  ),
  actual_raw AS (
    SELECT a.country, a.disaggregation_level_one AS d1, a.disaggregation_level_two AS d2,
           a.value, a.lin_source_row_number
    FROM rep_warehouse.view_observed_kpi a
    WHERE a.kpi_group = p_kpi_group AND a.indicator = p_indicator AND a.year = p_year
      AND a.value ~ '^-?[0-9.]+$'
  ),
  actual_dedup AS (
    SELECT DISTINCT ON (country, mk_d1, mk_d2) country, mk_d1, mk_d2, value::NUMERIC AS value
    FROM (
      SELECT *, lower(trim(d1)) AS mk_d1, NULLIF(lower(trim(d2)), '0') AS mk_d2
      FROM actual_raw
    ) x
    ORDER BY country, mk_d1, mk_d2, lin_source_row_number
  ),
  actual_rollup AS (
    SELECT country, mk_d2,
      MAX(value) FILTER (WHERE mk_d1 = 'total') AS exact_total_value,
      SUM(value) FILTER (WHERE mk_d1 <> 'total') AS components_sum
    FROM actual_dedup
    GROUP BY country, mk_d2
  ),
  all_countries AS (
    SELECT country FROM milestone
    UNION
    SELECT country FROM actual_dedup
  ),
  combos AS (
    SELECT c.country, k.d1, k.d2, k.value_type, k.mk_d1, k.mk_d2
    FROM all_countries c CROSS JOIN milestone_keys k
  )
  SELECT co.country, co.d1, co.d2, m.milestone_value,
    CASE WHEN co.mk_d1 = 'total' THEN COALESCE(ar.exact_total_value, ar.components_sum) ELSE ad.value END AS actual_value,
    co.value_type
  FROM combos co
  LEFT JOIN milestone m ON m.country = co.country AND lower(trim(m.d1)) = co.mk_d1
    AND COALESCE(NULLIF(lower(trim(m.d2)), '0'), '') = COALESCE(co.mk_d2, '')
  LEFT JOIN actual_rollup ar ON ar.country = co.country
    AND COALESCE(ar.mk_d2, '') = COALESCE(co.mk_d2, '') AND co.mk_d1 = 'total'
  LEFT JOIN actual_dedup ad ON ad.country = co.country AND ad.mk_d1 = co.mk_d1
    AND COALESCE(ad.mk_d2, '') = COALESCE(co.mk_d2, '') AND co.mk_d1 <> 'total'
  WHERE m.milestone_value IS NOT NULL
     OR (CASE WHEN co.mk_d1 = 'total' THEN COALESCE(ar.exact_total_value, ar.components_sum) ELSE ad.value END) IS NOT NULL
  ORDER BY co.d1, co.d2, co.country;
$$;


-- ===== 20260714170858_add_dashlet_comments.sql =====
-- Static, admin-editable comment box per dashlet.
--
-- Separate from rep_portal.data_dictionary (KPI definitions, shown on hover
-- via KpiInfoIcon) and rep_portal.kpi_mapping (per-toggle-variant rows, not
-- 1-per-card). Keyed by permission_key so it reuses the existing 1-row-per-
-- dashlet identity in rep_portal.permissions, and so visibility naturally
-- follows whatever hasPermission() gate already wraps the dashlet card.

CREATE TABLE rep_portal.dashlet_comments (
  id             SERIAL PRIMARY KEY,
  permission_key TEXT NOT NULL UNIQUE
    REFERENCES rep_portal.permissions(key) ON DELETE CASCADE,
  comment        TEXT,
  is_enabled     BOOLEAN NOT NULL DEFAULT false,
  updated_by     UUID,
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE rep_portal.dashlet_comments ENABLE ROW LEVEL SECURITY;
-- No policies added — default deny, matching every other rep_portal table.
-- Access is exclusively through the SECURITY DEFINER RPCs below.

CREATE TRIGGER dashlet_comments_updated_at
  BEFORE UPDATE ON rep_portal.dashlet_comments
  FOR EACH ROW EXECUTE FUNCTION rep_portal.set_updated_at();

-- ── Seed — placeholder row for every dashlet permission that exists today ──────

INSERT INTO rep_portal.dashlet_comments (permission_key)
SELECT key FROM rep_portal.permissions WHERE category = 'dashlet';

-- ── Auto-seed trigger — new dashlet permissions get a placeholder row too ──────

CREATE OR REPLACE FUNCTION rep_portal.seed_dashlet_comment()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
BEGIN
  IF NEW.category = 'dashlet' THEN
    INSERT INTO rep_portal.dashlet_comments (permission_key)
    VALUES (NEW.key)
    ON CONFLICT (permission_key) DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.seed_dashlet_comment() FROM PUBLIC;

CREATE TRIGGER permissions_seed_dashlet_comment
  AFTER INSERT ON rep_portal.permissions
  FOR EACH ROW EXECUTE FUNCTION rep_portal.seed_dashlet_comment();

-- ── Read RPC — used by the dashboard to populate comment boxes ─────────────────

CREATE OR REPLACE FUNCTION rep_portal.get_dashlet_comments()
RETURNS TABLE (
  permission_key TEXT,
  comment        TEXT,
  updated_at     TIMESTAMPTZ
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
  SELECT permission_key, comment, updated_at
  FROM rep_portal.dashlet_comments
  WHERE is_enabled = true
    AND comment IS NOT NULL;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_dashlet_comments() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_dashlet_comments() TO authenticated;

-- ── Write RPC — used by the (future) admin UI to edit comments ─────────────────

CREATE OR REPLACE FUNCTION rep_portal.set_dashlet_comment(
  p_permission_key TEXT,
  p_comment        TEXT,
  p_is_enabled     BOOLEAN
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  UPDATE rep_portal.dashlet_comments
  SET comment    = p_comment,
      is_enabled = p_is_enabled,
      updated_by = auth.uid()
  WHERE permission_key = p_permission_key;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'unknown permission_key: %', p_permission_key;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.set_dashlet_comment(TEXT, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.set_dashlet_comment(TEXT, TEXT, BOOLEAN) TO authenticated;


-- ===== 20260714171530_get_missing_kpi_definitions.sql =====
-- Surfaces dashlets whose kpi_id has no current definition in rep_warehouse.dim_kpi.
--
-- dim_kpi is only populated by uploading kpi-definitions.xlsx through the admin
-- portal (frontend/src/routes/admin/kpis.tsx) -- there's no automatic seeding
-- the way there is for rep_portal.dashlet_comments (see seed_dashlet_comment()
-- trigger, migration 20260714170858). A KpiInfoIcon with no matching dim_kpi
-- row just silently renders nothing, so this report is the only way to know
-- a definition is missing rather than simply not written yet.
--
-- rep_portal.kpi_mapping is used as the source of "which kpi_ids are actually
-- wired to a dashlet" since that mapping only otherwise exists as scattered
-- kpiId="..." props in frontend .tsx files, not in any queryable table.

CREATE OR REPLACE FUNCTION rep_portal.get_missing_kpi_definitions()
RETURNS TABLE (
  kpi_id         TEXT,
  dashboard_page TEXT,
  data_element   TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, pg_temp
AS $$
  SELECT DISTINCT km.kpi_id, km.dashboard_page, km.data_element
  FROM rep_portal.kpi_mapping km
  WHERE NOT EXISTS (
    SELECT 1
    FROM rep_warehouse.dim_kpi dk
    WHERE dk.source_kpi_id = km.kpi_id
      AND dk.scd_is_current = true
  )
  ORDER BY km.kpi_id;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_missing_kpi_definitions() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_missing_kpi_definitions() TO authenticated;


-- ===== 20260715075924_add_salesforce_report_config.sql =====
-- Config tables for the Salesforce Report pivot-builder page (/salesforce-report).
--
-- Unlike rep_portal.metric_config (fixed named metrics for Dynamic Data), these
-- tables let an admin curate, per fact table ("report"), which columns are
-- available as group-by/filter dimensions and which measures can be aggregated,
-- each with an editable display alias. report_config itself stays fixed (one row
-- per Salesforce fact view); dimension/measure rows are admin-managed via
-- /admin/salesforce-reports.

CREATE TABLE rep_portal.report_config (
  report_key      TEXT        PRIMARY KEY,
  label           TEXT        NOT NULL,
  source_view     TEXT        NOT NULL,
  year_field      TEXT        NOT NULL,
  geography_level TEXT        NOT NULL CHECK (geography_level IN ('school', 'district')),
  sort_order      INTEGER     NOT NULL DEFAULT 0,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE TABLE rep_portal.report_dimension_config (
  id          SERIAL      PRIMARY KEY,
  report_key  TEXT        NOT NULL REFERENCES rep_portal.report_config(report_key) ON DELETE CASCADE,
  column_name TEXT        NOT NULL,
  label       TEXT        NOT NULL,
  enabled     BOOLEAN     NOT NULL DEFAULT true,
  sort_order  INTEGER     NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (report_key, column_name)
);

CREATE TABLE rep_portal.report_measure_config (
  id          SERIAL      PRIMARY KEY,
  report_key  TEXT        NOT NULL REFERENCES rep_portal.report_config(report_key) ON DELETE CASCADE,
  column_name TEXT,                                    -- NULL for count
  label       TEXT        NOT NULL,
  agg_type    TEXT        NOT NULL CHECK (agg_type IN ('count', 'sum')),
  enabled     BOOLEAN     NOT NULL DEFAULT true,
  sort_order  INTEGER     NOT NULL DEFAULT 0,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  CHECK ((agg_type = 'count' AND column_name IS NULL) OR (agg_type = 'sum' AND column_name IS NOT NULL)),
  UNIQUE (report_key, agg_type, column_name)
);

REVOKE ALL ON rep_portal.report_config           FROM PUBLIC;
REVOKE ALL ON rep_portal.report_dimension_config FROM PUBLIC;
REVOKE ALL ON rep_portal.report_measure_config   FROM PUBLIC;
GRANT SELECT ON rep_portal.report_config           TO authenticated;
GRANT SELECT ON rep_portal.report_dimension_config TO authenticated;
GRANT SELECT ON rep_portal.report_measure_config   TO authenticated;
GRANT ALL    ON rep_portal.report_config           TO service_role;
GRANT ALL    ON rep_portal.report_dimension_config TO service_role;
GRANT ALL    ON rep_portal.report_measure_config   TO service_role;

-- ── Seed: reports ────────────────────────────────────────────────────────────

INSERT INTO rep_portal.report_config (report_key, label, source_view, year_field, geography_level, sort_order) VALUES
('children_supported',  'Children Supported',   'view_children_supported',  'year',            'school',   10),
('guide_assignment',    'Guide Assignment',      'view_guide_assignment',    'joined_year',     'school',   20),
('cama_membership',     'CAMA Membership',       'view_cama_membership',     'join_year',       'school',   30),
('post_school_support', 'Post-School Support',   'view_post_school_support', 'year',            'district', 40),
('grants',              'Grants',                'view_grants',              'grant_year',      'district', 50),
('loans',               'Loans',                 'view_loans',               'disbursal_year',  'district', 60);

-- ── Seed: dimensions ─────────────────────────────────────────────────────────

INSERT INTO rep_portal.report_dimension_config (report_key, column_name, label, sort_order) VALUES
-- children_supported
('children_supported', 'gender',                        'Gender',                      10),
('children_supported', 'wg_difficulty_overall',          'Disability Status',           20),
('children_supported', 'form',                           'Form',                        30),
('children_supported', 'contact_record_type',            'Contact Record Type',         40),
('children_supported', 'attendance_issues',               'Attendance Issues',          50),
('children_supported', 'received_financial_support',      'Received Financial Support', 60),
('children_supported', 'repeated',                        'Repeated Year',              70),
('children_supported', 'donor_name',                      'Donor',                      80),
('children_supported', 'project_code_name',               'Project Code',               90),
('children_supported', 'school_name',                     'School',                    100),
('children_supported', 'district',                        'District',                  110),
('children_supported', 'province',                        'Province',                  120),
('children_supported', 'country',                         'Country',                   130),
('children_supported', 'year_quarter',                    'Quarter',                   140),

-- guide_assignment
('guide_assignment', 'gender',                            'Gender',                     10),
('guide_assignment', 'wg_difficulty_overall',              'Disability Status',         20),
('guide_assignment', 'guide_type',                         'Guide Type',                30),
('guide_assignment', 'guide_status',                       'Guide Status',              40),
('guide_assignment', 'guide_specialty',                    'Guide Specialty',           50),
('guide_assignment', 'guide_dropout_reason',               'Dropout Reason',            60),
('guide_assignment', 'trained_in_climate_education',       'Trained In Climate Education', 70),
('guide_assignment', 'donor_name',                         'Donor',                     80),
('guide_assignment', 'school_name',                        'School',                    90),
('guide_assignment', 'district',                           'District',                 100),
('guide_assignment', 'province',                           'Province',                 110),
('guide_assignment', 'country',                            'Country',                  120),
('guide_assignment', 'joined_quarter',                     'Quarter Joined',           130),

-- cama_membership
('cama_membership', 'gender',                              'Gender',                    10),
('cama_membership', 'wg_difficulty_overall',                'Disability Status',        20),
('cama_membership', 'partner_school',                      'Partner School',            30),
('cama_membership', 'school_name',                         'School',                    40),
('cama_membership', 'district',                            'District',                  50),
('cama_membership', 'province',                            'Province',                  60),
('cama_membership', 'country',                             'Country',                   70),
('cama_membership', 'join_quarter',                        'Quarter Joined',            80),

-- post_school_support
('post_school_support', 'gender',                          'Gender',                    10),
('post_school_support', 'wg_difficulty_overall',            'Disability Status',        20),
('post_school_support', 'received_financial_support',       'Received Financial Support', 30),
('post_school_support', 'accommodation',                    'Accommodation',            40),
('post_school_support', 'form',                             'Form',                     50),
('post_school_support', 'donor_name',                       'Donor',                    60),
('post_school_support', 'district',                         'District',                 70),
('post_school_support', 'province',                         'Province',                 80),
('post_school_support', 'country',                          'Country',                  90),
('post_school_support', 'year_quarter',                     'Quarter',                 100),

-- grants
('grants', 'gender',                                       'Gender',                    10),
('grants', 'wg_difficulty_overall',                         'Disability Status',        20),
('grants', 'grant_type',                                   'Grant Type',                30),
('grants', 'grant_status',                                 'Grant Status',              40),
('grants', 'donor_name',                                   'Donor',                     50),
('grants', 'district',                                     'District',                  60),
('grants', 'province',                                     'Province',                  70),
('grants', 'country',                                      'Country',                   80),
('grants', 'grant_quarter',                                 'Quarter',                  90),

-- loans
('loans', 'gender',                                        'Gender',                    10),
('loans', 'wg_difficulty_overall',                          'Disability Status',        20),
('loans', 'loan_type',                                     'Loan Type',                 30),
('loans', 'loan_status',                                   'Loan Status',               40),
('loans', 'currency_iso_code',                              'Currency',                 50),
('loans', 'donor_name',                                    'Donor',                     60),
('loans', 'district',                                      'District',                  70),
('loans', 'province',                                      'Province',                  80),
('loans', 'country',                                       'Country',                   90),
('loans', 'disbursal_quarter',                              'Quarter',                 100);

-- ── Seed: measures ───────────────────────────────────────────────────────────

INSERT INTO rep_portal.report_measure_config (report_key, column_name, label, agg_type, sort_order) VALUES
('children_supported',  NULL,             'Count',             'count', 10),
('guide_assignment',    NULL,             'Count',             'count', 10),
('cama_membership',     NULL,             'Count',             'count', 10),
('post_school_support', NULL,             'Count',             'count', 10),
('grants',              NULL,             'Count',             'count', 10),
('grants',              'amount_given',   'Total Value (USD)', 'sum',   20),
('loans',               NULL,             'Count',             'count', 10),
('loans',               'loan_value',     'Total Value',       'sum',   20);


-- ===== 20260715080027_add_salesforce_report_rpcs.sql =====
-- RPCs backing the Salesforce Report pivot-builder page (/salesforce-report) and
-- its admin management page (/admin/salesforce-reports).
--
-- Frontend-facing (any authenticated user): get_report_catalog, get_report_dimension_values,
-- get_report_pivot.
-- Admin-only (rep_warehouse.is_admin()): get_source_view_columns, admin_get_report_config,
-- admin_set_report_dimensions, admin_set_report_measures.
--
-- get_report_pivot builds dynamic SQL the same way rep_portal.get_dashboard_data_filtered
-- does (format() with %I for identifiers), but every identifier is first checked against
-- the report_dimension_config / report_measure_config allow-lists — never interpolated
-- from caller input directly.

-- ── get_report_catalog ────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.get_report_catalog()
RETURNS json
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT json_build_object(
    'reports',
    COALESCE(json_agg(json_build_object(
      'report_key',      r.report_key,
      'label',           r.label,
      'geography_level', r.geography_level,
      'dimensions', (
        SELECT COALESCE(json_agg(json_build_object('column_name', d.column_name, 'label', d.label) ORDER BY d.sort_order, d.label), '[]'::json)
        FROM rep_portal.report_dimension_config d
        WHERE d.report_key = r.report_key AND d.enabled = true
      ),
      'measures', (
        SELECT COALESCE(json_agg(json_build_object('column_name', m.column_name, 'label', m.label, 'agg_type', m.agg_type) ORDER BY m.sort_order, m.label), '[]'::json)
        FROM rep_portal.report_measure_config m
        WHERE m.report_key = r.report_key AND m.enabled = true
      )
    ) ORDER BY r.sort_order, r.label), '[]'::json)
  )
  FROM rep_portal.report_config r;
$$;

REVOKE ALL   ON FUNCTION rep_portal.get_report_catalog() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_report_catalog() TO authenticated;

-- ── get_report_dimension_values ───────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.get_report_dimension_values(p_report_key text, p_column text)
RETURNS text[]
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_source_view text;
  v_result      text[];
BEGIN
  SELECT r.source_view INTO v_source_view
  FROM rep_portal.report_config r
  JOIN rep_portal.report_dimension_config d
    ON d.report_key = r.report_key AND d.column_name = p_column AND d.enabled = true
  WHERE r.report_key = p_report_key;

  IF v_source_view IS NULL THEN
    RETURN ARRAY[]::text[];
  END IF;

  EXECUTE format(
    'SELECT ARRAY(SELECT DISTINCT %I::text FROM rep_warehouse.%I WHERE %I IS NOT NULL ORDER BY 1 LIMIT 500)',
    p_column, v_source_view, p_column
  ) INTO v_result;

  RETURN COALESCE(v_result, ARRAY[]::text[]);
END;
$$;

REVOKE ALL   ON FUNCTION rep_portal.get_report_dimension_values(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_report_dimension_values(text, text) TO authenticated;

-- ── get_report_pivot ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.get_report_pivot(
  p_report_key  text,
  p_group_by    text[]  DEFAULT ARRAY[]::text[],
  p_measures    text[]  DEFAULT ARRAY[]::text[],
  p_filters     jsonb   DEFAULT '{}'::jsonb,
  p_year_start  int     DEFAULT 2020,
  p_year_end    int     DEFAULT 2030,
  p_countries   text[]  DEFAULT NULL,
  p_provinces   text[]  DEFAULT NULL,
  p_districts   text[]  DEFAULT NULL,
  p_schools     text[]  DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_report      rep_portal.report_config%ROWTYPE;
  v_valid_dims  text[];
  v_group_by    text[];
  v_select_cols text[] := ARRAY[]::text[];
  v_group_cols  text[] := ARRAY[]::text[];
  v_agg_cols    text[] := ARRAY[]::text[];
  v_where       text   := 'WHERE TRUE';
  v_sql         text;
  v_result      json;
  v_col         text;
  v_measure     RECORD;
  v_filter_key  text;
  v_filter_vals text[];
BEGIN
  SELECT * INTO v_report FROM rep_portal.report_config WHERE report_key = p_report_key;
  IF NOT FOUND THEN
    RETURN json_build_object('data', '[]'::json);
  END IF;

  -- Allow-list of enabled dimensions for this report
  SELECT COALESCE(array_agg(column_name), ARRAY[]::text[])
  INTO v_valid_dims
  FROM rep_portal.report_dimension_config
  WHERE report_key = p_report_key AND enabled = true;

  v_group_by := ARRAY(SELECT unnest(COALESCE(p_group_by, ARRAY[]::text[])) INTERSECT SELECT unnest(v_valid_dims));

  FOREACH v_col IN ARRAY v_group_by LOOP
    v_select_cols := array_append(v_select_cols, format('%I', v_col));
    v_group_cols  := array_append(v_group_cols, format('%I', v_col));
  END LOOP;

  -- Measure aggregates, validated against enabled report_measure_config.
  -- 'count' in p_measures selects the count() measure (column_name is NULL for it);
  -- any other entry is matched against a sum measure's column_name.
  FOR v_measure IN
    SELECT column_name, agg_type
    FROM rep_portal.report_measure_config
    WHERE report_key = p_report_key
      AND enabled = true
      AND (
        (agg_type = 'count' AND 'count' = ANY(COALESCE(p_measures, ARRAY[]::text[])))
        OR (agg_type = 'sum' AND column_name = ANY(COALESCE(p_measures, ARRAY[]::text[])))
      )
  LOOP
    IF v_measure.agg_type = 'count' THEN
      v_agg_cols := array_append(v_agg_cols, 'COUNT(*) AS count');
    ELSE
      v_agg_cols := array_append(v_agg_cols,
        format('ROUND(SUM(COALESCE(%I::numeric, 0)))::bigint AS %I', v_measure.column_name, v_measure.column_name));
    END IF;
  END LOOP;

  IF array_length(v_agg_cols, 1) IS NULL THEN
    v_agg_cols := ARRAY['COUNT(*) AS count'];
  END IF;

  -- Year range
  v_where := v_where || format(' AND %I BETWEEN %s AND %s', v_report.year_field, p_year_start, p_year_end);

  -- Geography filters
  IF p_countries IS NOT NULL AND array_length(p_countries, 1) > 0 THEN
    v_where := v_where || format(' AND country = ANY(ARRAY[%s])',
      (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_countries) c));
  END IF;
  IF p_provinces IS NOT NULL AND array_length(p_provinces, 1) > 0 THEN
    v_where := v_where || format(' AND province = ANY(ARRAY[%s])',
      (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_provinces) c));
  END IF;
  IF p_districts IS NOT NULL AND array_length(p_districts, 1) > 0 THEN
    v_where := v_where || format(' AND district = ANY(ARRAY[%s])',
      (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_districts) c));
  END IF;
  IF p_schools IS NOT NULL AND array_length(p_schools, 1) > 0 AND v_report.geography_level = 'school' THEN
    v_where := v_where || format(' AND school_name = ANY(ARRAY[%s])',
      (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_schools) c));
  END IF;

  -- Dimension filters: {column: [values]}, keys validated against the enabled allow-list
  FOR v_filter_key IN SELECT jsonb_object_keys(COALESCE(p_filters, '{}'::jsonb))
  LOOP
    IF v_filter_key = ANY(v_valid_dims) THEN
      SELECT array_agg(value) INTO v_filter_vals
      FROM jsonb_array_elements_text(p_filters -> v_filter_key) AS value;

      IF v_filter_vals IS NOT NULL AND array_length(v_filter_vals, 1) > 0 THEN
        v_where := v_where || format(' AND %I = ANY(ARRAY[%s])',
          v_filter_key,
          (SELECT string_agg(quote_literal(c), ',') FROM unnest(v_filter_vals) c));
      END IF;
    END IF;
  END LOOP;

  v_sql := 'SELECT ' || array_to_string(v_select_cols || v_agg_cols, ', ') ||
           ' FROM rep_warehouse.' || quote_ident(v_report.source_view) || ' ' || v_where;

  IF array_length(v_group_cols, 1) IS NOT NULL THEN
    v_sql := v_sql || ' GROUP BY ' || array_to_string(v_group_cols, ', ');
  END IF;

  EXECUTE 'SELECT json_build_object(''data'', COALESCE(json_agg(r), ''[]''::json)) FROM (' || v_sql || ') r'
  INTO v_result;

  RETURN COALESCE(v_result, json_build_object('data', '[]'::json));
END;
$$;

REVOKE ALL   ON FUNCTION rep_portal.get_report_pivot(text, text[], text[], jsonb, int, int, text[], text[], text[], text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_report_pivot(text, text[], text[], jsonb, int, int, text[], text[], text[], text[]) TO authenticated;

-- ── get_source_view_columns (admin) ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.get_source_view_columns(p_report_key text)
RETURNS json
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_source_view text;
  v_result      json;
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT source_view INTO v_source_view FROM rep_portal.report_config WHERE report_key = p_report_key;
  IF v_source_view IS NULL THEN
    RETURN '[]'::json;
  END IF;

  SELECT COALESCE(json_agg(json_build_object('column_name', c.column_name, 'data_type', c.data_type) ORDER BY c.ordinal_position), '[]'::json)
  INTO v_result
  FROM information_schema.columns c
  WHERE c.table_schema = 'rep_warehouse' AND c.table_name = v_source_view;

  RETURN v_result;
END;
$$;

REVOKE ALL   ON FUNCTION rep_portal.get_source_view_columns(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_source_view_columns(text) TO authenticated;

-- ── admin_get_report_config ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.admin_get_report_config()
RETURNS json
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_result json;
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT json_build_object(
    'reports',
    COALESCE(json_agg(json_build_object(
      'report_key',      r.report_key,
      'label',           r.label,
      'geography_level', r.geography_level,
      'dimensions', (
        SELECT COALESCE(json_agg(json_build_object('id', d.id, 'column_name', d.column_name, 'label', d.label, 'enabled', d.enabled, 'sort_order', d.sort_order) ORDER BY d.sort_order, d.label), '[]'::json)
        FROM rep_portal.report_dimension_config d
        WHERE d.report_key = r.report_key
      ),
      'measures', (
        SELECT COALESCE(json_agg(json_build_object('id', m.id, 'column_name', m.column_name, 'label', m.label, 'agg_type', m.agg_type, 'enabled', m.enabled, 'sort_order', m.sort_order) ORDER BY m.sort_order, m.label), '[]'::json)
        FROM rep_portal.report_measure_config m
        WHERE m.report_key = r.report_key
      )
    ) ORDER BY r.sort_order, r.label), '[]'::json)
  )
  INTO v_result
  FROM rep_portal.report_config r;

  RETURN v_result;
END;
$$;

REVOKE ALL   ON FUNCTION rep_portal.admin_get_report_config() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.admin_get_report_config() TO authenticated;

-- ── admin_set_report_dimensions ───────────────────────────────────────────────
-- Full-replace of a report's dimension rows, mirroring the permissionIds full-replace
-- pattern used by createRole/updateRole for rep_portal.role_permissions.

CREATE OR REPLACE FUNCTION rep_portal.admin_set_report_dimensions(p_report_key text, p_dimensions jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_source_view  text;
  v_valid_cols   text[];
  v_item         jsonb;
  v_column_name  text;
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT source_view INTO v_source_view FROM rep_portal.report_config WHERE report_key = p_report_key;
  IF v_source_view IS NULL THEN
    RAISE EXCEPTION 'Unknown report_key: %', p_report_key;
  END IF;

  SELECT array_agg(column_name) INTO v_valid_cols
  FROM information_schema.columns
  WHERE table_schema = 'rep_warehouse' AND table_name = v_source_view;

  FOR v_item IN SELECT jsonb_array_elements(p_dimensions)
  LOOP
    v_column_name := v_item ->> 'column_name';
    IF v_column_name IS NULL OR NOT (v_column_name = ANY(v_valid_cols)) THEN
      RAISE EXCEPTION 'Invalid column_name for report %: %', p_report_key, v_column_name;
    END IF;
  END LOOP;

  DELETE FROM rep_portal.report_dimension_config WHERE report_key = p_report_key;

  INSERT INTO rep_portal.report_dimension_config (report_key, column_name, label, enabled, sort_order)
  SELECT
    p_report_key,
    v_item ->> 'column_name',
    COALESCE(v_item ->> 'label', v_item ->> 'column_name'),
    COALESCE((v_item ->> 'enabled')::boolean, true),
    COALESCE((v_item ->> 'sort_order')::int, 0)
  FROM jsonb_array_elements(p_dimensions) AS v_item;
END;
$$;

REVOKE ALL   ON FUNCTION rep_portal.admin_set_report_dimensions(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.admin_set_report_dimensions(text, jsonb) TO authenticated;

-- ── admin_set_report_measures ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.admin_set_report_measures(p_report_key text, p_measures jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_source_view    text;
  v_numeric_cols   text[];
  v_item           jsonb;
  v_column_name    text;
  v_agg_type       text;
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT source_view INTO v_source_view FROM rep_portal.report_config WHERE report_key = p_report_key;
  IF v_source_view IS NULL THEN
    RAISE EXCEPTION 'Unknown report_key: %', p_report_key;
  END IF;

  SELECT array_agg(column_name) INTO v_numeric_cols
  FROM information_schema.columns
  WHERE table_schema = 'rep_warehouse' AND table_name = v_source_view
    AND data_type IN ('integer', 'numeric', 'bigint', 'double precision', 'real', 'smallint');

  FOR v_item IN SELECT jsonb_array_elements(p_measures)
  LOOP
    v_column_name := v_item ->> 'column_name';
    v_agg_type    := v_item ->> 'agg_type';

    IF v_agg_type NOT IN ('count', 'sum') THEN
      RAISE EXCEPTION 'Invalid agg_type: %', v_agg_type;
    END IF;
    IF v_agg_type = 'count' AND v_column_name IS NOT NULL THEN
      RAISE EXCEPTION 'count measures must not have a column_name';
    END IF;
    IF v_agg_type = 'sum' AND (v_column_name IS NULL OR NOT (v_column_name = ANY(v_numeric_cols))) THEN
      RAISE EXCEPTION 'Invalid numeric column_name for sum measure on report %: %', p_report_key, v_column_name;
    END IF;
  END LOOP;

  DELETE FROM rep_portal.report_measure_config WHERE report_key = p_report_key;

  INSERT INTO rep_portal.report_measure_config (report_key, column_name, label, agg_type, enabled, sort_order)
  SELECT
    p_report_key,
    v_item ->> 'column_name',
    COALESCE(v_item ->> 'label', INITCAP(COALESCE(v_item ->> 'column_name', 'Count'))),
    v_item ->> 'agg_type',
    COALESCE((v_item ->> 'enabled')::boolean, true),
    COALESCE((v_item ->> 'sort_order')::int, 0)
  FROM jsonb_array_elements(p_measures) AS v_item;
END;
$$;

REVOKE ALL   ON FUNCTION rep_portal.admin_set_report_measures(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.admin_set_report_measures(text, jsonb) TO authenticated;


-- ===== 20260715084723_enable_rls_report_config_tables.sql =====
-- Enable RLS (default-deny, no policies) on the new Salesforce Report config
-- tables, matching the rep_portal.metric_config pattern. Without this, the
-- REVOKE/GRANT alone doesn't block direct PostgREST access (GRANT SELECT to
-- authenticated + RLS disabled means these tables are fully queryable via
-- /rest/v1/report_dimension_config etc., bypassing the enabled=true filtering
-- done in get_report_catalog()). SECURITY DEFINER functions still bypass RLS
-- as the table owner, so get_report_catalog / admin_get_report_config etc.
-- are unaffected.

ALTER TABLE rep_portal.report_config           ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_portal.report_dimension_config ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_portal.report_measure_config   ENABLE ROW LEVEL SECURITY;


-- ===== 20260715085319_fix_report_config_setters_ambiguous_v_item.sql =====
-- Fix "column reference \"v_item\" is ambiguous" (42702) in
-- admin_set_report_dimensions / admin_set_report_measures: the INSERT ... SELECT
-- reused v_item as both the declared PL/pgSQL loop variable and the
-- jsonb_array_elements() FROM-clause alias. Rename the FROM alias to `elem`.

CREATE OR REPLACE FUNCTION rep_portal.admin_set_report_dimensions(p_report_key text, p_dimensions jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_source_view  text;
  v_valid_cols   text[];
  v_item         jsonb;
  v_column_name  text;
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT source_view INTO v_source_view FROM rep_portal.report_config WHERE report_key = p_report_key;
  IF v_source_view IS NULL THEN
    RAISE EXCEPTION 'Unknown report_key: %', p_report_key;
  END IF;

  SELECT array_agg(column_name) INTO v_valid_cols
  FROM information_schema.columns
  WHERE table_schema = 'rep_warehouse' AND table_name = v_source_view;

  FOR v_item IN SELECT jsonb_array_elements(p_dimensions)
  LOOP
    v_column_name := v_item ->> 'column_name';
    IF v_column_name IS NULL OR NOT (v_column_name = ANY(v_valid_cols)) THEN
      RAISE EXCEPTION 'Invalid column_name for report %: %', p_report_key, v_column_name;
    END IF;
  END LOOP;

  DELETE FROM rep_portal.report_dimension_config WHERE report_key = p_report_key;

  INSERT INTO rep_portal.report_dimension_config (report_key, column_name, label, enabled, sort_order)
  SELECT
    p_report_key,
    elem ->> 'column_name',
    COALESCE(elem ->> 'label', elem ->> 'column_name'),
    COALESCE((elem ->> 'enabled')::boolean, true),
    COALESCE((elem ->> 'sort_order')::int, 0)
  FROM jsonb_array_elements(p_dimensions) AS elem;
END;
$$;

REVOKE ALL   ON FUNCTION rep_portal.admin_set_report_dimensions(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.admin_set_report_dimensions(text, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION rep_portal.admin_set_report_measures(p_report_key text, p_measures jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_source_view    text;
  v_numeric_cols   text[];
  v_item           jsonb;
  v_column_name    text;
  v_agg_type       text;
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT source_view INTO v_source_view FROM rep_portal.report_config WHERE report_key = p_report_key;
  IF v_source_view IS NULL THEN
    RAISE EXCEPTION 'Unknown report_key: %', p_report_key;
  END IF;

  SELECT array_agg(column_name) INTO v_numeric_cols
  FROM information_schema.columns
  WHERE table_schema = 'rep_warehouse' AND table_name = v_source_view
    AND data_type IN ('integer', 'numeric', 'bigint', 'double precision', 'real', 'smallint');

  FOR v_item IN SELECT jsonb_array_elements(p_measures)
  LOOP
    v_column_name := v_item ->> 'column_name';
    v_agg_type    := v_item ->> 'agg_type';

    IF v_agg_type NOT IN ('count', 'sum') THEN
      RAISE EXCEPTION 'Invalid agg_type: %', v_agg_type;
    END IF;
    IF v_agg_type = 'count' AND v_column_name IS NOT NULL THEN
      RAISE EXCEPTION 'count measures must not have a column_name';
    END IF;
    IF v_agg_type = 'sum' AND (v_column_name IS NULL OR NOT (v_column_name = ANY(v_numeric_cols))) THEN
      RAISE EXCEPTION 'Invalid numeric column_name for sum measure on report %: %', p_report_key, v_column_name;
    END IF;
  END LOOP;

  DELETE FROM rep_portal.report_measure_config WHERE report_key = p_report_key;

  INSERT INTO rep_portal.report_measure_config (report_key, column_name, label, agg_type, enabled, sort_order)
  SELECT
    p_report_key,
    elem ->> 'column_name',
    COALESCE(elem ->> 'label', INITCAP(COALESCE(elem ->> 'column_name', 'Count'))),
    elem ->> 'agg_type',
    COALESCE((elem ->> 'enabled')::boolean, true),
    COALESCE((elem ->> 'sort_order')::int, 0)
  FROM jsonb_array_elements(p_measures) AS elem;
END;
$$;

REVOKE ALL   ON FUNCTION rep_portal.admin_set_report_measures(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.admin_set_report_measures(text, jsonb) TO authenticated;


-- ===== 20260715090147_fix_report_pivot_preserve_group_by_order.sql =====
-- Fix get_report_pivot: group-by column order wasn't preserved. It validated
-- p_group_by against the enabled-dimension allow-list via `unnest(...) INTERSECT
-- unnest(...)`, but INTERSECT is a set operation with no order guarantee — the
-- caller's requested column order (and therefore the pivot table's column order)
-- came back effectively scrambled. Replaced with an explicit ordered loop that
-- keeps only allow-listed columns while preserving p_group_by's order.

CREATE OR REPLACE FUNCTION rep_portal.get_report_pivot(
  p_report_key  text,
  p_group_by    text[]  DEFAULT ARRAY[]::text[],
  p_measures    text[]  DEFAULT ARRAY[]::text[],
  p_filters     jsonb   DEFAULT '{}'::jsonb,
  p_year_start  int     DEFAULT 2020,
  p_year_end    int     DEFAULT 2030,
  p_countries   text[]  DEFAULT NULL,
  p_provinces   text[]  DEFAULT NULL,
  p_districts   text[]  DEFAULT NULL,
  p_schools     text[]  DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_report      rep_portal.report_config%ROWTYPE;
  v_valid_dims  text[];
  v_group_by    text[];
  v_select_cols text[] := ARRAY[]::text[];
  v_group_cols  text[] := ARRAY[]::text[];
  v_agg_cols    text[] := ARRAY[]::text[];
  v_where       text   := 'WHERE TRUE';
  v_sql         text;
  v_result      json;
  v_col         text;
  v_measure     RECORD;
  v_filter_key  text;
  v_filter_vals text[];
BEGIN
  SELECT * INTO v_report FROM rep_portal.report_config WHERE report_key = p_report_key;
  IF NOT FOUND THEN
    RETURN json_build_object('data', '[]'::json);
  END IF;

  -- Allow-list of enabled dimensions for this report
  SELECT COALESCE(array_agg(column_name), ARRAY[]::text[])
  INTO v_valid_dims
  FROM rep_portal.report_dimension_config
  WHERE report_key = p_report_key AND enabled = true;

  -- Keep only allow-listed columns, preserving the caller's requested order
  -- (a set operation like INTERSECT would not preserve order here).
  v_group_by := ARRAY[]::text[];
  FOREACH v_col IN ARRAY COALESCE(p_group_by, ARRAY[]::text[]) LOOP
    IF v_col = ANY(v_valid_dims) AND NOT (v_col = ANY(v_group_by)) THEN
      v_group_by := array_append(v_group_by, v_col);
      v_select_cols := array_append(v_select_cols, format('%I', v_col));
      v_group_cols  := array_append(v_group_cols, format('%I', v_col));
    END IF;
  END LOOP;

  -- Measure aggregates, validated against enabled report_measure_config.
  -- 'count' in p_measures selects the count() measure (column_name is NULL for it);
  -- any other entry is matched against a sum measure's column_name.
  FOR v_measure IN
    SELECT column_name, agg_type
    FROM rep_portal.report_measure_config
    WHERE report_key = p_report_key
      AND enabled = true
      AND (
        (agg_type = 'count' AND 'count' = ANY(COALESCE(p_measures, ARRAY[]::text[])))
        OR (agg_type = 'sum' AND column_name = ANY(COALESCE(p_measures, ARRAY[]::text[])))
      )
  LOOP
    IF v_measure.agg_type = 'count' THEN
      v_agg_cols := array_append(v_agg_cols, 'COUNT(*) AS count');
    ELSE
      v_agg_cols := array_append(v_agg_cols,
        format('ROUND(SUM(COALESCE(%I::numeric, 0)))::bigint AS %I', v_measure.column_name, v_measure.column_name));
    END IF;
  END LOOP;

  IF array_length(v_agg_cols, 1) IS NULL THEN
    v_agg_cols := ARRAY['COUNT(*) AS count'];
  END IF;

  -- Year range
  v_where := v_where || format(' AND %I BETWEEN %s AND %s', v_report.year_field, p_year_start, p_year_end);

  -- Geography filters
  IF p_countries IS NOT NULL AND array_length(p_countries, 1) > 0 THEN
    v_where := v_where || format(' AND country = ANY(ARRAY[%s])',
      (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_countries) c));
  END IF;
  IF p_provinces IS NOT NULL AND array_length(p_provinces, 1) > 0 THEN
    v_where := v_where || format(' AND province = ANY(ARRAY[%s])',
      (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_provinces) c));
  END IF;
  IF p_districts IS NOT NULL AND array_length(p_districts, 1) > 0 THEN
    v_where := v_where || format(' AND district = ANY(ARRAY[%s])',
      (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_districts) c));
  END IF;
  IF p_schools IS NOT NULL AND array_length(p_schools, 1) > 0 AND v_report.geography_level = 'school' THEN
    v_where := v_where || format(' AND school_name = ANY(ARRAY[%s])',
      (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_schools) c));
  END IF;

  -- Dimension filters: {column: [values]}, keys validated against the enabled allow-list
  FOR v_filter_key IN SELECT jsonb_object_keys(COALESCE(p_filters, '{}'::jsonb))
  LOOP
    IF v_filter_key = ANY(v_valid_dims) THEN
      SELECT array_agg(value) INTO v_filter_vals
      FROM jsonb_array_elements_text(p_filters -> v_filter_key) AS value;

      IF v_filter_vals IS NOT NULL AND array_length(v_filter_vals, 1) > 0 THEN
        v_where := v_where || format(' AND %I = ANY(ARRAY[%s])',
          v_filter_key,
          (SELECT string_agg(quote_literal(c), ',') FROM unnest(v_filter_vals) c));
      END IF;
    END IF;
  END LOOP;

  v_sql := 'SELECT ' || array_to_string(v_select_cols || v_agg_cols, ', ') ||
           ' FROM rep_warehouse.' || quote_ident(v_report.source_view) || ' ' || v_where;

  IF array_length(v_group_cols, 1) IS NOT NULL THEN
    v_sql := v_sql || ' GROUP BY ' || array_to_string(v_group_cols, ', ');
  END IF;

  EXECUTE 'SELECT json_build_object(''data'', COALESCE(json_agg(r), ''[]''::json)) FROM (' || v_sql || ') r'
  INTO v_result;

  RETURN COALESCE(v_result, json_build_object('data', '[]'::json));
END;
$$;

REVOKE ALL   ON FUNCTION rep_portal.get_report_pivot(text, text[], text[], jsonb, int, int, text[], text[], text[], text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_report_pivot(text, text[], text[], jsonb, int, int, text[], text[], text[], text[]) TO authenticated;


-- ===== 20260715094031_fix_report_pivot_filter_type_cast.sql =====
-- Fix "operator does not exist: smallint = text" (42883) in get_report_pivot's
-- dimension filter loop. Admins can add non-text columns (e.g. `year`, a
-- smallint) as filterable dimensions via /admin/salesforce-reports, but the
-- filter comparison compared the raw column against quoted text literals with
-- no cast, which only worked for already-text columns. Cast the column to
-- text for comparison, matching the cast already used in
-- get_report_dimension_values when it fetches distinct filter values.

CREATE OR REPLACE FUNCTION rep_portal.get_report_pivot(
  p_report_key  text,
  p_group_by    text[]  DEFAULT ARRAY[]::text[],
  p_measures    text[]  DEFAULT ARRAY[]::text[],
  p_filters     jsonb   DEFAULT '{}'::jsonb,
  p_year_start  int     DEFAULT 2020,
  p_year_end    int     DEFAULT 2030,
  p_countries   text[]  DEFAULT NULL,
  p_provinces   text[]  DEFAULT NULL,
  p_districts   text[]  DEFAULT NULL,
  p_schools     text[]  DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_report      rep_portal.report_config%ROWTYPE;
  v_valid_dims  text[];
  v_group_by    text[];
  v_select_cols text[] := ARRAY[]::text[];
  v_group_cols  text[] := ARRAY[]::text[];
  v_agg_cols    text[] := ARRAY[]::text[];
  v_where       text   := 'WHERE TRUE';
  v_sql         text;
  v_result      json;
  v_col         text;
  v_measure     RECORD;
  v_filter_key  text;
  v_filter_vals text[];
BEGIN
  SELECT * INTO v_report FROM rep_portal.report_config WHERE report_key = p_report_key;
  IF NOT FOUND THEN
    RETURN json_build_object('data', '[]'::json);
  END IF;

  -- Allow-list of enabled dimensions for this report
  SELECT COALESCE(array_agg(column_name), ARRAY[]::text[])
  INTO v_valid_dims
  FROM rep_portal.report_dimension_config
  WHERE report_key = p_report_key AND enabled = true;

  -- Keep only allow-listed columns, preserving the caller's requested order
  -- (a set operation like INTERSECT would not preserve order here).
  v_group_by := ARRAY[]::text[];
  FOREACH v_col IN ARRAY COALESCE(p_group_by, ARRAY[]::text[]) LOOP
    IF v_col = ANY(v_valid_dims) AND NOT (v_col = ANY(v_group_by)) THEN
      v_group_by := array_append(v_group_by, v_col);
      v_select_cols := array_append(v_select_cols, format('%I', v_col));
      v_group_cols  := array_append(v_group_cols, format('%I', v_col));
    END IF;
  END LOOP;

  -- Measure aggregates, validated against enabled report_measure_config.
  -- 'count' in p_measures selects the count() measure (column_name is NULL for it);
  -- any other entry is matched against a sum measure's column_name.
  FOR v_measure IN
    SELECT column_name, agg_type
    FROM rep_portal.report_measure_config
    WHERE report_key = p_report_key
      AND enabled = true
      AND (
        (agg_type = 'count' AND 'count' = ANY(COALESCE(p_measures, ARRAY[]::text[])))
        OR (agg_type = 'sum' AND column_name = ANY(COALESCE(p_measures, ARRAY[]::text[])))
      )
  LOOP
    IF v_measure.agg_type = 'count' THEN
      v_agg_cols := array_append(v_agg_cols, 'COUNT(*) AS count');
    ELSE
      v_agg_cols := array_append(v_agg_cols,
        format('ROUND(SUM(COALESCE(%I::numeric, 0)))::bigint AS %I', v_measure.column_name, v_measure.column_name));
    END IF;
  END LOOP;

  IF array_length(v_agg_cols, 1) IS NULL THEN
    v_agg_cols := ARRAY['COUNT(*) AS count'];
  END IF;

  -- Year range
  v_where := v_where || format(' AND %I BETWEEN %s AND %s', v_report.year_field, p_year_start, p_year_end);

  -- Geography filters
  IF p_countries IS NOT NULL AND array_length(p_countries, 1) > 0 THEN
    v_where := v_where || format(' AND country = ANY(ARRAY[%s])',
      (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_countries) c));
  END IF;
  IF p_provinces IS NOT NULL AND array_length(p_provinces, 1) > 0 THEN
    v_where := v_where || format(' AND province = ANY(ARRAY[%s])',
      (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_provinces) c));
  END IF;
  IF p_districts IS NOT NULL AND array_length(p_districts, 1) > 0 THEN
    v_where := v_where || format(' AND district = ANY(ARRAY[%s])',
      (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_districts) c));
  END IF;
  IF p_schools IS NOT NULL AND array_length(p_schools, 1) > 0 AND v_report.geography_level = 'school' THEN
    v_where := v_where || format(' AND school_name = ANY(ARRAY[%s])',
      (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_schools) c));
  END IF;

  -- Dimension filters: {column: [values]}, keys validated against the enabled allow-list.
  -- Cast the column to text for comparison — dimensions can be any column type
  -- (admins can add numeric/boolean columns too), and values always arrive as text.
  FOR v_filter_key IN SELECT jsonb_object_keys(COALESCE(p_filters, '{}'::jsonb))
  LOOP
    IF v_filter_key = ANY(v_valid_dims) THEN
      SELECT array_agg(value) INTO v_filter_vals
      FROM jsonb_array_elements_text(p_filters -> v_filter_key) AS value;

      IF v_filter_vals IS NOT NULL AND array_length(v_filter_vals, 1) > 0 THEN
        v_where := v_where || format(' AND %I::text = ANY(ARRAY[%s])',
          v_filter_key,
          (SELECT string_agg(quote_literal(c), ',') FROM unnest(v_filter_vals) c));
      END IF;
    END IF;
  END LOOP;

  v_sql := 'SELECT ' || array_to_string(v_select_cols || v_agg_cols, ', ') ||
           ' FROM rep_warehouse.' || quote_ident(v_report.source_view) || ' ' || v_where;

  IF array_length(v_group_cols, 1) IS NOT NULL THEN
    v_sql := v_sql || ' GROUP BY ' || array_to_string(v_group_cols, ', ');
  END IF;

  EXECUTE 'SELECT json_build_object(''data'', COALESCE(json_agg(r), ''[]''::json)) FROM (' || v_sql || ') r'
  INTO v_result;

  RETURN COALESCE(v_result, json_build_object('data', '[]'::json));
END;
$$;

REVOKE ALL   ON FUNCTION rep_portal.get_report_pivot(text, text[], text[], jsonb, int, int, text[], text[], text[], text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_report_pivot(text, text[], text[], jsonb, int, int, text[], text[], text[], text[]) TO authenticated;


-- ===== 20260715100818_hardening_report_dimensions_and_measures.sql =====
-- Harden the admin-managed report config against two review findings:
--
-- 1. Label collisions: report_dimension_config/report_measure_config only
--    enforce column_name uniqueness, not label uniqueness. Two dimensions with
--    the same label silently break selection on /salesforce-report — the
--    frontend resolves a chosen label back to a column_name via a Map keyed
--    by label, so a duplicate label makes the second column unreachable and
--    can cause the wrong column to be queried. Reject duplicate labels
--    (case-insensitive, trimmed) within a single admin_set_report_* call.
--
-- 2. The report's own year_field (e.g. `year`, a smallint) is already applied
--    via the dedicated p_year_start/p_year_end range on every get_report_pivot
--    call. Letting an admin also add it as a generic filterable dimension (as
--    happened earlier — see 20260715094031's fix comment) creates two
--    independent, unreconciled year filters that can silently return zero
--    rows when they disagree. Exclude year_field from the admin "add column"
--    picker and reject it server-side in both setters.

CREATE OR REPLACE FUNCTION rep_portal.get_source_view_columns(p_report_key text)
RETURNS json
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_source_view text;
  v_year_field  text;
  v_result      json;
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT source_view, year_field INTO v_source_view, v_year_field
  FROM rep_portal.report_config WHERE report_key = p_report_key;
  IF v_source_view IS NULL THEN
    RETURN '[]'::json;
  END IF;

  SELECT COALESCE(json_agg(json_build_object('column_name', c.column_name, 'data_type', c.data_type) ORDER BY c.ordinal_position), '[]'::json)
  INTO v_result
  FROM information_schema.columns c
  WHERE c.table_schema = 'rep_warehouse' AND c.table_name = v_source_view
    AND c.column_name IS DISTINCT FROM v_year_field;

  RETURN v_result;
END;
$$;

REVOKE ALL   ON FUNCTION rep_portal.get_source_view_columns(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_source_view_columns(text) TO authenticated;

CREATE OR REPLACE FUNCTION rep_portal.admin_set_report_dimensions(p_report_key text, p_dimensions jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_source_view  text;
  v_year_field   text;
  v_valid_cols   text[];
  v_item         jsonb;
  v_column_name  text;
  v_dup_label    text;
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT source_view, year_field INTO v_source_view, v_year_field
  FROM rep_portal.report_config WHERE report_key = p_report_key;
  IF v_source_view IS NULL THEN
    RAISE EXCEPTION 'Unknown report_key: %', p_report_key;
  END IF;

  SELECT array_agg(column_name) INTO v_valid_cols
  FROM information_schema.columns
  WHERE table_schema = 'rep_warehouse' AND table_name = v_source_view;

  FOR v_item IN SELECT jsonb_array_elements(p_dimensions)
  LOOP
    v_column_name := v_item ->> 'column_name';
    IF v_column_name IS NULL OR NOT (v_column_name = ANY(v_valid_cols)) THEN
      RAISE EXCEPTION 'Invalid column_name for report %: %', p_report_key, v_column_name;
    END IF;
    IF v_column_name = v_year_field THEN
      RAISE EXCEPTION 'Column % is this report''s year field and is already applied via the year range filter — it cannot also be a dimension', v_column_name;
    END IF;
  END LOOP;

  SELECT lower(trim(elem ->> 'label')) INTO v_dup_label
  FROM jsonb_array_elements(p_dimensions) AS elem
  GROUP BY lower(trim(elem ->> 'label'))
  HAVING count(*) > 1
  LIMIT 1;
  IF v_dup_label IS NOT NULL THEN
    RAISE EXCEPTION 'Duplicate dimension label (labels must be unique per report): %', v_dup_label;
  END IF;

  DELETE FROM rep_portal.report_dimension_config WHERE report_key = p_report_key;

  INSERT INTO rep_portal.report_dimension_config (report_key, column_name, label, enabled, sort_order)
  SELECT
    p_report_key,
    elem ->> 'column_name',
    COALESCE(elem ->> 'label', elem ->> 'column_name'),
    COALESCE((elem ->> 'enabled')::boolean, true),
    COALESCE((elem ->> 'sort_order')::int, 0)
  FROM jsonb_array_elements(p_dimensions) AS elem;
END;
$$;

REVOKE ALL   ON FUNCTION rep_portal.admin_set_report_dimensions(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.admin_set_report_dimensions(text, jsonb) TO authenticated;

CREATE OR REPLACE FUNCTION rep_portal.admin_set_report_measures(p_report_key text, p_measures jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_source_view    text;
  v_year_field     text;
  v_numeric_cols   text[];
  v_item           jsonb;
  v_column_name    text;
  v_agg_type       text;
  v_dup_label      text;
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT source_view, year_field INTO v_source_view, v_year_field
  FROM rep_portal.report_config WHERE report_key = p_report_key;
  IF v_source_view IS NULL THEN
    RAISE EXCEPTION 'Unknown report_key: %', p_report_key;
  END IF;

  SELECT array_agg(column_name) INTO v_numeric_cols
  FROM information_schema.columns
  WHERE table_schema = 'rep_warehouse' AND table_name = v_source_view
    AND data_type IN ('integer', 'numeric', 'bigint', 'double precision', 'real', 'smallint');

  FOR v_item IN SELECT jsonb_array_elements(p_measures)
  LOOP
    v_column_name := v_item ->> 'column_name';
    v_agg_type    := v_item ->> 'agg_type';

    IF v_agg_type IS NULL OR v_agg_type NOT IN ('count', 'sum') THEN
      RAISE EXCEPTION 'Invalid agg_type: %', v_agg_type;
    END IF;
    IF v_agg_type = 'count' AND v_column_name IS NOT NULL THEN
      RAISE EXCEPTION 'count measures must not have a column_name';
    END IF;
    IF v_agg_type = 'sum' AND (v_column_name IS NULL OR NOT (v_column_name = ANY(v_numeric_cols))) THEN
      RAISE EXCEPTION 'Invalid numeric column_name for sum measure on report %: %', p_report_key, v_column_name;
    END IF;
    IF v_column_name = v_year_field THEN
      RAISE EXCEPTION 'Column % is this report''s year field and is already applied via the year range filter — it cannot also be a measure', v_column_name;
    END IF;
  END LOOP;

  SELECT lower(trim(elem ->> 'label')) INTO v_dup_label
  FROM jsonb_array_elements(p_measures) AS elem
  GROUP BY lower(trim(elem ->> 'label'))
  HAVING count(*) > 1
  LIMIT 1;
  IF v_dup_label IS NOT NULL THEN
    RAISE EXCEPTION 'Duplicate measure label (labels must be unique per report): %', v_dup_label;
  END IF;

  DELETE FROM rep_portal.report_measure_config WHERE report_key = p_report_key;

  INSERT INTO rep_portal.report_measure_config (report_key, column_name, label, agg_type, enabled, sort_order)
  SELECT
    p_report_key,
    elem ->> 'column_name',
    COALESCE(elem ->> 'label', INITCAP(COALESCE(elem ->> 'column_name', 'Count'))),
    elem ->> 'agg_type',
    COALESCE((elem ->> 'enabled')::boolean, true),
    COALESCE((elem ->> 'sort_order')::int, 0)
  FROM jsonb_array_elements(p_measures) AS elem;
END;
$$;

REVOKE ALL   ON FUNCTION rep_portal.admin_set_report_measures(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.admin_set_report_measures(text, jsonb) TO authenticated;


-- ===== 20260715100902_report_pivot_geo_cast_and_null_guards.sql =====
-- Two get_report_pivot hardening fixes from code review:
--
-- 1. The generic dimension-filter path was fixed to cast the column to ::text
--    before comparing against filter values (20260715094031), but the four
--    hardcoded geography filters (country/province/district/school_name) were
--    left uncast — same bug class, currently dormant only because all 6
--    seeded source_views happen to type those columns as text. Add the same
--    ::text cast for consistency and defense-in-depth.
--
-- 2. rep_portal.get_dashboard_data_filtered (the older, analogous Dynamic Data
--    RPC) excludes rows with a NULL year/country/district/school so a metric
--    never shows a blank/null grouping bucket. get_report_pivot never gained
--    the equivalent guard, so the same underlying data can show a stray null
--    row here that /dynamic would never show for the "same" numbers. Add the
--    same guards.

CREATE OR REPLACE FUNCTION rep_portal.get_report_pivot(
  p_report_key  text,
  p_group_by    text[]  DEFAULT ARRAY[]::text[],
  p_measures    text[]  DEFAULT ARRAY[]::text[],
  p_filters     jsonb   DEFAULT '{}'::jsonb,
  p_year_start  int     DEFAULT 2020,
  p_year_end    int     DEFAULT 2030,
  p_countries   text[]  DEFAULT NULL,
  p_provinces   text[]  DEFAULT NULL,
  p_districts   text[]  DEFAULT NULL,
  p_schools     text[]  DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_report      rep_portal.report_config%ROWTYPE;
  v_valid_dims  text[];
  v_group_by    text[];
  v_select_cols text[] := ARRAY[]::text[];
  v_group_cols  text[] := ARRAY[]::text[];
  v_agg_cols    text[] := ARRAY[]::text[];
  v_where       text   := 'WHERE TRUE';
  v_sql         text;
  v_result      json;
  v_col         text;
  v_measure     RECORD;
  v_filter_key  text;
  v_filter_vals text[];
BEGIN
  SELECT * INTO v_report FROM rep_portal.report_config WHERE report_key = p_report_key;
  IF NOT FOUND THEN
    RETURN json_build_object('data', '[]'::json);
  END IF;

  -- Allow-list of enabled dimensions for this report
  SELECT COALESCE(array_agg(column_name), ARRAY[]::text[])
  INTO v_valid_dims
  FROM rep_portal.report_dimension_config
  WHERE report_key = p_report_key AND enabled = true;

  -- Keep only allow-listed columns, preserving the caller's requested order
  -- (a set operation like INTERSECT would not preserve order here).
  v_group_by := ARRAY[]::text[];
  FOREACH v_col IN ARRAY COALESCE(p_group_by, ARRAY[]::text[]) LOOP
    IF v_col = ANY(v_valid_dims) AND NOT (v_col = ANY(v_group_by)) THEN
      v_group_by := array_append(v_group_by, v_col);
      v_select_cols := array_append(v_select_cols, format('%I', v_col));
      v_group_cols  := array_append(v_group_cols, format('%I', v_col));
    END IF;
  END LOOP;

  -- Measure aggregates, validated against enabled report_measure_config.
  -- 'count' in p_measures selects the count() measure (column_name is NULL for it);
  -- any other entry is matched against a sum measure's column_name.
  FOR v_measure IN
    SELECT column_name, agg_type
    FROM rep_portal.report_measure_config
    WHERE report_key = p_report_key
      AND enabled = true
      AND (
        (agg_type = 'count' AND 'count' = ANY(COALESCE(p_measures, ARRAY[]::text[])))
        OR (agg_type = 'sum' AND column_name = ANY(COALESCE(p_measures, ARRAY[]::text[])))
      )
  LOOP
    IF v_measure.agg_type = 'count' THEN
      v_agg_cols := array_append(v_agg_cols, 'COUNT(*) AS count');
    ELSE
      v_agg_cols := array_append(v_agg_cols,
        format('ROUND(SUM(COALESCE(%I::numeric, 0)))::bigint AS %I', v_measure.column_name, v_measure.column_name));
    END IF;
  END LOOP;

  IF array_length(v_agg_cols, 1) IS NULL THEN
    v_agg_cols := ARRAY['COUNT(*) AS count'];
  END IF;

  -- Year range
  v_where := v_where || format(' AND %I BETWEEN %s AND %s', v_report.year_field, p_year_start, p_year_end);

  -- NULL guards — never show a blank/null grouping bucket, matching
  -- rep_portal.get_dashboard_data_filtered's equivalent guard.
  v_where := v_where || format(' AND %I IS NOT NULL AND country IS NOT NULL', v_report.year_field);
  IF v_report.geography_level = 'school' THEN
    v_where := v_where || ' AND school_name IS NOT NULL';
  ELSE
    v_where := v_where || ' AND district IS NOT NULL';
  END IF;

  -- Geography filters
  IF p_countries IS NOT NULL AND array_length(p_countries, 1) > 0 THEN
    v_where := v_where || format(' AND country::text = ANY(ARRAY[%s])',
      (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_countries) c));
  END IF;
  IF p_provinces IS NOT NULL AND array_length(p_provinces, 1) > 0 THEN
    v_where := v_where || format(' AND province::text = ANY(ARRAY[%s])',
      (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_provinces) c));
  END IF;
  IF p_districts IS NOT NULL AND array_length(p_districts, 1) > 0 THEN
    v_where := v_where || format(' AND district::text = ANY(ARRAY[%s])',
      (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_districts) c));
  END IF;
  IF p_schools IS NOT NULL AND array_length(p_schools, 1) > 0 AND v_report.geography_level = 'school' THEN
    v_where := v_where || format(' AND school_name::text = ANY(ARRAY[%s])',
      (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_schools) c));
  END IF;

  -- Dimension filters: {column: [values]}, keys validated against the enabled allow-list.
  -- Cast the column to text for comparison — dimensions can be any column type
  -- (admins can add numeric/boolean columns too), and values always arrive as text.
  FOR v_filter_key IN SELECT jsonb_object_keys(COALESCE(p_filters, '{}'::jsonb))
  LOOP
    IF v_filter_key = ANY(v_valid_dims) THEN
      SELECT array_agg(value) INTO v_filter_vals
      FROM jsonb_array_elements_text(p_filters -> v_filter_key) AS value;

      IF v_filter_vals IS NOT NULL AND array_length(v_filter_vals, 1) > 0 THEN
        v_where := v_where || format(' AND %I::text = ANY(ARRAY[%s])',
          v_filter_key,
          (SELECT string_agg(quote_literal(c), ',') FROM unnest(v_filter_vals) c));
      END IF;
    END IF;
  END LOOP;

  v_sql := 'SELECT ' || array_to_string(v_select_cols || v_agg_cols, ', ') ||
           ' FROM rep_warehouse.' || quote_ident(v_report.source_view) || ' ' || v_where;

  IF array_length(v_group_cols, 1) IS NOT NULL THEN
    v_sql := v_sql || ' GROUP BY ' || array_to_string(v_group_cols, ', ');
  END IF;

  EXECUTE 'SELECT json_build_object(''data'', COALESCE(json_agg(r), ''[]''::json)) FROM (' || v_sql || ') r'
  INTO v_result;

  RETURN COALESCE(v_result, json_build_object('data', '[]'::json));
END;
$$;

REVOKE ALL   ON FUNCTION rep_portal.get_report_pivot(text, text[], text[], jsonb, int, int, text[], text[], text[], text[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_report_pivot(text, text[], text[], jsonb, int, int, text[], text[], text[], text[]) TO authenticated;


-- ===== 20260715100945_report_dimension_values_truncation_flag.sql =====
-- get_report_dimension_values silently capped distinct values at 500 with no
-- way for the caller to know the list was truncated. CAMFED has well over 500
-- schools across programme countries, and school_name is a seeded filterable
-- dimension, so values sorting after the cutoff were simply unreachable in
-- the filter UI with no indication. Change the return shape to
-- { values: text[], truncated: boolean } so the frontend can show a hint.
--
-- Return type changes from text[] to json, so the function must be dropped
-- and recreated (CREATE OR REPLACE cannot change a function's return type).

DROP FUNCTION IF EXISTS rep_portal.get_report_dimension_values(text, text);

CREATE FUNCTION rep_portal.get_report_dimension_values(p_report_key text, p_column text)
RETURNS json
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_source_view text;
  v_all         text[];
BEGIN
  SELECT r.source_view INTO v_source_view
  FROM rep_portal.report_config r
  JOIN rep_portal.report_dimension_config d
    ON d.report_key = r.report_key AND d.column_name = p_column AND d.enabled = true
  WHERE r.report_key = p_report_key;

  IF v_source_view IS NULL THEN
    RETURN json_build_object('values', '[]'::json, 'truncated', false);
  END IF;

  -- Fetch one more than the display cap so we can detect truncation.
  EXECUTE format(
    'SELECT ARRAY(SELECT DISTINCT %I::text FROM rep_warehouse.%I WHERE %I IS NOT NULL ORDER BY 1 LIMIT 501)',
    p_column, v_source_view, p_column
  ) INTO v_all;

  IF v_all IS NULL THEN
    RETURN json_build_object('values', '[]'::json, 'truncated', false);
  END IF;

  IF array_length(v_all, 1) > 500 THEN
    RETURN json_build_object('values', to_json(v_all[1:500]), 'truncated', true);
  END IF;

  RETURN json_build_object('values', to_json(v_all), 'truncated', false);
END;
$$;

REVOKE ALL   ON FUNCTION rep_portal.get_report_dimension_values(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_report_dimension_values(text, text) TO authenticated;


-- ===== 20260715102551_allow_year_field_as_dimension.sql =====
-- Reconsidered: blocking the report's year_field from being a dimension
-- (20260715100818) also blocked grouping by year (e.g. "gender x year" trend
-- breakdown), which is a legitimate, common need — not just a redundant
-- filter. The actual risk was narrower: FILTERING by an exact year value is
-- redundant with the dedicated Start/End Year range controls and can
-- silently produce zero rows if the two disagree. GROUPING by year has no
-- such conflict — it only shapes output rows within the already-applied
-- range, same as grouping by any other dimension.
--
-- Fix: allow year_field as a dimension again (restores group-by), and seed
-- it as a "Year" dimension on every report so it's immediately usable. Still
-- block it as a measure (summing year values is never meaningful, regardless
-- of the filter question) — that restriction is untouched.

CREATE OR REPLACE FUNCTION rep_portal.get_source_view_columns(p_report_key text)
RETURNS json
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_source_view text;
  v_result      json;
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT source_view INTO v_source_view FROM rep_portal.report_config WHERE report_key = p_report_key;
  IF v_source_view IS NULL THEN
    RETURN '[]'::json;
  END IF;

  SELECT COALESCE(json_agg(json_build_object('column_name', c.column_name, 'data_type', c.data_type) ORDER BY c.ordinal_position), '[]'::json)
  INTO v_result
  FROM information_schema.columns c
  WHERE c.table_schema = 'rep_warehouse' AND c.table_name = v_source_view;

  RETURN v_result;
END;
$$;

REVOKE ALL   ON FUNCTION rep_portal.get_source_view_columns(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_source_view_columns(text) TO authenticated;

CREATE OR REPLACE FUNCTION rep_portal.admin_set_report_dimensions(p_report_key text, p_dimensions jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_source_view  text;
  v_valid_cols   text[];
  v_item         jsonb;
  v_column_name  text;
  v_dup_label    text;
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  SELECT source_view INTO v_source_view FROM rep_portal.report_config WHERE report_key = p_report_key;
  IF v_source_view IS NULL THEN
    RAISE EXCEPTION 'Unknown report_key: %', p_report_key;
  END IF;

  SELECT array_agg(column_name) INTO v_valid_cols
  FROM information_schema.columns
  WHERE table_schema = 'rep_warehouse' AND table_name = v_source_view;

  FOR v_item IN SELECT jsonb_array_elements(p_dimensions)
  LOOP
    v_column_name := v_item ->> 'column_name';
    IF v_column_name IS NULL OR NOT (v_column_name = ANY(v_valid_cols)) THEN
      RAISE EXCEPTION 'Invalid column_name for report %: %', p_report_key, v_column_name;
    END IF;
  END LOOP;

  SELECT lower(trim(elem ->> 'label')) INTO v_dup_label
  FROM jsonb_array_elements(p_dimensions) AS elem
  GROUP BY lower(trim(elem ->> 'label'))
  HAVING count(*) > 1
  LIMIT 1;
  IF v_dup_label IS NOT NULL THEN
    RAISE EXCEPTION 'Duplicate dimension label (labels must be unique per report): %', v_dup_label;
  END IF;

  DELETE FROM rep_portal.report_dimension_config WHERE report_key = p_report_key;

  INSERT INTO rep_portal.report_dimension_config (report_key, column_name, label, enabled, sort_order)
  SELECT
    p_report_key,
    elem ->> 'column_name',
    COALESCE(elem ->> 'label', elem ->> 'column_name'),
    COALESCE((elem ->> 'enabled')::boolean, true),
    COALESCE((elem ->> 'sort_order')::int, 0)
  FROM jsonb_array_elements(p_dimensions) AS elem;
END;
$$;

REVOKE ALL   ON FUNCTION rep_portal.admin_set_report_dimensions(text, jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.admin_set_report_dimensions(text, jsonb) TO authenticated;

-- Seed "Year" as a dimension on every report, using each report's own year_field,
-- so group-by-year is immediately usable without an admin having to add it manually.
INSERT INTO rep_portal.report_dimension_config (report_key, column_name, label, sort_order)
SELECT report_key, year_field, 'Year', 5
FROM rep_portal.report_config
ON CONFLICT (report_key, column_name) DO NOTHING;


-- ===== 20260716095135_add_metric_config_list_rpc.sql =====
-- List RPC for rep_portal.metric_config — used by the admin Dashlets page to
-- populate the metric picker when wiring permission_metric_map rows.

CREATE OR REPLACE FUNCTION rep_portal.get_metric_config()
RETURNS TABLE (
  id          INTEGER,
  metric_name TEXT,
  sort_order  INTEGER,
  enabled     BOOLEAN
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  RETURN QUERY
  SELECT mc.id, mc.metric_name, mc.sort_order, mc.enabled
  FROM rep_portal.metric_config mc
  ORDER BY mc.sort_order;
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_metric_config() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_metric_config() TO authenticated;


-- ===== 20260716103923_grant_service_role_dashlet_comments.sql =====
-- rep_portal.dashlet_comments was created with RLS-with-no-policy and RPC-only
-- access, but never granted directly to service_role — unlike permissions and
-- permission_metric_map. The admin-users edge function (service role, via
-- PostgREST) embeds dashlet_comments in its permission-list select, which
-- fails with "permission denied for table dashlet_comments" without this.

GRANT ALL ON rep_portal.dashlet_comments TO service_role;
GRANT USAGE ON SEQUENCE rep_portal.dashlet_comments_id_seq TO service_role;


-- ===== 20260716113624_add_get_view_columns_rpc.sql =====
-- Lists the real columns of a rep_warehouse view, for the admin Metric Config
-- form's "year field" dropdown and filter-builder field picker — so admins
-- pick real column names instead of typing them freehand. Restricted to the
-- fixed set of views metric_config.source_view is allowed to reference.

CREATE OR REPLACE FUNCTION rep_portal.get_view_columns(p_view_name TEXT)
RETURNS TABLE (
  column_name TEXT,
  data_type   TEXT
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  IF p_view_name NOT IN (
    'view_children_supported', 'view_guide_assignment', 'view_cama_membership',
    'view_post_school_support', 'view_grants', 'view_loans'
  ) THEN
    RAISE EXCEPTION 'unknown view: %', p_view_name;
  END IF;

  RETURN QUERY
  SELECT c.column_name::TEXT, c.data_type::TEXT
  FROM information_schema.columns c
  WHERE c.table_schema = 'rep_warehouse'
    AND c.table_name = p_view_name
  ORDER BY c.ordinal_position;
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_view_columns(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_view_columns(TEXT) TO authenticated;


-- ===== 20260716120757_add_entity_history.sql =====
-- Generic audit/history table backing "revert if you break something" for
-- admin-managed dashlets (permissions + permission_metric_map +
-- dashlet_comments combined) and metric_config. Each row is a full snapshot
-- of the entity's state captured immediately before a change is applied —
-- restore re-applies an old snapshot as a new change, it doesn't rewrite
-- history.

CREATE TABLE rep_portal.entity_history (
  id          SERIAL      PRIMARY KEY,
  entity_type TEXT        NOT NULL CHECK (entity_type IN ('dashlet', 'metric_config')),
  entity_key  TEXT        NOT NULL,
  change_type TEXT        NOT NULL CHECK (change_type IN ('create', 'update', 'delete', 'restore')),
  snapshot    JSONB       NOT NULL,
  changed_by  UUID,
  changed_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX entity_history_lookup_idx ON rep_portal.entity_history (entity_type, entity_key, changed_at DESC);

REVOKE ALL ON rep_portal.entity_history FROM PUBLIC;
GRANT ALL   ON rep_portal.entity_history TO service_role;
GRANT USAGE ON SEQUENCE rep_portal.entity_history_id_seq TO service_role;


-- ===== 20260716120830_add_history_to_set_dashlet_comment.sql =====
-- set_dashlet_comment is the one dashlet write path that bypasses the
-- admin-users edge function (called directly via supabase.rpc() from the
-- frontend) — so it needs its own history snapshot, capturing the combined
-- dashlet state (permission metadata + metric wiring + prior comment)
-- immediately before the comment is overwritten.

CREATE OR REPLACE FUNCTION rep_portal.set_dashlet_comment(
  p_permission_key TEXT,
  p_comment        TEXT,
  p_is_enabled     BOOLEAN
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
DECLARE
  v_snapshot JSONB;
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  SELECT jsonb_build_object(
    'key', p.key,
    'label', p.label,
    'description', p.description,
    'parent_key', p.parent_key,
    'metric_config_ids', COALESCE((
      SELECT jsonb_agg(m.metric_config_id) FROM rep_portal.permission_metric_map m
      WHERE m.permission_key = p.key AND m.metric_config_id IS NOT NULL
    ), '[]'::jsonb),
    'kpi_ids', COALESCE((
      SELECT jsonb_agg(m.metric_id) FROM rep_portal.permission_metric_map m
      WHERE m.permission_key = p.key AND m.metric_config_id IS NULL
    ), '[]'::jsonb),
    'comment', dc.comment,
    'comment_enabled', dc.is_enabled
  )
  INTO v_snapshot
  FROM rep_portal.permissions p
  LEFT JOIN rep_portal.dashlet_comments dc ON dc.permission_key = p.key
  WHERE p.key = p_permission_key;

  IF v_snapshot IS NOT NULL THEN
    INSERT INTO rep_portal.entity_history (entity_type, entity_key, change_type, snapshot, changed_by)
    VALUES ('dashlet', p_permission_key, 'update', v_snapshot, auth.uid());
  END IF;

  UPDATE rep_portal.dashlet_comments
  SET comment    = p_comment,
      is_enabled = p_is_enabled,
      updated_by = auth.uid()
  WHERE permission_key = p_permission_key;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'unknown permission_key: %', p_permission_key;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.set_dashlet_comment(TEXT, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.set_dashlet_comment(TEXT, TEXT, BOOLEAN) TO authenticated;


-- ===== 20260716124317_grant_service_role_metric_config_seq.sql =====
-- rep_portal.metric_config was granted table-level access to service_role but
-- never USAGE on its id SERIAL sequence — inserts relying on the default
-- nextval() (metric-config-create) fail with "permission denied for sequence
-- metric_config_id_seq" without this.

GRANT USAGE ON SEQUENCE rep_portal.metric_config_id_seq TO service_role;


-- ===== 20260716175653_drop_stray_handle_new_user_trigger.sql =====
-- Drop a stray trigger on auth.users left over from an unrelated app that
-- previously shared this Supabase project (a supplier/importer marketplace).
-- It called public.handle_new_user(), which inserts into public.profiles —
-- a table that does not exist in this project. Every new-user creation
-- (invite, sign-up, OAuth) was failing with:
--   500: Database error saving new user
--   relation "public.profiles" does not exist (SQLSTATE 42P01)
-- because the failed insert aborted the whole auth.users insert transaction.

DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
DROP FUNCTION IF EXISTS public.handle_new_user();


-- ===== 20260717175014_add_dashlet_groups_and_dashlets.sql =====
-- Phase 0: introduce rep_portal.dashlets as the real dashlet hub, with a
-- curated rep_portal.dashlet_groups table for section grouping/ordering,
-- replacing dashlet_comments and the parent_key-as-grouping convention.
--
-- Also retires the reactive seed_dashlet_comment() trigger entirely, with no
-- replacement — per explicit direction: "Dashlets must be created first and
-- permissions added." Dashlet creation is now only ever done through the new
-- create_dashlet() RPC (next migration), which inserts both rows atomically.
-- dashlet_comments itself is left in place for now (dropped in a later,
-- separate cleanup migration) so the old table/RPCs keep working during the
-- gap between this migration landing and the admin-users edge function
-- deploy catching up.

-- ── 0.1a: dashlet_groups ──────────────────────────────────────────────────────

CREATE TABLE rep_portal.dashlet_groups (
  id             SERIAL PRIMARY KEY,
  name           TEXT NOT NULL UNIQUE,
  display_order  INTEGER NOT NULL DEFAULT 0,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE rep_portal.dashlet_groups ENABLE ROW LEVEL SECURITY;
-- No policies — default deny, matching every other rep_portal table. Access
-- exclusively through the admin-users edge function (service_role).

CREATE TRIGGER dashlet_groups_updated_at
  BEFORE UPDATE ON rep_portal.dashlet_groups
  FOR EACH ROW EXECUTE FUNCTION rep_portal.set_updated_at();

-- ── 0.1b: dashlets ────────────────────────────────────────────────────────────

CREATE TABLE rep_portal.dashlets (
  id               SERIAL PRIMARY KEY,
  permission_key   TEXT NOT NULL UNIQUE REFERENCES rep_portal.permissions(key) ON DELETE CASCADE,
  source_type      TEXT NOT NULL DEFAULT 'kpi' CHECK (source_type IN ('kpi', 'salesforce')),
  group_id         INTEGER REFERENCES rep_portal.dashlet_groups(id) ON DELETE SET NULL,
  comment          TEXT,
  comment_enabled  BOOLEAN NOT NULL DEFAULT false,
  chart_type       TEXT CHECK (chart_type IN ('number', 'bar', 'line')),
  display_mode     TEXT CHECK (display_mode IN ('aggregate', 'timeline')),
  updated_by       UUID,
  updated_at       TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at       TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE rep_portal.dashlets ENABLE ROW LEVEL SECURITY;
-- No policies — default deny. Read access for the dashboard's comment icon
-- goes through get_dashlet_comments(); everything else through admin-users.

CREATE TRIGGER dashlets_updated_at
  BEFORE UPDATE ON rep_portal.dashlets
  FOR EACH ROW EXECUTE FUNCTION rep_portal.set_updated_at();

-- ── 0.2: migrate existing dashlet_comments data into dashlets ───────────────

INSERT INTO rep_portal.dashlets (permission_key, comment, comment_enabled, updated_by, updated_at, created_at)
SELECT permission_key, comment, is_enabled, updated_by, updated_at, created_at
FROM rep_portal.dashlet_comments;

-- Every row already defaulted to 'kpi' on insert. Flip only the ones actually
-- wired to metric_config (Salesforce) — everything else (KPI-wired or
-- entirely unwired) stays 'kpi', the safe default.
UPDATE rep_portal.dashlets d SET source_type = 'salesforce'
WHERE EXISTS (
  SELECT 1 FROM rep_portal.permission_metric_map m
  WHERE m.permission_key = d.permission_key AND m.metric_config_id IS NOT NULL
);

-- One-time seed of dashlet_groups from the distinct permissions.parent_key
-- values currently in use by dashlet-category permissions. display_order
-- assigned by first appearance — an admin can reorder freely afterward via
-- the Groups tab.
INSERT INTO rep_portal.dashlet_groups (name, display_order)
SELECT DISTINCT p.parent_key, ROW_NUMBER() OVER (ORDER BY MIN(p.id)) - 1
FROM rep_portal.permissions p
WHERE p.category = 'dashlet' AND p.parent_key IS NOT NULL
GROUP BY p.parent_key
ON CONFLICT (name) DO NOTHING;

-- One-time seed of dashlets.group_id, matched by name against the groups
-- just created. From this point on the two are independent — editing a
-- permission's parent_key later does NOT cascade here, and renaming a
-- dashlet_groups row does not touch permissions.
UPDATE rep_portal.dashlets d SET group_id = g.id
FROM rep_portal.permissions p
JOIN rep_portal.dashlet_groups g ON g.name = p.parent_key
WHERE p.key = d.permission_key;

-- Retire the reactive trigger entirely. No replacement trigger is created —
-- from this point on, a dashlets row only ever comes from create_dashlet()
-- (next migration), never as a side effect of inserting into permissions.
DROP TRIGGER permissions_seed_dashlet_comment ON rep_portal.permissions;
DROP FUNCTION rep_portal.seed_dashlet_comment();

-- ── Grants ────────────────────────────────────────────────────────────────────

GRANT ALL ON rep_portal.dashlet_groups, rep_portal.dashlets TO service_role;
GRANT USAGE ON SEQUENCE rep_portal.dashlet_groups_id_seq, rep_portal.dashlets_id_seq TO service_role;

