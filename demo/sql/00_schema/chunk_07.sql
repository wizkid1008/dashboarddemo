-- Schema chunk 7 - run only after the previous chunk succeeded.
-- Generated from supabase/migrations in filename order. Do not reorder.


-- ===== 20260818105244_add_caller_allowed_countries.sql =====
-- Shared helper for country-based RBAC, reusing rep_portal.user_countries
-- (previously only enforced in the admin console) across the main data RPCs.
--
-- NULL   = caller is unrestricted (full admin bypass, or a trusted
--          service-role caller such as the WhatsApp bot, which has no
--          auth.uid() and must not be default-denied)
-- '{}'   = caller has no countries assigned -> default-deny, sees nothing
-- {..}   = caller's explicit allow-list
CREATE OR REPLACE FUNCTION rep_portal.caller_allowed_countries()
RETURNS text[] LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT CASE
    WHEN (auth.jwt()->'app_metadata'->>'role') = 'admin' THEN NULL
    WHEN (auth.jwt()->>'role') = 'service_role' THEN NULL
    ELSE COALESCE(
      (SELECT array_agg(country) FROM rep_portal.user_countries WHERE user_id = auth.uid()),
      ARRAY[]::text[]
    )
  END
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.caller_allowed_countries() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.caller_allowed_countries() TO authenticated;


-- ===== 20260818105305_scope_dashboard_metadata_by_country.sql =====
-- Country-scope get_dashboard_metadata()'s countries + geography fields using
-- rep_portal.caller_allowed_countries(). NULL from the helper means
-- unrestricted (full admin); everyone else is filtered to their allow-list,
-- which is empty by default (default-deny) until an admin assigns countries.
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
          AND  (rep_portal.caller_allowed_countries() IS NULL
                OR country = ANY(rep_portal.caller_allowed_countries()))
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
      CASE WHEN (auth.jwt()->'app_metadata'->>'role') = 'admin' THEN
        (SELECT COALESCE(json_agg(metric_name ORDER BY sort_order, metric_name), '[]'::json)
         FROM   rep_portal.metric_config
         WHERE  enabled = true)
      ELSE
        (SELECT COALESCE(json_agg(DISTINCT mc.metric_name ORDER BY mc.metric_name), '[]'::json)
         FROM   rep_portal.metric_config               mc
         JOIN   rep_portal.permission_metric_config_map pmcm ON pmcm.metric_config_id = mc.id
         JOIN   rep_portal.permissions                  p    ON p.key                = pmcm.permission_key
         JOIN   rep_portal.role_permissions             rp   ON rp.permission_id     = p.id
         JOIN   rep_portal.user_roles                   ur   ON ur.role_id           = rp.role_id
         WHERE  ur.user_id  = auth.uid()
           AND  mc.enabled  = true)
      END
    ),

    'geography', (
      SELECT COALESCE(json_agg(row_to_json(r)), '[]'::json)
      FROM (
        SELECT DISTINCT
          g.country,
          g.province,
          g.district,
          s.school_name AS school,
          s.school_type
        FROM   rep_warehouse.dim_geography g
        LEFT   JOIN rep_warehouse.dim_school s
               ON  s.geography_id = g.id
               AND s.scd_is_current = true
               AND s.school_name IS NOT NULL
        WHERE  g.scd_is_current = true
          AND  g.country IS NOT NULL
          AND  g.district IS NOT NULL
          AND  g.country NOT IN ('International', 'United Kingdom', 'United States')
          AND  (rep_portal.caller_allowed_countries() IS NULL
                OR g.country = ANY(rep_portal.caller_allowed_countries()))
        ORDER BY g.country, g.province, g.district, s.school_name
      ) r
    )

  );
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.get_dashboard_metadata() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_dashboard_metadata() TO authenticated;


-- ===== 20260818105413_scope_dashboard_data_by_country.sql =====
-- Country-scope get_dashboard_data_scoped() (main Dashboard) and
-- get_dashboard_data_filtered() (Dynamic Data) using
-- rep_portal.caller_allowed_countries(). Logic otherwise unchanged from
-- 20260803120000_add_school_type_to_dynamic_data.sql.

CREATE OR REPLACE FUNCTION rep_portal.get_dashboard_data_scoped()
RETURNS json LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = rep_portal, public
AS $$
  SELECT json_build_object('data', COALESCE(json_agg(r), '[]'::json))
  FROM (
    SELECT d.*
    FROM rep_portal.dashboard_data_agg d
    WHERE
      (
        (auth.jwt()->'app_metadata'->>'role') = 'admin'
        OR EXISTS (
          SELECT 1
          FROM rep_portal.permissions p
          JOIN rep_portal.dashlets dl ON dl.permission_key = p.key
          JOIN rep_portal.role_permissions rp ON rp.permission_id = p.id
          JOIN rep_portal.user_roles ur ON ur.role_id = rp.role_id
          WHERE ur.user_id = auth.uid()
            AND (
              EXISTS (
                SELECT 1 FROM rep_portal.dashlet_kpi_config dkc
                WHERE dkc.dashlet_id = dl.id AND dkc.kpi_id = d.metric
              )
              OR EXISTS (
                SELECT 1 FROM rep_portal.dashlet_metric_configs dmc
                JOIN rep_portal.metric_config mc ON mc.id = dmc.metric_config_id
                WHERE dmc.dashlet_id = dl.id AND mc.metric_name = d.metric
              )
            )
        )
      )
      AND (rep_portal.caller_allowed_countries() IS NULL
           OR d.country = ANY(rep_portal.caller_allowed_countries()))
  ) r;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.get_dashboard_data_scoped() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_dashboard_data_scoped() TO authenticated;


CREATE OR REPLACE FUNCTION rep_portal.get_dashboard_data_filtered(
  p_countries    text[]  DEFAULT NULL,
  p_provinces    text[]  DEFAULT NULL,
  p_districts    text[]  DEFAULT NULL,
  p_schools      text[]  DEFAULT NULL,
  p_year_start   int     DEFAULT 2020,
  p_year_end     int     DEFAULT 2030,
  p_metrics      text[]  DEFAULT NULL,
  p_school_types text[]  DEFAULT NULL
)
RETURNS json
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
DECLARE
  v_is_admin        BOOLEAN;
  v_allowed_metrics TEXT[];
  v_allowed_countries TEXT[];
BEGIN
  v_is_admin := (auth.jwt()->'app_metadata'->>'role') = 'admin';
  v_allowed_countries := rep_portal.caller_allowed_countries();

  IF v_is_admin THEN
    -- Admin sees all enabled metrics (filtered to requested list if provided)
    SELECT ARRAY_AGG(metric_name)
    INTO   v_allowed_metrics
    FROM   rep_portal.metric_config
    WHERE  enabled = true
      AND  (p_metrics IS NULL OR array_length(p_metrics, 1) IS NULL OR metric_name = ANY(p_metrics));
  ELSE
    -- Non-admin: intersect requested metrics with permitted metrics via
    -- the per-metric dd:metric:* RBAC bridge.
    SELECT ARRAY_AGG(DISTINCT mc.metric_name)
    INTO   v_allowed_metrics
    FROM   rep_portal.metric_config               mc
    JOIN   rep_portal.permission_metric_config_map pmcm ON pmcm.metric_config_id = mc.id
    JOIN   rep_portal.permissions                  p    ON p.key                = pmcm.permission_key
    JOIN   rep_portal.role_permissions             rp   ON rp.permission_id     = p.id
    JOIN   rep_portal.user_roles                   ur   ON ur.role_id           = rp.role_id
    WHERE  ur.user_id  = auth.uid()
      AND  mc.enabled  = true
      AND  (p_metrics IS NULL OR array_length(p_metrics, 1) IS NULL OR mc.metric_name = ANY(p_metrics));
  END IF;

  IF v_allowed_metrics IS NULL OR array_length(v_allowed_metrics, 1) IS NULL THEN
    RETURN json_build_object('data', '[]'::json);
  END IF;

  -- Country RBAC: default-deny for non-admins with no countries assigned.
  IF v_allowed_countries IS NOT NULL AND array_length(v_allowed_countries, 1) IS NULL THEN
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
        a.school_type,
        a.year,
        a.metric,
        a.value
      FROM rep_portal.dashboard_data_agg a
      WHERE a.metric = ANY(v_allowed_metrics)
        AND a.year BETWEEN p_year_start AND p_year_end
        AND (v_allowed_countries IS NULL OR a.country = ANY(v_allowed_countries))
        AND (p_countries IS NULL OR array_length(p_countries, 1) IS NULL OR a.country  = ANY(p_countries))
        AND (p_provinces IS NULL OR array_length(p_provinces, 1) IS NULL OR a.province = ANY(p_provinces))
        AND (p_districts IS NULL OR array_length(p_districts, 1) IS NULL OR a.district = ANY(p_districts))
        AND (p_schools   IS NULL OR array_length(p_schools,   1) IS NULL OR a.school   = ANY(p_schools))
        -- School type only ever narrows school-level rows. District/country-level
        -- rows carry NULL school_type and are excluded when a type is requested,
        -- which is correct: those metrics have no school to classify.
        AND (p_school_types IS NULL OR array_length(p_school_types, 1) IS NULL
             OR a.school_type = ANY(p_school_types))
      ORDER BY a.metric, a.country, a.province, a.district, a.school, a.year
    ) r
  );
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.get_dashboard_data_filtered(text[], text[], text[], text[], int, int, text[], text[]) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_dashboard_data_filtered(text[], text[], text[], text[], int, int, text[], text[]) TO authenticated;


-- ===== 20260818105515_scope_map_data_by_country.sql =====
-- Country-scope the Map RPCs using rep_portal.caller_allowed_countries().
-- Both already hardcode a 5-country data-availability whitelist
-- ('Tanzania','Ghana','Malawi','Zambia','Zimbabwe') for which countries have
-- map shape data; the RBAC filter layers on top of that, both must pass.
-- search_path is rep_warehouse, public (unchanged) so caller_allowed_countries()
-- is called schema-qualified.

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
    AND (rep_portal.caller_allowed_countries() IS NULL
         OR country = ANY(rep_portal.caller_allowed_countries()))
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

REVOKE EXECUTE ON FUNCTION rep_portal.get_district_kpi_data() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_district_kpi_data() TO authenticated;


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
  AND g.country IN ('Tanzania', 'Ghana', 'Malawi', 'Zambia', 'Zimbabwe')
  AND (rep_portal.caller_allowed_countries() IS NULL
       OR g.country = ANY(rep_portal.caller_allowed_countries()));
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.get_school_point_data() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_school_point_data() TO authenticated;


-- ===== 20260818110136_scope_kpi_report_by_country.sql =====
-- Country-scope the rep_portal.kpi_report_* wrapper functions used by the
-- KPI Trends and KPI Report web pages, via rep_portal.caller_allowed_countries().
--
-- These wrappers are also called by the WhatsApp bot (whatsapp-webhook,
-- service-role client, no auth.uid()) -- caller_allowed_countries() already
-- treats service_role as unrestricted (NULL), so bot behavior is unchanged.
-- rep_warehouse.kpi_report_* (the underlying implementations) are left
-- untouched: the RBAC gate lives only in the rep_portal API layer.
--
-- kpi_report_all_groups / kpi_report_all_indicators / kpi_report_country are
-- unchanged: they return group/indicator names or a district->country lookup,
-- not country-scoped data rows.

CREATE OR REPLACE FUNCTION rep_portal.kpi_report_years(p_country text)
RETURNS TABLE(year integer)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT * FROM rep_warehouse.kpi_report_years(p_country)
  WHERE rep_portal.caller_allowed_countries() IS NULL
     OR p_country = ANY(rep_portal.caller_allowed_countries());
$$;

CREATE OR REPLACE FUNCTION rep_portal.kpi_report_groups(p_country text, p_year integer)
RETURNS TABLE(kpi_group text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT * FROM rep_warehouse.kpi_report_groups(p_country, p_year)
  WHERE rep_portal.caller_allowed_countries() IS NULL
     OR p_country = ANY(rep_portal.caller_allowed_countries());
$$;

CREATE OR REPLACE FUNCTION rep_portal.kpi_report_indicators(p_country text, p_year integer, p_kpi_group text)
RETURNS TABLE(indicator text, short_label text, source_kpi_id text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT indicator, short_label, source_kpi_id
  FROM rep_warehouse.kpi_report_indicators(p_country, p_year, p_kpi_group)
       WITH ORDINALITY AS t(indicator, short_label, source_kpi_id, ord)
  WHERE rep_portal.caller_allowed_countries() IS NULL
     OR p_country = ANY(rep_portal.caller_allowed_countries())
  ORDER BY ord;
$$;

CREATE OR REPLACE FUNCTION rep_portal.kpi_report_indicator_detail(p_country text, p_year integer, p_kpi_group text, p_indicator text)
RETURNS TABLE(disaggregation_level_one text, disaggregation_level_two text, value_type text, value text, definition text, source_kpi_id text)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT disaggregation_level_one, disaggregation_level_two, value_type, value, definition, source_kpi_id
  FROM rep_warehouse.kpi_report_indicator_detail(p_country, p_year, p_kpi_group, p_indicator)
       WITH ORDINALITY AS t(disaggregation_level_one, disaggregation_level_two, value_type, value, definition, source_kpi_id, ord)
  WHERE rep_portal.caller_allowed_countries() IS NULL
     OR p_country = ANY(rep_portal.caller_allowed_countries())
  ORDER BY ord;
$$;

CREATE OR REPLACE FUNCTION rep_portal.kpi_report_indicator_trend(p_country text, p_kpi_group text, p_indicator text)
RETURNS TABLE(year integer, disaggregation_level_one text, disaggregation_level_two text, value_type text, value text, is_visible boolean)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT t.year, t.disaggregation_level_one, t.disaggregation_level_two, t.value_type, t.value,
         COALESCE(v.is_visible, true)
  FROM rep_warehouse.kpi_report_indicator_trend(p_country, p_kpi_group, p_indicator)
       WITH ORDINALITY AS t(year, disaggregation_level_one, disaggregation_level_two, value_type, value, ord)
  LEFT JOIN rep_portal.kpi_trend_chart_visibility v
    ON v.chart_key = rep_warehouse.kpi_trend_chart_key(p_kpi_group, p_indicator, t.disaggregation_level_one, t.disaggregation_level_two)
  WHERE rep_portal.caller_allowed_countries() IS NULL
     OR p_country = ANY(rep_portal.caller_allowed_countries())
  ORDER BY t.ord;
$$;

CREATE OR REPLACE FUNCTION rep_portal.kpi_report_indicator_trend_all_countries(p_kpi_group text, p_indicator text)
RETURNS TABLE(country text, year integer, disaggregation_level_one text, disaggregation_level_two text, value_type text, value text, is_visible boolean)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT t.country, t.year, t.disaggregation_level_one, t.disaggregation_level_two, t.value_type, t.value,
         COALESCE(v.is_visible, true)
  FROM rep_warehouse.kpi_report_indicator_trend_all_countries(p_kpi_group, p_indicator)
       WITH ORDINALITY AS t(country, year, disaggregation_level_one, disaggregation_level_two, value_type, value, ord)
  LEFT JOIN rep_portal.kpi_trend_chart_visibility v
    ON v.chart_key = rep_warehouse.kpi_trend_chart_key(p_kpi_group, p_indicator, t.disaggregation_level_one, t.disaggregation_level_two)
  WHERE rep_portal.caller_allowed_countries() IS NULL
     OR t.country = ANY(rep_portal.caller_allowed_countries())
  ORDER BY t.ord;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_report_years(text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.kpi_report_years(text) TO authenticated;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_report_groups(text, integer) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.kpi_report_groups(text, integer) TO authenticated;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_report_indicators(text, integer, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.kpi_report_indicators(text, integer, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_report_indicator_detail(text, integer, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.kpi_report_indicator_detail(text, integer, text, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_report_indicator_trend(text, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.kpi_report_indicator_trend(text, text, text) TO authenticated;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_report_indicator_trend_all_countries(text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.kpi_report_indicator_trend_all_countries(text, text) TO authenticated;


-- ===== 20260818110231_scope_kpi_milestone_report_by_country.sql =====
-- Country-scope rep_portal.kpi_milestone_report() using
-- rep_portal.caller_allowed_countries(). This function deliberately shows
-- all countries side-by-side in one grouped-bar chart (matches CAMFED's
-- "Spotlight KPIs" deck) and has no country parameter -- so instead of
-- gating the whole call, filter which country rows come back, per row.
-- A restricted caller simply sees fewer bars. Also called by the WhatsApp
-- bot (service-role), which caller_allowed_countries() already treats as
-- unrestricted (NULL).
--
-- kpi_milestone_years / kpi_milestone_groups / kpi_milestone_indicators are
-- unchanged: they return years/group/indicator names, not country data rows.
CREATE OR REPLACE FUNCTION rep_portal.kpi_milestone_report(p_year integer, p_kpi_group text, p_indicator text)
RETURNS TABLE(country text, disaggregation_level_one text, disaggregation_level_two text, milestone_value numeric, actual_value numeric, value_type text, is_visible boolean)
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT t.country, t.disaggregation_level_one, t.disaggregation_level_two, t.milestone_value, t.actual_value, t.value_type,
         COALESCE(v.is_visible, true)
  FROM rep_warehouse.kpi_milestone_report(p_year, p_kpi_group, p_indicator)
       WITH ORDINALITY AS t(country, disaggregation_level_one, disaggregation_level_two, milestone_value, actual_value, value_type, ord)
  LEFT JOIN rep_portal.kpi_milestone_chart_visibility v
    ON v.chart_key = rep_warehouse.kpi_milestone_chart_key(p_kpi_group, p_indicator, t.disaggregation_level_one, t.disaggregation_level_two)
  WHERE rep_portal.caller_allowed_countries() IS NULL
     OR t.country = ANY(rep_portal.caller_allowed_countries())
  ORDER BY t.ord;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_milestone_report(integer, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.kpi_milestone_report(integer, text, text) TO authenticated;


-- ===== 20260821075407_create_deleted_source_ids.sql =====
-- Tracks Salesforce records observed with IsDeleted = true, detected by the
-- standalone ingest-deletions pipeline (separate from the main ingest pipeline).
-- Lives in rep_warehouse (not rep_raw) so it survives rep_raw full-load truncates.
CREATE TABLE rep_warehouse.deleted_source_ids (
    object_name        TEXT        NOT NULL,   -- e.g. 'schools', 'contacts', 'academic_record'
    salesforce_id       TEXT        NOT NULL,
    sf_deleted_at       TIMESTAMPTZ,             -- Salesforce LastModifiedDate at time of delete
    detected_at         TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    processed_at        TIMESTAMPTZ,             -- set once etl_apply_deletions() has soft-deleted the warehouse row
    deletion_run_id      UUID,
    PRIMARY KEY (object_name, salesforce_id)
);

CREATE INDEX idx_deleted_source_ids_unprocessed
    ON rep_warehouse.deleted_source_ids (object_name)
    WHERE processed_at IS NULL;

ALTER TABLE rep_warehouse.deleted_source_ids ENABLE ROW LEVEL SECURITY;
-- No policies: default deny. Only accessed via SECURITY DEFINER functions
-- (rep_warehouse.etl_apply_deletions) and service-role Edge Functions.


-- ===== 20260821075419_create_deletion_run_log.sql =====
-- Run-level log for the standalone ingest-deletions pipeline, analogous to
-- rep_warehouse.ingest_run / etl_batch_log for the main ingest/ETL pipeline.
-- Answers "did deletion detection run, when, against how many objects, did it succeed".
CREATE TABLE rep_warehouse.deletion_run_log (
    run_id              UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
    triggered_by        TEXT,           -- ingest_run.run_id (as text) that triggered it via the reactive trigger, or 'manual'
    started_at          TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    finished_at         TIMESTAMPTZ,
    status              TEXT        NOT NULL DEFAULT 'in_progress',  -- 'in_progress' | 'completed' | 'failed'
    objects_queried     INTEGER,
    deletions_found     INTEGER,
    deletions_applied   INTEGER,
    error                TEXT
);

CREATE INDEX idx_deletion_run_log_started_at
    ON rep_warehouse.deletion_run_log (started_at DESC);

ALTER TABLE rep_warehouse.deletion_run_log ENABLE ROW LEVEL SECURITY;
-- No policies: default deny. Written by the ingest-deletions Edge Function (service role).


-- ===== 20260821075521_etl_apply_deletions.sql =====
-- Soft-deletes warehouse rows whose Salesforce source record was observed with
-- IsDeleted = true by the standalone ingest-deletions pipeline. Reads from
-- rep_warehouse.deleted_source_ids (populated by ingest-deletions) and never
-- touches etl_run_salesforce()/etl_run_staging()/etl_run_warehouse() — this is a
-- deliberately separate, additive step so the existing verified ETL is untouched.
--
-- dim_geography (built from countries/districts, keyed by name not Salesforce Id)
-- has no source id column to soft-delete against, so 'countries' and 'districts'
-- deletions are recorded in deleted_source_ids but intentionally not propagated
-- to the warehouse here — see CLAUDE.md's known-gaps register.
CREATE OR REPLACE FUNCTION rep_warehouse.etl_apply_deletions(p_deletion_run_id UUID DEFAULT NULL)
RETURNS TABLE(objects_processed INTEGER, rows_soft_deleted INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, rep_staging, rep_raw, pg_temp
SET statement_timeout = 0 AS $$
DECLARE
    v_dims_updated    INTEGER := 0;
    v_facts_updated   INTEGER := 0;
    v_rows            INTEGER;
    v_objects_touched INTEGER;
BEGIN
    SELECT COUNT(DISTINCT object_name) INTO v_objects_touched
    FROM rep_warehouse.deleted_source_ids WHERE processed_at IS NULL;

    -- ── ROC dimensions (source_roc_id) ──────────────────────────────────────
    UPDATE rep_warehouse.dim_roc_geography w
    SET scd_is_current = false, scd_effective_to = CURRENT_DATE
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'dimension_1_roc' AND d.processed_at IS NULL
      AND w.source_roc_id = d.salesforce_id AND w.scd_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_dims_updated := v_dims_updated + v_rows;

    UPDATE rep_warehouse.dim_roc_project_code w
    SET scd_is_current = false, scd_effective_to = CURRENT_DATE
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'dimension_2_roc' AND d.processed_at IS NULL
      AND w.source_roc_id = d.salesforce_id AND w.scd_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_dims_updated := v_dims_updated + v_rows;

    UPDATE rep_warehouse.dim_roc_donor w
    SET scd_is_current = false, scd_effective_to = CURRENT_DATE
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'dimension_3_roc' AND d.processed_at IS NULL
      AND w.source_roc_id = d.salesforce_id AND w.scd_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_dims_updated := v_dims_updated + v_rows;

    UPDATE rep_warehouse.dim_roc_donor_activity w
    SET scd_is_current = false, scd_effective_to = CURRENT_DATE
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'dimension_4_roc' AND d.processed_at IS NULL
      AND w.source_roc_id = d.salesforce_id AND w.scd_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_dims_updated := v_dims_updated + v_rows;

    -- ── dim_school (source_school_id) ───────────────────────────────────────
    UPDATE rep_warehouse.dim_school w
    SET scd_is_current = false, scd_effective_to = CURRENT_DATE
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'schools' AND d.processed_at IS NULL
      AND w.source_school_id = d.salesforce_id AND w.scd_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_dims_updated := v_dims_updated + v_rows;

    -- ── dim_contact — special-cased ─────────────────────────────────────────
    -- dim_contact merges 5 staging sources by priority (contacts > academic_record
    -- > guides > cama_members > grant_recipients, see etl_load_dim_contact()).
    -- A deletion on a non-authoritative source must NOT blank the contact — the
    -- merge already self-heals by falling back to the next-priority source on the
    -- next ETL run. Only soft-delete dim_contact when the deletion is on the
    -- 'contacts' object itself AND no other staging source still carries a row
    -- for that contact_id (defensive anti-join mirroring etl_load_dim_contact()'s
    -- own UNION ALL sources).
    UPDATE rep_warehouse.dim_contact w
    SET scd_is_current = false, scd_effective_to = CURRENT_DATE
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'contacts' AND d.processed_at IS NULL
      AND w.source_contact_id = d.salesforce_id AND w.scd_is_current = true
      AND NOT EXISTS (SELECT 1 FROM rep_staging.contacts s WHERE s.salesforce_id = d.salesforce_id)
      AND NOT EXISTS (SELECT 1 FROM rep_staging.academic_record s WHERE s.contact_id = d.salesforce_id)
      AND NOT EXISTS (SELECT 1 FROM rep_staging.guides s WHERE s.contact_id = d.salesforce_id)
      AND NOT EXISTS (SELECT 1 FROM rep_staging.cama_members s WHERE s.contact_id = d.salesforce_id)
      AND NOT EXISTS (SELECT 1 FROM rep_staging.grant_recipients s WHERE s.contact_id = d.salesforce_id);
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_dims_updated := v_dims_updated + v_rows;

    -- ── Facts (1:1 with a specific source record, no merge ambiguity) ──────
    UPDATE rep_warehouse.fact_children_supported f
    SET lin_is_current = false
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'academic_record' AND d.processed_at IS NULL
      AND f.source_academic_record_id = d.salesforce_id AND f.lin_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_facts_updated := v_facts_updated + v_rows;

    UPDATE rep_warehouse.fact_post_school_support f
    SET lin_is_current = false
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'academic_record' AND d.processed_at IS NULL
      AND f.source_academic_record_id = d.salesforce_id AND f.lin_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_facts_updated := v_facts_updated + v_rows;

    UPDATE rep_warehouse.fact_guide_assignment f
    SET lin_is_current = false
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'guides' AND d.processed_at IS NULL
      AND f.source_guide_id = d.salesforce_id AND f.lin_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_facts_updated := v_facts_updated + v_rows;

    UPDATE rep_warehouse.fact_cama_membership f
    SET lin_is_current = false
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'contacts' AND d.processed_at IS NULL
      AND f.source_contact_id = d.salesforce_id AND f.lin_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_facts_updated := v_facts_updated + v_rows;

    UPDATE rep_warehouse.fact_grants f
    SET lin_is_current = false
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'grant_recipients' AND d.processed_at IS NULL
      AND f.source_grant_id = d.salesforce_id AND f.lin_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_facts_updated := v_facts_updated + v_rows;

    UPDATE rep_warehouse.fact_loans f
    SET lin_is_current = false
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'loan_recipients' AND d.processed_at IS NULL
      AND f.source_loan_id = d.salesforce_id AND f.lin_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_facts_updated := v_facts_updated + v_rows;

    -- ── Mark every row this run touched as processed ────────────────────────
    -- (countries/districts rows are marked processed too — they're intentionally
    -- not propagated to the warehouse, see header comment — so they don't get
    -- re-scanned by every future run.)
    UPDATE rep_warehouse.deleted_source_ids
    SET processed_at = NOW(), deletion_run_id = COALESCE(p_deletion_run_id, deletion_run_id)
    WHERE processed_at IS NULL;

    RETURN QUERY SELECT v_objects_touched, v_dims_updated + v_facts_updated;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.etl_apply_deletions(UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_warehouse.etl_apply_deletions(UUID) TO service_role;


-- ===== 20260821075633_ingest_run_completed_trigger_deletions.sql =====
-- Reactive trigger: fires the new ingest-deletions Edge Function whenever an
-- ingest_run flips to 'completed'. Chosen instead of a second pg_cron schedule
-- so deletion detection runs right after every ingest without a standalone
-- schedule and without editing ingest-trigger/the orchestrator/run-ingest.js —
-- it only reacts to a status write those already make.
--
-- Mirrors the existing fire-and-forget net.http_post pattern used by
-- kpi_delete_year() (20260603175952_kpi_delete_year_async_refresh.sql), but
-- resolves the target URL from a Vault secret (like configure_ingest_cron())
-- rather than request.headers, since a trigger fired from a plain UPDATE has
-- no PostgREST request context (e.g. run-ingest.js writes ingest_run directly
-- over a DB connection, not through PostgREST).
--
-- One-time setup (per environment), alongside the existing ingest_auth_header secret:
--   SELECT vault.create_secret(
--     'https://<project>.supabase.co/functions/v1/ingest-deletions',
--     'ingest_deletions_url'
--   );
-- Local dev: 'http://host.docker.internal:54321/functions/v1/ingest-deletions'.
-- If the secret is absent (e.g. not yet configured), the trigger silently no-ops.

CREATE OR REPLACE FUNCTION rep_warehouse.trg_fire_ingest_deletions()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, public AS $$
DECLARE
    v_url  TEXT;
    v_auth TEXT;
BEGIN
    BEGIN
        SELECT decrypted_secret INTO v_url  FROM vault.decrypted_secrets WHERE name = 'ingest_deletions_url';
        SELECT decrypted_secret INTO v_auth FROM vault.decrypted_secrets WHERE name = 'ingest_auth_header';

        IF v_url IS NOT NULL AND v_auth IS NOT NULL THEN
            PERFORM net.http_post(
                url     := v_url,
                headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', v_auth),
                body    := jsonb_build_object('triggered_by', NEW.run_id)
            );
        END IF;
    EXCEPTION WHEN OTHERS THEN
        -- Never let a missing secret or an unreachable function fail the ingest run.
        NULL;
    END;
    RETURN NEW;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.trg_fire_ingest_deletions() FROM PUBLIC;

CREATE TRIGGER trg_ingest_run_completed_fire_deletions
AFTER UPDATE ON rep_warehouse.ingest_run
FOR EACH ROW
WHEN (NEW.status = 'completed' AND OLD.status IS DISTINCT FROM 'completed')
EXECUTE FUNCTION rep_warehouse.trg_fire_ingest_deletions();


-- ===== 20260821075717_filter_fact_views_lin_is_current.sql =====
-- Adds a `WHERE f.lin_is_current = true` predicate to every fact-backed view.
-- lin_is_current has existed on every fact table since the start but was never
-- actually filtered anywhere — soft-deleting a fact row (rep_warehouse.etl_apply_deletions,
-- part of the new deletion-detection pipeline) had no visible effect without this.
-- Bodies below are copied verbatim from each view's latest prior migration
-- (20260803120000 for view_children_supported/view_guide_assignment/view_cama_membership,
-- 20260707170002 for view_loans, 20250201000031 for view_post_school_support/view_grants)
-- with only the new WHERE clause added — no other column/join changes.

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
    g.country,
    s.school_type
FROM rep_warehouse.fact_children_supported f
LEFT JOIN rep_warehouse.dim_contact         ct ON ct.id = f.contact_id
LEFT JOIN rep_warehouse.dim_school           s  ON  s.id = f.school_id
LEFT JOIN rep_warehouse.dim_geography        g  ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date            dd  ON dd.id = f.year_date_id
LEFT JOIN rep_warehouse.dim_roc_donor       d3  ON d3.id = f.roc_donor_id
LEFT JOIN rep_warehouse.dim_roc_project_code d2 ON d2.id = f.roc_project_code_id
WHERE f.lin_is_current = true;

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
    g.country,
    s.school_type
FROM rep_warehouse.fact_guide_assignment f
LEFT JOIN rep_warehouse.dim_contact  ct       ON ct.id = f.contact_id
LEFT JOIN rep_warehouse.dim_school    s        ON  s.id = f.school_id
LEFT JOIN rep_warehouse.dim_geography g        ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date      joined_dd ON joined_dd.id = f.date_joined_id
LEFT JOIN rep_warehouse.dim_date      left_dd   ON left_dd.id   = f.date_left_id
LEFT JOIN rep_warehouse.dim_roc_donor d3        ON d3.id = f.roc_donor_id
WHERE f.lin_is_current = true;

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
    g.country,
    s.school_type
FROM rep_warehouse.fact_cama_membership f
LEFT JOIN rep_warehouse.dim_contact  ct ON ct.id = f.contact_id
LEFT JOIN rep_warehouse.dim_school    s  ON  s.id = f.school_id
LEFT JOIN rep_warehouse.dim_geography g  ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = f.date_joined_id
WHERE f.lin_is_current = true;

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
LEFT JOIN rep_warehouse.dim_roc_donor d3 ON d3.id = f.roc_donor_id
WHERE f.lin_is_current = true;

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
LEFT JOIN rep_warehouse.dim_roc_donor d3 ON d3.id = f.roc_donor_id
WHERE f.lin_is_current = true;

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
LEFT JOIN rep_warehouse.dim_roc_donor d3 ON d3.id = f.roc_donor_id
WHERE f.lin_is_current = true;

-- view_donor_summary aggregates across four fact tables directly (not via the
-- views above), so it needs its own lin_is_current filter on each join to keep
-- soft-deleted rows out of the counts.
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
LEFT JOIN rep_warehouse.fact_children_supported f_cs ON f_cs.roc_donor_id = d3.id AND f_cs.lin_is_current = true
LEFT JOIN rep_warehouse.fact_guide_assignment   f_ga ON f_ga.roc_donor_id = d3.id AND f_ga.lin_is_current = true
LEFT JOIN rep_warehouse.fact_grants             f_gr ON f_gr.roc_donor_id = d3.id AND f_gr.lin_is_current = true
LEFT JOIN rep_warehouse.fact_loans              f_lo ON f_lo.roc_donor_id = d3.id AND f_lo.lin_is_current = true
WHERE d3.scd_is_current = true
GROUP BY d3.id, d3.name, d3.reporting_code, d3.available_country, d3.active,
         d3.start_date, d3.end_date;


-- ===== 20260821080640_fix_etl_apply_deletions_dim_contact_check.sql =====
-- Fixes rep_warehouse.etl_apply_deletions(): the dim_contact anti-join
-- referenced rep_staging.* tables directly, but rep_staging (and rep_raw for
-- Salesforce objects) are dropped/truncated by etl_run_salesforce()'s own
-- cleanup step *before* this function ever runs (it's fired reactively off
-- ingest_run.status = 'completed', which is set only after that cleanup).
-- Confirmed by local testing: "relation rep_staging.contacts does not exist"
-- aborted the whole function, silently rolling back every soft-delete in the
-- same call (including unrelated dim_school rows) since it's one transaction.
--
-- Fix: check the permanent warehouse fact tables instead of transient staging.
-- Also corrected the source list — 'cama_members' isn't an independent
-- Salesforce object (rep_staging.cama_members is just rep_staging.contacts
-- filtered to record_type_name = 'Cama', see CLAUDE.md), so a 'contacts'
-- deletion already removes that source too; checking it separately was
-- redundant with the 'contacts' branch and has been dropped.
--
-- Also stamps lin_load_batch_id = d.deletion_run_id on every soft-deleted row,
-- matching the existing "one UUID flows everywhere" convention
-- (ingest_run.run_id = etl_batch_log.batch_id = lin_load_batch_id — CLAUDE.md
-- → Batch ID propagation). ingest-deletions reuses the triggering
-- ingest_run.run_id as deletion_run_log.run_id (and therefore
-- deleted_source_ids.deletion_run_id) whenever it's fired by the reactive
-- trigger, so in the common case this is the same batch id already on the row
-- from other columns in that pipeline run, not an unrelated new one.
CREATE OR REPLACE FUNCTION rep_warehouse.etl_apply_deletions(p_deletion_run_id UUID DEFAULT NULL)
RETURNS TABLE(objects_processed INTEGER, rows_soft_deleted INTEGER)
LANGUAGE plpgsql
SECURITY DEFINER SET search_path = rep_warehouse, pg_temp
SET statement_timeout = 0 AS $$
DECLARE
    v_dims_updated    INTEGER := 0;
    v_facts_updated   INTEGER := 0;
    v_rows            INTEGER;
    v_objects_touched INTEGER;
BEGIN
    SELECT COUNT(DISTINCT object_name) INTO v_objects_touched
    FROM rep_warehouse.deleted_source_ids WHERE processed_at IS NULL;

    -- ── ROC dimensions (source_roc_id) ──────────────────────────────────────
    UPDATE rep_warehouse.dim_roc_geography w
    SET scd_is_current = false, scd_effective_to = CURRENT_DATE, lin_load_batch_id = d.deletion_run_id::text
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'dimension_1_roc' AND d.processed_at IS NULL
      AND w.source_roc_id = d.salesforce_id AND w.scd_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_dims_updated := v_dims_updated + v_rows;

    UPDATE rep_warehouse.dim_roc_project_code w
    SET scd_is_current = false, scd_effective_to = CURRENT_DATE, lin_load_batch_id = d.deletion_run_id::text
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'dimension_2_roc' AND d.processed_at IS NULL
      AND w.source_roc_id = d.salesforce_id AND w.scd_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_dims_updated := v_dims_updated + v_rows;

    UPDATE rep_warehouse.dim_roc_donor w
    SET scd_is_current = false, scd_effective_to = CURRENT_DATE, lin_load_batch_id = d.deletion_run_id::text
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'dimension_3_roc' AND d.processed_at IS NULL
      AND w.source_roc_id = d.salesforce_id AND w.scd_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_dims_updated := v_dims_updated + v_rows;

    UPDATE rep_warehouse.dim_roc_donor_activity w
    SET scd_is_current = false, scd_effective_to = CURRENT_DATE, lin_load_batch_id = d.deletion_run_id::text
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'dimension_4_roc' AND d.processed_at IS NULL
      AND w.source_roc_id = d.salesforce_id AND w.scd_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_dims_updated := v_dims_updated + v_rows;

    -- ── dim_school (source_school_id) ───────────────────────────────────────
    UPDATE rep_warehouse.dim_school w
    SET scd_is_current = false, scd_effective_to = CURRENT_DATE, lin_load_batch_id = d.deletion_run_id::text
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'schools' AND d.processed_at IS NULL
      AND w.source_school_id = d.salesforce_id AND w.scd_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_dims_updated := v_dims_updated + v_rows;

    -- ── dim_contact — special-cased ─────────────────────────────────────────
    -- dim_contact merges 5 staging sources by priority (contacts >
    -- academic_record > guides > cama_members > grant_recipients, see
    -- etl_load_dim_contact()) — but rep_staging/rep_raw don't exist by the
    -- time this function runs (see header comment), so "does another source
    -- still have this contact" is checked against permanent warehouse facts
    -- instead: fact_children_supported/fact_post_school_support stand in for
    -- academic_record, fact_guide_assignment for guides, fact_grants for
    -- grant_recipients. cama_members is the same underlying Contact record as
    -- 'contacts', not an independent source, so it needs no separate check.
    -- Only soft-delete dim_contact when the deletion is on 'contacts' itself
    -- AND none of those three still carry a current row for the contact.
    UPDATE rep_warehouse.dim_contact w
    SET scd_is_current = false, scd_effective_to = CURRENT_DATE, lin_load_batch_id = d.deletion_run_id::text
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'contacts' AND d.processed_at IS NULL
      AND w.source_contact_id = d.salesforce_id AND w.scd_is_current = true
      AND NOT EXISTS (
        SELECT 1 FROM rep_warehouse.fact_children_supported f
        WHERE f.source_contact_id = d.salesforce_id AND f.lin_is_current = true
      )
      AND NOT EXISTS (
        SELECT 1 FROM rep_warehouse.fact_post_school_support f
        WHERE f.source_contact_id = d.salesforce_id AND f.lin_is_current = true
      )
      AND NOT EXISTS (
        SELECT 1 FROM rep_warehouse.fact_guide_assignment f
        WHERE f.source_contact_id = d.salesforce_id AND f.lin_is_current = true
      )
      AND NOT EXISTS (
        SELECT 1 FROM rep_warehouse.fact_grants f
        WHERE f.source_contact_id = d.salesforce_id AND f.lin_is_current = true
      );
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_dims_updated := v_dims_updated + v_rows;

    -- ── Facts (1:1 with a specific source record, no merge ambiguity) ──────
    UPDATE rep_warehouse.fact_children_supported f
    SET lin_is_current = false, lin_load_batch_id = d.deletion_run_id::text
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'academic_record' AND d.processed_at IS NULL
      AND f.source_academic_record_id = d.salesforce_id AND f.lin_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_facts_updated := v_facts_updated + v_rows;

    UPDATE rep_warehouse.fact_post_school_support f
    SET lin_is_current = false, lin_load_batch_id = d.deletion_run_id::text
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'academic_record' AND d.processed_at IS NULL
      AND f.source_academic_record_id = d.salesforce_id AND f.lin_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_facts_updated := v_facts_updated + v_rows;

    UPDATE rep_warehouse.fact_guide_assignment f
    SET lin_is_current = false, lin_load_batch_id = d.deletion_run_id::text
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'guides' AND d.processed_at IS NULL
      AND f.source_guide_id = d.salesforce_id AND f.lin_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_facts_updated := v_facts_updated + v_rows;

    UPDATE rep_warehouse.fact_cama_membership f
    SET lin_is_current = false, lin_load_batch_id = d.deletion_run_id::text
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'contacts' AND d.processed_at IS NULL
      AND f.source_contact_id = d.salesforce_id AND f.lin_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_facts_updated := v_facts_updated + v_rows;

    UPDATE rep_warehouse.fact_grants f
    SET lin_is_current = false, lin_load_batch_id = d.deletion_run_id::text
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'grant_recipients' AND d.processed_at IS NULL
      AND f.source_grant_id = d.salesforce_id AND f.lin_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_facts_updated := v_facts_updated + v_rows;

    UPDATE rep_warehouse.fact_loans f
    SET lin_is_current = false, lin_load_batch_id = d.deletion_run_id::text
    FROM rep_warehouse.deleted_source_ids d
    WHERE d.object_name = 'loan_recipients' AND d.processed_at IS NULL
      AND f.source_loan_id = d.salesforce_id AND f.lin_is_current = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT; v_facts_updated := v_facts_updated + v_rows;

    -- ── Mark every row this run touched as processed ────────────────────────
    -- (countries/districts rows are marked processed too — they're intentionally
    -- not propagated to the warehouse, see the original migration's header
    -- comment — so they don't get re-scanned by every future run.)
    UPDATE rep_warehouse.deleted_source_ids
    SET processed_at = NOW(), deletion_run_id = COALESCE(p_deletion_run_id, deletion_run_id)
    WHERE processed_at IS NULL;

    RETURN QUERY SELECT v_objects_touched, v_dims_updated + v_facts_updated;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.etl_apply_deletions(UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_warehouse.etl_apply_deletions(UUID) TO service_role;


-- ===== 20260821081019_grant_service_role_deletion_tables.sql =====
-- Fixes a gap in the original deleted_source_ids/deletion_run_log migrations:
-- enabling RLS with no policy blocks all table-level access via PostgREST,
-- including service_role — RLS bypass for service_role doesn't substitute for
-- an explicit GRANT (PostgREST still checks table privileges first). Confirmed
-- by local testing: the ingest-deletions Edge Function's service-role insert
-- failed with "permission denied for table deletion_run_log" until this grant
-- was added. Matches the existing rep_warehouse.ingest_run pattern
-- (20250201000011_security.sql): GRANT ALL ... TO service_role alongside RLS.
GRANT ALL ON rep_warehouse.deleted_source_ids TO service_role;
GRANT ALL ON rep_warehouse.deletion_run_log   TO service_role;


-- ===== 20260821083419_add_get_deletion_run_log_entry_rpc.sql =====
-- Admin RPC for the Salesforce Log page (frontend/src/routes/admin/ingest.tsx):
-- surfaces the deletion-detection run for a given ingest run, alongside the
-- existing "ETL Transform" section (get_etl_batch_log_entry). Looked up by
-- run_id directly — ingest-deletions reuses the triggering ingest_run.run_id
-- as deletion_run_log.run_id (see CLAUDE.md → Deletion tracking), so a match
-- here means that ingest run's completion is what fired detection.
-- Same auth pattern as get_etl_batch_log_entry(): admin-only.
CREATE OR REPLACE FUNCTION rep_portal.get_deletion_run_log_entry(p_run_id UUID)
RETURNS TABLE (
  run_id             UUID,
  status             TEXT,
  objects_queried    INTEGER,
  deletions_found    INTEGER,
  deletions_applied  INTEGER,
  started_at         TIMESTAMPTZ,
  finished_at        TIMESTAMPTZ,
  error              TEXT
) LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin privileges required';
  END IF;
  RETURN QUERY
    SELECT l.run_id, l.status, l.objects_queried, l.deletions_found, l.deletions_applied,
           l.started_at, l.finished_at, l.error
    FROM rep_warehouse.deletion_run_log l
    WHERE l.run_id = p_run_id;
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.get_deletion_run_log_entry(UUID) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_deletion_run_log_entry(UUID) TO authenticated;


-- ===== 20260826075955_fix_usage_views_security_invoker.sql =====
-- Supabase security advisor (security_definer_view) flagged the four usage
-- analytics views as SECURITY DEFINER. The migration that created them
-- (20260712131244_add_portal_page_views.sql) intended them to be
-- security_invoker so a non-admin querying them directly (bypassing the
-- get_usage_*() RPCs, which check is_admin()) would still be blocked by the
-- admin-only RLS policies on portal_page_views / portal_usage_monthly.
-- security_invoker was never actually set, so the views ran with the view
-- owner's rights, bypassing RLS entirely for any authenticated user granted
-- direct SELECT on them.

ALTER VIEW rep_portal.view_usage_daily    SET (security_invoker = true);
ALTER VIEW rep_portal.view_usage_by_page  SET (security_invoker = true);
ALTER VIEW rep_portal.view_usage_by_user  SET (security_invoker = true);
ALTER VIEW rep_portal.view_usage_monthly  SET (security_invoker = true);

