-- ============================================================================
-- Demo seed 4/4 - open (anonymous) read access
--
-- !! DEMO PROJECT ONLY (gpyetojuzngrfrtcoycj) !!
--
-- Never run this against the production warehouse. It deliberately makes the
-- read RPCs callable by the `anon` role and removes the country default-deny
-- for unauthenticated callers, which is only acceptable because every row in
-- the demo project is fabricated by 01-03.
--
-- These changes are NOT migrations. `supabase db push` will not remove them,
-- but a later migration that redefines caller_allowed_countries() will
-- overwrite the override below -- re-run this file after any such push.
-- ============================================================================

BEGIN;

-- 1. Let the anon role reach the schema at all.
GRANT USAGE ON SCHEMA rep_portal TO anon;

-- 2. Country scoping: unauthenticated demo viewers are treated as unrestricted.
--
-- Production behaviour (kept intact for signed-in users): NULL = unrestricted,
-- '{}' = default-deny, {..} = explicit allow-list. The only change is the new
-- first branch, which would be a serious data leak on a project holding real
-- programme data and is safe here only because the data is invented.
CREATE OR REPLACE FUNCTION rep_portal.caller_allowed_countries()
RETURNS text[] LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT CASE
    WHEN auth.uid() IS NULL THEN NULL          -- DEMO ONLY: anonymous = unrestricted
    WHEN (auth.jwt()->'app_metadata'->>'role') = 'admin' THEN NULL
    WHEN (auth.jwt()->>'role') = 'service_role' THEN NULL
    ELSE COALESCE(
      (SELECT array_agg(country) FROM rep_portal.user_countries WHERE user_id = auth.uid()),
      ARRAY[]::text[]
    )
  END
$$;

GRANT EXECUTE ON FUNCTION rep_portal.caller_allowed_countries() TO anon;

-- 3. Grant EXECUTE on the read-only RPCs the demo pages call.
--
-- Explicit allow-list, not a blanket grant on the schema: rep_portal also holds
-- admin and mutating functions (set_user_countries, kpi_delete_year, admin_*,
-- the upload RPCs) which must stay unreachable by anon. Names are matched
-- against pg_proc, so entries that do not exist in this project are skipped
-- rather than raising, and overloads are all covered.
DO $$
DECLARE
  r record;
  v_allow text[] := ARRAY[
    -- Data Dashboard
    'get_dashlet_data', 'get_observed_kpi', 'get_dashboard_data_scoped',
    'get_main_dashboard_dashlets', 'get_dashboards', 'get_kpi_dashlet_data',
    'get_kpi_dashlet_milestones', 'get_salesforce_dashlet_data',
    'get_dashlet_targets', 'get_dashlet_comments',
    -- Shared metadata
    'get_dashboard_metadata', 'get_available_countries', 'get_loaded_years',
    'get_kpi_definitions', 'get_my_permissions', 'get_my_countries',
    -- Dynamic Data
    'get_dashboard_data_filtered',
    -- Map
    'get_district_kpi_data', 'get_school_point_data',
    -- KPI Report / Trends
    'kpi_report_years', 'kpi_report_groups', 'kpi_report_indicators',
    'kpi_report_all_groups', 'kpi_report_all_indicators',
    'kpi_report_indicator_detail', 'kpi_report_indicator_trend',
    'kpi_report_indicator_trend_all_countries',
    -- KPI Milestones
    'kpi_milestone_years', 'kpi_milestone_groups', 'kpi_milestone_indicators',
    'kpi_milestone_report',
    -- Salesforce Report
    'get_report_catalog', 'get_report_pivot', 'get_report_dimension_values'
  ];
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p
    JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'rep_portal'
      AND p.proname = ANY(v_allow)
  LOOP
    EXECUTE format('GRANT EXECUTE ON FUNCTION %s TO anon', r.sig);
  END LOOP;
END $$;

COMMIT;

-- What anon can now call. Anything unexpected in this list should be revoked.
SELECT p.proname, pg_get_function_identity_arguments(p.oid) AS args
FROM pg_proc p
JOIN pg_namespace n ON n.oid = p.pronamespace
WHERE n.nspname = 'rep_portal'
  AND has_function_privilege('anon', p.oid, 'EXECUTE')
ORDER BY p.proname;
