import { useState, useMemo } from 'react'
import { useKpiCoverage } from '@/features/admin/coverageQueries'
import type { KpiCoverageSummary } from '@/features/admin/coverageQueries'
import { AdminDataTable, type AdminColumn } from '@/features/admin/components/AdminDataTable'

// ── Helpers ───────────────────────────────────────────────────────────────────

function StatusBadge({ status }: { status: 'complete' | 'partial' | 'missing' }) {
  const cls =
    status === 'complete' ? 'admin-badge--green' :
    status === 'partial'  ? 'admin-badge--amber' :
                            'admin-badge--red'
  const label =
    status === 'complete' ? 'Complete' :
    status === 'partial'  ? 'Partial'  : 'Missing'
  return <span className={`admin-badge ${cls}`}>{label}</span>
}

function StatCard({ label, value, loading }: { label: string; value: string; loading: boolean }) {
  return (
    <div className="admin-stat-card">
      <span className="admin-stat-label">{label}</span>
      {loading
        ? <span className="admin-stat-value admin-stat-value--loading">…</span>
        : <span className="admin-stat-value">{value}</span>}
    </div>
  )
}

function exportCsv(summaries: KpiCoverageSummary[], allCountries: string[]) {
  const headers = [
    'KPI ID', 'KPI Name', 'Group',
    `Countries with Data (of ${allCountries.length})`,
    'Years with Data', 'Latest Year', 'Last Updated', 'Status',
  ]
  const rows = summaries.map(s => [
    s.kpi_id,
    s.name,
    s.group,
    String(s.countriesWithData.length),
    String(s.yearsWithData.length),
    String(s.latestYear ?? ''),
    s.lastUpdated ?? '',
    s.status,
  ])
  const csv = [headers, ...rows]
    .map(row => row.map(c => `"${String(c).replace(/"/g, '""')}"`).join(','))
    .join('\n')
  const blob = new Blob([csv], { type: 'text/csv' })
  const url  = URL.createObjectURL(blob)
  const a    = document.createElement('a')
  a.href     = url
  a.download = 'kpi-coverage.csv'
  a.click()
  URL.revokeObjectURL(url)
}

// ── Heatmap ───────────────────────────────────────────────────────────────────

function CoverageHeatmap({
  kpi,
  allCountries,
  allYears,
}: {
  kpi: KpiCoverageSummary
  allCountries: string[]
  allYears: number[]
}) {
  return (
    <div className="coverage-heatmap-wrap">
      <table className="coverage-heatmap">
        <thead>
          <tr>
            <th className="coverage-heatmap-country-col">Country</th>
            {allYears.map(y => (
              <th key={y} className="coverage-heatmap-year-col">{y}</th>
            ))}
          </tr>
        </thead>
        <tbody>
          {allCountries.map(country => (
            <tr key={country}>
              <td className="coverage-heatmap-country">{country}</td>
              {allYears.map(year => {
                const cell    = kpi.countryYearMap[country]?.[year]
                const covered = cell?.covered ?? false
                const count   = cell?.count   ?? 0
                return (
                  <td
                    key={year}
                    className={`coverage-heatmap-cell ${covered ? 'coverage-heatmap-cell--covered' : 'coverage-heatmap-cell--missing'}`}
                    title={covered
                      ? `${country} ${year}: ${count} record${count !== 1 ? 's' : ''}`
                      : `${country} ${year}: No data`}
                  >
                    {covered ? count : '✕'}
                  </td>
                )
              })}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  )
}

// ── Detail drawer ─────────────────────────────────────────────────────────────

function CoverageDrawer({
  kpi,
  allCountries,
  allYears,
  onClose,
}: {
  kpi: KpiCoverageSummary
  allCountries: string[]
  allYears: number[]
  onClose: () => void
}) {
  const missingCombinations = useMemo(() => {
    const missing: string[] = []
    for (const c of allCountries) {
      for (const y of allYears) {
        if (!kpi.countryYearMap[c]?.[y]?.covered) {
          missing.push(`${c} ${y}`)
        }
      }
    }
    return missing
  }, [kpi, allCountries, allYears])

  return (
    <div className="admin-modal-overlay" onClick={onClose}>
      <div className="coverage-drawer" onClick={e => e.stopPropagation()}>
        {/* Header */}
        <div className="coverage-drawer-header">
          <div>
            <h2 className="coverage-drawer-title">{kpi.name}</h2>
            <div style={{ display: 'flex', gap: 8, alignItems: 'center', marginTop: 6 }}>
              <code className="admin-table-mono admin-muted">{kpi.kpi_id}</code>
              <span className="admin-muted">·</span>
              <span className="admin-muted" style={{ fontSize: '0.82rem' }}>{kpi.group}</span>
              <span className="admin-muted">·</span>
              <StatusBadge status={kpi.status} />
            </div>
          </div>
          <button className="coverage-drawer-close" onClick={onClose} aria-label="Close">✕</button>
        </div>

        {/* Mini stats */}
        <div className="admin-stat-grid" style={{ marginTop: 16, gridTemplateColumns: 'repeat(2, 1fr)' }}>
          <div className="admin-stat-card">
            <span className="admin-stat-label">Total records</span>
            <span className="admin-stat-value">{kpi.totalRecords.toLocaleString()}</span>
          </div>
          <div className="admin-stat-card">
            <span className="admin-stat-label">Countries with data</span>
            <span className="admin-stat-value">{kpi.countriesWithData.length} / {allCountries.length}</span>
          </div>
          <div className="admin-stat-card">
            <span className="admin-stat-label">Latest year</span>
            <span className="admin-stat-value">{kpi.latestYear ?? '—'}</span>
          </div>
          <div className="admin-stat-card">
            <span className="admin-stat-label">Last updated</span>
            <span className="admin-stat-value" style={{ fontSize: '0.95rem' }}>{kpi.lastUpdated ?? '—'}</span>
          </div>
        </div>

        {/* Dashboard charts */}
        {kpi.dashboardCharts.length > 0 && (
          <>
            <h3 className="admin-section-title" style={{ marginTop: 24, marginBottom: 8 }}>Shown on Dashboard</h3>
            <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
              {kpi.dashboardCharts.map((c, i) => (
                <div key={i} style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
                  <span className="admin-badge admin-badge--purple">{c.section}</span>
                  <span style={{ fontSize: '0.85rem', color: 'var(--text)' }}>{c.chartName}</span>
                </div>
              ))}
            </div>
          </>
        )}

        {/* Heatmap */}
        <h3 className="admin-section-title" style={{ marginTop: 24, marginBottom: 8 }}>Country × Year Coverage</h3>
        <CoverageHeatmap kpi={kpi} allCountries={allCountries} allYears={allYears} />

        {/* Missing combinations */}
        {missingCombinations.length > 0 && (
          <>
            <h3 className="admin-section-title" style={{ marginTop: 24, marginBottom: 8 }}>
              Missing Combinations
              <span className="admin-muted" style={{ fontWeight: 400, marginLeft: 8 }}>
                ({missingCombinations.length})
              </span>
            </h3>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6 }}>
              {missingCombinations.map(m => (
                <span key={m} className="admin-badge admin-badge--red">{m}</span>
              ))}
            </div>
          </>
        )}
      </div>
    </div>
  )
}

function coverageColumns(countryCount: number): AdminColumn<KpiCoverageSummary>[] {
  return [
    { key: 'name', header: 'KPI Name', sortValue: (s) => s.name, render: (s) => <span className="admin-table-name">{s.name}</span> },
    { key: 'kpi_id', header: 'KPI ID', sortValue: (s) => s.kpi_id, render: (s) => <span className="admin-table-mono admin-muted">{s.kpi_id}</span> },
    {
      key: 'dashboard', header: 'Dashboard',
      render: (s) => s.dashboardCharts.length > 0
        ? <div style={{ display: 'flex', flexWrap: 'wrap', gap: 4 }}>
            {s.dashboardCharts.map((c, i) => (
              <span key={i} className="admin-badge admin-badge--purple" title={`${c.chartName} · ${c.section}`}>
                {c.section}
              </span>
            ))}
          </div>
        : <span className="admin-muted" style={{ fontSize: '0.78rem' }}>—</span>,
    },
    { key: 'countries', header: 'Countries', sortValue: (s) => s.countriesWithData.length, render: (s) => `${s.countriesWithData.length} / ${countryCount}` },
    { key: 'years', header: 'Years', sortValue: (s) => s.yearsWithData.length, render: (s) => s.yearsWithData.length },
    { key: 'latestYear', header: 'Latest Year', sortValue: (s) => s.latestYear, render: (s) => s.latestYear ?? '—' },
    { key: 'lastUpdated', header: 'Last Updated', sortValue: (s) => s.lastUpdated, render: (s) => <span className="admin-muted">{s.lastUpdated ?? '—'}</span> },
    { key: 'status', header: 'Status', sortValue: (s) => s.status, render: (s) => <StatusBadge status={s.status} /> },
  ]
}

// ── Page ──────────────────────────────────────────────────────────────────────

export function AdminCoveragePage() {
  const { data, isLoading, error } = useKpiCoverage()

  const [search,        setSearch]        = useState('')
  const [filterCountry, setFilterCountry] = useState('')
  const [filterYear,    setFilterYear]    = useState('')
  const [filterStatus,  setFilterStatus]  = useState('')
  const [filterGroup,   setFilterGroup]   = useState('')
  const [selectedKpi,   setSelectedKpi]   = useState<KpiCoverageSummary | null>(null)

  const summaries    = data?.summaries    ?? []
  const allCountries = data?.allCountries ?? []
  const allYears     = data?.allYears     ?? []

  // Summary stats
  const totalKpis      = summaries.length
  const kpisWithData   = summaries.filter(s => s.status !== 'missing').length
  const latestUpdate   = summaries.reduce<string | null>(
    (max, s) => (!s.lastUpdated ? max : !max || s.lastUpdated > max ? s.lastUpdated : max),
    null,
  )
  const missingCount   = useMemo(() => {
    let n = 0
    for (const s of summaries) {
      for (const c of allCountries) {
        for (const y of allYears) {
          if (!s.countryYearMap[c]?.[y]?.covered) n++
        }
      }
    }
    return n
  }, [summaries, allCountries, allYears])

  const groups = useMemo(
    () => [...new Set(summaries.map(s => s.group))].sort(),
    [summaries],
  )

  const filtered = useMemo(() => {
    const q = search.toLowerCase()
    return summaries.filter(s => {
      if (q && !s.name.toLowerCase().includes(q) && !s.kpi_id.toLowerCase().includes(q)) return false
      if (filterCountry && !s.countriesWithData.includes(filterCountry))                  return false
      if (filterYear    && !s.yearsWithData.includes(Number(filterYear)))                  return false
      if (filterStatus  && s.status !== filterStatus)                                      return false
      if (filterGroup   && s.group  !== filterGroup)                                       return false
      return true
    })
  }, [summaries, search, filterCountry, filterYear, filterStatus, filterGroup])

  return (
    <div className="admin-page">
      <div className="admin-page-header">
        <h1 className="admin-page-title">Data Coverage</h1>
        <button
          className="admin-btn admin-btn--ghost"
          onClick={() => exportCsv(filtered, allCountries)}
          disabled={filtered.length === 0}
        >
          Export CSV
        </button>
      </div>

      {error && (
        <p className="admin-error" style={{ marginBottom: 16 }}>
          Failed to load coverage data: {(error as Error).message}
        </p>
      )}

      {/* Summary cards */}
      <div className="admin-stat-grid" style={{ marginBottom: 24 }}>
        <StatCard label="Total KPIs"              value={String(totalKpis)}                loading={isLoading} />
        <StatCard label="KPIs with data"          value={String(kpisWithData)}             loading={isLoading} />
        <StatCard label="Countries"               value={String(allCountries.length)}      loading={isLoading} />
        <StatCard label="Years"                   value={String(allYears.length)}          loading={isLoading} />
        <StatCard label="Most recent update"      value={latestUpdate ?? '—'}              loading={isLoading} />
        <StatCard label="Missing country-years"   value={isLoading ? '…' : String(missingCount)} loading={false} />
      </div>

      {/* Filters */}
      <div className="admin-section-header" style={{ marginBottom: 12, flexWrap: 'wrap', gap: 8 }}>
        <input
          className="admin-input admin-input--sm"
          placeholder="Search KPI name or ID…"
          value={search}
          onChange={e => setSearch(e.target.value)}
          style={{ minWidth: 200 }}
        />
        <select className="admin-select" value={filterCountry} onChange={e => setFilterCountry(e.target.value)}>
          <option value="">All countries</option>
          {allCountries.map(c => <option key={c} value={c}>{c}</option>)}
        </select>
        <select className="admin-select" value={filterYear} onChange={e => setFilterYear(e.target.value)}>
          <option value="">All years</option>
          {allYears.map(y => <option key={y} value={y}>{y}</option>)}
        </select>
        <select className="admin-select" value={filterStatus} onChange={e => setFilterStatus(e.target.value)}>
          <option value="">All statuses</option>
          <option value="complete">Complete</option>
          <option value="partial">Partial</option>
          <option value="missing">Missing</option>
        </select>
        <select className="admin-select" value={filterGroup} onChange={e => setFilterGroup(e.target.value)}>
          <option value="">All groups</option>
          {groups.map(g => <option key={g} value={g}>{g}</option>)}
        </select>
      </div>

      {/* Table */}
      <AdminDataTable
        data={filtered}
        rowKey={(s) => s.kpi_id}
        columns={coverageColumns(allCountries.length)}
        isLoading={isLoading}
        loadingMessage="Loading coverage data…"
        emptyMessage="No KPIs match the current filters."
        onRowClick={(s) => setSelectedKpi(s)}
      />

      {/* Detail drawer */}
      {selectedKpi && (
        <CoverageDrawer
          kpi={selectedKpi}
          allCountries={allCountries}
          allYears={allYears}
          onClose={() => setSelectedKpi(null)}
        />
      )}
    </div>
  )
}
