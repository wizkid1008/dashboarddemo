-- Schema chunk 6 - run only after the previous chunk succeeded.
-- Generated from supabase/migrations in filename order. Do not reorder.


-- ===== 20260717175046_add_create_dashlet_rpc.sql =====
-- create_dashlet(): the only way a dashlet gets created. Inserts the
-- permissions row and the dashlets row (plus its metric wiring) together in
-- one call — if any part fails, the whole thing rolls back, so there is
-- never a state where a permission exists without its dashlet, or a dashlet
-- without its permission. Replaces the old flow where creating a permission
-- reactively spawned a dashlet_comments row via trigger.

CREATE OR REPLACE FUNCTION rep_portal.create_dashlet(
  p_key               TEXT,
  p_label             TEXT,
  p_description       TEXT,
  p_parent_key        TEXT,
  p_source_type       TEXT,
  p_group_id          INTEGER,
  p_chart_type        TEXT,
  p_display_mode      TEXT,
  p_comment           TEXT,
  p_comment_enabled   BOOLEAN,
  p_metric_config_ids INTEGER[],
  p_kpi_ids           TEXT[],
  p_updated_by        UUID
)
RETURNS rep_portal.dashlets
LANGUAGE plpgsql SECURITY DEFINER SET search_path = rep_portal, pg_temp AS $$
DECLARE
  v_dashlet rep_portal.dashlets;
BEGIN
  INSERT INTO rep_portal.permissions (key, label, description, category, parent_key)
  VALUES (p_key, p_label, p_description, 'dashlet', p_parent_key);

  INSERT INTO rep_portal.dashlets (
    permission_key, source_type, group_id, chart_type, display_mode,
    comment, comment_enabled, updated_by
  )
  VALUES (
    p_key, p_source_type, p_group_id, p_chart_type, p_display_mode,
    p_comment, p_comment_enabled, p_updated_by
  )
  RETURNING * INTO v_dashlet;

  -- Metric wiring, folded into the same atomic call rather than a follow-up
  -- step — only the array matching source_type is ever used, so a dashlet
  -- can never be created already wired to both kinds of metric.
  IF p_source_type = 'salesforce' THEN
    INSERT INTO rep_portal.permission_metric_map (permission_key, metric_id, metric_config_id)
    SELECT p_key, mc.metric_name, mc.id FROM rep_portal.metric_config mc WHERE mc.id = ANY(p_metric_config_ids);
  ELSIF p_source_type = 'kpi' THEN
    INSERT INTO rep_portal.permission_metric_map (permission_key, metric_id, metric_config_id)
    SELECT p_key, kid, NULL FROM unnest(p_kpi_ids) AS kid;
  END IF;

  RETURN v_dashlet;
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.create_dashlet(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, BOOLEAN, INTEGER[], TEXT[], UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.create_dashlet(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, BOOLEAN, INTEGER[], TEXT[], UUID) TO service_role;


-- ===== 20260717175113_update_dashlet_comment_rpcs_use_dashlets.sql =====
-- Retarget get_dashlet_comments()/set_dashlet_comment() from dashlet_comments
-- to dashlets (comment/comment_enabled columns, same shape). Return shape and
-- grants are unchanged — useDashletComments.ts/DashletCommentIcon.tsx need no
-- frontend changes.

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
  FROM rep_portal.dashlets
  WHERE comment_enabled = true
    AND comment IS NOT NULL;
$$;

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
    'source_type', d.source_type,
    'group_id', d.group_id,
    'chart_type', d.chart_type,
    'display_mode', d.display_mode,
    'metric_config_ids', COALESCE((
      SELECT jsonb_agg(m.metric_config_id) FROM rep_portal.permission_metric_map m
      WHERE m.permission_key = p.key AND m.metric_config_id IS NOT NULL
    ), '[]'::jsonb),
    'kpi_ids', COALESCE((
      SELECT jsonb_agg(m.metric_id) FROM rep_portal.permission_metric_map m
      WHERE m.permission_key = p.key AND m.metric_config_id IS NULL
    ), '[]'::jsonb),
    'comment', d.comment,
    'comment_enabled', d.comment_enabled
  )
  INTO v_snapshot
  FROM rep_portal.permissions p
  LEFT JOIN rep_portal.dashlets d ON d.permission_key = p.key
  WHERE p.key = p_permission_key;

  IF v_snapshot IS NOT NULL THEN
    INSERT INTO rep_portal.entity_history (entity_type, entity_key, change_type, snapshot, changed_by)
    VALUES ('dashlet', p_permission_key, 'update', v_snapshot, auth.uid());
  END IF;

  UPDATE rep_portal.dashlets
  SET comment         = p_comment,
      comment_enabled  = p_is_enabled,
      updated_by       = auth.uid()
  WHERE permission_key = p_permission_key;

  IF NOT FOUND THEN
    RAISE EXCEPTION 'unknown permission_key: %', p_permission_key;
  END IF;
END;
$$;


-- ===== 20260717175133_repoint_permission_metric_map_fk_to_dashlets.sql =====
-- Repoint permission_metric_map's FK from permissions(key) to
-- dashlets(permission_key) — metric wiring now genuinely "flows from" a
-- dashlet rather than sibling off the RBAC table. No query changes needed:
-- every existing join (pmm.permission_key = p.key) is unaffected, only which
-- table enforces referential integrity moves. Safe because every
-- category='dashlet' permission already has a dashlets row (backfilled in
-- the earlier migration this session).

ALTER TABLE rep_portal.permission_metric_map
  DROP CONSTRAINT permission_metric_map_permission_key_fkey,
  ADD CONSTRAINT permission_metric_map_permission_key_fkey
    FOREIGN KEY (permission_key) REFERENCES rep_portal.dashlets(permission_key) ON DELETE CASCADE;


-- ===== 20260717175159_add_kpi_dashboard_rpcs.sql =====
-- Phase 1: new "KPI Dashboard" page RPCs. No role/permission filtering, per
-- explicit decision this session — matches the existing KPI Trends/
-- Milestones RPCs, which have zero permission_metric_map involvement and are
-- gated only by "any authenticated user."

-- get_kpi_dashlets(): every KPI-type dashlet that's configured to appear on
-- the KPI Dashboard page (chart_type IS NOT NULL), grouped/ordered by
-- dashlet_groups.display_order — not permissions.parent_key, so this page's
-- sections can diverge from the RBAC role editor's grouping over time.
CREATE OR REPLACE FUNCTION rep_portal.get_kpi_dashlets()
RETURNS TABLE (
  permission_key      TEXT,
  label               TEXT,
  description         TEXT,
  group_id            INTEGER,
  group_name          TEXT,
  group_display_order INTEGER,
  chart_type          TEXT,
  display_mode        TEXT,
  kpi_ids             TEXT[]
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
  SELECT
    p.key,
    p.label,
    p.description,
    d.group_id,
    g.name,
    g.display_order,
    d.chart_type,
    d.display_mode,
    COALESCE(array_agg(pmm.metric_id) FILTER (WHERE pmm.metric_id IS NOT NULL), '{}')
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.permission_metric_map pmm ON pmm.permission_key = p.key
  LEFT JOIN rep_portal.dashlet_groups g ON g.id = d.group_id
  WHERE p.category = 'dashlet'
    AND d.source_type = 'kpi'
    AND d.chart_type IS NOT NULL
  GROUP BY p.key, p.label, p.description, d.group_id, g.name, g.display_order, d.chart_type, d.display_mode
  ORDER BY COALESCE(g.display_order, 999999), g.name NULLS LAST, p.label;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_kpi_dashlets() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_kpi_dashlets() TO authenticated;

-- get_kpi_dashlet_data(): raw view_observed_kpi rows for a batch of KPI
-- codes (as returned by get_kpi_dashlets() above) — no per-permission
-- filtering needed since get_kpi_dashlets() already has none. Fetched broad
-- (all countries/years for the given codes); aggregation happens client-side
-- so filters (group/country/year) can be applied without a re-fetch.
CREATE OR REPLACE FUNCTION rep_portal.get_kpi_dashlet_data(p_kpi_ids TEXT[])
RETURNS TABLE (
  source_kpi_id             TEXT,
  country                   TEXT,
  year                      INTEGER,
  disaggregation_level_one  TEXT,
  disaggregation_level_two  TEXT,
  value_type                TEXT,
  value                     TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_warehouse, rep_portal, public
AS $$
  SELECT kpi_id, country, year, disaggregation_level_one, disaggregation_level_two, value_type, value
  FROM (
    SELECT DISTINCT ON (kpi_id, country, year, disaggregation_level_one, disaggregation_level_two, value_type, value)
      kpi_id, country, year, disaggregation_level_one, disaggregation_level_two, value_type, value, lin_source_row_number
    FROM rep_warehouse.view_observed_kpi
    WHERE kpi_id = ANY(p_kpi_ids)
      AND row_scope IN ('ANNUAL', 'DETAIL')
      AND country IS NOT NULL
      AND year IS NOT NULL
    ORDER BY kpi_id, country, year, disaggregation_level_one, disaggregation_level_two, value_type, value, lin_source_row_number
  ) deduped
  ORDER BY kpi_id, country, year;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_kpi_dashlet_data(TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_kpi_dashlet_data(TEXT[]) TO authenticated;


-- ===== 20260718072530_remove_line_chart_type_from_dashlets.sql =====
-- Remove 'line' as a dashlet chart_type option. The KPI Dashboard page now
-- shows a single selected year per card (no year range), so a line chart
-- has nothing to draw a trend across — it rendered as a scatter of single
-- dots, functionally identical to 'bar' but with no line. Reclassify every
-- existing 'line' dashlet to 'bar' and tighten the CHECK constraint so
-- 'line' can't be picked again.

UPDATE rep_portal.dashlets SET chart_type = 'bar' WHERE chart_type = 'line';

ALTER TABLE rep_portal.dashlets DROP CONSTRAINT dashlets_chart_type_check;
ALTER TABLE rep_portal.dashlets ADD CONSTRAINT dashlets_chart_type_check
  CHECK (chart_type IN ('number', 'bar'));


-- ===== 20260718073219_fix_kpi_dashlet_data_row_cap_truncation.sql =====
-- get_kpi_dashlet_data() returned SETOF a row shape, which PostgREST caps at
-- its default max-rows (1000) for table/set-returning functions. The KPI
-- Dashboard's combined fetch across all wired KPI codes is ~2200 rows, so
-- codes sorting after row 1000 (e.g. 'P1', used by Total Boys/Girls
-- Supported) were silently dropped entirely — the cards showed "No data"
-- regardless of which year was selected, because they never received any
-- rows for that KPI code at all.
--
-- Fix: return one jsonb array instead of a row-set. PostgREST returns a
-- function's scalar/json return value as-is, with no row cap — only
-- SETOF/table results are capped.

DROP FUNCTION IF EXISTS rep_portal.get_kpi_dashlet_data(TEXT[]);

CREATE FUNCTION rep_portal.get_kpi_dashlet_data(p_kpi_ids TEXT[])
RETURNS jsonb
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_warehouse, rep_portal, public
AS $$
  SELECT COALESCE(jsonb_agg(row_to_json(final)), '[]'::jsonb)
  FROM (
    SELECT kpi_id AS source_kpi_id, country, year, disaggregation_level_one, disaggregation_level_two, value_type, value
    FROM (
      SELECT DISTINCT ON (kpi_id, country, year, disaggregation_level_one, disaggregation_level_two, value_type, value)
        kpi_id, country, year, disaggregation_level_one, disaggregation_level_two, value_type, value, lin_source_row_number
      FROM rep_warehouse.view_observed_kpi
      WHERE kpi_id = ANY(p_kpi_ids)
        AND row_scope IN ('ANNUAL', 'DETAIL')
        AND country IS NOT NULL
        AND year IS NOT NULL
      ORDER BY kpi_id, country, year, disaggregation_level_one, disaggregation_level_two, value_type, value, lin_source_row_number
    ) deduped
    ORDER BY kpi_id, country, year
  ) final;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_kpi_dashlet_data(TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_kpi_dashlet_data(TEXT[]) TO authenticated;


-- ===== 20260718074015_add_pie_table_chart_types.sql =====
-- Add 'pie' and 'table' as dashlet chart_type options — both are valid ways
-- to view single-year, one-value-per-country data alongside 'bar': 'pie' for
-- metrics that are genuinely a share of one total (e.g. Total Boys Supported
-- broken down by country), 'table' for exact figures / larger country
-- counts. They reuse the same aggregation as 'bar' (see aggregate.ts) — only
-- the rendering differs.

ALTER TABLE rep_portal.dashlets DROP CONSTRAINT dashlets_chart_type_check;
ALTER TABLE rep_portal.dashlets ADD CONSTRAINT dashlets_chart_type_check
  CHECK (chart_type IN ('number', 'bar', 'pie', 'table'));


-- ===== 20260718082328_add_horizontal_bar_chart_type.sql =====
-- Add 'horizontal_bar' as a dashlet chart_type option — same one-value-per-country
-- snapshot aggregation as 'bar' (see aggregate.ts), just rendered with
-- countries on the Y-axis instead of the X-axis.

ALTER TABLE rep_portal.dashlets DROP CONSTRAINT dashlets_chart_type_check;
ALTER TABLE rep_portal.dashlets ADD CONSTRAINT dashlets_chart_type_check
  CHECK (chart_type IN ('number', 'bar', 'horizontal_bar', 'pie', 'table'));


-- ===== 20260718093343_add_kpi_disaggregation_filters_to_metric_map.sql =====
-- Let a KPI-type dashlet filter which disaggregation slice of its metric it
-- sums, instead of blindly summing every row under the KPI code. This closes
-- two real accuracy gaps found in the KPI Dashboard: (1) row_scope alone
-- can't distinguish parallel ANNUAL series (e.g. P1's 'Annual' vs 'Newly
-- supported' — both classified ANNUAL by etl_run_staging(), both currently
-- summed together, double-counting); (2) there was no way to isolate a
-- slice (e.g. "boys only" across school levels).
--
-- Wiring stays in permission_metric_map (already the home for "how this
-- dashlet connects to its data source") rather than moving onto dashlets —
-- disagg filters are just more detail about that same connection. The
-- "one KPI code per dashlet" rule (confirmed: no dashlet today combines 2+
-- valid KPI codes) is enforced with a partial unique index, not a table
-- restructure.

ALTER TABLE rep_portal.permission_metric_map
  ADD COLUMN kpi_disagg1_filter   TEXT,
  ADD COLUMN kpi_disagg2_filters  TEXT[] NOT NULL DEFAULT '{}',
  ADD COLUMN kpi_split_mode       TEXT NOT NULL DEFAULT 'combine'
    CHECK (kpi_split_mode IN ('combine', 'split'));

-- Cleanup, inline: keep only the one real KPI-code row per 'kpi' dashlet,
-- delete dead legacy text references (e.g. 'Number of Clients by Form —
-- Boys') left over from before source_type existed. Audited: every 'kpi'
-- dashlet wired to 2+ metric_ids has exactly one that matches a real
-- dim_kpi.source_kpi_id.
DELETE FROM rep_portal.permission_metric_map pmm
USING rep_portal.dashlets d
WHERE pmm.permission_key = d.permission_key
  AND d.source_type = 'kpi'
  AND pmm.metric_config_id IS NULL
  AND NOT EXISTS (
    SELECT 1 FROM rep_warehouse.dim_kpi dk
    WHERE dk.source_kpi_id = pmm.metric_id AND dk.scd_is_current = true
  );

-- Same cleanup for dashlets reclassified to 'salesforce' earlier this
-- session (dead legacy text references from before source_type existed) —
-- a 'salesforce' dashlet should have zero metric_config_id IS NULL rows.
DELETE FROM rep_portal.permission_metric_map pmm
USING rep_portal.dashlets d
WHERE pmm.permission_key = d.permission_key
  AND d.source_type = 'salesforce'
  AND pmm.metric_config_id IS NULL;

-- Enforce "at most one KPI code per dashlet" at the DB level going forward.
CREATE UNIQUE INDEX permission_metric_map_one_kpi_per_dashlet
  ON rep_portal.permission_metric_map (permission_key)
  WHERE metric_config_id IS NULL;


-- ===== 20260718093420_update_create_dashlet_single_kpi_disagg.sql =====
-- create_dashlet(): KPI wiring is now a single kpi_id (not an array) plus a
-- disaggregation filter, matching the permission_metric_map schema change in
-- add_kpi_disaggregation_filters_to_metric_map.sql. The parameter list
-- changes (p_kpi_ids TEXT[] -> p_kpi_id TEXT + 3 new params), so this is a
-- new overload unless the old one is dropped first.

DROP FUNCTION IF EXISTS rep_portal.create_dashlet(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, BOOLEAN, INTEGER[], TEXT[], UUID);

CREATE FUNCTION rep_portal.create_dashlet(
  p_key                  TEXT,
  p_label                TEXT,
  p_description          TEXT,
  p_parent_key           TEXT,
  p_source_type          TEXT,
  p_group_id             INTEGER,
  p_chart_type           TEXT,
  p_display_mode         TEXT,
  p_comment              TEXT,
  p_comment_enabled      BOOLEAN,
  p_metric_config_ids    INTEGER[],
  p_kpi_id               TEXT,
  p_kpi_disagg1_filter   TEXT,
  p_kpi_disagg2_filters  TEXT[],
  p_kpi_split_mode       TEXT,
  p_updated_by           UUID
)
RETURNS rep_portal.dashlets
LANGUAGE plpgsql SECURITY DEFINER SET search_path = rep_portal, pg_temp AS $$
DECLARE
  v_dashlet rep_portal.dashlets;
BEGIN
  -- Both inserts happen inside this one function call — a single transaction from the
  -- caller's point of view. If either fails (duplicate key, bad FK, etc.) the whole
  -- call rolls back: there is no state where a permission exists without its dashlet,
  -- or a dashlet without its permission.
  INSERT INTO rep_portal.permissions (key, label, description, category, parent_key)
  VALUES (p_key, p_label, p_description, 'dashlet', p_parent_key);

  INSERT INTO rep_portal.dashlets (
    permission_key, source_type, group_id, chart_type, display_mode,
    comment, comment_enabled, updated_by
  )
  VALUES (
    p_key, p_source_type, p_group_id, p_chart_type, p_display_mode,
    p_comment, p_comment_enabled, p_updated_by
  )
  RETURNING * INTO v_dashlet;

  -- Metric wiring, folded into the same atomic call rather than a follow-up step —
  -- only the side matching source_type is ever used, so a dashlet can never be
  -- created already wired to both kinds of metric (same rule 0.5 enforces on edit).
  -- The permission_metric_map_one_kpi_per_dashlet unique index backstops the 'kpi'
  -- branch structurally: this INSERT can only ever produce at most one row.
  IF p_source_type = 'salesforce' THEN
    INSERT INTO rep_portal.permission_metric_map (permission_key, metric_id, metric_config_id)
    SELECT p_key, mc.metric_name, mc.id FROM rep_portal.metric_config mc WHERE mc.id = ANY(p_metric_config_ids);
  ELSIF p_source_type = 'kpi' AND p_kpi_id IS NOT NULL THEN
    INSERT INTO rep_portal.permission_metric_map (
      permission_key, metric_id, metric_config_id,
      kpi_disagg1_filter, kpi_disagg2_filters, kpi_split_mode
    )
    VALUES (
      p_key, p_kpi_id, NULL,
      p_kpi_disagg1_filter, COALESCE(p_kpi_disagg2_filters, '{}'), COALESCE(p_kpi_split_mode, 'combine')
    );
  END IF;

  RETURN v_dashlet;
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.create_dashlet(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, BOOLEAN, INTEGER[], TEXT, TEXT, TEXT[], TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.create_dashlet(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, BOOLEAN, INTEGER[], TEXT, TEXT, TEXT[], TEXT, UUID) TO service_role;


-- ===== 20260718093505_update_get_kpi_dashlets_single_kpi_disagg.sql =====
-- get_kpi_dashlets(): return a single kpi_id + its disaggregation filter
-- config instead of an array_agg'd kpi_ids — permission_metric_map now holds
-- at most one metric_config_id IS NULL row per dashlet (enforced by
-- permission_metric_map_one_kpi_per_dashlet), so no GROUP BY/array_agg is
-- needed for that side. Return type changes, so DROP first.

DROP FUNCTION IF EXISTS rep_portal.get_kpi_dashlets();

CREATE FUNCTION rep_portal.get_kpi_dashlets()
RETURNS TABLE (
  permission_key       TEXT,
  label                TEXT,
  description          TEXT,
  group_id             INTEGER,
  group_name           TEXT,
  group_display_order  INTEGER,
  chart_type           TEXT,
  display_mode         TEXT,
  kpi_id               TEXT,
  kpi_disagg1_filter   TEXT,
  kpi_disagg2_filters  TEXT[],
  kpi_split_mode       TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
  SELECT
    p.key,
    p.label,
    p.description,
    d.group_id,
    g.name,
    g.display_order,
    d.chart_type,
    d.display_mode,
    pmm.metric_id,
    pmm.kpi_disagg1_filter,
    pmm.kpi_disagg2_filters,
    pmm.kpi_split_mode
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.permission_metric_map pmm ON pmm.permission_key = p.key AND pmm.metric_config_id IS NULL
  LEFT JOIN rep_portal.dashlet_groups g ON g.id = d.group_id
  WHERE p.category = 'dashlet'
    AND d.source_type = 'kpi'
    AND d.chart_type IS NOT NULL
    AND pmm.metric_id IS NOT NULL
  ORDER BY COALESCE(g.display_order, 999999), g.name NULLS LAST, p.label;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_kpi_dashlets() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_kpi_dashlets() TO authenticated;


-- ===== 20260718093547_add_get_kpi_disaggregations_rpc.sql =====
-- get_kpi_disaggregations(): distinct disaggregation_level_one/_two pairs for
-- a KPI code, used by the admin Dashlets form to populate the disagg1/disagg2
-- pickers from real values instead of free text that might not match
-- anything. Admin-only — called through admin-users (service_role), not a
-- direct frontend RPC call.

CREATE FUNCTION rep_portal.get_kpi_disaggregations(p_kpi_id TEXT)
RETURNS TABLE (
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_warehouse, rep_portal, pg_temp
AS $$
  SELECT DISTINCT disaggregation_level_one, disaggregation_level_two
  FROM rep_warehouse.view_observed_kpi
  WHERE kpi_id = p_kpi_id AND row_scope IN ('ANNUAL', 'DETAIL')
  ORDER BY 1, 2;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_kpi_disaggregations(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_kpi_disaggregations(TEXT) TO service_role;


-- ===== 20260718114515_generalize_kpi_disagg1_to_multiselect.sql =====
-- Generalize kpi_disagg1_filter (single value) to kpi_disagg1_filters
-- (TEXT[]), symmetric with kpi_disagg2_filters. Found through use: which
-- physical column (disaggregation_level_one vs _two) holds the "split-worthy"
-- value vs the "scope filter" value is decided per-KPI by etl_run_staging()'s
-- unpivot and is inconsistent across the catalog — e.g. for KPI 1.9 ("Number
-- of Learner Guides"), disaggregation_level_one holds Government/CAMFED
-- trained (the split the admin wants) and disaggregation_level_two holds the
-- Annual/Cumulative/Newly-trained scope filter — backwards from P1, where
-- level_one held the scope. Since a dashlet's admin fields are hardwired to
-- specific physical columns, the only fix is letting both axes do the same
-- thing: a multi-select filter that can optionally become the split axis.

ALTER TABLE rep_portal.permission_metric_map
  ADD COLUMN kpi_disagg1_filters TEXT[] NOT NULL DEFAULT '{}';

-- Backfill: a single prior filter value becomes a one-element array; NULL (no
-- filter) becomes empty array — same "no filter" semantics disagg2 always had.
UPDATE rep_portal.permission_metric_map
SET kpi_disagg1_filters = ARRAY[kpi_disagg1_filter]
WHERE kpi_disagg1_filter IS NOT NULL;

ALTER TABLE rep_portal.permission_metric_map DROP COLUMN kpi_disagg1_filter;

-- A dashlet can split on at most one axis at a time — there's no card layout
-- for "grouped bars of grouped bars." If disagg1 is the split axis (2+
-- selected), disagg2 must be unfiltered (0) or narrowed to exactly one value
-- (never 2+) — and symmetrically if disagg2 is the split axis.
ALTER TABLE rep_portal.permission_metric_map
  ADD CONSTRAINT permission_metric_map_one_split_axis
  CHECK (NOT (array_length(kpi_disagg1_filters, 1) > 1 AND array_length(kpi_disagg2_filters, 1) > 1));


-- ===== 20260718114542_update_create_dashlet_disagg1_array.sql =====
-- create_dashlet(): p_kpi_disagg1_filter TEXT -> p_kpi_disagg1_filters TEXT[],
-- matching the permission_metric_map schema change in
-- generalize_kpi_disagg1_to_multiselect.sql. Signature changes, so drop first.

DROP FUNCTION IF EXISTS rep_portal.create_dashlet(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, BOOLEAN, INTEGER[], TEXT, TEXT, TEXT[], TEXT, UUID);

CREATE FUNCTION rep_portal.create_dashlet(
  p_key                  TEXT,
  p_label                TEXT,
  p_description          TEXT,
  p_parent_key           TEXT,
  p_source_type          TEXT,
  p_group_id             INTEGER,
  p_chart_type           TEXT,
  p_display_mode         TEXT,
  p_comment              TEXT,
  p_comment_enabled      BOOLEAN,
  p_metric_config_ids    INTEGER[],
  p_kpi_id               TEXT,
  p_kpi_disagg1_filters  TEXT[],
  p_kpi_disagg2_filters  TEXT[],
  p_kpi_split_mode       TEXT,
  p_updated_by           UUID
)
RETURNS rep_portal.dashlets
LANGUAGE plpgsql SECURITY DEFINER SET search_path = rep_portal, pg_temp AS $$
DECLARE
  v_dashlet rep_portal.dashlets;
BEGIN
  INSERT INTO rep_portal.permissions (key, label, description, category, parent_key)
  VALUES (p_key, p_label, p_description, 'dashlet', p_parent_key);

  INSERT INTO rep_portal.dashlets (
    permission_key, source_type, group_id, chart_type, display_mode,
    comment, comment_enabled, updated_by
  )
  VALUES (
    p_key, p_source_type, p_group_id, p_chart_type, p_display_mode,
    p_comment, p_comment_enabled, p_updated_by
  )
  RETURNING * INTO v_dashlet;

  IF p_source_type = 'salesforce' THEN
    INSERT INTO rep_portal.permission_metric_map (permission_key, metric_id, metric_config_id)
    SELECT p_key, mc.metric_name, mc.id FROM rep_portal.metric_config mc WHERE mc.id = ANY(p_metric_config_ids);
  ELSIF p_source_type = 'kpi' AND p_kpi_id IS NOT NULL THEN
    INSERT INTO rep_portal.permission_metric_map (
      permission_key, metric_id, metric_config_id,
      kpi_disagg1_filters, kpi_disagg2_filters, kpi_split_mode
    )
    VALUES (
      p_key, p_kpi_id, NULL,
      COALESCE(p_kpi_disagg1_filters, '{}'), COALESCE(p_kpi_disagg2_filters, '{}'), COALESCE(p_kpi_split_mode, 'combine')
    );
  END IF;

  RETURN v_dashlet;
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.create_dashlet(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, BOOLEAN, INTEGER[], TEXT, TEXT[], TEXT[], TEXT, UUID) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.create_dashlet(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, BOOLEAN, INTEGER[], TEXT, TEXT[], TEXT[], TEXT, UUID) TO service_role;


-- ===== 20260718114621_update_get_kpi_dashlets_disagg1_array.sql =====
-- get_kpi_dashlets(): kpi_disagg1_filter TEXT -> kpi_disagg1_filters TEXT[],
-- matching the permission_metric_map schema change. Return type changes, so
-- drop first.

DROP FUNCTION IF EXISTS rep_portal.get_kpi_dashlets();

CREATE FUNCTION rep_portal.get_kpi_dashlets()
RETURNS TABLE (
  permission_key       TEXT,
  label                TEXT,
  description          TEXT,
  group_id             INTEGER,
  group_name           TEXT,
  group_display_order  INTEGER,
  chart_type           TEXT,
  display_mode         TEXT,
  kpi_id               TEXT,
  kpi_disagg1_filters  TEXT[],
  kpi_disagg2_filters  TEXT[],
  kpi_split_mode       TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
  SELECT
    p.key,
    p.label,
    p.description,
    d.group_id,
    g.name,
    g.display_order,
    d.chart_type,
    d.display_mode,
    pmm.metric_id,
    pmm.kpi_disagg1_filters,
    pmm.kpi_disagg2_filters,
    pmm.kpi_split_mode
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.permission_metric_map pmm ON pmm.permission_key = p.key AND pmm.metric_config_id IS NULL
  LEFT JOIN rep_portal.dashlet_groups g ON g.id = d.group_id
  WHERE p.category = 'dashlet'
    AND d.source_type = 'kpi'
    AND d.chart_type IS NOT NULL
    AND pmm.metric_id IS NOT NULL
  ORDER BY COALESCE(g.display_order, 999999), g.name NULLS LAST, p.label;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_kpi_dashlets() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_kpi_dashlets() TO authenticated;


-- ===== 20260718142053_add_source_type_to_dashlet_groups.sql =====
-- Give dashlet_groups its own source_type, so a group belongs to exactly one
-- of 'kpi'/'salesforce' instead of being shared between both. Found through
-- use: get_kpi_dashlets() (source_type='kpi'-only) uses dashlet_groups.
-- display_order to order /kpi-dashboard sections, but any dashlet_groups row
-- could hold both kpi- and salesforce-type dashlets, so the display_order
-- sequence an admin edits on the Groups tab had unexplained gaps relative to
-- what actually rendered. Fix: tag each group by type; a dashlet may only
-- reference a group of its own source_type (enforced by trigger below).
--
-- Per explicit direction: nothing gets unlinked. Existing group->dashlet
-- links are preserved; only the two genuinely mixed groups (Education Reach,
-- Learner Guide Programme — both kept as 'kpi') have their Salesforce
-- dashlets reassigned to a real system group, not nulled out. Two such
-- system groups (_ungrouped_kpi, _ungrouped_salesforce) also become the
-- standing home for any dashlet with no group at all, replacing the ad-hoc
-- group_id IS NULL handling with a real row.

-- Groups are now scoped per source_type — two lists, not one shared
-- namespace, so the same name can validly exist once per list.
ALTER TABLE rep_portal.dashlet_groups DROP CONSTRAINT dashlet_groups_name_key;
ALTER TABLE rep_portal.dashlet_groups
  ADD COLUMN source_type TEXT NOT NULL DEFAULT 'kpi' CHECK (source_type IN ('kpi', 'salesforce')),
  ADD CONSTRAINT dashlet_groups_name_source_type_key UNIQUE (name, source_type);

-- Data-driven backfill: a group whose dashlets are ALL salesforce (and it has
-- at least one) is tagged 'salesforce'. Every other existing group — pure-kpi,
-- empty, or mixed (Education Reach, Learner Guide Programme) — keeps the
-- DEFAULT 'kpi', per explicit confirmation those two mixed groups are kpi.
UPDATE rep_portal.dashlet_groups g
SET source_type = 'salesforce'
WHERE EXISTS (SELECT 1 FROM rep_portal.dashlets d WHERE d.group_id = g.id AND d.source_type = 'salesforce')
  AND NOT EXISTS (SELECT 1 FROM rep_portal.dashlets d WHERE d.group_id = g.id AND d.source_type = 'kpi');

-- System groups — one per source_type, literally named _ungrouped_kpi /
-- _ungrouped_salesforce. Sort last by default (display_order 999999); an
-- admin can reposition them like any other group.
INSERT INTO rep_portal.dashlet_groups (name, source_type, display_order) VALUES
  ('_ungrouped_kpi', 'kpi', 999999),
  ('_ungrouped_salesforce', 'salesforce', 999999);

-- Move the Salesforce dashlets currently sitting in the two now-'kpi' mixed
-- groups into _ungrouped_salesforce — reassigned, not unlinked. The admin
-- can move them into a more fitting Salesforce group later via the Groups tab.
UPDATE rep_portal.dashlets d
SET group_id = (SELECT id FROM rep_portal.dashlet_groups WHERE name = '_ungrouped_salesforce')
WHERE d.source_type = 'salesforce'
  AND d.group_id IN (SELECT id FROM rep_portal.dashlet_groups WHERE name IN ('Education Reach', 'Learner Guide Programme'));

-- Any dashlet with no group at all lands in its type's system group.
UPDATE rep_portal.dashlets d
SET group_id = (SELECT id FROM rep_portal.dashlet_groups WHERE name = '_ungrouped_' || d.source_type)
WHERE d.group_id IS NULL;

-- Structural guarantee going forward: a dashlet's group_id must point at a
-- group of the same source_type. Enforced via trigger since a CHECK can't
-- reference another table.
CREATE OR REPLACE FUNCTION rep_portal.enforce_dashlet_group_source_type()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = rep_portal, pg_temp AS $$
BEGIN
  IF NEW.group_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM rep_portal.dashlet_groups g
    WHERE g.id = NEW.group_id AND g.source_type = NEW.source_type
  ) THEN
    RAISE EXCEPTION 'dashlet %: group_id % does not belong to a group of source_type %', NEW.permission_key, NEW.group_id, NEW.source_type;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER dashlets_enforce_group_source_type
  BEFORE INSERT OR UPDATE OF group_id, source_type ON rep_portal.dashlets
  FOR EACH ROW EXECUTE FUNCTION rep_portal.enforce_dashlet_group_source_type();


-- ===== 20260718155617_add_show_milestone_to_permission_metric_map.sql =====
-- Let a KPI-type dashlet opt into showing its milestone/target value
-- (rep_warehouse.fact_kpi_milestone, already populated via the separate KPI
-- Milestones upload flow) alongside its actual value on the KPI Dashboard.
-- Wiring stays in permission_metric_map, same home as kpi_disagg1_filters/
-- kpi_disagg2_filters/kpi_split_mode — "more detail about how this dashlet
-- connects to its data". No DB-level CHECK tying this to chart_type (mirrors
-- kpi_split_mode, whose bar/horizontal_bar/table-only validity is enforced
-- only in the admin-users edge function, not the DB).

ALTER TABLE rep_portal.permission_metric_map
  ADD COLUMN show_milestone BOOLEAN NOT NULL DEFAULT false;


-- ===== 20260718155639_add_get_kpi_dashlet_milestones_rpc.sql =====
-- get_kpi_dashlet_milestones(): milestone rows (rep_warehouse.fact_kpi_
-- milestone) for a batch of KPI codes, for KPI Dashboard dashlets with
-- show_milestone = true. Same single-layer shape as get_kpi_dashlet_data()
-- (rep_portal function reading rep_warehouse directly) — fetched broad (all
-- countries/years for the given codes), aggregation happens client-side.
--
-- No dedup/rollup logic here, unlike kpi_milestone_report()'s "Total"
-- rollup — that reconciles milestone rows against *actual* rows for the
-- separate KPI Milestones page. This RPC only returns the milestone rows
-- themselves; combining them with actuals happens client-side in
-- aggregateMilestone() alongside aggregateDashlet()'s existing disagg
-- filtering.
CREATE OR REPLACE FUNCTION rep_portal.get_kpi_dashlet_milestones(p_kpi_ids TEXT[])
RETURNS TABLE (
  source_kpi_id             TEXT,
  country                   TEXT,
  year                      INTEGER,
  disaggregation_level_one  TEXT,
  disaggregation_level_two  TEXT,
  value                     NUMERIC,
  value_type                TEXT
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_warehouse, rep_portal, public
AS $$
  SELECT k.source_kpi_id, g.country, m.year,
    m.disaggregation_level_one, m.disaggregation_level_two, m.value, m.value_type
  FROM rep_warehouse.fact_kpi_milestone m
  JOIN rep_warehouse.dim_kpi k ON k.id = m.kpi_id AND k.scd_is_current = true
  JOIN rep_warehouse.dim_geography g ON g.id = m.geography_id AND g.scd_is_current = true
  WHERE k.source_kpi_id = ANY(p_kpi_ids)
  ORDER BY k.source_kpi_id, g.country, m.year;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_kpi_dashlet_milestones(TEXT[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_kpi_dashlet_milestones(TEXT[]) TO authenticated;


-- ===== 20260718155705_update_get_kpi_dashlets_show_milestone.sql =====
-- get_kpi_dashlets(): return show_milestone alongside the existing disagg/
-- split_mode wiring, so the KPI Dashboard page knows which dashlets should
-- fetch and render a milestone overlay/value. Return type changes, so DROP
-- first (same pattern as the disagg1-multiselect migration).

DROP FUNCTION IF EXISTS rep_portal.get_kpi_dashlets();

CREATE FUNCTION rep_portal.get_kpi_dashlets()
RETURNS TABLE (
  permission_key       TEXT,
  label                TEXT,
  description          TEXT,
  group_id             INTEGER,
  group_name           TEXT,
  group_display_order  INTEGER,
  chart_type           TEXT,
  display_mode         TEXT,
  kpi_id               TEXT,
  kpi_disagg1_filters  TEXT[],
  kpi_disagg2_filters  TEXT[],
  kpi_split_mode       TEXT,
  show_milestone       BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
  SELECT
    p.key,
    p.label,
    p.description,
    d.group_id,
    g.name,
    g.display_order,
    d.chart_type,
    d.display_mode,
    pmm.metric_id,
    pmm.kpi_disagg1_filters,
    pmm.kpi_disagg2_filters,
    pmm.kpi_split_mode,
    pmm.show_milestone
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.permission_metric_map pmm ON pmm.permission_key = p.key AND pmm.metric_config_id IS NULL
  LEFT JOIN rep_portal.dashlet_groups g ON g.id = d.group_id
  WHERE p.category = 'dashlet'
    AND d.source_type = 'kpi'
    AND d.chart_type IS NOT NULL
    AND pmm.metric_id IS NOT NULL
  ORDER BY COALESCE(g.display_order, 999999), g.name NULLS LAST, p.label;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_kpi_dashlets() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_kpi_dashlets() TO authenticated;


-- ===== 20260718155707_update_create_dashlet_show_milestone.sql =====
-- create_dashlet(): add p_show_milestone so a new KPI dashlet can opt into
-- milestone rendering at creation time, not just on later edit. Signature
-- changes, so drop first.

DROP FUNCTION IF EXISTS rep_portal.create_dashlet(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, BOOLEAN, INTEGER[], TEXT, TEXT[], TEXT[], TEXT, UUID);

CREATE FUNCTION rep_portal.create_dashlet(
  p_key                  TEXT,
  p_label                TEXT,
  p_description          TEXT,
  p_parent_key           TEXT,
  p_source_type          TEXT,
  p_group_id             INTEGER,
  p_chart_type           TEXT,
  p_display_mode         TEXT,
  p_comment              TEXT,
  p_comment_enabled      BOOLEAN,
  p_metric_config_ids    INTEGER[],
  p_kpi_id               TEXT,
  p_kpi_disagg1_filters  TEXT[],
  p_kpi_disagg2_filters  TEXT[],
  p_kpi_split_mode       TEXT,
  p_updated_by           UUID,
  p_show_milestone       BOOLEAN DEFAULT false
)
RETURNS rep_portal.dashlets
LANGUAGE plpgsql SECURITY DEFINER SET search_path = rep_portal, pg_temp AS $$
DECLARE
  v_dashlet rep_portal.dashlets;
BEGIN
  INSERT INTO rep_portal.permissions (key, label, description, category, parent_key)
  VALUES (p_key, p_label, p_description, 'dashlet', p_parent_key);

  INSERT INTO rep_portal.dashlets (
    permission_key, source_type, group_id, chart_type, display_mode,
    comment, comment_enabled, updated_by
  )
  VALUES (
    p_key, p_source_type, p_group_id, p_chart_type, p_display_mode,
    p_comment, p_comment_enabled, p_updated_by
  )
  RETURNING * INTO v_dashlet;

  IF p_source_type = 'salesforce' THEN
    INSERT INTO rep_portal.permission_metric_map (permission_key, metric_id, metric_config_id)
    SELECT p_key, mc.metric_name, mc.id FROM rep_portal.metric_config mc WHERE mc.id = ANY(p_metric_config_ids);
  ELSIF p_source_type = 'kpi' AND p_kpi_id IS NOT NULL THEN
    INSERT INTO rep_portal.permission_metric_map (
      permission_key, metric_id, metric_config_id,
      kpi_disagg1_filters, kpi_disagg2_filters, kpi_split_mode, show_milestone
    )
    VALUES (
      p_key, p_kpi_id, NULL,
      COALESCE(p_kpi_disagg1_filters, '{}'), COALESCE(p_kpi_disagg2_filters, '{}'), COALESCE(p_kpi_split_mode, 'combine'),
      COALESCE(p_show_milestone, false)
    );
  END IF;

  RETURN v_dashlet;
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.create_dashlet(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, BOOLEAN, INTEGER[], TEXT, TEXT[], TEXT[], TEXT, UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.create_dashlet(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, BOOLEAN, INTEGER[], TEXT, TEXT[], TEXT[], TEXT, UUID, BOOLEAN) TO service_role;


-- ===== 20260719062538_add_dashlet_status_and_drafts.sql =====
-- Draft / publish workflow for dashlets. Editing an already-published dashlet
-- must not change what the public dashboard shows until the edit is
-- explicitly published — so this can't be a simple in-place status flag on
-- the live row (that would make edits go live immediately). Instead: a
-- separate staging table mirrors the live row's editable fields, and
-- "Publish" is the action that copies the draft over the live row.
--
-- Applies uniformly to both dashlet source types (kpi + salesforce) — see
-- admin-users edge function changes for the write-path branching logic.

ALTER TABLE rep_portal.dashlets
  ADD COLUMN status TEXT NOT NULL DEFAULT 'draft' CHECK (status IN ('draft', 'published'));

-- Everything currently live (has a chart type, i.e. already shown on the KPI
-- Dashboard) stays live — this migration must not un-publish anything.
UPDATE rep_portal.dashlets SET status = 'published' WHERE chart_type IS NOT NULL;

-- Staging copy for edits made to an already-published dashlet. Mirrors
-- exactly the fields getDashletSnapshot() (admin-users/index.ts) already
-- assembles — permissions + dashlets + its one permission_metric_map row —
-- one row per dashlet with a pending, unpublished edit. Absence of a row
-- means "no pending changes."
CREATE TABLE rep_portal.dashlet_drafts (
  permission_key       TEXT PRIMARY KEY REFERENCES rep_portal.dashlets(permission_key) ON DELETE CASCADE,
  label                TEXT NOT NULL,
  description          TEXT,
  parent_key           TEXT,
  source_type          TEXT NOT NULL,
  group_id             INTEGER,
  chart_type           TEXT,
  display_mode         TEXT,
  comment              TEXT,
  comment_enabled      BOOLEAN NOT NULL DEFAULT false,
  metric_config_ids    INTEGER[] NOT NULL DEFAULT '{}',
  kpi_id               TEXT,
  kpi_disagg1_filters  TEXT[] NOT NULL DEFAULT '{}',
  kpi_disagg2_filters  TEXT[] NOT NULL DEFAULT '{}',
  kpi_split_mode       TEXT,
  show_milestone       BOOLEAN NOT NULL DEFAULT false,
  updated_by           UUID,
  updated_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  created_at           TIMESTAMPTZ NOT NULL DEFAULT now(),
  CONSTRAINT dashlet_drafts_group_id_fkey FOREIGN KEY (group_id)
    REFERENCES rep_portal.dashlet_groups(id) ON DELETE SET NULL
);

ALTER TABLE rep_portal.dashlet_drafts ENABLE ROW LEVEL SECURITY;
-- No policies — default deny, same as every other rep_portal table. Access
-- exclusively through the admin-users edge function (service_role).

CREATE TRIGGER dashlet_drafts_updated_at
  BEFORE UPDATE ON rep_portal.dashlet_drafts
  FOR EACH ROW EXECUTE FUNCTION rep_portal.set_updated_at();

GRANT ALL ON rep_portal.dashlet_drafts TO service_role;


-- ===== 20260719062620_update_get_kpi_dashlets_status_filter.sql =====
-- get_kpi_dashlets(): only return dashlets whose live row is published. This
-- is the entire public-visibility gate for the draft/publish workflow — the
-- function keeps reading only the live dashlets/permissions/
-- permission_metric_map rows (never dashlet_drafts), so a pending edit to a
-- published dashlet has zero effect on the public KPI Dashboard until it's
-- explicitly published. Return type unchanged, so no DROP needed.

CREATE OR REPLACE FUNCTION rep_portal.get_kpi_dashlets()
RETURNS TABLE (
  permission_key       TEXT,
  label                TEXT,
  description          TEXT,
  group_id             INTEGER,
  group_name           TEXT,
  group_display_order  INTEGER,
  chart_type           TEXT,
  display_mode         TEXT,
  kpi_id               TEXT,
  kpi_disagg1_filters  TEXT[],
  kpi_disagg2_filters  TEXT[],
  kpi_split_mode       TEXT,
  show_milestone       BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
  SELECT
    p.key,
    p.label,
    p.description,
    d.group_id,
    g.name,
    g.display_order,
    d.chart_type,
    d.display_mode,
    pmm.metric_id,
    pmm.kpi_disagg1_filters,
    pmm.kpi_disagg2_filters,
    pmm.kpi_split_mode,
    pmm.show_milestone
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.permission_metric_map pmm ON pmm.permission_key = p.key AND pmm.metric_config_id IS NULL
  LEFT JOIN rep_portal.dashlet_groups g ON g.id = d.group_id
  WHERE p.category = 'dashlet'
    AND d.source_type = 'kpi'
    AND d.chart_type IS NOT NULL
    AND d.status = 'published'
    AND pmm.metric_id IS NOT NULL
  ORDER BY COALESCE(g.display_order, 999999), g.name NULLS LAST, p.label;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_kpi_dashlets() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_kpi_dashlets() TO authenticated;


-- ===== 20260719062625_add_get_kpi_dashlets_admin.sql =====
-- get_kpi_dashlets_admin(): admin-only preview of the KPI Dashboard —
-- returns every KPI dashlet regardless of status, with any pending
-- dashlet_drafts row merged over its live fields, so an admin previewing
-- sees exactly what publishing would produce. Also returns status and
-- has_pending_draft so the UI can badge draft / published / "unpublished
-- changes". Mirrors get_kpi_dashlets()'s shape plus those two extra columns.

CREATE FUNCTION rep_portal.get_kpi_dashlets_admin()
RETURNS TABLE (
  permission_key       TEXT,
  label                TEXT,
  description          TEXT,
  group_id             INTEGER,
  group_name           TEXT,
  group_display_order  INTEGER,
  chart_type           TEXT,
  display_mode         TEXT,
  kpi_id               TEXT,
  kpi_disagg1_filters  TEXT[],
  kpi_disagg2_filters  TEXT[],
  kpi_split_mode       TEXT,
  show_milestone       BOOLEAN,
  status               TEXT,
  has_pending_draft    BOOLEAN
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
  SELECT
    p.key,
    COALESCE(dr.label, p.label),
    COALESCE(dr.description, p.description),
    COALESCE(dr.group_id, d.group_id),
    g.name,
    g.display_order,
    COALESCE(dr.chart_type, d.chart_type),
    COALESCE(dr.display_mode, d.display_mode),
    COALESCE(dr.kpi_id, pmm.metric_id),
    COALESCE(dr.kpi_disagg1_filters, pmm.kpi_disagg1_filters),
    COALESCE(dr.kpi_disagg2_filters, pmm.kpi_disagg2_filters),
    COALESCE(dr.kpi_split_mode, pmm.kpi_split_mode),
    COALESCE(dr.show_milestone, pmm.show_milestone),
    d.status,
    (dr.permission_key IS NOT NULL)
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.dashlet_drafts dr ON dr.permission_key = p.key
  LEFT JOIN rep_portal.permission_metric_map pmm ON pmm.permission_key = p.key AND pmm.metric_config_id IS NULL
  LEFT JOIN rep_portal.dashlet_groups g ON g.id = COALESCE(dr.group_id, d.group_id)
  WHERE p.category = 'dashlet'
    AND COALESCE(dr.source_type, d.source_type) = 'kpi'
    AND COALESCE(dr.chart_type, d.chart_type) IS NOT NULL
    AND COALESCE(dr.kpi_id, pmm.metric_id) IS NOT NULL
  ORDER BY COALESCE(g.display_order, 999999), g.name NULLS LAST, COALESCE(dr.label, p.label);
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_kpi_dashlets_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_kpi_dashlets_admin() TO authenticated;


-- ===== 20260719062751_update_dashlet_comment_rpcs_status_staging.sql =====
-- get_dashlet_comments(): only surface a published dashlet's comment — a
-- staged (unpublished) comment edit made through DashletForm must not show
-- on either dashboard until Publish, consistent with get_kpi_dashlets().
--
-- set_dashlet_comment(): this RPC isn't currently called from the frontend
-- (DashletCommentIcon.tsx is read-only; comment edits go through the main
-- DashletForm -> dashlet-save, already staged by the admin-users edge
-- function). Closing it defensively so it can't become a silent bypass of
-- staging if anything calls it directly in the future: give it the same
-- live-status branch as dashlet-save.

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
  FROM rep_portal.dashlets
  WHERE comment_enabled = true
    AND comment IS NOT NULL
    AND status = 'published';
$$;

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
  v_dashlet  rep_portal.dashlets;
  v_perm     rep_portal.permissions;
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  SELECT * INTO v_dashlet FROM rep_portal.dashlets WHERE permission_key = p_permission_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unknown permission_key: %', p_permission_key;
  END IF;
  SELECT * INTO v_perm FROM rep_portal.permissions WHERE key = p_permission_key;

  SELECT jsonb_build_object(
    'key', v_perm.key,
    'label', v_perm.label,
    'description', v_perm.description,
    'parent_key', v_perm.parent_key,
    'source_type', v_dashlet.source_type,
    'group_id', v_dashlet.group_id,
    'chart_type', v_dashlet.chart_type,
    'display_mode', v_dashlet.display_mode,
    'metric_config_ids', COALESCE((
      SELECT jsonb_agg(m.metric_config_id) FROM rep_portal.permission_metric_map m
      WHERE m.permission_key = p_permission_key AND m.metric_config_id IS NOT NULL
    ), '[]'::jsonb),
    'kpi_ids', COALESCE((
      SELECT jsonb_agg(m.metric_id) FROM rep_portal.permission_metric_map m
      WHERE m.permission_key = p_permission_key AND m.metric_config_id IS NULL
    ), '[]'::jsonb),
    'comment', p_comment,
    'comment_enabled', p_is_enabled
  ) INTO v_snapshot;

  INSERT INTO rep_portal.entity_history (entity_type, entity_key, change_type, snapshot, changed_by)
  VALUES ('dashlet', p_permission_key, 'update', v_snapshot, auth.uid());

  IF v_dashlet.status = 'published' THEN
    -- Stage just the comment fields into dashlet_drafts. If a draft row
    -- already exists (an in-progress config edit from the main form), only
    -- the comment columns are touched — the rest of that pending edit is
    -- left intact. If no draft row exists yet, seed every other column from
    -- the current live values so the row is never partially populated.
    INSERT INTO rep_portal.dashlet_drafts (
      permission_key, label, description, parent_key, source_type, group_id,
      chart_type, display_mode, comment, comment_enabled, metric_config_ids,
      kpi_id, kpi_disagg1_filters, kpi_disagg2_filters, kpi_split_mode, show_milestone,
      updated_by
    )
    SELECT
      p_permission_key, v_perm.label, v_perm.description, v_perm.parent_key, v_dashlet.source_type, v_dashlet.group_id,
      v_dashlet.chart_type, v_dashlet.display_mode, p_comment, p_is_enabled,
      COALESCE((
        SELECT array_agg(m.metric_config_id) FROM rep_portal.permission_metric_map m
        WHERE m.permission_key = p_permission_key AND m.metric_config_id IS NOT NULL
      ), '{}'),
      (SELECT m.metric_id FROM rep_portal.permission_metric_map m WHERE m.permission_key = p_permission_key AND m.metric_config_id IS NULL LIMIT 1),
      COALESCE((SELECT m.kpi_disagg1_filters FROM rep_portal.permission_metric_map m WHERE m.permission_key = p_permission_key AND m.metric_config_id IS NULL LIMIT 1), '{}'),
      COALESCE((SELECT m.kpi_disagg2_filters FROM rep_portal.permission_metric_map m WHERE m.permission_key = p_permission_key AND m.metric_config_id IS NULL LIMIT 1), '{}'),
      (SELECT m.kpi_split_mode FROM rep_portal.permission_metric_map m WHERE m.permission_key = p_permission_key AND m.metric_config_id IS NULL LIMIT 1),
      COALESCE((SELECT m.show_milestone FROM rep_portal.permission_metric_map m WHERE m.permission_key = p_permission_key AND m.metric_config_id IS NULL LIMIT 1), false),
      auth.uid()
    ON CONFLICT (permission_key) DO UPDATE
      SET comment         = EXCLUDED.comment,
          comment_enabled = EXCLUDED.comment_enabled,
          updated_by      = EXCLUDED.updated_by;
  ELSE
    UPDATE rep_portal.dashlets
    SET comment         = p_comment,
        comment_enabled = p_is_enabled,
        updated_by      = auth.uid()
    WHERE permission_key = p_permission_key;
  END IF;
END;
$$;


-- ===== 20260719072223_update_get_kpi_dashlets_admin_include_comment.sql =====
-- get_kpi_dashlets_admin(): the comment tooltip (DashletCommentIcon) is fed
-- by a separate, non-preview-aware query — get_dashlet_comments(), which
-- only ever reads the live/published comment, regardless of the KPI
-- Dashboard's ?preview=1 mode. That meant a staged comment edit never showed
-- up anywhere, even in preview. Fix: return the merged (draft-over-live)
-- comment/comment_enabled here too, so the frontend can override the
-- tooltip's normal live-only lookup specifically in preview mode. Return
-- type changes, so DROP first.

DROP FUNCTION IF EXISTS rep_portal.get_kpi_dashlets_admin();

CREATE FUNCTION rep_portal.get_kpi_dashlets_admin()
RETURNS TABLE (
  permission_key       TEXT,
  label                TEXT,
  description          TEXT,
  group_id             INTEGER,
  group_name           TEXT,
  group_display_order  INTEGER,
  chart_type           TEXT,
  display_mode         TEXT,
  kpi_id               TEXT,
  kpi_disagg1_filters  TEXT[],
  kpi_disagg2_filters  TEXT[],
  kpi_split_mode       TEXT,
  show_milestone       BOOLEAN,
  status               TEXT,
  has_pending_draft    BOOLEAN,
  comment              TEXT,
  comment_enabled      BOOLEAN
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
  SELECT
    p.key,
    COALESCE(dr.label, p.label),
    COALESCE(dr.description, p.description),
    COALESCE(dr.group_id, d.group_id),
    g.name,
    g.display_order,
    COALESCE(dr.chart_type, d.chart_type),
    COALESCE(dr.display_mode, d.display_mode),
    COALESCE(dr.kpi_id, pmm.metric_id),
    COALESCE(dr.kpi_disagg1_filters, pmm.kpi_disagg1_filters),
    COALESCE(dr.kpi_disagg2_filters, pmm.kpi_disagg2_filters),
    COALESCE(dr.kpi_split_mode, pmm.kpi_split_mode),
    COALESCE(dr.show_milestone, pmm.show_milestone),
    d.status,
    (dr.permission_key IS NOT NULL),
    COALESCE(dr.comment, d.comment),
    COALESCE(dr.comment_enabled, d.comment_enabled)
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.dashlet_drafts dr ON dr.permission_key = p.key
  LEFT JOIN rep_portal.permission_metric_map pmm ON pmm.permission_key = p.key AND pmm.metric_config_id IS NULL
  LEFT JOIN rep_portal.dashlet_groups g ON g.id = COALESCE(dr.group_id, d.group_id)
  WHERE p.category = 'dashlet'
    AND COALESCE(dr.source_type, d.source_type) = 'kpi'
    AND COALESCE(dr.chart_type, d.chart_type) IS NOT NULL
    AND COALESCE(dr.kpi_id, pmm.metric_id) IS NOT NULL
  ORDER BY COALESCE(g.display_order, 999999), g.name NULLS LAST, COALESCE(dr.label, p.label);
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_kpi_dashlets_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_kpi_dashlets_admin() TO authenticated;


-- ===== 20260719125012_add_get_salesforce_dashlets_rpcs.sql =====
-- get_salesforce_dashlets() / get_salesforce_dashlets_admin(): the Salesforce
-- Dashboard equivalent of get_kpi_dashlets()/_admin(). Every dashlet always
-- has a real group_id (system groups _ungrouped_kpi/_ungrouped_salesforce
-- exist for the "no group chosen" case — see 20260718142053), so ungrouped
-- dashlets are excluded outright rather than falling back to a client-side
-- "Ungrouped" label (matches the same exclusion now applied to
-- get_kpi_dashlets()/_admin(), see the companion migration in this batch).
--
-- A Salesforce dashlet can be wired to 2+ metric_config rows (unlike a KPI
-- dashlet's single kpi_id) — metric_config_ids/metric_names are returned as
-- parallel arrays, order-aligned, for the frontend to render as multi-series.

CREATE OR REPLACE FUNCTION rep_portal.get_salesforce_dashlets()
RETURNS TABLE (
  permission_key       TEXT,
  label                TEXT,
  description          TEXT,
  group_id             INTEGER,
  group_name           TEXT,
  group_display_order  INTEGER,
  chart_type           TEXT,
  metric_config_ids    INTEGER[],
  metric_names         TEXT[]
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
  SELECT
    p.key,
    p.label,
    p.description,
    d.group_id,
    g.name,
    g.display_order,
    d.chart_type,
    mm.metric_config_ids,
    mm.metric_names
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  JOIN rep_portal.dashlet_groups g ON g.id = d.group_id
  JOIN LATERAL (
    SELECT
      array_agg(mc.id ORDER BY mc.sort_order NULLS LAST, mc.id)          AS metric_config_ids,
      array_agg(mc.metric_name ORDER BY mc.sort_order NULLS LAST, mc.id) AS metric_names
    FROM rep_portal.permission_metric_map pmm
    JOIN rep_portal.metric_config mc ON mc.id = pmm.metric_config_id
    WHERE pmm.permission_key = p.key AND pmm.metric_config_id IS NOT NULL
  ) mm ON true
  WHERE p.category = 'dashlet'
    AND d.source_type = 'salesforce'
    AND d.status = 'published'
    AND d.chart_type IS NOT NULL
    AND g.name <> '_ungrouped_salesforce'
    AND mm.metric_config_ids IS NOT NULL
  ORDER BY COALESCE(g.display_order, 999999), g.name, p.label;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_salesforce_dashlets() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_salesforce_dashlets() TO authenticated;

-- get_salesforce_dashlets_admin(): admin-only preview — every Salesforce
-- dashlet regardless of status, with any pending dashlet_drafts row merged
-- over its live fields (mirrors get_kpi_dashlets_admin()). A draft's
-- metric_config_ids is a full snapshot when present (getDashletSnapshot()
-- on the admin-users edge function always populates it, never a partial
-- diff), so has_pending_draft alone decides which array to use — not a
-- COALESCE on the array itself, since an intentionally-emptied draft
-- ('{}') must not silently fall back to the live set.
CREATE OR REPLACE FUNCTION rep_portal.get_salesforce_dashlets_admin()
RETURNS TABLE (
  permission_key       TEXT,
  label                TEXT,
  description          TEXT,
  group_id             INTEGER,
  group_name           TEXT,
  group_display_order  INTEGER,
  chart_type           TEXT,
  metric_config_ids    INTEGER[],
  metric_names         TEXT[],
  status               TEXT,
  has_pending_draft    BOOLEAN,
  comment              TEXT,
  comment_enabled      BOOLEAN
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
  SELECT
    p.key,
    COALESCE(dr.label, p.label),
    COALESCE(dr.description, p.description),
    COALESCE(dr.group_id, d.group_id),
    g.name,
    g.display_order,
    COALESCE(dr.chart_type, d.chart_type),
    ids.metric_config_ids,
    -- Names resolved in the same order as metric_config_ids (draft array
    -- order when a draft exists, sort_order otherwise), not re-sorted.
    ARRAY(
      SELECT mc.metric_name
      FROM unnest(ids.metric_config_ids) WITH ORDINALITY AS u(id, ord)
      JOIN rep_portal.metric_config mc ON mc.id = u.id
      ORDER BY u.ord
    ),
    d.status,
    (dr.permission_key IS NOT NULL),
    COALESCE(dr.comment, d.comment),
    COALESCE(dr.comment_enabled, d.comment_enabled)
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.dashlet_drafts dr ON dr.permission_key = p.key
  JOIN rep_portal.dashlet_groups g ON g.id = COALESCE(dr.group_id, d.group_id)
  JOIN LATERAL (
    SELECT CASE
      WHEN dr.permission_key IS NOT NULL THEN dr.metric_config_ids
      ELSE COALESCE((
        SELECT array_agg(pmm.metric_config_id ORDER BY mc.sort_order NULLS LAST, mc.id)
        FROM rep_portal.permission_metric_map pmm
        JOIN rep_portal.metric_config mc ON mc.id = pmm.metric_config_id
        WHERE pmm.permission_key = p.key AND pmm.metric_config_id IS NOT NULL
      ), '{}'::INTEGER[])
    END AS metric_config_ids
  ) ids ON true
  WHERE p.category = 'dashlet'
    AND d.source_type = 'salesforce'
    AND g.name <> '_ungrouped_salesforce'
  ORDER BY COALESCE(g.display_order, 999999), g.name, COALESCE(dr.label, p.label);
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_salesforce_dashlets_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_salesforce_dashlets_admin() TO authenticated;


-- ===== 20260719125134_exclude_ungrouped_from_kpi_dashlets.sql =====
-- Exclude ungrouped KPI dashlets from the public/preview KPI Dashboard, to
-- match the same rule applied to the new get_salesforce_dashlets()/_admin()
-- (companion migration in this batch): a dashlet sitting in the system
-- "no group" bucket (_ungrouped_kpi — see 20260718142053, every dashlet
-- always has a real group_id since that migration) simply never appears,
-- published or not. Requires assigning a real group before a dashlet shows
-- anywhere, consistent with everything else needing explicit configuration.
--
-- Return types unchanged, so CREATE OR REPLACE (no DROP needed).

CREATE OR REPLACE FUNCTION rep_portal.get_kpi_dashlets()
RETURNS TABLE (
  permission_key       TEXT,
  label                TEXT,
  description          TEXT,
  group_id             INTEGER,
  group_name           TEXT,
  group_display_order  INTEGER,
  chart_type           TEXT,
  display_mode         TEXT,
  kpi_id               TEXT,
  kpi_disagg1_filters  TEXT[],
  kpi_disagg2_filters  TEXT[],
  kpi_split_mode       TEXT,
  show_milestone       BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
  SELECT
    p.key,
    p.label,
    p.description,
    d.group_id,
    g.name,
    g.display_order,
    d.chart_type,
    d.display_mode,
    pmm.metric_id,
    pmm.kpi_disagg1_filters,
    pmm.kpi_disagg2_filters,
    pmm.kpi_split_mode,
    pmm.show_milestone
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.permission_metric_map pmm ON pmm.permission_key = p.key AND pmm.metric_config_id IS NULL
  JOIN rep_portal.dashlet_groups g ON g.id = d.group_id
  WHERE p.category = 'dashlet'
    AND d.source_type = 'kpi'
    AND d.chart_type IS NOT NULL
    AND d.status = 'published'
    AND pmm.metric_id IS NOT NULL
    AND g.name <> '_ungrouped_kpi'
  ORDER BY COALESCE(g.display_order, 999999), g.name, p.label;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_kpi_dashlets() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_kpi_dashlets() TO authenticated;

CREATE OR REPLACE FUNCTION rep_portal.get_kpi_dashlets_admin()
RETURNS TABLE (
  permission_key       TEXT,
  label                TEXT,
  description          TEXT,
  group_id             INTEGER,
  group_name           TEXT,
  group_display_order  INTEGER,
  chart_type           TEXT,
  display_mode         TEXT,
  kpi_id               TEXT,
  kpi_disagg1_filters  TEXT[],
  kpi_disagg2_filters  TEXT[],
  kpi_split_mode       TEXT,
  show_milestone       BOOLEAN,
  status               TEXT,
  has_pending_draft    BOOLEAN,
  comment              TEXT,
  comment_enabled      BOOLEAN
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
  SELECT
    p.key,
    COALESCE(dr.label, p.label),
    COALESCE(dr.description, p.description),
    COALESCE(dr.group_id, d.group_id),
    g.name,
    g.display_order,
    COALESCE(dr.chart_type, d.chart_type),
    COALESCE(dr.display_mode, d.display_mode),
    COALESCE(dr.kpi_id, pmm.metric_id),
    COALESCE(dr.kpi_disagg1_filters, pmm.kpi_disagg1_filters),
    COALESCE(dr.kpi_disagg2_filters, pmm.kpi_disagg2_filters),
    COALESCE(dr.kpi_split_mode, pmm.kpi_split_mode),
    COALESCE(dr.show_milestone, pmm.show_milestone),
    d.status,
    (dr.permission_key IS NOT NULL),
    COALESCE(dr.comment, d.comment),
    COALESCE(dr.comment_enabled, d.comment_enabled)
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.dashlet_drafts dr ON dr.permission_key = p.key
  LEFT JOIN rep_portal.permission_metric_map pmm ON pmm.permission_key = p.key AND pmm.metric_config_id IS NULL
  JOIN rep_portal.dashlet_groups g ON g.id = COALESCE(dr.group_id, d.group_id)
  WHERE p.category = 'dashlet'
    AND COALESCE(dr.source_type, d.source_type) = 'kpi'
    AND COALESCE(dr.chart_type, d.chart_type) IS NOT NULL
    AND COALESCE(dr.kpi_id, pmm.metric_id) IS NOT NULL
    AND g.name <> '_ungrouped_kpi'
  ORDER BY COALESCE(g.display_order, 999999), g.name, COALESCE(dr.label, p.label);
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_kpi_dashlets_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_kpi_dashlets_admin() TO authenticated;


-- ===== 20260719125240_add_get_salesforce_dashlet_data.sql =====
-- get_salesforce_dashlet_data(): broad country/year rows for a set of
-- metric_config ids, powering /salesforce-dashboard. Mirrors get_kpi_
-- dashlet_data()'s fetch-once model (all years/countries for the requested
-- metrics, filtering happens client-side) and reuses the dynamic-SQL
-- pattern from get_dashboard_data_filtered() (source_view/year_field/
-- value_agg/value_field/filters JSONB handling) — but grouped only by
-- country/year (no province/district/school; the Salesforce Dashboard stays
-- country-only on the chart axis for now) and with no geography/year-range
-- params of its own (the client sums whatever Start Year/End Year range is
-- selected). No permission filtering — any authenticated user, same as
-- get_kpi_dashlet_data().

CREATE OR REPLACE FUNCTION rep_portal.get_salesforce_dashlet_data(p_metric_config_ids INTEGER[])
RETURNS TABLE (
  metric_config_id INTEGER,
  metric_name      TEXT,
  country          TEXT,
  year             INTEGER,
  value            NUMERIC
)
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, public, pg_temp
AS $$
DECLARE
  v_metric      rep_portal.metric_config%ROWTYPE;
  v_sql         TEXT;
  v_union_parts TEXT[] := ARRAY[]::TEXT[];
  v_filter      JSONB;
  v_field       TEXT;
  v_op          TEXT;
  v_val         TEXT;
BEGIN
  IF p_metric_config_ids IS NULL OR array_length(p_metric_config_ids, 1) IS NULL THEN
    RETURN;
  END IF;

  FOR v_metric IN
    SELECT * FROM rep_portal.metric_config
    WHERE id = ANY(p_metric_config_ids) AND enabled = true
  LOOP
    -- year_field is smallint on some warehouse views (e.g.
    -- view_guide_assignment.joined_year) — cast explicitly so every branch
    -- of the UNION ALL matches the declared INTEGER return column.
    v_sql := format(
      'SELECT %L::int AS metric_config_id, %L::text AS metric_name, country, %I::int AS year, ',
      v_metric.id, v_metric.metric_name, v_metric.year_field
    );

    IF v_metric.value_agg = 'sum' THEN
      v_sql := v_sql || format('ROUND(SUM(COALESCE(%I::numeric, 0)), 2) AS value', v_metric.value_field);
    ELSE
      v_sql := v_sql || 'COUNT(*)::numeric AS value';
    END IF;

    v_sql := v_sql || format(' FROM rep_warehouse.%I WHERE TRUE', v_metric.source_view);
    v_sql := v_sql || format(' AND %I IS NOT NULL AND country IS NOT NULL', v_metric.year_field);

    -- JSONB filters — same eq / ilike / bool_true / not_null ops as
    -- get_dashboard_data_filtered().
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

    v_sql := v_sql || format(' GROUP BY country, %I', v_metric.year_field);

    v_union_parts := array_append(v_union_parts, v_sql);
  END LOOP;

  IF array_length(v_union_parts, 1) IS NULL THEN
    RETURN;
  END IF;

  RETURN QUERY EXECUTE array_to_string(v_union_parts, ' UNION ALL ');
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_salesforce_dashlet_data(INTEGER[]) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_salesforce_dashlet_data(INTEGER[]) TO authenticated;


-- ===== 20260719131418_fix_get_salesforce_dashlets_admin_chart_type_filter.sql =====
-- get_salesforce_dashlets_admin() was missing the "won't show until
-- configured" guard that get_kpi_dashlets_admin() already applies (COALESCE
-- chart_type IS NOT NULL, metric wiring non-empty) — without it, a
-- half-configured draft (no chart type and/or no metric picked yet) would
-- show up in ?preview=1 mode instead of being held back like an
-- unconfigured KPI dashlet is. Bringing it in line.

CREATE OR REPLACE FUNCTION rep_portal.get_salesforce_dashlets_admin()
RETURNS TABLE (
  permission_key       TEXT,
  label                TEXT,
  description          TEXT,
  group_id             INTEGER,
  group_name           TEXT,
  group_display_order  INTEGER,
  chart_type           TEXT,
  metric_config_ids    INTEGER[],
  metric_names         TEXT[],
  status               TEXT,
  has_pending_draft    BOOLEAN,
  comment              TEXT,
  comment_enabled      BOOLEAN
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
  SELECT
    p.key,
    COALESCE(dr.label, p.label),
    COALESCE(dr.description, p.description),
    COALESCE(dr.group_id, d.group_id),
    g.name,
    g.display_order,
    COALESCE(dr.chart_type, d.chart_type),
    ids.metric_config_ids,
    -- Names resolved in the same order as metric_config_ids (draft array
    -- order when a draft exists, sort_order otherwise), not re-sorted.
    ARRAY(
      SELECT mc.metric_name
      FROM unnest(ids.metric_config_ids) WITH ORDINALITY AS u(id, ord)
      JOIN rep_portal.metric_config mc ON mc.id = u.id
      ORDER BY u.ord
    ),
    d.status,
    (dr.permission_key IS NOT NULL),
    COALESCE(dr.comment, d.comment),
    COALESCE(dr.comment_enabled, d.comment_enabled)
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.dashlet_drafts dr ON dr.permission_key = p.key
  JOIN rep_portal.dashlet_groups g ON g.id = COALESCE(dr.group_id, d.group_id)
  JOIN LATERAL (
    SELECT CASE
      WHEN dr.permission_key IS NOT NULL THEN dr.metric_config_ids
      ELSE COALESCE((
        SELECT array_agg(pmm.metric_config_id ORDER BY mc.sort_order NULLS LAST, mc.id)
        FROM rep_portal.permission_metric_map pmm
        JOIN rep_portal.metric_config mc ON mc.id = pmm.metric_config_id
        WHERE pmm.permission_key = p.key AND pmm.metric_config_id IS NOT NULL
      ), '{}'::INTEGER[])
    END AS metric_config_ids
  ) ids ON true
  WHERE p.category = 'dashlet'
    AND d.source_type = 'salesforce'
    AND g.name <> '_ungrouped_salesforce'
    AND COALESCE(dr.chart_type, d.chart_type) IS NOT NULL
    AND array_length(ids.metric_config_ids, 1) > 0
  ORDER BY COALESCE(g.display_order, 999999), g.name, COALESCE(dr.label, p.label);
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_salesforce_dashlets_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_salesforce_dashlets_admin() TO authenticated;


-- ===== 20260719134304_add_line_chart_type_for_salesforce_dashlets.sql =====
-- Re-add 'line' as a dashlet chart_type option — dropped for KPI dashlets
-- in 20260718072530 (KPI Dashboard has no per-year trend rendering), but the
-- Salesforce Dashboard's new year-breakdown aggregation (single-metric Table
-- dashlets over a real Start-End range) makes a genuine trend-over-years
-- chart cheap to render, so it's being offered as its own selectable chart
-- type for Salesforce dashlets. The admin form only exposes this option when
-- Source type = Salesforce; nothing stops a KPI dashlet's chart_type from
-- being 'line' at the DB level, but the KPI Dashboard page has no renderer
-- for it (falls through unchanged from before this migration).

ALTER TABLE rep_portal.dashlets DROP CONSTRAINT dashlets_chart_type_check;
ALTER TABLE rep_portal.dashlets ADD CONSTRAINT dashlets_chart_type_check
  CHECK (chart_type IN ('number', 'bar', 'horizontal_bar', 'pie', 'table', 'line'));


-- ===== 20260719145736_add_dashboards_table.sql =====
-- Phase 1 of multi-dashboard support: introduce rep_portal.dashboards as a
-- real object, decoupling "how many dashboards exist" from "how many
-- source_types exist" (today source_type IN ('kpi','salesforce') is the only
-- thing distinguishing /kpi-dashboard from /salesforce-dashboard).
--
-- This migration only adds the table and seeds the two dashboards that
-- already exist today (as the default dashboard of each type). Wiring
-- dashlets/dashlet_groups to it happens in the next migration.

CREATE TABLE rep_portal.dashboards (
  id             SERIAL PRIMARY KEY,
  key            TEXT NOT NULL UNIQUE,
  label          TEXT NOT NULL,
  source_type    TEXT NOT NULL CHECK (source_type IN ('kpi', 'salesforce')),
  display_order  INTEGER NOT NULL DEFAULT 0,
  is_default     BOOLEAN NOT NULL DEFAULT false,
  created_at     TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at     TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- At most one default dashboard per type — this is what "?dashboard= not
-- given" resolves to, so it must be unambiguous.
CREATE UNIQUE INDEX dashboards_one_default_per_type
  ON rep_portal.dashboards (source_type) WHERE is_default;

ALTER TABLE rep_portal.dashboards ENABLE ROW LEVEL SECURITY;
-- No policies — default deny, matching every other rep_portal table. Read
-- access for authenticated users goes through get_dashboards() (added in a
-- later migration); writes exclusively through the admin-users edge function.

CREATE TRIGGER dashboards_updated_at
  BEFORE UPDATE ON rep_portal.dashboards
  FOR EACH ROW EXECUTE FUNCTION rep_portal.set_updated_at();

INSERT INTO rep_portal.dashboards (key, label, source_type, display_order, is_default) VALUES
  ('kpi', 'KPI Dashboard', 'kpi', 0, true),
  ('salesforce', 'Salesforce Dashboard', 'salesforce', 0, true);

GRANT ALL ON rep_portal.dashboards TO service_role;
GRANT USAGE ON SEQUENCE rep_portal.dashboards_id_seq TO service_role;


-- ===== 20260719145807_add_dashboard_id_to_dashlets_and_groups.sql =====
-- Phase 2 of multi-dashboard support: wire dashlets/dashlet_groups to a real
-- dashboards row instead of only knowing their source_type. source_type stays
-- (avoids touching every existing RPC/admin query that reads it) but becomes
-- derived from dashboard_id via trigger rather than independently settable —
-- a dashlet's type can never again drift from the dashboard it belongs to.

ALTER TABLE rep_portal.dashlets ADD COLUMN dashboard_id INTEGER REFERENCES rep_portal.dashboards(id);
ALTER TABLE rep_portal.dashlet_groups ADD COLUMN dashboard_id INTEGER REFERENCES rep_portal.dashboards(id);

CREATE OR REPLACE FUNCTION rep_portal.derive_source_type_from_dashboard()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = rep_portal, pg_temp AS $$
BEGIN
  NEW.source_type := (SELECT d.source_type FROM rep_portal.dashboards d WHERE d.id = NEW.dashboard_id);
  IF NEW.source_type IS NULL THEN
    RAISE EXCEPTION 'dashboard_id % does not reference a valid dashboard', NEW.dashboard_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER dashlets_derive_source_type
  BEFORE INSERT OR UPDATE OF dashboard_id ON rep_portal.dashlets
  FOR EACH ROW EXECUTE FUNCTION rep_portal.derive_source_type_from_dashboard();

CREATE TRIGGER dashlet_groups_derive_source_type
  BEFORE INSERT OR UPDATE OF dashboard_id ON rep_portal.dashlet_groups
  FOR EACH ROW EXECUTE FUNCTION rep_portal.derive_source_type_from_dashboard();

-- Backfill: every existing dashlet/group of a given source_type belongs to
-- that type's (only, at this point) default dashboard.
UPDATE rep_portal.dashlets d
SET dashboard_id = db.id
FROM rep_portal.dashboards db
WHERE db.source_type = d.source_type AND db.is_default;

UPDATE rep_portal.dashlet_groups g
SET dashboard_id = db.id
FROM rep_portal.dashboards db
WHERE db.source_type = g.source_type AND db.is_default;

ALTER TABLE rep_portal.dashlets ALTER COLUMN dashboard_id SET NOT NULL;
ALTER TABLE rep_portal.dashlet_groups ALTER COLUMN dashboard_id SET NOT NULL;


-- ===== 20260719145848_rescope_dashlet_groups_to_dashboard.sql =====
-- Phase 3 of multi-dashboard support: a dashlet_groups row now belongs to one
-- dashboard, not just one type — a name is unique per dashboard, and a
-- dashlet's group must belong to its own dashboard (tighter than the old
-- "same type" check, since two dashboards of the same type can now exist).
--
-- Also replaces the '_ungrouped_kpi' / '_ungrouped_salesforce' name-based
-- convention (which doesn't generalize past two dashboards) with a real
-- is_ungrouped flag. Every dashboard needs its own ungrouped placeholder row
-- going forward — created here for the two existing dashboards, and by
-- create_dashboard() for any new one (added in a later migration).

ALTER TABLE rep_portal.dashlet_groups DROP CONSTRAINT dashlet_groups_name_source_type_key;
ALTER TABLE rep_portal.dashlet_groups
  ADD CONSTRAINT dashlet_groups_name_dashboard_id_key UNIQUE (name, dashboard_id);

ALTER TABLE rep_portal.dashlet_groups ADD COLUMN is_ungrouped BOOLEAN NOT NULL DEFAULT false;

UPDATE rep_portal.dashlet_groups SET is_ungrouped = true
WHERE name IN ('_ungrouped_kpi', '_ungrouped_salesforce');

DROP TRIGGER dashlets_enforce_group_source_type ON rep_portal.dashlets;
DROP FUNCTION rep_portal.enforce_dashlet_group_source_type();

CREATE OR REPLACE FUNCTION rep_portal.enforce_dashlet_group_dashboard()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = rep_portal, pg_temp AS $$
BEGIN
  IF NEW.group_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM rep_portal.dashlet_groups g
    WHERE g.id = NEW.group_id AND g.dashboard_id = NEW.dashboard_id
  ) THEN
    RAISE EXCEPTION 'dashlet %: group_id % does not belong to dashboard %', NEW.permission_key, NEW.group_id, NEW.dashboard_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER dashlets_enforce_group_dashboard
  BEFORE INSERT OR UPDATE OF group_id, dashboard_id ON rep_portal.dashlets
  FOR EACH ROW EXECUTE FUNCTION rep_portal.enforce_dashlet_group_dashboard();


-- ===== 20260719145944_parameterize_dashlet_rpcs_by_dashboard.sql =====
-- Phase 4 of multi-dashboard support: the four dashlet-list RPCs move from
-- hardcoding "the one kpi/salesforce dashboard" (via source_type) to taking
-- an explicit p_dashboard_id, defaulting to that type's is_default dashboard
-- when omitted — this is what keeps /kpi-dashboard and /salesforce-dashboard
-- working with zero frontend changes until the dashboard-switcher UI lands.
--
-- A trailing DEFAULT NULL parameter still changes the function's argument
-- list — CREATE OR REPLACE alone would create an overload, not replace the
-- zero-arg original (Postgres only replaces on an exact argument-type
-- match), so the old signatures are dropped explicitly first.

DROP FUNCTION IF EXISTS rep_portal.get_kpi_dashlets();
DROP FUNCTION IF EXISTS rep_portal.get_kpi_dashlets_admin();
DROP FUNCTION IF EXISTS rep_portal.get_salesforce_dashlets();
DROP FUNCTION IF EXISTS rep_portal.get_salesforce_dashlets_admin();

CREATE OR REPLACE FUNCTION rep_portal.default_dashboard_id(p_source_type TEXT)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
  SELECT id FROM rep_portal.dashboards WHERE source_type = p_source_type AND is_default;
$$;

REVOKE ALL ON FUNCTION rep_portal.default_dashboard_id(TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.default_dashboard_id(TEXT) TO authenticated, service_role;

-- ── get_kpi_dashlets ─────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.get_kpi_dashlets(p_dashboard_id INTEGER DEFAULT NULL)
RETURNS TABLE (
  permission_key       TEXT,
  label                TEXT,
  description          TEXT,
  group_id             INTEGER,
  group_name           TEXT,
  group_display_order  INTEGER,
  chart_type           TEXT,
  display_mode         TEXT,
  kpi_id               TEXT,
  kpi_disagg1_filters  TEXT[],
  kpi_disagg2_filters  TEXT[],
  kpi_split_mode       TEXT,
  show_milestone       BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
  SELECT
    p.key,
    p.label,
    p.description,
    d.group_id,
    g.name,
    g.display_order,
    d.chart_type,
    d.display_mode,
    pmm.metric_id,
    pmm.kpi_disagg1_filters,
    pmm.kpi_disagg2_filters,
    pmm.kpi_split_mode,
    pmm.show_milestone
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.permission_metric_map pmm ON pmm.permission_key = p.key AND pmm.metric_config_id IS NULL
  JOIN rep_portal.dashlet_groups g ON g.id = d.group_id
  WHERE p.category = 'dashlet'
    AND d.dashboard_id = COALESCE(p_dashboard_id, rep_portal.default_dashboard_id('kpi'))
    AND d.chart_type IS NOT NULL
    AND d.status = 'published'
    AND pmm.metric_id IS NOT NULL
    AND g.is_ungrouped = false
  ORDER BY COALESCE(g.display_order, 999999), g.name, p.label;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_kpi_dashlets(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_kpi_dashlets(INTEGER) TO authenticated;

-- ── get_kpi_dashlets_admin ───────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.get_kpi_dashlets_admin(p_dashboard_id INTEGER DEFAULT NULL)
RETURNS TABLE (
  permission_key       TEXT,
  label                TEXT,
  description          TEXT,
  group_id             INTEGER,
  group_name           TEXT,
  group_display_order  INTEGER,
  chart_type           TEXT,
  display_mode         TEXT,
  kpi_id               TEXT,
  kpi_disagg1_filters  TEXT[],
  kpi_disagg2_filters  TEXT[],
  kpi_split_mode       TEXT,
  show_milestone       BOOLEAN,
  status               TEXT,
  has_pending_draft    BOOLEAN,
  comment              TEXT,
  comment_enabled      BOOLEAN
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
  SELECT
    p.key,
    COALESCE(dr.label, p.label),
    COALESCE(dr.description, p.description),
    COALESCE(dr.group_id, d.group_id),
    g.name,
    g.display_order,
    COALESCE(dr.chart_type, d.chart_type),
    COALESCE(dr.display_mode, d.display_mode),
    COALESCE(dr.kpi_id, pmm.metric_id),
    COALESCE(dr.kpi_disagg1_filters, pmm.kpi_disagg1_filters),
    COALESCE(dr.kpi_disagg2_filters, pmm.kpi_disagg2_filters),
    COALESCE(dr.kpi_split_mode, pmm.kpi_split_mode),
    COALESCE(dr.show_milestone, pmm.show_milestone),
    d.status,
    (dr.permission_key IS NOT NULL),
    COALESCE(dr.comment, d.comment),
    COALESCE(dr.comment_enabled, d.comment_enabled)
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.dashlet_drafts dr ON dr.permission_key = p.key
  LEFT JOIN rep_portal.permission_metric_map pmm ON pmm.permission_key = p.key AND pmm.metric_config_id IS NULL
  LEFT JOIN rep_portal.dashlet_groups g ON g.id = COALESCE(dr.group_id, d.group_id)
  WHERE p.category = 'dashlet'
    AND d.dashboard_id = COALESCE(p_dashboard_id, rep_portal.default_dashboard_id('kpi'))
    AND COALESCE(dr.chart_type, d.chart_type) IS NOT NULL
    AND COALESCE(dr.kpi_id, pmm.metric_id) IS NOT NULL
  ORDER BY COALESCE(g.display_order, 999999), g.name NULLS LAST, COALESCE(dr.label, p.label);
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_kpi_dashlets_admin(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_kpi_dashlets_admin(INTEGER) TO authenticated;

-- ── get_salesforce_dashlets ──────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.get_salesforce_dashlets(p_dashboard_id INTEGER DEFAULT NULL)
RETURNS TABLE (
  permission_key       TEXT,
  label                TEXT,
  description          TEXT,
  group_id             INTEGER,
  group_name           TEXT,
  group_display_order  INTEGER,
  chart_type           TEXT,
  metric_config_ids    INTEGER[],
  metric_names         TEXT[]
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
  SELECT
    p.key,
    p.label,
    p.description,
    d.group_id,
    g.name,
    g.display_order,
    d.chart_type,
    mm.metric_config_ids,
    mm.metric_names
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  JOIN rep_portal.dashlet_groups g ON g.id = d.group_id
  JOIN LATERAL (
    SELECT
      array_agg(mc.id ORDER BY mc.sort_order NULLS LAST, mc.id)          AS metric_config_ids,
      array_agg(mc.metric_name ORDER BY mc.sort_order NULLS LAST, mc.id) AS metric_names
    FROM rep_portal.permission_metric_map pmm
    JOIN rep_portal.metric_config mc ON mc.id = pmm.metric_config_id
    WHERE pmm.permission_key = p.key AND pmm.metric_config_id IS NOT NULL
  ) mm ON true
  WHERE p.category = 'dashlet'
    AND d.dashboard_id = COALESCE(p_dashboard_id, rep_portal.default_dashboard_id('salesforce'))
    AND d.status = 'published'
    AND d.chart_type IS NOT NULL
    AND g.is_ungrouped = false
    AND mm.metric_config_ids IS NOT NULL
  ORDER BY COALESCE(g.display_order, 999999), g.name, p.label;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_salesforce_dashlets(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_salesforce_dashlets(INTEGER) TO authenticated;

-- ── get_salesforce_dashlets_admin ────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.get_salesforce_dashlets_admin(p_dashboard_id INTEGER DEFAULT NULL)
RETURNS TABLE (
  permission_key       TEXT,
  label                TEXT,
  description          TEXT,
  group_id             INTEGER,
  group_name           TEXT,
  group_display_order  INTEGER,
  chart_type           TEXT,
  metric_config_ids    INTEGER[],
  metric_names         TEXT[],
  status               TEXT,
  has_pending_draft    BOOLEAN,
  comment              TEXT,
  comment_enabled      BOOLEAN
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
  SELECT
    p.key,
    COALESCE(dr.label, p.label),
    COALESCE(dr.description, p.description),
    COALESCE(dr.group_id, d.group_id),
    g.name,
    g.display_order,
    COALESCE(dr.chart_type, d.chart_type),
    ids.metric_config_ids,
    ARRAY(
      SELECT mc.metric_name
      FROM unnest(ids.metric_config_ids) WITH ORDINALITY AS u(id, ord)
      JOIN rep_portal.metric_config mc ON mc.id = u.id
      ORDER BY u.ord
    ),
    d.status,
    (dr.permission_key IS NOT NULL),
    COALESCE(dr.comment, d.comment),
    COALESCE(dr.comment_enabled, d.comment_enabled)
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.dashlet_drafts dr ON dr.permission_key = p.key
  JOIN rep_portal.dashlet_groups g ON g.id = COALESCE(dr.group_id, d.group_id)
  JOIN LATERAL (
    SELECT CASE
      WHEN dr.permission_key IS NOT NULL THEN dr.metric_config_ids
      ELSE COALESCE((
        SELECT array_agg(pmm.metric_config_id ORDER BY mc.sort_order NULLS LAST, mc.id)
        FROM rep_portal.permission_metric_map pmm
        JOIN rep_portal.metric_config mc ON mc.id = pmm.metric_config_id
        WHERE pmm.permission_key = p.key AND pmm.metric_config_id IS NOT NULL
      ), '{}'::INTEGER[])
    END AS metric_config_ids
  ) ids ON true
  WHERE p.category = 'dashlet'
    AND d.dashboard_id = COALESCE(p_dashboard_id, rep_portal.default_dashboard_id('salesforce'))
    AND g.is_ungrouped = false
    AND COALESCE(dr.chart_type, d.chart_type) IS NOT NULL
    AND array_length(ids.metric_config_ids, 1) > 0
  ORDER BY COALESCE(g.display_order, 999999), g.name, COALESCE(dr.label, p.label);
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_salesforce_dashlets_admin(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_salesforce_dashlets_admin(INTEGER) TO authenticated;


-- ===== 20260719150129_update_create_dashlet_dashboard_id.sql =====
-- create_dashlet(): p_source_type is replaced by p_dashboard_id — a dashlet
-- is now created directly against a dashboard, and source_type is derived
-- from it by the dashlets_derive_source_type trigger (20260719145807), so
-- there's no longer a separately-trusted type value that could drift from
-- the dashboard it's attached to. Signature changes, so drop first.

DROP FUNCTION IF EXISTS rep_portal.create_dashlet(TEXT, TEXT, TEXT, TEXT, TEXT, INTEGER, TEXT, TEXT, TEXT, BOOLEAN, INTEGER[], TEXT, TEXT[], TEXT[], TEXT, UUID, BOOLEAN);

CREATE FUNCTION rep_portal.create_dashlet(
  p_key                  TEXT,
  p_label                TEXT,
  p_description          TEXT,
  p_parent_key           TEXT,
  p_dashboard_id         INTEGER,
  p_group_id             INTEGER,
  p_chart_type           TEXT,
  p_display_mode         TEXT,
  p_comment              TEXT,
  p_comment_enabled      BOOLEAN,
  p_metric_config_ids    INTEGER[],
  p_kpi_id               TEXT,
  p_kpi_disagg1_filters  TEXT[],
  p_kpi_disagg2_filters  TEXT[],
  p_kpi_split_mode       TEXT,
  p_updated_by           UUID,
  p_show_milestone       BOOLEAN DEFAULT false
)
RETURNS rep_portal.dashlets
LANGUAGE plpgsql SECURITY DEFINER SET search_path = rep_portal, pg_temp AS $$
DECLARE
  v_dashlet rep_portal.dashlets;
BEGIN
  INSERT INTO rep_portal.permissions (key, label, description, category, parent_key)
  VALUES (p_key, p_label, p_description, 'dashlet', p_parent_key);

  INSERT INTO rep_portal.dashlets (
    permission_key, dashboard_id, group_id, chart_type, display_mode,
    comment, comment_enabled, updated_by
  )
  VALUES (
    p_key, p_dashboard_id, p_group_id, p_chart_type, p_display_mode,
    p_comment, p_comment_enabled, p_updated_by
  )
  RETURNING * INTO v_dashlet;

  IF v_dashlet.source_type = 'salesforce' THEN
    INSERT INTO rep_portal.permission_metric_map (permission_key, metric_id, metric_config_id)
    SELECT p_key, mc.metric_name, mc.id FROM rep_portal.metric_config mc WHERE mc.id = ANY(p_metric_config_ids);
  ELSIF v_dashlet.source_type = 'kpi' AND p_kpi_id IS NOT NULL THEN
    INSERT INTO rep_portal.permission_metric_map (
      permission_key, metric_id, metric_config_id,
      kpi_disagg1_filters, kpi_disagg2_filters, kpi_split_mode, show_milestone
    )
    VALUES (
      p_key, p_kpi_id, NULL,
      COALESCE(p_kpi_disagg1_filters, '{}'), COALESCE(p_kpi_disagg2_filters, '{}'), COALESCE(p_kpi_split_mode, 'combine'),
      COALESCE(p_show_milestone, false)
    );
  END IF;

  RETURN v_dashlet;
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.create_dashlet(TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER, TEXT, TEXT, TEXT, BOOLEAN, INTEGER[], TEXT, TEXT[], TEXT[], TEXT, UUID, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.create_dashlet(TEXT, TEXT, TEXT, TEXT, INTEGER, INTEGER, TEXT, TEXT, TEXT, BOOLEAN, INTEGER[], TEXT, TEXT[], TEXT[], TEXT, UUID, BOOLEAN) TO service_role;


-- ===== 20260719150500_add_get_dashboards_rpc.sql =====
-- get_dashboards(): public read of the dashboard catalog, used by
-- /kpi-dashboard and /salesforce-dashboard to resolve a ?dashboard= key to
-- its id and to populate the dashboard-switcher dropdown. Any authenticated
-- user — matches the existing "any authenticated user" gate on
-- get_kpi_dashlets()/get_salesforce_dashlets(), which this feeds into.

CREATE OR REPLACE FUNCTION rep_portal.get_dashboards()
RETURNS TABLE (
  id             INTEGER,
  key            TEXT,
  label          TEXT,
  source_type    TEXT,
  display_order  INTEGER,
  is_default     BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
  SELECT id, key, label, source_type, display_order, is_default
  FROM rep_portal.dashboards
  ORDER BY source_type, display_order, label;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_dashboards() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_dashboards() TO authenticated;


-- ===== 20260719153155_add_set_default_dashboard_rpc.sql =====
-- Unsetting a dashboard's is_default with no other default in place for its
-- source_type would leave get_kpi_dashlets()/get_salesforce_dashlets()'s own
-- NULL-p_dashboard_id fallback (default_dashboard_id()) resolving to nothing
-- — silently blanking /kpi-dashboard and /salesforce-dashboard with no
-- ?dashboard= param. The partial unique index on dashboards only prevents
-- two defaults for one type; it does nothing to prevent zero. This RPC makes
-- "move the default from A to B" one atomic statement instead of two
-- separate updates (unset-then-set) with a zero-default window between them,
-- and the admin-users edge function is being changed alongside this to
-- route every is_default:true through it and reject is_default:false outright.

CREATE OR REPLACE FUNCTION rep_portal.set_default_dashboard(p_dashboard_id INTEGER)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
DECLARE
  v_source_type TEXT;
BEGIN
  SELECT source_type INTO v_source_type FROM rep_portal.dashboards WHERE id = p_dashboard_id;
  IF v_source_type IS NULL THEN
    RAISE EXCEPTION 'dashboard % does not exist', p_dashboard_id;
  END IF;

  UPDATE rep_portal.dashboards SET is_default = false
  WHERE source_type = v_source_type AND is_default = true AND id <> p_dashboard_id;

  UPDATE rep_portal.dashboards SET is_default = true
  WHERE id = p_dashboard_id;
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.set_default_dashboard(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.set_default_dashboard(INTEGER) TO service_role;


-- ===== 20260720183851_add_get_view_column_values_rpc.sql =====
-- Returns distinct values for a column of a rep_warehouse view, for the admin
-- Metric Config form's filter-builder "equals" value picker — so admins pick
-- real values instead of typing them freehand. Sibling to get_view_columns,
-- restricted to the same fixed set of views metric_config.source_view is
-- allowed to reference.

CREATE OR REPLACE FUNCTION rep_portal.get_view_column_values(p_view_name TEXT, p_column_name TEXT)
RETURNS json
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, rep_warehouse, pg_temp
AS $$
DECLARE
  v_all text[];
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

  -- Unlike the view-name check above, an unknown column is treated as
  -- "no values" rather than an error — schema drift (a column renamed/
  -- dropped after a metric_config row was saved) shouldn't hard-fail the
  -- picker; the frontend falls back to free text in that case.
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'rep_warehouse' AND table_name = p_view_name AND column_name = p_column_name
  ) THEN
    RETURN json_build_object('values', '[]'::json, 'truncated', false);
  END IF;

  -- Fetch one more than the display cap so we can detect truncation.
  EXECUTE format(
    'SELECT ARRAY(SELECT DISTINCT %I::text FROM rep_warehouse.%I WHERE %I IS NOT NULL ORDER BY 1 LIMIT 501)',
    p_column_name, p_view_name, p_column_name
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

REVOKE ALL   ON FUNCTION rep_portal.get_view_column_values(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_view_column_values(TEXT, TEXT) TO authenticated;


-- ===== 20260721060240_add_dashlet_categories.sql =====
-- Adds a category tier above dashlet_groups (dashboard -> category -> group ->
-- dashlet), for the new "Main Dashboard" validation page that replaces the
-- hardcoded Level/Sub Level hierarchy dashboard (frontend/src/routes/dashboard.tsx)
-- with the same admin-configurable dashlet system already powering the KPI
-- Dashboard. Existing dashboards (KPI, Salesforce) are untouched: category_id
-- on dashlet_groups is nullable with no backfill, and neither
-- get_kpi_dashlets() nor get_salesforce_dashlets() reference it.

-- ── dashlet_categories ───────────────────────────────────────────────────────

CREATE TABLE rep_portal.dashlet_categories (
  id                 SERIAL PRIMARY KEY,
  dashboard_id       INTEGER NOT NULL REFERENCES rep_portal.dashboards(id),
  name               TEXT NOT NULL,
  display_order      INTEGER NOT NULL DEFAULT 0,
  is_uncategorized   BOOLEAN NOT NULL DEFAULT false,
  created_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  updated_at         TIMESTAMPTZ NOT NULL DEFAULT now(),
  UNIQUE (name, dashboard_id)
);

ALTER TABLE rep_portal.dashlet_categories ENABLE ROW LEVEL SECURITY;
-- No policies — default deny, matching every other rep_portal dashlet-config
-- table. Access exclusively through the admin-users edge function
-- (service_role) for writes, and get_main_dashboard_dashlets() for reads.

CREATE TRIGGER dashlet_categories_updated_at
  BEFORE UPDATE ON rep_portal.dashlet_categories
  FOR EACH ROW EXECUTE FUNCTION rep_portal.set_updated_at();

-- ── dashlet_groups.category_id ───────────────────────────────────────────────

ALTER TABLE rep_portal.dashlet_groups
  ADD COLUMN category_id INTEGER REFERENCES rep_portal.dashlet_categories(id) ON DELETE SET NULL;

-- A group's category (if set) must belong to the same dashboard as the group
-- itself — mirrors enforce_dashlet_group_dashboard()'s dashlet/group check.
CREATE OR REPLACE FUNCTION rep_portal.enforce_dashlet_group_category_dashboard()
RETURNS TRIGGER
LANGUAGE plpgsql SECURITY DEFINER SET search_path = rep_portal, pg_temp AS $$
BEGIN
  IF NEW.category_id IS NOT NULL AND NOT EXISTS (
    SELECT 1 FROM rep_portal.dashlet_categories c
    WHERE c.id = NEW.category_id AND c.dashboard_id = NEW.dashboard_id
  ) THEN
    RAISE EXCEPTION 'group %: category_id % does not belong to dashboard %', NEW.name, NEW.category_id, NEW.dashboard_id;
  END IF;
  RETURN NEW;
END;
$$;

CREATE TRIGGER dashlet_groups_enforce_category_dashboard
  BEFORE INSERT OR UPDATE OF category_id, dashboard_id ON rep_portal.dashlet_groups
  FOR EACH ROW EXECUTE FUNCTION rep_portal.enforce_dashlet_group_category_dashboard();

-- ── Seed the "Main Dashboard (Preview)" dashboard ────────────────────────────
-- source_type='kpi' — reuses the existing single-kpi_id-per-dashlet model
-- (get_main_dashboard_dashlets below is a category-aware sibling of
-- get_kpi_dashlets()), no multi-KPI sum/ratio support needed. is_default is
-- false: this dashboard is reached only via its own 'main' key, never as the
-- fallback for source_type='kpi' (that stays the existing KPI Dashboard).

DO $$
DECLARE
  v_dashboard_id INTEGER;
BEGIN
  INSERT INTO rep_portal.dashboards (key, label, source_type, display_order, is_default)
  VALUES ('main', 'Main Dashboard (Preview)', 'kpi', 1, false)
  RETURNING id INTO v_dashboard_id;

  -- Every dashboard needs its own "no group chosen" placeholder, same
  -- invariant dashboard-create already enforces in the admin-users edge function.
  INSERT INTO rep_portal.dashlet_groups (name, dashboard_id, is_ungrouped, display_order)
  VALUES ('_ungrouped_main', v_dashboard_id, true, 999999);

  -- "Uncategorized" fallback category — groups left without a category land
  -- here so nothing silently disappears from the validation page.
  INSERT INTO rep_portal.dashlet_categories (name, dashboard_id, is_uncategorized, display_order)
  VALUES ('Uncategorized', v_dashboard_id, true, 999999);
END $$;

-- ── get_main_dashboard_dashlets ──────────────────────────────────────────────
-- Category-aware sibling of get_kpi_dashlets(): same KPI resolution via
-- permission_metric_map, plus category_id/category_name/category_display_order.
-- Groups with no category fall back to that dashboard's "Uncategorized" row.

CREATE OR REPLACE FUNCTION rep_portal.get_main_dashboard_dashlets(p_dashboard_id INTEGER DEFAULT NULL)
RETURNS TABLE (
  permission_key          TEXT,
  label                   TEXT,
  description             TEXT,
  category_id             INTEGER,
  category_name           TEXT,
  category_display_order  INTEGER,
  group_id                INTEGER,
  group_name              TEXT,
  group_display_order     INTEGER,
  chart_type              TEXT,
  display_mode            TEXT,
  kpi_id                  TEXT,
  kpi_disagg1_filters     TEXT[],
  kpi_disagg2_filters     TEXT[],
  kpi_split_mode          TEXT,
  show_milestone          BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
  SELECT
    p.key,
    p.label,
    p.description,
    COALESCE(c.id, uc.id),
    COALESCE(c.name, uc.name),
    COALESCE(c.display_order, uc.display_order),
    d.group_id,
    g.name,
    g.display_order,
    d.chart_type,
    d.display_mode,
    pmm.metric_id,
    pmm.kpi_disagg1_filters,
    pmm.kpi_disagg2_filters,
    pmm.kpi_split_mode,
    pmm.show_milestone
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.permission_metric_map pmm ON pmm.permission_key = p.key AND pmm.metric_config_id IS NULL
  JOIN rep_portal.dashlet_groups g ON g.id = d.group_id
  LEFT JOIN rep_portal.dashlet_categories c ON c.id = g.category_id
  LEFT JOIN rep_portal.dashlet_categories uc ON uc.dashboard_id = g.dashboard_id AND uc.is_uncategorized = true
  WHERE p.category = 'dashlet'
    AND d.dashboard_id = COALESCE(p_dashboard_id, (SELECT id FROM rep_portal.dashboards WHERE key = 'main'))
    AND d.chart_type IS NOT NULL
    AND d.status = 'published'
    AND pmm.metric_id IS NOT NULL
    AND g.is_ungrouped = false
  ORDER BY COALESCE(c.display_order, uc.display_order, 999999), COALESCE(c.name, uc.name), COALESCE(g.display_order, 999999), g.name, p.label;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_main_dashboard_dashlets(INTEGER) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_main_dashboard_dashlets(INTEGER) TO authenticated;

-- ── Grants ────────────────────────────────────────────────────────────────────

GRANT ALL ON rep_portal.dashlet_categories TO service_role;
GRANT USAGE ON SEQUENCE rep_portal.dashlet_categories_id_seq TO service_role;


-- ===== 20260721071526_main_dashboard_uses_default_kpi_dashboard.sql =====
-- The "Main Dashboard (Preview)" page (frontend/src/routes/main-dashboard.tsx)
-- should show the existing default KPI Dashboard's real dashlets/groups
-- (categorized on top, via the tier added in
-- 20260721060240_add_dashlet_categories.sql), not a separate empty
-- dashboard that an admin would have to rebuild from scratch. Per explicit
-- direction: "This page must use the default kpi dashboard."
--
-- Existing groups on the default KPI dashboard have no category_id yet —
-- they simply fall back to "Uncategorized" (get_main_dashboard_dashlets
-- already handles this) until an admin assigns real categories via the
-- Categories/Groups tabs, which work against any dashboard, including the
-- default KPI one.

CREATE OR REPLACE FUNCTION rep_portal.get_main_dashboard_dashlets(p_dashboard_id INTEGER DEFAULT NULL)
RETURNS TABLE (
  permission_key          TEXT,
  label                   TEXT,
  description             TEXT,
  category_id             INTEGER,
  category_name           TEXT,
  category_display_order  INTEGER,
  group_id                INTEGER,
  group_name              TEXT,
  group_display_order     INTEGER,
  chart_type              TEXT,
  display_mode            TEXT,
  kpi_id                  TEXT,
  kpi_disagg1_filters     TEXT[],
  kpi_disagg2_filters     TEXT[],
  kpi_split_mode          TEXT,
  show_milestone          BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
  SELECT
    p.key,
    p.label,
    p.description,
    COALESCE(c.id, uc.id),
    COALESCE(c.name, uc.name),
    COALESCE(c.display_order, uc.display_order),
    d.group_id,
    g.name,
    g.display_order,
    d.chart_type,
    d.display_mode,
    pmm.metric_id,
    pmm.kpi_disagg1_filters,
    pmm.kpi_disagg2_filters,
    pmm.kpi_split_mode,
    pmm.show_milestone
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.permission_metric_map pmm ON pmm.permission_key = p.key AND pmm.metric_config_id IS NULL
  JOIN rep_portal.dashlet_groups g ON g.id = d.group_id
  LEFT JOIN rep_portal.dashlet_categories c ON c.id = g.category_id
  LEFT JOIN rep_portal.dashlet_categories uc ON uc.dashboard_id = g.dashboard_id AND uc.is_uncategorized = true
  WHERE p.category = 'dashlet'
    AND d.dashboard_id = COALESCE(p_dashboard_id, rep_portal.default_dashboard_id('kpi'))
    AND d.chart_type IS NOT NULL
    AND d.status = 'published'
    AND pmm.metric_id IS NOT NULL
    AND g.is_ungrouped = false
  ORDER BY COALESCE(c.display_order, uc.display_order, 999999), COALESCE(c.name, uc.name), COALESCE(g.display_order, 999999), g.name, p.label;
$$;

-- Remove the now-unused placeholder dashboard seeded in the previous
-- migration — nothing was ever attached to it (verified empty), and it
-- would otherwise sit as dead clutter in the admin Dashboards picker.
DELETE FROM rep_portal.dashlet_groups WHERE dashboard_id = (SELECT id FROM rep_portal.dashboards WHERE key = 'main');
DELETE FROM rep_portal.dashlet_categories WHERE dashboard_id = (SELECT id FROM rep_portal.dashboards WHERE key = 'main');
DELETE FROM rep_portal.dashboards WHERE key = 'main';


-- ===== 20260721071732_backfill_uncategorized_category.sql =====
-- get_main_dashboard_dashlets() falls back to each dashboard's "Uncategorized"
-- placeholder category for groups with no category_id — but that placeholder
-- was only ever seeded for the (now-removed) 'main' dashboard. Every other
-- existing dashboard (KPI, Salesforce) has none, so the fallback silently
-- resolved to NULL instead of "Uncategorized". Backfill one per dashboard
-- that's missing it, and seed it automatically for any future dashboard so
-- this can't recur — mirrors the existing "every dashboard needs its own
-- _ungrouped_* placeholder group" invariant.

INSERT INTO rep_portal.dashlet_categories (name, dashboard_id, is_uncategorized, display_order)
SELECT 'Uncategorized', d.id, true, 999999
FROM rep_portal.dashboards d
WHERE NOT EXISTS (
  SELECT 1 FROM rep_portal.dashlet_categories c
  WHERE c.dashboard_id = d.id AND c.is_uncategorized = true
);


-- ===== 20260721072201_hide_uncategorized_from_main_dashboard.sql =====
-- Per explicit direction: "uncategorised must not be visible on the
-- dashboard." Mirrors the existing g.is_ungrouped = false filter — a
-- dashlet whose group has no real category assigned yet is hidden from the
-- Main Dashboard entirely (not shown under a fallback "Uncategorized"
-- bucket) until an admin assigns one via the Categories/Groups tabs.
--
-- The dashlet_categories.is_uncategorized placeholder row itself is
-- unchanged and still needed — it's what ON DELETE SET NULL grants would
-- otherwise dangle against, and a future admin UI may still want to list
-- "unassigned groups" using it. This migration only changes what the public
-- get_main_dashboard_dashlets() RPC returns.

CREATE OR REPLACE FUNCTION rep_portal.get_main_dashboard_dashlets(p_dashboard_id INTEGER DEFAULT NULL)
RETURNS TABLE (
  permission_key          TEXT,
  label                   TEXT,
  description             TEXT,
  category_id             INTEGER,
  category_name           TEXT,
  category_display_order  INTEGER,
  group_id                INTEGER,
  group_name              TEXT,
  group_display_order     INTEGER,
  chart_type              TEXT,
  display_mode            TEXT,
  kpi_id                  TEXT,
  kpi_disagg1_filters     TEXT[],
  kpi_disagg2_filters     TEXT[],
  kpi_split_mode          TEXT,
  show_milestone          BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
  SELECT
    p.key,
    p.label,
    p.description,
    c.id,
    c.name,
    c.display_order,
    d.group_id,
    g.name,
    g.display_order,
    d.chart_type,
    d.display_mode,
    pmm.metric_id,
    pmm.kpi_disagg1_filters,
    pmm.kpi_disagg2_filters,
    pmm.kpi_split_mode,
    pmm.show_milestone
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.permission_metric_map pmm ON pmm.permission_key = p.key AND pmm.metric_config_id IS NULL
  JOIN rep_portal.dashlet_groups g ON g.id = d.group_id
  JOIN rep_portal.dashlet_categories c ON c.id = g.category_id AND c.is_uncategorized = false
  WHERE p.category = 'dashlet'
    AND d.dashboard_id = COALESCE(p_dashboard_id, rep_portal.default_dashboard_id('kpi'))
    AND d.chart_type IS NOT NULL
    AND d.status = 'published'
    AND pmm.metric_id IS NOT NULL
    AND g.is_ungrouped = false
  ORDER BY COALESCE(c.display_order, 999999), c.name, COALESCE(g.display_order, 999999), g.name, p.label;
$$;


-- ===== 20260721090100_add_get_last_complete_kpi_year.sql =====
-- Helper for cumulative KPI dashlets: resolve "the last fully-complete year" of KPI data,
-- so cumulative totals never surface a partial in-progress year's number.
--
-- KPI data (rep_warehouse.fact_observed_kpi) is uploaded per-year via kpi_upload_all(), one
-- successful rep_raw.upload_log row per year. A year only counts as "complete" once a LATER
-- year's upload has also started -- that's the only signal available that the year in
-- question is truly finished, not still being worked on. Falls back to the newest uploaded
-- year when there's nothing later to compare against yet (single-year history so far, or a
-- brand-new environment -> NULL, handled gracefully by callers).
--
-- rep_raw.level_one_upload_log is NOT considered here -- it has no year column at all (it's a
-- whole-file upsert log for a separate fact table, fact_level_one_kpis, that this function's
-- callers never touch).

CREATE OR REPLACE FUNCTION rep_portal.get_last_complete_kpi_year()
RETURNS integer
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, rep_raw, pg_temp
AS $$
  SELECT COALESCE(
    (SELECT MAX(u1.year) FROM rep_raw.upload_log u1
      WHERE u1.status = 'SUCCESS'
        AND EXISTS (SELECT 1 FROM rep_raw.upload_log u2
                    WHERE u2.status = 'SUCCESS' AND u2.year > u1.year)),
    (SELECT MAX(year) FROM rep_raw.upload_log WHERE status = 'SUCCESS')
  );
$$;

REVOKE ALL ON FUNCTION rep_portal.get_last_complete_kpi_year() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_last_complete_kpi_year() TO authenticated, anon;


-- ===== 20260721090200_kpi_mapping_add_is_cumulative.sql =====
-- Add a first-class "is this a cumulative dashlet" flag to rep_portal.kpi_mapping, so cumulative
-- rows can be identified reliably instead of inferring it from disaggregation text.
--
-- The "Cumulative..." text does NOT consistently live in disaggregation_level_one -- across the
-- 8 existing cumulative rows it's split roughly 50/50 between disaggregation_level_one
-- (Bursaries, Jobs Created, New Businesses) and disaggregation_level_two (Learner Guides,
-- Agriculture/Business Guide). The one column that IS consistent across all 8 is `toggle`
-- (always exactly 'Cumulative 2020-2030' / 'Cumulative All-time' regardless of which
-- disaggregation column carries the text), so is_cumulative is derived from toggle.
--
-- CONFIRMED via a live query against rep_warehouse.view_observed_kpi (disaggregation_level_one
-- ILIKE 'cumulative%'): kpi_mapping's cumulative rows use the WRONG label text. Real stored
-- values are 'Cumulative since 2020' / 'Cumulative since 2024' / 'Cumulative all-time' (and a
-- bare 'Cumulative' for kpi_id 2.1, unmapped) -- never the parenthesized
-- 'Cumulative (2020-2030)' / 'Cumulative (all-time)' style kpi_mapping was seeded with. This is
-- the same class of bug already hit and fixed once for a different table in
-- 20260710154248_fix_cumulative_kpi_dashboard_metrics.sql. Every cumulative dashlet_element is
-- therefore silently returning zero rows today, independent of any year-selection logic --
-- fixed here alongside adding is_cumulative so both land together.

ALTER TABLE rep_portal.kpi_mapping ADD COLUMN is_cumulative boolean NOT NULL DEFAULT false;

UPDATE rep_portal.kpi_mapping
SET is_cumulative = true,
    disaggregation_level_one = CASE disaggregation_level_one
      WHEN 'Cumulative (2020-2030)' THEN 'Cumulative since 2020'
      WHEN 'Cumulative (all-time)'  THEN 'Cumulative all-time'
      ELSE disaggregation_level_one
    END,
    disaggregation_level_two = CASE disaggregation_level_two
      WHEN 'Cumulative (2020-2030)' THEN 'Cumulative since 2020'
      WHEN 'Cumulative (all-time)'  THEN 'Cumulative all-time'
      ELSE disaggregation_level_two
    END
WHERE toggle IN ('Cumulative 2020-2030', 'Cumulative All-time');


-- ===== 20260721090300_backfill_get_dashlet_data.sql =====
-- Backfill: rep_portal.get_dashlet_data() has been live on this project since before this
-- migration existed -- created directly against the database (Studio/SQL editor), never
-- through a migration file. Confirmed via pg_get_functiondef('rep_portal.get_dashlet_data'::regproc)
-- and information_schema.routine_privileges. This is a verbatim capture, no behavior change --
-- it just brings the already-live function under version control for the first time, matching
-- the same trap and fix already applied once to rep_portal.kpi_mapping itself
-- (see 20260616235959_add_kpi_mapping_table.sql).
--
-- Powers the Data Dashboard's KPI cards: joins rep_portal.kpi_mapping to
-- rep_warehouse.view_observed_kpi to return the rows a given set of dashlet_element ids need,
-- for a given year range.

CREATE OR REPLACE FUNCTION rep_portal.get_dashlet_data(p_dashlet_elements integer[], p_start_year integer, p_end_year integer)
 RETURNS TABLE(dashlet_element integer, data_element text, toggle text, country text, kpi_id text, disaggregation_level_one text, disaggregation_level_two text, year integer, year_quarter integer, row_scope text, value text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'rep_portal', 'rep_warehouse', 'public'
AS $function$
  SELECT
    m.dashlet_element,
    m.data_element,
    m.toggle,
    k.country,
    k.kpi_id,
    k.disaggregation_level_one,
    k.disaggregation_level_two,
    k.year::int,
    k.year_quarter::int,
    k.row_scope,
    k.value::text
  FROM rep_portal.kpi_mapping m
  JOIN rep_warehouse.view_observed_kpi k
    ON  k.kpi_id = m.kpi_id
    AND (m.disaggregation_level_one IS NULL
         OR k.disaggregation_level_one = m.disaggregation_level_one)
    AND (m.disaggregation_level_two IS NULL
         OR k.disaggregation_level_two = m.disaggregation_level_two)
  WHERE m.dashlet_element = ANY(p_dashlet_elements)
    AND k.year BETWEEN p_start_year AND p_end_year
$function$
;

-- Confirmed live grants: postgres (owner), authenticated, anon -- no PUBLIC grant. A fresh
-- CREATE FUNCTION grants EXECUTE to PUBLIC by default, so revoke it explicitly to match.
REVOKE ALL ON FUNCTION rep_portal.get_dashlet_data(integer[], integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_dashlet_data(integer[], integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_dashlet_data(integer[], integer, integer) TO anon;


-- ===== 20260721090400_get_dashlet_data_use_last_complete_year.sql =====
-- Make get_dashlet_data resolve cumulative dashlets to the last fully-complete year's row,
-- instead of pulling every row in whatever year range the frontend happened to request.
--
-- Cumulative KPI rows (rep_portal.kpi_mapping.is_cumulative = true, added in
-- 20260721090200_kpi_mapping_add_is_cumulative.sql) are running totals as of their upload
-- year, not per-year deltas -- kpi_upload_all() does a year-scoped replace, so a KPI with
-- cumulative data uploaded in 2023/2024/2025 has three separate rows, each a bigger running
-- total. The frontend sums every row a dashlet_element's query returns
-- (sumDashletByCountry() in useDashletData.ts), so requesting a wide year range for a
-- cumulative element (e.g. the "cumulative all-time" UI path's p_start_year=0/p_end_year=9999)
-- would double/triple-count once more than one year of cumulative data exists.
--
-- Fix: for is_cumulative rows, ignore p_start_year/p_end_year entirely and resolve to the
-- single most recent row at-or-before rep_portal.get_last_complete_kpi_year() -- "at-or-before"
-- rather than an exact match, since a cumulative total that hasn't been re-uploaded this year
-- is still an accurate as-of-last-upload number, not a wrong one. The
-- COALESCE(..., kk.year) guard keeps this from suppressing all cumulative rows on a fresh
-- database with no upload_log history yet (get_last_complete_kpi_year() returns NULL there).
--
-- Non-cumulative rows are completely unchanged -- same p_start_year/p_end_year range as before.
-- Requires zero frontend changes: whatever year range a section component sends, cumulative
-- dashlet_elements now always collapse server-side to exactly one row per country.

CREATE OR REPLACE FUNCTION rep_portal.get_dashlet_data(p_dashlet_elements integer[], p_start_year integer, p_end_year integer)
 RETURNS TABLE(dashlet_element integer, data_element text, toggle text, country text, kpi_id text, disaggregation_level_one text, disaggregation_level_two text, year integer, year_quarter integer, row_scope text, value text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'rep_portal', 'rep_warehouse', 'public'
AS $function$
  SELECT
    m.dashlet_element,
    m.data_element,
    m.toggle,
    k.country,
    k.kpi_id,
    k.disaggregation_level_one,
    k.disaggregation_level_two,
    k.year::int,
    k.year_quarter::int,
    k.row_scope,
    k.value::text
  FROM rep_portal.kpi_mapping m
  JOIN rep_warehouse.view_observed_kpi k
    ON  k.kpi_id = m.kpi_id
    AND (m.disaggregation_level_one IS NULL
         OR k.disaggregation_level_one = m.disaggregation_level_one)
    AND (m.disaggregation_level_two IS NULL
         OR k.disaggregation_level_two = m.disaggregation_level_two)
  WHERE m.dashlet_element = ANY(p_dashlet_elements)
    AND (
      (NOT m.is_cumulative AND k.year BETWEEN p_start_year AND p_end_year)
      OR
      (m.is_cumulative AND k.year = (
         SELECT MAX(kk.year)
         FROM rep_warehouse.view_observed_kpi kk
         WHERE kk.kpi_id = m.kpi_id
           AND (m.disaggregation_level_one IS NULL
                OR kk.disaggregation_level_one = m.disaggregation_level_one)
           AND (m.disaggregation_level_two IS NULL
                OR kk.disaggregation_level_two = m.disaggregation_level_two)
           AND kk.year <= COALESCE(rep_portal.get_last_complete_kpi_year(), kk.year)
      ))
    )
$function$
;

-- Grants unchanged from 20260721090300_backfill_get_dashlet_data.sql (CREATE OR REPLACE
-- preserves existing grants on the same function signature) -- no REVOKE/GRANT needed here.


-- ===== 20260721100000_add_cumulative_since_2024_kpi_mapping.sql =====
-- Wire 'Cumulative since 2024' for the KPIs confirmed (via a live query joining kpi_mapping to
-- view_observed_kpi on kpi_id + disaggregation_level_two) to actually have that data available:
-- Bursaries (1.1), CAMA (1.2a), New Businesses (2.6), and Business Grants Count/USD (2.8a).
-- Community Champions (1.2b), Active Learner Guides (1.9), Jobs Created (2.9), Enterprise Guides
-- (2.2), and Businesses Supported (2.7) do NOT have confirmed 'since 2024' data and are
-- deliberately left unmapped here -- their cards will correctly show "No data" for this period.
--
-- New dashlet_element ids 91-95 (next available after the highest seeded id, 90).

INSERT INTO rep_portal.kpi_mapping
  (dashlet_element, kpi_id, disaggregation_level_one, disaggregation_level_two, source_table, dashboard_page, data_element, toggle, is_cumulative)
VALUES
  (91, '1.1',  'Cumulative since 2024', 'Girls Total',        'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'Girls Supported in School with Education Bursaries', 'Cumulative since 2024', true),
  (92, '1.2a', 'Cumulative since 2024', 'Girls Total',        'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'CAMA',                                                'Cumulative since 2024', true),
  (93, '2.6',  'Cumulative since 2024', NULL,                 'rep_warehouse.view_observed_kpi', 'Livelihoods: Jobs & Income',       'New Businesses',                                      'Cumulative since 2024', true),
  (94, '2.8a', 'Cumulative since 2024', 'Number of Grants',   'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach',   'Business Grants - Count',                             'Cumulative since 2024', true),
  (95, '2.8a', 'Cumulative since 2024', 'Grants USD value',   'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach',   'Business Grants - USD Value',                         'Cumulative since 2024', true);

SELECT setval('rep_portal.kpi_mapping_id_seq', (SELECT MAX(id) FROM rep_portal.kpi_mapping));


-- ===== 20260721105550_add_category_display_fields.sql =====
-- Lets an admin set a custom public-facing title/description per category,
-- distinct from the category's `name` (which stays the internal label used
-- in the Level dropdown and admin pickers). Generic field names — not
-- hero-specific — since this content could back a different UI spot later
-- without a rename. Both nullable, no backfill: NULL means "fall back to
-- the category name / a generic description" in the frontend.

ALTER TABLE rep_portal.dashlet_categories
  ADD COLUMN display_title TEXT,
  ADD COLUMN description TEXT;

-- get_main_dashboard_dashlets() already has a `description` column (the
-- dashlet's own description, from permissions.description) — the new
-- category fields are aliased category_display_title/category_description
-- to avoid a duplicate RETURNS TABLE column name, matching the existing
-- category_id/category_name/category_display_order prefix convention.

-- CREATE OR REPLACE can't change a function's output column list — must
-- drop first (same requirement documented in
-- 20260719145944_parameterize_dashlet_rpcs_by_dashboard.sql).
DROP FUNCTION IF EXISTS rep_portal.get_main_dashboard_dashlets(INTEGER);

CREATE OR REPLACE FUNCTION rep_portal.get_main_dashboard_dashlets(p_dashboard_id INTEGER DEFAULT NULL)
RETURNS TABLE (
  permission_key           TEXT,
  label                    TEXT,
  description              TEXT,
  category_id              INTEGER,
  category_name            TEXT,
  category_display_order   INTEGER,
  category_display_title   TEXT,
  category_description     TEXT,
  group_id                 INTEGER,
  group_name               TEXT,
  group_display_order      INTEGER,
  chart_type                TEXT,
  display_mode              TEXT,
  kpi_id                    TEXT,
  kpi_disagg1_filters       TEXT[],
  kpi_disagg2_filters       TEXT[],
  kpi_split_mode            TEXT,
  show_milestone            BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
  SELECT
    p.key,
    p.label,
    p.description,
    c.id,
    c.name,
    c.display_order,
    c.display_title,
    c.description,
    d.group_id,
    g.name,
    g.display_order,
    d.chart_type,
    d.display_mode,
    pmm.metric_id,
    pmm.kpi_disagg1_filters,
    pmm.kpi_disagg2_filters,
    pmm.kpi_split_mode,
    pmm.show_milestone
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.permission_metric_map pmm ON pmm.permission_key = p.key AND pmm.metric_config_id IS NULL
  JOIN rep_portal.dashlet_groups g ON g.id = d.group_id
  JOIN rep_portal.dashlet_categories c ON c.id = g.category_id AND c.is_uncategorized = false
  WHERE p.category = 'dashlet'
    AND d.dashboard_id = COALESCE(p_dashboard_id, rep_portal.default_dashboard_id('kpi'))
    AND d.chart_type IS NOT NULL
    AND d.status = 'published'
    AND pmm.metric_id IS NOT NULL
    AND g.is_ungrouped = false
  ORDER BY COALESCE(c.display_order, 999999), c.name, COALESCE(g.display_order, 999999), g.name, p.label;
$$;


-- ===== 20260721151352_add_kpi_trend_chart_visibility.sql =====
-- Admin-curatable visibility for individual charts on the /kpi-trends page.
-- Each chart is one (kpi_group, indicator, disaggregation_level_one,
-- disaggregation_level_two) combo; disaggregation combos aren't a fixed
-- catalog (unlike dim_kpi for indicators), they only exist as distinct values
-- inside view_observed_kpi fact data. Rather than a 4-column composite key,
-- a single derived chart_key string is stored — see
-- rep_warehouse.kpi_trend_chart_key() below, mirrored on the frontend by
-- kpiTrendChartKey() in frontend/src/features/kpi-report/trend-utils.ts.
--
-- Scope: this is specific to the trend charts on /kpi-trends only — it does
-- not touch KPI Dashboard dashlets, the KPI Report snapshot page, or KPI
-- Milestones, which have their own separate visibility mechanisms.
--
-- Enforcement is client-side only (same precedent as the map's dd:* KPI
-- dropdown filtering, documented in CLAUDE.md) — the RPCs below return
-- is_visible on every row for every caller; the frontend filters hidden rows
-- out for non-admins and shows everything (with hide/show controls) for
-- admins who've switched on "Show all charts (incl. hidden)".

CREATE TABLE rep_portal.kpi_trend_chart_visibility (
  chart_key   TEXT PRIMARY KEY,
  is_visible  BOOLEAN NOT NULL DEFAULT true,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE rep_portal.kpi_trend_chart_visibility ENABLE ROW LEVEL SECURITY;
-- No policies — default deny. Writes go through the admin-users edge function
-- (service_role); reads happen only via the SECURITY DEFINER RPCs below.

GRANT ALL ON rep_portal.kpi_trend_chart_visibility TO service_role;

-- Pure key-generating helper, used only from within the SECURITY DEFINER
-- functions below — never invoked directly by a client.
CREATE FUNCTION rep_warehouse.kpi_trend_chart_key(p_kpi_group TEXT, p_indicator TEXT, p_disagg1 TEXT, p_disagg2 TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE
AS $$
  SELECT p_kpi_group || '::' || p_indicator || '::' || COALESCE(p_disagg1, '') || '::' || COALESCE(p_disagg2, '');
$$;

-- Add is_visible to the two existing rep_portal trend wrappers. No WHERE
-- filtering here — every row carries the flag through to the frontend, which
-- decides who actually sees hidden charts.
--
-- Postgres won't let CREATE OR REPLACE change a function's OUT columns, so
-- both must be dropped first.
DROP FUNCTION rep_portal.kpi_report_indicator_trend(TEXT, TEXT, TEXT);
DROP FUNCTION rep_portal.kpi_report_indicator_trend_all_countries(TEXT, TEXT);

CREATE FUNCTION rep_portal.kpi_report_indicator_trend(p_country TEXT, p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  year INTEGER,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  value_type TEXT,
  value TEXT,
  is_visible BOOLEAN
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT t.year, t.disaggregation_level_one, t.disaggregation_level_two, t.value_type, t.value,
         COALESCE(v.is_visible, true)
  FROM rep_warehouse.kpi_report_indicator_trend(p_country, p_kpi_group, p_indicator)
       WITH ORDINALITY AS t(year, disaggregation_level_one, disaggregation_level_two, value_type, value, ord)
  LEFT JOIN rep_portal.kpi_trend_chart_visibility v
    ON v.chart_key = rep_warehouse.kpi_trend_chart_key(p_kpi_group, p_indicator, t.disaggregation_level_one, t.disaggregation_level_two)
  ORDER BY t.ord;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_report_indicator_trend(TEXT, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_report_indicator_trend(TEXT, TEXT, TEXT) TO authenticated;

CREATE FUNCTION rep_portal.kpi_report_indicator_trend_all_countries(p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  country TEXT,
  year INTEGER,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  value_type TEXT,
  value TEXT,
  is_visible BOOLEAN
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT t.country, t.year, t.disaggregation_level_one, t.disaggregation_level_two, t.value_type, t.value,
         COALESCE(v.is_visible, true)
  FROM rep_warehouse.kpi_report_indicator_trend_all_countries(p_kpi_group, p_indicator)
       WITH ORDINALITY AS t(country, year, disaggregation_level_one, disaggregation_level_two, value_type, value, ord)
  LEFT JOIN rep_portal.kpi_trend_chart_visibility v
    ON v.chart_key = rep_warehouse.kpi_trend_chart_key(p_kpi_group, p_indicator, t.disaggregation_level_one, t.disaggregation_level_two)
  ORDER BY t.ord;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_report_indicator_trend_all_countries(TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_report_indicator_trend_all_countries(TEXT, TEXT) TO authenticated;


-- ===== 20260722135314_list_portal_users_add_sort.sql =====
-- Add server-side sort support to list_portal_users.
-- Adds p_sort_key/p_sort_dir, allowlisted via CASE (never dynamic SQL).
-- Defaults (email, asc) preserve the previously hard-coded ORDER BY email.

DROP FUNCTION IF EXISTS rep_portal.list_portal_users(uuid,int,int,text,text,int,text,text);

CREATE OR REPLACE FUNCTION rep_portal.list_portal_users(
  p_caller_id  uuid,
  p_page       int  DEFAULT 1,
  p_page_size  int  DEFAULT 10,
  p_search     text DEFAULT '',
  p_admin_role text DEFAULT '',
  p_role_id    int  DEFAULT NULL,
  p_country    text DEFAULT '',
  p_status     text DEFAULT '',
  p_sort_key   text DEFAULT 'email',
  p_sort_dir   text DEFAULT 'asc'
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
  ),
  sorted AS (
    SELECT *,
      CASE p_sort_key
        WHEN 'admin'         THEN COALESCE(admin_role, '')
        WHEN 'status'        THEN status
        WHEN 'last_sign_in'  THEN to_char(last_sign_in_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US')
        ELSE                      email
      END AS sort_val
    FROM counted
  ),
  paginated AS (
    SELECT * FROM sorted
    ORDER BY
      CASE WHEN p_sort_dir = 'desc' THEN NULL ELSE sort_val END ASC  NULLS LAST,
      CASE WHEN p_sort_dir = 'desc' THEN sort_val END              DESC NULLS LAST
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

REVOKE EXECUTE ON FUNCTION rep_portal.list_portal_users(uuid,int,int,text,text,int,text,text,text,text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.list_portal_users(uuid,int,int,text,text,int,text,text,text,text) TO service_role;


-- ===== 20260722135317_list_whatsapp_users_add_sort.sql =====
-- Add server-side sort support to list_whatsapp_users.
-- Adds p_sort_key/p_sort_dir, allowlisted via CASE (never dynamic SQL).
-- Defaults (created_at, desc) preserve the previously hard-coded ORDER BY created_at DESC.

DROP FUNCTION IF EXISTS rep_portal.list_whatsapp_users(uuid, int, int, text, text);

CREATE OR REPLACE FUNCTION rep_portal.list_whatsapp_users(
  p_caller_id  uuid,
  p_page       int  DEFAULT 1,
  p_page_size  int  DEFAULT 25,
  p_search     text DEFAULT '',
  p_filter     text DEFAULT 'all',
  p_sort_key   text DEFAULT 'created_at',
  p_sort_dir   text DEFAULT 'desc'
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
  ),
  sorted AS (
    SELECT *,
      CASE p_sort_key
        WHEN 'portal_id' THEN portal_id
        WHEN 'phone'      THEN COALESCE(phone, '')
        WHEN 'name'       THEN COALESCE(name, '')
        WHEN 'email'      THEN COALESCE(email, '')
        WHEN 'role_name'  THEN COALESCE(role_name, '')
        ELSE                   to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US')
      END AS sort_val
    FROM counted
  ),
  paginated AS (
    SELECT * FROM sorted
    ORDER BY
      CASE WHEN p_sort_dir = 'desc' THEN NULL ELSE sort_val END ASC  NULLS LAST,
      CASE WHEN p_sort_dir = 'desc' THEN sort_val END              DESC NULLS LAST
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

REVOKE EXECUTE ON FUNCTION rep_portal.list_whatsapp_users(uuid, int, int, text, text, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.list_whatsapp_users(uuid, int, int, text, text, text, text) TO service_role;


-- ===== 20260722135319_list_district_access_add_sort.sql =====
-- Add server-side sort support to list_district_access.
-- Adds p_sort_key/p_sort_dir, allowlisted via CASE (never dynamic SQL).
-- Defaults (created_at, desc) preserve the previously hard-coded ORDER BY created_at DESC.

DROP FUNCTION IF EXISTS rep_portal.list_district_access(uuid, int, int, text, text, text);

CREATE OR REPLACE FUNCTION rep_portal.list_district_access(
  p_caller_id   uuid,
  p_page        int  DEFAULT 1,
  p_page_size   int  DEFAULT 25,
  p_search      text DEFAULT '',
  p_status      text DEFAULT '',
  p_district_id text DEFAULT '',
  p_sort_key    text DEFAULT 'created_at',
  p_sort_dir    text DEFAULT 'desc'
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
      req.portal_id AS requester_portal_id,
      apr.portal_id AS approver_portal_id,
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
  ),
  sorted AS (
    SELECT *,
      CASE p_sort_key
        WHEN 'district_name'    THEN district_name
        WHEN 'status'           THEN status
        WHEN 'decided_at'       THEN to_char(decided_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US')
        WHEN 'rejection_reason' THEN COALESCE(rejection_reason, '')
        WHEN 'requester'        THEN COALESCE(requester_portal_id, '')
        WHEN 'approver'         THEN COALESCE(approver_portal_id, '')
        ELSE                         to_char(created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US')
      END AS sort_val
    FROM counted
  ),
  paginated AS (
    SELECT * FROM sorted
    ORDER BY
      CASE WHEN p_sort_dir = 'desc' THEN NULL ELSE sort_val END ASC  NULLS LAST,
      CASE WHEN p_sort_dir = 'desc' THEN sort_val END              DESC NULLS LAST
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

REVOKE EXECUTE ON FUNCTION rep_portal.list_district_access(uuid, int, int, text, text, text, text, text) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.list_district_access(uuid, int, int, text, text, text, text, text) TO service_role;


-- ===== 20260722204238_add_whatsapp_approver_reminder_throttle.sql =====
-- Throttle column for the "pending approvals" reminder sent to approvers
-- when they next authenticate via Portal ID. Kept as a dedicated column
-- (not session context) because resetSession() wipes context on every
-- completed/abandoned flow, which would otherwise defeat the throttle.
ALTER TABLE rep_portal.whatsapp_bot_sessions
  ADD COLUMN last_approver_reminder_at TIMESTAMPTZ;


-- ===== 20260723000000_dedupe_kpi_mapping_cumulative_since_2024.sql =====
-- rep_portal.kpi_mapping had two identical rows for dashlet_element = 91 (Bursaries,
-- "Cumulative since 2024", kpi_id 1.1, disaggregation_level_one/two both 'Cumulative since
-- 2024'/'Girls Total') -- ids 83 and 88, inserted directly against the live project outside
-- of 20260721100000_add_cumulative_since_2024_kpi_mapping.sql (which only inserts each
-- dashlet_element once). rep_portal.get_dashlet_data()'s JOIN fanned out one real
-- view_observed_kpi row into two output rows per country, and the frontend's
-- sumDashletByCountry() summed both -- doubling every country's "Cumulative since 2024"
-- total on the Bursaries card (confirmed live: Ghana showed 128,664 instead of the real
-- 64,332).
--
-- Deletes duplicates by keeping the lowest id within each
-- (dashlet_element, kpi_id, disaggregation_level_one, disaggregation_level_two, toggle)
-- group, rather than hardcoding id = 88, so this is safe to apply on any environment
-- (including one where the duplicate never existed, or existed under different ids).

DELETE FROM rep_portal.kpi_mapping m
USING rep_portal.kpi_mapping m2
WHERE m.id > m2.id
  AND m.dashlet_element = m2.dashlet_element
  AND m.kpi_id = m2.kpi_id
  AND m.disaggregation_level_one IS NOT DISTINCT FROM m2.disaggregation_level_one
  AND m.disaggregation_level_two IS NOT DISTINCT FROM m2.disaggregation_level_two
  AND m.toggle IS NOT DISTINCT FROM m2.toggle;


-- ===== 20260723010000_wire_cama_and_totals_cumulative.sql =====
-- Wire 'Cumulative since 2020' and 'Cumulative all-time' for the Education Reach cards that
-- were still hardcoded to "no cumulative data" (CAMA_EL/GIRLS_EL/BOYS_EL all repeated their
-- Annual element id for cum2030/cumall in EducationReachSection.tsx) -- confirmed via a live
-- query against view_observed_kpi that real data exists for all of these, with the same
-- disaggregation_level_two casing already used by each card's Annual mapping:
--   - CAMA card combines kpi_id 1.2a ('CAMA') + 1.2b ('Community Champions'), disagg2 'Girls Total'
--   - Total Girls Supported: kpi_id P1, disagg2 'Girls total' (lowercase, matches existing Annual row)
--   - Total Boys Supported:  kpi_id P1, disagg2 'Boys total'
--
-- New dashlet_element ids 96-101 (next available after the highest seeded id, 95).
-- P1 has no 'Cumulative since 2024' rows at all, so cum2024 is correctly left unmapped for the
-- Total Girls/Boys cards (unchanged from the previous migration's scope).

INSERT INTO rep_portal.kpi_mapping
  (dashlet_element, kpi_id, disaggregation_level_one, disaggregation_level_two, source_table, dashboard_page, data_element, toggle, is_cumulative)
VALUES
  (96, '1.2a', 'Cumulative since 2020', 'Girls Total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'CAMA',                 'Cumulative since 2020', true),
  (96, '1.2b', 'Cumulative since 2020', 'Girls Total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'Community Champions',  'Cumulative since 2020', true),
  (97, '1.2a', 'Cumulative all-time',   'Girls Total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'CAMA',                 'Cumulative all-time',   true),
  (97, '1.2b', 'Cumulative all-time',   'Girls Total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'Community Champions',  'Cumulative all-time',   true),
  (98, 'P1',   'Cumulative since 2020', 'Girls total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'Total Girls Supported', 'Cumulative since 2020', true),
  (99, 'P1',   'Cumulative all-time',   'Girls total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'Total Girls Supported', 'Cumulative all-time',   true),
  (100, 'P1',  'Cumulative since 2020', 'Boys total',  'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'Total Boys Supported',  'Cumulative since 2020', true),
  (101, 'P1',  'Cumulative all-time',   'Boys total',  'rep_warehouse.view_observed_kpi', 'Girls Education: Education Reach', 'Total Boys Supported',  'Cumulative all-time',   true);

SELECT setval('rep_portal.kpi_mapping_id_seq', (SELECT MAX(id) FROM rep_portal.kpi_mapping));


-- ===== 20260723020000_wire_remaining_cumulative_dashlets.sql =====
-- Wire cumulative periods for the remaining dashlets confirmed (via live queries against
-- view_observed_kpi, matching each card's existing Annual disaggregation exactly) to have real
-- cumulative data that was never mapped. Covers Leadership & Tertiary (previously had zero
-- period-awareness), and partial gaps in Livelihoods Reach and Learner Guide Programme.
-- New dashlet_element ids 102-124 (next available after 101).
--
-- Genuinely NOT wired here because no real data exists for that specific variant (confirmed via
-- the same live queries, left as documented gaps, not oversights):
--   - 2.1 CAMA Members: only a single bare 'Cumulative' variant exists (not split into
--     since-2020/since-2024/all-time) -- mapped to both cum2030 and cumall below since it's the
--     same underlying running total either way; no cum2024 variant exists.
--   - 2.3 Young Women Supported by Transition Guides, 2.5 Young Women in Tertiary Education:
--     since-2020 + all-time only, no since-2024.
--   - 2.7 Businesses Supported: since-2020 (already wired, elements 46/48) + since-2024 (added
--     here) only, no all-time.
--   - 2.8b Loans: since-2020 only, no since-2024 or all-time.
--   - 2.13 CAMA Members in Leadership Roles: no cumulative data of any kind.
--   - 1.3 Children Receiving Support: 'Cumulative all-time' exists only as a combined
--     (non-gender-split) total, which doesn't fit the two per-gender cards -- left unmapped.

INSERT INTO rep_portal.kpi_mapping
  (dashlet_element, kpi_id, disaggregation_level_one, disaggregation_level_two, source_table, dashboard_page, data_element, toggle, is_cumulative)
VALUES
  -- CAMA Members (2.1) -- single 'Cumulative' variant reused for both cum2030 and cumall
  (102, '2.1', 'Cumulative', NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Leadership & Tertiary', 'CAMA Members', 'Cumulative since 2020', true),
  (103, '2.1', 'Cumulative', NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Leadership & Tertiary', 'CAMA Members', 'Cumulative all-time', true),

  -- Active Transition Guides (2.2, disaggregation_level_one = 'Transition Guides')
  (104, '2.2', 'Transition Guides', 'Cumulative since 2020', 'rep_warehouse.view_observed_kpi', 'Girls Education: Leadership & Tertiary', 'Active Transition Guides', 'Cumulative since 2020', true),
  (105, '2.2', 'Transition Guides', 'Cumulative all-time',   'rep_warehouse.view_observed_kpi', 'Girls Education: Leadership & Tertiary', 'Active Transition Guides', 'Cumulative all-time', true),
  (106, '2.2', 'Transition Guides', 'Cumulative since 2024', 'rep_warehouse.view_observed_kpi', 'Girls Education: Leadership & Tertiary', 'Active Transition Guides', 'Cumulative since 2024', true),

  -- Young Women Supported by Transition Guides (2.3)
  (107, '2.3', 'Cumulative since 2020', NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Leadership & Tertiary', 'Young Women Supported by Transition Guides', 'Cumulative since 2020', true),
  (108, '2.3', 'Cumulative all-time',   NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Leadership & Tertiary', 'Young Women Supported by Transition Guides', 'Cumulative all-time', true),

  -- Young Women in Tertiary Education (2.5)
  (109, '2.5', 'Cumulative since 2020', NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Leadership & Tertiary', 'Young Women in Tertiary Education', 'Cumulative since 2020', true),
  (110, '2.5', 'Cumulative all-time',   NULL, 'rep_warehouse.view_observed_kpi', 'Girls Education: Leadership & Tertiary', 'Young Women in Tertiary Education', 'Cumulative all-time', true),

  -- Active Enterprise Guides -- Agriculture (2.2, disaggregation_level_one = 'Agriculture Guides')
  (111, '2.2', 'Agriculture Guides', 'Cumulative since 2020', 'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Active Enterprise Guides - Agriculture', 'Cumulative since 2020', true),
  (112, '2.2', 'Agriculture Guides', 'Cumulative all-time',   'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Active Enterprise Guides - Agriculture', 'Cumulative all-time', true),
  (113, '2.2', 'Agriculture Guides', 'Cumulative since 2024', 'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Active Enterprise Guides - Agriculture', 'Cumulative since 2024', true),

  -- Active Enterprise Guides -- Business (2.2, disaggregation_level_one = 'Business Guides')
  (114, '2.2', 'Business Guides', 'Cumulative since 2020', 'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Active Enterprise Guides - Business', 'Cumulative since 2020', true),
  (115, '2.2', 'Business Guides', 'Cumulative all-time',   'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Active Enterprise Guides - Business', 'Cumulative all-time', true),
  (116, '2.2', 'Business Guides', 'Cumulative since 2024', 'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Active Enterprise Guides - Business', 'Cumulative since 2024', true),

  -- Businesses Supported (2.7) -- since-2020 already wired (elements 46/48); since-2024 added here
  (117, '2.7', 'Agriculture Guide', 'Cumulative since 2024', 'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Businesses Supported - Agriculture', 'Cumulative since 2024', true),
  (118, '2.7', 'Business Guide',    'Cumulative since 2024', 'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Businesses Supported - Business', 'Cumulative since 2024', true),

  -- Loans (2.8b) -- since-2020 only, disaggregation_level_two carries the loan-type category
  (119, '2.8b', 'Cumulative since 2020', 'Number of Kiva Loans',                        'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Loans - Kiva Count', 'Cumulative since 2020', true),
  (120, '2.8b', 'Cumulative since 2020', 'Number of Revolving Investment Fund loans',   'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Loans - RIF Count',  'Cumulative since 2020', true),
  (121, '2.8b', 'Cumulative since 2020', 'All loans USD value',                         'rep_warehouse.view_observed_kpi', 'Livelihoods: Livelihoods Reach', 'Loans - USD Value',  'Cumulative since 2020', true),

  -- Active Learner Guides (1.9, disaggregation_level_two = 'Cumulative since 2024', matching the
  -- existing Total/Cumulative since 2020/all-time rows at dashlet_element 23/24)
  (122, '1.9', 'Total', 'Cumulative since 2024', 'rep_warehouse.view_observed_kpi', 'Girls Education: Learner Guide Programme', 'Active Learner Guides', 'Cumulative since 2024', true),

  -- Children Receiving Support -- Girls/Boys (1.3): Cumulative since 2020 only, split by gender
  -- (disaggregation_level_two 'Girls total'/'Boys total', matching the existing Annual rows).
  (123, '1.3', 'Cumulative since 2020', 'Girls total', 'rep_warehouse.view_observed_kpi', 'Girls Education: Learner Guide Programme', 'Children Receiving Support - Girls', 'Cumulative since 2020', true),
  (124, '1.3', 'Cumulative since 2020', 'Boys total',  'rep_warehouse.view_observed_kpi', 'Girls Education: Learner Guide Programme', 'Children Receiving Support - Boys',  'Cumulative since 2020', true);

SELECT setval('rep_portal.kpi_mapping_id_seq', (SELECT MAX(id) FROM rep_portal.kpi_mapping));


-- ===== 20260723163119_add_dashlet_comment_direct_edit.sql =====
-- Stopgap "quick edit" comment tool for KPI dashlets, deliberately separate
-- from the comprehensive dashlets editor's draft/publish workflow
-- (rep_portal.set_dashlet_comment / dashlet_drafts, see
-- 20260719062751_update_dashlet_comment_rpcs_status_staging.sql). That
-- migration closed the direct-write path so staged edits couldn't be
-- silently bypassed — this migration reopens exactly that bypass, on
-- purpose, as an interim admin page until the full editor's staging flow is
-- trusted for comment-only edits. Writes here go straight to the live
-- rep_portal.dashlets row: no draft, no publish step.
--
-- KPI dashlets only — Salesforce dashlets are out of scope for this tool.

-- ── Read RPC — powers the quick-edit admin page ────────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.get_dashlets_for_comment_edit()
RETURNS TABLE (
  permission_key      TEXT,
  label               TEXT,
  group_id            INTEGER,
  group_name          TEXT,
  group_display_order INTEGER,
  comment             TEXT,
  comment_enabled     BOOLEAN
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
  SELECT
    p.key,
    p.label,
    d.group_id,
    g.name,
    g.display_order,
    d.comment,
    d.comment_enabled
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.dashlet_groups g ON g.id = d.group_id
  WHERE p.category = 'dashlet'
    AND d.source_type = 'kpi'
  ORDER BY COALESCE(g.display_order, 999999), g.name NULLS LAST, p.label;
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_dashlets_for_comment_edit() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_dashlets_for_comment_edit() TO authenticated;

-- ── Write RPC — direct publish, no staging ──────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.set_dashlet_comment_direct(
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
  v_dashlet  rep_portal.dashlets;
  v_perm     rep_portal.permissions;
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  SELECT * INTO v_dashlet FROM rep_portal.dashlets WHERE permission_key = p_permission_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unknown permission_key: %', p_permission_key;
  END IF;
  SELECT * INTO v_perm FROM rep_portal.permissions WHERE key = p_permission_key;

  SELECT jsonb_build_object(
    'key', v_perm.key,
    'label', v_perm.label,
    'comment', v_dashlet.comment,
    'comment_enabled', v_dashlet.comment_enabled,
    'edited_via', 'quick_comment_edit'
  ) INTO v_snapshot;

  INSERT INTO rep_portal.entity_history (entity_type, entity_key, change_type, snapshot, changed_by)
  VALUES ('dashlet', p_permission_key, 'update', v_snapshot, auth.uid());

  UPDATE rep_portal.dashlets
  SET comment         = p_comment,
      comment_enabled = p_is_enabled,
      updated_by      = auth.uid()
  WHERE permission_key = p_permission_key;
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.set_dashlet_comment_direct(TEXT, TEXT, BOOLEAN) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.set_dashlet_comment_direct(TEXT, TEXT, BOOLEAN) TO authenticated;


-- ===== 20260723175147_fix_mixed_source_type_dashlets.sql =====
-- Data fix, not a schema change. `dashlet:*` permission keys are the Main
-- Dashboard (SubLevelCharts.tsx) namespace and must always be source_type
-- = 'kpi' — `dd:*` is the separate namespace for Salesforce-driven Dynamic
-- Data / Map cards. Three dashlet:* rows had drifted onto the Salesforce
-- Dashboard (dashboard_id 2, source_type 'salesforce', draft, never
-- actually configured — chart_type IS NULL on all of them) instead of
-- living on the KPI Dashboard in their real Education Reach / Learner
-- Guide Programme group, which is why they were invisible to
-- rep_portal.get_dashlets_for_comment_edit() (scoped to source_type =
-- 'kpi') despite still rendering as real, permission-gated cards on the
-- live dashboard via DashletCommentIcon. Both the KPI Dashboard and
-- Salesforce Dashboard are still unreleased (nav hidden behind
-- SHOW_PENDING_APPROVAL_NAV = false), so moving a dashlet between them
-- here doesn't affect anything user-facing yet.
--
-- Two of the three (education_reach:cama_community, learner_guide:active_guides)
-- carry a permission_metric_map row wired to a Salesforce metric_config_id —
-- that wiring is meaningless once source_type flips to 'kpi' (the KPI-side
-- queries only ever read metric_id where metric_config_id IS NULL), so it's
-- removed rather than left dangling. Both dashlets end up unconfigured
-- (no chart_type, draft) in the correct kpi group, same as
-- education_reach:bursaries already was — an admin can wire a real KPI
-- metric_id to them later via the full Dashlets editor.
--
-- dashlet:munya was an unrelated personal test dashlet (its own group
-- "MunyaG", two metric_config_id links) — removed entirely per explicit
-- confirmation, along with its now-empty group.
--
-- Written to be idempotent across environments with diverged seed data:
-- local dev already had education_reach:bursaries correctly on the KPI
-- Dashboard, so re-applying the same target state to it is a no-op.

DELETE FROM rep_portal.permission_metric_map
WHERE permission_key IN ('dashlet:education_reach:cama_community', 'dashlet:learner_guide:active_guides');

UPDATE rep_portal.dashlets
SET source_type  = 'kpi',
    dashboard_id = (SELECT id FROM rep_portal.dashboards WHERE key = 'kpi'),
    group_id     = (SELECT id FROM rep_portal.dashlet_groups WHERE name = 'Education Reach' AND dashboard_id = (SELECT id FROM rep_portal.dashboards WHERE key = 'kpi'))
WHERE permission_key IN ('dashlet:education_reach:bursaries', 'dashlet:education_reach:cama_community');

UPDATE rep_portal.dashlets
SET source_type  = 'kpi',
    dashboard_id = (SELECT id FROM rep_portal.dashboards WHERE key = 'kpi'),
    group_id     = (SELECT id FROM rep_portal.dashlet_groups WHERE name = 'Learner Guide Programme' AND dashboard_id = (SELECT id FROM rep_portal.dashboards WHERE key = 'kpi'))
WHERE permission_key = 'dashlet:learner_guide:active_guides';

-- rep_portal.permissions -> dashlets -> permission_metric_map / dashlet_comments
-- / role_permissions all cascade on delete, so removing the permission row
-- is enough to fully remove dashlet:munya everywhere.
DELETE FROM rep_portal.permissions WHERE key = 'dashlet:munya';

DELETE FROM rep_portal.dashlet_groups WHERE name = 'MunyaG';


-- ===== 20260723180017_remove_stray_chidren_supported_dashlet.sql =====
-- Data fix. "dashlet:chidren-supported" (label "Children Supported CAMA",
-- Education Reach group) is a stray, typo-keyed permission — it isn't
-- referenced anywhere in the hardcoded Main Dashboard components
-- (SubLevelCharts.tsx or any *Section.tsx), no role is granted it, and it
-- duplicates dashlet:education_reach:total_girls/total_boys. Left in place
-- it would confuse admins using the dashlet-comments quick-edit tool with a
-- card that doesn't actually exist on the dashboard. Only present on the
-- linked remote, not local dev — the DELETE is a no-op there.
--
-- rep_portal.permissions -> dashlets -> permission_metric_map / dashlet_comments
-- / role_permissions all cascade on delete, so removing the permission row
-- is enough to fully remove it everywhere.
DELETE FROM rep_portal.permissions WHERE key = 'dashlet:chidren-supported';


-- ===== 20260723180532_set_dashlet_comment_direct_publishes_status.sql =====
-- rep_portal.get_dashlet_comments() (the read path the live dashboard uses,
-- via useDashletComments.ts) only returns a dashlet's comment when
-- status = 'published' — set_dashlet_comment_direct() wrote comment/
-- comment_enabled straight to the live row but never touched status, so a
-- comment saved via the quick-edit tool on a still-'draft' dashlet (e.g.
-- dashlet:education_reach:bursaries, never actually published through the
-- full editor) silently never appeared on the dashboard. Since this tool's
-- entire premise is "no draft, direct publish," saving a comment here should
-- also flip status to 'published' — one-way only, never un-publish.
--
-- Both affected dashlets (bursaries, cama_community) still have chart_type
-- IS NULL, so this doesn't cause a half-configured chart to start rendering
-- anywhere else (get_kpi_dashlets() / get_kpi_dashlets_admin() require
-- chart_type IS NOT NULL to show a chart) — it only unblocks the comment.

CREATE OR REPLACE FUNCTION rep_portal.set_dashlet_comment_direct(
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
  v_dashlet  rep_portal.dashlets;
  v_perm     rep_portal.permissions;
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'admin only';
  END IF;

  SELECT * INTO v_dashlet FROM rep_portal.dashlets WHERE permission_key = p_permission_key;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'unknown permission_key: %', p_permission_key;
  END IF;
  SELECT * INTO v_perm FROM rep_portal.permissions WHERE key = p_permission_key;

  SELECT jsonb_build_object(
    'key', v_perm.key,
    'label', v_perm.label,
    'comment', v_dashlet.comment,
    'comment_enabled', v_dashlet.comment_enabled,
    'status', v_dashlet.status,
    'edited_via', 'quick_comment_edit'
  ) INTO v_snapshot;

  INSERT INTO rep_portal.entity_history (entity_type, entity_key, change_type, snapshot, changed_by)
  VALUES ('dashlet', p_permission_key, 'update', v_snapshot, auth.uid());

  UPDATE rep_portal.dashlets
  SET comment         = p_comment,
      comment_enabled = p_is_enabled,
      status          = 'published',
      updated_by      = auth.uid()
  WHERE permission_key = p_permission_key;
END;
$$;


-- ===== 20260723180639_publish_pre_fix_direct_comments.sql =====
-- Catch-up for comments saved via the quick-edit tool before
-- set_dashlet_comment_direct() was fixed to also publish status (previous
-- migration). Both rows already have comment/comment_enabled set from that
-- earlier save but are stuck at status = 'draft', so they still don't show
-- on the dashboard via get_dashlet_comments(). One-time catch-up; going
-- forward the RPC itself keeps this in sync on every save.

UPDATE rep_portal.dashlets
SET status = 'published'
WHERE permission_key IN ('dashlet:education_reach:bursaries', 'dashlet:education_reach:cama_community')
  AND comment IS NOT NULL
  AND status = 'draft';


-- ===== 20260723181146_fix_leadership_tertiary_stray_group.sql =====
-- Data fix. dashlet:leadership_tertiary:cama_leadership sat alone in a
-- stray group literally named "dashlet:leadership_tertiary" (a permission
-- key pasted where a human label should be), instead of the real
-- "Leadership & Tertiary" group its 4 sibling dashlets
-- (transition_guides, cama_members, young_women_tg, women_tertiary) use.
-- permissions.parent_key had the same typo. Fixed by name lookup so this is
-- a no-op on environments (e.g. local dev) where the dashlet is already
-- correctly grouped and the stray group doesn't exist.

UPDATE rep_portal.dashlets d
SET group_id = (
  SELECT g2.id FROM rep_portal.dashlet_groups g2
  WHERE g2.name = 'Leadership & Tertiary' AND g2.dashboard_id = d.dashboard_id
)
WHERE d.permission_key = 'dashlet:leadership_tertiary:cama_leadership'
  AND d.group_id IN (SELECT id FROM rep_portal.dashlet_groups WHERE name = 'dashlet:leadership_tertiary');

UPDATE rep_portal.permissions
SET parent_key = 'Leadership & Tertiary'
WHERE key = 'dashlet:leadership_tertiary:cama_leadership'
  AND parent_key = 'dashlet:leadership_tertiary';

DELETE FROM rep_portal.dashlet_groups g
WHERE g.name = 'dashlet:leadership_tertiary'
  AND NOT EXISTS (SELECT 1 FROM rep_portal.dashlets d WHERE d.group_id = g.id);


-- ===== 20260724073654_add_short_label_to_kpi_definitions_load.sql =====
-- Wire short_label (added in 20260710102034_whatsapp_kpi_report.sql, populated so
-- far only via hand-authored one-off backfill migrations) into the normal
-- kpi_definitions.xlsx upload pipeline, as an optional field.
--
-- Blank/missing incoming values must never clobber a short_label already set
-- (whether by the earlier backfill migrations or a previous upload), so the
-- merge is COALESCE(incoming, current) rather than a straight overwrite.

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
    v_inserted             INTEGER := 0;
    v_updated              INTEGER := 0;
    v_skipped              INTEGER := 0;
    v_total                INTEGER := 0;
    v_missing_short_label  INTEGER := 0;
    v_row                  JSONB;
    v_src_id               TEXT;
    v_group                TEXT;
    v_indicator            TEXT;
    v_freq                 TEXT;
    v_start                TEXT;
    v_defn                 TEXT;
    v_short_label          TEXT;
    v_cur_short_label      TEXT;
    v_effective_short_label TEXT;
    v_new_hash             TEXT;
    v_cur_hash             TEXT;
    v_warnings             JSONB := '[]'::jsonb;
BEGIN
    PERFORM set_config('app.batch_id',      p_batch_id,     true);
    PERFORM set_config('app.source_system', 'Excel_CAMFED', true);
    PERFORM set_config('app.source_file',   p_source_file,  true);

    v_total := jsonb_array_length(p_rows);

    FOR v_row IN SELECT * FROM jsonb_array_elements(p_rows) LOOP
        v_src_id      := TRIM(v_row->>'source_kpi_id');
        v_group       := TRIM(v_row->>'kpi_group');
        v_indicator   := TRIM(v_row->>'indicator');
        v_freq        := NULLIF(TRIM(v_row->>'indicator_frequency'), '');
        v_start       := NULLIF(TRIM(v_row->>'indicator_start'),     '');
        v_defn        := NULLIF(TRIM(v_row->>'definition'),          '');
        v_short_label := NULLIF(TRIM(v_row->>'short_label'),         '');

        IF v_src_id IS NULL OR v_src_id = '' THEN
            CONTINUE;
        END IF;

        SELECT lin_business_hash, short_label INTO v_cur_hash, v_cur_short_label
          FROM rep_warehouse.dim_kpi
         WHERE source_kpi_id = v_src_id AND kpi_group = v_group AND scd_is_current = true
         LIMIT 1;

        v_effective_short_label := COALESCE(v_short_label, v_cur_short_label);

        v_new_hash := MD5(concat_ws('||',
            COALESCE(v_src_id,               ''),
            COALESCE(v_group,                ''),
            COALESCE(v_indicator,            ''),
            COALESCE(v_freq,                 ''),
            COALESCE(v_start,                ''),
            COALESCE(v_defn,                 ''),
            COALESCE(v_effective_short_label, '')
        ));

        IF v_cur_hash IS NULL THEN
            INSERT INTO rep_warehouse.dim_kpi
                (source_kpi_id, kpi_group, indicator,
                 indicator_frequency, indicator_start, definition, short_label,
                 scd_effective_from, scd_is_current, scd_version,
                 lin_business_hash, lin_load_batch_id,
                 lin_source_system, lin_source_file, lin_inserted_at)
            VALUES
                (v_src_id, v_group, v_indicator,
                 v_freq, v_start, v_defn, v_effective_short_label,
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
                   short_label         = v_effective_short_label,
                   lin_business_hash   = v_new_hash,
                   lin_load_batch_id   = p_batch_id,
                   lin_source_file     = p_source_file
             WHERE source_kpi_id = v_src_id AND kpi_group = v_group AND scd_is_current = true;

            v_updated := v_updated + 1;
        END IF;

        IF v_effective_short_label IS NULL THEN
            v_missing_short_label := v_missing_short_label + 1;
        END IF;
    END LOOP;

    IF v_missing_short_label > 0 THEN
        v_warnings := jsonb_build_array(
            v_missing_short_label || ' definition(s) still missing a Short Label — WhatsApp menus will show the full Indicator text until this is set.'
        );
    END IF;

    RETURN jsonb_build_object(
        'status',        'SUCCESS',
        'total',         v_total,
        'rows_inserted', v_inserted,
        'rows_updated',  v_updated,
        'rows_skipped',  v_skipped,
        'warnings',      v_warnings
    );

EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('status', 'FAILED', 'error', SQLERRM);
END;
$$;

REVOKE EXECUTE ON FUNCTION rep_warehouse.kpi_definitions_load(TEXT, JSONB, TEXT, TEXT) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_warehouse.kpi_definitions_load(TEXT, JSONB, TEXT, TEXT) TO authenticated;

-- ── get_kpi_definitions: expose short_label to the admin UI ─────────────────
-- Adding an OUT column changes the function's return row type, which
-- CREATE OR REPLACE cannot do -- the old signature must be dropped first.

DROP FUNCTION IF EXISTS rep_portal.get_kpi_definitions();

CREATE OR REPLACE FUNCTION rep_portal.get_kpi_definitions()
RETURNS TABLE (
  source_kpi_id        TEXT,
  kpi_group            TEXT,
  indicator            TEXT,
  indicator_frequency  TEXT,
  indicator_start      TEXT,
  definition           TEXT,
  short_label          TEXT
) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public AS $$
  SELECT
    source_kpi_id,
    kpi_group,
    indicator,
    indicator_frequency,
    indicator_start,
    definition,
    short_label
  FROM rep_warehouse.dim_kpi
  WHERE scd_is_current = true
  ORDER BY source_kpi_id;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.get_kpi_definitions() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_kpi_definitions() TO authenticated;


-- ===== 20260724074750_set_short_label_1_1c_safety_net_fund.sql =====
-- Backfill short_label for KPI 1.1c (Programme Metrics) -- missed by the
-- earlier hand-curated backfills (20260710102034, 20260712072056).

UPDATE rep_warehouse.dim_kpi
   SET short_label = 'Safety Net Fund'
 WHERE source_kpi_id = '1.1c'
   AND kpi_group = 'Programme Metrics'
   AND scd_is_current = true;


-- ===== 20260724092059_add_kpi_milestone_chart_visibility.sql =====
-- Admin-curatable visibility for individual charts on the /kpi-milestones
-- page. Each chart is one (kpi_group, indicator, disaggregation_level_one,
-- disaggregation_level_two) combo, same grain as the /kpi-trends visibility
-- table (rep_portal.kpi_trend_chart_visibility) — a single derived chart_key
-- string is stored, generated by rep_warehouse.kpi_milestone_chart_key()
-- below, mirrored on the frontend by kpiMilestoneChartKey() in
-- frontend/src/features/kpi-report/trend-utils.ts.
--
-- Scope: this is specific to /kpi-milestones only — a separate table from
-- kpi_trend_chart_visibility, per the scope note in
-- 20260721151352_add_kpi_trend_chart_visibility.sql.
--
-- Enforcement is client-side only, same precedent as KPI Trends — the RPC
-- below returns is_visible on every row for every caller; the frontend
-- filters hidden rows out for non-admins and shows everything (with
-- hide/show controls) for admins who've switched on "Show hidden charts".

CREATE TABLE rep_portal.kpi_milestone_chart_visibility (
  chart_key   TEXT PRIMARY KEY,
  is_visible  BOOLEAN NOT NULL DEFAULT true,
  updated_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);

ALTER TABLE rep_portal.kpi_milestone_chart_visibility ENABLE ROW LEVEL SECURITY;
-- No policies — default deny. Writes go through the admin-users edge function
-- (service_role); reads happen only via the SECURITY DEFINER RPC below.

GRANT ALL ON rep_portal.kpi_milestone_chart_visibility TO service_role;

-- Pure key-generating helper, used only from within the SECURITY DEFINER
-- function below — never invoked directly by a client.
CREATE FUNCTION rep_warehouse.kpi_milestone_chart_key(p_kpi_group TEXT, p_indicator TEXT, p_disagg1 TEXT, p_disagg2 TEXT)
RETURNS TEXT
LANGUAGE sql IMMUTABLE
AS $$
  SELECT p_kpi_group || '::' || p_indicator || '::' || COALESCE(p_disagg1, '') || '::' || COALESCE(p_disagg2, '');
$$;

-- Add is_visible to the rep_portal kpi_milestone_report wrapper. No WHERE
-- filtering here — every row carries the flag through to the frontend, which
-- decides who actually sees hidden charts.
--
-- Postgres won't let CREATE OR REPLACE change a function's OUT columns, so
-- the rep_portal wrapper must be dropped first (rep_warehouse.kpi_milestone_report
-- itself is unchanged).
DROP FUNCTION rep_portal.kpi_milestone_report(INTEGER, TEXT, TEXT);

CREATE FUNCTION rep_portal.kpi_milestone_report(p_year INTEGER, p_kpi_group TEXT, p_indicator TEXT)
RETURNS TABLE (
  country TEXT,
  disaggregation_level_one TEXT,
  disaggregation_level_two TEXT,
  milestone_value NUMERIC,
  actual_value NUMERIC,
  value_type TEXT,
  is_visible BOOLEAN
)
LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_warehouse, public
AS $$
  SELECT t.country, t.disaggregation_level_one, t.disaggregation_level_two, t.milestone_value, t.actual_value, t.value_type,
         COALESCE(v.is_visible, true)
  FROM rep_warehouse.kpi_milestone_report(p_year, p_kpi_group, p_indicator)
       WITH ORDINALITY AS t(country, disaggregation_level_one, disaggregation_level_two, milestone_value, actual_value, value_type, ord)
  LEFT JOIN rep_portal.kpi_milestone_chart_visibility v
    ON v.chart_key = rep_warehouse.kpi_milestone_chart_key(p_kpi_group, p_indicator, t.disaggregation_level_one, t.disaggregation_level_two)
  ORDER BY t.ord;
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.kpi_milestone_report(INTEGER, TEXT, TEXT) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.kpi_milestone_report(INTEGER, TEXT, TEXT) TO authenticated;


-- ===== 20260724102759_server_side_pagination_admin_tables.sql =====
-- Convert 5 unbounded, ever-growing admin history tables from client-side
-- pagination (fetch-all + slice in browser) to real server-side LIMIT/OFFSET
-- paging, following the get_all_kpi_rows/count_all_kpi_rows pattern.

-- ── Ingest run history ────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS rep_portal.get_ingest_runs();

CREATE FUNCTION rep_portal.get_ingest_runs(p_limit INTEGER DEFAULT 20, p_offset INTEGER DEFAULT 0)
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
    LIMIT p_limit OFFSET p_offset;
END;
$$;

CREATE OR REPLACE FUNCTION rep_portal.count_ingest_runs()
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = rep_warehouse, public
AS $$
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin privileges required';
  END IF;
  RETURN (SELECT count(*) FROM rep_warehouse.ingest_run);
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_ingest_runs(INTEGER, INTEGER) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_ingest_runs(INTEGER, INTEGER) TO authenticated;
REVOKE ALL ON FUNCTION rep_portal.count_ingest_runs() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.count_ingest_runs() TO authenticated;

-- ── KPI upload history ────────────────────────────────────────────────────

DROP FUNCTION IF EXISTS rep_portal.get_upload_log();

CREATE FUNCTION rep_portal.get_upload_log(p_limit INTEGER DEFAULT 30, p_offset INTEGER DEFAULT 0)
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
  LIMIT p_limit OFFSET p_offset;
$$;

CREATE OR REPLACE FUNCTION rep_portal.count_upload_log()
RETURNS BIGINT LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_raw, public
AS $$
  SELECT count(*) FROM rep_raw.upload_log;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_upload_log(INTEGER, INTEGER) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_upload_log(INTEGER, INTEGER) TO authenticated;
REVOKE ALL ON FUNCTION rep_portal.count_upload_log() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.count_upload_log() TO authenticated;

-- ── Level-1 KPI upload history ────────────────────────────────────────────

DROP FUNCTION IF EXISTS rep_portal.get_level_one_upload_log();

CREATE FUNCTION rep_portal.get_level_one_upload_log(p_limit INTEGER DEFAULT 30, p_offset INTEGER DEFAULT 0)
RETURNS TABLE (
  batch_id     TEXT,
  rows_added   INTEGER,
  rows_updated INTEGER,
  total_rows   INTEGER,
  status       TEXT,
  uploaded_by  TEXT,
  source_file  TEXT,
  inserted_at  TIMESTAMPTZ,
  error_msg    TEXT
) LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_raw, public
AS $$
  SELECT batch_id, rows_added, rows_updated, total_rows,
         status, uploaded_by, source_file, inserted_at, error_msg
  FROM rep_raw.level_one_upload_log
  ORDER BY inserted_at DESC
  LIMIT p_limit OFFSET p_offset;
$$;

CREATE OR REPLACE FUNCTION rep_portal.count_level_one_upload_log()
RETURNS BIGINT LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_raw, public
AS $$
  SELECT count(*) FROM rep_raw.level_one_upload_log;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_level_one_upload_log(INTEGER, INTEGER) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_level_one_upload_log(INTEGER, INTEGER) TO authenticated;
REVOKE ALL ON FUNCTION rep_portal.count_level_one_upload_log() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.count_level_one_upload_log() TO authenticated;

-- ── Milestone upload history ──────────────────────────────────────────────

DROP FUNCTION IF EXISTS rep_portal.get_milestone_upload_log();

CREATE FUNCTION rep_portal.get_milestone_upload_log(p_limit INTEGER DEFAULT 100, p_offset INTEGER DEFAULT 0)
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
SECURITY DEFINER STABLE SET search_path = rep_portal, rep_raw, public
AS $$
  SELECT batch_id, source_file, uploaded_by, rows_loaded, status, error_msg, inserted_at
  FROM rep_raw.milestone_upload_log
  ORDER BY inserted_at DESC
  LIMIT p_limit OFFSET p_offset;
$$;

CREATE OR REPLACE FUNCTION rep_portal.count_milestone_upload_log()
RETURNS BIGINT LANGUAGE sql SECURITY DEFINER STABLE
SET search_path = rep_portal, rep_raw, public
AS $$
  SELECT count(*) FROM rep_raw.milestone_upload_log;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_milestone_upload_log(INTEGER, INTEGER) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_milestone_upload_log(INTEGER, INTEGER) TO authenticated;
REVOKE ALL ON FUNCTION rep_portal.count_milestone_upload_log() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.count_milestone_upload_log() TO authenticated;

-- ── WhatsApp errors ────────────────────────────────────────────────────────
-- Read directly from rep_portal.whatsapp_events instead of view_wa_errors,
-- which is hard-capped at LIMIT 100 and would otherwise cap the paginated
-- count regardless of the true number of error events.

DROP FUNCTION IF EXISTS rep_portal.get_wa_errors();

CREATE FUNCTION rep_portal.get_wa_errors(p_limit INTEGER DEFAULT 100, p_offset INTEGER DEFAULT 0)
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
  RETURN QUERY
    SELECT e.id, e.flow, e.from_step, e.to_step, e.occurred_at
    FROM rep_portal.whatsapp_events e
    WHERE e.outcome = 'error'
    ORDER BY e.occurred_at DESC
    LIMIT p_limit OFFSET p_offset;
END;
$$;

CREATE OR REPLACE FUNCTION rep_portal.count_wa_errors()
RETURNS BIGINT LANGUAGE plpgsql SECURITY DEFINER STABLE
SET search_path = rep_portal, public
AS $$
BEGIN
  IF NOT rep_warehouse.is_admin() THEN
    RAISE EXCEPTION 'Admin privileges required';
  END IF;
  RETURN (SELECT count(*) FROM rep_portal.whatsapp_events WHERE outcome = 'error');
END;
$$;

REVOKE ALL ON FUNCTION rep_portal.get_wa_errors(INTEGER, INTEGER) FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_wa_errors(INTEGER, INTEGER) TO authenticated;
REVOKE ALL ON FUNCTION rep_portal.count_wa_errors() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.count_wa_errors() TO authenticated;


-- ===== 20260729090821_add_kpi_page_permissions.sql =====
-- Add page-level permissions for the KPI viewing pages: page:kpi-report,
-- page:kpi-trends, page:kpi-milestones. These were previously unguarded --
-- visible to every authenticated user regardless of role.

INSERT INTO rep_portal.permissions (key, label, description, category, parent_key)
VALUES
  ('page:kpi-report',     'KPI Report',     'Access to the /kpi-report page',     'page', NULL),
  ('page:kpi-trends',     'KPI Trends',     'Access to the /kpi-trends page',     'page', NULL),
  ('page:kpi-milestones', 'KPI Milestones', 'Access to the /kpi-milestones page', 'page', NULL);

-- Backfill to every existing role so no one loses access they already have
-- today (the pages were unguarded). Roles can be tightened later via the
-- admin Roles UI.
INSERT INTO rep_portal.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM rep_portal.roles r
CROSS JOIN rep_portal.permissions p
WHERE p.key IN ('page:kpi-report', 'page:kpi-trends', 'page:kpi-milestones')
ON CONFLICT (role_id, permission_id) DO NOTHING;


-- ===== 20260729135702_add_per_metric_dynamic_data_permissions.sql =====
-- Per-metric permissions for Dynamic Data.
--
-- Today Dynamic Data access is coarse: one broad dd:salesforce permission
-- (held by zero roles) plus 10 legacy dd:* "card" permissions that each
-- loosely bundle several metrics, 7 of which have no working
-- permission_metric_map row at all. This migration replaces that with one
-- permission per metric_config row.
--
-- permission_metric_map.permission_key now FKs to dashlets.permission_key
-- (not permissions.key directly) because that table also carries KPI
-- dashlet-content columns (kpi_disagg1_filters, kpi_split_mode,
-- show_milestone) for the Dashlets Hub. Reusing it here would force a
-- throwaway dashlets row per permission just to satisfy the FK, and those
-- rows would show up as confusing entries in the Dashlets admin editor
-- (which lists dashlets by permissions.dashboard_id, sourced from that same
-- dashlets row). So instead: a small, dedicated bridge table, structurally
-- identical to what permission_metric_map looked like before the Dashlets
-- Hub repurposed it.

-- ── 1. Dedicated bridge table ───────────────────────────────────────────────

CREATE TABLE rep_portal.permission_metric_config_map (
  permission_key    TEXT    NOT NULL REFERENCES rep_portal.permissions(key) ON DELETE CASCADE,
  metric_config_id  INTEGER NOT NULL REFERENCES rep_portal.metric_config(id) ON DELETE CASCADE,
  PRIMARY KEY (permission_key, metric_config_id)
);

ALTER TABLE rep_portal.permission_metric_config_map ENABLE ROW LEVEL SECURITY;

CREATE POLICY "authenticated can read permission_metric_config_map"
  ON rep_portal.permission_metric_config_map FOR SELECT TO authenticated USING (true);

-- ── 2. One permission per metric_config row (all 26, not just enabled) ─────
-- Visibility on the Roles form is filtered dynamically by the admin-users
-- edge function based on metric_config.enabled, not by which rows exist here
-- — so a currently-disabled metric's permission sits inert until enabled,
-- with no follow-up migration needed then.

INSERT INTO rep_portal.permissions (key, label, category, parent_key) VALUES
  ('dd:metric:children_supported_total', 'Children Supported — Total', 'dashlet', 'Dynamic Data'),
  ('dd:metric:children_supported_girls', 'Children Supported — Girls', 'dashlet', 'Dynamic Data'),
  ('dd:metric:children_supported_boys', 'Children Supported — Boys', 'dashlet', 'Dynamic Data'),
  ('dd:metric:children_supported_bursary_girls', 'Children Supported — Bursary Girls', 'dashlet', 'Dynamic Data'),
  ('dd:metric:children_supported_step_up_fund', 'Children Supported — Step Up Fund', 'dashlet', 'Dynamic Data'),
  ('dd:metric:children_supported_girls_with_disability', 'Children Supported — Girls with Disability', 'dashlet', 'Dynamic Data'),
  ('dd:metric:children_supported_attendance_issues', 'Children Supported — Attendance Issues', 'dashlet', 'Dynamic Data'),
  ('dd:metric:children_supported_repeated_year', 'Children Supported — Repeated Year', 'dashlet', 'Dynamic Data'),
  ('dd:metric:children_supported_received_financial_support', 'Children Supported — Received Financial Support', 'dashlet', 'Dynamic Data'),
  ('dd:metric:active_learner_guides', 'Active Learner Guides', 'dashlet', 'Dynamic Data'),
  ('dd:metric:active_transition_guides', 'Active Transition Guides', 'dashlet', 'Dynamic Data'),
  ('dd:metric:active_enterprise_guides', 'Active Enterprise Guides', 'dashlet', 'Dynamic Data'),
  ('dd:metric:active_community_champions', 'Active Community Champions', 'dashlet', 'Dynamic Data'),
  ('dd:metric:active_learner_mentors', 'Active Learner Mentors', 'dashlet', 'Dynamic Data'),
  ('dd:metric:active_agriculture_guides', 'Active Agriculture Guides', 'dashlet', 'Dynamic Data'),
  ('dd:metric:active_business_guides', 'Active Business Guides', 'dashlet', 'Dynamic Data'),
  ('dd:metric:guides_trained_in_climate_education', 'Guides — Trained in Climate Education', 'dashlet', 'Dynamic Data'),
  ('dd:metric:cama_members', 'CAMA Members', 'dashlet', 'Dynamic Data'),
  ('dd:metric:cama_members_partner_school', 'CAMA Members — Partner School', 'dashlet', 'Dynamic Data'),
  ('dd:metric:cama_members_with_disability', 'CAMA Members — With Disability', 'dashlet', 'Dynamic Data'),
  ('dd:metric:post_school_support_total', 'Post-School Support — Total', 'dashlet', 'Dynamic Data'),
  ('dd:metric:post_school_support_received_financial_support', 'Post-School Support — Received Financial Support', 'dashlet', 'Dynamic Data'),
  ('dd:metric:grants_count', 'Grants — Count', 'dashlet', 'Dynamic Data'),
  ('dd:metric:grants_total_value_usd', 'Grants — Total Value (USD)', 'dashlet', 'Dynamic Data'),
  ('dd:metric:loans_count', 'Loans — Count', 'dashlet', 'Dynamic Data'),
  ('dd:metric:loans_total_value', 'Loans — Total Value', 'dashlet', 'Dynamic Data');

INSERT INTO rep_portal.permission_metric_config_map (permission_key, metric_config_id) VALUES
  ('dd:metric:children_supported_total', 1),
  ('dd:metric:children_supported_girls', 2),
  ('dd:metric:children_supported_boys', 3),
  ('dd:metric:children_supported_bursary_girls', 4),
  ('dd:metric:children_supported_step_up_fund', 5),
  ('dd:metric:children_supported_girls_with_disability', 6),
  ('dd:metric:children_supported_attendance_issues', 7),
  ('dd:metric:children_supported_repeated_year', 8),
  ('dd:metric:children_supported_received_financial_support', 9),
  ('dd:metric:active_learner_guides', 10),
  ('dd:metric:active_transition_guides', 11),
  ('dd:metric:active_enterprise_guides', 12),
  ('dd:metric:active_community_champions', 13),
  ('dd:metric:active_learner_mentors', 14),
  ('dd:metric:active_agriculture_guides', 15),
  ('dd:metric:active_business_guides', 16),
  ('dd:metric:guides_trained_in_climate_education', 17),
  ('dd:metric:cama_members', 18),
  ('dd:metric:cama_members_partner_school', 19),
  ('dd:metric:cama_members_with_disability', 20),
  ('dd:metric:post_school_support_total', 21),
  ('dd:metric:post_school_support_received_financial_support', 22),
  ('dd:metric:grants_count', 23),
  ('dd:metric:grants_total_value_usd', 24),
  ('dd:metric:loans_count', 25),
  ('dd:metric:loans_total_value', 26);

-- ── 3. Scope get_dashboard_data_filtered() and get_dashboard_metadata() ────
-- to union both permission_metric_map (legacy dd:* mappings) and the new
-- permission_metric_config_map, so the new permissions actually unlock real
-- data and dropdown options, not just checkboxes in Roles.

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
    -- Non-admin: intersect requested metrics with permitted metrics via RBAC.
    -- Unions the legacy permission_metric_map (dd:* card permissions) with
    -- the newer, per-metric permission_metric_config_map.
    SELECT ARRAY_AGG(DISTINCT metric_name)
    INTO   v_allowed_metrics
    FROM (
      SELECT mc.metric_name
      FROM   rep_portal.metric_config         mc
      JOIN   rep_portal.permission_metric_map pmm ON pmm.metric_config_id = mc.id
      JOIN   rep_portal.permissions           p   ON p.key                = pmm.permission_key
      JOIN   rep_portal.role_permissions      rp  ON rp.permission_id     = p.id
      JOIN   rep_portal.user_roles            ur  ON ur.role_id           = rp.role_id
      WHERE  ur.user_id  = auth.uid()
        AND  mc.enabled  = true
      UNION
      SELECT mc.metric_name
      FROM   rep_portal.metric_config               mc
      JOIN   rep_portal.permission_metric_config_map pmcm ON pmcm.metric_config_id = mc.id
      JOIN   rep_portal.permissions                  p    ON p.key                = pmcm.permission_key
      JOIN   rep_portal.role_permissions             rp   ON rp.permission_id     = p.id
      JOIN   rep_portal.user_roles                   ur   ON ur.role_id           = rp.role_id
      WHERE  ur.user_id  = auth.uid()
        AND  mc.enabled  = true
    ) allowed
    WHERE (p_metrics IS NULL OR array_length(p_metrics, 1) IS NULL OR metric_name = ANY(p_metrics));
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
      CASE WHEN (auth.jwt()->'app_metadata'->>'role') = 'admin' THEN
        (SELECT COALESCE(json_agg(metric_name ORDER BY sort_order, metric_name), '[]'::json)
         FROM   rep_portal.metric_config
         WHERE  enabled = true)
      ELSE
        (SELECT COALESCE(json_agg(DISTINCT mc.metric_name ORDER BY mc.metric_name), '[]'::json)
         FROM (
           SELECT mc.metric_name
           FROM   rep_portal.metric_config         mc
           JOIN   rep_portal.permission_metric_map pmm ON pmm.metric_config_id = mc.id
           JOIN   rep_portal.permissions           p   ON p.key                = pmm.permission_key
           JOIN   rep_portal.role_permissions      rp  ON rp.permission_id     = p.id
           JOIN   rep_portal.user_roles            ur  ON ur.role_id           = rp.role_id
           WHERE  ur.user_id  = auth.uid()
             AND  mc.enabled  = true
           UNION
           SELECT mc.metric_name
           FROM   rep_portal.metric_config               mc
           JOIN   rep_portal.permission_metric_config_map pmcm ON pmcm.metric_config_id = mc.id
           JOIN   rep_portal.permissions                  p    ON p.key                = pmcm.permission_key
           JOIN   rep_portal.role_permissions             rp   ON rp.permission_id     = p.id
           JOIN   rep_portal.user_roles                   ur   ON ur.role_id           = rp.role_id
           WHERE  ur.user_id  = auth.uid()
             AND  mc.enabled  = true
         ) mc)
      END
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

-- ── 4. Auto-assign every new permission to every existing role ─────────────
-- Bootstraps everyone to full metric visibility on top of whatever legacy
-- dd:* permissions they already hold. Admins narrow individual roles down
-- later via Roles.

INSERT INTO rep_portal.role_permissions (role_id, permission_id)
SELECT r.id, p.id
FROM rep_portal.roles r
CROSS JOIN rep_portal.permissions p
WHERE p.key LIKE 'dd:metric:%'
ON CONFLICT DO NOTHING;

-- ── 5. Delete dd:salesforce ──────────────────────────────────────────────
-- Held by zero roles today, fully superseded by the new per-metric
-- permissions. Cascades its dashlets row and permission_metric_map rows
-- automatically (both ON DELETE CASCADE) — it never used the new table.

DELETE FROM rep_portal.permissions WHERE key = 'dd:salesforce';

-- ── 6. Roles-form-only relabel of the 10 legacy dd:* keys ──────────────────
-- Updates parent_key only — nothing else about these rows changes. The
-- shared dashlet_groups row ("Dynamic Data + Map") is untouched, since it's
-- read directly by the Dashlets admin editor and the live Salesforce
-- Dashboard (dd:guides_by_type is a published chart in that group).

UPDATE rep_portal.permissions SET parent_key = 'Map'
WHERE key IN (
  'dd:active_learner_guides','dd:active_partner_schools','dd:cama_members',
  'dd:children_supported','dd:clients_by_form','dd:grants_disbursed','dd:guides_by_type',
  'dd:loans_disbursed','dd:post_school_clients','dd:women_tertiary'
);


-- ===== 20260729140000_add_update_quarter_to_dashlet_data.sql =====
-- Expose update_quarter on get_dashlet_data() so cumulative dashlet cards (SubLevelCharts'
-- section components, which all read cumulative rows through useDashletData/get_dashlet_data)
-- can show which quarter their totals were last updated as of (e.g. "Update Q1"), per dashlet
-- rather than once for the whole page -- update_quarter is a fact-row-level column (carried
-- through from the uploaded all_kpis file), not a single page-wide value.

-- CREATE OR REPLACE cannot change a function's RETURNS TABLE column list; drop first.
DROP FUNCTION IF EXISTS rep_portal.get_dashlet_data(integer[], integer, integer);

CREATE FUNCTION rep_portal.get_dashlet_data(p_dashlet_elements integer[], p_start_year integer, p_end_year integer)
 RETURNS TABLE(dashlet_element integer, data_element text, toggle text, country text, kpi_id text, disaggregation_level_one text, disaggregation_level_two text, year integer, year_quarter integer, row_scope text, value text, update_quarter text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'rep_portal', 'rep_warehouse', 'public'
AS $function$
  SELECT
    m.dashlet_element,
    m.data_element,
    m.toggle,
    k.country,
    k.kpi_id,
    k.disaggregation_level_one,
    k.disaggregation_level_two,
    k.year::int,
    k.year_quarter::int,
    k.row_scope,
    k.value::text,
    k.update_quarter
  FROM rep_portal.kpi_mapping m
  JOIN rep_warehouse.view_observed_kpi k
    ON  k.kpi_id = m.kpi_id
    AND (m.disaggregation_level_one IS NULL
         OR k.disaggregation_level_one = m.disaggregation_level_one)
    AND (m.disaggregation_level_two IS NULL
         OR k.disaggregation_level_two = m.disaggregation_level_two)
  WHERE m.dashlet_element = ANY(p_dashlet_elements)
    AND (
      (NOT m.is_cumulative AND k.year BETWEEN p_start_year AND p_end_year)
      OR
      (m.is_cumulative AND k.year = (
         SELECT MAX(kk.year)
         FROM rep_warehouse.view_observed_kpi kk
         WHERE kk.kpi_id = m.kpi_id
           AND (m.disaggregation_level_one IS NULL
                OR kk.disaggregation_level_one = m.disaggregation_level_one)
           AND (m.disaggregation_level_two IS NULL
                OR kk.disaggregation_level_two = m.disaggregation_level_two)
           AND kk.year <= COALESCE(rep_portal.get_last_complete_kpi_year(), kk.year)
      ))
    )
$function$
;

-- Dropping the function clears its grants -- reinstate them (same as
-- 20260721090300_backfill_get_dashlet_data.sql).
REVOKE ALL ON FUNCTION rep_portal.get_dashlet_data(integer[], integer, integer) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION rep_portal.get_dashlet_data(integer[], integer, integer) TO authenticated;
GRANT EXECUTE ON FUNCTION rep_portal.get_dashlet_data(integer[], integer, integer) TO anon;


-- ===== 20260729150000_fix_cumulative_dashlet_year_resolution.sql =====
-- Cumulative dashlet cards (get_dashlet_data, is_cumulative branch) were capping their year
-- resolution at rep_portal.get_last_complete_kpi_year() -- the same "wait for a later year to
-- start" gate used for annual/newly-supported cards. That gate exists to stop a partial
-- in-progress year's annual count from understating reality, which is the right call for
-- annual metrics. It's the wrong call for cumulative running totals: a cumulative figure only
-- grows and is never "partial" the way an annual count can be -- the newest uploaded row for a
-- cumulative KPI is its most accurate value, full stop. Capping it at the prior year meant every
-- cumulative dashlet across the app silently displayed last year's running total (and last
-- year's update_quarter) even once the current year's cumulative data had been fully uploaded.
--
-- Fix: drop the get_last_complete_kpi_year() cap from the is_cumulative branch -- just resolve
-- to the true MAX(year) available for that KPI/disaggregation. The non-cumulative branch is
-- unchanged; it doesn't use get_last_complete_kpi_year() at all (it just uses the caller's
-- p_start_year/p_end_year range).

CREATE OR REPLACE FUNCTION rep_portal.get_dashlet_data(p_dashlet_elements integer[], p_start_year integer, p_end_year integer)
 RETURNS TABLE(dashlet_element integer, data_element text, toggle text, country text, kpi_id text, disaggregation_level_one text, disaggregation_level_two text, year integer, year_quarter integer, row_scope text, value text, update_quarter text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'rep_portal', 'rep_warehouse', 'public'
AS $function$
  SELECT
    m.dashlet_element,
    m.data_element,
    m.toggle,
    k.country,
    k.kpi_id,
    k.disaggregation_level_one,
    k.disaggregation_level_two,
    k.year::int,
    k.year_quarter::int,
    k.row_scope,
    k.value::text,
    k.update_quarter
  FROM rep_portal.kpi_mapping m
  JOIN rep_warehouse.view_observed_kpi k
    ON  k.kpi_id = m.kpi_id
    AND (m.disaggregation_level_one IS NULL
         OR k.disaggregation_level_one = m.disaggregation_level_one)
    AND (m.disaggregation_level_two IS NULL
         OR k.disaggregation_level_two = m.disaggregation_level_two)
  WHERE m.dashlet_element = ANY(p_dashlet_elements)
    AND (
      (NOT m.is_cumulative AND k.year BETWEEN p_start_year AND p_end_year)
      OR
      (m.is_cumulative AND k.year = (
         SELECT MAX(kk.year)
         FROM rep_warehouse.view_observed_kpi kk
         WHERE kk.kpi_id = m.kpi_id
           AND (m.disaggregation_level_one IS NULL
                OR kk.disaggregation_level_one = m.disaggregation_level_one)
           AND (m.disaggregation_level_two IS NULL
                OR kk.disaggregation_level_two = m.disaggregation_level_two)
      ))
    )
$function$
;

-- CREATE OR REPLACE keeps existing grants (same signature as the prior migration) -- no
-- REVOKE/GRANT needed here.


-- ===== 20260729174537_fix_permission_metric_config_map_grants.sql =====
-- permission_metric_config_map (added in 20260729135702) got RLS + a SELECT
-- policy for authenticated, but no table-level GRANT — every other new
-- rep_portal table in this schema needs one (GRANT is checked before RLS
-- policies are even evaluated). Missing it caused "permission denied for
-- table permission_metric_config_map" from the admin-users edge function,
-- which reads it as service_role.

GRANT ALL ON rep_portal.permission_metric_config_map TO service_role;
GRANT SELECT ON rep_portal.permission_metric_config_map TO authenticated;


-- ===== 20260730044619_remove_permission_metric_map.sql =====
-- Remove rep_portal.permission_metric_map.
--
-- That table did two unrelated jobs: (1) RBAC — which metric(s)/KPI(s) a
-- permission unlocks, and (2) dashlet content wiring — which KPI code /
-- metric_config row(s) a Dashlets-Hub card renders, plus its disaggregation
-- filters, split mode, and milestone toggle.
--
-- Job (1) for Dynamic Data was already fully superseded by dd:metric:* /
-- permission_metric_config_map (20260729135702) — that migration's bootstrap
-- granted every role every dd:metric:* permission, so nothing depends on the
-- legacy dd:*/permission_metric_map UNION branch in get_dashboard_data_filtered
-- / get_dashboard_metadata anymore. That branch is deleted outright below, not
-- migrated anywhere.
--
-- Job (1) for the main Dashboard (dashlet:* permissions, via
-- get_dashboard_data_scoped) is untouched by that work and still needs a
-- home — it now derives from permissions <-> dashlets, already 1:1-unique on
-- permission_key.
--
-- Job (2) moves onto two new subtype tables mirroring dashlets.source_type
-- ('kpi' vs 'salesforce'), rather than nullable columns on dashlets itself —
-- dashlet_kpi_config (1:1 — a KPI dashlet has exactly one KPI code, already
-- enforced today by permission_metric_map_one_kpi_per_dashlet) and
-- dashlet_metric_configs (1:many — a Salesforce "combine" dashlet can
-- aggregate several metric_config rows).

-- ── 1. New tables ────────────────────────────────────────────────────────────

CREATE TABLE rep_portal.dashlet_kpi_config (
  dashlet_id           INTEGER PRIMARY KEY REFERENCES rep_portal.dashlets(id) ON DELETE CASCADE,
  kpi_id               TEXT NOT NULL,
  kpi_disagg1_filters  TEXT[]  NOT NULL DEFAULT '{}',
  kpi_disagg2_filters  TEXT[]  NOT NULL DEFAULT '{}',
  kpi_split_mode       TEXT    NOT NULL DEFAULT 'combine' CHECK (kpi_split_mode IN ('combine','split')),
  show_milestone       BOOLEAN NOT NULL DEFAULT false,
  CONSTRAINT dashlet_kpi_config_one_split_axis
    CHECK (NOT (array_length(kpi_disagg1_filters,1) > 1 AND array_length(kpi_disagg2_filters,1) > 1))
);

ALTER TABLE rep_portal.dashlet_kpi_config ENABLE ROW LEVEL SECURITY;
-- No policies — default deny, matching dashlets/dashlet_groups. Access only
-- via SECURITY DEFINER functions / service_role.

CREATE TABLE rep_portal.dashlet_metric_configs (
  dashlet_id        INTEGER NOT NULL REFERENCES rep_portal.dashlets(id) ON DELETE CASCADE,
  metric_config_id  INTEGER NOT NULL REFERENCES rep_portal.metric_config(id) ON DELETE CASCADE,
  PRIMARY KEY (dashlet_id, metric_config_id)
);

ALTER TABLE rep_portal.dashlet_metric_configs ENABLE ROW LEVEL SECURITY;
-- No policies — default deny, same rationale.

GRANT ALL ON rep_portal.dashlet_kpi_config, rep_portal.dashlet_metric_configs TO service_role;

-- ── 2. Backfill from permission_metric_map ──────────────────────────────────

-- KPI-sourced content wiring (exactly one row per permission_key where
-- metric_config_id IS NULL, enforced today by permission_metric_map_one_kpi_per_dashlet)
INSERT INTO rep_portal.dashlet_kpi_config
  (dashlet_id, kpi_id, kpi_disagg1_filters, kpi_disagg2_filters, kpi_split_mode, show_milestone)
SELECT d.id, pmm.metric_id, pmm.kpi_disagg1_filters, pmm.kpi_disagg2_filters, pmm.kpi_split_mode, pmm.show_milestone
FROM rep_portal.permission_metric_map pmm
JOIN rep_portal.dashlets d ON d.permission_key = pmm.permission_key
WHERE pmm.metric_config_id IS NULL;

-- Salesforce-sourced content wiring (one row per metric_config this dashlet aggregates)
INSERT INTO rep_portal.dashlet_metric_configs (dashlet_id, metric_config_id)
SELECT d.id, pmm.metric_config_id
FROM rep_portal.permission_metric_map pmm
JOIN rep_portal.dashlets d ON d.permission_key = pmm.permission_key
WHERE pmm.metric_config_id IS NOT NULL;

-- ── 3. get_dashboard_data_scoped() — main Dashboard RBAC ────────────────────

CREATE OR REPLACE FUNCTION rep_portal.get_dashboard_data_scoped()
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
  ) r;
$$;

-- ── 4. get_dashboard_data_filtered() / get_dashboard_metadata() ─────────────
-- Delete the legacy dd:*/permission_metric_map UNION branch entirely — fully
-- superseded by dd:metric:*/permission_metric_config_map. Non-admin visibility
-- is now that one query alone.

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

-- ── 5. Dashlets Hub content RPCs ─────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.get_kpi_dashlets(p_dashboard_id INTEGER DEFAULT NULL)
RETURNS TABLE (
  permission_key       TEXT,
  label                TEXT,
  description          TEXT,
  group_id             INTEGER,
  group_name           TEXT,
  group_display_order  INTEGER,
  chart_type           TEXT,
  display_mode         TEXT,
  kpi_id               TEXT,
  kpi_disagg1_filters  TEXT[],
  kpi_disagg2_filters  TEXT[],
  kpi_split_mode       TEXT,
  show_milestone       BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
  SELECT
    p.key,
    p.label,
    p.description,
    d.group_id,
    g.name,
    g.display_order,
    d.chart_type,
    d.display_mode,
    dkc.kpi_id,
    dkc.kpi_disagg1_filters,
    dkc.kpi_disagg2_filters,
    dkc.kpi_split_mode,
    dkc.show_milestone
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.dashlet_kpi_config dkc ON dkc.dashlet_id = d.id
  JOIN rep_portal.dashlet_groups g ON g.id = d.group_id
  WHERE p.category = 'dashlet'
    AND d.dashboard_id = COALESCE(p_dashboard_id, rep_portal.default_dashboard_id('kpi'))
    AND d.chart_type IS NOT NULL
    AND d.status = 'published'
    AND dkc.kpi_id IS NOT NULL
    AND g.is_ungrouped = false
  ORDER BY COALESCE(g.display_order, 999999), g.name, p.label;
$$;

CREATE OR REPLACE FUNCTION rep_portal.get_kpi_dashlets_admin(p_dashboard_id INTEGER DEFAULT NULL)
RETURNS TABLE (
  permission_key       TEXT,
  label                TEXT,
  description          TEXT,
  group_id             INTEGER,
  group_name           TEXT,
  group_display_order  INTEGER,
  chart_type           TEXT,
  display_mode         TEXT,
  kpi_id               TEXT,
  kpi_disagg1_filters  TEXT[],
  kpi_disagg2_filters  TEXT[],
  kpi_split_mode       TEXT,
  show_milestone       BOOLEAN,
  status               TEXT,
  has_pending_draft    BOOLEAN,
  comment              TEXT,
  comment_enabled      BOOLEAN
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
  SELECT
    p.key,
    COALESCE(dr.label, p.label),
    COALESCE(dr.description, p.description),
    COALESCE(dr.group_id, d.group_id),
    g.name,
    g.display_order,
    COALESCE(dr.chart_type, d.chart_type),
    COALESCE(dr.display_mode, d.display_mode),
    COALESCE(dr.kpi_id, dkc.kpi_id),
    COALESCE(dr.kpi_disagg1_filters, dkc.kpi_disagg1_filters),
    COALESCE(dr.kpi_disagg2_filters, dkc.kpi_disagg2_filters),
    COALESCE(dr.kpi_split_mode, dkc.kpi_split_mode),
    COALESCE(dr.show_milestone, dkc.show_milestone),
    d.status,
    (dr.permission_key IS NOT NULL),
    COALESCE(dr.comment, d.comment),
    COALESCE(dr.comment_enabled, d.comment_enabled)
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.dashlet_drafts dr ON dr.permission_key = p.key
  LEFT JOIN rep_portal.dashlet_kpi_config dkc ON dkc.dashlet_id = d.id
  LEFT JOIN rep_portal.dashlet_groups g ON g.id = COALESCE(dr.group_id, d.group_id)
  WHERE p.category = 'dashlet'
    AND d.dashboard_id = COALESCE(p_dashboard_id, rep_portal.default_dashboard_id('kpi'))
    AND COALESCE(dr.chart_type, d.chart_type) IS NOT NULL
    AND COALESCE(dr.kpi_id, dkc.kpi_id) IS NOT NULL
  ORDER BY COALESCE(g.display_order, 999999), g.name NULLS LAST, COALESCE(dr.label, p.label);
END;
$$;

CREATE OR REPLACE FUNCTION rep_portal.get_salesforce_dashlets(p_dashboard_id INTEGER DEFAULT NULL)
RETURNS TABLE (
  permission_key       TEXT,
  label                TEXT,
  description          TEXT,
  group_id             INTEGER,
  group_name           TEXT,
  group_display_order  INTEGER,
  chart_type           TEXT,
  metric_config_ids    INTEGER[],
  metric_names         TEXT[]
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
  SELECT
    p.key,
    p.label,
    p.description,
    d.group_id,
    g.name,
    g.display_order,
    d.chart_type,
    mm.metric_config_ids,
    mm.metric_names
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  JOIN rep_portal.dashlet_groups g ON g.id = d.group_id
  JOIN LATERAL (
    SELECT
      array_agg(mc.id ORDER BY mc.sort_order NULLS LAST, mc.id)          AS metric_config_ids,
      array_agg(mc.metric_name ORDER BY mc.sort_order NULLS LAST, mc.id) AS metric_names
    FROM rep_portal.dashlet_metric_configs dmc
    JOIN rep_portal.metric_config mc ON mc.id = dmc.metric_config_id
    WHERE dmc.dashlet_id = d.id
  ) mm ON true
  WHERE p.category = 'dashlet'
    AND d.dashboard_id = COALESCE(p_dashboard_id, rep_portal.default_dashboard_id('salesforce'))
    AND d.status = 'published'
    AND d.chart_type IS NOT NULL
    AND g.is_ungrouped = false
    AND mm.metric_config_ids IS NOT NULL
  ORDER BY COALESCE(g.display_order, 999999), g.name, p.label;
$$;

CREATE OR REPLACE FUNCTION rep_portal.get_salesforce_dashlets_admin(p_dashboard_id INTEGER DEFAULT NULL)
RETURNS TABLE (
  permission_key       TEXT,
  label                TEXT,
  description          TEXT,
  group_id             INTEGER,
  group_name           TEXT,
  group_display_order  INTEGER,
  chart_type           TEXT,
  metric_config_ids    INTEGER[],
  metric_names         TEXT[],
  status               TEXT,
  has_pending_draft    BOOLEAN,
  comment              TEXT,
  comment_enabled      BOOLEAN
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
  SELECT
    p.key,
    COALESCE(dr.label, p.label),
    COALESCE(dr.description, p.description),
    COALESCE(dr.group_id, d.group_id),
    g.name,
    g.display_order,
    COALESCE(dr.chart_type, d.chart_type),
    ids.metric_config_ids,
    ARRAY(
      SELECT mc.metric_name
      FROM unnest(ids.metric_config_ids) WITH ORDINALITY AS u(id, ord)
      JOIN rep_portal.metric_config mc ON mc.id = u.id
      ORDER BY u.ord
    ),
    d.status,
    (dr.permission_key IS NOT NULL),
    COALESCE(dr.comment, d.comment),
    COALESCE(dr.comment_enabled, d.comment_enabled)
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.dashlet_drafts dr ON dr.permission_key = p.key
  JOIN rep_portal.dashlet_groups g ON g.id = COALESCE(dr.group_id, d.group_id)
  JOIN LATERAL (
    SELECT CASE
      WHEN dr.permission_key IS NOT NULL THEN dr.metric_config_ids
      ELSE COALESCE((
        SELECT array_agg(dmc.metric_config_id ORDER BY mc.sort_order NULLS LAST, mc.id)
        FROM rep_portal.dashlet_metric_configs dmc
        JOIN rep_portal.metric_config mc ON mc.id = dmc.metric_config_id
        WHERE dmc.dashlet_id = d.id
      ), '{}'::INTEGER[])
    END AS metric_config_ids
  ) ids ON true
  WHERE p.category = 'dashlet'
    AND d.dashboard_id = COALESCE(p_dashboard_id, rep_portal.default_dashboard_id('salesforce'))
    AND g.is_ungrouped = false
    AND COALESCE(dr.chart_type, d.chart_type) IS NOT NULL
    AND array_length(ids.metric_config_ids, 1) > 0
  ORDER BY COALESCE(g.display_order, 999999), g.name, COALESCE(dr.label, p.label);
END;
$$;

CREATE OR REPLACE FUNCTION rep_portal.get_main_dashboard_dashlets(p_dashboard_id INTEGER DEFAULT NULL)
RETURNS TABLE (
  permission_key           TEXT,
  label                    TEXT,
  description              TEXT,
  category_id              INTEGER,
  category_name            TEXT,
  category_display_order   INTEGER,
  category_display_title   TEXT,
  category_description     TEXT,
  group_id                 INTEGER,
  group_name               TEXT,
  group_display_order      INTEGER,
  chart_type                TEXT,
  display_mode              TEXT,
  kpi_id                    TEXT,
  kpi_disagg1_filters       TEXT[],
  kpi_disagg2_filters       TEXT[],
  kpi_split_mode            TEXT,
  show_milestone            BOOLEAN
)
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = rep_portal, pg_temp
AS $$
  SELECT
    p.key,
    p.label,
    p.description,
    c.id,
    c.name,
    c.display_order,
    c.display_title,
    c.description,
    d.group_id,
    g.name,
    g.display_order,
    d.chart_type,
    d.display_mode,
    dkc.kpi_id,
    dkc.kpi_disagg1_filters,
    dkc.kpi_disagg2_filters,
    dkc.kpi_split_mode,
    dkc.show_milestone
  FROM rep_portal.permissions p
  JOIN rep_portal.dashlets d ON d.permission_key = p.key
  LEFT JOIN rep_portal.dashlet_kpi_config dkc ON dkc.dashlet_id = d.id
  JOIN rep_portal.dashlet_groups g ON g.id = d.group_id
  JOIN rep_portal.dashlet_categories c ON c.id = g.category_id AND c.is_uncategorized = false
  WHERE p.category = 'dashlet'
    AND d.dashboard_id = COALESCE(p_dashboard_id, rep_portal.default_dashboard_id('kpi'))
    AND d.chart_type IS NOT NULL
    AND d.status = 'published'
    AND dkc.kpi_id IS NOT NULL
    AND g.is_ungrouped = false
  ORDER BY COALESCE(c.display_order, 999999), c.name, COALESCE(g.display_order, 999999), g.name, p.label;
$$;

-- ── 6. create_dashlet() ──────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION rep_portal.create_dashlet(
  p_key                  TEXT,
  p_label                TEXT,
  p_description          TEXT,
  p_parent_key           TEXT,
  p_dashboard_id         INTEGER,
  p_group_id             INTEGER,
  p_chart_type           TEXT,
  p_display_mode         TEXT,
  p_comment              TEXT,
  p_comment_enabled      BOOLEAN,
  p_metric_config_ids    INTEGER[],
  p_kpi_id               TEXT,
  p_kpi_disagg1_filters  TEXT[],
  p_kpi_disagg2_filters  TEXT[],
  p_kpi_split_mode       TEXT,
  p_updated_by           UUID,
  p_show_milestone       BOOLEAN DEFAULT false
)
RETURNS rep_portal.dashlets
LANGUAGE plpgsql SECURITY DEFINER SET search_path = rep_portal, pg_temp AS $$
DECLARE
  v_dashlet rep_portal.dashlets;
BEGIN
  INSERT INTO rep_portal.permissions (key, label, description, category, parent_key)
  VALUES (p_key, p_label, p_description, 'dashlet', p_parent_key);

  INSERT INTO rep_portal.dashlets (
    permission_key, dashboard_id, group_id, chart_type, display_mode,
    comment, comment_enabled, updated_by
  )
  VALUES (
    p_key, p_dashboard_id, p_group_id, p_chart_type, p_display_mode,
    p_comment, p_comment_enabled, p_updated_by
  )
  RETURNING * INTO v_dashlet;

  IF v_dashlet.source_type = 'salesforce' THEN
    INSERT INTO rep_portal.dashlet_metric_configs (dashlet_id, metric_config_id)
    SELECT v_dashlet.id, mc.id FROM rep_portal.metric_config mc WHERE mc.id = ANY(p_metric_config_ids);
  ELSIF v_dashlet.source_type = 'kpi' AND p_kpi_id IS NOT NULL THEN
    INSERT INTO rep_portal.dashlet_kpi_config (
      dashlet_id, kpi_id, kpi_disagg1_filters, kpi_disagg2_filters, kpi_split_mode, show_milestone
    )
    VALUES (
      v_dashlet.id, p_kpi_id,
      COALESCE(p_kpi_disagg1_filters, '{}'), COALESCE(p_kpi_disagg2_filters, '{}'), COALESCE(p_kpi_split_mode, 'combine'),
      COALESCE(p_show_milestone, false)
    );
  END IF;

  RETURN v_dashlet;
END;
$$;

-- ── 7. Drop the old table ────────────────────────────────────────────────────

DROP TABLE rep_portal.permission_metric_map;


-- ===== 20260803120000_add_school_type_to_dynamic_data.sql =====
-- Add school_type to the Dynamic Data pipeline so the School layer can filter by it.
--
-- dim_school.school_type has been populated from Salesforce School_Type__c since
-- the initial load, but it stopped at the warehouse: dashboard_data_agg carried
-- only country/province/district/school(name)/year/metric/value, so nothing
-- downstream of rep_warehouse could see it.
--
-- Chain added here:
--   dim_school.school_type
--     → view_children_supported / view_guide_assignment / view_cama_membership
--     → rep_portal.dashboard_data_agg.school_type   (via refresh_dashboard_data_agg)
--     → get_dashboard_data_filtered(p_school_types)  (new filter param)
--     → get_dashboard_metadata()                     (per-school type, for the dropdown)
--
-- Only the three school-level source views are touched. The six district-level
-- metrics (grants, loans, post-school support) have no school at all, so
-- school_type is NULL on those rows — they are already hidden at the School
-- layer by DISTRICT_ONLY_METRICS in the frontend.

-- ── 1. Column on the aggregate table ─────────────────────────────────────────
--
-- Appended at the end. dashboard_data_agg_new is built with
-- (LIKE dashboard_data_agg INCLUDING ALL) so it inherits the column, and the
-- positional `INSERT ... SELECT *` swap at the end of the refresh still lines up.

ALTER TABLE rep_portal.dashboard_data_agg
  ADD COLUMN IF NOT EXISTS school_type TEXT;

-- ── 2. Expose school_type on the three school-level source views ─────────────
--
-- All three already LEFT JOIN dim_school for school_name, so this only adds a
-- column to the select list. CREATE OR REPLACE VIEW cannot insert a column in
-- the middle of an existing view, so school_type goes last in each.

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
    g.country,
    s.school_type
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
    g.country,
    s.school_type
FROM rep_warehouse.fact_cama_membership f
LEFT JOIN rep_warehouse.dim_contact  ct ON ct.id = f.contact_id
LEFT JOIN rep_warehouse.dim_school    s  ON  s.id = f.school_id
LEFT JOIN rep_warehouse.dim_geography g  ON  g.id = f.geography_id
LEFT JOIN rep_warehouse.dim_date     dd  ON dd.id = f.date_joined_id;

-- ── 3. refresh_dashboard_data_agg() — carry school_type through ──────────────
--
-- Unchanged from 20260710154248 apart from the school_type column in the
-- generated INSERT/SELECT/GROUP BY. District-level metrics insert NULL::text.
-- The five KPI-sourced blocks at the end are country-level ('National' school)
-- and keep their explicit column lists, so school_type stays NULL there.

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
          'INSERT INTO rep_portal.dashboard_data_agg_new (country, province, district, school, school_type, year, metric, value)
           SELECT country, province, district, school_name, school_type, %I, %L, ',
          v_metric.year_field, v_metric.metric_name
        );
      ELSE
        v_sql := format(
          'INSERT INTO rep_portal.dashboard_data_agg_new (country, province, district, school, school_type, year, metric, value)
           SELECT country, province, district, ''District Total'', NULL::text, %I, %L, ',
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
        v_sql := v_sql || format(' GROUP BY country, province, district, school_name, school_type, %I', v_metric.year_field);
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

-- ── 4. get_dashboard_metadata() — school_type per school ─────────────────────
--
-- Unchanged from 20260730044619 apart from s.school_type in the geography rows.
-- The frontend uses this to build the School Type dropdown scoped to the
-- selected district, rather than showing a global list of every type.

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
        ORDER BY g.country, g.province, g.district, s.school_name
      ) r
    )

  );
$$;

REVOKE EXECUTE ON FUNCTION rep_portal.get_dashboard_metadata() FROM PUBLIC;
GRANT  EXECUTE ON FUNCTION rep_portal.get_dashboard_metadata() TO authenticated;

-- ── 5. get_dashboard_data_filtered() — new p_school_types param ──────────────
--
-- Signature change (7 args → 8), so the old function is dropped rather than
-- replaced; CREATE OR REPLACE would leave an overload behind. RBAC logic is
-- unchanged from 20260730044619.

DROP FUNCTION IF EXISTS rep_portal.get_dashboard_data_filtered(text[], text[], text[], text[], int, int, text[]);

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

-- ── 6. Rebuild so school_type is populated immediately ───────────────────────
--
-- Without this the column exists but is NULL on every row until the next ETL
-- run or KPI upload fires the async refresh, and the new filter returns nothing.

SELECT rep_portal.refresh_dashboard_data_agg();


-- ===== 20260805103000_add_form_5_6_grade_progression.sql =====
-- Progression to Next Grade (KPI 1.7) only ever reached the dashboard as Form 1-4: kpi_mapping
-- had exactly four rows (dashlet_element 14-17) pinned to disaggregation_level_two 'Form 1'
-- through 'Form 4', so get_dashlet_data() discarded Form 5 and Form 6 before they reached the
-- frontend.
--
-- Confirmed against rep_warehouse.view_observed_kpi: every programme country stores a uniform
-- 'Form 1'..'Form 6' slot vocabulary for KPI 1.7 (six rows each, 2020-2025; Kenya 2025 only).
-- Which grades a country actually uses is expressed by the value being the literal string
-- 'Not applicable' -- not by rows being absent. So Ghana, Tanzania and Zimbabwe carry real
-- Form 5/Form 6 percentages that the card was silently dropping, while Malawi/Kenya carry
-- 'Not applicable' there and correctly render as n/a.
--
-- The country-specific grade names shown on the dashboard (Ghana's JHS1-3/SHS1-3, Zambia's
-- Grade 8-12) are a display-only renaming of these neutral slots, applied in
-- EducationOutcomesSection.tsx -- deliberately NOT stored here, so the warehouse keeps one
-- vocabulary and a new programme country needs no data migration.
--
-- Two pinned rows rather than relaxing disaggregation_level_two to NULL: KPI 1.7 also carries
-- 'Lower Secondary'/'Upper secondary' aggregate rows, which a NULL match would pull in and the
-- frontend would then have to filter back out.
--
-- dashlet_element 125/126 continue from 124, the current maximum
-- (20260723020000_wire_remaining_cumulative_dashlets.sql). is_cumulative is omitted -- it
-- defaults to false, which is correct for these annual rate rows.

-- Guarded rather than a plain INSERT: these two rows were applied to the remote database by
-- hand via the SQL editor before this file was recorded in supabase_migrations, so an
-- unguarded push would insert them a second time. kpi_mapping has no unique constraint on
-- dashlet_element, so nothing would reject the duplicate -- get_dashlet_data() would return
-- each Form 5/6 value twice and the card would render the doubled set.
INSERT INTO rep_portal.kpi_mapping
  (dashlet_element, kpi_id, disaggregation_level_one, disaggregation_level_two, source_table, dashboard_page, data_element, toggle)
SELECT v.dashlet_element, v.kpi_id, v.disaggregation_level_one, v.disaggregation_level_two,
       'rep_warehouse.view_observed_kpi', 'Girls Education: Education Outcomes',
       'Progression to Next Grade', v.toggle
FROM (VALUES
  (125, '1.7', 'CAMFED supported', 'Form 5', 'Form 5'),
  (126, '1.7', 'CAMFED supported', 'Form 6', 'Form 6')
) AS v(dashlet_element, kpi_id, disaggregation_level_one, disaggregation_level_two, toggle)
WHERE NOT EXISTS (
  SELECT 1 FROM rep_portal.kpi_mapping m
  WHERE m.kpi_id = v.kpi_id
    AND m.disaggregation_level_one = v.disaggregation_level_one
    AND m.disaggregation_level_two = v.disaggregation_level_two
);

SELECT setval('rep_portal.kpi_mapping_id_seq', (SELECT MAX(id) FROM rep_portal.kpi_mapping));

