-- ============================================================================
-- Demo seed 1/4 - dimensions
--
-- Run against the DEMO project only (gpyetojuzngrfrtcoycj), after `supabase db
-- push` has created the schema. Every row this file writes is fabricated and is
-- tagged lin_source_system = 'Demo_Seed' so it can be identified and removed.
--
-- Re-runnable: each INSERT is guarded by NOT EXISTS, so running the file twice
-- does not duplicate rows.
--
-- District names are the real geoBoundaries ADM2 shapeName values for each
-- country, because the map matches district rows to GeoJSON features by name --
-- invented names would leave the district layer uncoloured.
-- ============================================================================

BEGIN;

-- Countries ------------------------------------------------------------------
-- get_district_kpi_data() hardcodes this country list, so seeding others would
-- produce dashboard rows the map silently ignores.

INSERT INTO rep_warehouse.dim_geography
  (country, province, district, is_country,
   scd_effective_from, scd_is_current, scd_version,
   lin_source_system, lin_source_file, lin_load_batch_id)
SELECT v.country, NULL, NULL, true,
       DATE '2020-01-01', true, 1,
       'Demo_Seed', 'demo-seed', 'demo-seed'
FROM (VALUES ('Ghana'),('Malawi'),('Tanzania'),('Zambia'),('Zimbabwe')) v(country)
WHERE NOT EXISTS (
  SELECT 1 FROM rep_warehouse.dim_geography g
  WHERE g.country = v.country AND g.province IS NULL AND g.district IS NULL
);

-- Districts ------------------------------------------------------------------
-- Two or more provinces per country so the Dynamic Data province filter has
-- something to do; eight districts each.

INSERT INTO rep_warehouse.dim_geography
  (country, province, district, is_country,
   scd_effective_from, scd_is_current, scd_version,
   lin_source_system, lin_source_file, lin_load_batch_id)
SELECT v.country, v.province, v.district, false,
       DATE '2020-01-01', true, 1,
       'Demo_Seed', 'demo-seed', 'demo-seed'
FROM (VALUES
  ('Ghana','Greater Accra','Adenta Municipal'),
  ('Ghana','Greater Accra','Ledzokuku Municipal'),
  ('Ghana','Northern','Chereponi'),
  ('Ghana','Northern','Gushegu'),
  ('Ghana','Northern','Saboba'),
  ('Ghana','Upper West','Wa East'),
  ('Ghana','Upper West','Wa Municipal'),
  ('Ghana','Upper West','Jirapa'),
  ('Malawi','Southern','Balaka'),
  ('Malawi','Southern','Blantyre'),
  ('Malawi','Southern','Chikwawa'),
  ('Malawi','Southern','Chiradzulu'),
  ('Malawi','Northern','Chitipa'),
  ('Malawi','Northern','Karonga'),
  ('Malawi','Central','Dedza'),
  ('Malawi','Central','Dowa'),
  ('Tanzania','Arusha','Arusha'),
  ('Tanzania','Arusha','Arusha Urban'),
  ('Tanzania','Arusha','Karatu'),
  ('Tanzania','Arusha','Longido'),
  ('Tanzania','Arusha','Meru'),
  ('Tanzania','Arusha','Monduli'),
  ('Tanzania','Arusha','Ngorongoro'),
  ('Tanzania','Dar es Salaam','Ilala'),
  ('Zambia','Eastern','Chadiza'),
  ('Zambia','Eastern','Chasefu'),
  ('Zambia','Muchinga','Chama'),
  ('Zambia','North-Western','Chavuma'),
  ('Zambia','Luapula','Chembe'),
  ('Zambia','Luapula','Chiengi'),
  ('Zambia','Luapula','Chifunabuli'),
  ('Zambia','Central','Chibombo'),
  ('Zimbabwe','Matabeleland South','Beitbridge'),
  ('Zimbabwe','Matabeleland South','Beitbridge Urban'),
  ('Zimbabwe','Masvingo','Bikita'),
  ('Zimbabwe','Mashonaland Central','Bindura'),
  ('Zimbabwe','Mashonaland Central','Bindura Urban'),
  ('Zimbabwe','Matabeleland North','Binga'),
  ('Zimbabwe','Matabeleland North','Bubi'),
  ('Zimbabwe','Manicaland','Buhera')
) v(country, province, district)
WHERE NOT EXISTS (
  SELECT 1 FROM rep_warehouse.dim_geography g
  WHERE g.country = v.country AND g.district = v.district
);

-- KPI definitions ------------------------------------------------------------
-- Derived from rep_portal.kpi_mapping (seeded by migration) so that every KPI
-- the Data Dashboard asks for has a definition row to join to. kpi_group comes
-- from the dashboard page name, which is what the KPI Report groups by.

INSERT INTO rep_warehouse.dim_kpi
  (source_kpi_id, kpi_group, indicator,
   scd_effective_from, scd_is_current, scd_version,
   lin_source_system, lin_source_file, lin_load_batch_id)
SELECT DISTINCT ON (m.kpi_id)
       m.kpi_id,
       m.dashboard_page,
       m.data_element,
       DATE '2020-01-01', true, 1,
       'Demo_Seed', 'demo-seed', 'demo-seed'
FROM rep_portal.kpi_mapping m
WHERE NOT EXISTS (
  SELECT 1 FROM rep_warehouse.dim_kpi k
  WHERE k.source_kpi_id = m.kpi_id AND k.scd_is_current = true
)
ORDER BY m.kpi_id, m.dashlet_element;

-- Schools --------------------------------------------------------------------
-- Three per district. Coordinates are the country centroid plus a deterministic
-- offset, which spreads the map's school-point layer sensibly inside the right
-- country without pretending to be real locations.

INSERT INTO rep_warehouse.dim_school
  (source_school_id, school_name, geography_id, province, district, country,
   school_type, active_partner_school, latitude, longitude,
   scd_effective_from, scd_is_current, scd_version,
   lin_source_system, lin_source_file, lin_load_batch_id)
SELECT
  format('DEMO-SCH-%s-%s', g.id, s.n),
  format('%s Secondary School %s', g.district, s.n),
  g.id, g.province, g.district, g.country,
  CASE s.n WHEN 2 THEN 'Primary' ELSE 'Secondary' END,
  true,
  c.lat + ((g.id % 7) - 3) * 0.35 + s.n * 0.08,
  c.lon + ((g.id % 5) - 2) * 0.35 + s.n * 0.08,
  DATE '2020-01-01', true, 1,
  'Demo_Seed', 'demo-seed', 'demo-seed'
FROM rep_warehouse.dim_geography g
JOIN (VALUES
  ('Ghana', 7.9, -1.0), ('Malawi', -13.2, 34.3), ('Tanzania', -6.4, 34.9),
  ('Zambia', -13.1, 27.9), ('Zimbabwe', -19.0, 29.9)
) c(country, lat, lon) ON c.country = g.country
CROSS JOIN generate_series(1, 3) AS s(n)
WHERE g.district IS NOT NULL
  AND g.scd_is_current = true
  AND NOT EXISTS (
    SELECT 1 FROM rep_warehouse.dim_school ds
    WHERE ds.source_school_id = format('DEMO-SCH-%s-%s', g.id, s.n)
  );

-- Contacts -------------------------------------------------------------------
-- One pool per school: 12 pupils, 4 guides, 6 CAMA members. Gender and
-- wg_difficulty_overall matter because Dynamic Data metrics filter on them
-- (metric_config.filters), so the split here decides whether the "Girls",
-- "Boys" and "with Disability" metrics come back non-zero.

INSERT INTO rep_warehouse.dim_contact
  (source_contact_id, country, gender, wg_difficulty_overall, active_on_bursary,
   district_of_residence, birth_date,
   scd_effective_from, scd_is_current, scd_version,
   lin_source_system, lin_source_file, lin_load_batch_id)
SELECT
  format('DEMO-CON-%s-%s-%s', sch.id, p.role, p.n),
  sch.country,
  CASE WHEN p.role = 'pupil' AND p.n % 4 = 0 THEN 'Male' ELSE 'Female' END,
  CASE WHEN p.n % 9 = 0 THEN 'Some difficulty' ELSE NULL END,
  p.role = 'pupil',
  sch.district,
  DATE '2006-01-01' + ((sch.id * 7 + p.n) % 1200),
  DATE '2020-01-01', true, 1,
  'Demo_Seed', 'demo-seed', 'demo-seed'
FROM rep_warehouse.dim_school sch
CROSS JOIN LATERAL (
  SELECT 'pupil'::text AS role, gs.n FROM generate_series(1, 12) gs(n)
  UNION ALL
  SELECT 'guide', gs.n FROM generate_series(1, 4) gs(n)
  UNION ALL
  SELECT 'cama', gs.n FROM generate_series(1, 6) gs(n)
) p
WHERE sch.scd_is_current = true
  AND sch.source_school_id LIKE 'DEMO-SCH-%'
  AND NOT EXISTS (
    SELECT 1 FROM rep_warehouse.dim_contact dc
    WHERE dc.source_contact_id = format('DEMO-CON-%s-%s-%s', sch.id, p.role, p.n)
  );

COMMIT;

-- Sanity check
SELECT 'dim_geography' AS seeded_table, COUNT(*) FROM rep_warehouse.dim_geography WHERE lin_source_system = 'Demo_Seed'
UNION ALL SELECT 'dim_kpi',     COUNT(*) FROM rep_warehouse.dim_kpi     WHERE lin_source_system = 'Demo_Seed'
UNION ALL SELECT 'dim_school',  COUNT(*) FROM rep_warehouse.dim_school  WHERE lin_source_system = 'Demo_Seed'
UNION ALL SELECT 'dim_contact', COUNT(*) FROM rep_warehouse.dim_contact WHERE lin_source_system = 'Demo_Seed';
