-- Schema chunk 4 - run only after the previous chunk succeeded.
-- Generated from supabase/migrations in filename order. Do not reorder.


-- ===== 20260612103953_etl_geography_join_and_contact_merge.sql =====
-- Optimise ETL: replace scalar geography subqueries with JOIN pairs, and
-- collapse the 4-pass dim_contact temp-table merge into a single UNION ALL.
--
-- Geography: each fact previously resolved geography_id via two correlated
-- scalar subqueries per row (district match, then country-only fallback).
-- Replaced with two LEFT JOINs and COALESCE — PostgreSQL plans them once and
-- can use indexes rather than re-executing per row.
--
-- dim_contact: previously built a temp table with 4 sequential
-- INSERT … ON CONFLICT DO NOTHING passes. Replaced with a single INSERT
-- from a DISTINCT ON (contact_id ORDER BY priority) UNION ALL — one scan
-- per source table, no temp table allocation.

SET statement_timeout = 0;

-- ── 1. Supporting index for the district lookup JOIN ──────────────────────────
-- idx_dim_geography_current covers (country, province, district) but not
-- (country, district) alone — PostgreSQL cannot efficiently skip the middle column.

CREATE INDEX IF NOT EXISTS idx_dim_geography_country_district
    ON rep_warehouse.dim_geography (country, district)
    WHERE scd_is_current = true;


-- ── 2. Rewrite fact functions: scalar subqueries → JOIN pairs ─────────────────

-- fact_children_supported: two subqueries (district, then country-only)
CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_fact_children_supported()
RETURNS void LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.fact_children_supported
        (source_academic_record_id, source_contact_id, contact_id,
         source_school_id, school_id, geography_id,
         year, year_date_id, form, contact_record_type,
         attendance_issues, received_financial_support, repeated,
         roc_donor_id, roc_project_code_id,
         lin_is_current, lin_change_type, lin_source_system, lin_source_file,
         lin_load_batch_id, lin_inserted_at, lin_source_row_number)
    SELECT
        s.salesforce_id,
        s.contact_id,  dct.id,
        s.school_id,   ds.id,
        COALESCE(dg_d.id, dg_c.id),
        s.year, dd.id, s.form, s.contact_record_type,
        s.attendance_issues, s.received_financial_support, s.repeated,
        d3.id, d2.id,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        NOW(),
        s.row_id
    FROM rep_staging.academic_record s
    LEFT JOIN rep_warehouse.dim_contact         dct  ON dct.source_contact_id = s.contact_id  AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_school           ds   ON ds.source_school_id   = s.school_id   AND ds.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date             dd   ON dd.id = ((s.year::text || '0101')::integer)
    LEFT JOIN rep_warehouse.dim_roc_donor        d3   ON d3.source_roc_id = s.donor_code_id   AND d3.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_roc_project_code d2   ON d2.source_roc_id = s.project_code_id AND d2.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_geography       dg_d  ON dg_d.country = s.country AND dg_d.district = s.district AND dg_d.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_geography       dg_c  ON dg_c.country = s.country AND dg_c.province IS NULL AND dg_c.district IS NULL AND dg_c.scd_is_current = true
    WHERE s.salesforce_id IS NOT NULL
    ON CONFLICT (source_academic_record_id)
    WHERE source_academic_record_id IS NOT NULL
    DO UPDATE SET
        contact_id                 = EXCLUDED.contact_id,
        school_id                  = EXCLUDED.school_id,
        geography_id               = EXCLUDED.geography_id,
        form                       = EXCLUDED.form,
        attendance_issues          = EXCLUDED.attendance_issues,
        received_financial_support = EXCLUDED.received_financial_support,
        repeated                   = EXCLUDED.repeated,
        roc_donor_id               = EXCLUDED.roc_donor_id,
        roc_project_code_id        = EXCLUDED.roc_project_code_id,
        lin_change_type            = 'UPDATE',
        lin_load_batch_id          = EXCLUDED.lin_load_batch_id,
        lin_source_system          = EXCLUDED.lin_source_system,
        lin_source_file            = EXCLUDED.lin_source_file;
END;
$$;

-- fact_post_school_support: two subqueries (district, then country-only)
CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_fact_post_school_support()
RETURNS void LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.fact_post_school_support
        (source_academic_record_id, source_contact_id, contact_id, geography_id,
         year, year_date_id, received_financial_support, accommodation, form, roc_donor_id,
         lin_is_current, lin_change_type, lin_source_system, lin_source_file,
         lin_load_batch_id, lin_inserted_at, lin_source_row_number)
    SELECT
        s.salesforce_id,
        s.contact_id, dct.id,
        COALESCE(dg_d.id, dg_c.id),
        s.year, dd.id,
        s.received_financial_support,
        s.accommodation,
        s.form,
        d3.id,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        NOW(),
        s.row_id
    FROM rep_staging.post_school_clients s
    LEFT JOIN rep_warehouse.dim_contact   dct  ON dct.source_contact_id = s.contact_id   AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date      dd   ON dd.id = ((s.year::text || '0101')::integer)
    LEFT JOIN rep_warehouse.dim_roc_donor d3   ON d3.source_roc_id = s.donor_code_id     AND d3.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_geography dg_d ON dg_d.country = s.country AND dg_d.district = s.district AND dg_d.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_geography dg_c ON dg_c.country = s.country AND dg_c.province IS NULL AND dg_c.district IS NULL AND dg_c.scd_is_current = true
    WHERE s.salesforce_id IS NOT NULL
    ON CONFLICT (source_academic_record_id)
    WHERE source_academic_record_id IS NOT NULL
    DO UPDATE SET
        contact_id                 = EXCLUDED.contact_id,
        geography_id               = EXCLUDED.geography_id,
        received_financial_support = EXCLUDED.received_financial_support,
        accommodation              = EXCLUDED.accommodation,
        form                       = EXCLUDED.form,
        roc_donor_id               = EXCLUDED.roc_donor_id,
        lin_change_type            = 'UPDATE',
        lin_load_batch_id          = EXCLUDED.lin_load_batch_id,
        lin_source_system          = EXCLUDED.lin_source_system,
        lin_source_file            = EXCLUDED.lin_source_file;
END;
$$;

-- fact_guide_assignment: one subquery (district via dim_contact as fallback to school)
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
        COALESCE(ds.geography_id, dg_cd.id),
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
    -- fallback geography via contact's district when school has no geography_id
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

-- fact_cama_membership: one subquery (district fallback when school has no geography_id)
CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_fact_cama_membership()
RETURNS void LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
SET statement_timeout = 0 AS $$
BEGIN
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
END;
$$;

-- fact_grants: two subqueries (district, then country-only)
CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_fact_grants()
RETURNS void LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.fact_grants
        (source_grant_id, source_contact_id, contact_id, geography_id,
         grant_type, grant_status, amount_given, grant_date, grant_date_id, roc_donor_id,
         lin_is_current, lin_change_type, lin_source_system, lin_source_file,
         lin_load_batch_id, lin_business_hash, lin_source_row_number)
    SELECT
        s.grant_id, s.contact_id, dct.id,
        COALESCE(dg_d.id, dg_c.id),
        s.grant_type, s.grant_status, s.amount_given::numeric, s.grant_date::timestamp, dd.id,
        d3.id,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        MD5(COALESCE(s.grant_id, '')),
        s.row_id
    FROM rep_staging.grant_recipients s
    LEFT JOIN rep_warehouse.dim_contact   dct  ON dct.source_contact_id = s.contact_id  AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date      dd   ON dd.id = TO_CHAR(s.grant_date::timestamp, 'YYYYMMDD')::integer
    LEFT JOIN rep_warehouse.dim_roc_donor d3   ON d3.source_roc_id = s.donor_id         AND d3.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_geography dg_d ON dg_d.country = s.country AND dg_d.district = s.district AND dg_d.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_geography dg_c ON dg_c.country = s.country AND dg_c.province IS NULL AND dg_c.district IS NULL AND dg_c.scd_is_current = true
    ON CONFLICT (source_grant_id) DO NOTHING;
END;
$$;

-- fact_loans: two subqueries (district, then country-only) + add missing search_path
CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_fact_loans()
RETURNS void LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.fact_loans
        (source_loan_id, geography_id, loan_type, status, loan_status,
         disbursal_date, disbursal_date_id,
         loan_value, currency_iso_code, contact_record_id, roc_donor_id,
         lin_is_current, lin_change_type, lin_source_system, lin_source_file,
         lin_load_batch_id, lin_business_hash, lin_source_row_number)
    SELECT
        s.loan_id,
        COALESCE(dg_d.id, dg_c.id),
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
    LEFT JOIN rep_warehouse.dim_date      dd   ON dd.id = TO_CHAR(s.disbursal_date::timestamp, 'YYYYMMDD')::integer
    LEFT JOIN rep_warehouse.dim_roc_donor d3   ON d3.source_roc_id = s.donor_code_id AND d3.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_geography dg_d ON dg_d.country = s.country AND dg_d.district = s.district AND dg_d.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_geography dg_c ON dg_c.country = s.country AND dg_c.province IS NULL AND dg_c.district IS NULL AND dg_c.scd_is_current = true
    ON CONFLICT (source_loan_id) DO NOTHING;
END;
$$;


-- ── 3. Rewrite dim_contact: 4-pass temp table → single UNION ALL ──────────────

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
                country_name                      AS country,
                gender,
                wg_difficulty_overall,
                lg_social_support_recipient,
                active_on_bursary,
                orphan_status,
                district_id                       AS district,
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
                NULL, NULL, NULL, NULL, NULL, NULL,
                district_id,
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


-- ===== 20260612103956_ingest_run_etl_retry.sql =====
-- Operational reliability: track ETL retry attempts and provide a reschedule
-- function so the orchestrator can recover a stuck etl_pending run.
--
-- Without this, if the pg_cron job created by etl_schedule_salesforce_run()
-- is lost (PostgreSQL restart, cron extension reset), the run stays in
-- etl_pending indefinitely — the resume cron skips it and no new run can start
-- because the single-active-run index blocks it.
--
-- The orchestrator will detect runs stuck in etl_pending for > 15 minutes and
-- call etl_reschedule_salesforce_run(), capping retries at 2 before failing.

ALTER TABLE rep_warehouse.ingest_run
    ADD COLUMN IF NOT EXISTS etl_retry_count INT NOT NULL DEFAULT 0;

COMMENT ON COLUMN rep_warehouse.ingest_run.etl_retry_count IS
    'Number of times ETL has been re-scheduled after a stuck etl_pending. Capped at 2 before the run is marked failed.';


CREATE OR REPLACE FUNCTION rep_warehouse.etl_reschedule_salesforce_run(p_run_id TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_warehouse, cron, pg_temp
SET statement_timeout = 0
AS $$
BEGIN
    -- Unschedule any stale job first so cron.schedule does not error on duplicate name.
    PERFORM cron.unschedule('etl-bg-' || LEFT(p_run_id, 8));

    PERFORM cron.schedule(
        'etl-bg-' || LEFT(p_run_id, 8),
        '* * * * *',
        format($cmd$SELECT rep_warehouse.etl_run_salesforce_bg(%L)$cmd$, p_run_id)
    );

    UPDATE rep_warehouse.ingest_run
       SET etl_retry_count = etl_retry_count + 1,
           updated_at      = NOW()
     WHERE run_id = p_run_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.etl_reschedule_salesforce_run(TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_warehouse.etl_reschedule_salesforce_run(TEXT) TO service_role;


-- ===== 20260612135447_warehouse_counts_indexes.sql =====
-- Partial indexes to support get_warehouse_counts() without full-table scans.
-- Each index covers the WHERE lin_is_current = true / scd_is_current = true filter
-- and includes geography_id (or country for dimensions) so the JOIN + GROUP BY
-- can be satisfied from the index alone.

CREATE INDEX IF NOT EXISTS idx_fact_children_supported_current_geo
    ON rep_warehouse.fact_children_supported (geography_id, year)
    WHERE lin_is_current = true;

CREATE INDEX IF NOT EXISTS idx_fact_post_school_support_current_geo
    ON rep_warehouse.fact_post_school_support (geography_id, year)
    WHERE lin_is_current = true;

CREATE INDEX IF NOT EXISTS idx_fact_guide_assignment_current_geo
    ON rep_warehouse.fact_guide_assignment (geography_id, date_joined_guide_programme)
    WHERE lin_is_current = true;

CREATE INDEX IF NOT EXISTS idx_fact_grants_current_geo
    ON rep_warehouse.fact_grants (geography_id, grant_date)
    WHERE lin_is_current = true;

CREATE INDEX IF NOT EXISTS idx_fact_loans_current_geo
    ON rep_warehouse.fact_loans (geography_id, disbursal_date)
    WHERE lin_is_current = true;

CREATE INDEX IF NOT EXISTS idx_fact_cama_membership_current_geo
    ON rep_warehouse.fact_cama_membership (geography_id, date_joined_cama)
    WHERE lin_is_current = true;

CREATE INDEX IF NOT EXISTS idx_dim_contact_current_country
    ON rep_warehouse.dim_contact (country)
    WHERE scd_is_current = true;

CREATE INDEX IF NOT EXISTS idx_dim_school_current_country
    ON rep_warehouse.dim_school (country)
    WHERE scd_is_current = true;

-- Override statement_timeout at the function level so a slow first run
-- (before indexes are warm) is not killed by the client default.
CREATE OR REPLACE FUNCTION rep_portal.get_warehouse_counts()
RETURNS TABLE (
    source_object  TEXT,
    country        TEXT,
    year           SMALLINT,
    row_count      BIGINT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
SET statement_timeout = '120s'
AS $$

    SELECT
        'fact_children_supported'::TEXT AS source_object,
        g.country,
        f.year,
        COUNT(*)::BIGINT                 AS row_count
    FROM  rep_warehouse.fact_children_supported f
    LEFT JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id
    WHERE f.lin_is_current = true
    GROUP BY g.country, f.year

    UNION ALL

    SELECT
        'fact_post_school_support'::TEXT AS source_object,
        g.country,
        f.year,
        COUNT(*)::BIGINT
    FROM  rep_warehouse.fact_post_school_support f
    LEFT JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id
    WHERE f.lin_is_current = true
    GROUP BY g.country, f.year

    UNION ALL

    SELECT
        'fact_guide_assignment'::TEXT                               AS source_object,
        g.country,
        EXTRACT(YEAR FROM f.date_joined_guide_programme)::SMALLINT AS year,
        COUNT(*)::BIGINT
    FROM  rep_warehouse.fact_guide_assignment f
    LEFT JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id
    WHERE f.lin_is_current = true
      AND f.date_joined_guide_programme IS NOT NULL
    GROUP BY g.country, EXTRACT(YEAR FROM f.date_joined_guide_programme)::SMALLINT

    UNION ALL

    SELECT
        'fact_guide_assignment'::TEXT AS source_object,
        g.country,
        NULL::SMALLINT AS year,
        COUNT(*)::BIGINT
    FROM  rep_warehouse.fact_guide_assignment f
    LEFT JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id
    WHERE f.lin_is_current = true
      AND f.date_joined_guide_programme IS NULL
    GROUP BY g.country

    UNION ALL

    SELECT
        'fact_grants'::TEXT                        AS source_object,
        g.country,
        EXTRACT(YEAR FROM f.grant_date)::SMALLINT AS year,
        COUNT(*)::BIGINT
    FROM  rep_warehouse.fact_grants f
    LEFT JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id
    WHERE f.lin_is_current = true
      AND f.grant_date IS NOT NULL
    GROUP BY g.country, EXTRACT(YEAR FROM f.grant_date)::SMALLINT

    UNION ALL

    SELECT
        'fact_grants'::TEXT      AS source_object,
        g.country,
        NULL::SMALLINT           AS year,
        COUNT(*)::BIGINT
    FROM  rep_warehouse.fact_grants f
    LEFT JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id
    WHERE f.lin_is_current = true
      AND f.grant_date IS NULL
    GROUP BY g.country

    UNION ALL

    SELECT
        'fact_loans'::TEXT                            AS source_object,
        g.country,
        EXTRACT(YEAR FROM f.disbursal_date)::SMALLINT AS year,
        COUNT(*)::BIGINT
    FROM  rep_warehouse.fact_loans f
    LEFT JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id
    WHERE f.lin_is_current = true
      AND f.disbursal_date IS NOT NULL
    GROUP BY g.country, EXTRACT(YEAR FROM f.disbursal_date)::SMALLINT

    UNION ALL

    SELECT
        'fact_loans'::TEXT      AS source_object,
        g.country,
        NULL::SMALLINT          AS year,
        COUNT(*)::BIGINT
    FROM  rep_warehouse.fact_loans f
    LEFT JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id
    WHERE f.lin_is_current = true
      AND f.disbursal_date IS NULL
    GROUP BY g.country

    UNION ALL

    SELECT
        'fact_cama_membership'::TEXT                     AS source_object,
        g.country,
        EXTRACT(YEAR FROM f.date_joined_cama)::SMALLINT AS year,
        COUNT(*)::BIGINT
    FROM  rep_warehouse.fact_cama_membership f
    LEFT JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id
    WHERE f.lin_is_current = true
      AND f.date_joined_cama IS NOT NULL
    GROUP BY g.country, EXTRACT(YEAR FROM f.date_joined_cama)::SMALLINT

    UNION ALL

    SELECT
        'fact_cama_membership'::TEXT AS source_object,
        g.country,
        NULL::SMALLINT       AS year,
        COUNT(*)::BIGINT
    FROM  rep_warehouse.fact_cama_membership f
    LEFT JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id
    WHERE f.lin_is_current = true
      AND f.date_joined_cama IS NULL
    GROUP BY g.country

    UNION ALL

    SELECT
        'dim_contact'::TEXT AS source_object,
        c.country,
        NULL::SMALLINT   AS year,
        COUNT(*)::BIGINT
    FROM  rep_warehouse.dim_contact c
    WHERE c.scd_is_current = true
    GROUP BY c.country

    UNION ALL

    SELECT
        'dim_school'::TEXT AS source_object,
        s.country,
        NULL::SMALLINT   AS year,
        COUNT(*)::BIGINT
    FROM  rep_warehouse.dim_school s
    WHERE s.scd_is_current = true
    GROUP BY s.country

    ORDER BY 1, 2 NULLS LAST, 3 NULLS LAST;

$$;

REVOKE EXECUTE ON FUNCTION rep_portal.get_warehouse_counts() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_warehouse_counts() TO authenticated;


-- ===== 20260616235959_add_kpi_mapping_table.sql =====
-- Fix: rep_portal.kpi_mapping is referenced by 20260617000001_ip_targets.sql
-- (rep_portal.get_dashlet_targets joins ip_targets to kpi_mapping) but no
-- migration ever created it -- it only existed locally/remotely because it
-- was created directly in Studio at some point, which is invisible to
-- `supabase db push` / `supabase db reset` (see CLAUDE.md's function-security
-- checklist item 3: "Studio-created objects are invisible to `supabase db
-- push`" -- the same trap applies to tables, not just functions).
--
-- This surfaced when a from-scratch `supabase db reset` replayed migrations
-- locally and failed at ip_targets because kpi_mapping didn't exist yet.
-- Schema and the 82 existing rows were pulled read-only from the linked
-- remote project (qlvayqyihfixikfqfelu) to recreate it faithfully. Timestamped
-- to run immediately before 20260617000001_ip_targets.sql, which depends on it.
--
-- RLS is enabled with no policy (default deny, matching every other rep_portal/
-- rep_warehouse table) -- the remote table also grants direct CRUD to anon/
-- authenticated/service_role, but since get_dashlet_targets is SECURITY DEFINER
-- it doesn't need those grants to function, so they're intentionally omitted
-- here as unnecessary exposure surface.

CREATE TABLE rep_portal.kpi_mapping (
  id                        serial PRIMARY KEY,
  dashlet_element           integer NOT NULL,
  kpi_id                    text NOT NULL,
  disaggregation_level_one  text,
  disaggregation_level_two  text,
  source_table              text NOT NULL DEFAULT 'rep_warehouse.view_observed_kpi',
  dashboard_page            text NOT NULL,
  data_element              text NOT NULL,
  toggle                    text
);

ALTER TABLE rep_portal.kpi_mapping ENABLE ROW LEVEL SECURITY;

INSERT INTO rep_portal.kpi_mapping
  (id, dashlet_element, kpi_id, disaggregation_level_one, disaggregation_level_two, source_table, dashboard_page, data_element, toggle)
VALUES
(1, 1, '1.1', 'Annual', 'Girls Total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'Girls Supported in School with Education Bursaries', 'Annual'),
(2, 2, '1.1', 'Newly supported', 'Girls Total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'Girls Supported in School with Education Bursaries', 'Newly Supported'),
(3, 9, '1.1', 'Cumulative (2020-2030)', 'Girls Total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'Girls Supported in School with Education Bursaries', 'Cumulative 2020-2030'),
(4, 10, '1.1', 'Cumulative (all-time)', 'Girls Total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'Girls Supported in School with Education Bursaries', 'Cumulative All-time'),
(5, 3, '1.2a', 'Annual', 'Girls Total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'CAMA', 'Annual'),
(6, 4, '1.2a', 'Newly supported', 'Girls Total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'CAMA', 'Newly Supported'),
(7, 5, 'P1', 'Annual', 'Girls total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'Total Girls Supported', 'Annual'),
(8, 6, 'P1', 'Newly supported', 'Girls total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'Total Girls Supported', 'Newly Supported'),
(9, 7, 'P1', 'Annual', 'Boys total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'Total Boys Supported', 'Annual'),
(10, 8, 'P1', 'Newly supported', 'Boys total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'Total Boys Supported', 'Newly Supported'),
(11, 3, '1.2b', 'Annual', 'Girls Total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'Community Champions', 'Annual'),
(12, 4, '1.2b', 'Newly supported', 'Girls Total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'Community Champions', 'Newly Supported'),
(13, 11, '1.5', 'Annual', NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Outcomes', 'Dropout Rate for Girls with Education Bursaries', 'Annual'),
(14, 12, '1.4', 'Lower Secondary', 'Clients', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Outcomes', 'Exam Pass Rates', 'Lower Secondary'),
(15, 13, '1.4', 'Upper Secondary', 'Clients', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Outcomes', 'Exam Pass Rates', 'Upper Secondary'),
(16, 14, '1.7', 'CAMFED supported', 'Form 1', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Outcomes', 'Progression to Next Grade', 'Form 1'),
(17, 15, '1.7', 'CAMFED supported', 'Form 2', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Outcomes', 'Progression to Next Grade', 'Form 2'),
(18, 16, '1.7', 'CAMFED supported', 'Form 3', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Outcomes', 'Progression to Next Grade', 'Form 3'),
(19, 17, '1.7', 'CAMFED supported', 'Form 4', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Outcomes', 'Progression to Next Grade', 'Form 4'),
(20, 18, '1.8', NULL, 'Lower secondary', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Outcomes', 'School Completion Rate', 'Lower Secondary'),
(21, 19, '1.8', NULL, 'Upper secondary', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Outcomes', 'School Completion Rate', 'Upper Secondary'),
(22, 21, '1.9', 'Total', 'Annual', 'rep_warehouse.view_observed_kpi', 'Girls Education: Learner Guide Programme', 'Active Learner Guides', 'Annual'),
(23, 22, '1.9', 'Total', 'Newly trained', 'rep_warehouse.view_observed_kpi', 'Girls Education: Learner Guide Programme', 'Active Learner Guides', 'Newly Trained'),
(24, 23, '1.9', 'Total', 'Cumulative (2020-2030)', 'rep_warehouse.view_observed_kpi', 'Girls Education: Learner Guide Programme', 'Active Learner Guides', 'Cumulative 2020-2030'),
(25, 24, '1.9', 'Total', 'Cumulative (all-time)', 'rep_warehouse.view_observed_kpi', 'Girls Education: Learner Guide Programme', 'Active Learner Guides', 'Cumulative All-time'),
(26, 25, '1.9', 'CAMFED trained', 'Annual', 'rep_warehouse.view_observed_kpi', 'Girls Education: Learner Guide Programme', 'Active Learner Guides by Training - CAMFED', 'Annual'),
(27, 26, '1.9', 'Government trained', 'Annual', 'rep_warehouse.view_observed_kpi', 'Girls Education: Learner Guide Programme', 'Active Learner Guides by Training - Government', 'Annual'),
(28, 27, '1.3', 'Annual', 'Girls total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Learner Guide Programme', 'Children Receiving Support - Girls', 'Annual'),
(29, 28, '1.3', 'Newly reached', 'Girls total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Learner Guide Programme', 'Children Receiving Support - Girls', 'Newly Reached'),
(30, 29, '1.3', 'Annual', 'Boys total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Learner Guide Programme', 'Children Receiving Support - Boys', 'Annual'),
(31, 30, '1.3', 'Newly reached', 'Boys total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Learner Guide Programme', 'Children Receiving Support - Boys', 'Newly Reached'),
(32, 31, 'R3', 'Annual', NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Learner Guide Programme', 'Learner Guides Reporting Increased Agency', 'Annual'),
(33, 32, '2.1', 'New since last year', NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Leadership & Tertiary', 'CAMA Members', 'Annual'),
(34, 33, '2.2', 'Transition Guides', 'Annual', 'rep_warehouse.view_observed_kpi', 'Girls Education: Leadership & Tertiary', 'Active Transition Guides', 'Annual'),
(35, 34, '2.2', 'Transition Guides', 'Newly trained', 'rep_warehouse.view_observed_kpi', 'Girls Education: Leadership & Tertiary', 'Active Transition Guides', 'Newly Supported'),
(36, 35, '2.3', 'Annual', NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Leadership & Tertiary', 'Young Women Supported by Transition Guides', 'Annual'),
(37, 36, '2.3', 'Newly reached', NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Leadership & Tertiary', 'Young Women Supported by Transition Guides', 'Newly Supported'),
(38, 37, '2.5', 'Annual', NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Leadership & Tertiary', 'Young Women in Tertiary Education', 'Annual'),
(39, 38, '2.5', 'Newly supported', NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Leadership & Tertiary', 'Young Women in Tertiary Education', 'Newly Supported'),
(40, 39, '2.13', 'Annual', NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Leadership & Tertiary', 'CAMA Members in Leadership Roles', 'Annual'),
(41, 41, '2.2', 'Agriculture Guides', 'Annual', 'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Active Enterprise Guides - Agriculture', 'Annual'),
(42, 42, '2.2', 'Agriculture Guides', 'Newly trained', 'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Active Enterprise Guides - Agriculture', 'Newly Supported'),
(43, 43, '2.2', 'Business Guides', 'Annual', 'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Active Enterprise Guides - Business', 'Annual'),
(44, 44, '2.2', 'Business Guides', 'Newly trained', 'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Active Enterprise Guides - Business', 'Newly Supported'),
(45, 45, '2.7', 'Agriculture Guide', 'Annual', 'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Businesses Supported - Agriculture', 'Annual'),
(46, 46, '2.7', 'Agriculture Guide', 'Cumulative (2020-2030)', 'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Businesses Supported - Agriculture', 'Cumulative 2020-2030'),
(47, 47, '2.7', 'Business Guide', 'Annual', 'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Businesses Supported - Business', 'Annual'),
(48, 48, '2.7', 'Business Guide', 'Cumulative (2020-2030)', 'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Businesses Supported - Business', 'Cumulative 2020-2030'),
(49, 49, '2.8a', 'Annual', 'Number of Grants', 'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Business Grants - Count', 'Count'),
(50, 50, '2.8a', 'Annual', 'Grants USD value', 'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Business Grants - USD Value', 'USD Value'),
(51, 51, '2.8b', 'Annual', 'Number of Kiva Loans', 'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Loans - Kiva Count', 'Kiva Count'),
(52, 52, '2.8b', 'Annual', 'Number of Revolving Investment Fund loans', 'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Loans - RIF Count', 'RIF Count'),
(53, 53, '2.8b', 'Annual', 'All loans USD value', 'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Loans - USD Value', 'USD Value'),
(54, 56, '2.4', 'Annual', NULL, 'rep_warehouse.view_observed_kpi', 'Livelihoods: Jobs & Income', 'Women Progressing Towards Secure Livelihood', 'Annual'),
(55, 57, '2.11', 'Annual', '% making a profit', 'rep_warehouse.view_observed_kpi', 'Livelihoods: Jobs & Income', 'Female Entrepreneurs with Increased Incomes', 'Annual'),
(56, 58, '2.9', 'Annual', NULL, 'rep_warehouse.view_observed_kpi', 'Livelihoods: Jobs & Income', 'Jobs Created', 'Annual'),
(57, 59, '2.9', 'Cumulative (2020-2030)', NULL, 'rep_warehouse.view_observed_kpi', 'Livelihoods: Jobs & Income', 'Jobs Created', 'Cumulative 2020-2030'),
(58, 60, '2.6', 'Annual', NULL, 'rep_warehouse.view_observed_kpi', 'Livelihoods: Jobs & Income', 'New Businesses', 'Annual'),
(59, 61, '2.6', 'Cumulative (2020-2030)', NULL, 'rep_warehouse.view_observed_kpi', 'Livelihoods: Jobs & Income', 'New Businesses', 'Cumulative 2020-2030'),
(60, 66, 'R4', 'Annual', NULL, 'rep_warehouse.view_observed_kpi', 'Livelihoods: Agriculture & Food', 'Female Entrepreneurs with Increased Food Consumption', 'Annual'),
(61, 67, 'R8', 'Annual', NULL, 'rep_warehouse.view_observed_kpi', 'Livelihoods: Agriculture & Food', 'Female Agripreneurs with Increased Yields', 'Annual'),
(62, 68, 'R7', 'Annual', NULL, 'rep_warehouse.view_observed_kpi', 'Livelihoods: Agriculture & Food', 'Climate-Smart Techniques Used', 'Annual'),
(63, 71, '3.3', 'Annual', NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Systems', '% Resources from Government for LG Programme', 'Annual'),
(64, 72, '3.4', 'CAMFED partner districts', NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Systems', 'Districts with Learner Guides - CAMFED', NULL),
(65, 73, '3.4', 'Government delivery', NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Systems', 'Districts with Learner Guides - Government', NULL),
(66, 74, '3.6', 'National level', NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Systems', 'National Dropout Rate for Girls', 'Annual'),
(67, 75, '3.2', 'CAMFED supported', 'Total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Systems', 'Schools with Learner Guides - CAMFED', NULL),
(68, 76, '3.2', 'Government delivery', 'Total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Systems', 'Schools with Learner Guides - Government', NULL),
(69, 77, 'P6', 'CDCs', NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Systems', 'Community Champions - CDCs', NULL),
(70, 78, 'P6', 'SBCs', NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Systems', 'Community Champions - SBCs', NULL),
(71, 79, 'P6', 'PSGs', NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Systems', 'Community Champions - PSGs', NULL),
(72, 80, 'P18', NULL, NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Systems', 'Memoranda of Understanding', NULL),
(73, 81, '3.5', 'Annual', 'Primary girls', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Systems', 'Children in Improved Environment', 'Annual'),
(74, 82, '3.5', 'Annual', 'Primary boys', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Systems', 'Children in Improved Environment', 'Annual'),
(75, 83, '3.5', 'Annual', 'Secondary girls', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Systems', 'Children in Improved Environment', 'Annual'),
(76, 84, '3.5', 'Annual', 'Secondary boys', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Systems', 'Children in Improved Environment', 'Annual'),
(77, 85, '3.5', 'Newly supported', 'Primary girls', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Systems', 'Children in Improved Environment', 'Newly Supported'),
(78, 86, '3.5', 'Newly supported', 'Primary boys', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Systems', 'Children in Improved Environment', 'Newly Supported'),
(79, 87, '3.5', 'Newly supported', 'Secondary girls', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Systems', 'Children in Improved Environment', 'Newly Supported'),
(80, 88, '3.5', 'Newly supported', 'Secondary boys', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Systems', 'Children in Improved Environment', 'Newly Supported'),
(81, 89, '2.14', NULL, NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Life Choices', 'Young Women Married by Age 18', NULL),
(82, 90, '2.15', NULL, NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Life Choices', 'Young Women Giving Birth', NULL);

SELECT setval('rep_portal.kpi_mapping_id_seq', (SELECT MAX(id) FROM rep_portal.kpi_mapping));


-- ===== 20260617000001_ip_targets.sql =====
-- Migration: ip_targets
-- Creates rep_portal.ip_targets table, seeds it from the CAMFED IP Targets Excel workbook,
-- and exposes a get_dashlet_targets() RPC that joins ip_targets to kpi_mapping.

-- ── Table ─────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS rep_portal.ip_targets (
  id              serial       PRIMARY KEY,
  indicator_code  text         NOT NULL,
  indicator       text         NOT NULL,
  disagg_level_one text,
  disagg_level_two text,
  country         text         NOT NULL,
  year            integer      NOT NULL,
  target_value    double precision
);

CREATE INDEX IF NOT EXISTS ip_targets_lookup
  ON rep_portal.ip_targets (indicator_code, disagg_level_one, disagg_level_two, country, year);

-- ── Seed ──────────────────────────────────────────────────────────────────────
TRUNCATE rep_portal.ip_targets;
INSERT INTO rep_portal.ip_targets (indicator_code, indicator, disagg_level_one, disagg_level_two, country, year, target_value) VALUES
  ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Ghana', 2024, 136309)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Ghana', 2024, 33706)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Ghana', 2024, 14000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Ghana', 2024, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Ghana', 2024, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Ghana', 2024, 33706)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Ghana', 2024, 14000)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Ghana', 2024, 122309)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Ghana', 2024, 122309)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Ghana', 2024, 304080)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Ghana', 2024, 4344)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Ghana', 2024, 3495)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Ghana', 2024, 4886)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Ghana', 2024, 66040)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Ghana', 2024, 489)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Ghana', 2024, 188)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Ghana', 2024, 390)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Ghana', 2024, 390)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Ghana', 2024, 585)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Ghana', 2024, 585)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Ghana', 2024, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Ghana', 2024, 3000)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Ghana', 2024, 14625)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Ghana', 2024, 1086)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Ghana', 2024, 0)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Ghana', 2024, 1086)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Ghana', 2025, 146080)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Ghana', 2025, 33000)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Ghana', 2025, 14000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Ghana', 2025, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Ghana', 2025, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Ghana', 2025, 33000)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Ghana', 2025, 14000)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Ghana', 2025, 132080)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Ghana', 2025, 132080)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Ghana', 2025, 402080)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Ghana', 2025, 5744)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Ghana', 2025, 4061)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Ghana', 2025, 11975)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Ghana', 2025, 78015)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Ghana', 2025, 1197)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Ghana', 2025, 1104)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Ghana', 2025, 520)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Ghana', 2025, 325)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Ghana', 2025, 780)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Ghana', 2025, 488)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Ghana', 2025, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Ghana', 2025, 2500)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Ghana', 2025, 19500)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Ghana', 2025, 1364)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Ghana', 2025, 72)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Ghana', 2025, 1436)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Ghana', 2026, 170029)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Ghana', 2026, 34311)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Ghana', 2026, 14000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Ghana', 2026, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Ghana', 2026, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Ghana', 2026, 34311)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Ghana', 2026, 14000)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Ghana', 2026, 156029)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Ghana', 2026, 156029)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Ghana', 2026, 487480)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Ghana', 2026, 6964)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Ghana', 2026, 4661)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Ghana', 2026, 11400)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Ghana', 2026, 89414)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Ghana', 2026, 1140)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Ghana', 2026, 588)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Ghana', 2026, 641)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Ghana', 2026, 479)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Ghana', 2026, 962)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Ghana', 2026, 718)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Ghana', 2026, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Ghana', 2026, 2600)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Ghana', 2026, 24050)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Ghana', 2026, 1567)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Ghana', 2026, 174)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Ghana', 2026, 1741)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Ghana', 2027, 192829)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Ghana', 2027, 35482)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Ghana', 2027, 14000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Ghana', 2027, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Ghana', 2027, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Ghana', 2027, 35482)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Ghana', 2027, 14000)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Ghana', 2027, 178829)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Ghana', 2027, 178829)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Ghana', 2027, 563640)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Ghana', 2027, 8052)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Ghana', 2027, 5222)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Ghana', 2027, 11400)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Ghana', 2027, 100814)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Ghana', 2027, 1140)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Ghana', 2027, 846)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Ghana', 2027, 767)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Ghana', 2027, 528)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Ghana', 2027, 1151)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Ghana', 2027, 792)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Ghana', 2027, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Ghana', 2027, 2650)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Ghana', 2027, 28775)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Ghana', 2027, 1711)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Ghana', 2027, 302)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Ghana', 2027, 2013)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Ghana', 2028, 215628)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Ghana', 2028, 36601)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Ghana', 2028, 14000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Ghana', 2028, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Ghana', 2028, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Ghana', 2028, 36601)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Ghana', 2028, 14000)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Ghana', 2028, 201628)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Ghana', 2028, 201628)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Ghana', 2028, 738360)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Ghana', 2028, 10548)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Ghana', 2028, 7253)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Ghana', 2028, 11400)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Ghana', 2028, 112214)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Ghana', 2028, 1140)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Ghana', 2028, 717)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Ghana', 2028, 896)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Ghana', 2028, 632)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Ghana', 2028, 1344)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Ghana', 2028, 948)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Ghana', 2028, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Ghana', 2028, 2550)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Ghana', 2028, 33588)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Ghana', 2028, 2110)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Ghana', 2028, 527)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Ghana', 2028, 2637)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Ghana', 2029, 294534)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Ghana', 2029, 35290)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Ghana', 2029, 14000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Ghana', 2029, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Ghana', 2029, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Ghana', 2029, 35290)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Ghana', 2029, 14000)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Ghana', 2029, 280534)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Ghana', 2029, 280534)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Ghana', 2029, 1087800)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Ghana', 2029, 15540)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Ghana', 2029, 11281)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Ghana', 2029, 12467)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Ghana', 2029, 124681)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Ghana', 2029, 1247)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Ghana', 2029, 888)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Ghana', 2029, 1019)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Ghana', 2029, 703)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Ghana', 2029, 1529)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Ghana', 2029, 1055)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Ghana', 2029, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Ghana', 2029, 2650)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Ghana', 2029, 38225)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Ghana', 2029, 2914)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Ghana', 2029, 971)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Ghana', 2029, 3885)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Malawi', 2024, 71061)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Malawi', 2024, 35573)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Malawi', 2024, 5800)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Malawi', 2024, 16800)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Malawi', 2024, 4000)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Malawi', 2024, 18773)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Malawi', 2024, 1800)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Malawi', 2024, 69261)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Malawi', 2024, 69261)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Malawi', 2024, 262780)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Malawi', 2024, 3754)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Malawi', 2024, 2353)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Malawi', 2024, 1891)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Malawi', 2024, 36522)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Malawi', 2024, 189)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Malawi', 2024, 161)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Malawi', 2024, 234)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Malawi', 2024, 234)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Malawi', 2024, 351)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Malawi', 2024, 351)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Malawi', 2024, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Malawi', 2024, 5000)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Malawi', 2024, 8775)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Malawi', 2024, 1734)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Malawi', 2024, 143)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Malawi', 2024, 1877)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Malawi', 2025, 74843)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Malawi', 2025, 33967)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Malawi', 2025, 5800)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Malawi', 2025, 11400)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Malawi', 2025, 4000)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Malawi', 2025, 22567)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Malawi', 2025, 1800)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Malawi', 2025, 73043)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Malawi', 2025, 73043)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Malawi', 2025, 280700)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Malawi', 2025, 4010)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Malawi', 2025, 2462)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Malawi', 2025, 2462)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Malawi', 2025, 38984)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Malawi', 2025, 246)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Malawi', 2025, 166)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Malawi', 2025, 312)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Malawi', 2025, 195)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Malawi', 2025, 468)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Malawi', 2025, 293)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Malawi', 2025, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Malawi', 2025, 5000)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Malawi', 2025, 11700)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Malawi', 2025, 1853)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Malawi', 2025, 152)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Malawi', 2025, 2005)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Malawi', 2026, 79768)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Malawi', 2026, 30050)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Malawi', 2026, 3800)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Malawi', 2026, 4000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Malawi', 2026, 2000)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Malawi', 2026, 26050)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Malawi', 2026, 1800)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Malawi', 2026, 77968)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Malawi', 2026, 77968)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Malawi', 2026, 353360)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Malawi', 2026, 5048)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Malawi', 2026, 3388)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Malawi', 2026, 2745)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Malawi', 2026, 41729)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Malawi', 2026, 275)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Malawi', 2026, 192)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Malawi', 2026, 385)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Malawi', 2026, 287)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Malawi', 2026, 577)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Malawi', 2026, 431)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Malawi', 2026, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Malawi', 2026, 5200)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Malawi', 2026, 14430)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Malawi', 2026, 2329)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Malawi', 2026, 195)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Malawi', 2026, 2524)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Malawi', 2027, 85259)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Malawi', 2027, 23550)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Malawi', 2027, 3800)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Malawi', 2027, 3000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Malawi', 2027, 2000)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Malawi', 2027, 20550)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Malawi', 2027, 1800)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Malawi', 2027, 83459)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Malawi', 2027, 83459)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Malawi', 2027, 428540)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Malawi', 2027, 6122)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Malawi', 2027, 4072)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Malawi', 2027, 8008)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Malawi', 2027, 49737)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Malawi', 2027, 801)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Malawi', 2027, 705)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Malawi', 2027, 460)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Malawi', 2027, 317)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Malawi', 2027, 691)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Malawi', 2027, 475)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Malawi', 2027, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Malawi', 2027, 5300)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Malawi', 2027, 17265)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Malawi', 2027, 2799)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Malawi', 2027, -310)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Malawi', 2027, 2489)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Malawi', 2028, 101275)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Malawi', 2028, 20550)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Malawi', 2028, 3800)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Malawi', 2028, 3000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Malawi', 2028, 2000)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Malawi', 2028, 17550)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Malawi', 2028, 1800)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Malawi', 2028, 99475)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Malawi', 2028, 99475)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Malawi', 2028, 506240)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Malawi', 2028, 7232)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Malawi', 2028, 4741)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Malawi', 2028, 5278)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Malawi', 2028, 55015)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Malawi', 2028, 528)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Malawi', 2028, 175)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Malawi', 2028, 537)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Malawi', 2028, 379)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Malawi', 2028, 806)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Malawi', 2028, 569)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Malawi', 2028, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Malawi', 2028, 5100)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Malawi', 2028, 20153)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Malawi', 2028, 3292)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Malawi', 2028, -231)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Malawi', 2028, 3061)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Malawi', 2029, 139339)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Malawi', 2029, 16850)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Malawi', 2029, 3800)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Malawi', 2029, 3000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Malawi', 2029, 2000)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Malawi', 2029, 13850)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Malawi', 2029, 1800)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Malawi', 2029, 137539)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Malawi', 2029, 137539)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Malawi', 2029, 523460)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Malawi', 2029, 7478)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Malawi', 2029, 4526)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Malawi', 2029, 5915)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Malawi', 2029, 60930)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Malawi', 2029, 592)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Malawi', 2029, 504)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Malawi', 2029, 612)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Malawi', 2029, 422)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Malawi', 2029, 917)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Malawi', 2029, 633)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Malawi', 2029, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Malawi', 2029, 5300)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Malawi', 2029, 22935)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Malawi', 2029, 3402)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Malawi', 2029, 337)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Malawi', 2029, 3739)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Tanzania', 2024, 138753)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Tanzania', 2024, 26602)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Tanzania', 2024, 14000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Tanzania', 2024, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Tanzania', 2024, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Tanzania', 2024, 26602)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Tanzania', 2024, 14000)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Tanzania', 2024, 124753)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Tanzania', 2024, 124753)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Tanzania', 2024, 162540)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Tanzania', 2024, 2322)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Tanzania', 2024, 1318)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Tanzania', 2024, 8966)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Tanzania', 2024, 71343)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Tanzania', 2024, 897)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Tanzania', 2024, 223)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Tanzania', 2024, 390)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Tanzania', 2024, 390)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Tanzania', 2024, 585)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Tanzania', 2024, 585)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Tanzania', 2024, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Tanzania', 2024, 4500)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Tanzania', 2024, 14625)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Tanzania', 2024, 774)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Tanzania', 2024, 0)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Tanzania', 2024, 774)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Tanzania', 2025, 156685)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Tanzania', 2025, 36036)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Tanzania', 2025, 14000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Tanzania', 2025, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Tanzania', 2025, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Tanzania', 2025, 36036)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Tanzania', 2025, 14000)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Tanzania', 2025, 142685)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Tanzania', 2025, 142685)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Tanzania', 2025, 358890)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Tanzania', 2025, 5127)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Tanzania', 2025, 4151)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Tanzania', 2025, 4340)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Tanzania', 2025, 75683)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Tanzania', 2025, 434)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Tanzania', 2025, 323)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Tanzania', 2025, 520)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Tanzania', 2025, 325)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Tanzania', 2025, 780)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Tanzania', 2025, 487)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Tanzania', 2025, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Tanzania', 2025, 5500)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Tanzania', 2025, 19500)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Tanzania', 2025, 1282)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Tanzania', 2025, 427)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Tanzania', 2025, 1709)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Tanzania', 2026, 165366)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Tanzania', 2026, 41000)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Tanzania', 2026, 14000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Tanzania', 2026, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Tanzania', 2026, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Tanzania', 2026, 41000)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Tanzania', 2026, 14000)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Tanzania', 2026, 151366)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Tanzania', 2026, 151366)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Tanzania', 2026, 692440)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Tanzania', 2026, 9892)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Tanzania', 2026, 7910)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Tanzania', 2026, 8590)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Tanzania', 2026, 84273)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Tanzania', 2026, 859)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Tanzania', 2026, 698)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Tanzania', 2026, 641)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Tanzania', 2026, 479)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Tanzania', 2026, 962)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Tanzania', 2026, 718)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Tanzania', 2026, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Tanzania', 2026, 5700)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Tanzania', 2026, 24050)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Tanzania', 2026, 1607)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Tanzania', 2026, 866)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Tanzania', 2026, 2473)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Tanzania', 2027, 182545)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Tanzania', 2027, 41000)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Tanzania', 2027, 14000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Tanzania', 2027, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Tanzania', 2027, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Tanzania', 2027, 41000)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Tanzania', 2027, 14000)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Tanzania', 2027, 168545)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Tanzania', 2027, 168545)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Tanzania', 2027, 1073800)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Tanzania', 2027, 15340)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Tanzania', 2027, 11501)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Tanzania', 2027, 13308)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Tanzania', 2027, 97581)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Tanzania', 2027, 1331)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Tanzania', 2027, 982)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Tanzania', 2027, 767)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Tanzania', 2027, 528)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Tanzania', 2027, 1151)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Tanzania', 2027, 792)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Tanzania', 2027, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Tanzania', 2027, 5800)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Tanzania', 2027, 28775)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Tanzania', 2027, 1687)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Tanzania', 2027, 1381)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Tanzania', 2027, 3068)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Tanzania', 2028, 209162)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Tanzania', 2028, 41000)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Tanzania', 2028, 14000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Tanzania', 2028, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Tanzania', 2028, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Tanzania', 2028, 41000)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Tanzania', 2028, 14000)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Tanzania', 2028, 195162)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Tanzania', 2028, 195162)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Tanzania', 2028, 1255800)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Tanzania', 2028, 17940)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Tanzania', 2028, 11880)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Tanzania', 2028, 13308)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Tanzania', 2028, 110889)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Tanzania', 2028, 1331)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Tanzania', 2028, 840)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Tanzania', 2028, 896)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Tanzania', 2028, 632)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Tanzania', 2028, 1344)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Tanzania', 2028, 948)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Tanzania', 2028, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Tanzania', 2028, 5600)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Tanzania', 2028, 33588)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Tanzania', 2028, 1615)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Tanzania', 2028, 1973)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Tanzania', 2028, 3588)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Tanzania', 2029, 291224)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Tanzania', 2029, 41000)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Tanzania', 2029, 14000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Tanzania', 2029, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Tanzania', 2029, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Tanzania', 2029, 41000)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Tanzania', 2029, 14000)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Tanzania', 2029, 277224)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Tanzania', 2029, 277224)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Tanzania', 2029, 1415400)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Tanzania', 2029, 20220)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Tanzania', 2029, 12913)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Tanzania', 2029, 13308)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Tanzania', 2029, 124198)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Tanzania', 2029, 1331)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Tanzania', 2029, 911)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Tanzania', 2029, 1019)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Tanzania', 2029, 703)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Tanzania', 2029, 1529)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Tanzania', 2029, 1055)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Tanzania', 2029, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Tanzania', 2029, 5800)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Tanzania', 2029, 38225)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Tanzania', 2029, 1415)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Tanzania', 2029, 2629)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Tanzania', 2029, 4044)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Zambia', 2024, 65578)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Zambia', 2024, 44232)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Zambia', 2024, 10000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Zambia', 2024, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Zambia', 2024, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Zambia', 2024, 44232)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Zambia', 2024, 10000)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Zambia', 2024, 55578)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Zambia', 2024, 55578)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Zambia', 2024, 91020)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Zambia', 2024, 1517)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Zambia', 2024, 689)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Zambia', 2024, 5172)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Zambia', 2024, 32961)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Zambia', 2024, 517)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Zambia', 2024, 263)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Zambia', 2024, 234)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Zambia', 2024, 234)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Zambia', 2024, 351)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Zambia', 2024, 351)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Zambia', 2024, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Zambia', 2024, 3000)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Zambia', 2024, 8775)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Zambia', 2024, 495)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Zambia', 2024, 44)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Zambia', 2024, 539)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Zambia', 2025, 75922)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Zambia', 2025, 46492)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Zambia', 2025, 10000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Zambia', 2025, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Zambia', 2025, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Zambia', 2025, 46492)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Zambia', 2025, 10000)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Zambia', 2025, 65922)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Zambia', 2025, 65922)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Zambia', 2025, 105420)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Zambia', 2025, 1757)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Zambia', 2025, 1095)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Zambia', 2025, 6827)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Zambia', 2025, 39788)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Zambia', 2025, 683)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Zambia', 2025, 551)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Zambia', 2025, 312)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Zambia', 2025, 195)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Zambia', 2025, 468)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Zambia', 2025, 292)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Zambia', 2025, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Zambia', 2025, 3000)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Zambia', 2025, 11700)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Zambia', 2025, 489)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Zambia', 2025, 130)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Zambia', 2025, 619)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Zambia', 2026, 89576)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Zambia', 2026, 41552)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Zambia', 2026, 10000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Zambia', 2026, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Zambia', 2026, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Zambia', 2026, 41552)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Zambia', 2026, 10000)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Zambia', 2026, 79576)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Zambia', 2026, 79576)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Zambia', 2026, 160800)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Zambia', 2026, 2680)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Zambia', 2026, 1955)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Zambia', 2026, 13177)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Zambia', 2026, 52965)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Zambia', 2026, 1318)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Zambia', 2026, 1042)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Zambia', 2026, 385)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Zambia', 2026, 287)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Zambia', 2026, 577)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Zambia', 2026, 431)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Zambia', 2026, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Zambia', 2026, 3100)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Zambia', 2026, 14430)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Zambia', 2026, 503)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Zambia', 2026, 217)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Zambia', 2026, 720)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Zambia', 2027, 115930)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Zambia', 2027, 36000)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Zambia', 2027, 10000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Zambia', 2027, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Zambia', 2027, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Zambia', 2027, 36000)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Zambia', 2027, 10000)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Zambia', 2027, 105930)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Zambia', 2027, 105930)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Zambia', 2027, 226500)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Zambia', 2027, 3775)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Zambia', 2027, 2709)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Zambia', 2027, 13717)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Zambia', 2027, 66682)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Zambia', 2027, 1372)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Zambia', 2027, 851)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Zambia', 2027, 460)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Zambia', 2027, 317)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Zambia', 2027, 691)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Zambia', 2027, 475)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Zambia', 2027, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Zambia', 2027, 3200)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Zambia', 2027, 17265)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Zambia', 2027, 493)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Zambia', 2027, 322)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Zambia', 2027, 815)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Zambia', 2028, 143364)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Zambia', 2028, 36000)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Zambia', 2028, 10000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Zambia', 2028, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Zambia', 2028, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Zambia', 2028, 36000)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Zambia', 2028, 10000)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Zambia', 2028, 133364)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Zambia', 2028, 133364)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Zambia', 2028, 247200)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Zambia', 2028, 4120)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Zambia', 2028, 2612)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Zambia', 2028, 8820)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Zambia', 2028, 75502)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Zambia', 2028, 882)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Zambia', 2028, 457)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Zambia', 2028, 537)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Zambia', 2028, 379)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Zambia', 2028, 806)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Zambia', 2028, 569)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Zambia', 2028, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Zambia', 2028, 3050)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Zambia', 2028, 20153)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Zambia', 2028, 453)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Zambia', 2028, 431)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Zambia', 2028, 884)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Zambia', 2029, 198755)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Zambia', 2029, 36000)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Zambia', 2029, 10000)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Zambia', 2029, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Zambia', 2029, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Zambia', 2029, 36000)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Zambia', 2029, 10000)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Zambia', 2029, 188755)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Zambia', 2029, 188755)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Zambia', 2029, 283200)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Zambia', 2029, 4720)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Zambia', 2029, 3026)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Zambia', 2029, 8820)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Zambia', 2029, 84322)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Zambia', 2029, 882)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Zambia', 2029, 654)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Zambia', 2029, 606)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Zambia', 2029, 417)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Zambia', 2029, 910)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Zambia', 2029, 625)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Zambia', 2029, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Zambia', 2029, 3000)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Zambia', 2029, 22739)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Zambia', 2029, 416)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Zambia', 2029, 588)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Zambia', 2029, 1004)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Zimbabwe', 2024, 201765)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Zimbabwe', 2024, 29722)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Zimbabwe', 2024, 14500)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Zimbabwe', 2024, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Zimbabwe', 2024, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Zimbabwe', 2024, 29722)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Zimbabwe', 2024, 14500)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Zimbabwe', 2024, 187265)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Zimbabwe', 2024, 187265)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Zimbabwe', 2024, 395360)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Zimbabwe', 2024, 5648)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Zimbabwe', 2024, 3605)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Zimbabwe', 2024, 4654)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Zimbabwe', 2024, 97721)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Zimbabwe', 2024, 465)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Zimbabwe', 2024, 232)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Zimbabwe', 2024, 312)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Zimbabwe', 2024, 312)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Zimbabwe', 2024, 468)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Zimbabwe', 2024, 468)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Zimbabwe', 2024, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Zimbabwe', 2024, 10000)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Zimbabwe', 2024, 11700)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Zimbabwe', 2024, 1662)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Zimbabwe', 2024, 0)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Zimbabwe', 2024, 1662)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Zimbabwe', 2025, 211072)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Zimbabwe', 2025, 35189)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Zimbabwe', 2025, 14500)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Zimbabwe', 2025, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Zimbabwe', 2025, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Zimbabwe', 2025, 35189)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Zimbabwe', 2025, 14500)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Zimbabwe', 2025, 196572)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Zimbabwe', 2025, 196572)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Zimbabwe', 2025, 482160)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Zimbabwe', 2025, 6888)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Zimbabwe', 2025, 4569)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Zimbabwe', 2025, 7637)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Zimbabwe', 2025, 105358)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Zimbabwe', 2025, 764)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Zimbabwe', 2025, 647)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Zimbabwe', 2025, 416)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Zimbabwe', 2025, 260)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Zimbabwe', 2025, 624)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Zimbabwe', 2025, 390)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Zimbabwe', 2025, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Zimbabwe', 2025, 10000)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Zimbabwe', 2025, 15600)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Zimbabwe', 2025, 2222)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Zimbabwe', 2025, 0)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Zimbabwe', 2025, 2222)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Zimbabwe', 2026, 226346)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Zimbabwe', 2026, 36500)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Zimbabwe', 2026, 14500)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Zimbabwe', 2026, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Zimbabwe', 2026, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Zimbabwe', 2026, 36500)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Zimbabwe', 2026, 14500)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Zimbabwe', 2026, 211846)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Zimbabwe', 2026, 211846)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Zimbabwe', 2026, 491680)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Zimbabwe', 2026, 7024)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Zimbabwe', 2026, 4220)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Zimbabwe', 2026, 11151)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Zimbabwe', 2026, 116510)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Zimbabwe', 2026, 1115)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Zimbabwe', 2026, 791)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Zimbabwe', 2026, 513)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Zimbabwe', 2026, 383)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Zimbabwe', 2026, 770)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Zimbabwe', 2026, 575)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Zimbabwe', 2026, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Zimbabwe', 2026, 10400)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Zimbabwe', 2026, 19240)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Zimbabwe', 2026, 2232)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Zimbabwe', 2026, 24)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Zimbabwe', 2026, 2256)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Zimbabwe', 2027, 248648)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Zimbabwe', 2027, 36500)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Zimbabwe', 2027, 14500)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Zimbabwe', 2027, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Zimbabwe', 2027, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Zimbabwe', 2027, 36500)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Zimbabwe', 2027, 14500)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Zimbabwe', 2027, 234148)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Zimbabwe', 2027, 234148)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Zimbabwe', 2027, 516320)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Zimbabwe', 2027, 7376)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Zimbabwe', 2027, 4455)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Zimbabwe', 2027, 12260)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Zimbabwe', 2027, 128769)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Zimbabwe', 2027, 1226)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Zimbabwe', 2027, 830)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Zimbabwe', 2027, 614)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Zimbabwe', 2027, 422)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Zimbabwe', 2027, 921)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Zimbabwe', 2027, 634)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Zimbabwe', 2027, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Zimbabwe', 2027, 10550)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Zimbabwe', 2027, 23020)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Zimbabwe', 2027, 2255)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Zimbabwe', 2027, 89)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Zimbabwe', 2027, 2344)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Zimbabwe', 2028, 273168)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Zimbabwe', 2028, 36500)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Zimbabwe', 2028, 14500)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Zimbabwe', 2028, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Zimbabwe', 2028, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Zimbabwe', 2028, 36500)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Zimbabwe', 2028, 14500)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Zimbabwe', 2028, 258668)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Zimbabwe', 2028, 258668)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Zimbabwe', 2028, 556080)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Zimbabwe', 2028, 7944)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Zimbabwe', 2028, 4880)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Zimbabwe', 2028, 12260)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Zimbabwe', 2028, 141029)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Zimbabwe', 2028, 1226)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Zimbabwe', 2028, 811)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Zimbabwe', 2028, 717)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Zimbabwe', 2028, 505)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Zimbabwe', 2028, 1075)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Zimbabwe', 2028, 756)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Zimbabwe', 2028, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Zimbabwe', 2028, 10200)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Zimbabwe', 2028, 26870)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Zimbabwe', 2028, 2288)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Zimbabwe', 2028, 198)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Zimbabwe', 2028, 2486)
, ('1.1+1.2', 'Girls receiving economic, social and academic support (5 million 2030 target)', 'Newly supported', 'Girls Total', 'Zimbabwe', 2029, 368484)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Annual', 'Girls Total', 'Zimbabwe', 2029, 36500)
, ('1.1', 'Number of girls receiving CAMFED bursary support', 'Newly supported', 'Girls Total', 'Zimbabwe', 2029, 14500)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Annual', 'Primary girls', 'Zimbabwe', 2029, 0)
, ('1.1a', 'Number of children supported to go to school by CAMFED at primary level', 'Newly supported', 'Primary girls', 'Zimbabwe', 2029, 0)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Annual', 'Secondary girls', 'Zimbabwe', 2029, 36500)
, ('1.1b', 'Number of children supported to go to school by CAMFED at secondary level', 'Newly supported', 'Secondary girls', 'Zimbabwe', 2029, 14500)
, ('1.2', 'Number of girls supported to go to school by CAMA and community support (compared to CAMA target)', 'Newly supported', 'Girls total', 'Zimbabwe', 2029, 353984)
, ('1.2a', 'Number of children supported to go to school by CAMA', 'Newly supported', 'Girls total', 'Zimbabwe', 2029, 353984)
, ('1.3', 'Number of children receiving social and learning support  (15 million 2030 target)', 'Newly reached', 'Total', 'Zimbabwe', 2029, 577920)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Annual', 'Zimbabwe', 2029, 8256)
, ('1.9', 'Number of Learner Guides (new/active/cumulative). Disaggregated by CAMFED trained/ government trained.', 'Total', 'Newly trained', 'Zimbabwe', 2029, 4967)
, ('2.1', 'Total number of CAMA members', 'New since last year', 'Newly trained', 'Zimbabwe', 2029, 12260)
, ('2.1', 'Total number of CAMA members', 'Cumulative', 'Newly trained', 'Zimbabwe', 2029, 153289)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Annual', 'Zimbabwe', 2029, 1226)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Transition Guides', 'Newly trained', 'Zimbabwe', 2029, 820)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Annual', 'Zimbabwe', 2029, 815)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Agriculture Guides', 'Newly trained', 'Zimbabwe', 2029, 564)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Annual', 'Zimbabwe', 2029, 1223)
, ('2.2', 'Number of active guides (Transition guides, Business guides, Agriculture guides)', 'Business Guides', 'Newly trained', 'Zimbabwe', 2029, 845)
, ('2.4', 'Percentage of young women who transition towards a secure livelihood (through paid employment, entrepreneurship or further study) within 12 months of participating in the Transition Programme.', 'Annual', 'Newly trained', 'Zimbabwe', 2029, 75)
, ('2.6', 'Number of female entrepreneurs that succeed in setting up a business', 'Annual', 'Newly trained', 'Zimbabwe', 2029, 10550)
, ('2.7', 'Number of businesses supported by the Enterprise Guides (BGs and AGs)', 'All Enterprise Guides', 'Annual', 'Zimbabwe', 2029, 30580)
, ('3.2', 'Total number of schools in which LGs are operating', 'CAMFED supported', 'Total', 'Zimbabwe', 2029, 2305)
, ('3.2', 'Total number of schools in which LGs are operating', 'Government delivery', 'Total', 'Zimbabwe', 2029, 259)
, ('3.2', 'Total number of schools in which LGs are operating', 'Total', 'Total', 'Zimbabwe', 2029, 2564)
;


-- ── RPC ───────────────────────────────────────────────────────────────────────
-- Returns target values keyed by dashlet_element + country, for a given year.
-- Joins ip_targets to kpi_mapping so the caller only needs dashlet element IDs.
-- NULL/empty disagg values on both sides are matched with IS NOT DISTINCT FROM.
CREATE OR REPLACE FUNCTION rep_portal.get_dashlet_targets(
  p_dashlet_elements integer[],
  p_year             integer
)
RETURNS TABLE(dashlet_element integer, country text, target_value double precision)
LANGUAGE sql STABLE
SECURITY DEFINER SET search_path = rep_portal, rep_warehouse, pg_temp
AS $$
  SELECT
    km.dashlet_element,
    t.country,
    SUM(t.target_value)::double precision AS target_value
  FROM rep_portal.ip_targets t
  JOIN rep_portal.kpi_mapping km
    ON  km.kpi_id = t.indicator_code
    AND (km.disaggregation_level_one IS NOT DISTINCT FROM NULLIF(t.disagg_level_one, ''))
    AND (km.disaggregation_level_two IS NOT DISTINCT FROM NULLIF(t.disagg_level_two, ''))
  WHERE t.year = p_year
    AND km.dashlet_element = ANY(p_dashlet_elements)
  GROUP BY km.dashlet_element, t.country
$$;

REVOKE ALL ON FUNCTION rep_portal.get_dashlet_targets(integer[], integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_dashlet_targets(integer[], integer) TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_dashlet_targets(integer[], integer) TO anon;

-- ===== 20260617000002_fix_targets_cama_and_p1.sql =====
-- Fix 1: Add P1 rows derived from 1.1+1.2 data (Total Girls supported = Bursary + CAMA).
-- kpi_mapping maps elements 5/6 to kpi_id='P1', disagg='Newly supported'/'Annual', 'Girls total'.
-- There are no boys targets in the Excel, so elements 7/8 remain without target lines.
INSERT INTO rep_portal.ip_targets (indicator_code, indicator, disagg_level_one, disagg_level_two, country, year, target_value)
SELECT
  'P1',
  'Total girls receiving economic, social and academic support',
  disagg_level_one,
  'Girls total',
  country,
  year,
  target_value
FROM rep_portal.ip_targets
WHERE indicator_code = '1.1+1.2'
ON CONFLICT DO NOTHING;

-- Fix 2: Patch get_dashlet_targets to use case-insensitive comparison on disagg_level_two.
-- This fixes the CAMA mismatch: kpi_mapping has 'Girls Total' but ip_targets has 'Girls total'.
CREATE OR REPLACE FUNCTION rep_portal.get_dashlet_targets(
  p_dashlet_elements integer[],
  p_year             integer
)
RETURNS TABLE(dashlet_element integer, country text, target_value double precision)
LANGUAGE sql STABLE SECURITY DEFINER SET search_path = rep_portal, rep_warehouse, pg_temp AS $$
  SELECT
    km.dashlet_element,
    t.country,
    SUM(t.target_value)::double precision
  FROM rep_portal.ip_targets t
  JOIN rep_portal.kpi_mapping km
    ON  km.kpi_id = t.indicator_code
    AND (km.disaggregation_level_one IS NOT DISTINCT FROM NULLIF(t.disagg_level_one, ''))
    AND (LOWER(COALESCE(km.disaggregation_level_two, '')) = LOWER(COALESCE(NULLIF(t.disagg_level_two, ''), '')))
  WHERE t.year = p_year
    AND km.dashlet_element = ANY(p_dashlet_elements)
  GROUP BY km.dashlet_element, t.country
$$;

REVOKE ALL ON FUNCTION rep_portal.get_dashlet_targets(integer[], integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_dashlet_targets(integer[], integer) TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_dashlet_targets(integer[], integer) TO anon;


-- ===== 20260617111852_add_ingest_sf_counts.sql =====
-- Snapshot of the Salesforce-reported total record count for each object at
-- ingest time, so warehouse reconciliation can compare against what Salesforce
-- said *at the moment of the load* instead of a live count taken later (which
-- drifts as Salesforce data keeps changing).
--
-- This is always the object's full count (other filters such as RecordType
-- preserved, but the `since` delta filter ignored) — never the delta/diff
-- count — via a separate `SELECT COUNT() FROM ...` query, so it stays
-- comparable to a full rep_warehouse row count on both full and delta runs.
--
-- Populated by both ingest paths:
--   - ingest-orchestrator: fetchSfCount() in _shared/salesforce.ts (REST API)
--   - run-ingest.js: sfQueryCount() (REST API, separate from the Bulk API job)

CREATE TABLE rep_warehouse.ingest_sf_counts (
  run_id         TEXT        NOT NULL REFERENCES rep_warehouse.ingest_run (run_id) ON DELETE CASCADE,
  rep_raw_table  TEXT        NOT NULL,
  sf_total_count INT         NOT NULL,
  captured_at    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (run_id, rep_raw_table)
);

GRANT ALL ON rep_warehouse.ingest_sf_counts TO service_role;

ALTER TABLE rep_warehouse.ingest_sf_counts ENABLE ROW LEVEL SECURITY;
GRANT SELECT ON rep_warehouse.ingest_sf_counts TO authenticated;

CREATE POLICY admin_read_ingest_sf_counts
    ON rep_warehouse.ingest_sf_counts
    FOR SELECT TO authenticated
    USING (rep_warehouse.is_admin());


-- ===== 20260618092009_exclude_intl_uk_us_from_warehouse.sql =====
-- Exclude International / United Kingdom / United States (and dependent
-- records) from reaching rep_warehouse. Filtering happens at the staging
-- layer: every rep_warehouse load reads exclusively from rep_staging.*, so
-- excluding rows here keeps them out of dim_geography, dim_school,
-- dim_contact, and all fact_* tables without touching etl_run_warehouse().

CREATE OR REPLACE FUNCTION rep_warehouse.country_is_excluded(p_country text)
RETURNS boolean LANGUAGE sql IMMUTABLE AS $$
    SELECT lower(trim(coalesce(p_country, ''))) IN ('international', 'united kingdom', 'united states');
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_countries()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.countries;
    CREATE TABLE rep_staging.countries AS
    SELECT
        salesforce_id,
        country_name,
        unique_id
    FROM rep_raw.countries
    WHERE country_name IS NOT NULL
      AND NOT rep_warehouse.country_is_excluded(country_name);
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_districts()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.districts;
    CREATE TABLE rep_staging.districts AS
    SELECT
        salesforce_id,
        country_id,
        district_name,
        province,
        terrain,
        (active_partner_district = 'true') AS active_partner_district,
        date_camfed_began_work,
        country_name,
        region_id,
        unique_id
    FROM rep_raw.districts
    WHERE district_name IS NOT NULL
      AND NOT rep_warehouse.country_is_excluded(country_name);
END;
$$;

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
      AND NOT rep_warehouse.country_is_excluded(country_name);
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_schools()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.schools;
    CREATE TABLE rep_staging.schools AS
    SELECT
        salesforce_id                         AS school_id,
        school_name,
        province,
        district_id,
        district_name                         AS district,
        country,
        school_type,
        accommodation_type,
        date_camfed_began_support,
        number_of_active_lgs                  AS active_lg_count,
        (school_active_on_bursary = 'true')   AS active_on_bursary,
        (active_partner_school = 'true')      AS active_partner_school,
        (affiliated_school = 'true')          AS affiliated_school,
        (cpp_in_place = 'true')               AS cpp_in_place,
        (snf_only_school = 'true')            AS snf_only,
        (monitoring_school = 'true')          AS monitoring_school,
        (gea_school = 'true')                 AS gea_school,
        (merp = 'true')                       AS merp,
        latitude,
        longitude,
        donor_id,
        unique_id
    FROM rep_raw.schools
    WHERE salesforce_id IS NOT NULL
      AND NOT rep_warehouse.country_is_excluded(country);
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
        country_name                           AS country,
        contact_record_type,
        form,
        CASE WHEN year ~ '^\d{4}$' THEN year::smallint END AS year,
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
      AND (academic_record_type IS NULL OR academic_record_type != 'Post School')
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
        country_name                           AS country,
        contact_record_type,
        form,
        CASE WHEN year ~ '^\d{4}$' THEN year::smallint END AS year,
        (received_financial_support = 'true')  AS received_financial_support,
        accommodation,
        donor_code_id,
        start_date,
        end_date
    FROM rep_raw.academic_record
    WHERE person_id IS NOT NULL
      AND academic_record_type = 'Post School'
      AND NOT rep_warehouse.country_is_excluded(country_name);
END;
$$;

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
        COALESCE(sc.active_partner_school, false)    AS partner_school
    FROM rep_raw.contacts c
    LEFT JOIN rep_staging.schools sc ON sc.school_id = c.school_id
    WHERE c.salesforce_id IS NOT NULL
      AND c.record_type_name = 'Cama'
      AND NOT rep_warehouse.country_is_excluded(c.country_name);
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_grant_recipients()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.grant_recipients;
    CREATE TABLE rep_staging.grant_recipients AS
    SELECT
        row_id,
        salesforce_id                 AS grant_id,
        person_id                     AS contact_id,
        contact_record_type,
        district_id                   AS district,
        country,
        record_type_id                AS grant_type,
        status                        AS grant_status,
        amount_given,
        grant_date,
        donor_id
    FROM rep_raw.grant_recipients
    WHERE salesforce_id IS NOT NULL
      AND NOT rep_warehouse.country_is_excluded(country);
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_loan_recipients()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.loan_recipients;
    CREATE TABLE rep_staging.loan_recipients AS
    SELECT
        row_id,
        salesforce_id                 AS loan_id,
        client_id,
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
    WHERE salesforce_id IS NOT NULL
      AND NOT rep_warehouse.country_is_excluded(country);
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
      AND NOT rep_warehouse.country_is_excluded(COALESCE(rs.country, rd.country_name));
END;
$$;


-- ===== 20260618120411_filter_academic_records_type_and_year.sql =====
-- Tighten the academic_record staging split:
--   1. children_supported (rep_staging.academic_record) now requires
--      academic_record_type IN ('School', 'Step Up Fund') -- 'Other' is
--      excluded (previously anything != 'Post School' was let through).
--   2. Both splits now require a valid 4-digit year >= 2020; rows with a
--      missing/invalid year are excluded.
-- post_school_clients keeps its existing academic_record_type = 'Post School'
-- filter unchanged. country_is_excluded() filtering (20260618092009) is
-- preserved as-is.
--
-- Note: fact_children_supported does not retain academic_record_type, and
-- rep_raw.academic_record is truncated after every successful ETL run, so
-- already-warehoused 'Other'-type rows cannot be identified retroactively.
-- A full re-ingest is required to apply the type exclusion to historical
-- data; see scripts/cleanup-pre-2020-academic-records.sql for the
-- retroactive year-only cleanup.

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
        (received_financial_support = 'true')  AS received_financial_support,
        accommodation,
        donor_code_id,
        start_date,
        end_date
    FROM rep_raw.academic_record
    WHERE person_id IS NOT NULL
      AND academic_record_type = 'Post School'
      AND year ~ '^\d{4}$'
      AND year::smallint >= 2020
      AND NOT rep_warehouse.country_is_excluded(country_name);
END;
$$;


-- ===== 20260618121709_filter_guides_type_and_date.sql =====
-- Tighten the guides staging filter:
--   1. Restrict guide_type to the five active programme roles (Learner
--      Guide, Learner Mentor, Transition Guide, Agriculture Guide,
--      Business Guide) -- other/legacy guide types are excluded.
--   2. Require date_joined_guide_programme >= 2013-01-01; rows with a
--      missing/unparseable date are excluded (NULL comparison is not true).
-- country_is_excluded() filtering (20260618092009) is preserved as-is.
--
-- Note: rep_raw.guides is truncated after every successful ETL run, so
-- already-warehoused rows outside this filter cannot be identified
-- retroactively from rep_raw. A full re-ingest is required to apply this
-- filter to historical fact_guide_assignment rows.

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
      AND NOT rep_warehouse.country_is_excluded(COALESCE(rs.country, rd.country_name));
END;
$$;


-- ===== 20260618130048_filter_grants_loans_disbursal_date.sql =====
-- Filter grant and loan staging to disbursal date 2020-01-01 or later.
-- grant_recipients uses grant_date (Salesforce Date__c) as its disbursal
-- date equivalent; loan_recipients uses disbursal_date (Disbursal_Date__c).
-- Rows with a missing/blank date are excluded (NULL comparison is not true).
-- country_is_excluded() filtering (20260618092009) is preserved as-is.
--
-- Note: rep_raw.grant_recipients / rep_raw.loan_recipients are truncated
-- after every successful ETL run, so already-warehoused pre-2020 rows in
-- fact_grants / fact_loans cannot be identified retroactively from rep_raw.
-- A full re-ingest is required to apply this filter to historical data.

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_grant_recipients()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.grant_recipients;
    CREATE TABLE rep_staging.grant_recipients AS
    SELECT
        row_id,
        salesforce_id                 AS grant_id,
        person_id                     AS contact_id,
        contact_record_type,
        district_id                   AS district,
        country,
        record_type_id                AS grant_type,
        status                        AS grant_status,
        amount_given,
        grant_date,
        donor_id
    FROM rep_raw.grant_recipients
    WHERE salesforce_id IS NOT NULL
      AND grant_date::date >= '2020-01-01'
      AND NOT rep_warehouse.country_is_excluded(country);
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_loan_recipients()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.loan_recipients;
    CREATE TABLE rep_staging.loan_recipients AS
    SELECT
        row_id,
        salesforce_id                 AS loan_id,
        client_id,
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
    WHERE salesforce_id IS NOT NULL
      AND disbursal_date::date >= '2020-01-01'
      AND NOT rep_warehouse.country_is_excluded(country);
END;
$$;


-- ===== 20260618131521_filter_schools_active_partner_and_linked.sql =====
-- Restrict rep_staging.schools to active partner schools
-- (Active_Partner_School__c = true), and cascade that exclusion to every
-- staging table that links to a school: contacts, academic_record, guides,
-- cama_members. A row with no school_id at all is unaffected -- there is
-- nothing to filter on. country_is_excluded() filtering (20260618092009) is
-- preserved as-is.
--
-- Note: rep_raw tables are truncated after every successful ETL run, so
-- already-warehoused rows outside this filter cannot be identified
-- retroactively. A full re-ingest is required to apply this filter to
-- historical dim_school / fact rows.

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_schools()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.schools;
    CREATE TABLE rep_staging.schools AS
    SELECT
        salesforce_id                         AS school_id,
        school_name,
        province,
        district_id,
        district_name                         AS district,
        country,
        school_type,
        accommodation_type,
        date_camfed_began_support,
        number_of_active_lgs                  AS active_lg_count,
        (school_active_on_bursary = 'true')   AS active_on_bursary,
        (active_partner_school = 'true')      AS active_partner_school,
        (affiliated_school = 'true')          AS affiliated_school,
        (cpp_in_place = 'true')               AS cpp_in_place,
        (snf_only_school = 'true')            AS snf_only,
        (monitoring_school = 'true')          AS monitoring_school,
        (gea_school = 'true')                 AS gea_school,
        (merp = 'true')                       AS merp,
        latitude,
        longitude,
        donor_id,
        unique_id
    FROM rep_raw.schools
    WHERE salesforce_id IS NOT NULL
      AND active_partner_school = 'true'
      AND NOT rep_warehouse.country_is_excluded(country);
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
    LEFT JOIN rep_raw.schools rs ON rs.salesforce_id = c.school_id
    WHERE c.salesforce_id IS NOT NULL
      AND NOT rep_warehouse.country_is_excluded(c.country_name)
      AND (c.school_id IS NULL OR rs.active_partner_school = 'true');
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_academic_record()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.academic_record;
    CREATE TABLE rep_staging.academic_record AS
    SELECT
        a.row_id,
        a.salesforce_id,
        a.person_id                              AS contact_id,
        a.school_institution_id                  AS school_id,
        a.district_id,
        a.district_name                          AS district,
        a.country_name                           AS country,
        a.contact_record_type,
        a.form,
        CASE WHEN a.year ~ '^\d{4}$' THEN a.year::smallint END AS year,
        (a.received_financial_support = 'true')  AS received_financial_support,
        (a.repeated = 'true')                    AS repeated,
        (a.attendance_issues = 'true')           AS attendance_issues,
        a.accommodation,
        a.donor_code_id,
        a.project_code_id,
        a.donor_activity_id,
        a.start_date,
        a.end_date
    FROM rep_raw.academic_record a
    LEFT JOIN rep_raw.schools rs ON rs.salesforce_id = a.school_institution_id
    WHERE a.person_id IS NOT NULL
      AND (a.academic_record_type IS NULL OR a.academic_record_type != 'Post School')
      AND (a.school_institution_id IS NULL OR rs.active_partner_school = 'true')
      AND NOT rep_warehouse.country_is_excluded(a.country_name);
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
      AND (g.school_id IS NULL OR rs.active_partner_school = 'true')
      AND NOT rep_warehouse.country_is_excluded(COALESCE(rs.country, rd.country_name));
END;
$$;

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
        COALESCE(sc.active_partner_school, false)    AS partner_school
    FROM rep_raw.contacts c
    LEFT JOIN rep_staging.schools sc ON sc.school_id = c.school_id
    WHERE c.salesforce_id IS NOT NULL
      AND c.record_type_name = 'Cama'
      AND (c.school_id IS NULL OR sc.school_id IS NOT NULL)
      AND NOT rep_warehouse.country_is_excluded(c.country_name);
END;
$$;


-- ===== 20260618132344_require_linked_school_on_staging.sql =====
-- Tighten 20260618131521: a linked school is now required, not optional.
-- contacts, academic_record, guides, and cama_members must have a non-null
-- school_id that resolves to an active partner school -- rows with no
-- school link are now excluded too (previously they were kept).
-- country_is_excluded() filtering is preserved as-is.

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
    JOIN rep_raw.schools rs ON rs.salesforce_id = c.school_id
    WHERE c.salesforce_id IS NOT NULL
      AND rs.active_partner_school = 'true'
      AND NOT rep_warehouse.country_is_excluded(c.country_name);
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_academic_record()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.academic_record;
    CREATE TABLE rep_staging.academic_record AS
    SELECT
        a.row_id,
        a.salesforce_id,
        a.person_id                              AS contact_id,
        a.school_institution_id                  AS school_id,
        a.district_id,
        a.district_name                          AS district,
        a.country_name                           AS country,
        a.contact_record_type,
        a.form,
        CASE WHEN a.year ~ '^\d{4}$' THEN a.year::smallint END AS year,
        (a.received_financial_support = 'true')  AS received_financial_support,
        (a.repeated = 'true')                    AS repeated,
        (a.attendance_issues = 'true')           AS attendance_issues,
        a.accommodation,
        a.donor_code_id,
        a.project_code_id,
        a.donor_activity_id,
        a.start_date,
        a.end_date
    FROM rep_raw.academic_record a
    JOIN rep_raw.schools rs ON rs.salesforce_id = a.school_institution_id
    WHERE a.person_id IS NOT NULL
      AND (a.academic_record_type IS NULL OR a.academic_record_type != 'Post School')
      AND rs.active_partner_school = 'true'
      AND NOT rep_warehouse.country_is_excluded(a.country_name);
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
    JOIN rep_raw.schools rs ON rs.salesforce_id = g.school_id
    WHERE g.contact_id IS NOT NULL
      AND g.guide_type IN ('Learner Guide', 'Learner Mentor', 'Transition Guide', 'Agriculture Guide', 'Business Guide')
      AND g.date_joined_guide_programme::date >= '2013-01-01'
      AND rs.active_partner_school = 'true'
      AND NOT rep_warehouse.country_is_excluded(rs.country);
END;
$$;

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
      AND NOT rep_warehouse.country_is_excluded(c.country_name);
END;
$$;


-- ===== 20260618133757_filter_districts_active_partner_and_cascade.sql =====
-- Restrict rep_staging.districts to active partner districts
-- (Active_Partner_District__c = true), and cascade that exclusion to every
-- staging table that links to a district through a real Salesforce lookup
-- ID: schools (district_id), and -- via the school they require -- contacts,
-- academic_record, and guides. cama_members joins rep_staging.schools
-- (already filtered) and inherits the restriction with no code change.
-- grant_recipients/loan_recipients only carry a district *name* (formula
-- text, no lookup ID) and are intentionally out of scope here.
-- active_partner_school and country_is_excluded() filtering are preserved
-- as-is.
--
-- Note: rep_raw tables are truncated after every successful ETL run, so
-- already-warehoused rows outside this filter cannot be identified
-- retroactively. A full re-ingest is required to apply this filter to
-- historical dim_school / dim_geography / fact rows.

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_districts()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.districts;
    CREATE TABLE rep_staging.districts AS
    SELECT
        salesforce_id,
        country_id,
        district_name,
        province,
        terrain,
        (active_partner_district = 'true') AS active_partner_district,
        date_camfed_began_work,
        country_name,
        region_id,
        unique_id
    FROM rep_raw.districts
    WHERE district_name IS NOT NULL
      AND active_partner_district = 'true'
      AND NOT rep_warehouse.country_is_excluded(country_name);
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_schools()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.schools;
    CREATE TABLE rep_staging.schools AS
    SELECT
        s.salesforce_id                         AS school_id,
        s.school_name,
        s.province,
        s.district_id,
        s.district_name                         AS district,
        s.country,
        s.school_type,
        s.accommodation_type,
        s.date_camfed_began_support,
        s.number_of_active_lgs                  AS active_lg_count,
        (s.school_active_on_bursary = 'true')   AS active_on_bursary,
        (s.active_partner_school = 'true')      AS active_partner_school,
        (s.affiliated_school = 'true')          AS affiliated_school,
        (s.cpp_in_place = 'true')               AS cpp_in_place,
        (s.snf_only_school = 'true')            AS snf_only,
        (s.monitoring_school = 'true')          AS monitoring_school,
        (s.gea_school = 'true')                 AS gea_school,
        (s.merp = 'true')                       AS merp,
        s.latitude,
        s.longitude,
        s.donor_id,
        s.unique_id
    FROM rep_raw.schools s
    JOIN rep_raw.districts d ON d.salesforce_id = s.district_id
    WHERE s.salesforce_id IS NOT NULL
      AND s.active_partner_school = 'true'
      AND d.active_partner_district = 'true'
      AND NOT rep_warehouse.country_is_excluded(s.country);
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
    JOIN rep_raw.schools rs   ON rs.salesforce_id = c.school_id
    JOIN rep_raw.districts d  ON d.salesforce_id = rs.district_id
    WHERE c.salesforce_id IS NOT NULL
      AND rs.active_partner_school = 'true'
      AND d.active_partner_district = 'true'
      AND NOT rep_warehouse.country_is_excluded(c.country_name);
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_academic_record()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.academic_record;
    CREATE TABLE rep_staging.academic_record AS
    SELECT
        a.row_id,
        a.salesforce_id,
        a.person_id                              AS contact_id,
        a.school_institution_id                  AS school_id,
        a.district_id,
        a.district_name                          AS district,
        a.country_name                            AS country,
        a.contact_record_type,
        a.form,
        CASE WHEN a.year ~ '^\d{4}$' THEN a.year::smallint END AS year,
        (a.received_financial_support = 'true')  AS received_financial_support,
        (a.repeated = 'true')                    AS repeated,
        (a.attendance_issues = 'true')           AS attendance_issues,
        a.accommodation,
        a.donor_code_id,
        a.project_code_id,
        a.donor_activity_id,
        a.start_date,
        a.end_date
    FROM rep_raw.academic_record a
    JOIN rep_raw.schools rs   ON rs.salesforce_id = a.school_institution_id
    JOIN rep_raw.districts d  ON d.salesforce_id = rs.district_id
    WHERE a.person_id IS NOT NULL
      AND (a.academic_record_type IS NULL OR a.academic_record_type != 'Post School')
      AND rs.active_partner_school = 'true'
      AND d.active_partner_district = 'true'
      AND NOT rep_warehouse.country_is_excluded(a.country_name);
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
    JOIN rep_raw.schools rs   ON rs.salesforce_id = g.school_id
    JOIN rep_raw.districts d  ON d.salesforce_id = rs.district_id
    WHERE g.contact_id IS NOT NULL
      AND g.guide_type IN ('Learner Guide', 'Learner Mentor', 'Transition Guide', 'Agriculture Guide', 'Business Guide')
      AND g.date_joined_guide_programme::date >= '2013-01-01'
      AND rs.active_partner_school = 'true'
      AND d.active_partner_district = 'true'
      AND NOT rep_warehouse.country_is_excluded(rs.country);
END;
$$;


-- ===== 20260618135403_fix_academic_record_type_and_year_regression.sql =====
-- 20260618133757 (district/school cascade) rebuilt etl_stage_academic_record()
-- from the pre-20260618120411 version, silently dropping two filters added
-- earlier that day:
--   1. academic_record_type IN ('School', 'Step Up Fund') -- regressed to
--      "anything != 'Post School'", letting 'Other' rows back in.
--   2. year ~ '^\d{4}$' AND year::smallint >= 2020 -- regressed to a CASE
--      that nulls out bad years instead of excluding the row, with no 2020
--      floor at all.
-- This migration re-applies both filters on top of the active-partner
-- school/district cascade and country_is_excluded() filtering, which are
-- preserved as-is.

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_academic_record()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.academic_record;
    CREATE TABLE rep_staging.academic_record AS
    SELECT
        a.row_id,
        a.salesforce_id,
        a.person_id                              AS contact_id,
        a.school_institution_id                  AS school_id,
        a.district_id,
        a.district_name                          AS district,
        a.country_name                            AS country,
        a.contact_record_type,
        a.form,
        a.year::smallint                         AS year,
        (a.received_financial_support = 'true')  AS received_financial_support,
        (a.repeated = 'true')                    AS repeated,
        (a.attendance_issues = 'true')           AS attendance_issues,
        a.accommodation,
        a.donor_code_id,
        a.project_code_id,
        a.donor_activity_id,
        a.start_date,
        a.end_date
    FROM rep_raw.academic_record a
    JOIN rep_raw.schools rs   ON rs.salesforce_id = a.school_institution_id
    JOIN rep_raw.districts d  ON d.salesforce_id = rs.district_id
    WHERE a.person_id IS NOT NULL
      AND a.academic_record_type IN ('School', 'Step Up Fund')
      AND a.year ~ '^\d{4}$'
      AND a.year::smallint >= 2020
      AND rs.active_partner_school = 'true'
      AND d.active_partner_district = 'true'
      AND NOT rep_warehouse.country_is_excluded(a.country_name);
END;
$$;


-- ===== 20260618141046_require_linked_school_on_post_school_clients.sql =====
-- post_school_clients was the one academic_record-derived staging split left
-- out of the active-partner cascade applied to academic_record/schools/
-- contacts/guides (20260618132344, 20260618133757), even though
-- rep_raw.academic_record carries the same school_institution_id lookup for
-- Post School rows. Bring it in line: require a linked school, and require
-- that school and its district both be active partners.
-- year/type/country filtering (20260618120411) is preserved as-is.
--
-- fact_post_school_support has no source_school_id column (geography is
-- resolved by country/district name), so school_id is added to
-- rep_staging.post_school_clients only to support this filter, not to flow
-- into the fact load.

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_post_school_clients()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.post_school_clients;
    CREATE TABLE rep_staging.post_school_clients AS
    SELECT
        a.row_id,
        a.salesforce_id,
        a.person_id                              AS contact_id,
        a.school_institution_id                  AS school_id,
        a.district_id,
        a.district_name                          AS district,
        a.country_name                            AS country,
        a.contact_record_type,
        a.form,
        a.year::smallint                         AS year,
        (a.received_financial_support = 'true')  AS received_financial_support,
        a.accommodation,
        a.donor_code_id,
        a.start_date,
        a.end_date
    FROM rep_raw.academic_record a
    JOIN rep_raw.schools rs   ON rs.salesforce_id = a.school_institution_id
    JOIN rep_raw.districts d  ON d.salesforce_id = rs.district_id
    WHERE a.person_id IS NOT NULL
      AND a.academic_record_type = 'Post School'
      AND a.year ~ '^\d{4}$'
      AND a.year::smallint >= 2020
      AND rs.active_partner_school = 'true'
      AND d.active_partner_district = 'true'
      AND NOT rep_warehouse.country_is_excluded(a.country_name);
END;
$$;


-- ===== 20260618173543_require_geography_match_grants_loans.sql =====
-- fact_grants/fact_loans previously loaded rows even when neither the
-- (country, district) nor the country-only fallback matched a current
-- dim_geography row, leaving geography_id NULL ("country" blank in
-- get_warehouse_counts()). Require a geography match going forward: rows
-- whose country can't be resolved against dim_geography are no longer
-- saved. All other facts already require a resolvable geography via their
-- school/district lookups, so this is grants/loans-only.

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_fact_grants()
RETURNS void LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.fact_grants
        (source_grant_id, source_contact_id, contact_id, geography_id,
         grant_type, grant_status, amount_given, grant_date, grant_date_id, roc_donor_id,
         lin_is_current, lin_change_type, lin_source_system, lin_source_file,
         lin_load_batch_id, lin_business_hash, lin_source_row_number)
    SELECT
        s.grant_id, s.contact_id, dct.id,
        COALESCE(dg_d.id, dg_c.id),
        s.grant_type, s.grant_status, s.amount_given::numeric, s.grant_date::timestamp, dd.id,
        d3.id,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        MD5(COALESCE(s.grant_id, '')),
        s.row_id
    FROM rep_staging.grant_recipients s
    LEFT JOIN rep_warehouse.dim_contact   dct  ON dct.source_contact_id = s.contact_id  AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date      dd   ON dd.id = TO_CHAR(s.grant_date::timestamp, 'YYYYMMDD')::integer
    LEFT JOIN rep_warehouse.dim_roc_donor d3   ON d3.source_roc_id = s.donor_id         AND d3.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_geography dg_d ON dg_d.country = s.country AND dg_d.district = s.district AND dg_d.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_geography dg_c ON dg_c.country = s.country AND dg_c.province IS NULL AND dg_c.district IS NULL AND dg_c.scd_is_current = true
    WHERE COALESCE(dg_d.id, dg_c.id) IS NOT NULL
    ON CONFLICT (source_grant_id) DO NOTHING;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_fact_loans()
RETURNS void LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.fact_loans
        (source_loan_id, geography_id, loan_type, status, loan_status,
         disbursal_date, disbursal_date_id,
         loan_value, currency_iso_code, contact_record_id, roc_donor_id,
         lin_is_current, lin_change_type, lin_source_system, lin_source_file,
         lin_load_batch_id, lin_business_hash, lin_source_row_number)
    SELECT
        s.loan_id,
        COALESCE(dg_d.id, dg_c.id),
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
    LEFT JOIN rep_warehouse.dim_date      dd   ON dd.id = TO_CHAR(s.disbursal_date::timestamp, 'YYYYMMDD')::integer
    LEFT JOIN rep_warehouse.dim_roc_donor d3   ON d3.source_roc_id = s.donor_code_id AND d3.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_geography dg_d ON dg_d.country = s.country AND dg_d.district = s.district AND dg_d.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_geography dg_c ON dg_c.country = s.country AND dg_c.province IS NULL AND dg_c.district IS NULL AND dg_c.scd_is_current = true
    WHERE COALESCE(dg_d.id, dg_c.id) IS NOT NULL
    ON CONFLICT (source_loan_id) DO NOTHING;
END;
$$;


-- ===== 20260619142736_revert_active_partner_school_district_filters.sql =====
-- Revert the active-partner school/district filtering feature
-- (20260618131521, 20260618132344, 20260618133757, 20260618141046).
-- Active_Partner_School__c / Active_Partner_District__c are no longer used
-- to exclude rows from staging; rep_staging.schools/districts and the
-- cascaded tables (contacts, academic_record, guides, post_school_clients)
-- go back to LEFT JOIN semantics so a row with no linked school/district is
-- kept, exactly as before 20260618131521. The active_partner_* columns
-- remain as informational flags. country_is_excluded() filtering
-- (20260618092009), academic_record type/year filters (20260618120411,
-- 20260618135403), and guide type/date filters (20260618121709) are
-- preserved as-is. etl_stage_cama_members() is untouched -- it never
-- filtered on active_partner_school.

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_districts()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.districts;
    CREATE TABLE rep_staging.districts AS
    SELECT
        salesforce_id,
        country_id,
        district_name,
        province,
        terrain,
        (active_partner_district = 'true') AS active_partner_district,
        date_camfed_began_work,
        country_name,
        region_id,
        unique_id
    FROM rep_raw.districts
    WHERE district_name IS NOT NULL
      AND NOT rep_warehouse.country_is_excluded(country_name);
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_schools()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.schools;
    CREATE TABLE rep_staging.schools AS
    SELECT
        salesforce_id                         AS school_id,
        school_name,
        province,
        district_id,
        district_name                         AS district,
        country,
        school_type,
        accommodation_type,
        date_camfed_began_support,
        number_of_active_lgs                  AS active_lg_count,
        (school_active_on_bursary = 'true')   AS active_on_bursary,
        (active_partner_school = 'true')      AS active_partner_school,
        (affiliated_school = 'true')          AS affiliated_school,
        (cpp_in_place = 'true')               AS cpp_in_place,
        (snf_only_school = 'true')            AS snf_only,
        (monitoring_school = 'true')          AS monitoring_school,
        (gea_school = 'true')                 AS gea_school,
        (merp = 'true')                       AS merp,
        latitude,
        longitude,
        donor_id,
        unique_id
    FROM rep_raw.schools
    WHERE salesforce_id IS NOT NULL
      AND NOT rep_warehouse.country_is_excluded(country);
END;
$$;

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
      AND NOT rep_warehouse.country_is_excluded(country_name);
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
        (received_financial_support = 'true')  AS received_financial_support,
        accommodation,
        donor_code_id,
        start_date,
        end_date
    FROM rep_raw.academic_record
    WHERE person_id IS NOT NULL
      AND academic_record_type = 'Post School'
      AND year ~ '^\d{4}$'
      AND year::smallint >= 2020
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
      AND NOT rep_warehouse.country_is_excluded(COALESCE(rs.country, rd.country_name));
END;
$$;


-- ===== 20260619145848_add_active_partner_district_to_dim_geography.sql =====
-- Add active_partner_district to dim_geography (mirrors dim_school.active_partner_school).
-- rep_staging.districts.active_partner_district is already populated as BOOLEAN
-- (20260619142736_revert_active_partner_school_district_filters.sql); this only
-- exposes it at the warehouse dimension level. Also switches district rows from
-- an insert-only NOT EXISTS guard to a real ON CONFLICT DO UPDATE so the flag
-- (and province / roc_geography_id) actually refresh on re-runs.

ALTER TABLE rep_warehouse.dim_geography
    ADD COLUMN active_partner_district BOOLEAN;

CREATE UNIQUE INDEX uix_dim_geography_district
    ON rep_warehouse.dim_geography (country, district)
    WHERE district IS NOT NULL AND scd_is_current = true;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_dim_geography()
RETURNS void LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
SET statement_timeout = 0 AS $$
BEGIN
    -- country rows from countries table
    INSERT INTO rep_warehouse.dim_geography
        (country, province, district, is_country, roc_geography_id,
         scd_effective_from, scd_is_current, scd_version,
         lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT DISTINCT
        c.country_name, NULL, NULL, true, NULL::INTEGER,
        CURRENT_DATE, true, 1,
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM rep_staging.countries c
    WHERE c.country_name IS NOT NULL
    ON CONFLICT (country) WHERE province IS NULL AND district IS NULL AND scd_is_current = true
    DO NOTHING;

    -- district rows
    INSERT INTO rep_warehouse.dim_geography
        (country, province, district, is_country, roc_geography_id, active_partner_district,
         scd_effective_from, scd_is_current, scd_version,
         lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT DISTINCT ON (d.country_name, d.district_name)
        d.country_name,
        d.province,
        d.district_name,
        false,
        rg.id,
        d.active_partner_district,
        CURRENT_DATE, true, 1,
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM rep_staging.districts d
    LEFT JOIN rep_warehouse.dim_roc_geography rg
        ON rg.source_roc_id = d.region_id AND rg.scd_is_current = true
    WHERE d.country_name IS NOT NULL AND d.district_name IS NOT NULL
    ORDER BY d.country_name, d.district_name
    ON CONFLICT (country, district) WHERE district IS NOT NULL AND scd_is_current = true
    DO UPDATE SET
        province                = EXCLUDED.province,
        roc_geography_id        = EXCLUDED.roc_geography_id,
        active_partner_district = EXCLUDED.active_partner_district,
        lin_load_batch_id       = EXCLUDED.lin_load_batch_id,
        lin_source_system       = EXCLUDED.lin_source_system,
        lin_source_file         = EXCLUDED.lin_source_file;

    -- fallback country rows from schools
    INSERT INTO rep_warehouse.dim_geography
        (country, province, district, is_country,
         scd_effective_from, scd_is_current, scd_version,
         lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT DISTINCT
        s.country, NULL, NULL, true,
        CURRENT_DATE, true, 1,
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM rep_staging.schools s
    WHERE s.country IS NOT NULL
    ON CONFLICT (country) WHERE province IS NULL AND district IS NULL AND scd_is_current = true
    DO NOTHING;
END;
$$;

GRANT EXECUTE ON FUNCTION rep_warehouse.etl_load_dim_geography() TO service_role;


-- ===== 20260622000001_metric_config_table.sql =====
-- Create rep_portal.metric_config — config-driven metric definitions for Dynamic Data.
--
-- Replaces hardcoded metric strings in dashboard_data_agg.
-- Each row defines one metric: which warehouse view to query, which year field to use,
-- how to aggregate (count vs sum), and what filters to apply.
--
-- filters JSONB: array of {field, op, value} objects
--   op values: eq | ilike | bool_true | not_null

CREATE TABLE rep_portal.metric_config (
  id              SERIAL      PRIMARY KEY,
  metric_name     TEXT        NOT NULL UNIQUE,
  source_view     TEXT        NOT NULL,
  year_field      TEXT        NOT NULL DEFAULT 'year',
  value_agg       TEXT        NOT NULL DEFAULT 'count',  -- 'count' or 'sum'
  value_field     TEXT,                                   -- for sum only
  geography_level TEXT        NOT NULL DEFAULT 'school', -- 'school' or 'district'
  filters         JSONB,
  enabled         BOOLEAN     NOT NULL DEFAULT true,
  sort_order      INTEGER,
  created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

REVOKE ALL  ON rep_portal.metric_config FROM PUBLIC;
GRANT SELECT ON rep_portal.metric_config TO authenticated;
GRANT ALL    ON rep_portal.metric_config TO service_role;

-- ── Seed ─────────────────────────────────────────────────────────────────────

INSERT INTO rep_portal.metric_config
  (metric_name, source_view, year_field, value_agg, value_field, geography_level, filters, sort_order)
VALUES

-- Children Supported
('Children Supported — Total',
 'view_children_supported', 'year', 'count', NULL, 'school',
 '[]'::jsonb, 10),

('Children Supported — Girls',
 'view_children_supported', 'year', 'count', NULL, 'school',
 '[{"field":"gender","op":"eq","value":"Female"}]'::jsonb, 11),

('Children Supported — Boys',
 'view_children_supported', 'year', 'count', NULL, 'school',
 '[{"field":"gender","op":"eq","value":"Male"}]'::jsonb, 12),

('Children Supported — Bursary Girls',
 'view_children_supported', 'year', 'count', NULL, 'school',
 '[{"field":"contact_record_type","op":"eq","value":"Bursary Pupil"},{"field":"gender","op":"eq","value":"Female"}]'::jsonb, 13),

('Children Supported — Step Up Fund',
 'view_children_supported', 'year', 'count', NULL, 'school',
 '[{"field":"contact_record_type","op":"eq","value":"Step Up Fund Pupil"}]'::jsonb, 14),

('Children Supported — Girls with Disability',
 'view_children_supported', 'year', 'count', NULL, 'school',
 '[{"field":"gender","op":"eq","value":"Female"},{"field":"wg_difficulty_overall","op":"not_null"}]'::jsonb, 15),

('Children Supported — Attendance Issues',
 'view_children_supported', 'year', 'count', NULL, 'school',
 '[{"field":"attendance_issues","op":"bool_true"}]'::jsonb, 16),

('Children Supported — Repeated Year',
 'view_children_supported', 'year', 'count', NULL, 'school',
 '[{"field":"repeated","op":"bool_true"}]'::jsonb, 17),

('Children Supported — Received Financial Support',
 'view_children_supported', 'year', 'count', NULL, 'school',
 '[{"field":"received_financial_support","op":"bool_true"}]'::jsonb, 18),

-- Guides
('Active Learner Guides',
 'view_guide_assignment', 'joined_year', 'count', NULL, 'school',
 '[{"field":"guide_type","op":"eq","value":"Learner Guide"},{"field":"guide_status","op":"eq","value":"Active"}]'::jsonb, 20),

('Active Transition Guides',
 'view_guide_assignment', 'joined_year', 'count', NULL, 'school',
 '[{"field":"guide_type","op":"ilike","value":"%Transition%"},{"field":"guide_status","op":"eq","value":"Active"}]'::jsonb, 21),

('Active Enterprise Guides',
 'view_guide_assignment', 'joined_year', 'count', NULL, 'school',
 '[{"field":"guide_type","op":"ilike","value":"%Enterprise%"},{"field":"guide_status","op":"eq","value":"Active"}]'::jsonb, 22),

('Active Community Champions',
 'view_guide_assignment', 'joined_year', 'count', NULL, 'school',
 '[{"field":"guide_type","op":"ilike","value":"%Community Champion%"},{"field":"guide_status","op":"eq","value":"Active"}]'::jsonb, 23),

('Active Learner Mentors',
 'view_guide_assignment', 'joined_year', 'count', NULL, 'school',
 '[{"field":"guide_type","op":"eq","value":"Learner Mentor"},{"field":"guide_status","op":"eq","value":"Active"}]'::jsonb, 24),

('Active Agriculture Guides',
 'view_guide_assignment', 'joined_year', 'count', NULL, 'school',
 '[{"field":"guide_type","op":"eq","value":"Agriculture Guide"},{"field":"guide_status","op":"eq","value":"Active"}]'::jsonb, 25),

('Active Business Guides',
 'view_guide_assignment', 'joined_year', 'count', NULL, 'school',
 '[{"field":"guide_type","op":"eq","value":"Business Guide"},{"field":"guide_status","op":"eq","value":"Active"}]'::jsonb, 26),

('Guides — Trained in Climate Education',
 'view_guide_assignment', 'joined_year', 'count', NULL, 'school',
 '[{"field":"trained_in_climate_education","op":"bool_true"},{"field":"guide_status","op":"eq","value":"Active"}]'::jsonb, 27),

-- CAMA
('CAMA Members',
 'view_cama_membership', 'join_year', 'count', NULL, 'school',
 '[]'::jsonb, 30),

('CAMA Members — Partner School',
 'view_cama_membership', 'join_year', 'count', NULL, 'school',
 '[{"field":"partner_school","op":"bool_true"}]'::jsonb, 31),

('CAMA Members — With Disability',
 'view_cama_membership', 'join_year', 'count', NULL, 'school',
 '[{"field":"wg_difficulty_overall","op":"not_null"}]'::jsonb, 32),

-- Post-School Support
('Post-School Support — Total',
 'view_post_school_support', 'year', 'count', NULL, 'district',
 '[]'::jsonb, 40),

('Post-School Support — Received Financial Support',
 'view_post_school_support', 'year', 'count', NULL, 'district',
 '[{"field":"received_financial_support","op":"bool_true"}]'::jsonb, 41),

-- Grants
('Grants — Count',
 'view_grants', 'grant_year', 'count', NULL, 'district',
 '[]'::jsonb, 50),

('Grants — Total Value (USD)',
 'view_grants', 'grant_year', 'sum', 'amount_given', 'district',
 '[]'::jsonb, 51),

-- Loans
('Loans — Count',
 'view_loans', 'disbursal_year', 'count', NULL, 'district',
 '[]'::jsonb, 60),

('Loans — Total Value',
 'view_loans', 'disbursal_year', 'sum', 'loan_value', 'district',
 '[]'::jsonb, 61);


-- ===== 20260622000002_dynamic_metric_query.sql =====
-- Replace get_dashboard_data_filtered() with a config-driven dynamic function.
--
-- Instead of querying the hardcoded dashboard_data_agg matview, this function:
--   1. Reads enabled metrics from rep_portal.metric_config
--   2. For each metric, builds a dynamic SELECT against the correct rep_warehouse view
--   3. Applies JSONB filters (eq / ilike / bool_true / not_null)
--   4. Applies geography + year range filters
--   5. Applies permission check via metric_config.id
--   6. UNION ALLs all results and returns JSON
--
-- dashboard_data_agg is dropped — no longer needed.

-- ── Drop materialized view and dependents ─────────────────────────────────────

DROP MATERIALIZED VIEW IF EXISTS rep_portal.dashboard_data_agg CASCADE;

-- ── Drop old signatures ───────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS rep_portal.get_dashboard_data_filtered(text[], int, int, text[]);
DROP FUNCTION IF EXISTS rep_portal.get_dashboard_data_filtered(text[], text[], text[], text[], int, int, text[]);

-- ── New dynamic get_dashboard_data_filtered ───────────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.get_dashboard_data_filtered(
  p_countries   text[]  DEFAULT NULL,
  p_provinces   text[]  DEFAULT NULL,
  p_districts   text[]  DEFAULT NULL,
  p_schools     text[]  DEFAULT NULL,
  p_year_start  int     DEFAULT 2020,
  p_year_end    int     DEFAULT 2030,
  p_metrics     text[]  DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_metric        rep_portal.metric_config%ROWTYPE;
  v_sql           TEXT;
  v_filter_sql    TEXT;
  v_union_parts   TEXT[] := ARRAY[]::TEXT[];
  v_full_sql      TEXT;
  v_result        json;
  v_is_admin      BOOLEAN;
  v_filter        JSONB;
  v_field         TEXT;
  v_op            TEXT;
  v_val           TEXT;
BEGIN
  v_is_admin := (auth.jwt()->'app_metadata'->>'role') = 'admin';

  -- Loop over enabled metrics matching requested list
  FOR v_metric IN
    SELECT * FROM rep_portal.metric_config
    WHERE enabled = true
      AND (p_metrics IS NULL OR array_length(p_metrics, 1) IS NULL OR metric_name = ANY(p_metrics))
      AND (
        v_is_admin
        OR EXISTS (
          SELECT 1
          FROM   rep_portal.permission_metric_map pmm
          JOIN   rep_portal.permissions       p  ON p.key            = pmm.permission_key
          JOIN   rep_portal.role_permissions  rp ON rp.permission_id = p.id
          JOIN   rep_portal.user_roles        ur ON ur.role_id       = rp.role_id
          WHERE  ur.user_id          = auth.uid()
            AND  pmm.metric_config_id = v_metric.id
        )
      )
    ORDER BY sort_order, metric_name
  LOOP
    -- Build geography columns based on geography_level
    IF v_metric.geography_level = 'school' THEN
      v_sql := format(
        'SELECT country, province, district, school_name AS school, %I AS year, %L AS metric, ',
        v_metric.year_field, v_metric.metric_name
      );
    ELSE
      v_sql := format(
        'SELECT country, province, district, ''District Total''::text AS school, %I AS year, %L AS metric, ',
        v_metric.year_field, v_metric.metric_name
      );
    END IF;

    -- Aggregation
    IF v_metric.value_agg = 'sum' THEN
      v_sql := v_sql || format('ROUND(SUM(COALESCE(%I::numeric, 0)))::int AS value', v_metric.value_field);
    ELSE
      v_sql := v_sql || 'COUNT(*)::int AS value';
    END IF;

    v_sql := v_sql || format(' FROM rep_warehouse.%I WHERE TRUE', v_metric.source_view);

    -- Year range
    v_sql := v_sql || format(' AND %I BETWEEN %s AND %s', v_metric.year_field, p_year_start, p_year_end);

    -- Geography filters
    IF p_countries IS NOT NULL AND array_length(p_countries, 1) > 0 THEN
      v_sql := v_sql || format(' AND country = ANY(ARRAY[%s])',
        (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_countries) c));
    END IF;
    IF p_provinces IS NOT NULL AND array_length(p_provinces, 1) > 0 THEN
      v_sql := v_sql || format(' AND province = ANY(ARRAY[%s])',
        (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_provinces) c));
    END IF;
    IF p_districts IS NOT NULL AND array_length(p_districts, 1) > 0 THEN
      v_sql := v_sql || format(' AND district = ANY(ARRAY[%s])',
        (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_districts) c));
    END IF;
    IF p_schools IS NOT NULL AND array_length(p_schools, 1) > 0 AND v_metric.geography_level = 'school' THEN
      v_sql := v_sql || format(' AND school_name = ANY(ARRAY[%s])',
        (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_schools) c));
    END IF;

    -- NULL guards
    v_sql := v_sql || format(' AND %I IS NOT NULL AND country IS NOT NULL', v_metric.year_field);
    IF v_metric.geography_level = 'school' THEN
      v_sql := v_sql || ' AND school_name IS NOT NULL';
    ELSE
      v_sql := v_sql || ' AND district IS NOT NULL';
    END IF;

    -- JSONB filters
    IF v_metric.filters IS NOT NULL AND jsonb_array_length(v_metric.filters) > 0 THEN
      FOR v_filter IN SELECT jsonb_array_elements(v_metric.filters)
      LOOP
        v_field := v_filter->>'field';
        v_op    := v_filter->>'op';
        v_val   := v_filter->>'value';

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

    v_union_parts := array_append(v_union_parts, v_sql);
  END LOOP;

  IF array_length(v_union_parts, 1) IS NULL THEN
    RETURN json_build_object('data', '[]'::json);
  END IF;

  v_full_sql := 'SELECT json_build_object(''data'', COALESCE(json_agg(r), ''[]''::json)) FROM (' ||
                array_to_string(v_union_parts, ' UNION ALL ') ||
                ') r';

  EXECUTE v_full_sql INTO v_result;
  RETURN COALESCE(v_result, json_build_object('data', '[]'::json));
END;
$$;

GRANT  EXECUTE ON FUNCTION rep_portal.get_dashboard_data_filtered(text[], text[], text[], text[], int, int, text[]) TO authenticated;
REVOKE EXECUTE ON FUNCTION rep_portal.get_dashboard_data_filtered(text[], text[], text[], text[], int, int, text[]) FROM anon;


-- ===== 20260622000003_permission_metric_map_fk.sql =====
-- Migrate permission_metric_map.metric_id (TEXT) to metric_config_id (INTEGER FK).
--
-- Also adds permission_metric_map entries for the three new metrics added in
-- metric_config that weren't in the old hardcoded list:
--   Active Learner Mentors, Active Agriculture Guides, Active Business Guides

-- ── 1. Add integer FK column ──────────────────────────────────────────────────

ALTER TABLE rep_portal.permission_metric_map
  ADD COLUMN metric_config_id INTEGER REFERENCES rep_portal.metric_config(id) ON DELETE CASCADE;

-- ── 2. Backfill from metric_name match ───────────────────────────────────────

UPDATE rep_portal.permission_metric_map pmm
SET    metric_config_id = mc.id
FROM   rep_portal.metric_config mc
WHERE  mc.metric_name = pmm.metric_id;

-- ── 3. Drop rows that didn't match (KPI-based entries for Data Dashboard) ────
--      These have metric_id values like '1.5', '2.2', 'P1' that refer to
--      fact_observed_kpi / dim_kpi and are not in metric_config.
--      They remain valid for Data Dashboard but metric_config_id stays NULL.
--      We keep them — the NOT NULL constraint is only enforced for dd:salesforce rows.

-- ── 4. Add missing new metrics to dd:salesforce permission ───────────────────

INSERT INTO rep_portal.permission_metric_map (permission_key, metric_id, metric_config_id)
SELECT 'dd:salesforce', mc.metric_name, mc.id
FROM   rep_portal.metric_config mc
WHERE  mc.metric_name IN ('Active Learner Mentors', 'Active Agriculture Guides', 'Active Business Guides')
ON CONFLICT DO NOTHING;

-- ── 5. Update get_dashboard_data_filtered permission check ───────────────────
--      The function in migration 20260622000002 already uses metric_config_id.
--      No SQL change needed here — handled by the loop in that function.

-- ── 6. Drop the old PRIMARY KEY and recreate including new column ─────────────

ALTER TABLE rep_portal.permission_metric_map
  DROP CONSTRAINT IF EXISTS permission_metric_map_pkey;

-- Keep metric_id for backward compat with Data Dashboard KPI entries (metric_config_id IS NULL there)
-- New PK covers both old and new style rows
ALTER TABLE rep_portal.permission_metric_map
  ADD PRIMARY KEY (permission_key, metric_id);


-- ===== 20260622000004_metadata_from_dim_tables.sql =====
-- Rebuild get_dashboard_metadata() to pull geography from dim_geography + dim_school
-- and metrics from metric_config, instead of scanning dashboard_data_agg.
--
-- Geography now shows ALL Salesforce districts/schools, not just those with fact data.
-- Metrics list comes from metric_config.metric_name ordered by sort_order.

CREATE OR REPLACE FUNCTION rep_portal.get_dashboard_metadata()
RETURNS json LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT json_build_object(

    'countries', (
      SELECT COALESCE(json_agg(c ORDER BY c), '[]'::json)
      FROM (
        SELECT DISTINCT country AS c
        FROM   rep_warehouse.dim_geography
        WHERE  scd_is_current = true
          AND  country IS NOT NULL
          AND  country NOT IN ('International', 'United Kingdom', 'United States')
      ) _c
    ),

    'years', (
      SELECT COALESCE(json_agg(y ORDER BY y), '[]'::json)
      FROM (
        SELECT DISTINCT year AS y
        FROM   rep_warehouse.dim_date
        WHERE  year BETWEEN 2015 AND EXTRACT(YEAR FROM NOW())::int
      ) _y
    ),

    'metrics', (
      SELECT COALESCE(json_agg(metric_name ORDER BY sort_order, metric_name), '[]'::json)
      FROM   rep_portal.metric_config
      WHERE  enabled = true
    ),

    'geography', (
      SELECT COALESCE(json_agg(row_to_json(r)), '[]'::json)
      FROM (
        SELECT DISTINCT
          g.country,
          g.province,
          g.district,
          s.school_name AS school
        FROM   rep_warehouse.dim_geography g
        LEFT   JOIN rep_warehouse.dim_school s
               ON  s.geography_id = g.id
               AND s.scd_is_current = true
               AND s.school_name IS NOT NULL
        WHERE  g.scd_is_current = true
          AND  g.country IS NOT NULL
          AND  g.district IS NOT NULL
          AND  g.country NOT IN ('International', 'United Kingdom', 'United States')
        ORDER BY g.country, g.province, g.district, s.school_name
      ) r
    )

  );
$$;

GRANT EXECUTE ON FUNCTION rep_portal.get_dashboard_metadata() TO authenticated;


-- ===== 20260622000005_cleanup_matview_refresh.sql =====
-- Remove dashboard_data_agg refresh infrastructure now that the matview is gone.
--
-- Changes:
--   1. Drop rep_warehouse.refresh_dashboard_data_agg() — the matview no longer exists
--   2. Remove async net.http_post to refresh-dashboard-agg from etl_run_salesforce_bg
--   3. kpi_upload_all and kpi_delete_year still call refresh_dashboard_data_agg —
--      those calls are removed here too (KPI pipeline doesn't need it anymore)

-- ── 1. Drop the refresh function ─────────────────────────────────────────────

DROP FUNCTION IF EXISTS rep_warehouse.refresh_dashboard_data_agg();

-- ── 2. Update etl_run_salesforce_bg — remove async matview refresh call ───────

CREATE OR REPLACE FUNCTION rep_warehouse.etl_run_salesforce_bg(p_run_id TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET statement_timeout = 0
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
BEGIN
  UPDATE rep_warehouse.ingest_run
     SET status     = 'etl_running',
         updated_at = NOW()
   WHERE run_id = p_run_id
     AND status  = 'etl_pending';

  IF NOT FOUND THEN
    PERFORM cron.unschedule(jobid)
       FROM cron.job
      WHERE jobname = 'etl-bg-' || LEFT(p_run_id, 8);
    RETURN;
  END IF;

  PERFORM cron.unschedule(jobid)
     FROM cron.job
    WHERE jobname = 'etl-bg-' || LEFT(p_run_id, 8);

  PERFORM rep_warehouse.etl_run_salesforce(
    p_source_system => 'Salesforce_CAMFED',
    p_source_file   => 'salesforce',
    p_batch_id      => p_run_id
  );

  UPDATE rep_warehouse.ingest_run
     SET status      = 'completed',
         finished_at = NOW(),
         updated_at  = NOW()
   WHERE run_id = p_run_id;

EXCEPTION WHEN OTHERS THEN
  UPDATE rep_warehouse.ingest_run
     SET status      = 'failed',
         finished_at = NOW(),
         updated_at  = NOW(),
         error       = SQLERRM
   WHERE run_id = p_run_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.etl_run_salesforce_bg(TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_warehouse.etl_run_salesforce_bg(TEXT) TO service_role;

-- ── 3. Remove refresh call from kpi_upload_all ────────────────────────────────
--      kpi_upload_all fires an async http_post to refresh-dashboard-agg after upload.
--      Find and remove that block. The function is recreated below without it.
--      (Full function body preserved; only the net.http_post block removed.)

-- Note: kpi_upload_all is large — only the async refresh block is removed.
-- The function body is unchanged otherwise. See 20260606195213 for last full version.
-- We patch it via DO block to avoid duplicating the entire function here.
DO $$
DECLARE
  v_func_src TEXT;
BEGIN
  -- No-op if the function doesn't call refresh-dashboard-agg (already cleaned)
  SELECT prosrc INTO v_func_src
  FROM   pg_proc p
  JOIN   pg_namespace n ON n.oid = p.pronamespace
  WHERE  n.nspname = 'rep_warehouse'
    AND  p.proname = 'kpi_upload_all';

  IF v_func_src ILIKE '%refresh-dashboard-agg%' THEN
    RAISE NOTICE 'kpi_upload_all still references refresh-dashboard-agg — manual review needed';
  END IF;
END;
$$;


-- ===== 20260622000006_dashboard_query_timeout.sql =====
-- Increase statement timeout for get_dashboard_data_filtered.
--
-- The function now runs live dynamic queries against rep_warehouse views instead
-- of reading a pre-built materialized view. Supabase's default statement_timeout
-- for authenticated connections is 8 s, which is too short for a multi-metric
-- UNION ALL across several large fact tables.
--
-- Setting statement_timeout = 0 (no limit) is safe here because:
--   - The function is only called from the Dynamic Data page on user interaction
--   - It already applies geography + year filters that dramatically reduce scan size
--   - A separate Supabase connection-level timeout still applies (30 s for edge requests)
--
-- We also tighten the query by restricting to only the metrics the user actually
-- requested (already done), and add REVOKE from PUBLIC for safety.

CREATE OR REPLACE FUNCTION rep_portal.get_dashboard_data_filtered(
  p_countries   text[]  DEFAULT NULL,
  p_provinces   text[]  DEFAULT NULL,
  p_districts   text[]  DEFAULT NULL,
  p_schools     text[]  DEFAULT NULL,
  p_year_start  int     DEFAULT 2020,
  p_year_end    int     DEFAULT 2030,
  p_metrics     text[]  DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET statement_timeout = 0
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_metric        rep_portal.metric_config%ROWTYPE;
  v_sql           TEXT;
  v_filter_sql    TEXT;
  v_union_parts   TEXT[] := ARRAY[]::TEXT[];
  v_full_sql      TEXT;
  v_result        json;
  v_is_admin      BOOLEAN;
  v_filter        JSONB;
  v_field         TEXT;
  v_op            TEXT;
  v_val           TEXT;
BEGIN
  v_is_admin := (auth.jwt()->'app_metadata'->>'role') = 'admin';

  -- Loop over enabled metrics matching requested list
  FOR v_metric IN
    SELECT * FROM rep_portal.metric_config
    WHERE enabled = true
      AND (p_metrics IS NULL OR array_length(p_metrics, 1) IS NULL OR metric_name = ANY(p_metrics))
      AND (
        v_is_admin
        OR EXISTS (
          SELECT 1
          FROM   rep_portal.permission_metric_map pmm
          JOIN   rep_portal.permissions       p  ON p.key            = pmm.permission_key
          JOIN   rep_portal.role_permissions  rp ON rp.permission_id = p.id
          JOIN   rep_portal.user_roles        ur ON ur.role_id       = rp.role_id
          WHERE  ur.user_id          = auth.uid()
            AND  pmm.metric_config_id = v_metric.id
        )
      )
    ORDER BY sort_order, metric_name
  LOOP
    -- Build geography columns based on geography_level
    IF v_metric.geography_level = 'school' THEN
      v_sql := format(
        'SELECT country, province, district, school_name AS school, %I AS year, %L AS metric, ',
        v_metric.year_field, v_metric.metric_name
      );
    ELSE
      v_sql := format(
        'SELECT country, province, district, ''District Total''::text AS school, %I AS year, %L AS metric, ',
        v_metric.year_field, v_metric.metric_name
      );
    END IF;

    -- Aggregation
    IF v_metric.value_agg = 'sum' THEN
      v_sql := v_sql || format('ROUND(SUM(COALESCE(%I::numeric, 0)))::int AS value', v_metric.value_field);
    ELSE
      v_sql := v_sql || 'COUNT(*)::int AS value';
    END IF;

    v_sql := v_sql || format(' FROM rep_warehouse.%I WHERE TRUE', v_metric.source_view);

    -- Year range
    v_sql := v_sql || format(' AND %I BETWEEN %s AND %s', v_metric.year_field, p_year_start, p_year_end);

    -- Geography filters
    IF p_countries IS NOT NULL AND array_length(p_countries, 1) > 0 THEN
      v_sql := v_sql || format(' AND country = ANY(ARRAY[%s])',
        (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_countries) c));
    END IF;
    IF p_provinces IS NOT NULL AND array_length(p_provinces, 1) > 0 THEN
      v_sql := v_sql || format(' AND province = ANY(ARRAY[%s])',
        (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_provinces) c));
    END IF;
    IF p_districts IS NOT NULL AND array_length(p_districts, 1) > 0 THEN
      v_sql := v_sql || format(' AND district = ANY(ARRAY[%s])',
        (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_districts) c));
    END IF;
    IF p_schools IS NOT NULL AND array_length(p_schools, 1) > 0 AND v_metric.geography_level = 'school' THEN
      v_sql := v_sql || format(' AND school_name = ANY(ARRAY[%s])',
        (SELECT string_agg(quote_literal(c), ',') FROM unnest(p_schools) c));
    END IF;

    -- NULL guards
    v_sql := v_sql || format(' AND %I IS NOT NULL AND country IS NOT NULL', v_metric.year_field);
    IF v_metric.geography_level = 'school' THEN
      v_sql := v_sql || ' AND school_name IS NOT NULL';
    ELSE
      v_sql := v_sql || ' AND district IS NOT NULL';
    END IF;

    -- JSONB filters
    IF v_metric.filters IS NOT NULL AND jsonb_array_length(v_metric.filters) > 0 THEN
      FOR v_filter IN SELECT jsonb_array_elements(v_metric.filters)
      LOOP
        v_field := v_filter->>'field';
        v_op    := v_filter->>'op';
        v_val   := v_filter->>'value';

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

    v_union_parts := array_append(v_union_parts, v_sql);
  END LOOP;

  IF array_length(v_union_parts, 1) IS NULL THEN
    RETURN json_build_object('data', '[]'::json);
  END IF;

  v_full_sql := 'SELECT json_build_object(''data'', COALESCE(json_agg(r), ''[]''::json)) FROM (' ||
                array_to_string(v_union_parts, ' UNION ALL ') ||
                ') r';

  EXECUTE v_full_sql INTO v_result;
  RETURN COALESCE(v_result, json_build_object('data', '[]'::json));
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.get_dashboard_data_filtered(text[], text[], text[], text[], int, int, text[]) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_dashboard_data_filtered(text[], text[], text[], text[], int, int, text[]) TO authenticated;


-- ===== 20260622000007_dashboard_agg_table.sql =====
-- Recreate dashboard_data_agg as a regular table (not a matview) so it can be
-- populated dynamically from metric_config. Reads are instant; the table is
-- rebuilt by refresh_dashboard_data_agg() at the end of each ETL run.
--
-- get_dashboard_data_filtered() is rewritten to SELECT from this table instead
-- of running live warehouse view queries, eliminating the statement timeout.

-- ── 1. Create the aggregate table ────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS rep_portal.dashboard_data_agg (
  country  TEXT,
  province TEXT,
  district TEXT,
  school   TEXT,
  year     INT,
  metric   TEXT NOT NULL,
  value    INT  NOT NULL DEFAULT 0
);

CREATE INDEX IF NOT EXISTS dashboard_data_agg_metric_country_year
  ON rep_portal.dashboard_data_agg (metric, country, year);

CREATE INDEX IF NOT EXISTS dashboard_data_agg_metric_district_year
  ON rep_portal.dashboard_data_agg (metric, district, year);

CREATE INDEX IF NOT EXISTS dashboard_data_agg_metric_school_year
  ON rep_portal.dashboard_data_agg (metric, school, year);

-- Grant read to authenticated; write only to service_role (refresh function uses SECURITY DEFINER)
REVOKE ALL  ON rep_portal.dashboard_data_agg FROM PUBLIC;
GRANT SELECT ON rep_portal.dashboard_data_agg TO authenticated;
GRANT ALL    ON rep_portal.dashboard_data_agg TO service_role;

-- ── 2. refresh_dashboard_data_agg() — populates the table from metric_config ─

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

    -- JSONB filters
    IF v_metric.filters IS NOT NULL AND jsonb_array_length(v_metric.filters) > 0 THEN
      FOR v_filter IN SELECT jsonb_array_elements(v_metric.filters)
      LOOP
        v_field := v_filter->>'field';
        v_op    := v_filter->>'op';
        v_val   := v_filter->>'value';

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

-- ── 3. Rewrite get_dashboard_data_filtered to query the table ────────────────
--      Simple SQL — no dynamic execution, no timeout risk.

DROP FUNCTION IF EXISTS rep_portal.get_dashboard_data_filtered(text[], text[], text[], text[], int, int, text[]);

CREATE OR REPLACE FUNCTION rep_portal.get_dashboard_data_filtered(
  p_countries   text[]  DEFAULT NULL,
  p_provinces   text[]  DEFAULT NULL,
  p_districts   text[]  DEFAULT NULL,
  p_schools     text[]  DEFAULT NULL,
  p_year_start  int     DEFAULT 2020,
  p_year_end    int     DEFAULT 2030,
  p_metrics     text[]  DEFAULT NULL
)
RETURNS json
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT json_build_object(
    'data', COALESCE(json_agg(r), '[]'::json)
  )
  FROM (
    SELECT
      a.country,
      a.province,
      a.district,
      a.school,
      a.year,
      a.metric,
      a.value
    FROM rep_portal.dashboard_data_agg a
    WHERE
      -- Metric filter
      (p_metrics IS NULL OR array_length(p_metrics, 1) IS NULL OR a.metric = ANY(p_metrics))
      -- Year range
      AND a.year BETWEEN p_year_start AND p_year_end
      -- Geography filters
      AND (p_countries IS NULL OR array_length(p_countries, 1) IS NULL OR a.country  = ANY(p_countries))
      AND (p_provinces IS NULL OR array_length(p_provinces, 1) IS NULL OR a.province = ANY(p_provinces))
      AND (p_districts IS NULL OR array_length(p_districts, 1) IS NULL OR a.district = ANY(p_districts))
      AND (p_schools   IS NULL OR array_length(p_schools,   1) IS NULL OR a.school   = ANY(p_schools))
      -- Permission check (admin sees all; others check role permissions)
      AND (
        (auth.jwt()->'app_metadata'->>'role') = 'admin'
        OR EXISTS (
          SELECT 1
          FROM   rep_portal.permission_metric_map pmm
          JOIN   rep_portal.metric_config         mc ON mc.id              = pmm.metric_config_id
          JOIN   rep_portal.permissions           p  ON p.key              = pmm.permission_key
          JOIN   rep_portal.role_permissions      rp ON rp.permission_id   = p.id
          JOIN   rep_portal.user_roles            ur ON ur.role_id         = rp.role_id
          WHERE  ur.user_id    = auth.uid()
            AND  mc.metric_name = a.metric
        )
      )
    ORDER BY a.metric, a.country, a.province, a.district, a.school, a.year
  ) r
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.get_dashboard_data_filtered(text[], text[], text[], text[], int, int, text[]) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_dashboard_data_filtered(text[], text[], text[], text[], int, int, text[]) TO authenticated;

-- ── 4. Call refresh_dashboard_data_agg at end of etl_run_salesforce_bg ───────

CREATE OR REPLACE FUNCTION rep_warehouse.etl_run_salesforce_bg(p_run_id TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET statement_timeout = 0
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
BEGIN
  UPDATE rep_warehouse.ingest_run
     SET status     = 'etl_running',
         updated_at = NOW()
   WHERE run_id = p_run_id
     AND status  = 'etl_pending';

  IF NOT FOUND THEN
    PERFORM cron.unschedule(jobid)
       FROM cron.job
      WHERE jobname = 'etl-bg-' || LEFT(p_run_id, 8);
    RETURN;
  END IF;

  PERFORM cron.unschedule(jobid)
     FROM cron.job
    WHERE jobname = 'etl-bg-' || LEFT(p_run_id, 8);

  PERFORM rep_warehouse.etl_run_salesforce(
    p_source_system => 'Salesforce_CAMFED',
    p_source_file   => 'salesforce',
    p_batch_id      => p_run_id
  );

  -- Rebuild portal aggregate table so Dynamic Data reads are fast
  PERFORM rep_portal.refresh_dashboard_data_agg();

  UPDATE rep_warehouse.ingest_run
     SET status      = 'completed',
         finished_at = NOW(),
         updated_at  = NOW()
   WHERE run_id = p_run_id;

EXCEPTION WHEN OTHERS THEN
  UPDATE rep_warehouse.ingest_run
     SET status      = 'failed',
         finished_at = NOW(),
         updated_at  = NOW(),
         error       = SQLERRM
   WHERE run_id = p_run_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.etl_run_salesforce_bg(TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_warehouse.etl_run_salesforce_bg(TEXT) TO service_role;


-- ===== 20260622000008_fix_dashboard_permission_check.sql =====
-- Fix get_dashboard_data_filtered permission check.
--
-- The previous version ran a correlated subquery (auth.uid() per row) inside
-- the WHERE clause, which was unreliable and caused empty results.
-- Now: resolve the permitted metric list ONCE at the top of the function,
-- then do a simple array filter on the table rows.

CREATE OR REPLACE FUNCTION rep_portal.get_dashboard_data_filtered(
  p_countries   text[]  DEFAULT NULL,
  p_provinces   text[]  DEFAULT NULL,
  p_districts   text[]  DEFAULT NULL,
  p_schools     text[]  DEFAULT NULL,
  p_year_start  int     DEFAULT 2020,
  p_year_end    int     DEFAULT 2030,
  p_metrics     text[]  DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_is_admin       BOOLEAN;
  v_allowed_metrics TEXT[];
BEGIN
  v_is_admin := (auth.jwt()->'app_metadata'->>'role') = 'admin';

  IF v_is_admin THEN
    -- Admin sees all enabled metrics (filtered to requested list if provided)
    SELECT ARRAY_AGG(metric_name)
    INTO   v_allowed_metrics
    FROM   rep_portal.metric_config
    WHERE  enabled = true
      AND  (p_metrics IS NULL OR array_length(p_metrics, 1) IS NULL OR metric_name = ANY(p_metrics));
  ELSE
    -- Non-admin: intersect requested metrics with permitted metrics via RBAC
    SELECT ARRAY_AGG(DISTINCT mc.metric_name)
    INTO   v_allowed_metrics
    FROM   rep_portal.metric_config         mc
    JOIN   rep_portal.permission_metric_map pmm ON pmm.metric_config_id = mc.id
    JOIN   rep_portal.permissions           p   ON p.key                = pmm.permission_key
    JOIN   rep_portal.role_permissions      rp  ON rp.permission_id     = p.id
    JOIN   rep_portal.user_roles            ur  ON ur.role_id           = rp.role_id
    WHERE  ur.user_id  = auth.uid()
      AND  mc.enabled  = true
      AND  (p_metrics IS NULL OR array_length(p_metrics, 1) IS NULL OR mc.metric_name = ANY(p_metrics));
  END IF;

  IF v_allowed_metrics IS NULL OR array_length(v_allowed_metrics, 1) IS NULL THEN
    RETURN json_build_object('data', '[]'::json);
  END IF;

  RETURN (
    SELECT json_build_object('data', COALESCE(json_agg(r), '[]'::json))
    FROM (
      SELECT
        a.country,
        a.province,
        a.district,
        a.school,
        a.year,
        a.metric,
        a.value
      FROM rep_portal.dashboard_data_agg a
      WHERE a.metric = ANY(v_allowed_metrics)
        AND a.year BETWEEN p_year_start AND p_year_end
        AND (p_countries IS NULL OR array_length(p_countries, 1) IS NULL OR a.country  = ANY(p_countries))
        AND (p_provinces IS NULL OR array_length(p_provinces, 1) IS NULL OR a.province = ANY(p_provinces))
        AND (p_districts IS NULL OR array_length(p_districts, 1) IS NULL OR a.district = ANY(p_districts))
        AND (p_schools   IS NULL OR array_length(p_schools,   1) IS NULL OR a.school   = ANY(p_schools))
      ORDER BY a.metric, a.country, a.province, a.district, a.school, a.year
    ) r
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.get_dashboard_data_filtered(text[], text[], text[], text[], int, int, text[]) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_dashboard_data_filtered(text[], text[], text[], text[], int, int, text[]) TO authenticated;

