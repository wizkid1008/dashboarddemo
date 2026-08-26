# CAMFED Dashboard

A data dashboard built for CAMFED, powered by React 19, TypeScript, Vite, TanStack Router, and TanStack Query.

## Tech Stack

- **React 19** — UI framework
- **TypeScript** — Type safety
- **Vite** — Build tool and dev server
- **TanStack Router** — File-based, type-safe routing
- **TanStack Query** — Async data fetching and caching
- **Tailwind CSS v4** — Utility-first styling, alongside the hand-written `brand.css`
- **Chart.js** — Data visualisation
- **Lucide React** — Icons

## Project Structure

```
src/
  components/         # Shared components (filters, charts, dashboard sections)
    charts/           # FlexChart — the shared Chart.js wrapper
    dashboard/        # EducationReachSection, SubLevelCharts
  contexts/           # AuthContext (session, isAdmin, permissions)
  data/               # Static data (hierarchy, dashboard chart registry, brand colours)
  features/                # Feature-scoped code, each with its own queries.ts:
    admin/                 #   admin console (users, roles, ingest, KPI upload, WhatsApp analytics, ...)
    dashboards/            #   shared dashboard building blocks
    default-dashboard/     #   /default-dashboard — dashlet-based landing dashboard
    kpi-dashboard/         #   /kpi-dashboard, /kpi-trends, /kpi-milestones
    kpi-report/            #   /kpi-report
    salesforce-dashboard/  #   /salesforce-dashboard
    salesforce-report/     #   /salesforce-report
  queries/            # Cross-cutting TanStack Query hooks (useDashboardData, useObservedKpi, ...)
  routes/             # File-based routes (TanStack Router) — one file per page, admin/* nested
  types/              # Shared TypeScript types
  utils/              # Dashboard utility functions
  router.tsx          # App router and root layout, incl. `_auth` beforeLoad guard
  main.tsx            # Entry point
  queryClient.ts      # TanStack Query client setup
```

New TanStack Query hooks belong in a `queries.ts` co-located within the relevant `features/` subdirectory, not in the shared `queries/` folder — see `CLAUDE.md` for the convention.

## Routes

Public (no session required): `/login`, `/forgot-password`, `/set-password`, `/reset-password`. Everything else requires an authenticated session; `/admin/*` additionally requires `app_metadata.role` of `'admin'` (full console) or `'country_admin'` (Users + Docs pages only, scoped to their countries — see `../docs/security.md` → Admin roles).

| Path | Page |
|---|---|
| `/` (`home.tsx`) | Landing page |
| `/dashboard` | Data Dashboard — filterable KPI charts by level/sub-level/country (`SubLevelCharts`) |
| `/default-dashboard` | Dashlet-based landing dashboard (admin-configured cards, `features/default-dashboard/`) |
| `/dynamic` | Dynamic Data |
| `/slicer` | Data Slicer |
| `/map` | Interactive map (country/district KPI layers) |
| `/kpi-dashboard`, `/kpi-trends`, `/kpi-milestones` | KPI dashboard views |
| `/kpi-report` | KPI report view |
| `/salesforce-dashboard`, `/salesforce-report` | Salesforce-sourced dashboard/report views |
| `/admin` (`admin/index.tsx`) | Admin overview (users, last ETL run, last ingest run) |
| `/admin/ingest` | Ingest run table, per-function state, manual trigger |
| `/admin/kpis` | KPI upload UI (All KPIs + Level-1 KPI tabs) |
| `/admin/users` | User list, invite, remove, set admin role, assign RBAC roles |
| `/admin/roles` | RBAC role and permission-set management |
| `/admin/dashlets` | Dashlet configuration editor |
| `/admin/dashlet-comments` | Dashlet comment moderation |
| `/admin/logs` | ETL batch log |
| `/admin/whatsapp` | WhatsApp bot analytics |
| `/admin/salesforce-reports` | Salesforce report admin |
| `/admin/coverage`, `/admin/recon`, `/admin/usage` | Data coverage, reconciliation, and usage admin views |
| `/admin/docs` | In-app documentation viewer |

For the full architecture (ETL pipeline, database schema, RBAC model, security rules), see the root [`CLAUDE.md`](../CLAUDE.md) and [`../docs/HANDOVER.md`](../docs/HANDOVER.md).

## Getting Started

### Prerequisites

- Node.js — version pinned in [`.nvmrc`](.nvmrc) (`nvm use`)
- npm

### Install dependencies

```bash
npm install
```

### Run development server

```bash
npm run dev
```

### Build for production

```bash
npm run build
```

### Preview production build

```bash
npm run preview
```

### Lint

```bash
npm run lint
```

### Type-check

```bash
npx tsc --noEmit
```

### Unused-code check

```bash
npm run knip
```

Reports unused files, exports, and dependencies; exits non-zero on findings. Config is `knip.json` — see `CLAUDE.md` → Commands for why its `ignoreDependencies` list must not be trimmed.

There is no automated test script (`npm test`) for this frontend — `lint`, `tsc --noEmit`, and `knip` are the only checks the CI/dev workflow currently runs. See `docs/HANDOVER.md` for this gap noted as an open item for the incoming team.
