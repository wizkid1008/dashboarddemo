-- Schema chunk 2 - run only after the previous chunk succeeded.
-- Generated from supabase/migrations in filename order. Do not reorder.


-- ===== 20250201000029_rep_portal_api_layer.sql =====
-- Consolidate all PostgREST access through rep_portal.
-- SECURITY DEFINER functions here read from rep_warehouse and rep_raw so those
-- schemas no longer need to be exposed directly via PostgREST.
-- After this migration, only rep_portal (and graphql_public) need to be in
-- config.toml [api] schemas.

-- ── Move dashboard_data_agg into rep_portal ───────────────────────────────────

DROP MATERIALIZED VIEW IF EXISTS public.dashboard_data_agg;

CREATE MATERIALIZED VIEW rep_portal.dashboard_data_agg AS

WITH valid_countries AS (
  SELECT DISTINCT country
  FROM rep_warehouse.view_observed_kpi
  WHERE country IS NOT NULL
)

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Newly supported'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Annual'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Annual'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Cumulative 2020-2030'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Cumulative (2020-2030)'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Cumulative all-time'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Cumulative (all-time)'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Learner Guides'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_type = 'Learner Guide' AND v.guide_status = 'Active' AND v.school_name IS NOT NULL
GROUP BY v.country, v.district, v.school_name

UNION ALL

SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form — Girls'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.gender = 'Female'
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form — Boys'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.gender = 'Male'
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Active Partner Schools'::text AS metric,
       COUNT(DISTINCT v.school_name)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Number of Women Supported by CAMFED in Tertiary Education'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_post_school_support v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Guides by Type'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_status = 'Active' AND v.school_name IS NOT NULL
GROUP BY v.country, v.district, v.school_name

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Number of Post School Clients'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_post_school_support v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.grant_year AS year,
       'Grants Disbursed'::text AS metric,
       ROUND(SUM(v.amount_given::numeric))::int AS value
FROM rep_warehouse.view_grants v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.grant_year IS NOT NULL
GROUP BY v.country, v.district, v.grant_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed'::text AS metric,
       ROUND(SUM(COALESCE(v.loan_value, 0)))::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'CAMA Members'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school by CAMA'
  AND disaggregation_level_one = 'Newly supported'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Community Champions'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school through community initiatives'
  AND disaggregation_level_one = 'Newly supported'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Guides — Transition'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_status = 'Active' AND v.school_name IS NOT NULL
  AND v.guide_type ILIKE '%Transition%'
GROUP BY v.country, v.district, v.school_name

UNION ALL

SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Guides — Agriculture'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_status = 'Active' AND v.school_name IS NOT NULL
  AND v.guide_type ILIKE '%Agri%'
GROUP BY v.country, v.district, v.school_name

UNION ALL

SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Guides — Business'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_status = 'Active' AND v.school_name IS NOT NULL
  AND (v.guide_type ILIKE '%Business%' OR v.guide_type ILIKE '%Enterprise%')
GROUP BY v.country, v.district, v.school_name

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.grant_year AS year,
       'Grants Distributed — Count'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_grants v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.grant_year IS NOT NULL
GROUP BY v.country, v.district, v.grant_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Agriculture'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%Agri%'
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Business'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL
  AND (v.loan_type ILIKE '%Business%' OR v.loan_type ILIKE '%Enterprise%')
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Kiva'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%Kiva%'
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — RIF'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%RIF%'
GROUP BY v.country, v.district, v.disbursal_year

WITH NO DATA;

REFRESH MATERIALIZED VIEW rep_portal.dashboard_data_agg;

-- ── Public data functions (anon + authenticated) ──────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.get_dashboard_data()
RETURNS json LANGUAGE sql SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT json_build_object('data', json_agg(r))
  FROM (SELECT * FROM rep_portal.dashboard_data_agg) r;
$$;

CREATE OR REPLACE FUNCTION rep_portal.get_observed_kpi(p_kpi_id TEXT)
RETURNS TABLE (
  country                  TEXT,
  kpi_id                   TEXT,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  year                     INTEGER,
  value                    TEXT
) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
  SELECT v.country, v.kpi_id, v.disaggregation_level_one,
         v.disaggregation_level_two, v.year, v.value
  FROM rep_warehouse.view_observed_kpi v
  WHERE v.kpi_id = p_kpi_id
    AND v.year IS NOT NULL
    AND v.country IS NOT NULL;
$$;

CREATE OR REPLACE FUNCTION rep_portal.get_district_kpi_data()
RETURNS TABLE (
  id                TEXT,
  country_slug      TEXT,
  country_name      TEXT,
  district_name     TEXT,
  program_count     INT,
  beneficiary_count INT,
  risk_score        NUMERIC,
  kpis              JSONB
) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
WITH valid_countries AS (
  SELECT DISTINCT country
  FROM rep_warehouse.view_observed_kpi
  WHERE country IS NOT NULL
    AND country IN ('Tanzania', 'Ghana', 'Malawi', 'Zambia', 'Zimbabwe')
),
all_districts AS (
  SELECT DISTINCT g.country, g.district
  FROM rep_warehouse.dim_geography g
  JOIN valid_countries vc ON vc.country = g.country
  WHERE g.district IS NOT NULL AND g.scd_is_current = true
),
children_by_district AS (
  SELECT g.country, g.district, COUNT(*) AS total
  FROM rep_warehouse.fact_children_supported f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
guides_by_district AS (
  SELECT
    g.country, g.district,
    COUNT(*) FILTER (WHERE f.guide_type ILIKE '%Learner%'    AND f.guide_status ILIKE '%Active%') AS learner,
    COUNT(*) FILTER (WHERE f.guide_type ILIKE '%Transition%' AND f.guide_status ILIKE '%Active%') AS transition,
    COUNT(*) FILTER (WHERE f.guide_type ILIKE '%Agri%'       AND f.guide_status ILIKE '%Active%') AS agriculture,
    COUNT(*) FILTER (WHERE f.guide_type ILIKE '%Business%'   AND f.guide_status ILIKE '%Active%') AS business
  FROM rep_warehouse.fact_guide_assignment f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
cama_by_district AS (
  SELECT g.country, g.district, COUNT(*) AS total
  FROM rep_warehouse.fact_cama_membership f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
grants_by_district AS (
  SELECT
    g.country, g.district,
    COUNT(*)                                     AS grant_count,
    ROUND(SUM(COALESCE(f.amount_given, 0)))::int AS grant_value
  FROM rep_warehouse.fact_grants f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
loans_by_district AS (
  SELECT
    g.country, g.district,
    COUNT(*)                                   AS loan_count,
    ROUND(SUM(COALESCE(f.loan_value, 0)))::int AS loan_value
  FROM rep_warehouse.fact_loans f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
post_school_by_district AS (
  SELECT g.country, g.district, COUNT(*) AS total
  FROM rep_warehouse.fact_post_school_support f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
schools_by_district AS (
  SELECT
    g.country, g.district,
    COUNT(*) FILTER (WHERE s.active_partner_school = true) AS active_partner_schools
  FROM rep_warehouse.dim_school s
  JOIN rep_warehouse.dim_geography g ON g.id = s.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL AND s.scd_is_current = true
  GROUP BY g.country, g.district
)
SELECT
  lower(replace(d.country, ' ', '-')) || '::' || lower(d.district) AS id,
  lower(replace(d.country, ' ', '-'))                               AS country_slug,
  d.country                                                         AS country_name,
  d.district                                                        AS district_name,
  COALESCE(cs.total, 0)::int                                        AS program_count,
  COALESCE(cs.total, 0)::int                                        AS beneficiary_count,
  0::numeric                                                        AS risk_score,
  jsonb_build_object(
    'education_bursaries_children',  COALESCE(cs.total, 0),
    'clients_by_form',               COALESCE(cs.total, 0),
    'active_learner_guides',         COALESCE(ga.learner,      0),
    'active_guides_transition',      COALESCE(ga.transition,   0),
    'active_guides_agriculture',     COALESCE(ga.agriculture,  0),
    'active_guides_business',        COALESCE(ga.business,     0),
    'active_guides_by_type',
      COALESCE(ga.learner, 0) + COALESCE(ga.transition, 0)
      + COALESCE(ga.agriculture, 0) + COALESCE(ga.business, 0),
    'cama_members',                  COALESCE(cam.total, 0),
    'grants_disbursed',              COALESCE(gr.grant_value, 0),
    'grants_distributed_count',      COALESCE(gr.grant_count, 0),
    'loans_disbursed',               COALESCE(lo.loan_value, 0),
    'post_school_clients',           COALESCE(ps.total, 0),
    'active_partner_schools',        COALESCE(sc.active_partner_schools, 0)
  ) AS kpis
FROM all_districts d
LEFT JOIN children_by_district    cs  ON cs.country  = d.country AND cs.district  = d.district
LEFT JOIN guides_by_district      ga  ON ga.country  = d.country AND ga.district  = d.district
LEFT JOIN cama_by_district        cam ON cam.country = d.country AND cam.district = d.district
LEFT JOIN grants_by_district      gr  ON gr.country  = d.country AND gr.district  = d.district
LEFT JOIN loans_by_district       lo  ON lo.country  = d.country AND lo.district  = d.district
LEFT JOIN post_school_by_district ps  ON ps.country  = d.country AND ps.district  = d.district
LEFT JOIN schools_by_district     sc  ON sc.country  = d.country AND sc.district  = d.district;
$$;

CREATE OR REPLACE FUNCTION rep_portal.get_school_point_data()
RETURNS TABLE (
  school_id     TEXT,
  school_name   TEXT,
  country_slug  TEXT,
  country_name  TEXT,
  district_name TEXT,
  province      TEXT,
  geo_source    TEXT,
  latitude      NUMERIC,
  longitude     NUMERIC,
  kpis          JSONB
) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
WITH
cs_by_school AS (
  SELECT
    f.school_id,
    COUNT(*)                                        AS total,
    COUNT(*) FILTER (WHERE ct.gender = 'Female')    AS girls,
    COUNT(*) FILTER (WHERE ct.gender = 'Male')      AS boys
  FROM rep_warehouse.fact_children_supported f
  LEFT JOIN rep_warehouse.dim_contact ct ON ct.id = f.contact_id
  WHERE f.school_id IS NOT NULL
  GROUP BY f.school_id
),
guides_by_school AS (
  SELECT
    school_id,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Learner%'    AND guide_status ILIKE '%Active%') AS learner,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Transition%' AND guide_status ILIKE '%Active%') AS transition,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Agri%'       AND guide_status ILIKE '%Active%') AS agriculture,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Business%'   AND guide_status ILIKE '%Active%') AS business
  FROM rep_warehouse.fact_guide_assignment
  WHERE school_id IS NOT NULL
  GROUP BY school_id
),
cama_by_school AS (
  SELECT school_id, COUNT(*) AS total
  FROM rep_warehouse.fact_cama_membership
  WHERE school_id IS NOT NULL
  GROUP BY school_id
)
SELECT
  s.source_school_id::text                  AS school_id,
  s.school_name,
  lower(replace(g.country, ' ', '-'))       AS country_slug,
  g.country                                 AS country_name,
  g.district                                AS district_name,
  g.province,
  'warehouse'                               AS geo_source,
  s.latitude,
  s.longitude,
  jsonb_build_object(
    'education_bursaries_children',  COALESCE(cs.total, 0),
    'clients_by_form',               COALESCE(cs.total, 0),
    'clients_by_form_girls',         COALESCE(cs.girls, 0),
    'clients_by_form_boys',          COALESCE(cs.boys,  0),
    'active_learner_guides',         COALESCE(ga.learner,      0),
    'active_guides_transition',      COALESCE(ga.transition,   0),
    'active_guides_agriculture',     COALESCE(ga.agriculture,  0),
    'active_guides_business',        COALESCE(ga.business,     0),
    'active_guides_by_type',
      COALESCE(ga.learner, 0) + COALESCE(ga.transition, 0)
      + COALESCE(ga.agriculture, 0) + COALESCE(ga.business, 0),
    'cama_members',                  COALESCE(cam.total, 0),
    'active_partner_schools',        CASE WHEN s.active_partner_school THEN 1 ELSE 0 END
  ) AS kpis
FROM rep_warehouse.dim_school s
JOIN  rep_warehouse.dim_geography g
      ON  g.id = s.geography_id AND g.scd_is_current = true
LEFT JOIN cs_by_school    cs  ON cs.school_id  = s.id
LEFT JOIN guides_by_school ga  ON ga.school_id  = s.id
LEFT JOIN cama_by_school   cam ON cam.school_id = s.id
WHERE s.scd_is_current = true
  AND s.latitude  IS NOT NULL
  AND s.longitude IS NOT NULL
  AND g.country IN ('Tanzania', 'Ghana', 'Malawi', 'Zambia', 'Zimbabwe');
$$;

GRANT EXECUTE ON FUNCTION rep_portal.get_dashboard_data()        TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_observed_kpi(TEXT)      TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_district_kpi_data()     TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_school_point_data()     TO authenticated;

-- ── Admin functions (authenticated only, admin-gated internally) ──────────────

CREATE OR REPLACE FUNCTION rep_portal.get_ingest_runs()
RETURNS TABLE (
  run_id          TEXT,
  status          TEXT,
  since           TIMESTAMPTZ,
  started_by      TEXT,
  current_wave    INTEGER,
  attempt_count   INTEGER,
  lease_expires_at TIMESTAMPTZ,
  started_at      TIMESTAMPTZ,
  finished_at     TIMESTAMPTZ,
  error           TEXT
) LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin privileges required';
  END IF;
  RETURN QUERY
    SELECT r.run_id, r.status, r.since, r.started_by, r.current_wave,
           r.attempt_count, r.lease_expires_at, r.started_at, r.finished_at, r.error
    FROM rep_warehouse.ingest_run r
    ORDER BY r.started_at DESC
    LIMIT 20;
END;
$$;

CREATE OR REPLACE FUNCTION rep_portal.get_ingest_fn_state(p_run_id TEXT)
RETURNS TABLE (
  fn_name       TEXT,
  status        TEXT,
  rows_fetched  INTEGER,
  attempt_count INTEGER,
  cursor        TEXT
) LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin privileges required';
  END IF;
  RETURN QUERY
    SELECT s.fn_name, s.status, s.rows_fetched, s.attempt_count, s.cursor
    FROM rep_warehouse.ingest_fn_state s
    WHERE s.run_id = p_run_id
    ORDER BY s.fn_name;
END;
$$;

CREATE OR REPLACE FUNCTION rep_portal.get_etl_batch_log()
RETURNS TABLE (
  batch_id      TEXT,
  status        TEXT,
  source_system TEXT,
  started_at    TIMESTAMPTZ,
  finished_at   TIMESTAMPTZ,
  error_message TEXT
) LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin privileges required';
  END IF;
  RETURN QUERY
    SELECT l.batch_id, l.status, l.source_system, l.started_at, l.finished_at, l.error_message
    FROM rep_warehouse.etl_batch_log l
    ORDER BY l.started_at DESC
    LIMIT 50;
END;
$$;

CREATE OR REPLACE FUNCTION rep_portal.get_etl_batch_log_entry(p_batch_id TEXT)
RETURNS TABLE (
  batch_id      TEXT,
  status        TEXT,
  source_system TEXT,
  started_at    TIMESTAMPTZ,
  finished_at   TIMESTAMPTZ,
  error_message TEXT
) LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin privileges required';
  END IF;
  RETURN QUERY
    SELECT l.batch_id, l.status, l.source_system, l.started_at, l.finished_at, l.error_message
    FROM rep_warehouse.etl_batch_log l
    WHERE l.batch_id = p_batch_id;
END;
$$;

CREATE OR REPLACE FUNCTION rep_portal.get_upload_log()
RETURNS TABLE (
  batch_id        TEXT,
  year            INTEGER,
  row_count       INTEGER,
  rows_loaded     INTEGER,
  rows_unmatched  INTEGER,
  rows_duplicate  INTEGER,
  status          TEXT,
  uploaded_by     TEXT,
  source_file     TEXT,
  inserted_at     TIMESTAMPTZ,
  error_msg       TEXT
) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_raw, public
AS $$
  SELECT batch_id, year, row_count, rows_loaded, rows_unmatched, rows_duplicate,
         status, uploaded_by, source_file, inserted_at, error_msg
  FROM rep_raw.upload_log
  ORDER BY inserted_at DESC
  LIMIT 30;
$$;

CREATE OR REPLACE FUNCTION rep_portal.get_level_one_upload_log()
RETURNS TABLE (
  batch_id    TEXT,
  rows_added  INTEGER,
  rows_updated INTEGER,
  total_rows  INTEGER,
  status      TEXT,
  uploaded_by TEXT,
  source_file TEXT,
  inserted_at TIMESTAMPTZ,
  error_msg   TEXT
) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_raw, public
AS $$
  SELECT batch_id, rows_added, rows_updated, total_rows,
         status, uploaded_by, source_file, inserted_at, error_msg
  FROM rep_raw.level_one_upload_log
  ORDER BY inserted_at DESC
  LIMIT 30;
$$;

CREATE OR REPLACE FUNCTION rep_portal.get_duplicate_rows(p_batch_id TEXT)
RETURNS TABLE (
  kpi_id                   TEXT,
  kpi_group                TEXT,
  year                     INTEGER,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  row_scope                TEXT,
  occurrences              INTEGER,
  row_ids                  TEXT[]
) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_raw, public
AS $$
  SELECT kpi_id, kpi_group, year, disaggregation_level_one, disaggregation_level_two,
         row_scope, occurrences, row_ids
  FROM rep_raw.duplicate_rows
  WHERE batch_id = p_batch_id
  ORDER BY kpi_id;
$$;

CREATE OR REPLACE FUNCTION rep_portal.get_loaded_years()
RETURNS TABLE (
  year          INTEGER,
  rows_loaded   INTEGER,
  rows_duplicate INTEGER,
  uploaded_by   TEXT,
  source_file   TEXT,
  inserted_at   TIMESTAMPTZ
) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_raw, public
AS $$
  SELECT DISTINCT ON (year)
    year, rows_loaded, rows_duplicate, uploaded_by, source_file, inserted_at
  FROM rep_raw.upload_log
  WHERE status = 'SUCCESS'
  ORDER BY year DESC, inserted_at DESC;
$$;

CREATE OR REPLACE FUNCTION rep_portal.check_upload_exists(p_year INTEGER)
RETURNS TABLE (inserted_at TIMESTAMPTZ, uploaded_by TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_raw, public
AS $$
  SELECT inserted_at, uploaded_by
  FROM rep_raw.upload_log
  WHERE year = p_year AND status = 'SUCCESS'
  ORDER BY inserted_at DESC
  LIMIT 1;
$$;

-- KPI functions: thin wrappers that delegate to rep_warehouse
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
  ghana           TEXT,
  malawi          TEXT,
  tanzania        TEXT,
  zambia          TEXT,
  zimbabwe        TEXT,
  total           TEXT,
  updated_date    TEXT
) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_raw, public
AS $$
  SELECT * FROM rep_warehouse.get_all_kpi_rows(p_year, p_limit, p_offset);
$$;

CREATE OR REPLACE FUNCTION rep_portal.count_all_kpi_rows(p_year INTEGER)
RETURNS BIGINT LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_raw, public
AS $$
  SELECT rep_warehouse.count_all_kpi_rows(p_year);
$$;

CREATE OR REPLACE FUNCTION rep_portal.kpi_delete_year(p_year INTEGER)
RETURNS JSONB LANGUAGE sql SECURITY DEFINER
SET search_path = rep_warehouse, rep_raw, public
AS $$
  SELECT rep_warehouse.kpi_delete_year(p_year);
$$;

GRANT EXECUTE ON FUNCTION rep_portal.get_ingest_runs()                                 TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_ingest_fn_state(TEXT)                         TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_etl_batch_log()                               TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_etl_batch_log_entry(TEXT)                     TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_upload_log()                                  TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_level_one_upload_log()                        TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_duplicate_rows(TEXT)                          TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_loaded_years()                                TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.check_upload_exists(INTEGER)                      TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_all_kpi_rows(INTEGER, INTEGER, INTEGER)       TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.count_all_kpi_rows(INTEGER)                       TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_delete_year(INTEGER)                          TO authenticated;

-- ── Revoke and drop old public functions (safe if they don't exist) ──────────

DO $$ BEGIN
  IF EXISTS (SELECT 1 FROM pg_matviews WHERE schemaname = 'public' AND matviewname = 'dashboard_data_agg') THEN
    REVOKE SELECT ON public.dashboard_data_agg FROM anon, authenticated;
    DROP MATERIALIZED VIEW public.dashboard_data_agg;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'get_dashboard_data') THEN
    REVOKE EXECUTE ON FUNCTION public.get_dashboard_data() FROM anon, authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'get_observed_kpi') THEN
    REVOKE EXECUTE ON FUNCTION public.get_observed_kpi(TEXT) FROM anon, authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'get_district_kpi_data') THEN
    REVOKE EXECUTE ON FUNCTION public.get_district_kpi_data() FROM anon, authenticated;
  END IF;
  IF EXISTS (SELECT 1 FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'public' AND p.proname = 'get_school_point_data') THEN
    REVOKE EXECUTE ON FUNCTION public.get_school_point_data() FROM anon, authenticated;
  END IF;
END $$;

DROP FUNCTION IF EXISTS public.get_dashboard_data();
DROP FUNCTION IF EXISTS public.get_observed_kpi(TEXT);
DROP FUNCTION IF EXISTS public.get_district_kpi_data();
DROP FUNCTION IF EXISTS public.get_school_point_data();


-- ===== 20250201000030_whatsapp_views_security_invoker.sql =====
-- Recreate WhatsApp analytics views with security_invoker = on.
-- Without this, views run as their creator (SECURITY DEFINER by default),
-- bypassing the admin-only RLS on whatsapp_events. With security_invoker,
-- RLS is enforced on the querying user — non-admins get empty results.

CREATE OR REPLACE VIEW rep_portal.view_wa_daily
WITH (security_invoker = on) AS
SELECT
  (occurred_at AT TIME ZONE 'UTC')::date          AS day,
  COUNT(DISTINCT phone_hash)                       AS unique_users,
  COUNT(*)                                         AS total_events,
  COUNT(*) FILTER (WHERE outcome = 'completed')    AS completions,
  COUNT(*) FILTER (WHERE outcome = 'error')        AS errors
FROM rep_portal.whatsapp_events
WHERE occurred_at >= now() - INTERVAL '60 days'
GROUP BY 1
ORDER BY 1 DESC;

GRANT SELECT ON rep_portal.view_wa_daily TO authenticated;

CREATE OR REPLACE VIEW rep_portal.view_wa_flow_summary
WITH (security_invoker = on) AS
SELECT
  flow,
  COUNT(DISTINCT phone_hash)                          AS unique_users,
  COUNT(*) FILTER (WHERE from_step = 'idle')          AS started,
  COUNT(*) FILTER (WHERE outcome = 'completed')       AS completed,
  COUNT(*) FILTER (WHERE outcome = 'abandoned')       AS abandoned,
  COUNT(*) FILTER (WHERE outcome = 'error')           AS errors,
  ROUND(
    100.0
      * COUNT(*) FILTER (WHERE outcome = 'completed')
      / NULLIF(COUNT(*) FILTER (WHERE from_step = 'idle'), 0),
    1
  ) AS completion_pct
FROM rep_portal.whatsapp_events
WHERE occurred_at >= now() - INTERVAL '30 days'
GROUP BY flow
ORDER BY started DESC NULLS LAST;

GRANT SELECT ON rep_portal.view_wa_flow_summary TO authenticated;

CREATE OR REPLACE VIEW rep_portal.view_wa_funnel
WITH (security_invoker = on) AS
SELECT
  flow,
  to_step                     AS step,
  COUNT(*)                    AS entries,
  COUNT(DISTINCT phone_hash)  AS unique_users
FROM rep_portal.whatsapp_events
WHERE occurred_at >= now() - INTERVAL '30 days'
GROUP BY flow, to_step
ORDER BY flow, entries DESC;

GRANT SELECT ON rep_portal.view_wa_funnel TO authenticated;

CREATE OR REPLACE VIEW rep_portal.view_wa_errors
WITH (security_invoker = on) AS
SELECT id, flow, from_step, to_step, occurred_at
FROM rep_portal.whatsapp_events
WHERE outcome = 'error'
ORDER BY occurred_at DESC
LIMIT 100;

GRANT SELECT ON rep_portal.view_wa_errors TO authenticated;


-- ===== 20250201000031_rep_warehouse_views_security_invoker.sql =====
-- Add security_invoker = on to all rep_warehouse views.
-- Views called from SECURITY DEFINER functions still run as postgres (current_user
-- inside those functions), so behaviour is unchanged. Direct access by non-superuser
-- roles would be subject to RLS, providing defence-in-depth.

CREATE OR REPLACE VIEW rep_warehouse.view_children_supported
WITH (security_invoker = on) AS
SELECT
    f.id,
    f.source_contact_id,
    ct.gender,
    ct.wg_difficulty_overall,
    dd.date_value                   AS year_date,
    dd.year                         AS year,
    dd.month                        AS year_month,
    dd.month_name                   AS year_month_name,
    dd.quarter                      AS year_quarter,
    f.form,
    f.contact_record_type,
    f.attendance_issues,
    f.received_financial_support,
    f.repeated,
    d3.name                         AS donor_name,
    d3.reporting_code               AS donor_code,
    d2.name                         AS project_code_name,
    d2.reporting_code               AS project_code,
    s.school_name,
    g.district,
    g.province,
    g.country
FROM rep_warehouse.fact_children_supported f
LEFT JOIN rep_warehouse.dim_contact         ct ON ct.id = f.contact_id
LEFT JOIN rep_warehouse.dim_school           s  ON  s.id = f.school_id
LEFT JOIN rep_warehouse.dim_geography        g  ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date            dd  ON dd.id = f.year_date_id
LEFT JOIN rep_warehouse.dim_roc_donor       d3  ON d3.id = f.roc_donor_id
LEFT JOIN rep_warehouse.dim_roc_project_code d2 ON d2.id = f.roc_project_code_id;


CREATE OR REPLACE VIEW rep_warehouse.view_guide_assignment
WITH (security_invoker = on) AS
SELECT
    f.id,
    f.source_contact_id,
    ct.gender,
    ct.wg_difficulty_overall,
    f.date_joined_guide_programme,
    joined_dd.year                  AS joined_year,
    joined_dd.month                 AS joined_month,
    joined_dd.month_name            AS joined_month_name,
    joined_dd.quarter               AS joined_quarter,
    f.date_left_guide_programme,
    left_dd.year                    AS left_year,
    left_dd.month                   AS left_month,
    left_dd.month_name              AS left_month_name,
    left_dd.quarter                 AS left_quarter,
    f.guide_type,
    f.guide_status,
    f.guide_specialty,
    f.guide_dropout_reason,
    f.trained_in_climate_education,
    d3.name                         AS donor_name,
    d3.reporting_code               AS donor_code,
    s.school_name,
    g.district,
    g.province,
    g.country
FROM rep_warehouse.fact_guide_assignment f
LEFT JOIN rep_warehouse.dim_contact  ct       ON ct.id = f.contact_id
LEFT JOIN rep_warehouse.dim_school    s        ON  s.id = f.school_id
LEFT JOIN rep_warehouse.dim_geography g        ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date      joined_dd ON joined_dd.id = f.date_joined_id
LEFT JOIN rep_warehouse.dim_date      left_dd   ON left_dd.id   = f.date_left_id
LEFT JOIN rep_warehouse.dim_roc_donor d3        ON d3.id = f.roc_donor_id;


CREATE OR REPLACE VIEW rep_warehouse.view_cama_membership
WITH (security_invoker = on) AS
SELECT
    f.id,
    f.source_contact_id,
    ct.gender,
    ct.wg_difficulty_overall,
    f.date_joined_cama,
    dd.year                         AS join_year,
    dd.month                        AS join_month,
    dd.month_name                   AS join_month_name,
    dd.quarter                      AS join_quarter,
    f.partner_school,
    s.school_name,
    g.district,
    g.province,
    g.country
FROM rep_warehouse.fact_cama_membership f
LEFT JOIN rep_warehouse.dim_contact  ct ON ct.id = f.contact_id
LEFT JOIN rep_warehouse.dim_school    s  ON  s.id = f.school_id
LEFT JOIN rep_warehouse.dim_geography g  ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = f.date_joined_id;


CREATE OR REPLACE VIEW rep_warehouse.view_post_school_support
WITH (security_invoker = on) AS
SELECT
    f.id,
    f.source_contact_id,
    ct.gender,
    ct.wg_difficulty_overall,
    dd.date_value                   AS year_date,
    dd.year                         AS year,
    dd.month                        AS year_month,
    dd.month_name                   AS year_month_name,
    dd.quarter                      AS year_quarter,
    f.received_financial_support,
    f.accommodation,
    f.form,
    d3.name                         AS donor_name,
    d3.reporting_code               AS donor_code,
    g.district,
    g.province,
    g.country
FROM rep_warehouse.fact_post_school_support f
LEFT JOIN rep_warehouse.dim_contact  ct ON ct.id = f.contact_id
LEFT JOIN rep_warehouse.dim_geography g  ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = f.year_date_id
LEFT JOIN rep_warehouse.dim_roc_donor d3 ON d3.id = f.roc_donor_id;


CREATE OR REPLACE VIEW rep_warehouse.view_grants
WITH (security_invoker = on) AS
SELECT
    f.id,
    f.source_grant_id,
    f.source_contact_id,
    ct.gender,
    ct.wg_difficulty_overall,
    f.grant_type,
    f.grant_status,
    f.amount_given,
    f.grant_date,
    dd.year                         AS grant_year,
    dd.month                        AS grant_month,
    dd.month_name                   AS grant_month_name,
    dd.quarter                      AS grant_quarter,
    d3.name                         AS donor_name,
    d3.reporting_code               AS donor_code,
    g.district,
    g.province,
    g.country
FROM rep_warehouse.fact_grants f
LEFT JOIN rep_warehouse.dim_contact  ct ON ct.id = f.contact_id
LEFT JOIN rep_warehouse.dim_geography g  ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = f.grant_date_id
LEFT JOIN rep_warehouse.dim_roc_donor d3 ON d3.id = f.roc_donor_id;


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
    g.country
FROM rep_warehouse.fact_loans f
LEFT JOIN rep_warehouse.dim_geography g  ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = f.disbursal_date_id
LEFT JOIN rep_warehouse.dim_roc_donor d3 ON d3.id = f.roc_donor_id;


CREATE OR REPLACE VIEW rep_warehouse.view_donor_summary
WITH (security_invoker = on) AS
SELECT
    d3.id                           AS donor_id,
    d3.name                         AS donor_name,
    d3.reporting_code               AS donor_code,
    d3.available_country,
    d3.active,
    d3.start_date                   AS donor_start_date,
    d3.end_date                     AS donor_end_date,
    COUNT(DISTINCT f_cs.id)         AS children_supported_count,
    COUNT(DISTINCT f_ga.id)         AS guides_count,
    COUNT(DISTINCT f_gr.id)         AS grants_count,
    COUNT(DISTINCT f_lo.id)         AS loans_count
FROM rep_warehouse.dim_roc_donor d3
LEFT JOIN rep_warehouse.fact_children_supported f_cs ON f_cs.roc_donor_id = d3.id
LEFT JOIN rep_warehouse.fact_guide_assignment   f_ga ON f_ga.roc_donor_id = d3.id
LEFT JOIN rep_warehouse.fact_grants             f_gr ON f_gr.roc_donor_id = d3.id
LEFT JOIN rep_warehouse.fact_loans              f_lo ON f_lo.roc_donor_id = d3.id
WHERE d3.scd_is_current = true
GROUP BY d3.id, d3.name, d3.reporting_code, d3.available_country, d3.active,
         d3.start_date, d3.end_date;


CREATE OR REPLACE VIEW rep_warehouse.view_school_map
WITH (security_invoker = on) AS
SELECT
    s.id,
    s.source_school_id,
    s.school_name,
    s.school_type,
    s.latitude,
    s.longitude,
    s.active_on_bursary,
    s.active_partner_school,
    s.monitoring_school,
    s.gea_school,
    s.cpp_in_place,
    s.snf_only,
    d3.name                         AS donor_name,
    d3.reporting_code               AS donor_code,
    g.district,
    g.province,
    g.country,
    rg.name                         AS roc_geography_name,
    rg.reporting_code               AS roc_geography_code
FROM rep_warehouse.dim_school s
LEFT JOIN rep_warehouse.dim_geography     g  ON g.id  = s.geography_id  AND g.scd_is_current = true
LEFT JOIN rep_warehouse.dim_roc_donor     d3 ON d3.id = s.roc_donor_id  AND d3.scd_is_current = true
LEFT JOIN rep_warehouse.dim_roc_geography rg ON rg.id = g.roc_geography_id AND rg.scd_is_current = true
WHERE s.scd_is_current = true
  AND s.latitude IS NOT NULL
  AND s.longitude IS NOT NULL;


CREATE OR REPLACE VIEW rep_warehouse.view_observed_kpi
WITH (security_invoker = on) AS
SELECT
    f.id,
    k.source_kpi_id                 AS kpi_id,
    k.kpi_group,
    k.indicator,
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
    g.country
FROM rep_warehouse.fact_observed_kpi f
LEFT JOIN rep_warehouse.dim_kpi      k  ON  k.id = f.kpi_id
LEFT JOIN rep_warehouse.dim_geography g  ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = f.year_date_id;


CREATE OR REPLACE VIEW rep_warehouse.view_kpi_counts
WITH (security_invoker = on) AS
SELECT
    id, kpi_id, kpi_group, indicator,
    disaggregation_level_one, disaggregation_level_two,
    row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric END AS value
FROM rep_warehouse.view_observed_kpi
WHERE value_type = 'Count'
  AND row_scope  = 'ANNUAL';

CREATE OR REPLACE VIEW rep_warehouse.view_kpi_percentages
WITH (security_invoker = on) AS
SELECT
    id, kpi_id, kpi_group, indicator,
    disaggregation_level_one, disaggregation_level_two,
    row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric * 100 END AS value_pct
FROM rep_warehouse.view_observed_kpi
WHERE value_type = 'Percentage'
  AND row_scope  = 'ANNUAL';

CREATE OR REPLACE VIEW rep_warehouse.view_kpi_targets
WITH (security_invoker = on) AS
SELECT
    id, kpi_id, kpi_group, indicator,
    disaggregation_level_one, disaggregation_level_two,
    value_type, row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric END AS value
FROM rep_warehouse.view_observed_kpi
WHERE row_scope = 'CUMULATIVE'
  AND disaggregation_level_one = 'Cumulative (2020-2030)';

CREATE OR REPLACE VIEW rep_warehouse.view_kpi_cumulative
WITH (security_invoker = on) AS
SELECT
    id, kpi_id, kpi_group, indicator,
    disaggregation_level_one, disaggregation_level_two,
    value_type, row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric END AS value
FROM rep_warehouse.view_observed_kpi
WHERE row_scope = 'CUMULATIVE'
  AND disaggregation_level_one IN ('Cumulative (all-time)', 'Cumulative');

CREATE OR REPLACE VIEW rep_warehouse.view_kpi_detail
WITH (security_invoker = on) AS
SELECT
    id, kpi_id, kpi_group, indicator,
    disaggregation_level_one, disaggregation_level_two,
    value_type, row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric END AS value
FROM rep_warehouse.view_observed_kpi
WHERE row_scope = 'DETAIL';

CREATE OR REPLACE VIEW rep_warehouse.view_kpi_subtotals
WITH (security_invoker = on) AS
SELECT
    id, kpi_id, kpi_group, indicator,
    disaggregation_level_one, disaggregation_level_two,
    value_type, row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric END AS value
FROM rep_warehouse.view_observed_kpi
WHERE row_scope = 'SUBTOTAL';

CREATE OR REPLACE VIEW rep_warehouse.view_kpi_benchmarks
WITH (security_invoker = on) AS
SELECT
    id, kpi_id, kpi_group, indicator,
    disaggregation_level_one, disaggregation_level_two,
    value_type, row_scope, lin_source_row_number,
    year_date, year, year_month, year_month_name, year_quarter,
    country, updated_date,
    CASE WHEN value ~ '^-?[0-9]*\.?[0-9]+$' THEN value::numeric END AS value
FROM rep_warehouse.view_observed_kpi
WHERE row_scope = 'BENCHMARK';

CREATE OR REPLACE VIEW rep_warehouse.view_level_one_kpis
WITH (security_invoker = on) AS
SELECT
    f.id,
    k.source_kpi_id                 AS kpi_id,
    k.kpi_group,
    k.indicator,
    f.school_level,
    f.annual_newly_supported,
    f.fund_type,
    f.gender,
    f.disaggregation_gender,
    dd.date_value                   AS year_date,
    dd.year                         AS year,
    dd.quarter                      AS year_quarter,
    f.value,
    g.country
FROM rep_warehouse.fact_level_one_kpis f
LEFT JOIN rep_warehouse.dim_kpi      k  ON  k.id = f.kpi_id
LEFT JOIN rep_warehouse.dim_geography g  ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = f.year_date_id;


-- ===== 20250201000032_map_functions_no_timeout.sql =====
-- Remove statement timeout on the two map aggregation functions.
-- These do full-table scans across multiple fact tables and regularly exceed
-- the PostgREST default timeout on large datasets.

CREATE OR REPLACE FUNCTION rep_portal.get_district_kpi_data()
RETURNS TABLE (
  id                TEXT,
  country_slug      TEXT,
  country_name      TEXT,
  district_name     TEXT,
  program_count     INT,
  beneficiary_count INT,
  risk_score        NUMERIC,
  kpis              JSONB
) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
SET statement_timeout = 0
AS $$
WITH valid_countries AS (
  SELECT DISTINCT country
  FROM rep_warehouse.view_observed_kpi
  WHERE country IS NOT NULL
    AND country IN ('Tanzania', 'Ghana', 'Malawi', 'Zambia', 'Zimbabwe')
),
all_districts AS (
  SELECT DISTINCT g.country, g.district
  FROM rep_warehouse.dim_geography g
  JOIN valid_countries vc ON vc.country = g.country
  WHERE g.district IS NOT NULL AND g.scd_is_current = true
),
children_by_district AS (
  SELECT g.country, g.district, COUNT(*) AS total
  FROM rep_warehouse.fact_children_supported f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
guides_by_district AS (
  SELECT
    g.country, g.district,
    COUNT(*) FILTER (WHERE f.guide_type ILIKE '%Learner%'    AND f.guide_status ILIKE '%Active%') AS learner,
    COUNT(*) FILTER (WHERE f.guide_type ILIKE '%Transition%' AND f.guide_status ILIKE '%Active%') AS transition,
    COUNT(*) FILTER (WHERE f.guide_type ILIKE '%Agri%'       AND f.guide_status ILIKE '%Active%') AS agriculture,
    COUNT(*) FILTER (WHERE f.guide_type ILIKE '%Business%'   AND f.guide_status ILIKE '%Active%') AS business
  FROM rep_warehouse.fact_guide_assignment f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
cama_by_district AS (
  SELECT g.country, g.district, COUNT(*) AS total
  FROM rep_warehouse.fact_cama_membership f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
grants_by_district AS (
  SELECT
    g.country, g.district,
    COUNT(*)                                     AS grant_count,
    ROUND(SUM(COALESCE(f.amount_given, 0)))::int AS grant_value
  FROM rep_warehouse.fact_grants f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
loans_by_district AS (
  SELECT
    g.country, g.district,
    COUNT(*)                                   AS loan_count,
    ROUND(SUM(COALESCE(f.loan_value, 0)))::int AS loan_value
  FROM rep_warehouse.fact_loans f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
post_school_by_district AS (
  SELECT g.country, g.district, COUNT(*) AS total
  FROM rep_warehouse.fact_post_school_support f
  JOIN rep_warehouse.dim_geography g ON g.id = f.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL
  GROUP BY g.country, g.district
),
schools_by_district AS (
  SELECT
    g.country, g.district,
    COUNT(*) FILTER (WHERE s.active_partner_school = true) AS active_partner_schools
  FROM rep_warehouse.dim_school s
  JOIN rep_warehouse.dim_geography g ON g.id = s.geography_id AND g.scd_is_current = true
  WHERE g.district IS NOT NULL AND s.scd_is_current = true
  GROUP BY g.country, g.district
)
SELECT
  lower(replace(d.country, ' ', '-')) || '::' || lower(d.district) AS id,
  lower(replace(d.country, ' ', '-'))                               AS country_slug,
  d.country                                                         AS country_name,
  d.district                                                        AS district_name,
  COALESCE(cs.total, 0)::int                                        AS program_count,
  COALESCE(cs.total, 0)::int                                        AS beneficiary_count,
  0::numeric                                                        AS risk_score,
  jsonb_build_object(
    'education_bursaries_children',  COALESCE(cs.total, 0),
    'clients_by_form',               COALESCE(cs.total, 0),
    'active_learner_guides',         COALESCE(ga.learner,      0),
    'active_guides_transition',      COALESCE(ga.transition,   0),
    'active_guides_agriculture',     COALESCE(ga.agriculture,  0),
    'active_guides_business',        COALESCE(ga.business,     0),
    'active_guides_by_type',
      COALESCE(ga.learner, 0) + COALESCE(ga.transition, 0)
      + COALESCE(ga.agriculture, 0) + COALESCE(ga.business, 0),
    'cama_members',                  COALESCE(cam.total, 0),
    'grants_disbursed',              COALESCE(gr.grant_value, 0),
    'grants_distributed_count',      COALESCE(gr.grant_count, 0),
    'loans_disbursed',               COALESCE(lo.loan_value, 0),
    'post_school_clients',           COALESCE(ps.total, 0),
    'active_partner_schools',        COALESCE(sc.active_partner_schools, 0)
  ) AS kpis
FROM all_districts d
LEFT JOIN children_by_district    cs  ON cs.country  = d.country AND cs.district  = d.district
LEFT JOIN guides_by_district      ga  ON ga.country  = d.country AND ga.district  = d.district
LEFT JOIN cama_by_district        cam ON cam.country = d.country AND cam.district = d.district
LEFT JOIN grants_by_district      gr  ON gr.country  = d.country AND gr.district  = d.district
LEFT JOIN loans_by_district       lo  ON lo.country  = d.country AND lo.district  = d.district
LEFT JOIN post_school_by_district ps  ON ps.country  = d.country AND ps.district  = d.district
LEFT JOIN schools_by_district     sc  ON sc.country  = d.country AND sc.district  = d.district;
$$;


CREATE OR REPLACE FUNCTION rep_portal.get_school_point_data()
RETURNS TABLE (
  school_id     TEXT,
  school_name   TEXT,
  country_slug  TEXT,
  country_name  TEXT,
  district_name TEXT,
  province      TEXT,
  geo_source    TEXT,
  latitude      NUMERIC,
  longitude     NUMERIC,
  kpis          JSONB
) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
SET statement_timeout = 0
AS $$
WITH
cs_by_school AS (
  SELECT
    f.school_id,
    COUNT(*)                                        AS total,
    COUNT(*) FILTER (WHERE ct.gender = 'Female')    AS girls,
    COUNT(*) FILTER (WHERE ct.gender = 'Male')      AS boys
  FROM rep_warehouse.fact_children_supported f
  LEFT JOIN rep_warehouse.dim_contact ct ON ct.id = f.contact_id
  WHERE f.school_id IS NOT NULL
  GROUP BY f.school_id
),
guides_by_school AS (
  SELECT
    school_id,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Learner%'    AND guide_status ILIKE '%Active%') AS learner,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Transition%' AND guide_status ILIKE '%Active%') AS transition,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Agri%'       AND guide_status ILIKE '%Active%') AS agriculture,
    COUNT(*) FILTER (WHERE guide_type ILIKE '%Business%'   AND guide_status ILIKE '%Active%') AS business
  FROM rep_warehouse.fact_guide_assignment
  WHERE school_id IS NOT NULL
  GROUP BY school_id
),
cama_by_school AS (
  SELECT school_id, COUNT(*) AS total
  FROM rep_warehouse.fact_cama_membership
  WHERE school_id IS NOT NULL
  GROUP BY school_id
)
SELECT
  s.source_school_id::text                  AS school_id,
  s.school_name,
  lower(replace(g.country, ' ', '-'))       AS country_slug,
  g.country                                 AS country_name,
  g.district                                AS district_name,
  g.province,
  'warehouse'                               AS geo_source,
  s.latitude,
  s.longitude,
  jsonb_build_object(
    'education_bursaries_children',  COALESCE(cs.total, 0),
    'clients_by_form',               COALESCE(cs.total, 0),
    'clients_by_form_girls',         COALESCE(cs.girls, 0),
    'clients_by_form_boys',          COALESCE(cs.boys,  0),
    'active_learner_guides',         COALESCE(ga.learner,      0),
    'active_guides_transition',      COALESCE(ga.transition,   0),
    'active_guides_agriculture',     COALESCE(ga.agriculture,  0),
    'active_guides_business',        COALESCE(ga.business,     0),
    'active_guides_by_type',
      COALESCE(ga.learner, 0) + COALESCE(ga.transition, 0)
      + COALESCE(ga.agriculture, 0) + COALESCE(ga.business, 0),
    'cama_members',                  COALESCE(cam.total, 0),
    'active_partner_schools',        CASE WHEN s.active_partner_school THEN 1 ELSE 0 END
  ) AS kpis
FROM rep_warehouse.dim_school s
JOIN  rep_warehouse.dim_geography g
      ON  g.id = s.geography_id AND g.scd_is_current = true
LEFT JOIN cs_by_school    cs  ON cs.school_id  = s.id
LEFT JOIN guides_by_school ga  ON ga.school_id  = s.id
LEFT JOIN cama_by_school   cam ON cam.school_id = s.id
WHERE s.scd_is_current = true
  AND s.latitude  IS NOT NULL
  AND s.longitude IS NOT NULL
  AND g.country IN ('Tanzania', 'Ghana', 'Malawi', 'Zambia', 'Zimbabwe');
$$;

GRANT EXECUTE ON FUNCTION rep_portal.get_district_kpi_data() TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_school_point_data() TO authenticated;


-- ===== 20250201000033_whatsapp_bot_portal_wrappers.sql =====
-- Route WhatsApp bot rep_warehouse calls through rep_portal so the bot
-- works without rep_warehouse being exposed via PostgREST.
--
-- Two areas were broken after the security-hardening (rep_warehouse removed
-- from PostgREST exposed schemas):
--   1. getDistricts()          — queried rep_warehouse.dim_geography directly
--   2. district_report_*()    — called rep_warehouse.district_report_* RPCs directly
--
-- All functions are SECURITY DEFINER so the service_role JWT used by the
-- Edge Function can call them without direct access to rep_warehouse.

-- ── 1. get_bot_districts ──────────────────────────────────────────────────────
-- Returns distinct (country, province, district) triples from dim_geography
-- for current rows that have a non-null district.

CREATE OR REPLACE FUNCTION rep_portal.get_bot_districts()
RETURNS TABLE (country TEXT, province TEXT, district TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
  SELECT DISTINCT
    g.country::TEXT,
    g.province::TEXT,
    g.district::TEXT
  FROM rep_warehouse.dim_geography g
  WHERE g.scd_is_current = true
    AND g.district IS NOT NULL
  ORDER BY 1, 2, 3;
$$;

GRANT EXECUTE ON FUNCTION rep_portal.get_bot_districts() TO service_role;

-- ── 2. district_report_children ───────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.district_report_children(p_district TEXT)
RETURNS TABLE (
  report_year  INT,
  total_girls  BIGINT,
  school_count BIGINT,
  top_schools  TEXT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
  SELECT * FROM rep_warehouse.district_report_children(p_district);
$$;

GRANT EXECUTE ON FUNCTION rep_portal.district_report_children(TEXT) TO service_role;

-- ── 3. district_report_people ─────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.district_report_people(p_district TEXT)
RETURNS TABLE (
  active_guides BIGINT,
  total_guides  BIGINT,
  cama_members  BIGINT
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
  SELECT * FROM rep_warehouse.district_report_people(p_district);
$$;

GRANT EXECUTE ON FUNCTION rep_portal.district_report_people(TEXT) TO service_role;

-- ── 4. district_report_finance ────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.district_report_finance(p_district TEXT)
RETURNS TABLE (
  grants_year  INT,
  grants_count BIGINT,
  grants_total NUMERIC,
  loans_year   INT,
  loans_count  BIGINT,
  loans_total  NUMERIC
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
  SELECT * FROM rep_warehouse.district_report_finance(p_district);
$$;

GRANT EXECUTE ON FUNCTION rep_portal.district_report_finance(TEXT) TO service_role;


-- ===== 20250201000034_fix_get_ingest_runs_since_type.sql =====
-- Fix: get_ingest_runs() declared `since` as TIMESTAMPTZ but the column is TEXT.
-- Recreate with the correct type so PostgREST can call it without a 400 error.
-- Must DROP first because PostgreSQL won't allow changing the return type in place.

DROP FUNCTION IF EXISTS rep_portal.get_ingest_runs();

CREATE FUNCTION rep_portal.get_ingest_runs()
RETURNS TABLE (
  run_id           TEXT,
  status           TEXT,
  since            TEXT,
  started_by       TEXT,
  current_wave     INTEGER,
  attempt_count    INTEGER,
  lease_expires_at TIMESTAMPTZ,
  started_at       TIMESTAMPTZ,
  finished_at      TIMESTAMPTZ,
  error            TEXT
) LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin privileges required';
  END IF;
  RETURN QUERY
    SELECT r.run_id, r.status, r.since, r.started_by, r.current_wave::INTEGER,
           r.attempt_count, r.lease_expires_at, r.started_at, r.finished_at, r.error
    FROM rep_warehouse.ingest_run r
    ORDER BY r.started_at DESC
    LIMIT 20;
END;
$$;

GRANT EXECUTE ON FUNCTION rep_portal.get_ingest_runs() TO authenticated;


-- ===== 20250201000035_wa_analytics_rpc_wrappers.sql =====
-- Wrap WhatsApp analytics views in SECURITY DEFINER RPCs.
--
-- The views use security_invoker = on, so they run as the calling role
-- (authenticated). That role was never granted SELECT on the underlying
-- whatsapp_events table, causing a 403. SECURITY DEFINER functions run
-- as their owner (postgres), who has full access; the admin check is
-- enforced in the function body instead of via RLS.

CREATE OR REPLACE FUNCTION rep_portal.get_wa_daily()
RETURNS TABLE (
  day          DATE,
  unique_users BIGINT,
  total_events BIGINT,
  completions  BIGINT,
  errors       BIGINT
) LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = rep_portal, public
AS $$
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin privileges required';
  END IF;
  RETURN QUERY SELECT v.day, v.unique_users, v.total_events, v.completions, v.errors
               FROM rep_portal.view_wa_daily v;
END;
$$;

CREATE OR REPLACE FUNCTION rep_portal.get_wa_flow_summary()
RETURNS TABLE (
  flow           TEXT,
  unique_users   BIGINT,
  started        BIGINT,
  completed      BIGINT,
  abandoned      BIGINT,
  errors         BIGINT,
  completion_pct NUMERIC
) LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = rep_portal, public
AS $$
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin privileges required';
  END IF;
  RETURN QUERY SELECT v.flow, v.unique_users, v.started, v.completed,
                      v.abandoned, v.errors, v.completion_pct
               FROM rep_portal.view_wa_flow_summary v;
END;
$$;

CREATE OR REPLACE FUNCTION rep_portal.get_wa_funnel(p_flow TEXT DEFAULT NULL)
RETURNS TABLE (
  flow         TEXT,
  step         TEXT,
  entries      BIGINT,
  unique_users BIGINT
) LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = rep_portal, public
AS $$
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin privileges required';
  END IF;
  RETURN QUERY
    SELECT v.flow, v.step, v.entries, v.unique_users
    FROM rep_portal.view_wa_funnel v
    WHERE p_flow IS NULL OR v.flow = p_flow
    ORDER BY v.entries DESC;
END;
$$;

CREATE OR REPLACE FUNCTION rep_portal.get_wa_errors()
RETURNS TABLE (
  id          BIGINT,
  flow        TEXT,
  from_step   TEXT,
  to_step     TEXT,
  occurred_at TIMESTAMPTZ
) LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = rep_portal, public
AS $$
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin privileges required';
  END IF;
  RETURN QUERY SELECT v.id, v.flow, v.from_step, v.to_step, v.occurred_at
               FROM rep_portal.view_wa_errors v;
END;
$$;

GRANT EXECUTE ON FUNCTION rep_portal.get_wa_daily()              TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_wa_flow_summary()       TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_wa_funnel(TEXT)         TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_wa_errors()             TO authenticated;


-- ===== 20260514100147_roles.sql =====
-- RBAC: roles, permissions (dashlet + wa_report categories only)
-- Adds:
--   rep_portal.permissions, roles, role_permissions, user_roles, permission_metric_map
--   RPCs: get_my_permissions, get_dashboard_data_scoped, get_wa_report_permissions
--   Replaces: rep_portal.get_observed_kpi with permission-aware version

-- ── Tables ────────────────────────────────────────────────────────────────────

CREATE TABLE rep_portal.permissions (
  id          SERIAL PRIMARY KEY,
  key         TEXT NOT NULL UNIQUE,
  label       TEXT NOT NULL,
  description TEXT,
  category    TEXT NOT NULL
    CHECK (category IN ('dashlet', 'wa_report')),
  parent_key  TEXT  -- used for UI grouping in role editor (sublevel label string)
);

CREATE TABLE rep_portal.roles (
  id          SERIAL PRIMARY KEY,
  name        TEXT NOT NULL UNIQUE,
  description TEXT,
  created_by  UUID,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE OR REPLACE FUNCTION rep_portal.set_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql
SET search_path = rep_portal, pg_temp
AS $$
BEGIN NEW.updated_at = now(); RETURN NEW; END; $$;

CREATE TRIGGER roles_updated_at
  BEFORE UPDATE ON rep_portal.roles
  FOR EACH ROW EXECUTE FUNCTION rep_portal.set_updated_at();

CREATE TABLE rep_portal.role_permissions (
  role_id       INTEGER NOT NULL REFERENCES rep_portal.roles(id) ON DELETE CASCADE,
  permission_id INTEGER NOT NULL REFERENCES rep_portal.permissions(id) ON DELETE CASCADE,
  PRIMARY KEY (role_id, permission_id)
);

CREATE TABLE rep_portal.user_roles (
  user_id     UUID    NOT NULL,
  role_id     INTEGER NOT NULL REFERENCES rep_portal.roles(id) ON DELETE CASCADE,
  assigned_by UUID,
  assigned_at TIMESTAMPTZ NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, role_id)
);

-- Maps dashlet permission keys to the metric IDs they grant access to.
-- metric_id matches:
--   - kpi_id values in rep_warehouse.view_observed_kpi (e.g. '1.5', '2.2', 'P1')
--   - metric values in rep_portal.dashboard_data_agg (e.g. 'CAMA Members')
CREATE TABLE rep_portal.permission_metric_map (
  permission_key TEXT NOT NULL REFERENCES rep_portal.permissions(key) ON DELETE CASCADE,
  metric_id      TEXT NOT NULL,
  PRIMARY KEY (permission_key, metric_id)
);

-- ── RLS ───────────────────────────────────────────────────────────────────────

ALTER TABLE rep_portal.permissions           ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_portal.roles                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_portal.role_permissions      ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_portal.user_roles            ENABLE ROW LEVEL SECURITY;
ALTER TABLE rep_portal.permission_metric_map ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated can read permissions"
  ON rep_portal.permissions FOR SELECT TO authenticated USING (true);

CREATE POLICY "authenticated can read roles"
  ON rep_portal.roles FOR SELECT TO authenticated USING (true);

CREATE POLICY "authenticated can read role_permissions"
  ON rep_portal.role_permissions FOR SELECT TO authenticated USING (true);

CREATE POLICY "users can read own user_roles"
  ON rep_portal.user_roles FOR SELECT TO authenticated USING (user_id = auth.uid());

CREATE POLICY "authenticated can read permission_metric_map"
  ON rep_portal.permission_metric_map FOR SELECT TO authenticated USING (true);

-- ── Seed: dashlet permissions (one per card) ─────────────────────────────────
-- parent_key = section name used for grouping in the role editor UI

INSERT INTO rep_portal.permissions (key, label, category, parent_key) VALUES
  -- Education Reach (4 cards)
  ('dashlet:education_reach:bursaries',        'Girls Supported with Education Bursaries', 'dashlet', 'Education Reach'),
  ('dashlet:education_reach:cama_community',   'Girls Supported by CAMA & Community Champions', 'dashlet', 'Education Reach'),
  ('dashlet:education_reach:total_girls',      'Total Girls Supported',                    'dashlet', 'Education Reach'),
  ('dashlet:education_reach:total_boys',       'Total Boys Supported',                     'dashlet', 'Education Reach'),

  -- Education Outcomes (4 cards)
  ('dashlet:education_outcomes:dropout_rate',      'Dropout Rate',                'dashlet', 'Education Outcomes'),
  ('dashlet:education_outcomes:grade_progression', 'Progression to Next Grade',   'dashlet', 'Education Outcomes'),
  ('dashlet:education_outcomes:exam_pass_rates',   'Exam Pass Rates',             'dashlet', 'Education Outcomes'),
  ('dashlet:education_outcomes:school_completion', 'School Completion Rate',      'dashlet', 'Education Outcomes'),

  -- Learner Guide Programme (3 cards)
  ('dashlet:learner_guide:active_guides',      'Active Learner Guides',                        'dashlet', 'Learner Guide Programme'),
  ('dashlet:learner_guide:guides_by_training', 'Active Learner Guides by Training',            'dashlet', 'Learner Guide Programme'),
  ('dashlet:learner_guide:children_sls',       'Children Receiving Social & Learning Support', 'dashlet', 'Learner Guide Programme'),

  -- Leadership & Tertiary (4 cards)
  ('dashlet:leadership_tertiary:transition_guides', 'Active Transition Guides',                       'dashlet', 'Leadership & Tertiary'),
  ('dashlet:leadership_tertiary:cama_members',      'Numbers of CAMA Members',                        'dashlet', 'Leadership & Tertiary'),
  ('dashlet:leadership_tertiary:young_women_tg',    'Young Women Supported by Transition Guides',     'dashlet', 'Leadership & Tertiary'),
  ('dashlet:leadership_tertiary:women_tertiary',    'Young Women in Tertiary Education',              'dashlet', 'Leadership & Tertiary'),

  -- Livelihoods Reach (4 cards)
  ('dashlet:livelihoods_reach:enterprise_guides',   'Active Enterprise Guides',               'dashlet', 'Livelihoods Reach'),
  ('dashlet:livelihoods_reach:businesses_supported','Businesses Supported',                   'dashlet', 'Livelihoods Reach'),
  ('dashlet:livelihoods_reach:business_grants',     'Business Grants Distributed',            'dashlet', 'Livelihoods Reach'),
  ('dashlet:livelihoods_reach:loans',               'CAMFED Kiva & RIF Loans Distributed',   'dashlet', 'Livelihoods Reach'),

  -- Jobs & Income (4 cards)
  ('dashlet:jobs_income:women_livelihood',       'Women Progressing Towards a Secure Livelihood',     'dashlet', 'Jobs & Income'),
  ('dashlet:jobs_income:entrepreneurs_income',   'Female Entrepreneurs with Increased Incomes',       'dashlet', 'Jobs & Income'),
  ('dashlet:jobs_income:jobs_created',           'Jobs Created through Enterprise Programme',         'dashlet', 'Jobs & Income'),
  ('dashlet:jobs_income:new_businesses',         'New Businesses',                                    'dashlet', 'Jobs & Income'),

  -- Agriculture & Food (3 cards)
  ('dashlet:agriculture_food:food_consumption',  'Female Entrepreneurs — Increased Food Consumption', 'dashlet', 'Agriculture & Food'),
  ('dashlet:agriculture_food:increased_yields',  'Female Agripreneurs — Increased Yields',            'dashlet', 'Agriculture & Food'),
  ('dashlet:agriculture_food:climate_techniques','Average Climate-Smart Techniques Used',             'dashlet', 'Agriculture & Food'),

  -- Life Choices (2 cards)
  ('dashlet:life_choices:married_by_18', 'Young Women Married by Age 18',             'dashlet', 'Life Choices'),
  ('dashlet:life_choices:birth_by_18',   'Young Women Giving Birth by Age 18',        'dashlet', 'Life Choices'),

  -- Education Systems 1 (2 cards — static data, no KPI RPC)
  ('dashlet:education_systems_1:districts_with_lg', 'Districts with Learner Guides', 'dashlet', 'Education Systems 1'),
  ('dashlet:education_systems_1:schools_with_lg',   'Schools with Learner Guides',   'dashlet', 'Education Systems 1'),

  -- Education Systems 2 (3 cards)
  ('dashlet:education_systems_2:mou',                 'Memoranda of Understanding',                     'dashlet', 'Education Systems 2'),
  ('dashlet:education_systems_2:community_champions', 'Active Community Champions',                     'dashlet', 'Education Systems 2'),
  ('dashlet:education_systems_2:children_learning',   'Children Benefitting from Improved Learning Env','dashlet', 'Education Systems 2');

-- ── Seed: wa_report permissions ───────────────────────────────────────────────

INSERT INTO rep_portal.permissions (key, label, category) VALUES
  ('wa_report:children', 'Children Supported', 'wa_report'),
  ('wa_report:people',   'People',             'wa_report'),
  ('wa_report:finance',  'Finance',            'wa_report');

-- ── Seed: permission_metric_map ───────────────────────────────────────────────
-- Maps each dashlet card permission to the metric ID(s) it requires.
-- Note: KPI 2.2 is used by both transition_guides and enterprise_guides;
--   get_observed_kpi('2.2') returns data if the user holds either permission.

INSERT INTO rep_portal.permission_metric_map (permission_key, metric_id) VALUES
  -- Education Reach
  ('dashlet:education_reach:bursaries', 'Children Supported in School with Education Bursaries'),
  ('dashlet:education_reach:bursaries', 'Children Supported in School with Education Bursaries — Annual'),
  ('dashlet:education_reach:bursaries', 'Children Supported in School with Education Bursaries — Cumulative 2020-2030'),
  ('dashlet:education_reach:bursaries', 'Children Supported in School with Education Bursaries — Cumulative all-time'),
  ('dashlet:education_reach:cama_community', 'CAMA Members'),
  ('dashlet:education_reach:cama_community', 'Community Champions'),
  ('dashlet:education_reach:total_girls', 'P1'),
  ('dashlet:education_reach:total_boys',  'P1'),

  -- Education Outcomes
  ('dashlet:education_outcomes:dropout_rate',      '1.5'),
  ('dashlet:education_outcomes:grade_progression', '1.7'),
  ('dashlet:education_outcomes:exam_pass_rates',   '1.4'),
  ('dashlet:education_outcomes:school_completion', '1.8'),

  -- Learner Guide Programme
  ('dashlet:learner_guide:active_guides',      '1.9'),
  ('dashlet:learner_guide:guides_by_training', '1.9'),
  ('dashlet:learner_guide:children_sls',       '1.3'),

  -- Leadership & Tertiary
  ('dashlet:leadership_tertiary:transition_guides', '2.2'),
  ('dashlet:leadership_tertiary:cama_members',      '2.1'),
  ('dashlet:leadership_tertiary:young_women_tg',    '2.3'),
  ('dashlet:leadership_tertiary:women_tertiary',    '2.5'),

  -- Livelihoods Reach
  ('dashlet:livelihoods_reach:enterprise_guides',    '2.2'),
  ('dashlet:livelihoods_reach:businesses_supported', '2.7'),
  ('dashlet:livelihoods_reach:business_grants',      '2.8a'),
  ('dashlet:livelihoods_reach:loans',                '2.8b'),

  -- Jobs & Income
  ('dashlet:jobs_income:women_livelihood',     '2.4'),
  ('dashlet:jobs_income:entrepreneurs_income', '2.11'),
  ('dashlet:jobs_income:jobs_created',         '2.9'),
  ('dashlet:jobs_income:new_businesses',       '2.6'),

  -- Agriculture & Food
  ('dashlet:agriculture_food:food_consumption',  'R4'),
  ('dashlet:agriculture_food:increased_yields',  'R8'),
  ('dashlet:agriculture_food:climate_techniques','R7'),

  -- Life Choices
  ('dashlet:life_choices:married_by_18', '2.14'),
  ('dashlet:life_choices:birth_by_18',   '2.15'),

  -- Education Systems 1: static data only — no metric_map entries needed

  -- Education Systems 2
  ('dashlet:education_systems_2:mou',                 'P18'),
  ('dashlet:education_systems_2:community_champions', 'P6'),
  ('dashlet:education_systems_2:children_learning',   '3.5');

-- ── RPC: get_my_permissions() ─────────────────────────────────────────────────

CREATE FUNCTION rep_portal.get_my_permissions()
RETURNS TABLE(key TEXT) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = rep_portal, public
AS $$
  SELECT DISTINCT p.key
  FROM rep_portal.user_roles ur
  JOIN rep_portal.role_permissions rp ON rp.role_id = ur.role_id
  JOIN rep_portal.permissions p ON p.id = rp.permission_id
  WHERE ur.user_id = auth.uid();
$$;

GRANT EXECUTE ON FUNCTION rep_portal.get_my_permissions() TO authenticated;
REVOKE EXECUTE ON FUNCTION rep_portal.get_my_permissions() FROM anon;

-- ── RPC: get_dashboard_data_scoped() ─────────────────────────────────────────
-- Scoped version of get_dashboard_data: admins see all rows, others see only
-- rows whose metric is permitted via permission_metric_map.

CREATE FUNCTION rep_portal.get_dashboard_data_scoped()
RETURNS json LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = rep_portal, public
AS $$
  SELECT json_build_object('data', COALESCE(json_agg(r), '[]'::json))
  FROM (
    SELECT d.*
    FROM rep_portal.dashboard_data_agg d
    WHERE
      (auth.jwt()->'app_metadata'->>'role') = 'admin'
      OR EXISTS (
        SELECT 1
        FROM rep_portal.permission_metric_map pmm
        JOIN rep_portal.permissions p ON p.key = pmm.permission_key
        JOIN rep_portal.role_permissions rp ON rp.permission_id = p.id
        JOIN rep_portal.user_roles ur ON ur.role_id = rp.role_id
        WHERE ur.user_id = auth.uid()
          AND pmm.metric_id = d.metric
      )
  ) r;
$$;

GRANT EXECUTE ON FUNCTION rep_portal.get_dashboard_data_scoped() TO authenticated;
REVOKE EXECUTE ON FUNCTION rep_portal.get_dashboard_data_scoped() FROM anon;

-- ── RPC: get_observed_kpi (replace with permission-aware version) ─────────────
-- Admins get all rows. Authenticated users get rows only when they hold a
-- dashlet permission whose permission_metric_map.metric_id matches p_kpi_id.

CREATE OR REPLACE FUNCTION rep_portal.get_observed_kpi(p_kpi_id TEXT)
RETURNS TABLE (
  country                  TEXT,
  kpi_id                   TEXT,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  year                     INTEGER,
  value                    TEXT
) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, rep_portal, public
AS $$
  SELECT v.country, v.kpi_id, v.disaggregation_level_one,
         v.disaggregation_level_two, v.year, v.value
  FROM rep_warehouse.view_observed_kpi v
  WHERE v.kpi_id = p_kpi_id
    AND v.year IS NOT NULL
    AND v.country IS NOT NULL
    AND (
      (auth.jwt()->'app_metadata'->>'role') = 'admin'
      OR EXISTS (
        SELECT 1
        FROM rep_portal.permission_metric_map pmm
        JOIN rep_portal.permissions p ON p.key = pmm.permission_key
        JOIN rep_portal.role_permissions rp ON rp.permission_id = p.id
        JOIN rep_portal.user_roles ur ON ur.role_id = rp.role_id
        WHERE ur.user_id = auth.uid()
          AND pmm.metric_id = p_kpi_id
      )
    );
$$;

GRANT EXECUTE ON FUNCTION rep_portal.get_observed_kpi(TEXT) TO authenticated;

-- ── RPC: get_wa_report_permissions(p_whatsapp_user_id) ───────────────────────
-- Called by whatsapp-webhook (service_role) using verified_user_id from
-- auth:pending session context. Empty result → caller shows all 3 reports.

CREATE FUNCTION rep_portal.get_wa_report_permissions(p_whatsapp_user_id INTEGER)
RETURNS TABLE(key TEXT) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = rep_portal, public
AS $$
  SELECT DISTINCT p.key
  FROM rep_portal.whatsapp_users wu
  JOIN rep_portal.user_roles ur ON ur.user_id = wu.supabase_user_id
  JOIN rep_portal.role_permissions rp ON rp.role_id = ur.role_id
  JOIN rep_portal.permissions p ON p.id = rp.permission_id
  WHERE wu.id = p_whatsapp_user_id
    AND p.category = 'wa_report';
$$;

GRANT EXECUTE ON FUNCTION rep_portal.get_wa_report_permissions(INTEGER) TO service_role;
REVOKE EXECUTE ON FUNCTION rep_portal.get_wa_report_permissions(INTEGER) FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.get_wa_report_permissions(INTEGER) FROM authenticated;

-- ── Seed: Full Access role — assign all permissions to every existing user ────
-- Ensures no existing user loses dashboard or WhatsApp report access on deploy.

INSERT INTO rep_portal.roles (name, description)
VALUES ('Full Access', 'All dashlet and WhatsApp report permissions');

INSERT INTO rep_portal.role_permissions (role_id, permission_id)
SELECT (SELECT id FROM rep_portal.roles WHERE name = 'Full Access'), id
FROM rep_portal.permissions;

INSERT INTO rep_portal.user_roles (user_id, role_id)
SELECT au.id, (SELECT id FROM rep_portal.roles WHERE name = 'Full Access')
FROM auth.users au;

-- ── Grants ────────────────────────────────────────────────────────────────────

GRANT ALL ON rep_portal.permissions,
             rep_portal.roles,
             rep_portal.role_permissions,
             rep_portal.user_roles,
             rep_portal.permission_metric_map TO service_role;

GRANT USAGE ON SEQUENCE rep_portal.permissions_id_seq,
                        rep_portal.roles_id_seq TO service_role;


-- ===== 20260515104116_fix_etl_function_search_paths.sql =====
-- Pin search_path on all ETL functions that were missing it.
-- Uses ALTER FUNCTION so function bodies are untouched.
-- Wrapped in DO blocks so functions that don't exist on this environment are skipped.
-- search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
--   rep_warehouse — function home schema + dim/fact tables
--   rep_staging   — conformed tables (staging fns write, load fns read)
--   rep_raw       — landing tables (staging fns read)
--   pg_temp       — required by etl_load_dim_contact (_etl_contacts temp table)

DO $$
DECLARE fn TEXT;
BEGIN
  FOR fn IN SELECT unnest(ARRAY[
    'etl_stage_dimension_1_roc',
    'etl_stage_dimension_2_roc',
    'etl_stage_dimension_3_roc',
    'etl_stage_dimension_4_roc',
    'etl_stage_countries',
    'etl_stage_districts',
    'etl_stage_contacts',
    'etl_stage_schools',
    'etl_stage_academic_record',
    'etl_stage_post_school_clients',
    'etl_stage_guides',
    'etl_stage_cama_members',
    'etl_stage_grant_recipients',
    'etl_stage_loan_recipients',
    'etl_stage_all_kpis',
    'etl_stage_level_one_kpis',
    'etl_load_dim_roc_geography',
    'etl_load_dim_roc_project_code',
    'etl_load_dim_roc_donor',
    'etl_load_dim_roc_donor_activity',
    'etl_load_dim_geography',
    'etl_load_dim_school',
    'etl_load_dim_contact',
    'etl_load_dim_geography_kpi',
    'etl_load_fact_children_supported',
    'etl_load_fact_guide_assignment',
    'etl_load_fact_cama_membership',
    'etl_load_fact_post_school_support',
    'etl_load_fact_grants',
    'etl_load_fact_loans',
    'etl_load_fact_observed_kpi',
    'etl_load_fact_level_one_kpis',
    'etl_run_staging',
    'etl_run_warehouse',
    'etl_run_kpi_staging',
    'etl_run_kpi_warehouse'
  ]) LOOP
    BEGIN
      EXECUTE format(
        'ALTER FUNCTION rep_warehouse.%I() SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp',
        fn
      );
    EXCEPTION WHEN undefined_function THEN
      RAISE NOTICE 'Skipping % — function does not exist', fn;
    END;
  END LOOP;
END;
$$;

-- etl_load_dim_kpi was redefined in migration 013 without search_path
ALTER FUNCTION rep_warehouse.etl_load_dim_kpi()
    SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp;

-- is_admin only needs rep_warehouse (calls auth.jwt() which is always qualified)
ALTER FUNCTION rep_warehouse.is_admin()
    SET search_path = rep_warehouse, pg_temp;


-- ===== 20260515110721_fix_anon_access_and_search_paths.sql =====
-- ── 1. Drop legacy orphan functions in public schema ─────────────────────────
-- These were created outside migrations, are not referenced by the frontend,
-- and are superseded by the rep_portal API layer.

DROP FUNCTION IF EXISTS public.get_dd_cama_members();
DROP FUNCTION IF EXISTS public.get_dd_children_bursaries();
DROP FUNCTION IF EXISTS public.get_dd_clients_by_form();
DROP FUNCTION IF EXISTS public.get_dd_grants();
DROP FUNCTION IF EXISTS public.get_dd_guides_by_type();
DROP FUNCTION IF EXISTS public.get_dd_learner_guides();
DROP FUNCTION IF EXISTS public.get_dd_loans();
DROP FUNCTION IF EXISTS public.get_dd_partner_schools();
DROP FUNCTION IF EXISTS public.get_dd_post_school_clients();
DROP FUNCTION IF EXISTS public.get_dd_tertiary_education();
DROP FUNCTION IF EXISTS public.get_dim_geography();
DROP FUNCTION IF EXISTS public.get_dim_school();


-- ── 2. rep_warehouse — revoke PUBLIC execute ──────────────────────────────────
-- All rep_warehouse functions are internal (ETL, ingest state machine, cron).
-- Only service_role should call them. Explicit service_role grants already exist
-- in earlier migrations; revoking PUBLIC closes the anon/authenticated gap.

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA rep_warehouse FROM PUBLIC;


-- ── 3. rep_raw.truncate_table — revoke PUBLIC execute ────────────────────────
-- Only the ingest script (service_role) should truncate raw tables.

REVOKE EXECUTE ON FUNCTION rep_raw.truncate_table(p_table TEXT) FROM PUBLIC;


-- ── 4. rep_portal — revoke anon from non-public functions ────────────────────
-- Four functions are intentionally public (no login required):
--   get_dashboard_data, get_observed_kpi, get_district_kpi_data, get_school_point_data
-- Everything else requires authentication.

REVOKE EXECUTE ON FUNCTION rep_portal.check_upload_exists(p_year INTEGER)                          FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.count_all_kpi_rows(p_year INTEGER)                           FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.district_report_children(p_district TEXT)                    FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.district_report_finance(p_district TEXT)                     FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.district_report_people(p_district TEXT)                      FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.get_all_kpi_rows(p_year INTEGER, p_limit INTEGER, p_offset INTEGER) FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.get_bot_districts()                                           FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.get_duplicate_rows(p_batch_id TEXT)                          FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.get_etl_batch_log()                                          FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.get_etl_batch_log_entry(p_batch_id TEXT)                     FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.get_ingest_fn_state(p_run_id TEXT)                           FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.get_ingest_runs()                                            FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.get_level_one_upload_log()                                   FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.get_loaded_years()                                           FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.get_upload_log()                                             FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.get_wa_daily()                                               FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.get_wa_errors()                                              FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.get_wa_flow_summary()                                        FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.get_wa_funnel(p_flow TEXT)                                   FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.kpi_delete_year(p_year INTEGER)                              FROM anon;


-- ── 5. Fix remaining search_path on rep_warehouse.district_report_* ──────────
-- The original rep_warehouse implementations (migration 018) were never patched.
-- The rep_portal wrappers (migration 033) already have search_path set.

ALTER FUNCTION rep_warehouse.district_report_children(p_district TEXT)
    SET search_path = rep_warehouse, pg_temp;

ALTER FUNCTION rep_warehouse.district_report_finance(p_district TEXT)
    SET search_path = rep_warehouse, pg_temp;

ALTER FUNCTION rep_warehouse.district_report_people(p_district TEXT)
    SET search_path = rep_warehouse, pg_temp;


-- ── 6. Fix search_path on rep_raw.truncate_table ─────────────────────────────

ALTER FUNCTION rep_raw.truncate_table(p_table TEXT)
    SET search_path = rep_raw, pg_temp;


-- ===== 20260515110851_fix_rep_portal_anon_access.sql =====
-- Remove the default PUBLIC EXECUTE grant on all rep_portal functions,
-- then grant back only to the roles that should have access.
--
-- authenticated — all rep_portal functions (logged-in users)
-- anon          — only the 4 public data functions (no login required)

REVOKE EXECUTE ON ALL FUNCTIONS IN SCHEMA rep_portal FROM PUBLIC;

GRANT EXECUTE ON ALL FUNCTIONS IN SCHEMA rep_portal TO authenticated;

GRANT EXECUTE ON FUNCTION rep_portal.get_dashboard_data()          TO anon;
GRANT EXECUTE ON FUNCTION rep_portal.get_observed_kpi(p_kpi_id TEXT) TO anon;
GRANT EXECUTE ON FUNCTION rep_portal.get_district_kpi_data()       TO anon;
GRANT EXECUTE ON FUNCTION rep_portal.get_school_point_data()       TO anon;


-- ===== 20260516161024_fix_dashboard_agg_refresh_and_user_roles.sql =====
-- 1. Refresh dashboard_data_agg at the end of every Salesforce ETL run.
--    etl_run_warehouse() loads all facts but never refreshes the mat view.

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
    REFRESH MATERIALIZED VIEW rep_portal.dashboard_data_agg;
END;
$$;

-- 2. Auto-assign new Supabase Auth users to the "Full Access" role on sign-up.
--    The original seed INSERT in 20260514100147_roles.sql ran before any users existed.

CREATE OR REPLACE FUNCTION rep_portal.assign_default_role()
RETURNS TRIGGER LANGUAGE plpgsql SECURITY DEFINER
SET search_path = rep_portal, public
AS $$
DECLARE
    v_role_id INTEGER;
BEGIN
    SELECT id INTO v_role_id FROM rep_portal.roles WHERE name = 'Full Access';
    IF v_role_id IS NOT NULL THEN
        INSERT INTO rep_portal.user_roles (user_id, role_id)
        VALUES (NEW.id, v_role_id)
        ON CONFLICT DO NOTHING;
    END IF;
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.assign_default_role() FROM PUBLIC;

CREATE OR REPLACE TRIGGER trg_assign_default_role
    AFTER INSERT ON auth.users
    FOR EACH ROW EXECUTE FUNCTION rep_portal.assign_default_role();

-- 3. Backfill existing users who were created before the role seed ran.

INSERT INTO rep_portal.user_roles (user_id, role_id)
SELECT au.id, r.id
FROM auth.users au
CROSS JOIN rep_portal.roles r
WHERE r.name = 'Full Access'
ON CONFLICT DO NOTHING;


-- ===== 20260516173118_fix_permission_metric_map_and_kpi_refresh.sql =====
-- Fix 1: Add missing metric mappings for fact-based dashboard_data_agg metrics.
--
-- get_dashboard_data_scoped filters dashboard_data_agg rows using permission_metric_map.
-- The original seed only covered KPI-id strings (for get_observed_kpi) and 6 named
-- metric strings. The remaining 18 metric strings from fact tables (Active Learner Guides,
-- Grants Disbursed, etc.) had no entries, so non-admin users always got an empty dataset
-- → data.countries = [] → all dashboard chart iterations produced zero rows.

INSERT INTO rep_portal.permission_metric_map (permission_key, metric_id) VALUES
  -- Education Reach (fact-based)
  ('dashlet:education_reach:bursaries',           'Number of Clients by Form'),
  ('dashlet:education_reach:bursaries',           'Number of Clients by Form — Girls'),
  ('dashlet:education_reach:total_boys',          'Number of Clients by Form — Boys'),
  ('dashlet:education_reach:bursaries',           'Active Partner Schools'),

  -- Learner Guide Programme (fact-based)
  ('dashlet:learner_guide:active_guides',         'Active Learner Guides'),
  ('dashlet:learner_guide:guides_by_training',    'Active Guides by Type'),

  -- Leadership & Tertiary (fact-based)
  ('dashlet:leadership_tertiary:women_tertiary',    'Number of Women Supported by CAMFED in Tertiary Education'),
  ('dashlet:leadership_tertiary:women_tertiary',    'Number of Post School Clients'),
  ('dashlet:leadership_tertiary:transition_guides', 'Active Guides — Transition'),

  -- Livelihoods Reach (fact-based)
  ('dashlet:livelihoods_reach:enterprise_guides',  'Active Guides — Agriculture'),
  ('dashlet:livelihoods_reach:enterprise_guides',  'Active Guides — Business'),
  ('dashlet:livelihoods_reach:business_grants',    'Grants Disbursed'),
  ('dashlet:livelihoods_reach:business_grants',    'Grants Distributed — Count'),
  ('dashlet:livelihoods_reach:loans',              'Loans Disbursed'),
  ('dashlet:livelihoods_reach:loans',              'Loans Disbursed — Agriculture'),
  ('dashlet:livelihoods_reach:loans',              'Loans Disbursed — Business'),
  ('dashlet:livelihoods_reach:loans',              'Loans Disbursed — Kiva'),
  ('dashlet:livelihoods_reach:loans',              'Loans Disbursed — RIF')
ON CONFLICT DO NOTHING;

-- Fix 2: Refresh dashboard_data_agg after KPI uploads.
--
-- kpi_upload_all and kpi_upload_level_one write to fact_observed_kpi /
-- fact_level_one_kpis, but never refreshed the mat view. The bursaries, CAMA
-- Members, and Community Champions metrics (which read from view_observed_kpi)
-- therefore stayed stale after every upload until the next Salesforce ETL run.

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

    REFRESH MATERIALIZED VIEW rep_portal.dashboard_data_agg;

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

    REFRESH MATERIALIZED VIEW rep_portal.dashboard_data_agg;

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

-- Fix 3: Refresh dashboard_data_agg after kpi_delete_year so the deleted
-- year's data disappears from the dashboard immediately.

CREATE OR REPLACE FUNCTION rep_warehouse.kpi_delete_year(p_year INTEGER)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_raw, rep_warehouse, rep_portal, public
AS $$
DECLARE
  v_batch_ids TEXT[];
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

  REFRESH MATERIALIZED VIEW rep_portal.dashboard_data_agg;

  RETURN jsonb_build_object('status', 'OK', 'year', p_year);
END;
$$;

-- Also refresh the mat view immediately so existing data is visible right away.
REFRESH MATERIALIZED VIEW rep_portal.dashboard_data_agg;


-- ===== 20260517132923_whatsapp_role_selection.sql =====
-- WhatsApp role selection during registration
-- Adds:
--   rep_portal.roles.whatsapp_available  — flag for bot-visible roles
--   rep_portal.whatsapp_users.role_id    — role selected during WA registration
--   Replaces: get_wa_report_permissions  — adds direct role_id path for WA-only users
--   Updates:  public.on_auth_user_created — auto-assigns WA-selected role on invite

-- ── Schema changes ─────────────────────────────────────────────────────────────

ALTER TABLE rep_portal.roles
  ADD COLUMN whatsapp_available BOOLEAN NOT NULL DEFAULT FALSE;

ALTER TABLE rep_portal.whatsapp_users
  ADD COLUMN role_id INTEGER REFERENCES rep_portal.roles(id) ON DELETE SET NULL;

-- ── RPC: get_wa_report_permissions — replace with dual-path version ────────────
-- Path 1 (unchanged): supabase_user_id → user_roles → role_permissions
-- Path 2 (new):       whatsapp_users.role_id directly (WA-only users not yet invited)

CREATE OR REPLACE FUNCTION rep_portal.get_wa_report_permissions(p_whatsapp_user_id INTEGER)
RETURNS TABLE(key TEXT) LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = rep_portal, public
AS $$
  -- Path 1: user has a linked Supabase account with roles
  SELECT DISTINCT p.key
  FROM rep_portal.whatsapp_users wu
  JOIN rep_portal.user_roles ur ON ur.user_id = wu.supabase_user_id
  JOIN rep_portal.role_permissions rp ON rp.role_id = ur.role_id
  JOIN rep_portal.permissions p ON p.id = rp.permission_id
  WHERE wu.id = p_whatsapp_user_id
    AND p.category = 'wa_report'
  UNION
  -- Path 2: user selected a role at WA registration (no Supabase link yet)
  SELECT DISTINCT p.key
  FROM rep_portal.whatsapp_users wu
  JOIN rep_portal.role_permissions rp ON rp.role_id = wu.role_id
  JOIN rep_portal.permissions p ON p.id = rp.permission_id
  WHERE wu.id = p_whatsapp_user_id
    AND p.category = 'wa_report'
    AND wu.role_id IS NOT NULL;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.get_wa_report_permissions(INTEGER) FROM PUBLIC;
REVOKE EXECUTE ON FUNCTION rep_portal.get_wa_report_permissions(INTEGER) FROM anon;
REVOKE EXECUTE ON FUNCTION rep_portal.get_wa_report_permissions(INTEGER) FROM authenticated;
GRANT  EXECUTE ON FUNCTION rep_portal.get_wa_report_permissions(INTEGER) TO service_role;

-- ── Trigger: auto-assign WA-selected role when user is invited to Supabase ─────
-- The existing on_auth_user_created trigger links whatsapp_users.supabase_user_id.
-- This update adds: if that row has a role_id, insert the role into user_roles.

CREATE OR REPLACE FUNCTION public.on_auth_user_created()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_portal, public
AS $$
DECLARE
  v_wa_role_id INTEGER;
BEGIN
  -- If an existing WhatsApp-registered row has this email but no Supabase link, link it
  UPDATE rep_portal.whatsapp_users
  SET supabase_user_id = NEW.id,
      linked_at        = NOW()
  WHERE id = (
    SELECT id FROM rep_portal.whatsapp_users
    WHERE email = NEW.email AND supabase_user_id IS NULL
    ORDER BY created_at
    LIMIT 1
  )
  RETURNING role_id INTO v_wa_role_id;

  -- If nothing was linked, create a portal-only row (phone = '' satisfies NOT NULL)
  IF NOT FOUND THEN
    INSERT INTO rep_portal.whatsapp_users (phone, email, supabase_user_id, linked_at)
    VALUES ('', NEW.email, NEW.id, NOW());
  END IF;

  -- If the linked WA user had a role selected at registration, assign it now
  IF v_wa_role_id IS NOT NULL THEN
    INSERT INTO rep_portal.user_roles (user_id, role_id)
    VALUES (NEW.id, v_wa_role_id)
    ON CONFLICT DO NOTHING;
  END IF;

  RETURN NEW;
END;
$$;


-- ===== 20260517141148_fix_bot_districts_null_province.sql =====
-- Fix empty province option in WhatsApp bot registration.
-- get_bot_districts previously only filtered district IS NOT NULL,
-- allowing rows with a NULL province to produce a blank list entry.

CREATE OR REPLACE FUNCTION rep_portal.get_bot_districts()
RETURNS TABLE (country TEXT, province TEXT, district TEXT)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
  SELECT DISTINCT
    g.country::TEXT,
    g.province::TEXT,
    g.district::TEXT
  FROM rep_warehouse.dim_geography g
  WHERE g.scd_is_current = true
    AND g.district IS NOT NULL
    AND g.province IS NOT NULL
    AND g.country  IS NOT NULL
  ORDER BY 1, 2, 3;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.get_bot_districts() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_bot_districts() TO service_role;


-- ===== 20260517141419_fix_bot_districts_null_province.sql =====
-- Duplicate of 20260517141148_fix_bot_districts_null_province.sql — no-op.
SELECT 1;


-- ===== 20260520070904_user_countries.sql =====
-- User ↔ Country association table.
-- Stores which countries each portal user is linked to.
-- The data-filtering layer (down the line) will read this to scope dashboard queries.

CREATE TABLE rep_portal.user_countries (
  id          BIGSERIAL    PRIMARY KEY,
  user_id     UUID         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  country     TEXT         NOT NULL,
  assigned_by UUID         REFERENCES auth.users(id),
  assigned_at TIMESTAMPTZ  NOT NULL DEFAULT now(),
  UNIQUE (user_id, country)
);

ALTER TABLE rep_portal.user_countries ENABLE ROW LEVEL SECURITY;

-- Admins can do everything; each user can read their own rows.
CREATE POLICY "user_countries_admin_all"
  ON rep_portal.user_countries
  FOR ALL
  USING (rep_warehouse.is_admin());

CREATE POLICY "user_countries_user_read_own"
  ON rep_portal.user_countries
  FOR SELECT
  USING (auth.uid() = user_id);

-- ── Helper functions ──────────────────────────────────────────────────────────

-- Returns distinct country names that exist in the warehouse (for the admin picker).
CREATE OR REPLACE FUNCTION rep_portal.get_available_countries()
RETURNS TABLE (country TEXT)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT DISTINCT g.country
  FROM   rep_warehouse.dim_geography g
  WHERE  g.is_country = true
    AND  g.scd_is_current = true
  ORDER  BY g.country;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_available_countries() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_available_countries() TO authenticated;

-- Returns country TEXT[] for the calling user (non-admin portal usage).
CREATE OR REPLACE FUNCTION rep_portal.get_my_countries()
RETURNS TEXT[]
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT COALESCE(array_agg(uc.country ORDER BY uc.country), ARRAY[]::TEXT[])
  FROM   rep_portal.user_countries uc
  WHERE  uc.user_id = auth.uid();
$$;

REVOKE ALL ON FUNCTION rep_portal.get_my_countries() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_my_countries() TO authenticated;

-- Returns countries assigned to any user (admin callable).
CREATE OR REPLACE FUNCTION rep_portal.get_user_countries(p_user_id UUID)
RETURNS TEXT[]
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  RETURN (
    SELECT COALESCE(array_agg(uc.country ORDER BY uc.country), ARRAY[]::TEXT[])
    FROM   rep_portal.user_countries uc
    WHERE  uc.user_id = p_user_id
  );
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_user_countries(UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_user_countries(UUID) TO authenticated;

-- Replaces the full country set for a user (admin callable).
-- Pass an empty array to clear all assignments.
CREATE OR REPLACE FUNCTION rep_portal.set_user_countries(p_user_id UUID, p_countries TEXT[])
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  DELETE FROM rep_portal.user_countries WHERE user_id = p_user_id;

  IF array_length(p_countries, 1) > 0 THEN
    INSERT INTO rep_portal.user_countries (user_id, country, assigned_by)
    SELECT p_user_id, unnest(p_countries), auth.uid();
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.set_user_countries(UUID, TEXT[]) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.set_user_countries(UUID, TEXT[]) TO authenticated;


-- ===== 20260520075038_grant_user_countries.sql =====
-- Grant table-level SELECT to authenticated so PostgREST can evaluate RLS.
-- Admins get full access via the user_countries_admin_all policy;
-- regular users can only read their own rows via user_countries_user_read_own.
GRANT SELECT ON rep_portal.user_countries TO authenticated;


-- ===== 20260520075544_grant_is_admin_execute.sql =====
-- user_countries is queried directly by PostgREST (not through a SECURITY DEFINER
-- wrapper), so the authenticated role must be able to call is_admin() when
-- PostgreSQL evaluates the RLS policy.
GRANT EXECUTE ON FUNCTION rep_warehouse.is_admin() TO authenticated;


-- ===== 20260526152914_dd_permissions.sql =====
-- Dynamic Data (dd:*) permission keys.
-- These independently gate each metric dashlet on the /dynamic page.
-- parent_key = 'Dynamic Data' groups them in the role editor UI automatically.
-- All 10 are added to the Full Access role so no existing user loses access.

INSERT INTO rep_portal.permissions (key, label, category, parent_key) VALUES
  ('dd:children_supported',     'Children Supported in School with Education Bursaries', 'dashlet', 'Dynamic Data'),
  ('dd:active_learner_guides',  'Active Learner Guides',                                 'dashlet', 'Dynamic Data'),
  ('dd:clients_by_form',        'Number of Clients by Form',                             'dashlet', 'Dynamic Data'),
  ('dd:active_partner_schools', 'Active Partner Schools',                                'dashlet', 'Dynamic Data'),
  ('dd:women_tertiary',         'Number of Women Supported by CAMFED in Tertiary Education', 'dashlet', 'Dynamic Data'),
  ('dd:guides_by_type',         'Active Guides by Type',                                 'dashlet', 'Dynamic Data'),
  ('dd:post_school_clients',    'Number of Post School Clients',                         'dashlet', 'Dynamic Data'),
  ('dd:grants_disbursed',       'Grants Disbursed',                                      'dashlet', 'Dynamic Data'),
  ('dd:loans_disbursed',        'Loans Disbursed',                                       'dashlet', 'Dynamic Data'),
  ('dd:cama_members',           'CAMA Members',                                          'dashlet', 'Dynamic Data');

-- Map each dd:* key to the dashboard_data_agg metric strings it unlocks.
-- get_dashboard_data_scoped() uses these entries to filter data rows server-side.

INSERT INTO rep_portal.permission_metric_map (permission_key, metric_id) VALUES
  -- Children Supported (all disaggregation variants used by the double-line chart)
  ('dd:children_supported', 'Children Supported in School with Education Bursaries'),
  ('dd:children_supported', 'Children Supported in School with Education Bursaries — Annual'),
  ('dd:children_supported', 'Children Supported in School with Education Bursaries — Cumulative 2020-2030'),
  ('dd:children_supported', 'Children Supported in School with Education Bursaries — Cumulative all-time'),

  ('dd:active_learner_guides', 'Active Learner Guides'),

  -- Clients by Form (total + gender splits used by ClientsByFormChart)
  ('dd:clients_by_form', 'Number of Clients by Form'),
  ('dd:clients_by_form', 'Number of Clients by Form — Girls'),
  ('dd:clients_by_form', 'Number of Clients by Form — Boys'),

  ('dd:active_partner_schools', 'Active Partner Schools'),

  ('dd:women_tertiary', 'Number of Women Supported by CAMFED in Tertiary Education'),

  -- Guides by Type (aggregate + sub-types used by GroupedStackedChart)
  ('dd:guides_by_type', 'Active Guides by Type'),
  ('dd:guides_by_type', 'Active Guides — Transition'),
  ('dd:guides_by_type', 'Active Guides — Agriculture'),
  ('dd:guides_by_type', 'Active Guides — Business'),

  ('dd:post_school_clients', 'Number of Post School Clients'),

  ('dd:grants_disbursed', 'Grants Disbursed'),
  ('dd:grants_disbursed', 'Grants Distributed — Count'),

  ('dd:loans_disbursed', 'Loans Disbursed'),
  ('dd:loans_disbursed', 'Loans Disbursed — Agriculture'),
  ('dd:loans_disbursed', 'Loans Disbursed — Business'),
  ('dd:loans_disbursed', 'Loans Disbursed — Kiva'),
  ('dd:loans_disbursed', 'Loans Disbursed — RIF'),

  ('dd:cama_members', 'CAMA Members');

-- Grant all new dd:* permissions to the Full Access role.
INSERT INTO rep_portal.role_permissions (role_id, permission_id)
SELECT
  (SELECT id FROM rep_portal.roles WHERE name = 'Full Access'),
  p.id
FROM rep_portal.permissions p
WHERE p.key LIKE 'dd:%';


-- ===== 20260526163446_rename_dd_parent_key.sql =====


-- ===== 20260526163707_rename_dd_parent_key.sql =====


-- ===== 20260526163827_rename_dd_parent_key.sql =====
-- Rename the dd:* permission group from 'Dynamic Data' to 'Dynamic Data + Map'
-- to reflect that these permissions also gate the map KPI dropdown.

UPDATE rep_portal.permissions
SET parent_key = 'Dynamic Data + Map'
WHERE parent_key = 'Dynamic Data';


-- ===== 20260526171055_add_page_permissions.sql =====
-- Add page-level permissions: page:dashboard, page:dynamic, page:map
-- These gate access to the three main portal pages.

-- Drop the old CHECK constraint (auto-named by PostgreSQL) and recreate with 'page' added.
ALTER TABLE rep_portal.permissions
  DROP CONSTRAINT IF EXISTS permissions_category_check;

ALTER TABLE rep_portal.permissions
  ADD CONSTRAINT permissions_category_check
  CHECK (category IN ('dashlet', 'wa_report', 'page'));

-- Insert the three page permissions.
INSERT INTO rep_portal.permissions (key, label, description, category, parent_key)
VALUES
  ('page:dashboard', 'Data Dashboard', 'Access to the /dashboard page', 'page', NULL),
  ('page:dynamic',   'Dynamic Data',   'Access to the /dynamic page',   'page', NULL),
  ('page:map',       'Data Map',       'Access to the /map page',        'page', NULL);

-- Grant all 3 page permissions to the Full Access role so all existing users retain access.
-- The trg_assign_default_role trigger already handles newly invited users.
INSERT INTO rep_portal.role_permissions (role_id, permission_id)
SELECT
  (SELECT id FROM rep_portal.roles WHERE name = 'Full Access'),
  p.id
FROM rep_portal.permissions p
WHERE p.key IN ('page:dashboard', 'page:dynamic', 'page:map');


-- ===== 20260526201853_grant_user_countries_service_role.sql =====
-- service_role bypasses RLS but still needs table-level GRANT.
-- The edge function's admin client (service role key) queries user_countries
-- directly to scope country-admin user lists, so service_role needs SELECT.
-- INSERT/UPDATE/DELETE are handled by set_user_countries() SECURITY DEFINER.
GRANT SELECT ON rep_portal.user_countries TO service_role;


-- ===== 20260526203101_set_user_countries_allow_country_admin.sql =====
-- Allow country admins to set countries for users within their scope.
-- Restrictions:
--   1. All countries in p_countries must be a subset of the caller's own countries.
--   2. The target user must already share at least one country with the caller
--      (i.e. they appear in the caller's scoped user list).
-- Full admins are unrestricted as before.
CREATE OR REPLACE FUNCTION rep_portal.set_user_countries(p_user_id UUID, p_countries TEXT[])
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_caller_role   TEXT;
  v_is_admin      BOOLEAN;
  v_is_ca         BOOLEAN;
  v_caller_id     UUID;
  v_caller_countries TEXT[];
  v_invalid_count INT;
  v_in_scope      BOOLEAN;
BEGIN
  v_caller_role := auth.jwt() -> 'app_metadata' ->> 'role';
  v_is_admin    := v_caller_role = 'admin';
  v_is_ca       := v_caller_role = 'country_admin';
  v_caller_id   := auth.uid();

  IF NOT v_is_admin AND NOT v_is_ca THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  IF v_is_ca THEN
    -- Load caller's own countries
    SELECT COALESCE(array_agg(uc.country), ARRAY[]::TEXT[])
    INTO   v_caller_countries
    FROM   rep_portal.user_countries uc
    WHERE  uc.user_id = v_caller_id;

    -- All requested countries must be within the caller's own set
    SELECT COUNT(*) INTO v_invalid_count
    FROM   unnest(p_countries) AS c
    WHERE  c <> ALL(v_caller_countries);

    IF v_invalid_count > 0 THEN
      RAISE EXCEPTION 'Country admin can only assign countries within their own scope';
    END IF;

    -- Target user must already share at least one country with the caller
    -- (unless they have no countries yet — allow initial assignment)
    SELECT EXISTS (
      SELECT 1 FROM rep_portal.user_countries
      WHERE  user_id = p_user_id
        AND  country = ANY(v_caller_countries)
    ) INTO v_in_scope;

    IF NOT v_in_scope AND EXISTS (
      SELECT 1 FROM rep_portal.user_countries WHERE user_id = p_user_id
    ) THEN
      RAISE EXCEPTION 'Target user is outside your country scope';
    END IF;
  END IF;

  DELETE FROM rep_portal.user_countries WHERE user_id = p_user_id;

  IF array_length(p_countries, 1) > 0 THEN
    INSERT INTO rep_portal.user_countries (user_id, country, assigned_by)
    SELECT p_user_id, unnest(p_countries), v_caller_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.set_user_countries(UUID, TEXT[]) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.set_user_countries(UUID, TEXT[]) TO authenticated;


-- ===== 20260527000001_add_cumulative_2024_metric.sql =====
-- Add "Cumulative (2024-2030)" disaggregation variant to dashboard_data_agg.
-- This rebuilds the materialized view in full (ALTER is not supported on mat views)
-- with one new UNION ALL block added after the existing Cumulative (2020-2030) block.
-- Also adds the new metric to permission_metric_map for the dd:children_supported key.

DROP MATERIALIZED VIEW IF EXISTS rep_portal.dashboard_data_agg;

CREATE MATERIALIZED VIEW rep_portal.dashboard_data_agg AS

WITH valid_countries AS (
  SELECT DISTINCT country
  FROM rep_warehouse.view_observed_kpi
  WHERE country IS NOT NULL
)

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Newly supported'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Annual'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Annual'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Cumulative 2020-2030'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Cumulative (2020-2030)'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- NEW: Cumulative (2024-2030) variant — powers the "Cumulative since 2024" dropdown option
SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Cumulative 2024-2030'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Cumulative (2024-2030)'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Cumulative all-time'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Cumulative (all-time)'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Learner Guides'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_type = 'Learner Guide' AND v.guide_status = 'Active' AND v.school_name IS NOT NULL
GROUP BY v.country, v.district, v.school_name

UNION ALL

SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form — Girls'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.gender = 'Female'
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form — Boys'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.gender = 'Male'
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Active Partner Schools'::text AS metric,
       COUNT(DISTINCT v.school_name)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Number of Women Supported by CAMFED in Tertiary Education'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_post_school_support v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Guides by Type'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_status = 'Active' AND v.school_name IS NOT NULL
GROUP BY v.country, v.district, v.school_name

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Number of Post School Clients'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_post_school_support v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.grant_year AS year,
       'Grants Disbursed'::text AS metric,
       ROUND(SUM(v.amount_given::numeric))::int AS value
FROM rep_warehouse.view_grants v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.grant_year IS NOT NULL
GROUP BY v.country, v.district, v.grant_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed'::text AS metric,
       ROUND(SUM(COALESCE(v.loan_value, 0)))::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'CAMA Members'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school by CAMA'
  AND disaggregation_level_one = 'Newly supported'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Community Champions'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school through community initiatives'
  AND disaggregation_level_one = 'Newly supported'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Guides — Transition'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_status = 'Active' AND v.school_name IS NOT NULL
  AND v.guide_type ILIKE '%Transition%'
GROUP BY v.country, v.district, v.school_name

UNION ALL

SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Guides — Agriculture'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_status = 'Active' AND v.school_name IS NOT NULL
  AND v.guide_type ILIKE '%Agri%'
GROUP BY v.country, v.district, v.school_name

UNION ALL

SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Guides — Business'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_status = 'Active' AND v.school_name IS NOT NULL
  AND (v.guide_type ILIKE '%Business%' OR v.guide_type ILIKE '%Enterprise%')
GROUP BY v.country, v.district, v.school_name

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.grant_year AS year,
       'Grants Distributed — Count'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_grants v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.grant_year IS NOT NULL
GROUP BY v.country, v.district, v.grant_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Agriculture'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%Agri%'
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Business'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL
  AND (v.loan_type ILIKE '%Business%' OR v.loan_type ILIKE '%Enterprise%')
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Kiva'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%Kiva%'
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — RIF'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%RIF%'
GROUP BY v.country, v.district, v.disbursal_year

WITH NO DATA;

-- Register the new cumulative variant in the permission gate
INSERT INTO rep_portal.permission_metric_map (permission_key, metric_id) VALUES
  ('dd:children_supported', 'Children Supported in School with Education Bursaries — Cumulative 2024-2030')
ON CONFLICT DO NOTHING;

-- Populate the new rows immediately
REFRESH MATERIALIZED VIEW rep_portal.dashboard_data_agg;


-- ===== 20260527000002_add_cama_community_annual_metrics.sql =====
-- Add Annual disaggregation variants for CAMA Members and Community Champions.
-- These power the "Annual Total" toggle option on the Education Reach chart.
-- Full view rebuild required (ALTER not supported on materialized views).

DROP MATERIALIZED VIEW IF EXISTS rep_portal.dashboard_data_agg;

CREATE MATERIALIZED VIEW rep_portal.dashboard_data_agg AS

WITH valid_countries AS (
  SELECT DISTINCT country
  FROM rep_warehouse.view_observed_kpi
  WHERE country IS NOT NULL
)

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Newly supported'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Annual'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Annual'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Cumulative 2020-2030'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Cumulative (2020-2030)'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Cumulative 2024-2030'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Cumulative (2024-2030)'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Cumulative all-time'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Cumulative (all-time)'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Learner Guides'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_type = 'Learner Guide' AND v.guide_status = 'Active' AND v.school_name IS NOT NULL
GROUP BY v.country, v.district, v.school_name

UNION ALL

SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form — Girls'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.gender = 'Female'
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form — Boys'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.gender = 'Male'
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Active Partner Schools'::text AS metric,
       COUNT(DISTINCT v.school_name)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Number of Women Supported by CAMFED in Tertiary Education'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_post_school_support v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Guides by Type'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_status = 'Active' AND v.school_name IS NOT NULL
GROUP BY v.country, v.district, v.school_name

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Number of Post School Clients'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_post_school_support v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.grant_year AS year,
       'Grants Disbursed'::text AS metric,
       ROUND(SUM(v.amount_given::numeric))::int AS value
FROM rep_warehouse.view_grants v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.grant_year IS NOT NULL
GROUP BY v.country, v.district, v.grant_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed'::text AS metric,
       ROUND(SUM(COALESCE(v.loan_value, 0)))::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

-- CAMA Members — Newly supported (original)
SELECT country, 'National' AS district, 'National' AS school, year,
       'CAMA Members'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school by CAMA'
  AND disaggregation_level_one = 'Newly supported'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- CAMA Members — Annual (NEW: powers "Annual Total" toggle)
SELECT country, 'National' AS district, 'National' AS school, year,
       'CAMA Members — Annual'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school by CAMA'
  AND disaggregation_level_one = 'Annual'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- Community Champions — Newly supported (original)
SELECT country, 'National' AS district, 'National' AS school, year,
       'Community Champions'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school through community initiatives'
  AND disaggregation_level_one = 'Newly supported'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- Community Champions — Annual (NEW: powers "Annual Total" toggle)
SELECT country, 'National' AS district, 'National' AS school, year,
       'Community Champions — Annual'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school through community initiatives'
  AND disaggregation_level_one = 'Annual'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Guides — Transition'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_status = 'Active' AND v.school_name IS NOT NULL
  AND v.guide_type ILIKE '%Transition%'
GROUP BY v.country, v.district, v.school_name

UNION ALL

SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Guides — Agriculture'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_status = 'Active' AND v.school_name IS NOT NULL
  AND v.guide_type ILIKE '%Agri%'
GROUP BY v.country, v.district, v.school_name

UNION ALL

SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Guides — Business'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_status = 'Active' AND v.school_name IS NOT NULL
  AND (v.guide_type ILIKE '%Business%' OR v.guide_type ILIKE '%Enterprise%')
GROUP BY v.country, v.district, v.school_name

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.grant_year AS year,
       'Grants Distributed — Count'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_grants v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.grant_year IS NOT NULL
GROUP BY v.country, v.district, v.grant_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Agriculture'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%Agri%'
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Business'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL
  AND (v.loan_type ILIKE '%Business%' OR v.loan_type ILIKE '%Enterprise%')
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Kiva'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%Kiva%'
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — RIF'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%RIF%'
GROUP BY v.country, v.district, v.disbursal_year

WITH NO DATA;

-- Register the new Annual variants in the permission gate
INSERT INTO rep_portal.permission_metric_map (permission_key, metric_id) VALUES
  ('dd:cama_members', 'CAMA Members — Annual'),
  ('dd:children_supported', 'Community Champions — Annual')
ON CONFLICT DO NOTHING;

REFRESH MATERIALIZED VIEW rep_portal.dashboard_data_agg;


-- ===== 20260527000003_add_clients_by_form_level_metrics.sql =====
-- Add per-form-level breakdowns for "Number of Clients by Form" chart.
-- Powers the ClientsByFormChart component which shows Primary / Junior Secondary /
-- Senior Secondary / Tertiary / Other stacked bars.
-- Form values mapped from actual DB values (confirmed via query 2026-05-27):
--   Primary          : Stnd 5-8, Grade 2/4-7
--   Junior Secondary : Form 1-3, JH1-3, Grade 8-9
--   Senior Secondary : Form 4-6, SH1-3, Grade 10-12
--   Tertiary         : Tertiary 1-4
--   Other            : everything else (including null form)

DROP MATERIALIZED VIEW IF EXISTS rep_portal.dashboard_data_agg;

CREATE MATERIALIZED VIEW rep_portal.dashboard_data_agg AS

WITH valid_countries AS (
  SELECT DISTINCT country
  FROM rep_warehouse.view_observed_kpi
  WHERE country IS NOT NULL
)

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Newly supported'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Annual'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Annual'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Cumulative 2020-2030'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Cumulative (2020-2030)'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Cumulative 2024-2030'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Cumulative (2024-2030)'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Cumulative all-time'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Cumulative (all-time)'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Learner Guides'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_type = 'Learner Guide' AND v.guide_status = 'Active' AND v.school_name IS NOT NULL
GROUP BY v.country, v.district, v.school_name

UNION ALL

SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form — Girls'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.gender = 'Female'
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form — Boys'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.gender = 'Male'
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

-- Per-form-level breakdowns (power the ClientsByFormChart stacked bar)
SELECT v.country, v.district, v.school_name AS school, v.year,
       CASE
         WHEN v.form IN ('Stnd 5','Stnd 6','Stnd 7','Stnd 8',
                         'Grade 1','Grade 2','Grade 3','Grade 4','Grade 5','Grade 6','Grade 7')
           THEN 'Clients by Form — Primary'
         WHEN v.form IN ('Form 1','Form 2','Form 3','JH1','JH2','JH3','Grade 8','Grade 9')
           THEN 'Clients by Form — Junior Secondary'
         WHEN v.form IN ('Form 4','Form 5','Form 6','SH1','SH2','SH3','Grade 10','Grade 11','Grade 12')
           THEN 'Clients by Form — Senior Secondary'
         WHEN v.form ILIKE 'Tertiary%'
           THEN 'Clients by Form — Tertiary'
         ELSE 'Clients by Form — Other'
       END AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL
GROUP BY v.country, v.district, v.school_name, v.year,
         CASE
           WHEN v.form IN ('Stnd 5','Stnd 6','Stnd 7','Stnd 8',
                           'Grade 1','Grade 2','Grade 3','Grade 4','Grade 5','Grade 6','Grade 7')
             THEN 'Clients by Form — Primary'
           WHEN v.form IN ('Form 1','Form 2','Form 3','JH1','JH2','JH3','Grade 8','Grade 9')
             THEN 'Clients by Form — Junior Secondary'
           WHEN v.form IN ('Form 4','Form 5','Form 6','SH1','SH2','SH3','Grade 10','Grade 11','Grade 12')
             THEN 'Clients by Form — Senior Secondary'
           WHEN v.form ILIKE 'Tertiary%'
             THEN 'Clients by Form — Tertiary'
           ELSE 'Clients by Form — Other'
         END

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Active Partner Schools'::text AS metric,
       COUNT(DISTINCT v.school_name)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Number of Women Supported by CAMFED in Tertiary Education'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_post_school_support v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Guides by Type'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_status = 'Active' AND v.school_name IS NOT NULL
GROUP BY v.country, v.district, v.school_name

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Number of Post School Clients'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_post_school_support v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.grant_year AS year,
       'Grants Disbursed'::text AS metric,
       ROUND(SUM(v.amount_given::numeric))::int AS value
FROM rep_warehouse.view_grants v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.grant_year IS NOT NULL
GROUP BY v.country, v.district, v.grant_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed'::text AS metric,
       ROUND(SUM(COALESCE(v.loan_value, 0)))::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

-- CAMA Members — Newly supported
SELECT country, 'National' AS district, 'National' AS school, year,
       'CAMA Members'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school by CAMA'
  AND disaggregation_level_one = 'Newly supported'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- CAMA Members — Annual
SELECT country, 'National' AS district, 'National' AS school, year,
       'CAMA Members — Annual'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school by CAMA'
  AND disaggregation_level_one = 'Annual'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- Community Champions — Newly supported
SELECT country, 'National' AS district, 'National' AS school, year,
       'Community Champions'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school through community initiatives'
  AND disaggregation_level_one = 'Newly supported'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- Community Champions — Annual
SELECT country, 'National' AS district, 'National' AS school, year,
       'Community Champions — Annual'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school through community initiatives'
  AND disaggregation_level_one = 'Annual'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Guides — Transition'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_status = 'Active' AND v.school_name IS NOT NULL
  AND v.guide_type ILIKE '%Transition%'
GROUP BY v.country, v.district, v.school_name

UNION ALL

SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Guides — Agriculture'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_status = 'Active' AND v.school_name IS NOT NULL
  AND v.guide_type ILIKE '%Agri%'
GROUP BY v.country, v.district, v.school_name

UNION ALL

SELECT v.country, v.district, v.school_name AS school, 2025 AS year,
       'Active Guides — Business'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.guide_status = 'Active' AND v.school_name IS NOT NULL
  AND (v.guide_type ILIKE '%Business%' OR v.guide_type ILIKE '%Enterprise%')
GROUP BY v.country, v.district, v.school_name

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.grant_year AS year,
       'Grants Distributed — Count'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_grants v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.grant_year IS NOT NULL
GROUP BY v.country, v.district, v.grant_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Agriculture'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%Agri%'
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Business'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL
  AND (v.loan_type ILIKE '%Business%' OR v.loan_type ILIKE '%Enterprise%')
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Kiva'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%Kiva%'
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — RIF'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%RIF%'
GROUP BY v.country, v.district, v.disbursal_year

WITH NO DATA;

-- Register form-level metrics in the permission gate
INSERT INTO rep_portal.permission_metric_map (permission_key, metric_id) VALUES
  ('dd:clients_by_form', 'Clients by Form — Primary'),
  ('dd:clients_by_form', 'Clients by Form — Junior Secondary'),
  ('dd:clients_by_form', 'Clients by Form — Senior Secondary'),
  ('dd:clients_by_form', 'Clients by Form — Tertiary'),
  ('dd:clients_by_form', 'Clients by Form — Other')
ON CONFLICT DO NOTHING;

REFRESH MATERIALIZED VIEW rep_portal.dashboard_data_agg;


-- ===== 20260527000004_guide_metrics_time_series.sql =====
-- Replace hardcoded year=2025 guide metrics with proper time-series aggregations.
-- Uses joined_year / left_year to compute how many guides were active in each year:
--   active in year Y  ⟺  joined_year <= Y AND (left_year IS NULL OR left_year >= Y)
-- This gives a year-by-year count instead of a single 2025 snapshot.

DROP MATERIALIZED VIEW IF EXISTS rep_portal.dashboard_data_agg;

CREATE MATERIALIZED VIEW rep_portal.dashboard_data_agg AS

WITH valid_countries AS (
  SELECT DISTINCT country
  FROM rep_warehouse.view_observed_kpi
  WHERE country IS NOT NULL
),
years AS (
  SELECT generate_series(2020, 2030) AS yr
)

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Newly supported'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Annual'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Annual'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Cumulative 2020-2030'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Cumulative (2020-2030)'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Cumulative 2024-2030'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Cumulative (2024-2030)'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Cumulative all-time'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Cumulative (all-time)'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- Active Learner Guides — time series using joined_year / left_year
SELECT v.country, v.district, v.school_name AS school, y.yr AS year,
       'Active Learner Guides'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
CROSS JOIN years y
WHERE v.guide_type = 'Learner Guide'
  AND v.school_name IS NOT NULL
  AND v.joined_year IS NOT NULL
  AND v.joined_year <= y.yr
  AND (v.left_year IS NULL OR v.left_year >= y.yr)
GROUP BY v.country, v.district, v.school_name, y.yr

UNION ALL

SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form — Girls'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.gender = 'Female'
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form — Boys'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.gender = 'Male'
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

-- Per-form-level breakdowns
SELECT v.country, v.district, v.school_name AS school, v.year,
       CASE
         WHEN v.form IN ('Stnd 5','Stnd 6','Stnd 7','Stnd 8',
                         'Grade 1','Grade 2','Grade 3','Grade 4','Grade 5','Grade 6','Grade 7')
           THEN 'Clients by Form — Primary'
         WHEN v.form IN ('Form 1','Form 2','Form 3','JH1','JH2','JH3','Grade 8','Grade 9')
           THEN 'Clients by Form — Junior Secondary'
         WHEN v.form IN ('Form 4','Form 5','Form 6','SH1','SH2','SH3','Grade 10','Grade 11','Grade 12')
           THEN 'Clients by Form — Senior Secondary'
         WHEN v.form ILIKE 'Tertiary%'
           THEN 'Clients by Form — Tertiary'
         ELSE 'Clients by Form — Other'
       END AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL
GROUP BY v.country, v.district, v.school_name, v.year,
         CASE
           WHEN v.form IN ('Stnd 5','Stnd 6','Stnd 7','Stnd 8',
                           'Grade 1','Grade 2','Grade 3','Grade 4','Grade 5','Grade 6','Grade 7')
             THEN 'Clients by Form — Primary'
           WHEN v.form IN ('Form 1','Form 2','Form 3','JH1','JH2','JH3','Grade 8','Grade 9')
             THEN 'Clients by Form — Junior Secondary'
           WHEN v.form IN ('Form 4','Form 5','Form 6','SH1','SH2','SH3','Grade 10','Grade 11','Grade 12')
             THEN 'Clients by Form — Senior Secondary'
           WHEN v.form ILIKE 'Tertiary%'
             THEN 'Clients by Form — Tertiary'
           ELSE 'Clients by Form — Other'
         END

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Active Partner Schools'::text AS metric,
       COUNT(DISTINCT v.school_name)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Number of Women Supported by CAMFED in Tertiary Education'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_post_school_support v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

-- Active Guides by Type — time series
SELECT v.country, v.district, v.school_name AS school, y.yr AS year,
       'Active Guides by Type'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
CROSS JOIN years y
WHERE v.school_name IS NOT NULL
  AND v.joined_year IS NOT NULL
  AND v.joined_year <= y.yr
  AND (v.left_year IS NULL OR v.left_year >= y.yr)
GROUP BY v.country, v.district, v.school_name, y.yr

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Number of Post School Clients'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_post_school_support v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.grant_year AS year,
       'Grants Disbursed'::text AS metric,
       ROUND(SUM(v.amount_given::numeric))::int AS value
FROM rep_warehouse.view_grants v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.grant_year IS NOT NULL
GROUP BY v.country, v.district, v.grant_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed'::text AS metric,
       ROUND(SUM(COALESCE(v.loan_value, 0)))::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

-- CAMA Members — Newly supported
SELECT country, 'National' AS district, 'National' AS school, year,
       'CAMA Members'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school by CAMA'
  AND disaggregation_level_one = 'Newly supported'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- CAMA Members — Annual
SELECT country, 'National' AS district, 'National' AS school, year,
       'CAMA Members — Annual'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school by CAMA'
  AND disaggregation_level_one = 'Annual'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- Community Champions — Newly supported
SELECT country, 'National' AS district, 'National' AS school, year,
       'Community Champions'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school through community initiatives'
  AND disaggregation_level_one = 'Newly supported'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- Community Champions — Annual
SELECT country, 'National' AS district, 'National' AS school, year,
       'Community Champions — Annual'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school through community initiatives'
  AND disaggregation_level_one = 'Annual'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- Active Guides — Transition: time series
SELECT v.country, v.district, v.school_name AS school, y.yr AS year,
       'Active Guides — Transition'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
CROSS JOIN years y
WHERE v.school_name IS NOT NULL
  AND v.guide_type ILIKE '%Transition%'
  AND v.joined_year IS NOT NULL
  AND v.joined_year <= y.yr
  AND (v.left_year IS NULL OR v.left_year >= y.yr)
GROUP BY v.country, v.district, v.school_name, y.yr

UNION ALL

-- Active Guides — Agriculture: time series
SELECT v.country, v.district, v.school_name AS school, y.yr AS year,
       'Active Guides — Agriculture'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
CROSS JOIN years y
WHERE v.school_name IS NOT NULL
  AND v.guide_type ILIKE '%Agri%'
  AND v.joined_year IS NOT NULL
  AND v.joined_year <= y.yr
  AND (v.left_year IS NULL OR v.left_year >= y.yr)
GROUP BY v.country, v.district, v.school_name, y.yr

UNION ALL

-- Active Guides — Business: time series
SELECT v.country, v.district, v.school_name AS school, y.yr AS year,
       'Active Guides — Business'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
CROSS JOIN years y
WHERE v.school_name IS NOT NULL
  AND (v.guide_type ILIKE '%Business%' OR v.guide_type ILIKE '%Enterprise%')
  AND v.joined_year IS NOT NULL
  AND v.joined_year <= y.yr
  AND (v.left_year IS NULL OR v.left_year >= y.yr)
GROUP BY v.country, v.district, v.school_name, y.yr

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.grant_year AS year,
       'Grants Distributed — Count'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_grants v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.grant_year IS NOT NULL
GROUP BY v.country, v.district, v.grant_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Agriculture'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%Agri%'
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Business'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL
  AND (v.loan_type ILIKE '%Business%' OR v.loan_type ILIKE '%Enterprise%')
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Kiva'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%Kiva%'
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — RIF'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%RIF%'
GROUP BY v.country, v.district, v.disbursal_year

WITH NO DATA;

REFRESH MATERIALIZED VIEW rep_portal.dashboard_data_agg;


-- ===== 20260528000001_get_observed_kpi_add_quarter_scope.sql =====
-- Extend get_observed_kpi to return year_quarter and row_scope so the
-- frontend can filter to ANNUAL rows only (avoiding quarterly duplicates)
-- and distinguish cumulative vs annual data without a second RPC call.

CREATE OR REPLACE FUNCTION public.get_observed_kpi(p_kpi_id TEXT)
RETURNS TABLE (
  country                  TEXT,
  kpi_id                   TEXT,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  year                     INTEGER,
  year_quarter             INTEGER,
  row_scope                TEXT,
  value                    TEXT
) LANGUAGE sql SECURITY DEFINER AS $$
  SELECT
    v.country,
    v.kpi_id,
    v.disaggregation_level_one,
    v.disaggregation_level_two,
    v.year,
    v.year_quarter,
    v.row_scope,
    v.value
  FROM rep_warehouse.view_observed_kpi v
  WHERE v.kpi_id = p_kpi_id
    AND v.year IS NOT NULL
    AND v.country IS NOT NULL;
$$;

GRANT EXECUTE ON FUNCTION public.get_observed_kpi(TEXT) TO anon, authenticated;


-- ===== 20260528000002_add_cama_leadership_permission.sql =====
-- Register CAMA Members in Leadership Roles dashlet (KPI 2.13)
INSERT INTO rep_portal.permissions (key, label, category, parent_key)
VALUES ('dashlet:leadership_tertiary:cama_leadership', 'CAMA Members in Leadership Roles', 'dashlet', 'Leadership & Tertiary')
ON CONFLICT (key) DO NOTHING;

INSERT INTO rep_portal.permission_metric_map (permission_key, metric_id)
VALUES ('dashlet:leadership_tertiary:cama_leadership', '2.13')
ON CONFLICT DO NOTHING;


-- ===== 20260528000003_fix_get_observed_kpi_security_invoker.sql =====
-- rep_portal.get_observed_kpi was calling rep_warehouse.view_observed_kpi which
-- has security_invoker=on.  Inside a SECURITY DEFINER function that makes the
-- view run as the calling authenticated user, who lacks direct table grants on
-- fact_observed_kpi — so the function silently returned 0 rows.
--
-- Fix: join the base tables directly so SECURITY DEFINER is effective, and also
-- extend the return type with row_scope + year_quarter so the frontend can
-- filter to ANNUAL rows only.

DROP FUNCTION IF EXISTS rep_portal.get_observed_kpi(TEXT);

CREATE OR REPLACE FUNCTION rep_portal.get_observed_kpi(p_kpi_id TEXT)
RETURNS TABLE (
  country                  TEXT,
  kpi_id                   TEXT,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  year                     INTEGER,
  year_quarter             INTEGER,
  row_scope                TEXT,
  value                    TEXT
) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
  SELECT
    g.country,
    k.source_kpi_id          AS kpi_id,
    f.disaggregation_level_one,
    f.disaggregation_level_two,
    dd.year,
    dd.quarter               AS year_quarter,
    f.row_scope,
    f.value
  FROM rep_warehouse.fact_observed_kpi   f
  JOIN rep_warehouse.dim_kpi             k  ON k.id  = f.kpi_id
  JOIN rep_warehouse.dim_geography       g  ON g.id  = f.geography_id
  JOIN rep_warehouse.dim_date            dd ON dd.id = f.year_date_id
  WHERE k.source_kpi_id = p_kpi_id
    AND dd.year   IS NOT NULL
    AND g.country IS NOT NULL;
$$;

GRANT EXECUTE ON FUNCTION rep_portal.get_observed_kpi(TEXT) TO authenticated;


-- ===== 20260528000004_fix_view_observed_kpi_remove_security_invoker.sql =====
-- Migration 031 added security_invoker=on to all rep_warehouse views with the
-- assumption that SECURITY DEFINER functions run as postgres (current_user inside
-- the function), so the view would still bypass RLS.  That assumption only holds
-- when the function owner IS postgres/superuser.  When the function is owned by
-- any other role (e.g. authenticated), security_invoker causes the view to run as
-- that non-superuser role, which has no permissive RLS policies on the base tables,
-- so the view silently returns 0 rows.
--
-- Fix: recreate view_observed_kpi without security_invoker so it always runs as
-- its owner (postgres), which has BYPASSRLS.  The GRANT SELECT on the view to
-- authenticated remains in place for direct access.
--
-- Also update rep_portal.get_observed_kpi to go through the view (not base tables)
-- now that the view works correctly, and extend the return type with row_scope and
-- year_quarter so the frontend can filter to ANNUAL-only rows.

-- 1. Recreate view without security_invoker
CREATE OR REPLACE VIEW rep_warehouse.view_observed_kpi AS
SELECT
    f.id,
    k.source_kpi_id                 AS kpi_id,
    k.kpi_group,
    k.indicator,
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
    g.country
FROM rep_warehouse.fact_observed_kpi f
LEFT JOIN rep_warehouse.dim_kpi      k  ON  k.id = f.kpi_id
LEFT JOIN rep_warehouse.dim_geography g  ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = f.year_date_id;

GRANT SELECT ON rep_warehouse.view_observed_kpi TO authenticated;

-- 2. Update rep_portal.get_observed_kpi to use the view and return row_scope + year_quarter
DROP FUNCTION IF EXISTS rep_portal.get_observed_kpi(TEXT);
CREATE FUNCTION rep_portal.get_observed_kpi(p_kpi_id TEXT)
RETURNS TABLE (
  country                  TEXT,
  kpi_id                   TEXT,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  year                     INTEGER,
  year_quarter             INTEGER,
  row_scope                TEXT,
  value                    TEXT
) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
  SELECT
    v.country,
    v.kpi_id,
    v.disaggregation_level_one,
    v.disaggregation_level_two,
    v.year,
    v.year_quarter,
    v.row_scope,
    v.value
  FROM rep_warehouse.view_observed_kpi v
  WHERE v.kpi_id = p_kpi_id
    AND v.year IS NOT NULL
    AND v.country IS NOT NULL;
$$;

GRANT EXECUTE ON FUNCTION rep_portal.get_observed_kpi(TEXT) TO authenticated;


-- ===== 20260530140933_list_portal_users.sql =====
CREATE OR REPLACE FUNCTION rep_portal.list_portal_users(
  p_caller_id  uuid,
  p_page       int  DEFAULT 1,
  p_page_size  int  DEFAULT 10,
  p_search     text DEFAULT '',
  p_admin_role text DEFAULT '',
  p_role_id    int  DEFAULT NULL,
  p_country    text DEFAULT '',
  p_status     text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_portal, auth, public
AS $$
DECLARE
  v_is_country_admin boolean;
  v_caller_countries text[];
  v_result           jsonb;
BEGIN
  SELECT (raw_app_meta_data->>'role') = 'country_admin'
  INTO   v_is_country_admin
  FROM   auth.users WHERE id = p_caller_id;

  IF v_is_country_admin THEN
    SELECT array_agg(country) INTO v_caller_countries
    FROM   rep_portal.user_countries WHERE user_id = p_caller_id;
  END IF;

  WITH filtered AS (
    SELECT
      u.id,
      u.email,
      u.raw_app_meta_data->>'role'                    AS admin_role,
      u.created_at,
      u.last_sign_in_at,
      u.confirmed_at,
      u.invited_at,
      u.banned_until,
      CASE
        WHEN u.banned_until IS NOT NULL AND u.banned_until > now() THEN 'banned'
        WHEN u.last_sign_in_at IS NOT NULL                          THEN 'active'
        WHEN u.invited_at IS NOT NULL AND u.confirmed_at IS NULL    THEN 'invited'
        WHEN u.confirmed_at IS NOT NULL                             THEN 'confirmed'
        ELSE 'invited'
      END                                        AS status,
      COALESCE(
        (SELECT jsonb_agg(jsonb_build_object('id', r.id, 'name', r.name))
         FROM   rep_portal.user_roles ur JOIN rep_portal.roles r ON r.id = ur.role_id
         WHERE  ur.user_id = u.id), '[]'::jsonb) AS roles,
      COALESCE(
        (SELECT array_agg(uc.country)
         FROM   rep_portal.user_countries uc WHERE uc.user_id = u.id),
        '{}'::text[])                            AS countries
    FROM auth.users u
    WHERE
      -- country-admin scoping
      (NOT COALESCE(v_is_country_admin, false)
        OR u.id = p_caller_id
        OR EXISTS (SELECT 1 FROM rep_portal.user_countries uc
                   WHERE uc.user_id = u.id AND uc.country = ANY(v_caller_countries)))
      -- email search
      AND (p_search     = '' OR u.email ILIKE '%' || p_search || '%')
      -- admin role filter
      AND (p_admin_role = ''
           OR (p_admin_role = 'user'
               AND (u.raw_app_meta_data->>'role' IS NULL OR u.raw_app_meta_data->>'role' = ''))
           OR (p_admin_role <> 'user'
               AND u.raw_app_meta_data->>'role' = p_admin_role))
      -- RBAC role filter
      AND (p_role_id IS NULL
           OR EXISTS (SELECT 1 FROM rep_portal.user_roles ur
                      WHERE ur.user_id = u.id AND ur.role_id = p_role_id))
      -- country filter
      AND (p_country = ''
           OR EXISTS (SELECT 1 FROM rep_portal.user_countries uc
                      WHERE uc.user_id = u.id AND uc.country = p_country))
  ),
  -- status filter + window count in same CTE so LIMIT/OFFSET below doesn't shrink the count
  counted AS (
    SELECT *, COUNT(*) OVER() AS total_count
    FROM   filtered
    WHERE  p_status = '' OR status = p_status
    ORDER  BY email
  ),
  paginated AS (
    SELECT * FROM counted
    LIMIT  p_page_size OFFSET (p_page - 1) * p_page_size
  )
  SELECT jsonb_build_object(
    'users', COALESCE(jsonb_agg(
      jsonb_build_object(
        'id',              id,
        'email',           COALESCE(email, ''),
        'role',            COALESCE(admin_role, ''),
        'created_at',      created_at,
        'last_sign_in_at', last_sign_in_at,
        'confirmed_at',    confirmed_at,
        'invited_at',      invited_at,
        'banned_until',    banned_until,
        'roles',           roles,
        'countries',       to_jsonb(countries)
      )), '[]'::jsonb),
    'total',    COALESCE(MAX(total_count)::int, 0),
    'page',     p_page,
    'pageSize', p_page_size
  )
  INTO v_result
  FROM paginated;

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.list_portal_users(uuid,int,int,text,text,int,text,text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.list_portal_users(uuid,int,int,text,text,int,text,text) TO service_role;


-- ===== 20260530141632_fix_list_portal_users_app_meta.sql =====
CREATE OR REPLACE FUNCTION rep_portal.list_portal_users(
  p_caller_id  uuid,
  p_page       int  DEFAULT 1,
  p_page_size  int  DEFAULT 10,
  p_search     text DEFAULT '',
  p_admin_role text DEFAULT '',
  p_role_id    int  DEFAULT NULL,
  p_country    text DEFAULT '',
  p_status     text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_portal, auth, public
AS $$
DECLARE
  v_is_country_admin boolean;
  v_caller_countries text[];
  v_result           jsonb;
BEGIN
  SELECT (raw_app_meta_data->>'role') = 'country_admin'
  INTO   v_is_country_admin
  FROM   auth.users WHERE id = p_caller_id;

  IF v_is_country_admin THEN
    SELECT array_agg(country) INTO v_caller_countries
    FROM   rep_portal.user_countries WHERE user_id = p_caller_id;
  END IF;

  WITH filtered AS (
    SELECT
      u.id,
      u.email,
      u.raw_app_meta_data->>'role'                    AS admin_role,
      u.created_at,
      u.last_sign_in_at,
      u.confirmed_at,
      u.invited_at,
      u.banned_until,
      CASE
        WHEN u.banned_until IS NOT NULL AND u.banned_until > now() THEN 'banned'
        WHEN u.last_sign_in_at IS NOT NULL                          THEN 'active'
        WHEN u.invited_at IS NOT NULL AND u.confirmed_at IS NULL    THEN 'invited'
        WHEN u.confirmed_at IS NOT NULL                             THEN 'confirmed'
        ELSE 'invited'
      END                                        AS status,
      COALESCE(
        (SELECT jsonb_agg(jsonb_build_object('id', r.id, 'name', r.name))
         FROM   rep_portal.user_roles ur JOIN rep_portal.roles r ON r.id = ur.role_id
         WHERE  ur.user_id = u.id), '[]'::jsonb) AS roles,
      COALESCE(
        (SELECT array_agg(uc.country)
         FROM   rep_portal.user_countries uc WHERE uc.user_id = u.id),
        '{}'::text[])                            AS countries
    FROM auth.users u
    WHERE
      -- country-admin scoping
      (NOT COALESCE(v_is_country_admin, false)
        OR u.id = p_caller_id
        OR EXISTS (SELECT 1 FROM rep_portal.user_countries uc
                   WHERE uc.user_id = u.id AND uc.country = ANY(v_caller_countries)))
      -- email search
      AND (p_search     = '' OR u.email ILIKE '%' || p_search || '%')
      -- admin role filter
      AND (p_admin_role = ''
           OR (p_admin_role = 'user'
               AND (u.raw_app_meta_data->>'role' IS NULL OR u.raw_app_meta_data->>'role' = ''))
           OR (p_admin_role <> 'user'
               AND u.raw_app_meta_data->>'role' = p_admin_role))
      -- RBAC role filter
      AND (p_role_id IS NULL
           OR EXISTS (SELECT 1 FROM rep_portal.user_roles ur
                      WHERE ur.user_id = u.id AND ur.role_id = p_role_id))
      -- country filter
      AND (p_country = ''
           OR EXISTS (SELECT 1 FROM rep_portal.user_countries uc
                      WHERE uc.user_id = u.id AND uc.country = p_country))
  ),
  counted AS (
    SELECT *, COUNT(*) OVER() AS total_count
    FROM   filtered
    WHERE  p_status = '' OR status = p_status
    ORDER  BY email
  ),
  paginated AS (
    SELECT * FROM counted
    LIMIT  p_page_size OFFSET (p_page - 1) * p_page_size
  )
  SELECT jsonb_build_object(
    'users', COALESCE(jsonb_agg(
      jsonb_build_object(
        'id',              id,
        'email',           COALESCE(email, ''),
        'role',            COALESCE(admin_role, ''),
        'created_at',      created_at,
        'last_sign_in_at', last_sign_in_at,
        'confirmed_at',    confirmed_at,
        'invited_at',      invited_at,
        'banned_until',    banned_until,
        'roles',           roles,
        'countries',       to_jsonb(countries)
      )), '[]'::jsonb),
    'total',    COALESCE(MAX(total_count)::int, 0),
    'page',     p_page,
    'pageSize', p_page_size
  )
  INTO v_result
  FROM paginated;

  RETURN v_result;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.list_portal_users(uuid,int,int,text,text,int,text,text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.list_portal_users(uuid,int,int,text,text,int,text,text) TO service_role;


-- ===== 20260530145613_list_whatsapp_users.sql =====
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

  -- For country admins, compute the set of district IDs they can see.
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
    WHERE
      -- country-admin scoping
      (
        v_caller_role <> 'country_admin'
        OR (
          -- user has no districts -> always visible to country admin
          NOT EXISTS (SELECT 1 FROM rep_portal.whatsapp_district_access a WHERE a.requester_id  = wu.id)
          AND NOT EXISTS (SELECT 1 FROM rep_portal.whatsapp_approver_districts d WHERE d.whatsapp_user_id = wu.id)
        )
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
      -- text search
      AND (
        p_search = ''
        OR wu.portal_id ILIKE '%' || p_search || '%'
        OR wu.name      ILIKE '%' || p_search || '%'
        OR wu.email     ILIKE '%' || p_search || '%'
        OR wu.phone     ILIKE '%' || p_search || '%'
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


-- ===== 20260530151321_add_district_search_to_list_whatsapp_users.sql =====
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
    WHERE
      -- country-admin scoping
      (
        v_caller_role <> 'country_admin'
        OR (
          NOT EXISTS (SELECT 1 FROM rep_portal.whatsapp_district_access a WHERE a.requester_id  = wu.id)
          AND NOT EXISTS (SELECT 1 FROM rep_portal.whatsapp_approver_districts d WHERE d.whatsapp_user_id = wu.id)
        )
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


-- ===== 20260530155800_list_district_access.sql =====
CREATE OR REPLACE FUNCTION rep_portal.list_district_access(
  p_caller_id   uuid,
  p_page        int  DEFAULT 1,
  p_page_size   int  DEFAULT 25,
  p_search      text DEFAULT '',
  p_status      text DEFAULT '',
  p_district_id text DEFAULT ''
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_portal, auth, rep_warehouse, public
AS $$
DECLARE
  v_caller_role      text;
  v_caller_districts text[];
  v_result           jsonb;
BEGIN
  SELECT raw_app_meta_data->>'role'
  INTO   v_caller_role
  FROM   auth.users
  WHERE  id = p_caller_id;

  IF v_caller_role = 'country_admin' THEN
    SELECT array_agg(DISTINCT gbd.district)
    INTO   v_caller_districts
    FROM   rep_portal.get_bot_districts() gbd
    JOIN   rep_portal.user_countries uc ON uc.country = gbd.country
    WHERE  uc.user_id = p_caller_id;
  END IF;

  WITH filtered AS (
    SELECT
      da.id,
      da.district_id,
      da.district_name,
      da.status,
      da.decided_at,
      da.rejection_reason,
      da.created_at,
      jsonb_build_object(
        'id',        req.id,
        'portal_id', req.portal_id,
        'name',      req.name,
        'phone',     req.phone
      ) AS requester,
      CASE WHEN apr.id IS NOT NULL
        THEN jsonb_build_object('id', apr.id, 'portal_id', apr.portal_id, 'name', apr.name)
        ELSE NULL
      END AS approver
    FROM rep_portal.whatsapp_district_access da
    LEFT JOIN rep_portal.whatsapp_users req ON req.id = da.requester_id
    LEFT JOIN rep_portal.whatsapp_users apr ON apr.id = da.approver_id
    WHERE
      (v_caller_role <> 'country_admin' OR da.district_id = ANY(v_caller_districts))
      AND (p_status = '' OR da.status = p_status)
      AND (p_district_id = '' OR da.district_id = p_district_id)
      AND (
        p_search = ''
        OR req.portal_id ILIKE '%' || p_search || '%'
        OR req.name      ILIKE '%' || p_search || '%'
        OR req.phone     ILIKE '%' || p_search || '%'
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
    'records', COALESCE(jsonb_agg(
      jsonb_build_object(
        'id',               id,
        'district_id',      district_id,
        'district_name',    district_name,
        'status',           status,
        'decided_at',       decided_at,
        'rejection_reason', rejection_reason,
        'created_at',       created_at,
        'requester',        requester,
        'approver',         approver
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

REVOKE EXECUTE ON FUNCTION rep_portal.list_district_access(uuid, int, int, text, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.list_district_access(uuid, int, int, text, text, text) TO service_role;


-- ===== 20260530204144_grant_service_role_user_countries.sql =====
-- Grant service_role INSERT on user_countries so the admin-users edge function
-- can assign countries at invite time (direct insert via service role client).
-- SELECT already works; INSERT was missing.
GRANT INSERT ON rep_portal.user_countries TO service_role;


-- ===== 20260530204559_grant_service_role_user_countries_seq.sql =====
-- BIGSERIAL INSERT requires USAGE + SELECT on the underlying sequence.
GRANT USAGE, SELECT ON SEQUENCE rep_portal.user_countries_id_seq TO service_role;


-- ===== 20260531112055_remove_no_country_ca_loophole.sql =====
-- Remove country-admin loopholes that allowed operating on users/WA-users
-- who have no country/district associations.
-- Now that invitations require a country, no new users arrive without one,
-- so these carve-outs are no longer needed.

-- 1. set_user_countries: drop the "allow initial assignment for no-country users" exception.
--    Country admins must always share at least one country with the target user.
CREATE OR REPLACE FUNCTION rep_portal.set_user_countries(p_user_id UUID, p_countries TEXT[])
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_caller_role      TEXT;
  v_is_admin         BOOLEAN;
  v_is_ca            BOOLEAN;
  v_caller_id        UUID;
  v_caller_countries TEXT[];
  v_invalid_count    INT;
  v_in_scope         BOOLEAN;
BEGIN
  v_caller_role := auth.jwt() -> 'app_metadata' ->> 'role';
  v_is_admin    := v_caller_role = 'admin';
  v_is_ca       := v_caller_role = 'country_admin';
  v_caller_id   := auth.uid();

  IF NOT v_is_admin AND NOT v_is_ca THEN
    RAISE EXCEPTION 'Admin access required';
  END IF;

  IF v_is_ca THEN
    SELECT COALESCE(array_agg(uc.country), ARRAY[]::TEXT[])
    INTO   v_caller_countries
    FROM   rep_portal.user_countries uc
    WHERE  uc.user_id = v_caller_id;

    SELECT COUNT(*) INTO v_invalid_count
    FROM   unnest(p_countries) AS c
    WHERE  c <> ALL(v_caller_countries);

    IF v_invalid_count > 0 THEN
      RAISE EXCEPTION 'Country admin can only assign countries within their own scope';
    END IF;

    -- Target user must share at least one country with the caller (no exceptions)
    SELECT EXISTS (
      SELECT 1 FROM rep_portal.user_countries
      WHERE  user_id = p_user_id
        AND  country = ANY(v_caller_countries)
    ) INTO v_in_scope;

    IF NOT v_in_scope THEN
      RAISE EXCEPTION 'Target user is outside your country scope';
    END IF;
  END IF;

  DELETE FROM rep_portal.user_countries WHERE user_id = p_user_id;

  IF array_length(p_countries, 1) > 0 THEN
    INSERT INTO rep_portal.user_countries (user_id, country, assigned_by)
    SELECT p_user_id, unnest(p_countries), v_caller_id;
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.set_user_countries(UUID, TEXT[]) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.set_user_countries(UUID, TEXT[]) TO authenticated;

-- 2. list_whatsapp_users: remove the branch that made no-district WA users always
--    visible to country admins. Country admins now only see WA users who have at
--    least one district in their scope.
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


-- ===== 20260601000001_cap_guide_years_at_current_year.sql =====
-- Cap the guide time-series year range at the current calendar year.
-- Previously generate_series(2020, 2030) caused active guides (left_year IS NULL)
-- to appear in every future year through 2030. Now the upper bound is
-- EXTRACT(YEAR FROM CURRENT_DATE) so no future-year rows are ever produced.
-- The view will automatically include the new year each time it is refreshed
-- after 1 January without any further migration.

DROP MATERIALIZED VIEW IF EXISTS rep_portal.dashboard_data_agg;

CREATE MATERIALIZED VIEW rep_portal.dashboard_data_agg AS

WITH valid_countries AS (
  SELECT DISTINCT country
  FROM rep_warehouse.view_observed_kpi
  WHERE country IS NOT NULL
),
years AS (
  SELECT generate_series(2020, EXTRACT(YEAR FROM CURRENT_DATE)::int) AS yr
)

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Newly supported'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Annual'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Annual'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Cumulative 2020-2030'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Cumulative (2020-2030)'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Cumulative 2024-2030'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Cumulative (2024-2030)'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

SELECT country, 'National' AS district, 'National' AS school, year,
       'Children Supported in School with Education Bursaries — Cumulative all-time'::text AS metric,
       SUM(value::numeric)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE disaggregation_level_two = 'Girls Total'
  AND disaggregation_level_one = 'Cumulative (all-time)'
  AND indicator ILIKE '%girls receiving CAMF%'
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- Active Learner Guides — time series using joined_year / left_year
SELECT v.country, v.district, v.school_name AS school, y.yr AS year,
       'Active Learner Guides'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
CROSS JOIN years y
WHERE v.guide_type = 'Learner Guide'
  AND v.school_name IS NOT NULL
  AND v.joined_year IS NOT NULL
  AND v.joined_year <= y.yr
  AND (v.left_year IS NULL OR v.left_year >= y.yr)
GROUP BY v.country, v.district, v.school_name, y.yr

UNION ALL

SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form — Girls'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.gender = 'Female'
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

SELECT v.country, v.district, v.school_name AS school, v.year,
       'Number of Clients by Form — Boys'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL AND v.gender = 'Male'
GROUP BY v.country, v.district, v.school_name, v.year

UNION ALL

-- Per-form-level breakdowns
SELECT v.country, v.district, v.school_name AS school, v.year,
       CASE
         WHEN v.form IN ('Stnd 5','Stnd 6','Stnd 7','Stnd 8',
                         'Grade 1','Grade 2','Grade 3','Grade 4','Grade 5','Grade 6','Grade 7')
           THEN 'Clients by Form — Primary'
         WHEN v.form IN ('Form 1','Form 2','Form 3','JH1','JH2','JH3','Grade 8','Grade 9')
           THEN 'Clients by Form — Junior Secondary'
         WHEN v.form IN ('Form 4','Form 5','Form 6','SH1','SH2','SH3','Grade 10','Grade 11','Grade 12')
           THEN 'Clients by Form — Senior Secondary'
         WHEN v.form ILIKE 'Tertiary%'
           THEN 'Clients by Form — Tertiary'
         ELSE 'Clients by Form — Other'
       END AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.school_name IS NOT NULL AND v.year IS NOT NULL
GROUP BY v.country, v.district, v.school_name, v.year,
         CASE
           WHEN v.form IN ('Stnd 5','Stnd 6','Stnd 7','Stnd 8',
                           'Grade 1','Grade 2','Grade 3','Grade 4','Grade 5','Grade 6','Grade 7')
             THEN 'Clients by Form — Primary'
           WHEN v.form IN ('Form 1','Form 2','Form 3','JH1','JH2','JH3','Grade 8','Grade 9')
             THEN 'Clients by Form — Junior Secondary'
           WHEN v.form IN ('Form 4','Form 5','Form 6','SH1','SH2','SH3','Grade 10','Grade 11','Grade 12')
             THEN 'Clients by Form — Senior Secondary'
           WHEN v.form ILIKE 'Tertiary%'
             THEN 'Clients by Form — Tertiary'
           ELSE 'Clients by Form — Other'
         END

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Active Partner Schools'::text AS metric,
       COUNT(DISTINCT v.school_name)::int AS value
FROM rep_warehouse.view_children_supported v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Number of Women Supported by CAMFED in Tertiary Education'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_post_school_support v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

-- Active Guides by Type — time series
SELECT v.country, v.district, v.school_name AS school, y.yr AS year,
       'Active Guides by Type'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
CROSS JOIN years y
WHERE v.school_name IS NOT NULL
  AND v.joined_year IS NOT NULL
  AND v.joined_year <= y.yr
  AND (v.left_year IS NULL OR v.left_year >= y.yr)
GROUP BY v.country, v.district, v.school_name, y.yr

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.year,
       'Number of Post School Clients'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_post_school_support v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.year IS NOT NULL
GROUP BY v.country, v.district, v.year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.grant_year AS year,
       'Grants Disbursed'::text AS metric,
       ROUND(SUM(v.amount_given::numeric))::int AS value
FROM rep_warehouse.view_grants v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.grant_year IS NOT NULL
GROUP BY v.country, v.district, v.grant_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed'::text AS metric,
       ROUND(SUM(COALESCE(v.loan_value, 0)))::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

-- CAMA Members — Newly supported
SELECT country, 'National' AS district, 'National' AS school, year,
       'CAMA Members'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school by CAMA'
  AND disaggregation_level_one = 'Newly supported'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- CAMA Members — Annual
SELECT country, 'National' AS district, 'National' AS school, year,
       'CAMA Members — Annual'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school by CAMA'
  AND disaggregation_level_one = 'Annual'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- Community Champions — Newly supported
SELECT country, 'National' AS district, 'National' AS school, year,
       'Community Champions'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school through community initiatives'
  AND disaggregation_level_one = 'Newly supported'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- Community Champions — Annual
SELECT country, 'National' AS district, 'National' AS school, year,
       'Community Champions — Annual'::text AS metric,
       SUM(CASE WHEN value ~ '^[0-9]+(\.[0-9]+)?$' THEN value::numeric ELSE 0 END)::int AS value
FROM rep_warehouse.view_observed_kpi
WHERE indicator = 'Number of children supported to go to school through community initiatives'
  AND disaggregation_level_one = 'Annual'
  AND disaggregation_level_two = 'Girls Total'
  AND year_quarter = 1
  AND year IS NOT NULL AND country IS NOT NULL
GROUP BY country, year

UNION ALL

-- Active Guides — Transition: time series
SELECT v.country, v.district, v.school_name AS school, y.yr AS year,
       'Active Guides — Transition'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
CROSS JOIN years y
WHERE v.school_name IS NOT NULL
  AND v.guide_type ILIKE '%Transition%'
  AND v.joined_year IS NOT NULL
  AND v.joined_year <= y.yr
  AND (v.left_year IS NULL OR v.left_year >= y.yr)
GROUP BY v.country, v.district, v.school_name, y.yr

UNION ALL

-- Active Guides — Agriculture: time series
SELECT v.country, v.district, v.school_name AS school, y.yr AS year,
       'Active Guides — Agriculture'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
CROSS JOIN years y
WHERE v.school_name IS NOT NULL
  AND v.guide_type ILIKE '%Agri%'
  AND v.joined_year IS NOT NULL
  AND v.joined_year <= y.yr
  AND (v.left_year IS NULL OR v.left_year >= y.yr)
GROUP BY v.country, v.district, v.school_name, y.yr

UNION ALL

-- Active Guides — Business: time series
SELECT v.country, v.district, v.school_name AS school, y.yr AS year,
       'Active Guides — Business'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_guide_assignment v
JOIN valid_countries vc ON vc.country = v.country
CROSS JOIN years y
WHERE v.school_name IS NOT NULL
  AND (v.guide_type ILIKE '%Business%' OR v.guide_type ILIKE '%Enterprise%')
  AND v.joined_year IS NOT NULL
  AND v.joined_year <= y.yr
  AND (v.left_year IS NULL OR v.left_year >= y.yr)
GROUP BY v.country, v.district, v.school_name, y.yr

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.grant_year AS year,
       'Grants Distributed — Count'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_grants v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.grant_year IS NOT NULL
GROUP BY v.country, v.district, v.grant_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Agriculture'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%Agri%'
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Business'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL
  AND (v.loan_type ILIKE '%Business%' OR v.loan_type ILIKE '%Enterprise%')
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — Kiva'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%Kiva%'
GROUP BY v.country, v.district, v.disbursal_year

UNION ALL

SELECT v.country, v.district, 'District Total' AS school, v.disbursal_year AS year,
       'Loans Disbursed — RIF'::text AS metric,
       COUNT(*)::int AS value
FROM rep_warehouse.view_loans v
JOIN valid_countries vc ON vc.country = v.country
WHERE v.disbursal_year IS NOT NULL AND v.loan_type ILIKE '%RIF%'
GROUP BY v.country, v.district, v.disbursal_year

WITH NO DATA;

REFRESH MATERIALIZED VIEW rep_portal.dashboard_data_agg;


-- ===== 20260601000002_lazy_dashboard_fetch.sql =====
-- Lazy Dashboard Fetch refactor
--
-- Problem: get_dashboard_data_scoped() returns every row in dashboard_data_agg
-- with no filters, producing a massive JSON payload (school × metric × year for
-- all countries). Users with low bandwidth had to download everything before any
-- chart rendered.
--
-- Solution:
--   1. get_dashboard_metadata() — fast structural query; returns countries, years,
--      and the district/school geographic hierarchy. No metric values, tiny payload.
--      Called once on page mount to populate dropdowns.
--
--   2. get_dashboard_data_filtered(...) — parameterized; called only when the user
--      clicks Run. Accepts country list, year range, and metric list so only the
--      rows actually needed for the current query are transferred.
--
-- Fix: also adds missing permission_metric_map entries for ClientsByFormChart
-- sub-metrics ('Clients by Form — *') and for Active Learner Guides under
-- dd:guides_by_type (GroupedStackedChart uses it).

-- ── 1. get_dashboard_metadata ─────────────────────────────────────────────────

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
    'geography', (
      SELECT COALESCE(json_agg(row_to_json(r)), '[]'::json)
      FROM (
        SELECT DISTINCT country, district, school
        FROM   rep_portal.dashboard_data_agg
        WHERE  district IS NOT NULL AND district <> 'National'
          AND  school   IS NOT NULL AND school   <> 'District Total'
        ORDER BY country, district, school
      ) r
    )
  );
$$;

GRANT EXECUTE ON FUNCTION rep_portal.get_dashboard_metadata() TO authenticated;

-- ── 2. get_dashboard_data_filtered ───────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.get_dashboard_data_filtered(
  p_countries  text[],
  p_year_start int,
  p_year_end   int,
  p_metrics    text[]
)
RETURNS json LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = rep_portal, public
AS $$
  SELECT json_build_object('data', COALESCE(json_agg(r), '[]'::json))
  FROM (
    SELECT d.*
    FROM rep_portal.dashboard_data_agg d
    WHERE
      -- Year range filter
      d.year BETWEEN p_year_start AND p_year_end
      -- Country filter: NULL / empty array = all countries
      AND (
        p_countries IS NULL
        OR array_length(p_countries, 1) IS NULL
        OR d.country = ANY(p_countries)
      )
      -- Metric filter: NULL / empty array = all metrics
      AND (
        p_metrics IS NULL
        OR array_length(p_metrics, 1) IS NULL
        OR d.metric = ANY(p_metrics)
      )
      -- Permission check (same as get_dashboard_data_scoped)
      AND (
        (auth.jwt()->'app_metadata'->>'role') = 'admin'
        OR EXISTS (
          SELECT 1
          FROM   rep_portal.permission_metric_map pmm
          JOIN   rep_portal.permissions       p  ON p.key          = pmm.permission_key
          JOIN   rep_portal.role_permissions  rp ON rp.permission_id = p.id
          JOIN   rep_portal.user_roles        ur ON ur.role_id       = rp.role_id
          WHERE  ur.user_id      = auth.uid()
            AND  pmm.metric_id   = d.metric
        )
      )
  ) r;
$$;

GRANT EXECUTE ON FUNCTION rep_portal.get_dashboard_data_filtered(text[], int, int, text[]) TO authenticated;
REVOKE EXECUTE ON FUNCTION rep_portal.get_dashboard_data_filtered(text[], int, int, text[]) FROM anon;

-- ── 3. Fix missing permission_metric_map entries ──────────────────────────────
-- ClientsByFormChart reads 'Clients by Form — *' sub-metrics but these were not
-- in permission_metric_map, so non-admin users got no data in that chart.
-- GroupedStackedChart reads 'Active Learner Guides' via dd:guides_by_type.

INSERT INTO rep_portal.permission_metric_map (permission_key, metric_id) VALUES
  ('dd:clients_by_form', 'Clients by Form — Primary'),
  ('dd:clients_by_form', 'Clients by Form — Junior Secondary'),
  ('dd:clients_by_form', 'Clients by Form — Senior Secondary'),
  ('dd:clients_by_form', 'Clients by Form — Tertiary'),
  ('dd:clients_by_form', 'Clients by Form — Other'),
  ('dd:guides_by_type',  'Active Learner Guides')
ON CONFLICT DO NOTHING;


-- ===== 20260601000003_kpi_coverage_rpc.sql =====
-- KPI Coverage RPC
-- Returns exactly one representative row per (kpi_id, country, year) combination,
-- preferring SUBTOTAL scope, then ANNUAL, then any other scope.
-- This avoids the PostgREST max_rows server cap that was limiting results to 1 year.

CREATE OR REPLACE FUNCTION rep_portal.get_kpi_coverage_data()
RETURNS json
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, public
AS $$
  SELECT COALESCE(json_agg(row_to_json(r)), '[]'::json)
  FROM (
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
      END
  ) r;
$$;

GRANT EXECUTE ON FUNCTION rep_portal.get_kpi_coverage_data() TO authenticated, anon, service_role;


-- ===== 20260601000004_kpi_coverage_matview.sql =====
-- KPI Coverage materialized view
-- Replaces the get_kpi_coverage_data() RPC with a pre-computed snapshot.
-- DISTINCT ON reduces ~500k rows (one per row_scope) down to one row per
-- (kpi_id, country, year), well within PostgREST's max_rows limit.
-- Refresh with: REFRESH MATERIALIZED VIEW rep_portal.kpi_coverage_data;

-- Drop the RPC introduced in the previous migration
DROP FUNCTION IF EXISTS rep_portal.get_kpi_coverage_data();

-- Create the materialized view
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

-- Indexes for fast filtering by the frontend
CREATE INDEX ON rep_portal.kpi_coverage_data (kpi_id);
CREATE INDEX ON rep_portal.kpi_coverage_data (country);
CREATE INDEX ON rep_portal.kpi_coverage_data (year);

-- Grant read access
GRANT SELECT ON rep_portal.kpi_coverage_data TO authenticated, anon, service_role;


-- ===== 20260601000005_data_dictionary.sql =====
-- Data Dictionary table
-- Holds a human-readable definition for each KPI.
-- Format shown in the portal: KPI Name — KPI Number: Definition

CREATE TABLE rep_portal.data_dictionary (
  id          SERIAL PRIMARY KEY,
  kpi_id      TEXT        NOT NULL UNIQUE,
  kpi_name    TEXT        NOT NULL,
  kpi_number  TEXT,
  kpi_group   TEXT,
  definition  TEXT,
  created_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Placeholder entries — replace / extend via KPI Upload or direct SQL
INSERT INTO rep_portal.data_dictionary (kpi_id, kpi_name, kpi_number, kpi_group, definition) VALUES
  ('education_bursaries_children',   'Girls Supported with Education Bursaries',           'KPI-001', 'Girls'' Education',       'Number of girls receiving direct financial support through CAMFED''s bursary programme to remain in school.'),
  ('active_learner_guides',          'Active Learner Guides',                               'KPI-002', 'Girls'' Education',       'Number of trained CAMA members currently active as Learner Guides supporting younger girls in school.'),
  ('active_partner_schools',         'Active Partner Schools',                              'KPI-003', 'Education Systems',       'Number of schools where CAMFED programme activities are actively taking place in the reporting year.'),
  ('clients_by_form',                'Learner Guide Clients (Total)',                       'KPI-004', 'Girls'' Education',       'Total number of students supported by Learner Guides, including both girls and boys.'),
  ('clients_by_form_girls',          'Learner Guide Clients — Girls',                      'KPI-005', 'Girls'' Education',       'Number of female students receiving support from trained Learner Guides.'),
  ('clients_by_form_boys',           'Learner Guide Clients — Boys',                       'KPI-006', 'Girls'' Education',       'Number of male students receiving support from trained Learner Guides.'),
  ('cama_members',                   'CAMA Members',                                        'KPI-007', 'Livelihoods & Leadership','Number of registered members of the CAMFED Association (CAMA) — young women who benefited from CAMFED support.'),
  ('women_supported_tertiary',       'Women Supported into Tertiary Education',             'KPI-008', 'Livelihoods & Leadership','Number of CAMA members supported to access university or technical/vocational tertiary education.'),
  ('grants_disbursed',               'Business Grants Disbursed',                           'KPI-009', 'Livelihoods & Leadership','Total value of grants provided to CAMA members to start or grow income-generating businesses.'),
  ('active_guides_transition',       'Learner Guides — Transition Support',                'KPI-010', 'Girls'' Education',       'Number of Learner Guides providing transition counselling to help students move to the next school level.'),
  ('active_guides_agriculture',      'Learner Guides — Agriculture',                       'KPI-011', 'Girls'' Education',       'Number of Learner Guides delivering agricultural livelihood skills sessions.'),
  ('active_guides_business',         'Learner Guides — Business',                          'KPI-012', 'Girls'' Education',       'Number of Learner Guides delivering business and entrepreneurship skills sessions.');

GRANT SELECT ON rep_portal.data_dictionary TO authenticated, anon, service_role;


-- ===== 20260602000001_data_dictionary_seed.sql =====
-- Replaces placeholder entries in rep_portal.data_dictionary
-- with entries keyed to the numeric IDs used in the dashboard chart registry.

TRUNCATE rep_portal.data_dictionary RESTART IDENTITY;

INSERT INTO rep_portal.data_dictionary (kpi_id, kpi_name, kpi_number, kpi_group, definition) VALUES

-- ── Girls' Education: Education Reach ──────────────────────────────────────────
('1.1',  'Girls Supported with Education Bursaries',
         '1.1',   'Girls'' Education',
         'Number of girls receiving direct financial support through CAMFED''s bursary programme to remain in school. Includes both newly supported and annual figures depending on the selected period.'),

('1.2a', 'Girls Supported in School by CAMA Members',
         '1.2a',  'Girls'' Education',
         'Number of girls receiving in-school support from trained CAMA members (CAMFED Association). CAMA members are alumni who give back as mentors and role models within their communities.'),

('1.2b', 'Girls Supported in School by Community Champions',
         '1.2b',  'Girls'' Education',
         'Number of girls supported by Community Champions — local volunteers who advocate for girls'' education and work to address barriers such as poverty, early marriage, and pregnancy.'),

('P1',   'Total Girls and Boys Supported',
         'P1',    'Girls'' Education',
         'Combined total of girls and boys benefiting from CAMFED programming, aggregated across bursary, CAMA, and Community Champion support channels in the selected period.'),

-- ── Girls' Education: Education Outcomes ──────────────────────────────────────
('1.5',  'Dropout Rate for Girls with Education Bursaries',
         '1.5',   'Girls'' Education',
         'Annual percentage of bursary-supported girls who left school before completing the year (Early Marriage Programme). Lower figures indicate stronger retention outcomes.'),

('1.7',  'Progression to Next Grade',
         '1.7',   'Girls'' Education',
         'Percentage of CAMFED-supported students who successfully progressed to the next grade across Forms 1 to 4. Averaged across the selected countries and years.'),

('1.4',  'Exam Pass Rates',
         '1.4',   'Girls'' Education',
         'Comparative pass rates for CAMFED-supported clients versus national benchmarks at Lower and Upper Secondary level. Expressed as percentages to show programme impact on academic achievement.'),

('1.8',  'School Completion Rate',
         '1.8',   'Girls'' Education',
         'Percentage of CAMFED-supported girls who completed Lower and Upper Secondary school within the selected period. A key indicator of the programme''s impact on long-term educational attainment.'),

-- ── Girls' Education: Learner Guide Programme ─────────────────────────────────
('1.9',  'Active Learner Guides',
         '1.9',   'Girls'' Education',
         'Number of trained CAMA members currently serving as Learner Guides, providing academic, social, and emotional support to younger students in CAMFED partner schools.'),

('1.3',  'Children Receiving Social and Learning Support (My Better World)',
         '1.3',   'Girls'' Education',
         'Total number of children (girls and boys) receiving My Better World or Social and Learning Support (SLS) sessions delivered by Learner Guides in CAMFED partner schools.'),

('R3',   'Learner Guides Reporting Increased Agency',
         'R3',    'Girls'' Education',
         'Percentage of active Learner Guides who report increased confidence, decision-making ability, and a sense of agency as a result of their participation in the Learner Guide Programme.'),

-- ── Livelihoods & Leadership: Leadership & Tertiary ───────────────────────────
('2.2',  'Active Transition / Enterprise Guides',
         '2.2',   'Livelihoods & Leadership',
         'Number of CAMA members actively working as Transition Guides (supporting younger women into employment or study) or Enterprise Guides (coaching businesses and agriculture clients).'),

('2.1',  'CAMA Members',
         '2.1',   'Livelihoods & Leadership',
         'Total number of registered members of the CAMFED Association (CAMA) — women who benefited from CAMFED''s support and have joined a lifelong network of mutual support, advocacy, and leadership.'),

('2.3',  'Young Women Supported by Transition Guides',
         '2.3',   'Livelihoods & Leadership',
         'Number of young women receiving structured support from CAMA Transition Guides to navigate the transition from education to employment, enterprise, or further study.'),

('2.5',  'Women in Tertiary Education',
         '2.5',   'Livelihoods & Leadership',
         'Number of CAMA members supported by CAMFED to access university or technical and vocational tertiary education, enabling continued advancement beyond secondary school.'),

('2.13', 'CAMA Members in Leadership Roles',
         '2.13',  'Livelihoods & Leadership',
         'Number of CAMA members holding formal leadership positions — in government, civil society, business, or CAMFED governance structures — reflecting the long-term impact of the programme.'),

-- ── Livelihoods & Leadership: Livelihoods Reach ──────────────────────────────
('2.7',  'Businesses Supported by Enterprise Guides',
         '2.7',   'Livelihoods & Leadership',
         'Number of micro and small businesses — run by Agriculture or Business Guide clients — that received structured coaching or support from a CAMA Enterprise Guide in the period.'),

('2.8a', 'Business Grants Distributed',
         '2.8a',  'Livelihoods & Leadership',
         'Number and total USD value of start-up and growth grants provided to CAMA members through CAMFED''s enterprise programme to establish or expand income-generating activities.'),

('2.8b', 'CAMFED Kiva and RIF Loans',
         '2.8b',  'Livelihoods & Leadership',
         'Number and total USD value of loans disbursed through CAMFED''s Kiva and Revolving Investment Fund (RIF) partnerships to support CAMA members in starting or growing their businesses.'),

-- ── Livelihoods & Leadership: Jobs & Income ───────────────────────────────────
('2.4',  'Women Progressing to a Secure Livelihood',
         '2.4',   'Livelihoods & Leadership',
         'Percentage of women completing CAMFED''s transitions programme who progressed to a secure livelihood — defined as sustained employment, enterprise ownership, or continued education.'),

('2.11', 'Female Entrepreneurs with Increased Income',
         '2.11',  'Livelihoods & Leadership',
         'Percentage of female entrepreneurs in CAMFED''s enterprise programme who report that their business is making a profit, indicating improved economic self-sufficiency after programme participation.'),

('2.9',  'Jobs Created through Enterprise Programme',
         '2.9',   'Livelihoods & Leadership',
         'Total number of jobs created — including self-employment — by CAMA members supported through CAMFED''s enterprise programme, measuring direct economic impact in participating communities.'),

('2.6',  'New Businesses',
         '2.6',   'Livelihoods & Leadership',
         'Number of new businesses started by CAMA members with support from CAMFED''s enterprise programme, covering both agriculture-based and non-farm enterprises.'),

-- ── Livelihoods & Leadership: Agriculture & Food ─────────────────────────────
('R4',   'Household Food Consumption Score',
         'R4',    'Livelihoods & Leadership',
         'Percentage of female entrepreneurs who report an increased household food consumption score since participating in CAMFED''s enterprise programme, indicating improved household food security.'),

('R8',   'Agripreneurs with Increased Yields',
         'R8',    'Livelihoods & Leadership',
         'Percentage of female agripreneurs who report increased agricultural yields following participation in CAMFED''s Agriculture Guide Programme and adoption of improved farming practices.'),

('R7',   'Average Climate-Smart Techniques Used',
         'R7',    'Livelihoods & Leadership',
         'Average number of climate-smart agricultural techniques adopted by those receiving support from a CAMFED Agriculture Guide, measuring uptake of sustainable and resilient farming methods.'),

-- ── Livelihoods & Leadership: Life Choices ────────────────────────────────────
('2.14', 'Young Women Married by Age 18',
         '2.14',  'Livelihoods & Leadership',
         'Percentage of young women in CAMFED programme areas who were married before their 18th birthday, tracked to measure the programme''s progress on ending child marriage as a barrier to education.'),

('2.15', 'Young Women Giving Birth by Age 18',
         '2.15',  'Livelihoods & Leadership',
         'Percentage of young women who gave birth before age 18, and CAMA marriage and birth rate indicators, tracked to measure the programme''s impact on reproductive health outcomes.'),

-- ── Education Systems ─────────────────────────────────────────────────────────
('3.3',  '% of Resources Contributed by Government',
         '3.3',   'Education Systems',
         'Percentage of total resources for the Learner Guide Programme contributed by government — including funding, materials, and staff time — as an indicator of national ownership and sustainability.'),

('3.4',  'Districts with Learner Guides',
         '3.4',   'Education Systems',
         'Number of districts where Learner Guides are active, broken down by CAMFED-supported districts and those operating under government-led delivery, indicating the geographic scale of the programme.'),

('3.6',  'National Dropout Rate for Girls',
         '3.6',   'Education Systems',
         'National-level dropout rate for girls attributed to early marriage or pregnancy, used to contextualise CAMFED''s direct programme results against the broader national picture.'),

('3.2',  'Schools with Learner Guides',
         '3.2',   'Education Systems',
         'Number of schools where at least one trained Learner Guide is active, split between CAMFED-supported schools and schools reached through government delivery partnerships.'),

('P18',  'Memoranda of Understanding',
         'P18',   'Education Systems',
         'Number of formal Memoranda of Understanding (MoUs) signed between government departments and CAMFED, reflecting the depth of institutional partnership and policy integration for the Learner Guide Programme.'),

('3.5',  'Children Benefitting from Improved Learning Environment',
         '3.5',   'Education Systems',
         'Number of primary and secondary school children (girls and boys) who benefit from an improved learning environment as a direct result of CAMFED''s education systems strengthening activities.'),

('P6',   'Active Community Champions',
         'P6',    'Education Systems',
         'Number of active Community Champions — including CDCs, SBCs, and PSGs — who advocate for girls'' education and support families to keep girls in school at the community level.');


-- ===== 20260602000002_data_dictionary_rls.sql =====
-- Enable RLS on data_dictionary and add a permissive read policy.
-- Without this, PostgREST returns 0 rows even though GRANT SELECT was set,
-- because Supabase denies by default when RLS is active with no policy.

ALTER TABLE rep_portal.data_dictionary ENABLE ROW LEVEL SECURITY;

CREATE POLICY data_dictionary_select
  ON rep_portal.data_dictionary
  FOR SELECT TO authenticated
  USING (true);


-- ===== 20260602132757_drop_default_role_trigger.sql =====
-- Remove automatic Full Access assignment on new user creation.
-- Role is now explicitly chosen in the invite form (portal users) or
-- during WhatsApp bot registration (WA users), so a blanket default is
-- no longer appropriate and would override the admin-selected role.

DROP TRIGGER IF EXISTS trg_assign_default_role ON auth.users;
DROP FUNCTION IF EXISTS rep_portal.assign_default_role();

