import { useEffect, useRef, useState } from 'react'
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
  useWaDaily,
  useWaFlowSummary,
  useWaFunnel,
  useWaErrors,
  useWaErrorsCount,
  WA_ERRORS_PAGE_SIZE,
  type WaDaily,
  type WaFlowSummary,
  type WaError,
  type WaFunnelRow,
} from '@/features/admin/queries'
import { AdminDataTable, type AdminColumn, type ServerPaginationInfo } from '@/features/admin/components/AdminDataTable'

Chart.register(CategoryScale, LinearScale, PointElement, LineElement, BarElement, Title, Tooltip, Legend, Filler)

export function AdminWhatsAppPage() {
  const daily = useWaDaily()
  const flowSummary = useWaFlowSummary()
  const [errorsPage, setErrorsPage] = useState(1)
  const errors = useWaErrors(errorsPage)
  const errorsCount = useWaErrorsCount()
  const errorsTotalPages = Math.max(1, Math.ceil((errorsCount.data ?? 0) / WA_ERRORS_PAGE_SIZE))
  const [selectedFlow, setSelectedFlow] = useState<string | null>(null)

  function handleRefresh() {
    void daily.refetch()
    void flowSummary.refetch()
    void errors.refetch()
    void errorsCount.refetch()
  }

  const flows = flowSummary.data?.map((r) => r.flow) ?? []
  const activeFlow = selectedFlow ?? flows[0] ?? null

  const last30 = (daily.data ?? []).filter((d) => {
    const diff = (Date.now() - new Date(d.day).getTime()) / 86_400_000
    return diff <= 30
  })
  const totalEvents = last30.reduce((s, d) => s + Number(d.total_events), 0)
  const totalCompletions = last30.reduce((s, d) => s + Number(d.completions), 0)
  const totalErrors = last30.reduce((s, d) => s + Number(d.errors), 0)
  const topFlow = flowSummary.data?.[0]?.flow ?? '—'

  const isLoading = daily.isLoading || flowSummary.isLoading

  return (
    <div className="admin-page">
      <div className="admin-page-header">
        <h1 className="admin-page-title">WhatsApp Analytics</h1>
        <button
          className="admin-btn"
          onClick={handleRefresh}
          disabled={daily.isFetching || flowSummary.isFetching || errors.isFetching}
        >
          {(daily.isFetching || flowSummary.isFetching || errors.isFetching) ? 'Refreshing…' : 'Refresh'}
        </button>
      </div>

      {isLoading && <p className="admin-muted">Loading…</p>}
      {(daily.isError || flowSummary.isError) && (
        <p className="admin-error">Failed to load analytics.</p>
      )}

      {!isLoading && (
        <>
          <div style={{ display: 'grid', gridTemplateColumns: 'repeat(4, 1fr)', gap: '12px', marginBottom: '24px' }}>
            <StatCard label="Total events" value={totalEvents.toLocaleString()} />
            <StatCard label="Completions" value={totalCompletions.toLocaleString()} />
            <StatCard label="Errors" value={totalErrors.toLocaleString()} accent={totalErrors > 0 ? 'red' : undefined} />
            <StatCard label="Top flow" value={topFlow} />
          </div>

          <DailyChart data={daily.data ?? []} />

          {flowSummary.data && flowSummary.data.length > 0 && (
            <>
              <h2 style={{ fontSize: '15px', fontWeight: 600, margin: '24px 0 10px' }}>Flow summary</h2>
              <FlowSummaryTable rows={flowSummary.data} />
            </>
          )}

          {flows.length > 0 && (
            <>
              <div style={{ display: 'flex', alignItems: 'center', gap: '12px', margin: '24px 0 10px' }}>
                <h2 style={{ fontSize: '15px', fontWeight: 600, margin: 0 }}>Step funnel</h2>
                <select
                  className="admin-select"
                  value={activeFlow ?? ''}
                  onChange={(e) => setSelectedFlow(e.target.value)}
                >
                  {flows.map((f) => (
                    <option key={f} value={f}>{f}</option>
                  ))}
                </select>
              </div>
              <FunnelTable flow={activeFlow} />
            </>
          )}

          {(errorsCount.data ?? 0) > 0 && (
            <>
              <h2 style={{ fontSize: '15px', fontWeight: 600, margin: '24px 0 10px' }}>Recent errors</h2>
              <ErrorsTable
                rows={errors.data ?? []}
                isLoading={errors.isLoading}
                serverPagination={{ page: errorsPage, totalPages: errorsTotalPages, total: errorsCount.data ?? 0, onPage: setErrorsPage }}
              />
            </>
          )}
        </>
      )}
    </div>
  )
}

// ── Stat card ─────────────────────────────────────────────────────────────────

function StatCard({ label, value, accent }: { label: string; value: string; accent?: 'red' }) {
  return (
    <div style={{
      background: 'var(--color-surface, #fff)',
      border: '1px solid var(--color-border, #e5e7eb)',
      borderRadius: '8px',
      padding: '16px 20px',
    }}>
      <div style={{ fontSize: '12px', color: '#6b7280', marginBottom: '6px', textTransform: 'uppercase', letterSpacing: '0.05em' }}>{label}</div>
      <div style={{ fontSize: '24px', fontWeight: 700, color: accent === 'red' ? '#dc2626' : 'inherit' }}>{value}</div>
    </div>
  )
}

// ── Daily chart ───────────────────────────────────────────────────────────────

function DailyChart({ data }: { data: WaDaily[] }) {
  const canvasRef = useRef<HTMLCanvasElement>(null)
  const chartRef = useRef<Chart | null>(null)

  useEffect(() => {
    if (!canvasRef.current || data.length === 0) return
    if (chartRef.current) { chartRef.current.destroy(); chartRef.current = null }

    const sorted = [...data].reverse()
    const labels = sorted.map((d) => new Date(d.day).toLocaleDateString(undefined, { month: 'short', day: 'numeric' }))

    const chartData: ChartData<'line'> = {
      labels,
      datasets: [
        {
          label: 'Events',
          data: sorted.map((d) => Number(d.total_events)),
          borderColor: '#3b82f6',
          backgroundColor: 'rgba(59,130,246,0.08)',
          tension: 0.3,
          fill: true,
          pointRadius: 3,
        },
        {
          label: 'Completions',
          data: sorted.map((d) => Number(d.completions)),
          borderColor: '#10b981',
          backgroundColor: 'transparent',
          tension: 0.3,
          fill: false,
          pointRadius: 3,
        },
      ],
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
      Daily activity (last 60 days) — no events recorded yet
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

// ── Flow summary table ────────────────────────────────────────────────────────

const FLOW_SUMMARY_COLUMNS: AdminColumn<WaFlowSummary>[] = [
  { key: 'flow', header: 'Flow', sortValue: (r) => r.flow, render: (r) => <code style={{ fontSize: '12px' }}>{r.flow}</code> },
  { key: 'unique_users', header: 'Users', sortValue: (r) => Number(r.unique_users), render: (r) => Number(r.unique_users).toLocaleString() },
  { key: 'started', header: 'Started', sortValue: (r) => Number(r.started), render: (r) => Number(r.started).toLocaleString() },
  { key: 'completed', header: 'Completed', sortValue: (r) => Number(r.completed), render: (r) => Number(r.completed).toLocaleString() },
  { key: 'abandoned', header: 'Abandoned', sortValue: (r) => Number(r.abandoned), render: (r) => Number(r.abandoned).toLocaleString() },
  { key: 'errors', header: 'Errors', sortValue: (r) => Number(r.errors), render: (r) => Number(r.errors) > 0 ? <span style={{ color: '#dc2626' }}>{Number(r.errors)}</span> : '0' },
  { key: 'completion_pct', header: 'Completion %', sortValue: (r) => r.completion_pct, render: (r) => <CompletionBar pct={r.completion_pct} /> },
]

function FlowSummaryTable({ rows }: { rows: WaFlowSummary[] }) {
  return <AdminDataTable data={rows} rowKey={(r) => r.flow} columns={FLOW_SUMMARY_COLUMNS} />
}

function CompletionBar({ pct }: { pct: number | null }) {
  if (pct === null) return <span className="admin-muted">—</span>
  const n = Number(pct)
  const color = n >= 70 ? '#10b981' : n >= 40 ? '#f59e0b' : '#ef4444'
  return (
    <div style={{ display: 'flex', alignItems: 'center', gap: '8px' }}>
      <div style={{ flex: 1, background: '#f3f4f6', borderRadius: '4px', height: '6px', minWidth: '60px' }}>
        <div style={{ width: `${Math.min(n, 100)}%`, background: color, borderRadius: '4px', height: '6px' }} />
      </div>
      <span style={{ fontSize: '12px', color: '#374151', whiteSpace: 'nowrap' }}>{n}%</span>
    </div>
  )
}

// ── Funnel table ──────────────────────────────────────────────────────────────

function FunnelTable({ flow }: { flow: string | null }) {
  const funnel = useWaFunnel(flow)

  if (funnel.isLoading) return <p className="admin-muted">Loading…</p>
  if (!funnel.data || funnel.data.length === 0) return <p className="admin-muted">No data for this flow yet.</p>

  const maxEntries = Math.max(...funnel.data.map((r) => Number(r.entries)))

  const columns: AdminColumn<WaFunnelRow>[] = [
    { key: 'step', header: 'Step', sortValue: (r) => r.step, render: (r) => <code style={{ fontSize: '12px' }}>{r.step}</code> },
    { key: 'entries', header: 'Events', sortValue: (r) => Number(r.entries), render: (r) => Number(r.entries).toLocaleString() },
    { key: 'unique_users', header: 'Unique users', sortValue: (r) => Number(r.unique_users), render: (r) => Number(r.unique_users).toLocaleString() },
    {
      key: 'volume', header: 'Volume',
      render: (r) => {
        const pct = maxEntries > 0 ? (Number(r.entries) / maxEntries) * 100 : 0
        return (
          <div style={{ background: '#f3f4f6', borderRadius: '4px', height: '6px', minWidth: '80px' }}>
            <div style={{ width: `${pct}%`, background: '#3b82f6', borderRadius: '4px', height: '6px' }} />
          </div>
        )
      },
    },
  ]

  return <AdminDataTable data={funnel.data} rowKey={(r) => r.step} columns={columns} />
}

// ── Errors table ──────────────────────────────────────────────────────────────

const ERRORS_COLUMNS: AdminColumn<WaError>[] = [
  { key: 'flow', header: 'Flow', sortValue: (r) => r.flow, render: (r) => <code style={{ fontSize: '12px' }}>{r.flow}</code> },
  { key: 'from_step', header: 'From step', sortValue: (r) => r.from_step, render: (r) => <code style={{ fontSize: '12px' }}>{r.from_step ?? '—'}</code> },
  { key: 'to_step', header: 'To step', sortValue: (r) => r.to_step, render: (r) => <code style={{ fontSize: '12px' }}>{r.to_step}</code> },
  { key: 'occurred_at', header: 'When', sortValue: (r) => r.occurred_at, render: (r) => new Date(r.occurred_at).toLocaleString() },
]

function ErrorsTable({ rows, isLoading, serverPagination }: { rows: WaError[]; isLoading?: boolean; serverPagination: ServerPaginationInfo }) {
  return (
    <AdminDataTable
      data={rows}
      rowKey={(r) => r.id}
      columns={ERRORS_COLUMNS}
      isLoading={isLoading}
      serverPagination={serverPagination}
    />
  )
}
