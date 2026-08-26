# Connecting the demo to Supabase

Wires `dashboarddemo-ekt.pages.dev` to the demo Supabase project
`gpyetojuzngrfrtcoycj` and fills it with fabricated data, keeping the site
browsable without a login.

Everything here targets the **demo** project. None of it should ever run
against the production warehouse (`qlvayqyihfixikfqfelu`) — `sql/04_open_access.sql`
in particular deliberately opens anonymous read access.

## Why the demo is empty today

The Pages project has no `VITE_*` build variables set. Vite inlines those at
build time, so the shipped bundle contains the literal string `undefined` where
the Supabase URL should be, and every RPC posts to
`https://dashboarddemo-ekt.pages.dev/undefined/rest/v1/rpc/...` → 405. The only
Supabase host the deployment currently reaches is the production warehouse's
public storage bucket, which serves the map's boundary shapes.

## What was changed in the frontend

Branch `demo/connect-supabase` (off `main`, **not pushed**):

| File | Change |
|---|---|
| `frontend/src/lib/supabase.ts` | New `isDemoOpenAccess` flag, driven by `VITE_DEMO_OPEN_ACCESS` |
| `frontend/src/router.tsx` | `_auth` guard and page-view logging skip when open access is on |
| `frontend/src/contexts/AuthContext.tsx` | `hasPermission()` returns true under open access |
| `frontend/src/routes/map.tsx` | Boundary GeoJSON base URL comes from `VITE_MAP_SHAPES_BASE_URL`, defaulting to today's hardcoded production bucket |

The flag exists because the KPI Report, Trends and Milestones pages call
`supabase.schema('rep_portal')` — the **portal** client, not the warehouse one.
Setting `VITE_SUPABASE_URL` to make those pages work also flips
`isSupabaseConfigured` to true, which would switch the login gate on and end the
open demo. `VITE_DEMO_OPEN_ACCESS=true` keeps the current no-login behaviour
while real RPCs are issued as `anon`.

## Steps

### 1. Create the schema

287 migrations have to be applied to the empty project. Either route works —
everything else in this runbook is SQL Editor work regardless.

Neither route has been rehearsed against a fresh project. If a statement fails,
capture the error rather than skipping past it; a half-applied schema produces
confusing gaps several steps later.

**Route A — CLI (one command, preferred).** Needs Node (version in
`frontend/.nvmrc`) and `npm i -g supabase`. Run from the root of the **full**
portal repo — the one with `supabase/`, i.e. your `master` checkout, not this
deploy branch:

```bash
supabase link --project-ref gpyetojuzngrfrtcoycj
```

```bash
supabase db push
```

**Route B — SQL Editor only, no CLI.** `sql/00_schema/` holds the same 287
migrations concatenated in filename order and split into eight paste-able
chunks. Run `chunk_01` … `chunk_07` in order, each only after the previous one
succeeded, then `chunk_08_record_migrations.sql`.

That last file is not optional if you ever intend to use the CLI on this
project: pasting SQL bypasses the `supabase_migrations.schema_migrations`
bookkeeping the CLI keeps, so without it a later `supabase db push` replays all
287 migrations and fails on the first object that already exists.

The chunks are generated output, not hand-written — regenerate them rather than
editing them if migrations change.

### 2. Expose the schemas to PostgREST

Supabase dashboard → Project Settings → API → **Exposed schemas**: add
`rep_portal`, `rep_warehouse`, `rep_raw`. Without this every RPC returns 404
regardless of grants.

### 3. Seed the data

SQL Editor, in order. Each file is re-runnable and each ends with a sanity
check whose output is worth reading before moving on.

| File | Populates | Backs |
|---|---|---|
| `sql/01_seed_dimensions.sql` | Geography, KPI definitions, schools, contacts | Everything downstream |
| `sql/02_seed_kpi_facts.sql` | `fact_observed_kpi`, `fact_kpi_milestone` | Data Dashboard, KPI Report, Trends, Milestones |
| `sql/03_seed_salesforce_facts.sql` | Six Salesforce-shaped fact tables, then rebuilds `dashboard_data_agg` | Dynamic Data, Data Map |
| `sql/04_open_access.sql` | `anon` grants + country-scoping override | Browsing without a login |

`02` derives its combinations from `rep_portal.kpi_mapping`, so every dashboard
card the migrations wire up gets data — including cards added later. Its final
query lists every dashlet element with its matching row count; any element
showing `0` is a card that will still say "No data is available".

All seeded rows carry `lin_source_system = 'Demo_Seed'` and
`lin_load_batch_id = 'demo-seed'`.

### 4. Upload the map shapes

Storage → create a **public** bucket named `MapShapes`, then upload:

- `priority_adm2_v2.geojson` — already on disk at `scripts/map-shapes/` in your
  master checkout
- `africa_adm0_simplified.geojson` — fetch from the production bucket:

```bash
curl -O https://qlvayqyihfixikfqfelu.supabase.co/storage/v1/object/public/MapShapes/africa_adm0_simplified.geojson
```

The two `geoBoundariesCGAZ_*.geojson` files are fallbacks the map only reaches
for when the simplified pair is missing; skip them unless the map complains.

The district names seeded in `01` are the real geoBoundaries `shapeName` values
from `priority_adm2_v2.geojson`, so the district layer will actually colour in.

### 5. Set the Cloudflare Pages variables

Pages project → Settings → Environment variables (Production):

```
VITE_SUPABASE_URL=https://gpyetojuzngrfrtcoycj.supabase.co
VITE_SUPABASE_ANON_KEY=<publishable key>
VITE_WAREHOUSE_SUPABASE_URL=https://gpyetojuzngrfrtcoycj.supabase.co
VITE_WAREHOUSE_SUPABASE_KEY=<same publishable key>
VITE_MAP_SHAPES_BASE_URL=https://gpyetojuzngrfrtcoycj.supabase.co/storage/v1/object/public/MapShapes
VITE_DEMO_OPEN_ACCESS=true
```

Use the **publishable / anon** key (`sb_publishable_...`), never the service
role key — it would be readable in the shipped bundle.

### 6. Merge and redeploy

Saving variables does not rebuild. Merge `demo/connect-supabase` into `main`
and push; Cloudflare rebuilds on the commit.

## Verifying

1. `https://dashboarddemo-ekt.pages.dev/` loads without a login prompt.
2. DevTools → Network: RPCs go to `gpyetojuzngrfrtcoycj.supabase.co`, status
   200 — no `/undefined/` paths, no 405s.
3. Data Dashboard → Level 1 → Education Reach: cards show numbers instead of
   "No data is available for this KPI during this time period".
4. Data Map: districts in the five countries are coloured.
5. Dynamic Data: the metric dropdown is populated and returns rows.
6. KPI Report / Trends / Milestones: years and indicators are listed.

A 401 on an RPC means step 3's grant list missed it — add the name to
`v_allow` in `sql/04_open_access.sql` and re-run. A 404 means step 2.

## Removing the demo data

```sql
DELETE FROM rep_warehouse.fact_observed_kpi        WHERE lin_load_batch_id = 'demo-seed';
DELETE FROM rep_warehouse.fact_kpi_milestone       WHERE lin_load_batch_id = 'demo-seed';
DELETE FROM rep_warehouse.fact_children_supported  WHERE lin_load_batch_id = 'demo-seed';
DELETE FROM rep_warehouse.fact_guide_assignment    WHERE lin_load_batch_id = 'demo-seed';
DELETE FROM rep_warehouse.fact_cama_membership     WHERE lin_load_batch_id = 'demo-seed';
DELETE FROM rep_warehouse.fact_post_school_support WHERE lin_load_batch_id = 'demo-seed';
DELETE FROM rep_warehouse.fact_grants              WHERE lin_load_batch_id = 'demo-seed';
DELETE FROM rep_warehouse.fact_loans               WHERE lin_load_batch_id = 'demo-seed';
DELETE FROM rep_warehouse.dim_contact              WHERE lin_source_system = 'Demo_Seed';
DELETE FROM rep_warehouse.dim_school               WHERE lin_source_system = 'Demo_Seed';
DELETE FROM rep_warehouse.dim_kpi                  WHERE lin_source_system = 'Demo_Seed';
DELETE FROM rep_warehouse.dim_geography            WHERE lin_source_system = 'Demo_Seed';
SELECT rep_portal.refresh_dashboard_data_agg();
```
