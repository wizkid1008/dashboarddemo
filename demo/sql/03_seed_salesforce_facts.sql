-- ============================================================================
-- Demo seed 3/4 - Salesforce-shaped facts
--
-- Backs the Dynamic Data page and the Data Map. Both read the six views that
-- rep_portal.metric_config points at (view_children_supported,
-- view_guide_assignment, view_cama_membership, view_grants, view_loans,
-- view_post_school_support), so all six fact tables are seeded -- otherwise
-- individual Dynamic Data metrics come back as zero rather than absent, which
-- looks like a bug rather than a gap.
--
-- The map's get_district_kpi_data() counts fact_children_supported and
-- fact_guide_assignment per district, which is why guides carry
-- guide_type/guide_status values matching its ILIKE filters.
--
-- Re-runnable: deletes its own rows (batch 'demo-seed') before inserting.
-- Row volume is roughly 15k facts; the refresh at the end is the slow part.
-- ============================================================================

BEGIN;

DELETE FROM rep_warehouse.fact_children_supported  WHERE lin_load_batch_id = 'demo-seed';
DELETE FROM rep_warehouse.fact_guide_assignment    WHERE lin_load_batch_id = 'demo-seed';
DELETE FROM rep_warehouse.fact_cama_membership     WHERE lin_load_batch_id = 'demo-seed';
DELETE FROM rep_warehouse.fact_post_school_support WHERE lin_load_batch_id = 'demo-seed';
DELETE FROM rep_warehouse.fact_grants              WHERE lin_load_batch_id = 'demo-seed';
DELETE FROM rep_warehouse.fact_loans               WHERE lin_load_batch_id = 'demo-seed';

-- Children supported: one row per pupil per year -----------------------------

INSERT INTO rep_warehouse.fact_children_supported
  (source_contact_id, contact_id, source_school_id, school_id, geography_id,
   year, year_date_id, form, contact_record_type,
   attendance_issues, received_financial_support, repeated,
   lin_is_current, lin_change_type,
   lin_source_system, lin_source_file, lin_load_batch_id)
SELECT
  dc.source_contact_id,
  dc.id,
  ds.source_school_id,
  ds.id,
  ds.geography_id,
  y.year::smallint,
  dd.id,
  'Form ' || (1 + ((dc.id + y.year) % 4)),
  CASE WHEN (dc.id % 7) = 0 THEN 'Step Up Fund Pupil' ELSE 'Bursary Pupil' END,
  (dc.id % 11) = 0,
  true,
  (dc.id % 13) = 0,
  true, 'INSERT',
  'Demo_Seed', 'demo-seed', 'demo-seed'
FROM rep_warehouse.dim_school ds
JOIN rep_warehouse.dim_contact dc
  ON dc.source_contact_id LIKE format('DEMO-CON-%s-pupil-%%', ds.id)
 AND dc.scd_is_current = true
CROSS JOIN generate_series(2020, 2026) AS y(year)
LEFT JOIN rep_warehouse.dim_date dd ON dd.id = (y.year::text || '0101')::integer
WHERE ds.source_school_id LIKE 'DEMO-SCH-%' AND ds.scd_is_current = true;

-- Guides: one assignment per guide contact ------------------------------------

INSERT INTO rep_warehouse.fact_guide_assignment
  (source_contact_id, contact_id, source_school_id, school_id, geography_id,
   date_joined_guide_programme, date_joined_id,
   guide_type, guide_status, guide_specialty, trained_in_climate_education,
   lin_is_current, lin_change_type,
   lin_source_system, lin_source_file, lin_load_batch_id)
SELECT
  dc.source_contact_id,
  dc.id,
  ds.source_school_id,
  ds.id,
  ds.geography_id,
  make_timestamp(2020 + (dc.id % 6), 1 + (dc.id % 12), 1 + (dc.id % 27), 9, 0, 0),
  ((2020 + (dc.id % 6))::text || '0101')::integer,
  CASE (dc.id % 3)
    WHEN 0 THEN 'Learner Guide'
    WHEN 1 THEN 'Transition Guide'
    ELSE        'Agriculture Guide'
  END,
  CASE WHEN (dc.id % 17) = 0 THEN 'Inactive' ELSE 'Active' END,
  CASE WHEN (dc.id % 5) = 0 THEN 'Climate Smart Agriculture' ELSE NULL END,
  (dc.id % 4) = 0,
  true, 'INSERT',
  'Demo_Seed', 'demo-seed', 'demo-seed'
FROM rep_warehouse.dim_school ds
JOIN rep_warehouse.dim_contact dc
  ON dc.source_contact_id LIKE format('DEMO-CON-%s-guide-%%', ds.id)
 AND dc.scd_is_current = true
WHERE ds.source_school_id LIKE 'DEMO-SCH-%' AND ds.scd_is_current = true;

-- CAMA membership -------------------------------------------------------------

INSERT INTO rep_warehouse.fact_cama_membership
  (source_contact_id, contact_id, source_school_id, school_id, geography_id,
   date_joined_cama, date_joined_id, partner_school,
   lin_is_current, lin_change_type,
   lin_source_system, lin_source_file, lin_load_batch_id)
SELECT
  dc.source_contact_id,
  dc.id,
  ds.source_school_id,
  ds.id,
  ds.geography_id,
  make_timestamp(2020 + (dc.id % 6), 1 + (dc.id % 12), 1 + (dc.id % 27), 9, 0, 0),
  ((2020 + (dc.id % 6))::text || '0101')::integer,
  true,
  true, 'INSERT',
  'Demo_Seed', 'demo-seed', 'demo-seed'
FROM rep_warehouse.dim_school ds
JOIN rep_warehouse.dim_contact dc
  ON dc.source_contact_id LIKE format('DEMO-CON-%s-cama-%%', ds.id)
 AND dc.scd_is_current = true
WHERE ds.source_school_id LIKE 'DEMO-SCH-%' AND ds.scd_is_current = true;

-- Post-school support ---------------------------------------------------------
-- A third of CAMA members, in the two most recent years.

INSERT INTO rep_warehouse.fact_post_school_support
  (source_contact_id, contact_id, geography_id, year, year_date_id,
   received_financial_support, accommodation, form,
   lin_is_current, lin_change_type,
   lin_source_system, lin_source_file, lin_load_batch_id)
SELECT
  dc.source_contact_id,
  dc.id,
  g.id,
  y.year::smallint,
  dd.id,
  true,
  CASE WHEN (dc.id % 2) = 0 THEN 'Boarding' ELSE 'Day' END,
  'Tertiary',
  true, 'INSERT',
  'Demo_Seed', 'demo-seed', 'demo-seed'
FROM rep_warehouse.dim_contact dc
JOIN rep_warehouse.dim_geography g
  ON g.country = dc.country AND g.district = dc.district_of_residence AND g.scd_is_current = true
CROSS JOIN generate_series(2025, 2026) AS y(year)
LEFT JOIN rep_warehouse.dim_date dd ON dd.id = (y.year::text || '0101')::integer
WHERE dc.source_contact_id LIKE 'DEMO-CON-%-cama-%'
  AND dc.scd_is_current = true
  AND (dc.id % 3) = 0;

-- Business grants -------------------------------------------------------------

INSERT INTO rep_warehouse.fact_grants
  (source_grant_id, source_contact_id, contact_id, geography_id,
   grant_type, grant_status, amount_given, grant_date, grant_date_id,
   lin_is_current, lin_change_type,
   lin_source_system, lin_source_file, lin_load_batch_id)
SELECT
  format('DEMO-GRANT-%s-%s', dc.id, y.year),
  dc.source_contact_id,
  dc.id,
  g.id,
  CASE WHEN (dc.id % 2) = 0 THEN 'Business Grant' ELSE 'Enterprise Grant' END,
  'Disbursed',
  200 + (dc.id % 9) * 50,
  make_timestamp(y.year, 1 + (dc.id % 12), 1 + (dc.id % 27), 9, 0, 0),
  (y.year::text || '0101')::integer,
  true, 'INSERT',
  'Demo_Seed', 'demo-seed', 'demo-seed'
FROM rep_warehouse.dim_contact dc
JOIN rep_warehouse.dim_geography g
  ON g.country = dc.country AND g.district = dc.district_of_residence AND g.scd_is_current = true
CROSS JOIN generate_series(2023, 2026) AS y(year)
WHERE dc.source_contact_id LIKE 'DEMO-CON-%-cama-%'
  AND dc.scd_is_current = true
  AND (dc.id % 4) = 0;

-- Loans -----------------------------------------------------------------------

INSERT INTO rep_warehouse.fact_loans
  (source_loan_id, geography_id, loan_type, status, loan_status,
   disbursal_date, disbursal_date_id, loan_value, currency_iso_code,
   contact_record_id,
   lin_is_current, lin_change_type,
   lin_source_system, lin_source_file, lin_load_batch_id)
SELECT
  format('DEMO-LOAN-%s-%s', dc.id, y.year),
  g.id,
  CASE WHEN (dc.id % 2) = 0 THEN 'KIVA' ELSE 'RIF' END,
  'Active',
  'Repaying',
  make_timestamp(y.year, 1 + (dc.id % 12), 1 + (dc.id % 27), 9, 0, 0),
  (y.year::text || '0101')::integer,
  300 + (dc.id % 7) * 75,
  'USD',
  dc.source_contact_id,
  true, 'INSERT',
  'Demo_Seed', 'demo-seed', 'demo-seed'
FROM rep_warehouse.dim_contact dc
JOIN rep_warehouse.dim_geography g
  ON g.country = dc.country AND g.district = dc.district_of_residence AND g.scd_is_current = true
CROSS JOIN generate_series(2023, 2026) AS y(year)
WHERE dc.source_contact_id LIKE 'DEMO-CON-%-cama-%'
  AND dc.scd_is_current = true
  AND (dc.id % 5) = 0;

COMMIT;

-- Rebuild the Dynamic Data aggregation from the freshly seeded facts.
-- This reads every metric_config row and can take a minute.
SELECT rep_portal.refresh_dashboard_data_agg();

-- Sanity check
SELECT 'children', COUNT(*) FROM rep_warehouse.fact_children_supported  WHERE lin_load_batch_id = 'demo-seed'
UNION ALL SELECT 'guides',      COUNT(*) FROM rep_warehouse.fact_guide_assignment    WHERE lin_load_batch_id = 'demo-seed'
UNION ALL SELECT 'cama',        COUNT(*) FROM rep_warehouse.fact_cama_membership     WHERE lin_load_batch_id = 'demo-seed'
UNION ALL SELECT 'post_school', COUNT(*) FROM rep_warehouse.fact_post_school_support WHERE lin_load_batch_id = 'demo-seed'
UNION ALL SELECT 'grants',      COUNT(*) FROM rep_warehouse.fact_grants              WHERE lin_load_batch_id = 'demo-seed'
UNION ALL SELECT 'loans',       COUNT(*) FROM rep_warehouse.fact_loans               WHERE lin_load_batch_id = 'demo-seed'
UNION ALL SELECT 'agg_rows',    COUNT(*) FROM rep_portal.dashboard_data_agg;
