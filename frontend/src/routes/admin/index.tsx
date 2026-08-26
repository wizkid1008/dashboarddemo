import { useNavigate, Link } from '@tanstack/react-router'
import { useEffect } from 'react'
import {
  useIngestRuns, useEtlBatchLog, useAdminUsers, useWhatsAppUsers,
  useKpiCoverageSummary, useWaDaily, useDistrictAccess,
} from '@/features/admin/queries'
import { useWarehouseCounts } from '@/features/admin/reconQueries'
import { fmt } from '@/features/admin/Pagination'
import { useAuth } from '@/contexts/AuthContext'

const EMPTY_USER_FILTERS = { search: '', adminRole: '', roleId: null, country: '', status: '' }

const QUICK_LINKS = [
  { to: '/admin/ingest',   label: 'Salesforce Log',  desc: 'Ingest runs & ETL status' },
  { to: '/admin/kpis',     label: 'KPI Upload',       desc: 'Annual, milestone & level-1 data' },
  { to: '/admin/coverage', label: 'Coverage',         desc: 'KPI × country/year heatmap' },
  { to: '/admin/recon',    label: 'Reconciliation',   desc: 'Warehouse counts vs Salesforce' },
  { to: '/admin/salesforce-reports', label: 'Salesforce Reports', desc: 'Manage /salesforce-report dimensions & measures' },
  { to: '/admin/users',    label: 'Users',            desc: 'Portal, WhatsApp & district access' },
  { to: '/admin/roles',    label: 'Roles',            desc: 'Permissions & role assignment' },
  { to: '/admin/whatsapp', label: 'WhatsApp',         desc: 'Bot analytics & funnels' },
  { to: '/admin/usage',    label: 'Portal Usage',     desc: 'Dashboard, Dynamic Data & Map activity' },
] as const

export function AdminIndexPage() {
  const { isCountryAdmin } = useAuth()
  const navigate = useNavigate()
  const runs = useIngestRuns(1)
  const logs = useEtlBatchLog()
  const users = useAdminUsers(1, 1, EMPTY_USER_FILTERS)
  const waUsers = useWhatsAppUsers(1, 1, { search: '', filter: 'all' })
  const coverage = useKpiCoverageSummary()
  const waDaily = useWaDaily()
  const invited = useAdminUsers(1, 1, { ...EMPTY_USER_FILTERS, status: 'invited' })
  const pendingAccess = useDistrictAccess(1, 1, { statusFilter: 'pending' })
  const warehouseCounts = useWarehouseCounts()

  useEffect(() => {
    if (isCountryAdmin) {
      void navigate({ to: '/admin/users' })
    }
  }, [isCountryAdmin, navigate])

  const lastIngest = runs.data?.[0]
  const lastEtl = logs.data?.[0]
  const portalUserCount = users.data?.total ?? null
  const waUserCount = waUsers.data?.total ?? null
  const warehouseRowTotal = warehouseCounts.data
    ? warehouseCounts.data.reduce((sum, row) => sum + row.row_count, 0)
    : null
  const wa7d = waActivity(waDaily.data)

  return (
    <div className="admin-page">
      <h1 className="admin-page-title">Overview</h1>

      <div className="admin-section-title" style={{ marginTop: 0 }}>Data freshness</div>
      <div className="admin-stat-grid">
        <UsersStatCard
          portalCount={portalUserCount}
          waCount={waUserCount}
          loading={users.isLoading || waUsers.isLoading}
        />
        <StatCard
          label="Last ETL run"
          value={lastEtl?.status ?? '—'}
          sub={lastEtl ? fmt(lastEtl.started_at) : undefined}
          loading={logs.isLoading}
          accent={statusAccent(lastEtl?.status)}
        />
        <StatCard
          label="Last ingest run"
          value={lastIngest?.status ?? '—'}
          sub={lastIngest ? fmt(lastIngest.started_at) : undefined}
          loading={runs.isLoading}
          accent={statusAccent(lastIngest?.status)}
        />
        <StatCard
          label="Warehouse rows"
          value={warehouseRowTotal !== null ? warehouseRowTotal.toLocaleString() : '—'}
          loading={warehouseRowTotal === null}
        />
      </div>

      <div className="admin-section-title">Coverage &amp; activity</div>
      <div className="admin-stat-grid">
        <Link to="/admin/coverage" className="admin-stat-card admin-stat-card--blue" style={{ textDecoration: 'none' }}>
          <span className="admin-stat-label">KPI coverage</span>
          {coverage.isLoading || !coverage.data
            ? <span className="admin-stat-value admin-stat-value--loading">…</span>
            : <span className="admin-stat-value">{coverage.data.kpis_with_data} / {coverage.data.total_kpis}</span>}
          {coverage.data && (
            <span className="admin-stat-sub">
              {coverage.data.countries_covered} countries · {coverage.data.years_covered} years
            </span>
          )}
        </Link>
        <Link to="/admin/whatsapp" className="admin-stat-card" style={{ textDecoration: 'none' }}>
          <span className="admin-stat-label">WhatsApp activity (7d)</span>
          {waDaily.isLoading
            ? <span className="admin-stat-value admin-stat-value--loading">…</span>
            : <span className="admin-stat-value">{wa7d.events.toLocaleString()} events</span>}
          {!waDaily.isLoading && (
            <span className="admin-stat-sub">{wa7d.completions} completions · {wa7d.errors} errors</span>
          )}
        </Link>
        <Link to="/admin/users" className="admin-stat-card admin-stat-card--amber" style={{ textDecoration: 'none' }}>
          <span className="admin-stat-label">Invited users</span>
          {invited.isLoading
            ? <span className="admin-stat-value admin-stat-value--loading">…</span>
            : <span className="admin-stat-value">{invited.data?.total ?? 0}</span>}
          <span className="admin-stat-sub">awaiting confirmation</span>
        </Link>
        <Link to="/admin/users" className="admin-stat-card admin-stat-card--amber" style={{ textDecoration: 'none' }}>
          <span className="admin-stat-label">Pending district access</span>
          {pendingAccess.isLoading
            ? <span className="admin-stat-value admin-stat-value--loading">…</span>
            : <span className="admin-stat-value">{pendingAccess.data?.total ?? 0}</span>}
          <span className="admin-stat-sub">awaiting approver decision</span>
        </Link>
      </div>

      <div className="admin-section-title">Quick links</div>
      <div className="admin-stat-grid">
        {QUICK_LINKS.map(link => (
          <Link key={link.to} to={link.to} className="admin-stat-card" style={{ textDecoration: 'none' }}>
            <span className="admin-stat-label">{link.label}</span>
            <span className="admin-stat-sub">{link.desc}</span>
          </Link>
        ))}
      </div>
    </div>
  )
}

function waActivity(data: ReturnType<typeof useWaDaily>['data']) {
  if (!data) return { events: 0, completions: 0, errors: 0 }
  const cutoff = new Date()
  cutoff.setDate(cutoff.getDate() - 7)
  const recent = data.filter(d => new Date(d.day) >= cutoff)
  return recent.reduce(
    (acc, d) => ({
      events: acc.events + d.total_events,
      completions: acc.completions + d.completions,
      errors: acc.errors + d.errors,
    }),
    { events: 0, completions: 0, errors: 0 },
  )
}

function statusAccent(status?: string) {
  if (!status) return undefined
  if (status === 'completed' || status === 'success') return 'green'
  if (status === 'failed') return 'red'
  if (status === 'in_progress' || status === 'running') return 'blue'
  return undefined
}

function UsersStatCard({ portalCount, waCount, loading }: {
  portalCount: number | null
  waCount: number | null
  loading: boolean
}) {
  return (
    <Link to="/admin/users" className="admin-stat-card" style={{ textDecoration: 'none' }}>
      <span className="admin-stat-label">Users</span>
      <div style={{ display: 'flex', gap: 20, marginTop: 2 }}>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
          {loading
            ? <span className="admin-stat-value admin-stat-value--loading">…</span>
            : <span className="admin-stat-value">{portalCount ?? '—'}</span>}
          <span className="admin-stat-sub">Portal</span>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 2 }}>
          {loading
            ? <span className="admin-stat-value admin-stat-value--loading">…</span>
            : <span className="admin-stat-value">{waCount ?? '—'}</span>}
          <span className="admin-stat-sub">WhatsApp</span>
        </div>
      </div>
    </Link>
  )
}

function StatCard({ label, value, sub, loading, accent }: {
  label: string
  value: string
  sub?: string
  loading: boolean
  accent?: 'green' | 'red' | 'blue'
}) {
  const accentClass = accent ? ` admin-stat-card--${accent}` : ''
  return (
    <div className={`admin-stat-card${accentClass}`}>
      <span className="admin-stat-label">{label}</span>
      {loading
        ? <span className="admin-stat-value admin-stat-value--loading">…</span>
        : <span className="admin-stat-value">{value}</span>}
      {sub && <span className="admin-stat-sub">{sub}</span>}
    </div>
  )
}
