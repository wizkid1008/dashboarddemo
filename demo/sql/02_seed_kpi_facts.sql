-- ============================================================================
-- Demo seed 2/4 - KPI facts and milestones
--
-- Populates rep_warehouse.fact_observed_kpi for every (kpi_id, disaggregation)
-- combination that rep_portal.kpi_mapping actually asks for, across all five
-- seeded countries and 2020-2026. Driving the seed off kpi_mapping rather than
-- a hand-written list means every Data Dashboard card that exists gets data,
-- including any added by later migrations.
--
-- Backs: Data Dashboard (all three levels), KPI Report, KPI Trends, and -- via
-- fact_kpi_milestone -- KPI Milestones.
--
-- row_scope is computed with the same CASE expression the real ETL uses
-- (etl_stage_all_kpis), because the view_kpi_* views filter on it; getting it
-- wrong makes rows invisible rather than wrong-looking.
--
-- Re-runnable: deletes its own rows (batch 'demo-seed') before inserting.
-- ============================================================================

BEGIN;

DELETE FROM rep_warehouse.fact_observed_kpi  WHERE lin_load_batch_id = 'demo-seed';
DELETE FROM rep_warehouse.fact_kpi_milestone WHERE lin_load_batch_id = 'demo-seed';

-- Observed KPI facts ---------------------------------------------------------

WITH combos AS (
  SELECT DISTINCT
    m.kpi_id,
    m.disaggregation_level_one,
    m.disaggregation_level_two,
    m.data_element
  FROM rep_portal.kpi_mapping m
),
geo AS (
  SELECT id, country
  FROM rep_warehouse.dim_geography
  WHERE province IS NULL AND district IS NULL AND scd_is_current = true
    AND country IN ('Ghana','Malawi','Tanzania','Zambia','Zimbabwe')
),
years AS (SELECT generate_series(2020, 2026) AS year),
base AS (
  SELECT
    c.*,
    g.id   AS geography_id,
    g.country,
    y.year,
    -- Deterministic per (kpi, country) magnitude so numbers are stable across
    -- re-runs and differ plausibly between countries.
    (abs(('x' || substr(md5(c.kpi_id || g.country), 1, 8))::bit(32)::int) % 400 + 120) AS magnitude,
    -- Percentage-shaped indicators must not be seeded with five-figure counts.
    (c.data_element ILIKE '%rate%'
     OR c.data_element ILIKE '%percentage%'
     OR c.data_element ILIKE '%pass%'
     OR c.data_element ILIKE '%progression%'
     OR c.data_element ILIKE '%completion%'
     OR c.data_element ILIKE '%dropout%') AS is_pct,
    (c.disaggregation_level_one ILIKE '%cumulative%'
     OR c.disaggregation_level_two ILIKE '%cumulative%') AS is_cumulative
  FROM combos c
  CROSS JOIN geo g
  CROSS JOIN years y
),
valued AS (
  SELECT
    b.*,
    CASE
      WHEN b.is_pct THEN
        -- 48-92%, drifting upward year on year
        round((48 + (b.magnitude % 30) + (b.year - 2020) * 1.6)::numeric, 1)
      WHEN b.is_cumulative THEN
        -- Running total: annual figure accumulated since 2020
        (b.magnitude * 41 * (b.year - 2019))::numeric
      ELSE
        -- Annual figure with mild growth and a deterministic wobble
        round((b.magnitude * 41 * (1 + (b.year - 2020) * 0.08)
               + ((b.magnitude + b.year) % 37) * 11)::numeric, 0)
    END AS value_num
  FROM base b
)
INSERT INTO rep_warehouse.fact_observed_kpi
  (kpi_id, geography_id, year, year_date_id,
   disaggregation_level_one, disaggregation_level_two,
   value_type, row_scope, value, updated_date, update_quarter,
   lin_is_current, lin_change_type,
   lin_source_system, lin_source_file, lin_load_batch_id)
SELECT
  dk.id,
  v.geography_id,
  v.year::smallint,
  dd.id,
  v.disaggregation_level_one,
  v.disaggregation_level_two,
  CASE WHEN v.is_pct THEN 'Percentage' ELSE 'Number' END,
  CASE
    WHEN v.disaggregation_level_one ILIKE '%cumulative%'
      OR v.disaggregation_level_two ILIKE '%cumulative%'                    THEN 'CUMULATIVE'
    WHEN v.disaggregation_level_two ILIKE 'benchmark'
      OR v.disaggregation_level_two ILIKE '%poverty line%'                  THEN 'BENCHMARK'
    WHEN v.disaggregation_level_one = 'Total'
      OR v.disaggregation_level_two = 'Total'
      OR v.disaggregation_level_two ILIKE '%total'
      OR v.disaggregation_level_two ILIKE 'overall'
      OR v.disaggregation_level_two ILIKE 'combined'
      OR v.disaggregation_level_two ILIKE '%total%'                         THEN 'SUBTOTAL'
    WHEN v.disaggregation_level_one IN ('Annual','Newly supported','Newly reached',
                                        'New since last year','Annual reach per LG')
      OR v.disaggregation_level_two = 'Annual'                              THEN 'ANNUAL'
    ELSE                                                                         'DETAIL'
  END,
  v.value_num::text,
  make_date(v.year, 12, 31),
  'Q4',
  true, 'INSERT',
  'Demo_Seed', 'demo-seed', 'demo-seed'
FROM valued v
JOIN rep_warehouse.dim_kpi dk
  ON dk.source_kpi_id = v.kpi_id AND dk.scd_is_current = true
LEFT JOIN rep_warehouse.dim_date dd
  ON dd.id = (v.year::text || '0101')::integer;

-- Milestones -----------------------------------------------------------------
-- One target per annual KPI/country/year, set slightly above the observed value
-- so the Milestones page shows a mix of met and near-miss targets rather than a
-- uniform wall of green.

INSERT INTO rep_warehouse.fact_kpi_milestone
  (kpi_id, geography_id, year,
   disaggregation_level_one, disaggregation_level_two,
   value, value_type,
   lin_source_system, lin_source_file, lin_load_batch_id)
SELECT
  f.kpi_id,
  f.geography_id,
  f.year,
  f.disaggregation_level_one,
  f.disaggregation_level_two,
  CASE
    WHEN f.value_type = 'Percentage'
      THEN least(round((f.value::numeric * 1.05)::numeric, 1), 99.0)
    ELSE round(f.value::numeric * (CASE WHEN (f.id % 3) = 0 THEN 0.94 ELSE 1.12 END), 0)
  END,
  f.value_type,
  'Demo_Seed', 'demo-seed', 'demo-seed'
FROM rep_warehouse.fact_observed_kpi f
WHERE f.lin_load_batch_id = 'demo-seed'
  AND f.row_scope = 'ANNUAL'
  AND f.value ~ '^[0-9.]+$';

COMMIT;

-- Sanity check: every dashlet element in kpi_mapping should resolve to rows.
SELECT
  m.dashlet_element,
  m.data_element,
  m.toggle,
  COUNT(k.id) AS matching_fact_rows
FROM rep_portal.kpi_mapping m
LEFT JOIN rep_warehouse.view_observed_kpi k
  ON  k.kpi_id = m.kpi_id
  AND (m.disaggregation_level_one IS NULL OR k.disaggregation_level_one = m.disaggregation_level_one)
  AND (m.disaggregation_level_two IS NULL OR k.disaggregation_level_two = m.disaggregation_level_two)
GROUP BY m.dashlet_element, m.data_element, m.toggle
ORDER BY m.dashlet_element;
