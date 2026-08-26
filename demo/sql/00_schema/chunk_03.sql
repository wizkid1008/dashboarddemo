-- Schema chunk 3 - run only after the previous chunk succeeded.
-- Generated from supabase/migrations in filename order. Do not reorder.


-- ===== 20260602160016_list_whatsapp_users_add_role.sql =====
-- Add role_name to list_whatsapp_users output.
-- Joins whatsapp_users.role_id → roles.name so the admin can see which role
-- was assigned during WA registration or admin creation.

CREATE OR REPLACE FUNCTION rep_portal.list_whatsapp_users(
  p_caller_id  uuid,
  p_page       int  DEFAULT 1,
  p_page_size  int  DEFAULT 25,
  p_search     text DEFAULT '',
  p_filter     text DEFAULT 'all'
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_portal, auth, rep_warehouse, public
AS $$
DECLARE
  v_caller_role       text;
  v_caller_districts  text[];
  v_result            jsonb;
BEGIN
  SELECT raw_app_meta_data->>'role'
  INTO   v_caller_role
  FROM   auth.users
  WHERE  id = p_caller_id;

  IF v_caller_role = 'country_admin' THEN
    SELECT array_agg(DISTINCT gbd.district)
    INTO   v_caller_districts
    FROM   rep_portal.get_bot_districts() gbd
    JOIN   rep_portal.user_countries uc
      ON   uc.country = gbd.country
    WHERE  uc.user_id = p_caller_id;
  END IF;

  WITH filtered AS (
    SELECT
      wu.id,
      wu.portal_id,
      wu.phone,
      wu.name,
      wu.email,
      wu.supabase_user_id,
      wu.is_approver,
      wu.linked_at,
      wu.created_at,
      (wu.supabase_user_id IS NOT NULL)           AS is_linked,
      (wu.phone <> '')                             AS has_phone,
      r.name                                       AS role_name,
      COALESCE(
        (SELECT jsonb_agg(jsonb_build_object(
                  'district_id',   d.district_id,
                  'district_name', d.district_name))
         FROM   rep_portal.whatsapp_approver_districts d
         WHERE  d.whatsapp_user_id = wu.id),
        '[]'::jsonb
      )                                            AS approver_districts,
      COALESCE(
        (SELECT jsonb_agg(jsonb_build_object(
                  'id',               a.id,
                  'district_id',      a.district_id,
                  'district_name',    a.district_name,
                  'status',           a.status,
                  'approver_id',      a.approver_id,
                  'decided_at',       a.decided_at,
                  'rejection_reason', a.rejection_reason))
         FROM   rep_portal.whatsapp_district_access a
         WHERE  a.requester_id = wu.id),
        '[]'::jsonb
      )                                            AS district_access
    FROM rep_portal.whatsapp_users wu
    LEFT JOIN rep_portal.roles r ON r.id = wu.role_id
    WHERE
      -- country-admin scoping: must have at least one district in scope
      (
        v_caller_role <> 'country_admin'
        OR EXISTS (
          SELECT 1 FROM rep_portal.whatsapp_district_access a
          WHERE  a.requester_id = wu.id
          AND    a.district_id  = ANY(v_caller_districts)
        )
        OR EXISTS (
          SELECT 1 FROM rep_portal.whatsapp_approver_districts d
          WHERE  d.whatsapp_user_id = wu.id
          AND    d.district_id      = ANY(v_caller_districts)
        )
      )
      -- text search (portal_id, name, email, phone, district)
      AND (
        p_search = ''
        OR wu.portal_id ILIKE '%' || p_search || '%'
        OR wu.name      ILIKE '%' || p_search || '%'
        OR wu.email     ILIKE '%' || p_search || '%'
        OR wu.phone     ILIKE '%' || p_search || '%'
        OR EXISTS (
          SELECT 1 FROM rep_portal.whatsapp_district_access a
          WHERE  a.requester_id = wu.id
          AND   (a.district_id   ILIKE '%' || p_search || '%'
              OR a.district_name ILIKE '%' || p_search || '%')
        )
        OR EXISTS (
          SELECT 1 FROM rep_portal.whatsapp_approver_districts d
          WHERE  d.whatsapp_user_id = wu.id
          AND   (d.district_id   ILIKE '%' || p_search || '%'
              OR d.district_name ILIKE '%' || p_search || '%')
        )
      )
      -- tab filter
      AND (
        p_filter = 'all'
        OR (p_filter = 'phone-only'  AND wu.phone <> '')
        OR (p_filter = 'approvers'   AND wu.is_approver = true)
        OR (p_filter = 'has-pending' AND EXISTS (
              SELECT 1 FROM rep_portal.whatsapp_district_access a
              WHERE  a.requester_id = wu.id AND a.status = 'pending'))
      )
  ),
  counted AS (
    SELECT *, COUNT(*) OVER() AS total_count
    FROM   filtered
    ORDER  BY created_at DESC
  ),
  paginated AS (
    SELECT * FROM counted
    LIMIT  p_page_size OFFSET (p_page - 1) * p_page_size
  )
  SELECT jsonb_build_object(
    'users', COALESCE(jsonb_agg(
      jsonb_build_object(
        'id',               id,
        'portal_id',        portal_id,
        'phone',            phone,
        'name',             name,
        'email',            email,
        'supabase_user_id', supabase_user_id,
        'is_approver',      is_approver,
        'linked_at',        linked_at,
        'created_at',       created_at,
        'is_linked',        is_linked,
        'has_phone',        has_phone,
        'role_name',        role_name,
        'approver_districts', approver_districts,
        'district_access',    district_access
      )), '[]'::jsonb),
    'total',    COALESCE(MAX(total_count)::int, 0),
    'page',     p_page,
    'pageSize', p_page_size
  )
  INTO  v_result
  FROM  paginated;

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.list_whatsapp_users(uuid, int, int, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.list_whatsapp_users(uuid, int, int, text, text) TO service_role;


-- ===== 20260603000001_grant_map_rpcs.sql =====
-- Migration 20260603000001
-- Fix: grant EXECUTE on the rep_portal map RPC functions to authenticated users.
-- Migration 029 moved get_district_kpi_data and get_school_point_data from the
-- public schema to rep_portal but omitted the GRANT statements, causing the map
-- to receive permission-denied errors and fall back to empty KPI data.

GRANT EXECUTE ON FUNCTION rep_portal.get_district_kpi_data() TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_school_point_data() TO authenticated;


-- ===== 20260603175952_kpi_delete_year_async_refresh.sql =====
-- Replace kpi_delete_year with an async refresh approach.
--
-- The REFRESH MATERIALIZED VIEW inside the previous version timed out under
-- PostgREST's statement_timeout. Instead we:
--   1. Add a helper rep_warehouse.refresh_dashboard_data_agg() callable by service_role.
--   2. Fire-and-forget a net.http_post() to the refresh-dashboard-agg edge function
--      so the delete RPC returns immediately while the refresh runs in the background.
--   3. The edge function URL is derived from the PostgREST request.headers host so
--      no extra config or vault secrets are required beyond the existing ingest_auth_header.

-- Helper called by the edge function (service_role only)
CREATE OR REPLACE FUNCTION rep_warehouse.refresh_dashboard_data_agg()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW rep_portal.dashboard_data_agg;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.refresh_dashboard_data_agg() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_warehouse.refresh_dashboard_data_agg() TO service_role;

-- Replace kpi_delete_year: deletes synchronously, triggers refresh asynchronously
CREATE OR REPLACE FUNCTION rep_warehouse.kpi_delete_year(p_year INTEGER)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_raw, rep_warehouse, rep_portal, public
AS $$
DECLARE
  v_batch_ids  TEXT[];
  v_host       TEXT;
  v_auth       TEXT;
  v_fn_url     TEXT;
BEGIN
  SELECT array_agg(batch_id)
    INTO v_batch_ids
    FROM rep_raw.upload_log
   WHERE year = p_year;

  IF v_batch_ids IS NOT NULL THEN
    DELETE FROM rep_raw.unmatched_rows WHERE batch_id = ANY(v_batch_ids);
    DELETE FROM rep_raw.duplicate_rows  WHERE batch_id = ANY(v_batch_ids);
    DELETE FROM rep_raw.all_kpis        WHERE batch_id = ANY(v_batch_ids);
  END IF;

  DELETE FROM rep_warehouse.fact_observed_kpi WHERE year = p_year;

  DELETE FROM rep_raw.upload_log WHERE year = p_year;

  -- Trigger async refresh via pg_net if vault secret is available.
  -- Derives the project URL from the PostgREST request host header — no extra
  -- config needed. Silently skips if vault secret is missing (e.g. local dev).
  BEGIN
    SELECT decrypted_secret
      INTO v_auth
      FROM vault.decrypted_secrets
     WHERE name = 'ingest_auth_header'
     LIMIT 1;

    IF v_auth IS NOT NULL THEN
      v_host   := (current_setting('request.headers', true)::jsonb)->>'host';
      v_fn_url := 'https://' || v_host || '/functions/v1/refresh-dashboard-agg';

      PERFORM net.http_post(
        url     := v_fn_url,
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', v_auth
        ),
        body    := '{}'::jsonb
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    -- Never let the async refresh attempt fail the delete
    NULL;
  END;

  RETURN jsonb_build_object('status', 'OK', 'year', p_year);
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.kpi_delete_year(INTEGER) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_warehouse.kpi_delete_year(INTEGER) TO service_role;


-- ===== 20260603181925_kpi_upload_async_refresh.sql =====
-- Replace synchronous REFRESH MATERIALIZED VIEW in kpi_upload_all and
-- kpi_upload_level_one with an async fire-and-forget net.http_post to
-- refresh-dashboard-agg, matching the pattern used in kpi_delete_year.
-- The upload functions already have SET statement_timeout = 0 so they won't
-- timeout, but the sync refresh blocks the upload response unnecessarily.

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
    v_host              TEXT;
    v_auth              TEXT;
BEGIN
    PERFORM set_config('app.batch_id',      p_batch_id,        true);
    PERFORM set_config('app.source_system', 'Excel_CAMFED',    true);
    PERFORM set_config('app.source_file',   p_source_file,     true);

    -- One successful upload per year: reject if a SUCCESS row already exists.
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

    -- Rebuild all_kpis staging from all raw rows
    PERFORM rep_warehouse.etl_stage_all_kpis();

    -- Geography pre-check: dim_geography must have a country-level row for every
    -- country present in this year's data. dim_geography is populated by the
    -- Salesforce ingest; KPI uploads must not create geography rows.
    SELECT STRING_AGG(DISTINCT s.country, ', ' ORDER BY s.country)
    INTO v_missing_countries
    FROM rep_staging.all_kpis s
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

    SELECT COUNT(*) INTO v_total_staged
    FROM rep_staging.all_kpis
    WHERE year = p_year;

    -- Load KPI definitions into dim_kpi before inserting facts.
    PERFORM rep_warehouse.etl_load_dim_kpi();

    -- Log duplicate fact-key combinations within this upload
    WITH deduped_rows AS (
        SELECT DISTINCT
            kpi_id, kpi_group, year,
            disaggregation_level_one, disaggregation_level_two,
            row_scope, row_id
        FROM rep_staging.all_kpis
        WHERE year = p_year
    )
    INSERT INTO rep_raw.duplicate_rows
        (batch_id, kpi_id, kpi_group, year,
         disaggregation_level_one, disaggregation_level_two,
         row_scope, occurrences, row_ids)
    SELECT
        p_batch_id,
        kpi_id, kpi_group, year,
        disaggregation_level_one, disaggregation_level_two,
        row_scope,
        COUNT(*),
        array_agg(row_id::text ORDER BY row_id::integer)
    FROM deduped_rows
    GROUP BY kpi_id, kpi_group, year,
             disaggregation_level_one, disaggregation_level_two, row_scope
    HAVING COUNT(*) > 1;

    -- Year-scoped replace: delete existing fact rows for this year then reinsert.
    DELETE FROM rep_warehouse.fact_observed_kpi WHERE year = p_year;

    WITH deduped AS (
        SELECT DISTINCT ON (
            s.year, s.country, s.kpi_id, s.kpi_group,
            s.disaggregation_level_one, s.disaggregation_level_two, s.row_scope
        )
            s.row_id, s.year, s.country, s.kpi_id,
            s.disaggregation_level_one, s.disaggregation_level_two,
            s.value_type, s.row_scope, s.value, s.updated_date
        FROM rep_staging.all_kpis s
        WHERE s.year = p_year
        ORDER BY
            s.year, s.country, s.kpi_id, s.kpi_group,
            s.disaggregation_level_one, s.disaggregation_level_two, s.row_scope,
            s.row_id DESC
    )
    INSERT INTO rep_warehouse.fact_observed_kpi
        (kpi_id, geography_id, year, year_date_id,
         disaggregation_level_one, disaggregation_level_two, value_type, row_scope,
         value, updated_date,
         lin_is_current, lin_change_type,
         lin_source_system, lin_source_file, lin_load_batch_id, lin_source_row_number)
    SELECT
        dk.id,
        dg.id,
        s.year,
        dd.id,
        s.disaggregation_level_one,
        s.disaggregation_level_two,
        s.value_type,
        s.row_scope,
        s.value,
        NULLIF(s.updated_date, '')::date,
        true,
        'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        s.row_id
    FROM deduped s
    INNER JOIN rep_warehouse.dim_kpi dk
           ON dk.source_kpi_id = s.kpi_id AND dk.scd_is_current = true
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
         status, uploaded_by, source_file)
    VALUES
        (p_batch_id, p_year, v_row_count, v_rows_loaded, 0, v_rows_dup,
         'SUCCESS', p_uploaded_by, p_source_file);

    -- Async refresh: fire-and-forget to avoid blocking the upload response.
    BEGIN
        SELECT decrypted_secret INTO v_auth
          FROM vault.decrypted_secrets
         WHERE name = 'ingest_auth_header'
         LIMIT 1;

        IF v_auth IS NOT NULL THEN
            v_host := (current_setting('request.headers', true)::jsonb)->>'host';
            PERFORM net.http_post(
                url     := 'https://' || v_host || '/functions/v1/refresh-dashboard-agg',
                headers := jsonb_build_object(
                    'Content-Type',  'application/json',
                    'Authorization', v_auth
                ),
                body    := '{}'::jsonb
            );
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    RETURN jsonb_build_object(
        'status',                 'SUCCESS',
        'batch_id',               p_batch_id,
        'year',                   p_year,
        'total_staged',           v_total_staged,
        'rows_loaded',            v_rows_loaded,
        'rows_unmatched_kpi',     0,
        'rows_skipped_duplicate', v_rows_dup
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


CREATE OR REPLACE FUNCTION rep_warehouse.kpi_upload_level_one(
    p_batch_id    TEXT,
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
    v_total_rows        INTEGER := 0;
    v_rows_updated      INTEGER := 0;
    v_rows_added        INTEGER := 0;
    v_missing_countries TEXT;
    v_host              TEXT;
    v_auth              TEXT;
BEGIN
    PERFORM set_config('app.batch_id',      p_batch_id,        true);
    PERFORM set_config('app.source_system', 'Excel_CAMFED',    true);
    PERFORM set_config('app.source_file',   p_source_file,     true);

    -- Geography pre-check against the current batch only
    SELECT STRING_AGG(DISTINCT TRIM(s.country), ', ' ORDER BY TRIM(s.country))
    INTO v_missing_countries
    FROM rep_raw.level_one_kpis s
    WHERE s.batch_id  = p_batch_id
      AND s.country  IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_geography g
          WHERE g.country = TRIM(s.country) AND g.province IS NULL AND g.district IS NULL
      );

    IF v_missing_countries IS NOT NULL THEN
        INSERT INTO rep_raw.level_one_upload_log
            (batch_id, rows_added, rows_updated, total_rows, status, error_msg, uploaded_by, source_file)
        VALUES
            (p_batch_id, 0, 0, 0, 'FAILED',
             'Countries not found in geography dimension (run Salesforce ingest first): ' || v_missing_countries,
             p_uploaded_by, p_source_file);

        RETURN jsonb_build_object(
            'status', 'FAILED',
            'error',  'Countries not found in geography dimension (run Salesforce ingest first): ' || v_missing_countries
        );
    END IF;

    -- Rebuild level_one staging from all raw rows (needed for etl_load_dim_kpi)
    PERFORM rep_warehouse.etl_stage_level_one_kpis();

    -- Load KPI definitions into dim_kpi before inserting facts
    PERFORM rep_warehouse.etl_load_dim_kpi();

    -- Count distinct rows in this batch (dedup by upsert key)
    SELECT COUNT(*) INTO v_total_rows
    FROM (
        SELECT DISTINCT ON (
            s.year::smallint,
            COALESCE(dg.id,                          -1),
            COALESCE(TRIM(s.school_level),           ''),
            COALESCE(TRIM(s.annual_newly_supported), ''),
            COALESCE(TRIM(s.type),                   ''),
            COALESCE(TRIM(s.gender),                 '')
        ) s.row_id
        FROM rep_raw.level_one_kpis s
        LEFT JOIN rep_warehouse.dim_geography dg
               ON dg.country = TRIM(s.country) AND dg.province IS NULL AND dg.district IS NULL
        WHERE s.batch_id = p_batch_id
          AND s.year    IS NOT NULL
          AND s.country IS NOT NULL
          AND s.kpi     IS NOT NULL
        ORDER BY
            s.year::smallint,
            COALESCE(dg.id,                          -1),
            COALESCE(TRIM(s.school_level),           ''),
            COALESCE(TRIM(s.annual_newly_supported), ''),
            COALESCE(TRIM(s.type),                   ''),
            COALESCE(TRIM(s.gender),                 ''),
            s.row_id DESC
    ) _t;

    -- Count rows that already exist in the warehouse (will be updated)
    SELECT COUNT(*) INTO v_rows_updated
    FROM (
        SELECT DISTINCT ON (
            s.year::smallint,
            COALESCE(dg.id,                          -1),
            COALESCE(TRIM(s.school_level),           ''),
            COALESCE(TRIM(s.annual_newly_supported), ''),
            COALESCE(TRIM(s.type),                   ''),
            COALESCE(TRIM(s.gender),                 '')
        )
            s.year::smallint                  AS year,
            dg.id                             AS geography_id,
            TRIM(s.school_level)              AS school_level,
            TRIM(s.annual_newly_supported)    AS annual_newly_supported,
            TRIM(s.type)                      AS fund_type,
            TRIM(s.gender)                    AS gender
        FROM rep_raw.level_one_kpis s
        LEFT JOIN rep_warehouse.dim_geography dg
               ON dg.country = TRIM(s.country) AND dg.province IS NULL AND dg.district IS NULL
        WHERE s.batch_id = p_batch_id
          AND s.year IS NOT NULL AND s.country IS NOT NULL AND s.kpi IS NOT NULL
        ORDER BY
            s.year::smallint,
            COALESCE(dg.id,                          -1),
            COALESCE(TRIM(s.school_level),           ''),
            COALESCE(TRIM(s.annual_newly_supported), ''),
            COALESCE(TRIM(s.type),                   ''),
            COALESCE(TRIM(s.gender),                 ''),
            s.row_id DESC
    ) deduped
    WHERE EXISTS (
        SELECT 1 FROM rep_warehouse.fact_level_one_kpis f
        WHERE f.year                                    = deduped.year
          AND COALESCE(f.geography_id,            -1)  = COALESCE(deduped.geography_id,            -1)
          AND COALESCE(f.school_level,            '')  = COALESCE(deduped.school_level,            '')
          AND COALESCE(f.annual_newly_supported,  '')  = COALESCE(deduped.annual_newly_supported,  '')
          AND COALESCE(f.fund_type,               '')  = COALESCE(deduped.fund_type,               '')
          AND COALESCE(f.gender,                  '')  = COALESCE(deduped.gender,                  '')
    );

    v_rows_added := v_total_rows - v_rows_updated;

    -- Upsert into fact table.
    WITH deduped AS (
        SELECT DISTINCT ON (
            s.year::smallint,
            COALESCE(dg.id,                          -1),
            COALESCE(TRIM(s.school_level),           ''),
            COALESCE(TRIM(s.annual_newly_supported), ''),
            COALESCE(TRIM(s.type),                   ''),
            COALESCE(TRIM(s.gender),                 '')
        )
            s.row_id,
            s.year::smallint                  AS year,
            TRIM(s.kpi)                       AS kpi,
            TRIM(s.school_level)              AS school_level,
            TRIM(s.annual_newly_supported)    AS annual_newly_supported,
            TRIM(s.type)                      AS fund_type,
            TRIM(s.gender)                    AS gender,
            TRIM(s.disaggregation_gender)     AS disaggregation_gender,
            CASE
                WHEN REPLACE(s.value::TEXT, ',', '') ~ '^-?[0-9]*\.?[0-9]+([eE][+-]?[0-9]+)?$'
                THEN REPLACE(s.value::TEXT, ',', '')::NUMERIC
            END                               AS value,
            dg.id                             AS geography_id
        FROM rep_raw.level_one_kpis s
        LEFT JOIN rep_warehouse.dim_geography dg
               ON dg.country = TRIM(s.country) AND dg.province IS NULL AND dg.district IS NULL
        WHERE s.batch_id = p_batch_id
          AND s.year IS NOT NULL AND s.country IS NOT NULL AND s.kpi IS NOT NULL
        ORDER BY
            s.year::smallint,
            COALESCE(dg.id,                          -1),
            COALESCE(TRIM(s.school_level),           ''),
            COALESCE(TRIM(s.annual_newly_supported), ''),
            COALESCE(TRIM(s.type),                   ''),
            COALESCE(TRIM(s.gender),                 ''),
            s.row_id DESC
    )
    INSERT INTO rep_warehouse.fact_level_one_kpis
        (kpi_id, geography_id, year_date_id, year,
         school_level, annual_newly_supported, fund_type, gender, disaggregation_gender,
         value,
         lin_is_current, lin_change_type,
         lin_source_system, lin_source_file, lin_load_batch_id, lin_source_row_number)
    SELECT
        dk.id,
        s.geography_id,
        dd.id,
        s.year,
        s.school_level, s.annual_newly_supported, s.fund_type, s.gender, s.disaggregation_gender,
        s.value,
        true,
        'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        s.row_id
    FROM deduped s
    INNER JOIN rep_warehouse.dim_kpi dk
           ON dk.source_kpi_id = s.kpi AND dk.scd_is_current = true
    LEFT  JOIN rep_warehouse.dim_date dd
           ON dd.id = ((s.year::text || '0101')::integer)
    ON CONFLICT (
        year,
        COALESCE(geography_id,            -1),
        COALESCE(school_level,            ''),
        COALESCE(annual_newly_supported,  ''),
        COALESCE(fund_type,               ''),
        COALESCE(gender,                  '')
    )
    DO UPDATE SET
        kpi_id                = EXCLUDED.kpi_id,
        disaggregation_gender = EXCLUDED.disaggregation_gender,
        value                 = EXCLUDED.value,
        lin_is_current        = true,
        lin_change_type       = 'UPDATE',
        lin_source_system     = EXCLUDED.lin_source_system,
        lin_source_file       = EXCLUDED.lin_source_file,
        lin_load_batch_id     = EXCLUDED.lin_load_batch_id,
        lin_source_row_number = EXCLUDED.lin_source_row_number;

    INSERT INTO rep_raw.level_one_upload_log
        (batch_id, rows_added, rows_updated, total_rows, status, uploaded_by, source_file)
    VALUES
        (p_batch_id, v_rows_added, v_rows_updated, v_total_rows,
         'SUCCESS', p_uploaded_by, p_source_file);

    -- Async refresh: fire-and-forget to avoid blocking the upload response.
    BEGIN
        SELECT decrypted_secret INTO v_auth
          FROM vault.decrypted_secrets
         WHERE name = 'ingest_auth_header'
         LIMIT 1;

        IF v_auth IS NOT NULL THEN
            v_host := (current_setting('request.headers', true)::jsonb)->>'host';
            PERFORM net.http_post(
                url     := 'https://' || v_host || '/functions/v1/refresh-dashboard-agg',
                headers := jsonb_build_object(
                    'Content-Type',  'application/json',
                    'Authorization', v_auth
                ),
                body    := '{}'::jsonb
            );
        END IF;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    RETURN jsonb_build_object(
        'status',       'SUCCESS',
        'batch_id',     p_batch_id,
        'rows_added',   v_rows_added,
        'rows_updated', v_rows_updated,
        'total_rows',   v_total_rows,
        'message',      format('Loaded %s rows: %s added, %s updated',
                               v_total_rows, v_rows_added, v_rows_updated)
    );

EXCEPTION WHEN OTHERS THEN
    INSERT INTO rep_raw.level_one_upload_log
        (batch_id, rows_added, rows_updated, total_rows, status, error_msg, uploaded_by, source_file)
    VALUES
        (p_batch_id, 0, 0, 0, 'FAILED', SQLERRM, p_uploaded_by, p_source_file);

    RETURN jsonb_build_object('status', 'FAILED', 'error', SQLERRM);
END;
$$;


-- ===== 20260604000001_rebuild_dashboard_agg_from_salesforce.sql =====
-- Rebuild dashboard_data_agg from pure Salesforce transactional data.
--
-- All metrics now start at the individual student/guide/member record level
-- and aggregate naturally to school → district → country.
-- No manual KPI uploads (view_observed_kpi) are used.
--
-- Columns: country, district, school, year, metric, value
--
--   school = actual school name          (school-level rows)
--   school = 'District Total'            (district-level rows, no school breakdown)
--   school = 'National'                  (country-level rows)
--
-- fact_post_school_support, fact_grants, fact_loans have no school_id
-- so they aggregate to district level only.

DROP MATERIALIZED VIEW IF EXISTS rep_portal.dashboard_data_agg;

CREATE MATERIALIZED VIEW rep_portal.dashboard_data_agg AS

-- ─────────────────────────────────────────────────────────────────────────────
-- CHILDREN SUPPORTED  (fact_children_supported → school level)
-- ─────────────────────────────────────────────────────────────────────────────

-- Total children supported per school per year
SELECT v.country, v.district, v.school_name AS school, v.year,
       'Children Supported — Total'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

-- Girls supported per school per year
SELECT v.country, v.district, v.school_name AS school, v.year,
       'Children Supported — Girls'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.gender = 'Female'
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

-- Boys supported per school per year
SELECT v.country, v.district, v.school_name AS school, v.year,
       'Children Supported — Boys'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.gender = 'Male'
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

-- Bursary girls per school per year
SELECT v.country, v.district, v.school_name AS school, v.year,
       'Children Supported — Bursary Girls'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL
  AND v.contact_record_type = 'Bursary Pupil' AND v.gender = 'Female'
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

-- Step Up Fund children per school per year
SELECT v.country, v.district, v.school_name AS school, v.year,
       'Children Supported — Step Up Fund'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL
  AND v.contact_record_type = 'Step Up Fund Pupil'
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

-- Girls living with disability per school per year
SELECT v.country, v.district, v.school_name AS school, v.year,
       'Children Supported — Girls with Disability'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL
  AND v.gender = 'Female' AND v.wg_difficulty_overall IS NOT NULL
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

-- Children with attendance issues per school per year
SELECT v.country, v.district, v.school_name AS school, v.year,
       'Children Supported — Attendance Issues'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.attendance_issues = true
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

-- Children who repeated a year per school per year
SELECT v.country, v.district, v.school_name AS school, v.year,
       'Children Supported — Repeated Year'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.repeated = true
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

-- Children receiving financial support per school per year
SELECT v.country, v.district, v.school_name AS school, v.year,
       'Children Supported — Received Financial Support'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.received_financial_support = true
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

-- ─────────────────────────────────────────────────────────────────────────────
-- GUIDES  (fact_guide_assignment → school level)
-- Active = guide_status = 'Active'; year based on when they joined
-- ─────────────────────────────────────────────────────────────────────────────

-- Active Learner Guides per school
SELECT v.country, v.district, v.school_name AS school,
       v.joined_year AS year,
       'Active Learner Guides'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
WHERE v.school_name IS NOT NULL AND v.joined_year IS NOT NULL
  AND v.guide_type = 'Learner Guide' AND v.guide_status = 'Active'
GROUP BY v.country, v.district, v.school_name, v.joined_year

UNION ALL

-- Active Transition Guides per school
SELECT v.country, v.district, v.school_name AS school,
       v.joined_year AS year,
       'Active Transition Guides'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
WHERE v.school_name IS NOT NULL AND v.joined_year IS NOT NULL
  AND v.guide_type ILIKE '%Transition%' AND v.guide_status = 'Active'
GROUP BY v.country, v.district, v.school_name, v.joined_year

UNION ALL

-- Active Enterprise Guides per school
SELECT v.country, v.district, v.school_name AS school,
       v.joined_year AS year,
       'Active Enterprise Guides'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
WHERE v.school_name IS NOT NULL AND v.joined_year IS NOT NULL
  AND v.guide_type ILIKE '%Enterprise%' AND v.guide_status = 'Active'
GROUP BY v.country, v.district, v.school_name, v.joined_year

UNION ALL

-- Active Community Champions per school
SELECT v.country, v.district, v.school_name AS school,
       v.joined_year AS year,
       'Active Community Champions'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
WHERE v.school_name IS NOT NULL AND v.joined_year IS NOT NULL
  AND v.guide_type ILIKE '%Community Champion%' AND v.guide_status = 'Active'
GROUP BY v.country, v.district, v.school_name, v.joined_year

UNION ALL

-- Guides trained in climate education per school
SELECT v.country, v.district, v.school_name AS school,
       v.joined_year AS year,
       'Guides — Trained in Climate Education'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
WHERE v.school_name IS NOT NULL AND v.joined_year IS NOT NULL
  AND v.trained_in_climate_education = true AND v.guide_status = 'Active'
GROUP BY v.country, v.district, v.school_name, v.joined_year

UNION ALL

-- ─────────────────────────────────────────────────────────────────────────────
-- CAMA MEMBERSHIP  (fact_cama_membership → school level)
-- ─────────────────────────────────────────────────────────────────────────────

-- Total CAMA members per school per join year
SELECT v.country, v.district, v.school_name AS school,
       v.join_year AS year,
       'CAMA Members'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_cama_membership v
WHERE v.school_name IS NOT NULL AND v.join_year IS NOT NULL
GROUP BY v.country, v.district, v.school_name, v.join_year

UNION ALL

-- CAMA members at partner schools
SELECT v.country, v.district, v.school_name AS school,
       v.join_year AS year,
       'CAMA Members — Partner School'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_cama_membership v
WHERE v.school_name IS NOT NULL AND v.join_year IS NOT NULL AND v.partner_school = true
GROUP BY v.country, v.district, v.school_name, v.join_year

UNION ALL

-- CAMA members with disability
SELECT v.country, v.district, v.school_name AS school,
       v.join_year AS year,
       'CAMA Members — With Disability'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_cama_membership v
WHERE v.school_name IS NOT NULL AND v.join_year IS NOT NULL
  AND v.wg_difficulty_overall IS NOT NULL
GROUP BY v.country, v.district, v.school_name, v.join_year

UNION ALL

-- ─────────────────────────────────────────────────────────────────────────────
-- POST-SCHOOL SUPPORT  (fact_post_school_support → district level only)
-- ─────────────────────────────────────────────────────────────────────────────

-- Women in post-school / tertiary support per district per year
SELECT v.country, v.district, 'District Total'::text AS school,
       v.year,
       'Post-School Support — Total'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_post_school_support v
WHERE v.district IS NOT NULL AND v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

-- Post-school women receiving financial support
SELECT v.country, v.district, 'District Total'::text AS school,
       v.year,
       'Post-School Support — Received Financial Support'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_post_school_support v
WHERE v.district IS NOT NULL AND v.year IS NOT NULL AND v.received_financial_support = true
GROUP BY v.country, v.district, v.year

UNION ALL

-- ─────────────────────────────────────────────────────────────────────────────
-- GRANTS  (fact_grants → district level only)
-- ─────────────────────────────────────────────────────────────────────────────

-- Number of grants per district per year
SELECT v.country, v.district, 'District Total'::text AS school,
       v.grant_year AS year,
       'Grants — Count'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_grants v
WHERE v.district IS NOT NULL AND v.grant_year IS NOT NULL
GROUP BY v.country, v.district, v.grant_year

UNION ALL

-- Total grant value per district per year (USD)
SELECT v.country, v.district, 'District Total'::text AS school,
       v.grant_year AS year,
       'Grants — Total Value (USD)'::text AS metric,
       ROUND(SUM(v.amount_given::numeric))::int AS value
FROM rep_warehouse.view_grants v
WHERE v.district IS NOT NULL AND v.grant_year IS NOT NULL
GROUP BY v.country, v.district, v.grant_year

UNION ALL

-- ─────────────────────────────────────────────────────────────────────────────
-- LOANS  (fact_loans → district level only)
-- ─────────────────────────────────────────────────────────────────────────────

-- Number of loans per district per year
SELECT v.country, v.district, 'District Total'::text AS school,
       v.disbursal_year AS year,
       'Loans — Count'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
WHERE v.district IS NOT NULL AND v.disbursal_year IS NOT NULL
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

-- Total loan value per district per year
SELECT v.country, v.district, 'District Total'::text AS school,
       v.disbursal_year AS year,
       'Loans — Total Value'::text AS metric,
       ROUND(SUM(COALESCE(v.loan_value, 0)))::int AS value
FROM rep_warehouse.view_loans v
WHERE v.district IS NOT NULL AND v.disbursal_year IS NOT NULL
GROUP BY v.country, v.district, v.disbursal_year

WITH NO DATA;

-- ─────────────────────────────────────────────────────────────────────────────
-- Indexes for fast filtering by any geography level
-- ─────────────────────────────────────────────────────────────────────────────

CREATE INDEX idx_dda_country  ON rep_portal.dashboard_data_agg (country);
CREATE INDEX idx_dda_district ON rep_portal.dashboard_data_agg (country, district);
CREATE INDEX idx_dda_school   ON rep_portal.dashboard_data_agg (country, district, school);
CREATE INDEX idx_dda_metric   ON rep_portal.dashboard_data_agg (metric);
CREATE INDEX idx_dda_year     ON rep_portal.dashboard_data_agg (year);

-- ─────────────────────────────────────────────────────────────────────────────
-- Populate
-- ─────────────────────────────────────────────────────────────────────────────

REFRESH MATERIALIZED VIEW rep_portal.dashboard_data_agg;


-- ===== 20260604000002_add_province_to_dashboard_agg.sql =====
-- Add province to dashboard_data_agg so the full hierarchy is available:
-- school → district → province → country
--
-- Also updates get_dashboard_data() to include province in the payload.

DROP MATERIALIZED VIEW IF EXISTS rep_portal.dashboard_data_agg;

CREATE MATERIALIZED VIEW rep_portal.dashboard_data_agg AS

-- ── CHILDREN SUPPORTED (school level) ────────────────────────────────────────

SELECT v.country, v.province, v.district, v.school_name AS school, v.year,
       'Children Supported — Total'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL
GROUP BY v.country, v.province, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.province, v.district, v.school_name AS school, v.year,
       'Children Supported — Girls'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.gender = 'Female'
GROUP BY v.country, v.province, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.province, v.district, v.school_name AS school, v.year,
       'Children Supported — Boys'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.gender = 'Male'
GROUP BY v.country, v.province, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.province, v.district, v.school_name AS school, v.year,
       'Children Supported — Bursary Girls'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL
  AND v.contact_record_type = 'Bursary Pupil' AND v.gender = 'Female'
GROUP BY v.country, v.province, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.province, v.district, v.school_name AS school, v.year,
       'Children Supported — Step Up Fund'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL
  AND v.contact_record_type = 'Step Up Fund Pupil'
GROUP BY v.country, v.province, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.province, v.district, v.school_name AS school, v.year,
       'Children Supported — Girls with Disability'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL
  AND v.gender = 'Female' AND v.wg_difficulty_overall IS NOT NULL
GROUP BY v.country, v.province, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.province, v.district, v.school_name AS school, v.year,
       'Children Supported — Attendance Issues'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.attendance_issues = true
GROUP BY v.country, v.province, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.province, v.district, v.school_name AS school, v.year,
       'Children Supported — Repeated Year'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.repeated = true
GROUP BY v.country, v.province, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.province, v.district, v.school_name AS school, v.year,
       'Children Supported — Received Financial Support'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.received_financial_support = true
GROUP BY v.country, v.province, v.district, v.school_name, v.year

UNION ALL

-- ── GUIDES (school level) ─────────────────────────────────────────────────────

SELECT v.country, v.province, v.district, v.school_name AS school, v.joined_year AS year,
       'Active Learner Guides'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
WHERE v.school_name IS NOT NULL AND v.joined_year IS NOT NULL
  AND v.guide_type = 'Learner Guide' AND v.guide_status = 'Active'
GROUP BY v.country, v.province, v.district, v.school_name, v.joined_year

UNION ALL

SELECT v.country, v.province, v.district, v.school_name AS school, v.joined_year AS year,
       'Active Transition Guides'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
WHERE v.school_name IS NOT NULL AND v.joined_year IS NOT NULL
  AND v.guide_type ILIKE '%Transition%' AND v.guide_status = 'Active'
GROUP BY v.country, v.province, v.district, v.school_name, v.joined_year

UNION ALL

SELECT v.country, v.province, v.district, v.school_name AS school, v.joined_year AS year,
       'Active Enterprise Guides'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
WHERE v.school_name IS NOT NULL AND v.joined_year IS NOT NULL
  AND v.guide_type ILIKE '%Enterprise%' AND v.guide_status = 'Active'
GROUP BY v.country, v.province, v.district, v.school_name, v.joined_year

UNION ALL

SELECT v.country, v.province, v.district, v.school_name AS school, v.joined_year AS year,
       'Active Community Champions'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
WHERE v.school_name IS NOT NULL AND v.joined_year IS NOT NULL
  AND v.guide_type ILIKE '%Community Champion%' AND v.guide_status = 'Active'
GROUP BY v.country, v.province, v.district, v.school_name, v.joined_year

UNION ALL

SELECT v.country, v.province, v.district, v.school_name AS school, v.joined_year AS year,
       'Guides — Trained in Climate Education'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
WHERE v.school_name IS NOT NULL AND v.joined_year IS NOT NULL
  AND v.trained_in_climate_education = true AND v.guide_status = 'Active'
GROUP BY v.country, v.province, v.district, v.school_name, v.joined_year

UNION ALL

-- ── CAMA MEMBERSHIP (school level) ───────────────────────────────────────────

SELECT v.country, v.province, v.district, v.school_name AS school, v.join_year AS year,
       'CAMA Members'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_cama_membership v
WHERE v.school_name IS NOT NULL AND v.join_year IS NOT NULL
GROUP BY v.country, v.province, v.district, v.school_name, v.join_year

UNION ALL

SELECT v.country, v.province, v.district, v.school_name AS school, v.join_year AS year,
       'CAMA Members — Partner School'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_cama_membership v
WHERE v.school_name IS NOT NULL AND v.join_year IS NOT NULL AND v.partner_school = true
GROUP BY v.country, v.province, v.district, v.school_name, v.join_year

UNION ALL

SELECT v.country, v.province, v.district, v.school_name AS school, v.join_year AS year,
       'CAMA Members — With Disability'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_cama_membership v
WHERE v.school_name IS NOT NULL AND v.join_year IS NOT NULL
  AND v.wg_difficulty_overall IS NOT NULL
GROUP BY v.country, v.province, v.district, v.school_name, v.join_year

UNION ALL

-- ── POST-SCHOOL SUPPORT (district level — no school_id) ──────────────────────

SELECT v.country, v.province, v.district, 'District Total'::text AS school, v.year,
       'Post-School Support — Total'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_post_school_support v
WHERE v.district IS NOT NULL AND v.year IS NOT NULL
GROUP BY v.country, v.province, v.district, v.year

UNION ALL

SELECT v.country, v.province, v.district, 'District Total'::text AS school, v.year,
       'Post-School Support — Received Financial Support'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_post_school_support v
WHERE v.district IS NOT NULL AND v.year IS NOT NULL AND v.received_financial_support = true
GROUP BY v.country, v.province, v.district, v.year

UNION ALL

-- ── GRANTS (district level — no school_id) ───────────────────────────────────

SELECT v.country, v.province, v.district, 'District Total'::text AS school, v.grant_year AS year,
       'Grants — Count'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_grants v
WHERE v.district IS NOT NULL AND v.grant_year IS NOT NULL
GROUP BY v.country, v.province, v.district, v.grant_year

UNION ALL

SELECT v.country, v.province, v.district, 'District Total'::text AS school, v.grant_year AS year,
       'Grants — Total Value (USD)'::text AS metric,
       ROUND(SUM(v.amount_given::numeric))::int AS value
FROM rep_warehouse.view_grants v
WHERE v.district IS NOT NULL AND v.grant_year IS NOT NULL
GROUP BY v.country, v.province, v.district, v.grant_year

UNION ALL

-- ── LOANS (district level — no school_id) ────────────────────────────────────

SELECT v.country, v.province, v.district, 'District Total'::text AS school, v.disbursal_year AS year,
       'Loans — Count'::text AS metric, COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
WHERE v.district IS NOT NULL AND v.disbursal_year IS NOT NULL
GROUP BY v.country, v.province, v.district, v.disbursal_year

UNION ALL

SELECT v.country, v.province, v.district, 'District Total'::text AS school, v.disbursal_year AS year,
       'Loans — Total Value'::text AS metric,
       ROUND(SUM(COALESCE(v.loan_value, 0)))::int AS value
FROM rep_warehouse.view_loans v
WHERE v.district IS NOT NULL AND v.disbursal_year IS NOT NULL
GROUP BY v.country, v.province, v.district, v.disbursal_year

WITH NO DATA;

-- ── Indexes ───────────────────────────────────────────────────────────────────

CREATE INDEX idx_dda_country  ON rep_portal.dashboard_data_agg (country);
CREATE INDEX idx_dda_province ON rep_portal.dashboard_data_agg (country, province);
CREATE INDEX idx_dda_district ON rep_portal.dashboard_data_agg (country, province, district);
CREATE INDEX idx_dda_school   ON rep_portal.dashboard_data_agg (country, province, district, school);
CREATE INDEX idx_dda_metric   ON rep_portal.dashboard_data_agg (metric);
CREATE INDEX idx_dda_year     ON rep_portal.dashboard_data_agg (year);

REFRESH MATERIALIZED VIEW rep_portal.dashboard_data_agg;

-- ── Update get_dashboard_data() to include province ──────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.get_dashboard_data()
RETURNS json LANGUAGE sql SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT json_build_object('data', json_agg(r))
  FROM (SELECT * FROM rep_portal.dashboard_data_agg) r;
$$;


-- ===== 20260604000003_dynamic_data_province_rpcs.sql =====
-- Update RPCs to support the rebuilt Dynamic Data page.
--
-- Changes:
--   1. get_dashboard_metadata() — adds province to geography hierarchy
--   2. get_dashboard_data_filtered() — adds province[], district[], school[] filters

-- ── 1. get_dashboard_metadata ─────────────────────────────────────────────────
-- Returns countries, years, and the full country→province→district→school
-- hierarchy for populating cascading dropdowns.

CREATE OR REPLACE FUNCTION rep_portal.get_dashboard_metadata()
RETURNS json LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = rep_portal, public
AS $$
  SELECT json_build_object(
    'countries', (
      SELECT COALESCE(json_agg(c ORDER BY c), '[]'::json)
      FROM (SELECT DISTINCT country AS c FROM rep_portal.dashboard_data_agg WHERE country IS NOT NULL) _c
    ),
    'years', (
      SELECT COALESCE(json_agg(y ORDER BY y), '[]'::json)
      FROM (SELECT DISTINCT year AS y FROM rep_portal.dashboard_data_agg WHERE year IS NOT NULL) _y
    ),
    'metrics', (
      SELECT COALESCE(json_agg(m ORDER BY m), '[]'::json)
      FROM (SELECT DISTINCT metric AS m FROM rep_portal.dashboard_data_agg WHERE metric IS NOT NULL) _m
    ),
    'geography', (
      SELECT COALESCE(json_agg(row_to_json(r)), '[]'::json)
      FROM (
        SELECT DISTINCT country, province, district, school
        FROM   rep_portal.dashboard_data_agg
        WHERE  country  IS NOT NULL
          AND  school   NOT IN ('District Total', 'National')
        ORDER BY country, province, district, school
      ) r
    )
  );
$$;

GRANT EXECUTE ON FUNCTION rep_portal.get_dashboard_metadata() TO authenticated;

-- ── 2. get_dashboard_data_filtered ───────────────────────────────────────────
-- Adds p_provinces, p_districts, p_schools filters.
-- Old signature is replaced — the frontend will pass the new params.

DROP FUNCTION IF EXISTS rep_portal.get_dashboard_data_filtered(text[], int, int, text[]);

CREATE OR REPLACE FUNCTION rep_portal.get_dashboard_data_filtered(
  p_countries   text[]  DEFAULT NULL,
  p_provinces   text[]  DEFAULT NULL,
  p_districts   text[]  DEFAULT NULL,
  p_schools     text[]  DEFAULT NULL,
  p_year_start  int     DEFAULT 2020,
  p_year_end    int     DEFAULT 2030,
  p_metrics     text[]  DEFAULT NULL
)
RETURNS json LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = rep_portal, public
AS $$
  SELECT json_build_object('data', COALESCE(json_agg(r), '[]'::json))
  FROM (
    SELECT d.*
    FROM rep_portal.dashboard_data_agg d
    WHERE
      d.year BETWEEN p_year_start AND p_year_end
      AND (p_countries IS NULL OR array_length(p_countries, 1) IS NULL OR d.country  = ANY(p_countries))
      AND (p_provinces IS NULL OR array_length(p_provinces, 1) IS NULL OR d.province = ANY(p_provinces))
      AND (p_districts IS NULL OR array_length(p_districts, 1) IS NULL OR d.district = ANY(p_districts))
      AND (p_schools   IS NULL OR array_length(p_schools,   1) IS NULL OR d.school   = ANY(p_schools))
      AND (p_metrics   IS NULL OR array_length(p_metrics,   1) IS NULL OR d.metric   = ANY(p_metrics))
      AND (
        (auth.jwt()->'app_metadata'->>'role') = 'admin'
        OR EXISTS (
          SELECT 1
          FROM   rep_portal.permission_metric_map pmm
          JOIN   rep_portal.permissions       p  ON p.key            = pmm.permission_key
          JOIN   rep_portal.role_permissions  rp ON rp.permission_id = p.id
          JOIN   rep_portal.user_roles        ur ON ur.role_id       = rp.role_id
          WHERE  ur.user_id    = auth.uid()
            AND  pmm.metric_id = d.metric
        )
      )
  ) r;
$$;

GRANT EXECUTE ON FUNCTION rep_portal.get_dashboard_data_filtered(text[], text[], text[], text[], int, int, text[]) TO authenticated;
REVOKE EXECUTE ON FUNCTION rep_portal.get_dashboard_data_filtered(text[], text[], text[], text[], int, int, text[]) FROM anon;

-- ── 3. Permission map entries for new Salesforce-sourced metrics ──────────────
-- Add all new dashboard_data_agg metrics to a general 'dd:salesforce' permission.
-- Admins see everything; this ensures non-admins with that permission also see them.

INSERT INTO rep_portal.permissions (key, label, category, parent_key)
VALUES ('dd:salesforce', 'Dynamic Data — Salesforce', 'dashlet', 'Dynamic Data')
ON CONFLICT (key) DO NOTHING;

INSERT INTO rep_portal.permission_metric_map (permission_key, metric_id) VALUES
  ('dd:salesforce', 'Children Supported — Total'),
  ('dd:salesforce', 'Children Supported — Girls'),
  ('dd:salesforce', 'Children Supported — Boys'),
  ('dd:salesforce', 'Children Supported — Bursary Girls'),
  ('dd:salesforce', 'Children Supported — Step Up Fund'),
  ('dd:salesforce', 'Children Supported — Girls with Disability'),
  ('dd:salesforce', 'Children Supported — Attendance Issues'),
  ('dd:salesforce', 'Children Supported — Repeated Year'),
  ('dd:salesforce', 'Children Supported — Received Financial Support'),
  ('dd:salesforce', 'Active Learner Guides'),
  ('dd:salesforce', 'Active Transition Guides'),
  ('dd:salesforce', 'Active Enterprise Guides'),
  ('dd:salesforce', 'Active Community Champions'),
  ('dd:salesforce', 'Guides — Trained in Climate Education'),
  ('dd:salesforce', 'CAMA Members'),
  ('dd:salesforce', 'CAMA Members — Partner School'),
  ('dd:salesforce', 'CAMA Members — With Disability'),
  ('dd:salesforce', 'Post-School Support — Total'),
  ('dd:salesforce', 'Post-School Support — Received Financial Support'),
  ('dd:salesforce', 'Grants — Count'),
  ('dd:salesforce', 'Grants — Total Value (USD)'),
  ('dd:salesforce', 'Loans — Count'),
  ('dd:salesforce', 'Loans — Total Value')
ON CONFLICT DO NOTHING;


-- ===== 20260605071823_dim_kpi_add_definition_columns.sql =====
-- Add KPI metadata columns to dim_kpi.
-- kpi-definitions.xlsx is now the sole source for dim_kpi; these columns
-- carry the richer metadata from that file.

ALTER TABLE rep_warehouse.dim_kpi
    ADD COLUMN IF NOT EXISTS indicator_frequency TEXT,
    ADD COLUMN IF NOT EXISTS indicator_start     TEXT,
    ADD COLUMN IF NOT EXISTS definition          TEXT;


-- ===== 20260605071846_kpi_definitions_load.sql =====
-- kpi-definitions.xlsx is now the sole source for rep_warehouse.dim_kpi.
--
-- Changes:
--   1. kpi_definitions_load() — upserts dim_kpi from a JSONB array of rows
--      parsed from kpi-definitions.xlsx.  Full SCD2 on kpi_group/indicator
--      changes; type-1 in-place update for the three metadata columns.
--   2. etl_load_dim_kpi() — dropped.  dim_kpi must be populated via the
--      definitions upload before KPI data uploads are attempted.
--   3. kpi_upload_all() — removes the etl_load_dim_kpi() call; adds a hard-
--      failure pre-check that lists any kpi_id values in the staged data that
--      have no matching dim_kpi entry.
--   4. kpi_upload_level_one() — same pre-check added, etl_load_dim_kpi() removed.


-- ── 1. kpi_definitions_load ───────────────────────────────────────────────────

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
    v_cur_group TEXT;
    v_cur_ind   TEXT;
    v_max_ver   INTEGER;
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

        v_new_hash := MD5(
            concat_ws('||',
                COALESCE(v_src_id,    ''),
                COALESCE(v_group,     ''),
                COALESCE(v_indicator, ''),
                COALESCE(v_freq,      ''),
                COALESCE(v_start,     ''),
                COALESCE(v_defn,      '')
            )
        );

        -- Check if a current row already exists
        SELECT lin_business_hash, kpi_group, indicator
          INTO v_cur_hash, v_cur_group, v_cur_ind
          FROM rep_warehouse.dim_kpi
         WHERE source_kpi_id = v_src_id AND scd_is_current = true
         LIMIT 1;

        IF NOT FOUND THEN
            -- Brand-new KPI — insert
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
                 v_new_hash,
                 p_batch_id, 'Excel_CAMFED', p_source_file, NOW());

            v_inserted := v_inserted + 1;

        ELSIF v_cur_hash = v_new_hash THEN
            -- No change — skip
            v_skipped := v_skipped + 1;

        ELSIF v_cur_group IS DISTINCT FROM v_group
           OR v_cur_ind   IS DISTINCT FROM v_indicator THEN
            -- Core identity changed — SCD2: expire old, insert new version
            UPDATE rep_warehouse.dim_kpi
               SET scd_is_current    = false,
                   scd_effective_to  = CURRENT_DATE - 1,
                   lin_superseded_at = NOW()
             WHERE source_kpi_id = v_src_id AND scd_is_current = true;

            SELECT COALESCE(MAX(scd_version), 0) INTO v_max_ver
              FROM rep_warehouse.dim_kpi
             WHERE source_kpi_id = v_src_id;

            INSERT INTO rep_warehouse.dim_kpi
                (source_kpi_id, kpi_group, indicator,
                 indicator_frequency, indicator_start, definition,
                 scd_effective_from, scd_is_current, scd_version,
                 lin_business_hash, lin_load_batch_id,
                 lin_source_system, lin_source_file, lin_inserted_at)
            VALUES
                (v_src_id, v_group, v_indicator,
                 v_freq, v_start, v_defn,
                 CURRENT_DATE, true, v_max_ver + 1,
                 v_new_hash,
                 p_batch_id, 'Excel_CAMFED', p_source_file, NOW());

            v_updated := v_updated + 1;

        ELSE
            -- Only metadata columns changed — update in-place (no SCD bump)
            UPDATE rep_warehouse.dim_kpi
               SET indicator_frequency = v_freq,
                   indicator_start     = v_start,
                   definition          = v_defn,
                   lin_business_hash   = v_new_hash,
                   lin_load_batch_id   = p_batch_id,
                   lin_source_file     = p_source_file
             WHERE source_kpi_id = v_src_id AND scd_is_current = true;

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


-- ── 2. Drop etl_load_dim_kpi ─────────────────────────────────────────────────

DROP FUNCTION IF EXISTS rep_warehouse.etl_load_dim_kpi();


-- ── 3. kpi_upload_all: remove etl_load_dim_kpi call, add KPI pre-check ───────

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
BEGIN
    PERFORM set_config('app.batch_id',      p_batch_id,        true);
    PERFORM set_config('app.source_system', 'Excel_CAMFED',    true);
    PERFORM set_config('app.source_file',   p_source_file,     true);

    -- One successful upload per year: reject if a SUCCESS row already exists.
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

    -- Rebuild all_kpis staging from all raw rows
    PERFORM rep_warehouse.etl_stage_all_kpis();

    -- Geography pre-check
    SELECT STRING_AGG(DISTINCT s.country, ', ' ORDER BY s.country)
    INTO v_missing_countries
    FROM rep_staging.all_kpis s
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

    -- KPI pre-check: every kpi_id in the staged data must exist in dim_kpi.
    -- dim_kpi is now populated exclusively via kpi-definitions.xlsx upload.
    SELECT STRING_AGG(DISTINCT s.kpi_id, ', ' ORDER BY s.kpi_id)
    INTO v_missing_kpis
    FROM rep_staging.all_kpis s
    WHERE s.year = p_year
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_kpi dk
          WHERE dk.source_kpi_id = s.kpi_id AND dk.scd_is_current = true
      );

    IF v_missing_kpis IS NOT NULL THEN
        INSERT INTO rep_raw.upload_log
            (batch_id, year, row_count, rows_loaded, rows_unmatched, rows_duplicate,
             status, error_msg, uploaded_by, source_file)
        VALUES
            (p_batch_id, p_year, v_row_count, 0, 0, 0, 'FAILED',
             'KPI IDs not found in definitions (upload kpi-definitions.xlsx first): ' || v_missing_kpis,
             p_uploaded_by, p_source_file);

        RETURN jsonb_build_object(
            'status', 'FAILED',
            'error',  'KPI IDs not found in definitions (upload kpi-definitions.xlsx first): ' || v_missing_kpis
        );
    END IF;

    SELECT COUNT(*) INTO v_total_staged
    FROM rep_staging.all_kpis
    WHERE year = p_year;

    -- Log duplicate fact-key combinations within this upload
    WITH deduped_rows AS (
        SELECT DISTINCT
            kpi_id, kpi_group, year,
            disaggregation_level_one, disaggregation_level_two,
            row_scope, row_id
        FROM rep_staging.all_kpis
        WHERE year = p_year
    )
    INSERT INTO rep_raw.duplicate_rows
        (batch_id, kpi_id, kpi_group, year,
         disaggregation_level_one, disaggregation_level_two,
         row_scope, occurrences, row_ids)
    SELECT
        p_batch_id,
        kpi_id, kpi_group, year,
        disaggregation_level_one, disaggregation_level_two,
        row_scope,
        COUNT(*),
        array_agg(row_id::text ORDER BY row_id::integer)
    FROM deduped_rows
    GROUP BY kpi_id, kpi_group, year,
             disaggregation_level_one, disaggregation_level_two, row_scope
    HAVING COUNT(*) > 1;

    -- Year-scoped replace
    DELETE FROM rep_warehouse.fact_observed_kpi WHERE year = p_year;

    WITH deduped AS (
        SELECT DISTINCT ON (
            s.year, s.country, s.kpi_id, s.kpi_group,
            s.disaggregation_level_one, s.disaggregation_level_two, s.row_scope
        )
            s.row_id, s.year, s.country, s.kpi_id,
            s.disaggregation_level_one, s.disaggregation_level_two,
            s.value_type, s.row_scope, s.value, s.updated_date
        FROM rep_staging.all_kpis s
        WHERE s.year = p_year
        ORDER BY
            s.year, s.country, s.kpi_id, s.kpi_group,
            s.disaggregation_level_one, s.disaggregation_level_two, s.row_scope,
            s.row_id DESC
    )
    INSERT INTO rep_warehouse.fact_observed_kpi
        (kpi_id, geography_id, year, year_date_id,
         disaggregation_level_one, disaggregation_level_two, value_type, row_scope,
         value, updated_date,
         lin_is_current, lin_change_type,
         lin_source_system, lin_source_file, lin_load_batch_id, lin_source_row_number)
    SELECT
        dk.id,
        dg.id,
        s.year,
        dd.id,
        s.disaggregation_level_one,
        s.disaggregation_level_two,
        s.value_type,
        s.row_scope,
        s.value,
        NULLIF(s.updated_date, '')::date,
        true,
        'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        s.row_id
    FROM deduped s
    INNER JOIN rep_warehouse.dim_kpi dk
           ON dk.source_kpi_id = s.kpi_id AND dk.scd_is_current = true
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
         status, uploaded_by, source_file)
    VALUES
        (p_batch_id, p_year, v_row_count, v_rows_loaded, 0, v_rows_dup,
         'SUCCESS', p_uploaded_by, p_source_file);

    RETURN jsonb_build_object(
        'status',                 'SUCCESS',
        'batch_id',               p_batch_id,
        'year',                   p_year,
        'total_staged',           v_total_staged,
        'rows_loaded',            v_rows_loaded,
        'rows_unmatched_kpi',     0,
        'rows_skipped_duplicate', v_rows_dup
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


-- ── 4. kpi_upload_level_one: remove etl_load_dim_kpi call, add KPI pre-check ─

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_upload_level_one(
    p_batch_id    TEXT,
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
    v_total_rows        INTEGER := 0;
    v_rows_updated      INTEGER := 0;
    v_rows_added        INTEGER := 0;
    v_missing_countries TEXT;
    v_missing_kpis      TEXT;
BEGIN
    PERFORM set_config('app.batch_id',      p_batch_id,        true);
    PERFORM set_config('app.source_system', 'Excel_CAMFED',    true);
    PERFORM set_config('app.source_file',   p_source_file,     true);

    -- Geography pre-check against the current batch only
    SELECT STRING_AGG(DISTINCT TRIM(s.country), ', ' ORDER BY TRIM(s.country))
    INTO v_missing_countries
    FROM rep_raw.level_one_kpis s
    WHERE s.batch_id  = p_batch_id
      AND s.country  IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_geography g
          WHERE g.country = TRIM(s.country) AND g.province IS NULL AND g.district IS NULL
      );

    IF v_missing_countries IS NOT NULL THEN
        INSERT INTO rep_raw.level_one_upload_log
            (batch_id, rows_added, rows_updated, total_rows, status, error_msg, uploaded_by, source_file)
        VALUES
            (p_batch_id, 0, 0, 0, 'FAILED',
             'Countries not found in geography dimension (run Salesforce ingest first): ' || v_missing_countries,
             p_uploaded_by, p_source_file);

        RETURN jsonb_build_object(
            'status', 'FAILED',
            'error',  'Countries not found in geography dimension (run Salesforce ingest first): ' || v_missing_countries
        );
    END IF;

    -- KPI pre-check: every kpi value must exist in dim_kpi.
    SELECT STRING_AGG(DISTINCT TRIM(s.kpi), ', ' ORDER BY TRIM(s.kpi))
    INTO v_missing_kpis
    FROM rep_raw.level_one_kpis s
    WHERE s.batch_id = p_batch_id
      AND s.kpi IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_kpi dk
          WHERE dk.source_kpi_id = TRIM(s.kpi) AND dk.scd_is_current = true
      );

    IF v_missing_kpis IS NOT NULL THEN
        INSERT INTO rep_raw.level_one_upload_log
            (batch_id, rows_added, rows_updated, total_rows, status, error_msg, uploaded_by, source_file)
        VALUES
            (p_batch_id, 0, 0, 0, 'FAILED',
             'KPI IDs not found in definitions (upload kpi-definitions.xlsx first): ' || v_missing_kpis,
             p_uploaded_by, p_source_file);

        RETURN jsonb_build_object(
            'status', 'FAILED',
            'error',  'KPI IDs not found in definitions (upload kpi-definitions.xlsx first): ' || v_missing_kpis
        );
    END IF;

    -- Rebuild level_one staging from all raw rows
    PERFORM rep_warehouse.etl_stage_level_one_kpis();

    -- Count distinct rows in this batch (dedup by upsert key)
    SELECT COUNT(*) INTO v_total_rows
    FROM (
        SELECT DISTINCT ON (
            s.year::smallint,
            COALESCE(dg.id,                          -1),
            COALESCE(TRIM(s.school_level),           ''),
            COALESCE(TRIM(s.annual_newly_supported), ''),
            COALESCE(TRIM(s.type),                   ''),
            COALESCE(TRIM(s.gender),                 '')
        ) s.row_id
        FROM rep_raw.level_one_kpis s
        LEFT JOIN rep_warehouse.dim_geography dg
               ON dg.country = TRIM(s.country) AND dg.province IS NULL AND dg.district IS NULL
        WHERE s.batch_id = p_batch_id
          AND s.year    IS NOT NULL
          AND s.country IS NOT NULL
          AND s.kpi     IS NOT NULL
        ORDER BY
            s.year::smallint,
            COALESCE(dg.id,                          -1),
            COALESCE(TRIM(s.school_level),           ''),
            COALESCE(TRIM(s.annual_newly_supported), ''),
            COALESCE(TRIM(s.type),                   ''),
            COALESCE(TRIM(s.gender),                 ''),
            s.row_id DESC
    ) _t;

    -- Count rows that already exist in the warehouse (will be updated)
    SELECT COUNT(*) INTO v_rows_updated
    FROM (
        SELECT DISTINCT ON (
            s.year::smallint,
            COALESCE(dg.id,                          -1),
            COALESCE(TRIM(s.school_level),           ''),
            COALESCE(TRIM(s.annual_newly_supported), ''),
            COALESCE(TRIM(s.type),                   ''),
            COALESCE(TRIM(s.gender),                 '')
        )
            s.year::smallint                  AS year,
            dg.id                             AS geography_id,
            TRIM(s.school_level)              AS school_level,
            TRIM(s.annual_newly_supported)    AS annual_newly_supported,
            TRIM(s.type)                      AS fund_type,
            TRIM(s.gender)                    AS gender
        FROM rep_raw.level_one_kpis s
        LEFT JOIN rep_warehouse.dim_geography dg
               ON dg.country = TRIM(s.country) AND dg.province IS NULL AND dg.district IS NULL
        WHERE s.batch_id = p_batch_id
          AND s.year IS NOT NULL AND s.country IS NOT NULL AND s.kpi IS NOT NULL
        ORDER BY
            s.year::smallint,
            COALESCE(dg.id,                          -1),
            COALESCE(TRIM(s.school_level),           ''),
            COALESCE(TRIM(s.annual_newly_supported), ''),
            COALESCE(TRIM(s.type),                   ''),
            COALESCE(TRIM(s.gender),                 ''),
            s.row_id DESC
    ) deduped
    WHERE EXISTS (
        SELECT 1 FROM rep_warehouse.fact_level_one_kpis f
        WHERE f.year                                    = deduped.year
          AND COALESCE(f.geography_id,            -1)  = COALESCE(deduped.geography_id,            -1)
          AND COALESCE(f.school_level,            '')  = COALESCE(deduped.school_level,            '')
          AND COALESCE(f.annual_newly_supported,  '')  = COALESCE(deduped.annual_newly_supported,  '')
          AND COALESCE(f.fund_type,               '')  = COALESCE(deduped.fund_type,               '')
          AND COALESCE(f.gender,                  '')  = COALESCE(deduped.gender,                  '')
    );

    v_rows_added := v_total_rows - v_rows_updated;

    -- Upsert into fact table
    WITH deduped AS (
        SELECT DISTINCT ON (
            s.year::smallint,
            COALESCE(dg.id,                          -1),
            COALESCE(TRIM(s.school_level),           ''),
            COALESCE(TRIM(s.annual_newly_supported), ''),
            COALESCE(TRIM(s.type),                   ''),
            COALESCE(TRIM(s.gender),                 '')
        )
            s.row_id,
            s.year::smallint                  AS year,
            TRIM(s.kpi)                       AS kpi,
            TRIM(s.school_level)              AS school_level,
            TRIM(s.annual_newly_supported)    AS annual_newly_supported,
            TRIM(s.type)                      AS fund_type,
            TRIM(s.gender)                    AS gender,
            TRIM(s.disaggregation_gender)     AS disaggregation_gender,
            CASE
                WHEN REPLACE(s.value::TEXT, ',', '') ~ '^-?[0-9]*\.?[0-9]+([eE][+-]?[0-9]+)?$'
                THEN REPLACE(s.value::TEXT, ',', '')::NUMERIC
            END                               AS value,
            dg.id                             AS geography_id
        FROM rep_raw.level_one_kpis s
        LEFT JOIN rep_warehouse.dim_geography dg
               ON dg.country = TRIM(s.country) AND dg.province IS NULL AND dg.district IS NULL
        WHERE s.batch_id = p_batch_id
          AND s.year IS NOT NULL AND s.country IS NOT NULL AND s.kpi IS NOT NULL
        ORDER BY
            s.year::smallint,
            COALESCE(dg.id,                          -1),
            COALESCE(TRIM(s.school_level),           ''),
            COALESCE(TRIM(s.annual_newly_supported), ''),
            COALESCE(TRIM(s.type),                   ''),
            COALESCE(TRIM(s.gender),                 ''),
            s.row_id DESC
    )
    INSERT INTO rep_warehouse.fact_level_one_kpis
        (kpi_id, geography_id, year_date_id, year,
         school_level, annual_newly_supported, fund_type, gender, disaggregation_gender,
         value,
         lin_is_current, lin_change_type,
         lin_source_system, lin_source_file, lin_load_batch_id, lin_source_row_number)
    SELECT
        dk.id,
        s.geography_id,
        dd.id,
        s.year,
        s.school_level, s.annual_newly_supported, s.fund_type, s.gender, s.disaggregation_gender,
        s.value,
        true,
        'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        s.row_id
    FROM deduped s
    INNER JOIN rep_warehouse.dim_kpi dk
           ON dk.source_kpi_id = s.kpi AND dk.scd_is_current = true
    LEFT  JOIN rep_warehouse.dim_date dd
           ON dd.id = ((s.year::text || '0101')::integer)
    ON CONFLICT (
        year,
        COALESCE(geography_id,            -1),
        COALESCE(school_level,            ''),
        COALESCE(annual_newly_supported,  ''),
        COALESCE(fund_type,               ''),
        COALESCE(gender,                  '')
    )
    DO UPDATE SET
        kpi_id                = EXCLUDED.kpi_id,
        disaggregation_gender = EXCLUDED.disaggregation_gender,
        value                 = EXCLUDED.value,
        lin_is_current        = true,
        lin_change_type       = 'UPDATE',
        lin_source_system     = EXCLUDED.lin_source_system,
        lin_source_file       = EXCLUDED.lin_source_file,
        lin_load_batch_id     = EXCLUDED.lin_load_batch_id,
        lin_source_row_number = EXCLUDED.lin_source_row_number;

    INSERT INTO rep_raw.level_one_upload_log
        (batch_id, rows_added, rows_updated, total_rows, status, uploaded_by, source_file)
    VALUES
        (p_batch_id, v_rows_added, v_rows_updated, v_total_rows,
         'SUCCESS', p_uploaded_by, p_source_file);

    RETURN jsonb_build_object(
        'status',       'SUCCESS',
        'batch_id',     p_batch_id,
        'rows_added',   v_rows_added,
        'rows_updated', v_rows_updated,
        'total_rows',   v_total_rows,
        'message',      format('Loaded %s rows: %s added, %s updated',
                               v_total_rows, v_rows_added, v_rows_updated)
    );

EXCEPTION WHEN OTHERS THEN
    INSERT INTO rep_raw.level_one_upload_log
        (batch_id, rows_added, rows_updated, total_rows, status, error_msg, uploaded_by, source_file)
    VALUES
        (p_batch_id, 0, 0, 0, 'FAILED', SQLERRM, p_uploaded_by, p_source_file);

    RETURN jsonb_build_object('status', 'FAILED', 'error', SQLERRM);
END;
$$;


-- ===== 20260605091206_kpi_definitions_load_grant_service_role.sql =====
GRANT EXECUTE ON FUNCTION rep_warehouse.kpi_definitions_load(TEXT, JSONB, TEXT, TEXT) TO service_role;


-- ===== 20260605092604_get_kpi_definitions_summary.sql =====
CREATE OR REPLACE FUNCTION rep_portal.get_kpi_definitions_summary()
RETURNS JSON
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT json_build_object(
    'total',            COUNT(*),
    'last_loaded_at',   MAX(lin_inserted_at),
    'last_source_file', (
      SELECT lin_source_file
      FROM   rep_warehouse.dim_kpi
      WHERE  scd_is_current = true
      ORDER  BY lin_inserted_at DESC
      LIMIT  1
    )
  )
  FROM rep_warehouse.dim_kpi
  WHERE scd_is_current = true;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.get_kpi_definitions_summary() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_kpi_definitions_summary() TO authenticated;


-- ===== 20260605093502_kpi_definitions_load_simple_update.sql =====
-- Simplify kpi_definitions_load: source_kpi_id is the sole key.
-- Any change to any other field (kpi_group, indicator, indicator_frequency,
-- indicator_start, definition) does a plain in-place UPDATE — no SCD2 churn.

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
         WHERE source_kpi_id = v_src_id AND scd_is_current = true
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
               SET kpi_group           = v_group,
                   indicator           = v_indicator,
                   indicator_frequency = v_freq,
                   indicator_start     = v_start,
                   definition          = v_defn,
                   lin_business_hash   = v_new_hash,
                   lin_load_batch_id   = p_batch_id,
                   lin_source_file     = p_source_file
             WHERE source_kpi_id = v_src_id AND scd_is_current = true;

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


-- ===== 20260605100950_fix_kpi_upload_precheck_scope.sql =====
-- Fix KPI pre-check in kpi_upload_all to scope against the current batch's
-- raw rows rather than rep_staging.all_kpis.  Staging rebuilds from ALL rows
-- in rep_raw.all_kpis, so stale rows from previous failed uploads for the same
-- year would cause false "KPI not found" failures.

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

    -- Rebuild all_kpis staging from all raw rows
    PERFORM rep_warehouse.etl_stage_all_kpis();

    -- Geography pre-check
    SELECT STRING_AGG(DISTINCT s.country, ', ' ORDER BY s.country)
    INTO v_missing_countries
    FROM rep_staging.all_kpis s
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

    -- KPI pre-check: scope to this batch's raw rows only so stale rows from
    -- previous failed uploads for the same year don't cause false failures.
    SELECT STRING_AGG(DISTINCT r.kpi_no, ', ' ORDER BY r.kpi_no)
    INTO v_missing_kpis
    FROM rep_raw.all_kpis r
    WHERE r.batch_id = p_batch_id
      AND r.kpi_no IS NOT NULL
      AND r.year_of_kpis IS NOT NULL
      AND r.year_of_kpis::integer = p_year
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_kpi dk
          WHERE dk.source_kpi_id = r.kpi_no AND dk.scd_is_current = true
      );

    IF v_missing_kpis IS NOT NULL THEN
        INSERT INTO rep_raw.upload_log
            (batch_id, year, row_count, rows_loaded, rows_unmatched, rows_duplicate,
             status, error_msg, uploaded_by, source_file)
        VALUES
            (p_batch_id, p_year, v_row_count, 0, 0, 0, 'FAILED',
             'KPI IDs not found in definitions (upload kpi-definitions.xlsx first): ' || v_missing_kpis,
             p_uploaded_by, p_source_file);

        RETURN jsonb_build_object(
            'status', 'FAILED',
            'error',  'KPI IDs not found in definitions (upload kpi-definitions.xlsx first): ' || v_missing_kpis
        );
    END IF;

    SELECT COUNT(*) INTO v_total_staged
    FROM rep_staging.all_kpis
    WHERE year = p_year;

    -- Log duplicate fact-key combinations within this upload
    WITH deduped_rows AS (
        SELECT DISTINCT
            kpi_id, kpi_group, year,
            disaggregation_level_one, disaggregation_level_two,
            row_scope, row_id
        FROM rep_staging.all_kpis
        WHERE year = p_year
    )
    INSERT INTO rep_raw.duplicate_rows
        (batch_id, kpi_id, kpi_group, year,
         disaggregation_level_one, disaggregation_level_two,
         row_scope, occurrences, row_ids)
    SELECT
        p_batch_id,
        kpi_id, kpi_group, year,
        disaggregation_level_one, disaggregation_level_two,
        row_scope,
        COUNT(*),
        array_agg(row_id::text ORDER BY row_id::integer)
    FROM deduped_rows
    GROUP BY kpi_id, kpi_group, year,
             disaggregation_level_one, disaggregation_level_two, row_scope
    HAVING COUNT(*) > 1;

    -- Year-scoped replace
    DELETE FROM rep_warehouse.fact_observed_kpi WHERE year = p_year;

    WITH deduped AS (
        SELECT DISTINCT ON (
            s.year, s.country, s.kpi_id, s.kpi_group,
            s.disaggregation_level_one, s.disaggregation_level_two, s.row_scope
        )
            s.row_id, s.year, s.country, s.kpi_id,
            s.disaggregation_level_one, s.disaggregation_level_two,
            s.value_type, s.row_scope, s.value, s.updated_date
        FROM rep_staging.all_kpis s
        WHERE s.year = p_year
        ORDER BY
            s.year, s.country, s.kpi_id, s.kpi_group,
            s.disaggregation_level_one, s.disaggregation_level_two, s.row_scope,
            s.row_id DESC
    )
    INSERT INTO rep_warehouse.fact_observed_kpi
        (kpi_id, geography_id, year, year_date_id,
         disaggregation_level_one, disaggregation_level_two, value_type, row_scope,
         value, updated_date,
         lin_is_current, lin_change_type,
         lin_source_system, lin_source_file, lin_load_batch_id, lin_source_row_number)
    SELECT
        dk.id,
        dg.id,
        s.year,
        dd.id,
        s.disaggregation_level_one,
        s.disaggregation_level_two,
        s.value_type,
        s.row_scope,
        s.value,
        NULLIF(s.updated_date, '')::date,
        true,
        'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        s.row_id
    FROM deduped s
    INNER JOIN rep_warehouse.dim_kpi dk
           ON dk.source_kpi_id = s.kpi_id AND dk.scd_is_current = true
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
         status, uploaded_by, source_file)
    VALUES
        (p_batch_id, p_year, v_row_count, v_rows_loaded, 0, v_rows_dup,
         'SUCCESS', p_uploaded_by, p_source_file);

    RETURN jsonb_build_object(
        'status',                 'SUCCESS',
        'batch_id',               p_batch_id,
        'year',                   p_year,
        'total_staged',           v_total_staged,
        'rows_loaded',            v_rows_loaded,
        'rows_unmatched_kpi',     0,
        'rows_skipped_duplicate', v_rows_dup
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


-- ===== 20260605102343_fix_kpi_duplicate_check_batch_scope.sql =====
-- Scope duplicate-row detection to the current batch only.
-- rep_staging.all_kpis is rebuilt from ALL raw rows, so without scoping the
-- dedup check would flag collisions across different upload batches/years.
-- Fix: join staging back to rep_raw.all_kpis on row_id + batch_id so only
-- rows from this upload are considered.

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

    -- Rebuild all_kpis staging from all raw rows
    PERFORM rep_warehouse.etl_stage_all_kpis();

    -- Geography pre-check (batch-scoped via raw rows)
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

    -- KPI pre-check (batch-scoped via raw rows)
    SELECT STRING_AGG(DISTINCT r.kpi_no, ', ' ORDER BY r.kpi_no)
    INTO v_missing_kpis
    FROM rep_raw.all_kpis r
    WHERE r.batch_id = p_batch_id
      AND r.kpi_no IS NOT NULL
      AND r.year_of_kpis IS NOT NULL
      AND r.year_of_kpis::integer = p_year
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_kpi dk
          WHERE dk.source_kpi_id = r.kpi_no AND dk.scd_is_current = true
      );

    IF v_missing_kpis IS NOT NULL THEN
        INSERT INTO rep_raw.upload_log
            (batch_id, year, row_count, rows_loaded, rows_unmatched, rows_duplicate,
             status, error_msg, uploaded_by, source_file)
        VALUES
            (p_batch_id, p_year, v_row_count, 0, 0, 0, 'FAILED',
             'KPI IDs not found in definitions (upload kpi-definitions.xlsx first): ' || v_missing_kpis,
             p_uploaded_by, p_source_file);

        RETURN jsonb_build_object(
            'status', 'FAILED',
            'error',  'KPI IDs not found in definitions (upload kpi-definitions.xlsx first): ' || v_missing_kpis
        );
    END IF;

    SELECT COUNT(*) INTO v_total_staged
    FROM rep_staging.all_kpis s
    INNER JOIN rep_raw.all_kpis r ON r.row_id = s.row_id AND r.batch_id = p_batch_id
    WHERE s.year = p_year;

    -- Duplicate detection: scoped to this batch only via row_id → batch_id join
    WITH batch_staged AS (
        SELECT s.*
        FROM rep_staging.all_kpis s
        INNER JOIN rep_raw.all_kpis r ON r.row_id = s.row_id AND r.batch_id = p_batch_id
        WHERE s.year = p_year
    ),
    deduped_rows AS (
        SELECT DISTINCT
            kpi_id, kpi_group, year,
            disaggregation_level_one, disaggregation_level_two,
            row_scope, row_id
        FROM batch_staged
    )
    INSERT INTO rep_raw.duplicate_rows
        (batch_id, kpi_id, kpi_group, year,
         disaggregation_level_one, disaggregation_level_two,
         row_scope, occurrences, row_ids)
    SELECT
        p_batch_id,
        kpi_id, kpi_group, year,
        disaggregation_level_one, disaggregation_level_two,
        row_scope,
        COUNT(*),
        array_agg(row_id::text ORDER BY row_id::integer)
    FROM deduped_rows
    GROUP BY kpi_id, kpi_group, year,
             disaggregation_level_one, disaggregation_level_two, row_scope
    HAVING COUNT(*) > 1;

    -- Year-scoped replace: only current batch's rows are loaded into facts.
    -- The INNER JOIN on dim_kpi and dim_geography guarantees non-null FKs.
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
            s.row_id, s.year, s.country, s.kpi_id,
            s.disaggregation_level_one, s.disaggregation_level_two,
            s.value_type, s.row_scope, s.value, s.updated_date
        FROM batch_staged s
        ORDER BY
            s.year, s.country, s.kpi_id, s.kpi_group,
            s.disaggregation_level_one, s.disaggregation_level_two, s.row_scope,
            s.row_id DESC
    )
    INSERT INTO rep_warehouse.fact_observed_kpi
        (kpi_id, geography_id, year, year_date_id,
         disaggregation_level_one, disaggregation_level_two, value_type, row_scope,
         value, updated_date,
         lin_is_current, lin_change_type,
         lin_source_system, lin_source_file, lin_load_batch_id, lin_source_row_number)
    SELECT
        dk.id,
        dg.id,
        s.year,
        dd.id,
        s.disaggregation_level_one,
        s.disaggregation_level_two,
        s.value_type,
        s.row_scope,
        s.value,
        NULLIF(s.updated_date, '')::date,
        true,
        'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        s.row_id
    FROM deduped s
    INNER JOIN rep_warehouse.dim_kpi dk
           ON dk.source_kpi_id = s.kpi_id AND dk.scd_is_current = true
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
         status, uploaded_by, source_file)
    VALUES
        (p_batch_id, p_year, v_row_count, v_rows_loaded, 0, v_rows_dup,
         'SUCCESS', p_uploaded_by, p_source_file);

    RETURN jsonb_build_object(
        'status',                 'SUCCESS',
        'batch_id',               p_batch_id,
        'year',                   p_year,
        'total_staged',           v_total_staged,
        'rows_loaded',            v_rows_loaded,
        'rows_unmatched_kpi',     0,
        'rows_skipped_duplicate', v_rows_dup
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


-- ===== 20260605104800_fix_kpi_duplicate_detection_full_row.sql =====
-- Fix duplicate detection in kpi_upload_all to require an exact match on ALL
-- data columns, not just the key subset.  The previous approach grouped by
-- (kpi_id, kpi_group, year, disagg1, disagg2, row_scope) which flagged rows
-- with the same KPI/disagg but different country values as false positives.
--
-- Fix: check at rep_raw.all_kpis level (before country unpivoting) and group
-- by every data column including all country value columns.

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

    -- KPI pre-check (batch-scoped)
    SELECT STRING_AGG(DISTINCT r.kpi_no, ', ' ORDER BY r.kpi_no)
    INTO v_missing_kpis
    FROM rep_raw.all_kpis r
    WHERE r.batch_id = p_batch_id
      AND r.kpi_no IS NOT NULL
      AND r.year_of_kpis IS NOT NULL
      AND r.year_of_kpis::integer = p_year
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_kpi dk
          WHERE dk.source_kpi_id = r.kpi_no AND dk.scd_is_current = true
      );

    IF v_missing_kpis IS NOT NULL THEN
        INSERT INTO rep_raw.upload_log
            (batch_id, year, row_count, rows_loaded, rows_unmatched, rows_duplicate,
             status, error_msg, uploaded_by, source_file)
        VALUES
            (p_batch_id, p_year, v_row_count, 0, 0, 0, 'FAILED',
             'KPI IDs not found in definitions (upload kpi-definitions.xlsx first): ' || v_missing_kpis,
             p_uploaded_by, p_source_file);

        RETURN jsonb_build_object(
            'status', 'FAILED',
            'error',  'KPI IDs not found in definitions (upload kpi-definitions.xlsx first): ' || v_missing_kpis
        );
    END IF;

    SELECT COUNT(*) INTO v_total_staged
    FROM rep_staging.all_kpis s
    INNER JOIN rep_raw.all_kpis r ON r.row_id = s.row_id AND r.batch_id = p_batch_id
    WHERE s.year = p_year;

    -- Duplicate detection: exact match on ALL data columns in the raw row.
    -- Grouping by every value column ensures rows with the same KPI/disagg but
    -- different country values are not false positives.
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
        value_type, year_of_kpis, updated_date,
        ghana, malawi, tanzania, zambia, zimbabwe, total
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
            s.row_id, s.year, s.country, s.kpi_id,
            s.disaggregation_level_one, s.disaggregation_level_two,
            s.value_type, s.row_scope, s.value, s.updated_date
        FROM batch_staged s
        ORDER BY
            s.year, s.country, s.kpi_id, s.kpi_group,
            s.disaggregation_level_one, s.disaggregation_level_two, s.row_scope,
            s.row_id DESC
    )
    INSERT INTO rep_warehouse.fact_observed_kpi
        (kpi_id, geography_id, year, year_date_id,
         disaggregation_level_one, disaggregation_level_two, value_type, row_scope,
         value, updated_date,
         lin_is_current, lin_change_type,
         lin_source_system, lin_source_file, lin_load_batch_id, lin_source_row_number)
    SELECT
        dk.id, dg.id, s.year, dd.id,
        s.disaggregation_level_one, s.disaggregation_level_two,
        s.value_type, s.row_scope, s.value,
        NULLIF(s.updated_date, '')::date,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        s.row_id
    FROM deduped s
    INNER JOIN rep_warehouse.dim_kpi dk
           ON dk.source_kpi_id = s.kpi_id AND dk.scd_is_current = true
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
         status, uploaded_by, source_file)
    VALUES
        (p_batch_id, p_year, v_row_count, v_rows_loaded, 0, v_rows_dup,
         'SUCCESS', p_uploaded_by, p_source_file);

    RETURN jsonb_build_object(
        'status',                 'SUCCESS',
        'batch_id',               p_batch_id,
        'year',                   p_year,
        'total_staged',           v_total_staged,
        'rows_loaded',            v_rows_loaded,
        'rows_unmatched_kpi',     0,
        'rows_skipped_duplicate', v_rows_dup
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


-- ===== 20260605120648_all_kpis_add_update_quarter.sql =====
ALTER TABLE rep_raw.all_kpis
    ADD COLUMN IF NOT EXISTS update_quarter TEXT;


-- ===== 20260605121953_add_update_quarter_to_fact_observed_kpi.sql =====
-- Add update_quarter to fact_observed_kpi and carry it through the staging ETL.

ALTER TABLE rep_warehouse.fact_observed_kpi
    ADD COLUMN IF NOT EXISTS update_quarter TEXT;

-- Rebuild etl_stage_all_kpis to include update_quarter in each UNION ALL branch.
CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_all_kpis()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.all_kpis;
    CREATE TABLE rep_staging.all_kpis AS
    SELECT
        row_id,
        kpi_no::text                    AS kpi_id,
        indicator_group                 AS kpi_group,
        indicator,
        disaggregation1                 AS disaggregation_level_one,
        disaggregation2                 AS disaggregation_level_two,
        updated_date,
        update_quarter,
        year_of_kpis::smallint          AS year,
        value_type,
        CASE
            WHEN disaggregation1 ILIKE '%cumulative%'
              OR disaggregation2 ILIKE '%cumulative%'                       THEN 'CUMULATIVE'
            WHEN disaggregation2 ILIKE 'benchmark'
              OR disaggregation2 ILIKE '%poverty line%'                     THEN 'BENCHMARK'
            WHEN disaggregation1 = 'Total'
              OR disaggregation2 = 'Total'
              OR disaggregation2 ILIKE '%total'
              OR disaggregation2 ILIKE 'overall'
              OR disaggregation2 ILIKE 'combined'
              OR disaggregation2 ILIKE '%total%'                            THEN 'SUBTOTAL'
            WHEN disaggregation1 IN ('Annual','Newly supported','Newly reached',
                                     'New since last year','Annual reach per LG')
              OR disaggregation2 = 'Annual'                                 THEN 'ANNUAL'
            ELSE                                                                  'DETAIL'
        END                             AS row_scope,
        'Ghana'                         AS country,
        ghana::text                     AS value
    FROM rep_raw.all_kpis WHERE year_of_kpis IS NOT NULL AND ghana IS NOT NULL
    UNION ALL
    SELECT row_id, kpi_no::text, indicator_group, indicator, disaggregation1, disaggregation2,
           updated_date, update_quarter, year_of_kpis::smallint, value_type,
           CASE
               WHEN disaggregation1 ILIKE '%cumulative%' OR disaggregation2 ILIKE '%cumulative%' THEN 'CUMULATIVE'
               WHEN disaggregation2 ILIKE 'benchmark' OR disaggregation2 ILIKE '%poverty line%'  THEN 'BENCHMARK'
               WHEN disaggregation1 = 'Total' OR disaggregation2 = 'Total'
                 OR disaggregation2 ILIKE '%total' OR disaggregation2 ILIKE 'overall'
                 OR disaggregation2 ILIKE 'combined' OR disaggregation2 ILIKE '%total%'           THEN 'SUBTOTAL'
               WHEN disaggregation1 IN ('Annual','Newly supported','Newly reached',
                                        'New since last year','Annual reach per LG')
                 OR disaggregation2 = 'Annual'                                                    THEN 'ANNUAL'
               ELSE 'DETAIL'
           END,
           'Malawi', malawi::text
    FROM rep_raw.all_kpis WHERE year_of_kpis IS NOT NULL AND malawi IS NOT NULL
    UNION ALL
    SELECT row_id, kpi_no::text, indicator_group, indicator, disaggregation1, disaggregation2,
           updated_date, update_quarter, year_of_kpis::smallint, value_type,
           CASE
               WHEN disaggregation1 ILIKE '%cumulative%' OR disaggregation2 ILIKE '%cumulative%' THEN 'CUMULATIVE'
               WHEN disaggregation2 ILIKE 'benchmark' OR disaggregation2 ILIKE '%poverty line%'  THEN 'BENCHMARK'
               WHEN disaggregation1 = 'Total' OR disaggregation2 = 'Total'
                 OR disaggregation2 ILIKE '%total' OR disaggregation2 ILIKE 'overall'
                 OR disaggregation2 ILIKE 'combined' OR disaggregation2 ILIKE '%total%'           THEN 'SUBTOTAL'
               WHEN disaggregation1 IN ('Annual','Newly supported','Newly reached',
                                        'New since last year','Annual reach per LG')
                 OR disaggregation2 = 'Annual'                                                    THEN 'ANNUAL'
               ELSE 'DETAIL'
           END,
           'Tanzania', tanzania::text
    FROM rep_raw.all_kpis WHERE year_of_kpis IS NOT NULL AND tanzania IS NOT NULL
    UNION ALL
    SELECT row_id, kpi_no::text, indicator_group, indicator, disaggregation1, disaggregation2,
           updated_date, update_quarter, year_of_kpis::smallint, value_type,
           CASE
               WHEN disaggregation1 ILIKE '%cumulative%' OR disaggregation2 ILIKE '%cumulative%' THEN 'CUMULATIVE'
               WHEN disaggregation2 ILIKE 'benchmark' OR disaggregation2 ILIKE '%poverty line%'  THEN 'BENCHMARK'
               WHEN disaggregation1 = 'Total' OR disaggregation2 = 'Total'
                 OR disaggregation2 ILIKE '%total' OR disaggregation2 ILIKE 'overall'
                 OR disaggregation2 ILIKE 'combined' OR disaggregation2 ILIKE '%total%'           THEN 'SUBTOTAL'
               WHEN disaggregation1 IN ('Annual','Newly supported','Newly reached',
                                        'New since last year','Annual reach per LG')
                 OR disaggregation2 = 'Annual'                                                    THEN 'ANNUAL'
               ELSE 'DETAIL'
           END,
           'Zambia', zambia::text
    FROM rep_raw.all_kpis WHERE year_of_kpis IS NOT NULL AND zambia IS NOT NULL
    UNION ALL
    SELECT row_id, kpi_no::text, indicator_group, indicator, disaggregation1, disaggregation2,
           updated_date, update_quarter, year_of_kpis::smallint, value_type,
           CASE
               WHEN disaggregation1 ILIKE '%cumulative%' OR disaggregation2 ILIKE '%cumulative%' THEN 'CUMULATIVE'
               WHEN disaggregation2 ILIKE 'benchmark' OR disaggregation2 ILIKE '%poverty line%'  THEN 'BENCHMARK'
               WHEN disaggregation1 = 'Total' OR disaggregation2 = 'Total'
                 OR disaggregation2 ILIKE '%total' OR disaggregation2 ILIKE 'overall'
                 OR disaggregation2 ILIKE 'combined' OR disaggregation2 ILIKE '%total%'           THEN 'SUBTOTAL'
               WHEN disaggregation1 IN ('Annual','Newly supported','Newly reached',
                                        'New since last year','Annual reach per LG')
                 OR disaggregation2 = 'Annual'                                                    THEN 'ANNUAL'
               ELSE 'DETAIL'
           END,
           'Zimbabwe', zimbabwe::text
    FROM rep_raw.all_kpis WHERE year_of_kpis IS NOT NULL AND zimbabwe IS NOT NULL
    UNION ALL
    SELECT row_id, kpi_no::text, indicator_group, indicator, disaggregation1, disaggregation2,
           updated_date, update_quarter, year_of_kpis::smallint, value_type,
           CASE
               WHEN disaggregation1 ILIKE '%cumulative%' OR disaggregation2 ILIKE '%cumulative%' THEN 'CUMULATIVE'
               WHEN disaggregation2 ILIKE 'benchmark' OR disaggregation2 ILIKE '%poverty line%'  THEN 'BENCHMARK'
               WHEN disaggregation1 = 'Total' OR disaggregation2 = 'Total'
                 OR disaggregation2 ILIKE '%total' OR disaggregation2 ILIKE 'overall'
                 OR disaggregation2 ILIKE 'combined' OR disaggregation2 ILIKE '%total%'           THEN 'SUBTOTAL'
               WHEN disaggregation1 IN ('Annual','Newly supported','Newly reached',
                                        'New since last year','Annual reach per LG')
                 OR disaggregation2 = 'Annual'                                                    THEN 'ANNUAL'
               ELSE 'DETAIL'
           END,
           'Total', total::text
    FROM rep_raw.all_kpis WHERE year_of_kpis IS NOT NULL AND total IS NOT NULL;
END;
$$;

-- Rewrite kpi_upload_all to include update_quarter in the fact INSERT.
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

    -- KPI pre-check (batch-scoped)
    SELECT STRING_AGG(DISTINCT r.kpi_no, ', ' ORDER BY r.kpi_no)
    INTO v_missing_kpis
    FROM rep_raw.all_kpis r
    WHERE r.batch_id = p_batch_id
      AND r.kpi_no IS NOT NULL
      AND r.year_of_kpis IS NOT NULL
      AND r.year_of_kpis::integer = p_year
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_kpi dk
          WHERE dk.source_kpi_id = r.kpi_no AND dk.scd_is_current = true
      );

    IF v_missing_kpis IS NOT NULL THEN
        INSERT INTO rep_raw.upload_log
            (batch_id, year, row_count, rows_loaded, rows_unmatched, rows_duplicate,
             status, error_msg, uploaded_by, source_file)
        VALUES
            (p_batch_id, p_year, v_row_count, 0, 0, 0, 'FAILED',
             'KPI IDs not found in definitions (upload kpi-definitions.xlsx first): ' || v_missing_kpis,
             p_uploaded_by, p_source_file);

        RETURN jsonb_build_object(
            'status', 'FAILED',
            'error',  'KPI IDs not found in definitions (upload kpi-definitions.xlsx first): ' || v_missing_kpis
        );
    END IF;

    SELECT COUNT(*) INTO v_total_staged
    FROM rep_staging.all_kpis s
    INNER JOIN rep_raw.all_kpis r ON r.row_id = s.row_id AND r.batch_id = p_batch_id
    WHERE s.year = p_year;

    -- Duplicate detection: exact match on ALL data columns in the raw row.
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
        ghana, malawi, tanzania, zambia, zimbabwe, total
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
            s.row_id, s.year, s.country, s.kpi_id,
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
           ON dk.source_kpi_id = s.kpi_id AND dk.scd_is_current = true
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
         status, uploaded_by, source_file)
    VALUES
        (p_batch_id, p_year, v_row_count, v_rows_loaded, 0, v_rows_dup,
         'SUCCESS', p_uploaded_by, p_source_file);

    RETURN jsonb_build_object(
        'status',                 'SUCCESS',
        'batch_id',               p_batch_id,
        'year',                   p_year,
        'total_staged',           v_total_staged,
        'rows_loaded',            v_rows_loaded,
        'rows_unmatched_kpi',     0,
        'rows_skipped_duplicate', v_rows_dup
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


-- ===== 20260605122614_add_update_quarter_to_upload_log.sql =====
-- Add update_quarter to upload_log so it can be shown on the year card.
-- kpi_upload_all populates it from the batch's raw rows (distinct values, comma-separated).
-- get_loaded_years returns it alongside the existing columns.

ALTER TABLE rep_raw.upload_log
    ADD COLUMN IF NOT EXISTS update_quarter TEXT;

-- Rewrite kpi_upload_all to capture update_quarter from the batch rows.
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

    -- KPI pre-check (batch-scoped)
    SELECT STRING_AGG(DISTINCT r.kpi_no, ', ' ORDER BY r.kpi_no)
    INTO v_missing_kpis
    FROM rep_raw.all_kpis r
    WHERE r.batch_id = p_batch_id
      AND r.kpi_no IS NOT NULL
      AND r.year_of_kpis IS NOT NULL
      AND r.year_of_kpis::integer = p_year
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_kpi dk
          WHERE dk.source_kpi_id = r.kpi_no AND dk.scd_is_current = true
      );

    IF v_missing_kpis IS NOT NULL THEN
        INSERT INTO rep_raw.upload_log
            (batch_id, year, row_count, rows_loaded, rows_unmatched, rows_duplicate,
             status, error_msg, uploaded_by, source_file)
        VALUES
            (p_batch_id, p_year, v_row_count, 0, 0, 0, 'FAILED',
             'KPI IDs not found in definitions (upload kpi-definitions.xlsx first): ' || v_missing_kpis,
             p_uploaded_by, p_source_file);

        RETURN jsonb_build_object(
            'status', 'FAILED',
            'error',  'KPI IDs not found in definitions (upload kpi-definitions.xlsx first): ' || v_missing_kpis
        );
    END IF;

    SELECT COUNT(*) INTO v_total_staged
    FROM rep_staging.all_kpis s
    INNER JOIN rep_raw.all_kpis r ON r.row_id = s.row_id AND r.batch_id = p_batch_id
    WHERE s.year = p_year;

    -- Duplicate detection: exact match on ALL data columns in the raw row.
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
        ghana, malawi, tanzania, zambia, zimbabwe, total
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
            s.row_id, s.year, s.country, s.kpi_id,
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
           ON dk.source_kpi_id = s.kpi_id AND dk.scd_is_current = true
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

-- Rewrite get_loaded_years to return update_quarter.
DROP FUNCTION IF EXISTS rep_portal.get_loaded_years();
CREATE OR REPLACE FUNCTION rep_portal.get_loaded_years()
RETURNS TABLE (
  year           INTEGER,
  rows_loaded    INTEGER,
  rows_duplicate INTEGER,
  uploaded_by    TEXT,
  source_file    TEXT,
  inserted_at    TIMESTAMPTZ,
  update_quarter TEXT
) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_raw, public
AS $$
  SELECT DISTINCT ON (year)
    year, rows_loaded, rows_duplicate, uploaded_by, source_file, inserted_at, update_quarter
  FROM rep_raw.upload_log
  WHERE status = 'SUCCESS'
  ORDER BY year DESC, inserted_at DESC;
$$;


-- ===== 20260605123203_get_kpi_definitions_list.sql =====
CREATE OR REPLACE FUNCTION rep_portal.get_kpi_definitions()
RETURNS TABLE (
  source_kpi_id        TEXT,
  kpi_group            TEXT,
  indicator            TEXT,
  indicator_frequency  TEXT,
  indicator_start      TEXT,
  definition           TEXT
) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public AS $$
  SELECT
    source_kpi_id,
    kpi_group,
    indicator,
    indicator_frequency,
    indicator_start,
    definition
  FROM rep_warehouse.dim_kpi
  WHERE scd_is_current = true
  ORDER BY source_kpi_id;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.get_kpi_definitions() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_kpi_definitions() TO authenticated;


-- ===== 20260605130739_add_new_kpi_columns_to_views.sql =====
-- Add update_quarter (from fact_observed_kpi) and indicator_frequency,
-- indicator_start, definition (from dim_kpi) to view_observed_kpi and all
-- six specialised views that select from it.
-- Must DROP first because PostgreSQL disallows inserting columns mid-list
-- via CREATE OR REPLACE VIEW.

-- Drop specialised views first (no dependents beyond the base view)
DROP VIEW IF EXISTS rep_warehouse.view_kpi_counts;
DROP VIEW IF EXISTS rep_warehouse.view_kpi_percentages;
DROP VIEW IF EXISTS rep_warehouse.view_kpi_targets;
DROP VIEW IF EXISTS rep_warehouse.view_kpi_cumulative;
DROP VIEW IF EXISTS rep_warehouse.view_kpi_detail;
DROP VIEW IF EXISTS rep_warehouse.view_kpi_subtotals;
DROP VIEW IF EXISTS rep_warehouse.view_kpi_benchmarks;
-- CASCADE drops rep_portal.kpi_coverage_data materialized view which depends on this
DROP VIEW IF EXISTS rep_warehouse.view_observed_kpi CASCADE;

CREATE OR REPLACE VIEW rep_warehouse.view_observed_kpi AS
SELECT
    f.id,
    k.source_kpi_id                 AS kpi_id,
    k.kpi_group,
    k.indicator,
    k.indicator_frequency,
    k.indicator_start,
    k.definition,
    f.disaggregation_level_one,
    f.disaggregation_level_two,
    f.row_scope,
    f.lin_source_row_number,
    f.value_type,
    dd.date_value                   AS year_date,
    dd.year                         AS year,
    dd.month                        AS year_month,
    dd.month_name                   AS year_month_name,
    dd.quarter                      AS year_quarter,
    f.value,
    f.updated_date,
    f.update_quarter,
    g.country
FROM rep_warehouse.fact_observed_kpi f
LEFT JOIN rep_warehouse.dim_kpi      k  ON  k.id = f.kpi_id
LEFT JOIN rep_warehouse.dim_geography g  ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = f.year_date_id;


CREATE OR REPLACE VIEW rep_warehouse.view_kpi_counts AS
SELECT
    id, kpi_id, kpi_group, indicator,
    indicator_frequency, indicator_start, definition,
    disaggregation_level_one, disaggregation_level_two,
    row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date, update_quarter,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric END AS value
FROM rep_warehouse.view_observed_kpi
WHERE value_type = 'Count'
  AND row_scope  = 'ANNUAL';

CREATE OR REPLACE VIEW rep_warehouse.view_kpi_percentages AS
SELECT
    id, kpi_id, kpi_group, indicator,
    indicator_frequency, indicator_start, definition,
    disaggregation_level_one, disaggregation_level_two,
    row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date, update_quarter,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric * 100 END AS value_pct
FROM rep_warehouse.view_observed_kpi
WHERE value_type = 'Percentage'
  AND row_scope  = 'ANNUAL';

CREATE OR REPLACE VIEW rep_warehouse.view_kpi_targets AS
SELECT
    id, kpi_id, kpi_group, indicator,
    indicator_frequency, indicator_start, definition,
    disaggregation_level_one, disaggregation_level_two,
    value_type, row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date, update_quarter,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric END AS value
FROM rep_warehouse.view_observed_kpi
WHERE row_scope = 'CUMULATIVE'
  AND disaggregation_level_one = 'Cumulative (2020-2030)';

CREATE OR REPLACE VIEW rep_warehouse.view_kpi_cumulative AS
SELECT
    id, kpi_id, kpi_group, indicator,
    indicator_frequency, indicator_start, definition,
    disaggregation_level_one, disaggregation_level_two,
    value_type, row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date, update_quarter,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric END AS value
FROM rep_warehouse.view_observed_kpi
WHERE row_scope = 'CUMULATIVE'
  AND disaggregation_level_one IN ('Cumulative (all-time)', 'Cumulative');

CREATE OR REPLACE VIEW rep_warehouse.view_kpi_detail AS
SELECT
    id, kpi_id, kpi_group, indicator,
    indicator_frequency, indicator_start, definition,
    disaggregation_level_one, disaggregation_level_two,
    value_type, row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date, update_quarter,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric END AS value
FROM rep_warehouse.view_observed_kpi
WHERE row_scope = 'DETAIL';

CREATE OR REPLACE VIEW rep_warehouse.view_kpi_subtotals AS
SELECT
    id, kpi_id, kpi_group, indicator,
    indicator_frequency, indicator_start, definition,
    disaggregation_level_one, disaggregation_level_two,
    value_type, row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date, update_quarter,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric END AS value
FROM rep_warehouse.view_observed_kpi
WHERE row_scope = 'SUBTOTAL';

CREATE OR REPLACE VIEW rep_warehouse.view_kpi_benchmarks AS
SELECT
    id, kpi_id, kpi_group, indicator,
    indicator_frequency, indicator_start, definition,
    disaggregation_level_one, disaggregation_level_two,
    value_type, row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date, update_quarter,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric END AS value
FROM rep_warehouse.view_observed_kpi
WHERE row_scope = 'BENCHMARK';

-- Recreate kpi_coverage_data materialized view (was dropped via CASCADE above)
CREATE MATERIALIZED VIEW rep_portal.kpi_coverage_data AS
SELECT DISTINCT ON (kpi_id, country, year)
  kpi_id,
  indicator,
  kpi_group,
  country,
  year,
  value,
  row_scope,
  updated_date
FROM rep_warehouse.view_observed_kpi
WHERE country IS NOT NULL
  AND year   IS NOT NULL
ORDER BY
  kpi_id,
  country,
  year,
  CASE row_scope
    WHEN 'SUBTOTAL' THEN 1
    WHEN 'ANNUAL'   THEN 2
    ELSE                 3
  END;

CREATE INDEX ON rep_portal.kpi_coverage_data (kpi_id);
CREATE INDEX ON rep_portal.kpi_coverage_data (country);
CREATE INDEX ON rep_portal.kpi_coverage_data (year);

GRANT SELECT ON rep_portal.kpi_coverage_data TO authenticated, anon, service_role;


-- ===== 20260605133030_refresh_kpi_coverage_with_dashboard_agg.sql =====
-- Refresh kpi_coverage_data alongside dashboard_data_agg.
-- kpi_upload_all, kpi_upload_level_one, and kpi_delete_year all call
-- refresh_dashboard_data_agg() via the refresh-dashboard-agg edge function.
-- Adding kpi_coverage_data here means all three callers refresh it for free.

CREATE OR REPLACE FUNCTION rep_warehouse.refresh_dashboard_data_agg()
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
BEGIN
  REFRESH MATERIALIZED VIEW rep_portal.dashboard_data_agg;
  REFRESH MATERIALIZED VIEW rep_portal.kpi_coverage_data;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.refresh_dashboard_data_agg() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_warehouse.refresh_dashboard_data_agg() TO service_role;


-- ===== 20260606183746_kpi_countries_jsonb.sql =====
-- Replace hardcoded country columns in rep_raw.all_kpis with a JSONB column.
-- This allows new programme countries to be picked up from the xlsx automatically.
-- Total is kept as a separate column (it is an aggregate, not a country).

ALTER TABLE rep_raw.all_kpis
    ADD COLUMN countries JSONB;

ALTER TABLE rep_raw.all_kpis
    DROP COLUMN IF EXISTS ghana,
    DROP COLUMN IF EXISTS malawi,
    DROP COLUMN IF EXISTS tanzania,
    DROP COLUMN IF EXISTS zambia,
    DROP COLUMN IF EXISTS zimbabwe;


-- ===== 20260606183813_kpi_etl_dynamic_countries.sql =====
-- Rewrite etl_stage_all_kpis to unpivot countries dynamically from the JSONB
-- countries column instead of hardcoded UNION ALL branches per country.
-- Also update kpi_upload_all duplicate detection to use countries::text.

CREATE OR REPLACE FUNCTION rep_warehouse.etl_stage_all_kpis()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
SET statement_timeout = 0
AS $$
BEGIN
    DROP TABLE IF EXISTS rep_staging.all_kpis;
    CREATE TABLE rep_staging.all_kpis AS
    SELECT
        ak.row_id,
        ak.kpi_no::text                  AS kpi_id,
        ak.indicator_group               AS kpi_group,
        ak.indicator,
        ak.disaggregation1               AS disaggregation_level_one,
        ak.disaggregation2               AS disaggregation_level_two,
        ak.updated_date,
        ak.update_quarter,
        ak.year_of_kpis::smallint        AS year,
        ak.value_type,
        CASE
            WHEN ak.disaggregation1 ILIKE '%cumulative%'
              OR ak.disaggregation2 ILIKE '%cumulative%'                       THEN 'CUMULATIVE'
            WHEN ak.disaggregation2 ILIKE 'benchmark'
              OR ak.disaggregation2 ILIKE '%poverty line%'                     THEN 'BENCHMARK'
            WHEN ak.disaggregation1 = 'Total'
              OR ak.disaggregation2 = 'Total'
              OR ak.disaggregation2 ILIKE '%total'
              OR ak.disaggregation2 ILIKE 'overall'
              OR ak.disaggregation2 ILIKE 'combined'
              OR ak.disaggregation2 ILIKE '%total%'                            THEN 'SUBTOTAL'
            WHEN ak.disaggregation1 IN ('Annual','Newly supported','Newly reached',
                                         'New since last year','Annual reach per LG')
              OR ak.disaggregation2 = 'Annual'                                 THEN 'ANNUAL'
            ELSE                                                                     'DETAIL'
        END                              AS row_scope,
        kv.key                           AS country,
        kv.value                         AS value
    FROM rep_raw.all_kpis ak
    CROSS JOIN LATERAL jsonb_each_text(COALESCE(ak.countries, '{}')) kv
    WHERE ak.year_of_kpis IS NOT NULL
      AND kv.value IS NOT NULL

    UNION ALL

    -- Total row kept separate (aggregate, not a country)
    SELECT
        ak.row_id,
        ak.kpi_no::text,
        ak.indicator_group,
        ak.indicator,
        ak.disaggregation1,
        ak.disaggregation2,
        ak.updated_date,
        ak.update_quarter,
        ak.year_of_kpis::smallint,
        ak.value_type,
        CASE
            WHEN ak.disaggregation1 ILIKE '%cumulative%'
              OR ak.disaggregation2 ILIKE '%cumulative%'                       THEN 'CUMULATIVE'
            WHEN ak.disaggregation2 ILIKE 'benchmark'
              OR ak.disaggregation2 ILIKE '%poverty line%'                     THEN 'BENCHMARK'
            WHEN ak.disaggregation1 = 'Total'
              OR ak.disaggregation2 = 'Total'
              OR ak.disaggregation2 ILIKE '%total'
              OR ak.disaggregation2 ILIKE 'overall'
              OR ak.disaggregation2 ILIKE 'combined'
              OR ak.disaggregation2 ILIKE '%total%'                            THEN 'SUBTOTAL'
            WHEN ak.disaggregation1 IN ('Annual','Newly supported','Newly reached',
                                         'New since last year','Annual reach per LG')
              OR ak.disaggregation2 = 'Annual'                                 THEN 'ANNUAL'
            ELSE                                                                     'DETAIL'
        END,
        'Total'          AS country,
        ak.total::text   AS value
    FROM rep_raw.all_kpis ak
    WHERE ak.year_of_kpis IS NOT NULL
      AND ak.total IS NOT NULL;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.etl_stage_all_kpis() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_warehouse.etl_stage_all_kpis() TO service_role;


-- Rewrite kpi_upload_all with countries::text in duplicate detection.
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

    -- KPI pre-check (batch-scoped)
    SELECT STRING_AGG(DISTINCT r.kpi_no, ', ' ORDER BY r.kpi_no)
    INTO v_missing_kpis
    FROM rep_raw.all_kpis r
    WHERE r.batch_id = p_batch_id
      AND r.kpi_no IS NOT NULL
      AND r.year_of_kpis IS NOT NULL
      AND r.year_of_kpis::integer = p_year
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_kpi dk
          WHERE dk.source_kpi_id = r.kpi_no AND dk.scd_is_current = true
      );

    IF v_missing_kpis IS NOT NULL THEN
        INSERT INTO rep_raw.upload_log
            (batch_id, year, row_count, rows_loaded, rows_unmatched, rows_duplicate,
             status, error_msg, uploaded_by, source_file)
        VALUES
            (p_batch_id, p_year, v_row_count, 0, 0, 0, 'FAILED',
             'KPI IDs not found in definitions (upload kpi-definitions.xlsx first): ' || v_missing_kpis,
             p_uploaded_by, p_source_file);

        RETURN jsonb_build_object(
            'status', 'FAILED',
            'error',  'KPI IDs not found in definitions (upload kpi-definitions.xlsx first): ' || v_missing_kpis
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
            s.row_id, s.year, s.country, s.kpi_id,
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
           ON dk.source_kpi_id = s.kpi_id AND dk.scd_is_current = true
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
         status, uploaded_by, source_file)
    VALUES
        (p_batch_id, p_year, v_row_count, v_rows_loaded, 0, v_rows_dup,
         'SUCCESS', p_uploaded_by, p_source_file);

    RETURN jsonb_build_object(
        'status',                 'SUCCESS',
        'batch_id',               p_batch_id,
        'year',                   p_year,
        'total_staged',           v_total_staged,
        'rows_loaded',            v_rows_loaded,
        'rows_unmatched_kpi',     0,
        'rows_skipped_duplicate', v_rows_dup
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


-- ===== 20260606183923_kpi_raw_reader_jsonb.sql =====
-- Rewrite get_all_kpi_rows to return countries JSONB instead of individual country columns.

DROP FUNCTION IF EXISTS rep_warehouse.get_all_kpi_rows(INTEGER, INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION rep_warehouse.get_all_kpi_rows(
    p_year   INTEGER,
    p_limit  INTEGER DEFAULT 100,
    p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
    row_id          INTEGER,
    kpi_no          TEXT,
    indicator_group TEXT,
    indicator       TEXT,
    disaggregation1 TEXT,
    disaggregation2 TEXT,
    value_type      TEXT,
    countries       JSONB,
    total           TEXT,
    updated_date    TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_raw, rep_warehouse, public
AS $$
    SELECT
        k.row_id::integer,
        k.kpi_no, k.indicator_group, k.indicator,
        k.disaggregation1, k.disaggregation2, k.value_type,
        k.countries, k.total,
        k.updated_date
    FROM rep_raw.all_kpis k
    WHERE k.batch_id = (
        SELECT ul.batch_id FROM rep_raw.upload_log ul
        WHERE ul.year = p_year AND ul.status = 'SUCCESS'
        ORDER BY ul.inserted_at DESC LIMIT 1
    )
    ORDER BY k.row_id::integer
    LIMIT p_limit OFFSET p_offset;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.get_all_kpi_rows(INTEGER, INTEGER, INTEGER) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_warehouse.get_all_kpi_rows(INTEGER, INTEGER, INTEGER) TO authenticated;


-- ===== 20260606193012_fix_portal_get_all_kpi_rows_jsonb.sql =====
-- Update rep_portal.get_all_kpi_rows wrapper to match rep_warehouse signature (countries JSONB).

DROP FUNCTION IF EXISTS rep_portal.get_all_kpi_rows(INTEGER, INTEGER, INTEGER);

CREATE OR REPLACE FUNCTION rep_portal.get_all_kpi_rows(
  p_year   INTEGER,
  p_limit  INTEGER DEFAULT 100,
  p_offset INTEGER DEFAULT 0
)
RETURNS TABLE (
  row_id          INTEGER,
  kpi_no          TEXT,
  indicator_group TEXT,
  indicator       TEXT,
  disaggregation1 TEXT,
  disaggregation2 TEXT,
  value_type      TEXT,
  countries       JSONB,
  total           TEXT,
  updated_date    TEXT
) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_raw, public
AS $$
  SELECT * FROM rep_warehouse.get_all_kpi_rows(p_year, p_limit, p_offset);
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.get_all_kpi_rows(INTEGER, INTEGER, INTEGER) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_all_kpi_rows(INTEGER, INTEGER, INTEGER) TO authenticated;


-- ===== 20260606195213_fix_kpi_upload_all_restore_update_quarter.sql =====
-- Restore update_quarter capture in kpi_upload_all, dropped accidentally by 20260606183813.

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

    -- KPI pre-check (batch-scoped)
    SELECT STRING_AGG(DISTINCT r.kpi_no, ', ' ORDER BY r.kpi_no)
    INTO v_missing_kpis
    FROM rep_raw.all_kpis r
    WHERE r.batch_id = p_batch_id
      AND r.kpi_no IS NOT NULL
      AND r.year_of_kpis IS NOT NULL
      AND r.year_of_kpis::integer = p_year
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_kpi dk
          WHERE dk.source_kpi_id = r.kpi_no AND dk.scd_is_current = true
      );

    IF v_missing_kpis IS NOT NULL THEN
        INSERT INTO rep_raw.upload_log
            (batch_id, year, row_count, rows_loaded, rows_unmatched, rows_duplicate,
             status, error_msg, uploaded_by, source_file)
        VALUES
            (p_batch_id, p_year, v_row_count, 0, 0, 0, 'FAILED',
             'KPI IDs not found in definitions (upload kpi-definitions.xlsx first): ' || v_missing_kpis,
             p_uploaded_by, p_source_file);

        RETURN jsonb_build_object(
            'status', 'FAILED',
            'error',  'KPI IDs not found in definitions (upload kpi-definitions.xlsx first): ' || v_missing_kpis
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
            s.row_id, s.year, s.country, s.kpi_id,
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
           ON dk.source_kpi_id = s.kpi_id AND dk.scd_is_current = true
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


-- ===== 20260608151131_etl_bg_cron.sql =====
-- Run Salesforce ETL via pg_cron to avoid PostgREST HTTP timeout.
--
-- Problem: etl_run_salesforce() takes several minutes on a full load. When called
-- via PostgREST RPC (from the orchestrator Edge Function), the HTTP gateway drops
-- the connection before the function finishes, killing the backend transaction.
-- SET statement_timeout = 0 only disables the PostgreSQL-level timeout; it has no
-- effect on the PostgREST HTTP timeout.
--
-- Solution: the orchestrator calls etl_schedule_salesforce_run() — a fast RPC that
-- schedules a pg_cron one-shot job and sets ingest_run.status = 'etl_pending', then
-- returns immediately. pg_cron fires etl_run_salesforce_bg() within the next minute,
-- running the ETL entirely inside PostgreSQL with no HTTP layer involved.

-- ── 1. Widen ingest_run.status to include 'etl_pending' ───────────────────────
--
-- The inline CHECK constraint is auto-named ingest_run_status_check by PostgreSQL.
-- Drop it and add a new one that includes etl_pending.

ALTER TABLE rep_warehouse.ingest_run
  DROP CONSTRAINT IF EXISTS ingest_run_status_check;

ALTER TABLE rep_warehouse.ingest_run
  ADD CONSTRAINT ingest_run_status_check
  CHECK (status IN ('in_progress', 'leased', 'completed', 'failed', 'etl_pending'));

-- The partial unique index prevents two active runs at once. Extend it so that an
-- etl_pending run also blocks a new run from starting.
DROP INDEX IF EXISTS rep_warehouse.ingest_run_single_active_idx;

CREATE UNIQUE INDEX ingest_run_single_active_idx
  ON rep_warehouse.ingest_run ((1))
  WHERE status IN ('in_progress', 'leased', 'etl_pending');


-- ── 2. etl_run_salesforce_bg — called by pg_cron ──────────────────────────────
--
-- Unschedules itself first so a failure does not trigger a re-run on the next
-- cron tick. Then runs the full Salesforce ETL and marks ingest_run terminal.
-- Does not use ingest_finish_run() because that validates lease_owner, which a
-- cron job does not hold.

CREATE OR REPLACE FUNCTION rep_warehouse.etl_run_salesforce_bg(p_run_id TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET statement_timeout = 0
SET search_path = rep_warehouse, rep_staging, rep_raw, cron, pg_temp
AS $$
BEGIN
  -- Remove the one-shot job immediately — if the ETL fails we do not want the
  -- cron scheduler to retry it on the next tick.
  PERFORM cron.unschedule('etl-bg-' || LEFT(p_run_id, 8));

  -- Run staging + warehouse ETL. etl_run_salesforce handles etl_batch_log itself.
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
  -- Re-raise so pg_cron records the failure in cron.job_run_details.
  RAISE;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.etl_run_salesforce_bg(TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_warehouse.etl_run_salesforce_bg(TEXT) TO service_role;


-- ── 3. etl_schedule_salesforce_run — called by the orchestrator ───────────────
--
-- Schedules a one-shot pg_cron job that will fire within the next minute, then
-- sets ingest_run.status = 'etl_pending' so the 5-min resume cron ignores the run
-- while ETL is in progress.

CREATE OR REPLACE FUNCTION rep_warehouse.etl_schedule_salesforce_run(p_run_id TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_warehouse, cron, pg_temp
AS $$
BEGIN
  PERFORM cron.schedule(
    'etl-bg-' || LEFT(p_run_id, 8),
    '* * * * *',
    format(
      $cmd$SELECT rep_warehouse.etl_run_salesforce_bg(%L)$cmd$,
      p_run_id
    )
  );

  UPDATE rep_warehouse.ingest_run
     SET status     = 'etl_pending',
         updated_at = NOW()
   WHERE run_id = p_run_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.etl_schedule_salesforce_run(TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_warehouse.etl_schedule_salesforce_run(TEXT) TO service_role;


-- ===== 20260609065334_etl_bg_fix_exception_handling.sql =====
-- Fix etl_run_salesforce_bg exception handling.
--
-- Bug: the original function had RAISE at the end of its EXCEPTION block.
-- PostgreSQL rolls back the entire transaction when an exception propagates out
-- of a function — including the UPDATE to 'failed' inside the handler and the
-- cron.unschedule call in the main body. Result: status stayed 'etl_pending'
-- forever and the pg_cron job kept retrying every minute.
--
-- Fix:
--   1. Add 'etl_running' status so the function can atomically claim a run
--      before doing any work that might fail.
--   2. Rewrite etl_run_salesforce_bg to claim via UPDATE (not IF EXISTS), use
--      a safe unschedule that ignores missing jobs, and drop the RAISE so the
--      'failed' UPDATE actually commits.
--   3. On a failed run the cron job is still scheduled (unschedule was rolled
--      back with the transaction). The guard on the next tick sees status !=
--      'etl_pending', unschedules cleanly, and returns — two ticks max.

-- ── 1. Widen status constraint to include 'etl_running' ───────────────────────

ALTER TABLE rep_warehouse.ingest_run
  DROP CONSTRAINT IF EXISTS ingest_run_status_check;

ALTER TABLE rep_warehouse.ingest_run
  ADD CONSTRAINT ingest_run_status_check
  CHECK (status IN ('in_progress', 'leased', 'completed', 'failed', 'etl_pending', 'etl_running'));

-- Keep etl_running in the single-active-run guard.
DROP INDEX IF EXISTS rep_warehouse.ingest_run_single_active_idx;

CREATE UNIQUE INDEX ingest_run_single_active_idx
  ON rep_warehouse.ingest_run ((1))
  WHERE status IN ('in_progress', 'leased', 'etl_pending', 'etl_running');


-- ── 2. Rewritten etl_run_salesforce_bg ────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_warehouse.etl_run_salesforce_bg(p_run_id TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET statement_timeout = 0
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
BEGIN
  -- Atomically claim the run. If status is no longer 'etl_pending' (already
  -- completed, failed, or claimed by a concurrent tick) just remove the job
  -- and return so we don't run ETL twice or on a terminal run.
  UPDATE rep_warehouse.ingest_run
     SET status     = 'etl_running',
         updated_at = NOW()
   WHERE run_id = p_run_id
     AND status  = 'etl_pending';

  IF NOT FOUND THEN
    -- Safe unschedule: no error if the job is already gone.
    PERFORM cron.unschedule(jobid)
       FROM cron.job
      WHERE jobname = 'etl-bg-' || LEFT(p_run_id, 8);
    RETURN;
  END IF;

  -- Remove the one-shot job. If this transaction rolls back (ETL error below)
  -- the unschedule is also rolled back, so the job survives and fires again.
  -- The guard above then catches it (status = 'failed', not 'etl_pending') and
  -- unschedules cleanly on the second tick.
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
  -- Do NOT re-raise. Raising here would roll back this UPDATE, leaving the run
  -- stuck in 'etl_pending'. The error is visible in ingest_run.error and in
  -- cron.job_run_details. The cron job reruns once more, hits NOT FOUND above
  -- (status is now 'failed'), and unschedules itself.
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


-- ===== 20260609073052_etl_bg_disable_session_timeout.sql =====
-- pg_cron sessions inherit a database-level statement_timeout that overrides
-- function-level SET clauses. This causes REFRESH MATERIALIZED VIEW (called
-- inside etl_run_warehouse) to be cancelled mid-run.
--
-- Fix: call set_config('statement_timeout', '0', false) at the top of
-- etl_run_salesforce_bg to force the session-level GUC to 0, the same way
-- run-ingest.js does SET statement_timeout = 0 before running ETL steps.
-- false = session-scoped (persists for the entire pg_cron job execution).

CREATE OR REPLACE FUNCTION rep_warehouse.etl_run_salesforce_bg(p_run_id TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET statement_timeout = 0
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
BEGIN
  -- Force session-level timeout off. pg_cron inherits a database-level
  -- statement_timeout that overrides function SET clauses.
  PERFORM set_config('statement_timeout', '0', false);

  -- Atomically claim the run. If status is no longer 'etl_pending' (already
  -- completed, failed, or claimed by a concurrent tick) just remove the job
  -- and return so we don't run ETL twice or on a terminal run.
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


-- ===== 20260609074439_etl_bg_async_matview_refresh.sql =====
-- Fix pg_cron ETL timeout on REFRESH MATERIALIZED VIEW.
--
-- pg_cron sessions have an infrastructure-level statement_timeout that cannot
-- be overridden by SET statement_timeout = 0 in function declarations or by
-- set_config() calls. REFRESH MATERIALIZED VIEW rep_portal.dashboard_data_agg
-- (added to etl_run_warehouse in 20260516161024) is cancelled every time the
-- ETL runs via pg_cron.
--
-- Fix: remove the synchronous REFRESH from etl_run_warehouse() and fire it
-- asynchronously via net.http_post to the refresh-dashboard-agg Edge Function
-- from etl_run_salesforce_bg, after ETL completes and ingest_run is marked
-- completed. This is identical to the pattern used by kpi_upload_all and
-- kpi_upload_level_one (see 20260603181925_kpi_upload_async_refresh.sql).
--
-- run-ingest.js ETL path: refresh_dashboard_data_agg() is now called at the
-- end of runEtlPerTable() so the dashboard stays current after bulk loads too.

-- ── 1. Remove REFRESH from etl_run_warehouse ──────────────────────────────────

CREATE OR REPLACE FUNCTION rep_warehouse.etl_run_warehouse()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER
SET statement_timeout = 0
SET search_path = rep_warehouse, rep_staging, rep_raw, rep_portal, pg_temp
AS $$
BEGIN
    PERFORM rep_warehouse.etl_load_dim_roc_geography();
    PERFORM rep_warehouse.etl_load_dim_roc_project_code();
    PERFORM rep_warehouse.etl_load_dim_roc_donor();
    PERFORM rep_warehouse.etl_load_dim_roc_donor_activity();
    PERFORM rep_warehouse.etl_load_dim_geography();
    PERFORM rep_warehouse.etl_load_dim_school();
    PERFORM rep_warehouse.etl_load_dim_contact();
    PERFORM rep_warehouse.etl_load_fact_children_supported();
    PERFORM rep_warehouse.etl_load_fact_guide_assignment();
    PERFORM rep_warehouse.etl_load_fact_cama_membership();
    PERFORM rep_warehouse.etl_load_fact_post_school_support();
    PERFORM rep_warehouse.etl_load_fact_grants();
    PERFORM rep_warehouse.etl_load_fact_loans();
    -- REFRESH MATERIALIZED VIEW moved: pg_cron sessions enforce a timeout that
    -- overrides SET statement_timeout = 0. etl_run_salesforce_bg fires it async
    -- via net.http_post after ETL completes. run-ingest.js calls
    -- refresh_dashboard_data_agg() directly after its per-step ETL loop.
END;
$$;

GRANT EXECUTE ON FUNCTION rep_warehouse.etl_run_warehouse() TO service_role;


-- ── 2. etl_run_salesforce_bg — fire async refresh after ETL ───────────────────

CREATE OR REPLACE FUNCTION rep_warehouse.etl_run_salesforce_bg(p_run_id TEXT)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET statement_timeout = 0
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
DECLARE
  v_auth TEXT;
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

  -- Async mat view refresh — runs in the Edge Function context, outside
  -- pg_cron's session timeout. Failure must not fail the ingest run.
  BEGIN
    SELECT decrypted_secret INTO v_auth
      FROM vault.decrypted_secrets
     WHERE name = 'ingest_auth_header'
     LIMIT 1;

    IF v_auth IS NOT NULL THEN
      PERFORM net.http_post(
        url     := 'https://qlvayqyihfixikfqfelu.supabase.co/functions/v1/refresh-dashboard-agg',
        headers := jsonb_build_object(
          'Content-Type',  'application/json',
          'Authorization', v_auth
        ),
        body    := '{}'::jsonb
      );
    END IF;
  EXCEPTION WHEN OTHERS THEN
    NULL;
  END;

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


-- ===== 20260609092101_recon_warehouse_counts.sql =====
CREATE OR REPLACE FUNCTION rep_portal.get_warehouse_counts()
RETURNS TABLE (
    source_object  TEXT,
    country        TEXT,
    year           SMALLINT,
    row_count      BIGINT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$

    -- academic_record (School path) → fact_children_supported
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

    -- academic_record (Post School path) → fact_post_school_support
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

    -- guides → fact_guide_assignment (year from date_joined_guide_programme)
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

    -- guides with no join date
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

    -- grant_recipients → fact_grants (year from grant_date)
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

    -- grant_recipients with no grant date
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

    -- loan_recipients → fact_loans (year from disbursal_date)
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

    -- loan_recipients with no disbursal date
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

    -- cama_members → fact_cama_membership (year from date_joined_cama)
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

    -- cama_members with no join date
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

    -- contacts → dim_contact (SCD dimension; country column is direct)
    SELECT
        'dim_contact'::TEXT AS source_object,
        c.country,
        NULL::SMALLINT   AS year,
        COUNT(*)::BIGINT
    FROM  rep_warehouse.dim_contact c
    WHERE c.scd_is_current = true
    GROUP BY c.country

    UNION ALL

    -- schools → dim_school (SCD dimension; country column is direct)
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


-- ===== 20260609193023_simplify_etl_source_key_upserts.sql =====
SET statement_timeout = 0;

-- ══════════════════════════════════════════════════════════════════════════════
-- Simplify ETL: replace business hash dedup with source key upserts
--
-- Dimensions: ON CONFLICT (source_key) WHERE scd_is_current = true DO UPDATE
-- Facts:      ON CONFLICT (source_id) DO UPDATE
--
-- lin_business_hash column stays (nullable) but is no longer populated.
-- scd_is_current / scd_version / scd_effective_* columns kept for view
-- compatibility — scd_is_current is always true, scd_version always 1.
--
-- Fact tables that need new source ID columns are truncated here.
-- They will be repopulated on the next full ETL run.
-- ══════════════════════════════════════════════════════════════════════════════


-- ── 1. Add source ID columns to fact tables ───────────────────────────────────

ALTER TABLE rep_warehouse.fact_children_supported
    ADD COLUMN IF NOT EXISTS source_academic_record_id TEXT;

ALTER TABLE rep_warehouse.fact_post_school_support
    ADD COLUMN IF NOT EXISTS source_academic_record_id TEXT;

ALTER TABLE rep_warehouse.fact_guide_assignment
    ADD COLUMN IF NOT EXISTS source_guide_id TEXT;


-- ── 2. Truncate all Salesforce-sourced tables (repopulated on next full ETL) ──
-- All FK-related tables in one statement so PostgreSQL handles constraint checks.
-- KPI tables (dim_kpi, fact_observed_kpi, fact_level_one_kpis) are NOT touched.

-- Excluded from truncate (referenced by KPI tables or dim_geography which is kept):
--   dim_geography        → referenced by fact_observed_kpi, fact_level_one_kpis
--   dim_roc_geography    → referenced by dim_geography.roc_geography_id
-- These dims will be updated in-place by the new upsert ETL on next run.
TRUNCATE
    rep_warehouse.fact_grants,
    rep_warehouse.fact_loans,
    rep_warehouse.fact_children_supported,
    rep_warehouse.fact_post_school_support,
    rep_warehouse.fact_guide_assignment,
    rep_warehouse.fact_cama_membership,
    rep_warehouse.etl_batch_log,
    rep_warehouse.dim_contact,
    rep_warehouse.dim_school,
    rep_warehouse.dim_roc_donor_activity,
    rep_warehouse.dim_roc_donor,
    rep_warehouse.dim_roc_project_code;


-- ── 3. Drop old hash indexes ──────────────────────────────────────────────────

DROP INDEX IF EXISTS rep_warehouse.idx_fact_cs_business_hash;
DROP INDEX IF EXISTS rep_warehouse.idx_fact_cm_business_hash;
DROP INDEX IF EXISTS rep_warehouse.idx_fact_ga_business_hash;
DROP INDEX IF EXISTS rep_warehouse.idx_fact_ps_business_hash;


-- ── 4. New unique indexes on facts ───────────────────────────────────────────

CREATE UNIQUE INDEX uix_fact_cs_grain
    ON rep_warehouse.fact_children_supported (source_academic_record_id)
    WHERE source_academic_record_id IS NOT NULL;

CREATE UNIQUE INDEX uix_fact_ps_grain
    ON rep_warehouse.fact_post_school_support (source_academic_record_id)
    WHERE source_academic_record_id IS NOT NULL;

CREATE UNIQUE INDEX uix_fact_ga_grain
    ON rep_warehouse.fact_guide_assignment (source_guide_id)
    WHERE source_guide_id IS NOT NULL;

CREATE UNIQUE INDEX uix_fact_cm_grain
    ON rep_warehouse.fact_cama_membership (source_contact_id, source_school_id)
    WHERE source_contact_id IS NOT NULL AND source_school_id IS NOT NULL;


-- ── 5. Rewrite dimension ETL functions ───────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_dim_roc_geography()
RETURNS void LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.dim_roc_geography
        (source_roc_id, name, reporting_code, available_country, active,
         scd_effective_from, scd_is_current, scd_version,
         lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT DISTINCT ON (salesforce_id)
        salesforce_id, name, reporting_code, available_country, active,
        CURRENT_DATE, true, 1,
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM rep_staging.dimension_1_roc
    ORDER BY salesforce_id
    ON CONFLICT (source_roc_id) WHERE scd_is_current = true
    DO UPDATE SET
        name               = EXCLUDED.name,
        reporting_code     = EXCLUDED.reporting_code,
        available_country  = EXCLUDED.available_country,
        active             = EXCLUDED.active,
        scd_effective_from = EXCLUDED.scd_effective_from,
        lin_load_batch_id  = EXCLUDED.lin_load_batch_id,
        lin_source_system  = EXCLUDED.lin_source_system,
        lin_source_file    = EXCLUDED.lin_source_file;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_dim_roc_project_code()
RETURNS void LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.dim_roc_project_code
        (source_roc_id, name, reporting_code, available_country, active,
         scd_effective_from, scd_is_current, scd_version,
         lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT DISTINCT ON (salesforce_id)
        salesforce_id, name, reporting_code, available_country, active,
        CURRENT_DATE, true, 1,
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM rep_staging.dimension_2_roc
    ORDER BY salesforce_id
    ON CONFLICT (source_roc_id) WHERE scd_is_current = true
    DO UPDATE SET
        name               = EXCLUDED.name,
        reporting_code     = EXCLUDED.reporting_code,
        available_country  = EXCLUDED.available_country,
        active             = EXCLUDED.active,
        scd_effective_from = EXCLUDED.scd_effective_from,
        lin_load_batch_id  = EXCLUDED.lin_load_batch_id,
        lin_source_system  = EXCLUDED.lin_source_system,
        lin_source_file    = EXCLUDED.lin_source_file;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_dim_roc_donor()
RETURNS void LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.dim_roc_donor
        (source_roc_id, name, reporting_code, available_country, active, start_date, end_date,
         scd_effective_from, scd_is_current, scd_version,
         lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT DISTINCT ON (salesforce_id)
        salesforce_id, name, reporting_code, available_country, active,
        start_date::date, end_date::date,
        CURRENT_DATE, true, 1,
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM rep_staging.dimension_3_roc
    ORDER BY salesforce_id
    ON CONFLICT (source_roc_id) WHERE scd_is_current = true
    DO UPDATE SET
        name               = EXCLUDED.name,
        reporting_code     = EXCLUDED.reporting_code,
        available_country  = EXCLUDED.available_country,
        active             = EXCLUDED.active,
        start_date         = EXCLUDED.start_date,
        end_date           = EXCLUDED.end_date,
        scd_effective_from = EXCLUDED.scd_effective_from,
        lin_load_batch_id  = EXCLUDED.lin_load_batch_id,
        lin_source_system  = EXCLUDED.lin_source_system,
        lin_source_file    = EXCLUDED.lin_source_file;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_dim_roc_donor_activity()
RETURNS void LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.dim_roc_donor_activity
        (source_roc_id, donor_id, name, reporting_code, available_country, active,
         scd_effective_from, scd_is_current, scd_version,
         lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT DISTINCT ON (s.salesforce_id)
        s.salesforce_id,
        d3.id,
        s.name, s.reporting_code, s.available_country, s.active,
        CURRENT_DATE, true, 1,
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM rep_staging.dimension_4_roc s
    LEFT JOIN rep_warehouse.dim_roc_donor d3
        ON d3.source_roc_id = s.dimension_3_id AND d3.scd_is_current = true
    ORDER BY s.salesforce_id
    ON CONFLICT (source_roc_id) WHERE scd_is_current = true
    DO UPDATE SET
        donor_id           = EXCLUDED.donor_id,
        name               = EXCLUDED.name,
        reporting_code     = EXCLUDED.reporting_code,
        available_country  = EXCLUDED.available_country,
        active             = EXCLUDED.active,
        scd_effective_from = EXCLUDED.scd_effective_from,
        lin_load_batch_id  = EXCLUDED.lin_load_batch_id,
        lin_source_system  = EXCLUDED.lin_source_system,
        lin_source_file    = EXCLUDED.lin_source_file;
END;
$$;

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

    -- district rows (NOT EXISTS — no unique index on district grain)
    INSERT INTO rep_warehouse.dim_geography
        (country, province, district, is_country, roc_geography_id,
         scd_effective_from, scd_is_current, scd_version,
         lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT DISTINCT ON (d.country_name, d.district_name)
        d.country_name,
        d.province,
        d.district_name,
        false,
        rg.id,
        CURRENT_DATE, true, 1,
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM rep_staging.districts d
    LEFT JOIN rep_warehouse.dim_roc_geography rg
        ON rg.source_roc_id = d.region_id AND rg.scd_is_current = true
    WHERE d.country_name IS NOT NULL AND d.district_name IS NOT NULL
      AND NOT EXISTS (
          SELECT 1 FROM rep_warehouse.dim_geography g
          WHERE g.country = d.country_name AND g.district = d.district_name
            AND g.scd_is_current = true
      )
    ORDER BY d.country_name, d.district_name;

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

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_dim_school()
RETURNS void LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
SET statement_timeout = 0 AS $$
BEGIN
    INSERT INTO rep_warehouse.dim_school
        (source_school_id, school_name, geography_id, province, district, country,
         school_type, accommodation_type, date_camfed_began_support,
         active_on_bursary, cpp_in_place, snf_only, monitoring_school,
         gea_school, merp, active_partner_school, affiliated_school,
         latitude, longitude, roc_donor_id,
         scd_effective_from, scd_is_current, scd_version,
         lin_load_batch_id, lin_source_system, lin_source_file, lin_inserted_at)
    SELECT DISTINCT ON (s.school_id)
        s.school_id,
        s.school_name,
        dg.id,
        s.district, s.district, s.country,
        s.school_type,
        s.accommodation_type,
        s.date_camfed_began_support::timestamp,
        s.active_on_bursary, s.cpp_in_place, s.snf_only, s.monitoring_school,
        s.gea_school, s.merp, s.active_partner_school, s.affiliated_school,
        s.latitude::numeric, s.longitude::numeric,
        d3.id,
        CURRENT_DATE, true, 1,
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM rep_staging.schools s
    LEFT JOIN rep_warehouse.dim_geography dg
        ON dg.country = s.country AND dg.district = s.district AND dg.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_roc_donor d3
        ON d3.source_roc_id = s.donor_id AND d3.scd_is_current = true
    WHERE s.school_id IS NOT NULL
    ORDER BY s.school_id
    ON CONFLICT (source_school_id) WHERE scd_is_current = true
    DO UPDATE SET
        school_name                = EXCLUDED.school_name,
        geography_id               = EXCLUDED.geography_id,
        province                   = EXCLUDED.province,
        district                   = EXCLUDED.district,
        country                    = EXCLUDED.country,
        school_type                = EXCLUDED.school_type,
        accommodation_type         = EXCLUDED.accommodation_type,
        date_camfed_began_support  = EXCLUDED.date_camfed_began_support,
        active_on_bursary          = EXCLUDED.active_on_bursary,
        cpp_in_place               = EXCLUDED.cpp_in_place,
        snf_only                   = EXCLUDED.snf_only,
        monitoring_school          = EXCLUDED.monitoring_school,
        gea_school                 = EXCLUDED.gea_school,
        merp                       = EXCLUDED.merp,
        active_partner_school      = EXCLUDED.active_partner_school,
        affiliated_school          = EXCLUDED.affiliated_school,
        latitude                   = EXCLUDED.latitude,
        longitude                  = EXCLUDED.longitude,
        roc_donor_id               = EXCLUDED.roc_donor_id,
        scd_effective_from         = EXCLUDED.scd_effective_from,
        lin_load_batch_id          = EXCLUDED.lin_load_batch_id,
        lin_source_system          = EXCLUDED.lin_source_system,
        lin_source_file            = EXCLUDED.lin_source_file;
END;
$$;

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_dim_contact()
RETURNS void LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
SET statement_timeout = 0 AS $$
BEGIN
    DROP TABLE IF EXISTS _etl_contacts;
    CREATE TEMP TABLE _etl_contacts (
        contact_id                  TEXT PRIMARY KEY,
        country                     TEXT,
        gender                      TEXT,
        wg_difficulty_overall       TEXT,
        lg_social_support_recipient BOOLEAN,
        active_on_bursary           BOOLEAN,
        orphan_status               TEXT,
        district                    TEXT,
        donor_code_id               TEXT,
        project_code_id             TEXT,
        donor_activity_id           TEXT
    );

    INSERT INTO _etl_contacts
    SELECT DISTINCT ON (salesforce_id)
        salesforce_id,
        country_name,
        gender,
        wg_difficulty_overall,
        lg_social_support_recipient,
        active_on_bursary,
        orphan_status,
        district_id,
        donor_code_id,
        project_code_id,
        donor_activity_id
    FROM rep_staging.contacts
    WHERE salesforce_id IS NOT NULL
    ORDER BY salesforce_id;

    INSERT INTO _etl_contacts (contact_id, country, district, donor_code_id, project_code_id, donor_activity_id)
    SELECT contact_id, country, district_id, donor_code_id, project_code_id, donor_activity_id
    FROM (
        SELECT DISTINCT ON (contact_id)
            contact_id, country, district_id, donor_code_id, project_code_id, donor_activity_id
        FROM rep_staging.academic_record
        WHERE contact_id IS NOT NULL
        ORDER BY contact_id
    ) sub
    ON CONFLICT DO NOTHING;

    INSERT INTO _etl_contacts (contact_id, district)
    SELECT contact_id, district_id
    FROM (
        SELECT DISTINCT ON (contact_id)
            contact_id, district_id
        FROM rep_staging.guides
        WHERE contact_id IS NOT NULL
        ORDER BY contact_id
    ) sub
    ON CONFLICT DO NOTHING;

    INSERT INTO _etl_contacts (contact_id, country, district)
    SELECT contact_id, country, district
    FROM (
        SELECT DISTINCT ON (contact_id)
            contact_id, country, district
        FROM rep_staging.cama_members
        WHERE contact_id IS NOT NULL
        ORDER BY contact_id
    ) sub
    ON CONFLICT DO NOTHING;

    INSERT INTO _etl_contacts (contact_id, country, district)
    SELECT contact_id, country, district
    FROM (
        SELECT DISTINCT ON (contact_id)
            contact_id, country, district
        FROM rep_staging.grant_recipients
        WHERE contact_id IS NOT NULL
        ORDER BY contact_id
    ) sub
    ON CONFLICT DO NOTHING;

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
        d3.id,
        d2.id,
        d4.id,
        CURRENT_DATE, true, 1,
        current_setting('app.batch_id',      true),
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        NOW()
    FROM _etl_contacts i
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


-- ── 6. Rewrite fact ETL functions ─────────────────────────────────────────────

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
        s.contact_id, dct.id,
        s.school_id,  ds.id,
        COALESCE(
            (SELECT id FROM rep_warehouse.dim_geography
             WHERE country = s.country AND district = s.district AND scd_is_current = true LIMIT 1),
            (SELECT id FROM rep_warehouse.dim_geography
             WHERE country = s.country AND province IS NULL AND district IS NULL LIMIT 1)
        ),
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
    LEFT JOIN rep_warehouse.dim_contact          dct ON dct.source_contact_id = s.contact_id AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_school            ds  ON ds.source_school_id   = s.school_id  AND ds.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date              dd  ON dd.id = ((s.year::text || '0101')::integer)
    LEFT JOIN rep_warehouse.dim_roc_donor         d3  ON d3.source_roc_id = s.donor_code_id   AND d3.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_roc_project_code  d2  ON d2.source_roc_id = s.project_code_id AND d2.scd_is_current = true
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
        COALESCE(ds.geography_id,
            (SELECT id FROM rep_warehouse.dim_geography WHERE country = dct.country
             AND district = dct.district_of_residence AND scd_is_current = true LIMIT 1)
        ),
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
    LEFT JOIN rep_warehouse.dim_contact dct      ON dct.source_contact_id = s.contact_id AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_school  ds       ON ds.source_school_id   = s.school_id  AND ds.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date    dd_joined ON dd_joined.id = TO_CHAR(s.date_joined_guide_programme, 'YYYYMMDD')::integer
    LEFT JOIN rep_warehouse.dim_date    dd_left   ON dd_left.id   = TO_CHAR(s.date_left_guide_programme,   'YYYYMMDD')::integer
    LEFT JOIN rep_warehouse.dim_roc_donor d3      ON d3.source_roc_id = s.donor_id AND d3.scd_is_current = true
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
        COALESCE(ds.geography_id,
            (SELECT id FROM rep_warehouse.dim_geography WHERE country = s.country
             AND district = s.district AND scd_is_current = true LIMIT 1)
        ),
        s.date_joined_cama, dd.id,
        s.partner_school,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        NOW(),
        s.row_id
    FROM rep_staging.cama_members s
    LEFT JOIN rep_warehouse.dim_contact dct ON dct.source_contact_id = s.contact_id AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_school  ds  ON ds.source_school_id   = s.school_id  AND ds.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date    dd  ON dd.id = TO_CHAR(s.date_joined_cama::timestamp, 'YYYYMMDD')::integer
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
        COALESCE(
            (SELECT id FROM rep_warehouse.dim_geography
             WHERE country = s.country AND district = s.district AND scd_is_current = true LIMIT 1),
            (SELECT id FROM rep_warehouse.dim_geography
             WHERE country = s.country AND province IS NULL AND district IS NULL LIMIT 1)
        ),
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
    LEFT JOIN rep_warehouse.dim_contact  dct ON dct.source_contact_id = s.contact_id AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = ((s.year::text || '0101')::integer)
    LEFT JOIN rep_warehouse.dim_roc_donor d3 ON d3.source_roc_id = s.donor_code_id AND d3.scd_is_current = true
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


-- ── 7. Grants: add consistent search_path (logic unchanged) ──────────────────

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
        COALESCE(
            (SELECT id FROM rep_warehouse.dim_geography
             WHERE country = s.country AND district = s.district AND scd_is_current = true LIMIT 1),
            (SELECT id FROM rep_warehouse.dim_geography
             WHERE country = s.country AND province IS NULL AND district IS NULL LIMIT 1)
        ),
        s.grant_type, s.grant_status, s.amount_given::numeric, s.grant_date::timestamp, dd.id,
        d3.id,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        MD5(COALESCE(s.grant_id, '')),
        s.row_id
    FROM rep_staging.grant_recipients s
    LEFT JOIN rep_warehouse.dim_contact  dct ON dct.source_contact_id = s.contact_id AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = TO_CHAR(s.grant_date::timestamp, 'YYYYMMDD')::integer
    LEFT JOIN rep_warehouse.dim_roc_donor d3 ON d3.source_roc_id = s.donor_id AND d3.scd_is_current = true
    ON CONFLICT (source_grant_id) DO NOTHING;
END;
$$;


-- ===== 20260609201900_cleanup_raw_staging_after_etl.sql =====
-- Truncate rep_raw Salesforce tables and drop rep_staging tables after a
-- successful ETL run. Runs as a best-effort block — cleanup failure never
-- marks the ETL batch as failed.
-- KPI tables (rep_raw.all_kpis, rep_raw.level_one_kpis) are NOT touched.

CREATE OR REPLACE FUNCTION rep_warehouse.etl_run_salesforce(
    p_source_system TEXT DEFAULT 'Salesforce_CAMFED',
    p_source_file   TEXT DEFAULT 'salesforce',
    p_batch_id      TEXT DEFAULT NULL
)
RETURNS TEXT
LANGUAGE plpgsql
SECURITY DEFINER
SET statement_timeout = 0
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
DECLARE
    v_batch_id TEXT;
    v_err_msg  TEXT;
BEGIN
    v_batch_id := COALESCE(p_batch_id, gen_random_uuid()::text);

    PERFORM set_config('app.batch_id',      v_batch_id,      true);
    PERFORM set_config('app.source_system', p_source_system, true);
    PERFORM set_config('app.source_file',   p_source_file,   true);

    INSERT INTO rep_warehouse.etl_batch_log (batch_id, status, source_system)
    VALUES (v_batch_id, 'running', p_source_system);

    BEGIN
        PERFORM rep_warehouse.etl_run_staging();
        PERFORM rep_warehouse.etl_run_warehouse();

        UPDATE rep_warehouse.etl_batch_log
        SET status = 'success', finished_at = NOW()
        WHERE batch_id = v_batch_id;
    EXCEPTION WHEN OTHERS THEN
        GET STACKED DIAGNOSTICS v_err_msg = MESSAGE_TEXT;
        UPDATE rep_warehouse.etl_batch_log
        SET status = 'failed', finished_at = NOW(), error_message = v_err_msg
        WHERE batch_id = v_batch_id;
        RAISE;
    END;

    -- Best-effort cleanup: free storage after successful ETL.
    -- Failure here does not affect the batch log status.
    BEGIN
        TRUNCATE
            rep_raw.dimension_1_roc,
            rep_raw.dimension_2_roc,
            rep_raw.dimension_3_roc,
            rep_raw.dimension_4_roc,
            rep_raw.countries,
            rep_raw.contacts,
            rep_raw.districts,
            rep_raw.schools,
            rep_raw.academic_record,
            rep_raw.guides,
            rep_raw.grant_recipients,
            rep_raw.loan_recipients,
            rep_raw.cama_members;

        DROP TABLE IF EXISTS rep_staging.dimension_1_roc;
        DROP TABLE IF EXISTS rep_staging.dimension_2_roc;
        DROP TABLE IF EXISTS rep_staging.dimension_3_roc;
        DROP TABLE IF EXISTS rep_staging.dimension_4_roc;
        DROP TABLE IF EXISTS rep_staging.countries;
        DROP TABLE IF EXISTS rep_staging.contacts;
        DROP TABLE IF EXISTS rep_staging.districts;
        DROP TABLE IF EXISTS rep_staging.schools;
        DROP TABLE IF EXISTS rep_staging.academic_record;
        DROP TABLE IF EXISTS rep_staging.post_school_clients;
        DROP TABLE IF EXISTS rep_staging.guides;
        DROP TABLE IF EXISTS rep_staging.cama_members;
        DROP TABLE IF EXISTS rep_staging.grant_recipients;
        DROP TABLE IF EXISTS rep_staging.loan_recipients;
    EXCEPTION WHEN OTHERS THEN
        NULL;
    END;

    RETURN v_batch_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.etl_run_salesforce(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_warehouse.etl_run_salesforce(TEXT, TEXT, TEXT) TO service_role;


-- ===== 20260609210744_fix_cama_membership_null_school.sql =====
-- CAMA members without a school association were dropped by the previous ETL
-- rewrite because the ON CONFLICT target required both source_contact_id and
-- source_school_id to be NOT NULL. Add a second partial unique index for the
-- no-school grain and split the ETL into two INSERT statements.

CREATE UNIQUE INDEX uix_fact_cm_no_school
    ON rep_warehouse.fact_cama_membership (source_contact_id)
    WHERE source_contact_id IS NOT NULL AND source_school_id IS NULL;

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
        COALESCE(ds.geography_id,
            (SELECT id FROM rep_warehouse.dim_geography WHERE country = s.country
             AND district = s.district AND scd_is_current = true LIMIT 1)
        ),
        s.date_joined_cama, dd.id,
        s.partner_school,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        NOW(),
        s.row_id
    FROM rep_staging.cama_members s
    LEFT JOIN rep_warehouse.dim_contact dct ON dct.source_contact_id = s.contact_id AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_school  ds  ON ds.source_school_id   = s.school_id  AND ds.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date    dd  ON dd.id = TO_CHAR(s.date_joined_cama::timestamp, 'YYYYMMDD')::integer
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
        (SELECT id FROM rep_warehouse.dim_geography WHERE country = s.country
         AND province IS NULL AND district IS NULL LIMIT 1),
        s.date_joined_cama, dd.id,
        s.partner_school,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        NOW(),
        s.row_id
    FROM rep_staging.cama_members s
    LEFT JOIN rep_warehouse.dim_contact dct ON dct.source_contact_id = s.contact_id AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date    dd  ON dd.id = TO_CHAR(s.date_joined_cama::timestamp, 'YYYYMMDD')::integer
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


-- ===== 20260610111720_fix_guide_geography_district_lookup.sql =====
-- When a guide has no school, the previous fallback tried to match dim_geography using
-- dim_contact.district_of_residence, which stores a Salesforce ID not a district name.
-- This adds a third COALESCE option that resolves via the guide's own District__c field:
--   rep_raw.guides.district_id → rep_raw.districts.salesforce_id → dim_geography

CREATE OR REPLACE FUNCTION rep_warehouse.etl_load_fact_guide_assignment()
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET statement_timeout = 0
SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
AS $$
BEGIN
    INSERT INTO rep_warehouse.fact_guide_assignment
        (source_contact_id, contact_id, source_school_id, school_id, geography_id,
         date_joined_guide_programme, date_joined_id,
         date_left_guide_programme,   date_left_id,
         guide_type, guide_status, guide_specialty, guide_dropout_reason,
         trained_in_climate_education, roc_donor_id,
         lin_is_current, lin_change_type, lin_source_system, lin_source_file,
         lin_load_batch_id, lin_business_hash, lin_source_row_number)
    SELECT
        s.contact_id, dct.id,
        s.school_id,  ds.id,
        COALESCE(
            ds.geography_id,
            (SELECT id FROM rep_warehouse.dim_geography
             WHERE country = dct.country
               AND district = dct.district_of_residence
               AND scd_is_current = true LIMIT 1),
            (SELECT dg.id FROM rep_warehouse.dim_geography dg
             JOIN rep_raw.districts rd
               ON rd.district_name = dg.district AND rd.country_name = dg.country
             WHERE rd.salesforce_id = s.district_id
               AND dg.scd_is_current = true LIMIT 1)
        ),
        s.date_joined_guide_programme, dd_joined.id,
        s.date_left_guide_programme,   dd_left.id,
        s.guide_type, s.guide_status, s.guide_specialty, s.guide_dropout_reason,
        s.trained_in_climate_education,
        d3.id,
        true, 'INSERT',
        current_setting('app.source_system', true),
        current_setting('app.source_file',   true),
        current_setting('app.batch_id',      true),
        MD5(COALESCE(s.contact_id, '')),
        s.row_id
    FROM rep_staging.guides s
    LEFT JOIN rep_warehouse.dim_contact dct      ON dct.source_contact_id = s.contact_id AND dct.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_school  ds       ON ds.source_school_id   = s.school_id  AND ds.scd_is_current = true
    LEFT JOIN rep_warehouse.dim_date    dd_joined ON dd_joined.id = TO_CHAR(s.date_joined_guide_programme, 'YYYYMMDD')::integer
    LEFT JOIN rep_warehouse.dim_date    dd_left   ON dd_left.id   = TO_CHAR(s.date_left_guide_programme,   'YYYYMMDD')::integer
    LEFT JOIN rep_warehouse.dim_roc_donor d3      ON d3.source_roc_id = s.donor_id AND d3.scd_is_current = true
    WHERE NOT EXISTS (
        SELECT 1 FROM rep_warehouse.fact_guide_assignment f
        WHERE f.lin_business_hash = MD5(COALESCE(s.contact_id, ''))
    );
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.etl_load_fact_guide_assignment() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_warehouse.etl_load_fact_guide_assignment() TO service_role;


-- ===== 20260611144505_google_user_default_role.sql =====
-- Auto-assign new Google OAuth users to the CAMFED Staff role.
-- Invite-flow and WhatsApp users are unaffected (their provider is 'email').
-- Permissions for CAMFED Staff are managed via the admin roles UI.

-- 1. Ensure CAMFED Staff role exists
INSERT INTO rep_portal.roles (name, description)
VALUES ('CAMFED Staff', 'Default role for staff signing in via Google')
ON CONFLICT (name) DO NOTHING;

-- 2. Trigger function
CREATE OR REPLACE FUNCTION rep_portal.assign_google_user_role()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = rep_portal, public
AS $$
BEGIN
  IF NEW.raw_app_meta_data->>'provider' = 'google' THEN
    INSERT INTO rep_portal.user_roles (user_id, role_id)
    SELECT NEW.id, r.id
    FROM rep_portal.roles r
    WHERE r.name = 'CAMFED Staff'
    ON CONFLICT DO NOTHING;
  END IF;
  RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.assign_google_user_role() FROM PUBLIC;

-- 3. Trigger on auth.users
DROP TRIGGER IF EXISTS trg_assign_google_user_role ON auth.users;
CREATE TRIGGER trg_assign_google_user_role
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION rep_portal.assign_google_user_role();

