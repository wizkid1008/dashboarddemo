import { useEffect, useRef } from 'react'
import {
  Chart,
  CategoryScale,
  LinearScale,
  PointElement,
  LineElement,
  BarElement,
  Title,
  Tooltip,
  Legend,
  Filler,
  type ChartData,
} from 'chart.js'
import {
  useUsageDaily,
  useUsageByPage,
  useUsageByUser,
  useUsageMonthly,
  type UsageDaily,
  type UsageByUser,
  type UsageMonthly,
} from '@/features/admin/queries'
import { AdminDataTable, type AdminColumn } from '@/features/admin/components/AdminDataTable'

Chart.register(CategoryScale, LinearScale, PointElement, LineElement, BarElement, Title, Tooltip, Legend, Filler)

const PAGE_LABELS: Record<string, string> = {
  dashboard: 'Dashboard',
  dynamic: 'Dynamic Data',
  map: 'Map',
}

const PAGE_COLORS: Record<string, string> = {
  dashboard: '#3b82f6',
  dynamic: '#10b981',
  map: '#f59e0b',
}

export function AdminUsagePage() {
  const daily = useUsageDaily()
  const byPage = useUsageByPage()
  const byUser = useUsageByUser()
  const monthly = useUsageMonthly()

  function handleRefresh() {
    void daily.refetch()
    void byPage.refetch()
    void byUser.refetch()
    void monthly.refetch()
  }

  const last7 = (daily.data ?? []).filter((d) => {
    const diff = (Date.now() - new Date(d.day).getTime()) / 86_400_000
    return diff <= 7
  })
  const totalViews7d = last7.reduce((s, d) => s + Number(d.total_views), 0)
  const uniqueUsers7d = (byUser.data ?? []).filter((u) => {
    const diff = (Date.now() - new Date(u.last_seen).getTime()) / 86_400_000
    return diff <= 7
  }).length

  const isLoading = daily.isLoading || byPage.isLoading
  const isFetching = daily.isFetching || byPage.isFetching || byUser.isFetching || monthly.isFetching

  return (
    <div className="admin-page">
      <div className="admin-page-header">
        <h1 className="admin-page-title">Portal Usage</h1>
        <button className="admin-btn" onClick={handleRefresh} disabled={isFetching}>
          {isFetching ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>

      {isLoading && <p className="admin-muted">Loading…</p>}
      {(daily.isError || byPage.isError) && (
        <p className="admin-error">Failed to load usage analytics.</p>
      )}

      {!isLoading && (
        <>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(5, 1fr)', gap: '12px', marginBottom: '24px' }}>
            <StatCard label="Total views (7d)" value={totalViews7d.toLocaleString()} />
            <StatCard label="Unique users (7d)" value={uniqueUsers7d.toLocaleString()} />
            {(['dashboard', 'dynamic', 'map'] as const).map((page) => {
              const row = byPage.data?.find((r) => r.page === page)
              return (
                <StatCard
                  key={page}
                  label={`${PAGE_LABELS[page]} views (30d)`}
                  value={(row ? Number(row.total_views) : 0).toLocaleString()}
                />
              )
            })}
          </div>

          <DailyChart data={daily.data ?? []} />
          <MonthlyChart data={monthly.data ?? []} />

          <h2 style={{ fontSize: '15px', fontWeight: 600, margin: '24px 0 10px' }}>By user (last 90 days)</h2>
          <p className="admin-muted" style={{ marginTop: 0, marginBottom: '10px', fontSize: '12px' }}>
            Detail is retained for 90 days. Older activity is summarized in the monthly chart above rather than
            shown per-user here.
          </p>
          <UsersTable rows={byUser.data ?? []} />
        </>
      )}
    </div>
  )
}

// ── Stat card ─────────────────────────────────────────────────────────────────

function StatCard({ label, value }: { label: string; value: string }) {
  return (
    <div style={{
      background: 'var(--color-surface, #fff)',
      border: '1px solid var(--color-border, #e5e7eb)',
      borderRadius: '8px',
      padding: '16px 20px',
    }}>
      <div style={{ fontSize: '12px', color: '#6b7280', marginBottom: '6px', textTransform: 'uppercase', letterSpacing: '0.05em' }}>{label}</div>
      <div style={{ fontSize: '24px', fontWeight: 700 }}>{value}</div>
    </div>
  )
}

// ── Daily chart (last 60 days, one line per page) ───────────────────────────────

function DailyChart({ data }: { data: UsageDaily[] }) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const chartRef = useRef<Chart | null>(null)

  useEffect(() => {
    if (!canvasRef.current || data.length === 0) return
    if (chartRef.current) { chartRef.current.destroy(); chartRef.current = null }

    const days = Array.from(new Set(data.map((d) => d.day))).sort()
    const labels = days.map((day) => new Date(day).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }))

    const chartData: ChartData<'line'> = {
      labels,
      datasets: (['dashboard', 'dynamic', 'map'] as const).map((page) => ({
        label: PAGE_LABELS[page],
        data: days.map((day) => {
          const row = data.find((d) => d.day === day && d.page === page)
          return row ? Number(row.total_views) : 0
        }),
        borderColor: PAGE_COLORS[page],
        backgroundColor: 'transparent',
        tension: 0.3,
        fill: false,
        pointRadius: 3,
      })),
    }

    chartRef.current = new Chart(canvasRef.current, {
      type: 'line',
      data: chartData,
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: { legend: { position: 'top' }, title: { display: false } },
        scales: { y: { beginAtZero: true, ticks: { precision: 0 } } },
      },
    })

    return () => { chartRef.current?.destroy(); chartRef.current = null }
  }, [data])

  if (data.length === 0) return (
    <div style={{
      background: 'var(--color-surface, #fff)',
      border: '1px solid var(--color-border, #e5e7eb)',
      borderRadius: '8px',
      padding: '32px 20px',
      marginBottom: '8px',
      textAlign: 'center',
      color: '#9ca3af',
      fontSize: '13px',
    }}>
      Daily activity (last 60 days) — no page views recorded yet
    </div>
  )

  return (
    <div style={{
      background: 'var(--color-surface, #fff)',
      border: '1px solid var(--color-border, #e5e7eb)',
      borderRadius: '8px',
      padding: '16px 20px',
      marginBottom: '8px',
    }}>
      <div style={{ fontSize: '13px', fontWeight: 600, marginBottom: '12px', color: '#374151' }}>Daily activity (last 60 days)</div>
      <div style={{ height: '200px' }}>
        <canvas ref={canvasRef} />
      </div>
    </div>
  )
}

// ── Monthly chart (durable rollup, unbounded history) ───────────────────────────

function MonthlyChart({ data }: { data: UsageMonthly[] }) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const chartRef = useRef<Chart | null>(null)

  useEffect(() => {
    if (!canvasRef.current || data.length === 0) return
    if (chartRef.current) { chartRef.current.destroy(); chartRef.current = null }

    const months = Array.from(new Set(data.map((d) => d.usage_month))).sort()
    const labels = months.map((m) => new Date(m).toLocaleDateString(undefined, { year: 'numeric', month: 'short' }))

    const chartData: ChartData<'bar'> = {
      labels,
      datasets: (['dashboard', 'dynamic', 'map'] as const).map((page) => ({
        label: PAGE_LABELS[page],
        data: months.map((m) => {
          const row = data.find((d) => d.usage_month === m && d.page === page)
          return row ? Number(row.total_views) : 0
        }),
        backgroundColor: PAGE_COLORS[page],
      })),
    }

    chartRef.current = new Chart(canvasRef.current, {
      type: 'bar',
      data: chartData,
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: { legend: { position: 'top' }, title: { display: false } },
        scales: { x: { stacked: true }, y: { stacked: true, beginAtZero: true, ticks: { precision: 0 } } },
      },
    })

    return () => { chartRef.current?.destroy(); chartRef.current = null }
  }, [data])

  if (data.length === 0) return (
    <div style={{
      background: 'var(--color-surface, #fff)',
      border: '1px solid var(--color-border, #e5e7eb)',
      borderRadius: '8px',
      padding: '32px 20px',
      marginBottom: '8px',
      textAlign: 'center',
      color: '#9ca3af',
      fontSize: '13px',
    }}>
      Monthly trend — no completed months rolled up yet (runs on the 1st of each month)
    </div>
  )

  return (
    <div style={{
      background: 'var(--color-surface, #fff)',
      border: '1px solid var(--color-border, #e5e7eb)',
      borderRadius: '8px',
      padding: '16px 20px',
      marginBottom: '8px',
    }}>
      <div style={{ fontSize: '13px', fontWeight: 600, marginBottom: '12px', color: '#374151' }}>Monthly trend (long-term rollup)</div>
      <div style={{ height: '200px' }}>
        <canvas ref={canvasRef} />
      </div>
    </div>
  )
}

// ── Per-user table ────────────────────────────────────────────────────────────

const USAGE_COLUMNS: AdminColumn<UsageByUser>[] = [
  { key: 'user', header: 'User', sortValue: (r) => r.user_email ?? r.user_id, render: (r) => r.user_email ?? r.user_id },
  { key: 'last_seen', header: 'Last seen', sortValue: (r) => new Date(r.last_seen).getTime(), render: (r) => new Date(r.last_seen).toLocaleString() },
  { key: 'dashboard_views', header: 'Dashboard', align: 'right', sortValue: (r) => Number(r.dashboard_views), render: (r) => Number(r.dashboard_views).toLocaleString() },
  { key: 'dynamic_views', header: 'Dynamic Data', align: 'right', sortValue: (r) => Number(r.dynamic_views), render: (r) => Number(r.dynamic_views).toLocaleString() },
  { key: 'map_views', header: 'Map', align: 'right', sortValue: (r) => Number(r.map_views), render: (r) => Number(r.map_views).toLocaleString() },
  { key: 'total_views', header: 'Total', align: 'right', sortValue: (r) => Number(r.total_views), render: (r) => Number(r.total_views).toLocaleString() },
]

function UsersTable({ rows }: { rows: UsageByUser[] }) {
  return (
    <AdminDataTable
      data={rows}
      rowKey={(r) => r.user_id}
      columns={USAGE_COLUMNS}
      emptyMessage="No page views recorded yet."
      defaultSortKey="total_views"
      defaultSortDir="desc"
    />
  )
}
