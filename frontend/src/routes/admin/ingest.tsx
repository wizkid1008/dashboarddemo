import { useEffect, useState } from 'react'
import {
  useIngestRuns,
  useIngestRunCount,
  useIngestFnState,
  useEtlBatchLogEntry,
  useDeletionRunLogEntry,
  useTriggerIngest,
  INGEST_RUNS_PAGE_SIZE,
  type IngestRun,
} from '@/features/admin/queries'
import { fmt } from '@/features/admin/Pagination'
import { AdminDataTable, type AdminColumn } from '@/features/admin/components/AdminDataTable'
import { useQueryClient } from '@tanstack/react-query'

const INGEST_COLUMNS: AdminColumn<IngestRun>[] = [
  { key: 'run_id', header: 'Run ID', sortValue: (r) => r.run_id, render: (r) => <span className="admin-table-mono">{r.run_id.slice(0, 8)}…</span> },
  {
    key: 'status', header: 'Status', sortValue: (r) => r.status,
    render: (r) => (
      <>
        <StatusBadge status={r.status} />
        {r.error && <span className="admin-badge admin-badge--red" title={r.error}>!</span>}
      </>
    ),
  },
  { key: 'source', header: 'Source', sortValue: (r) => r.started_by, render: (r) => r.started_by === 'run-ingest' ? 'script' : 'cron' },
  { key: 'since', header: 'Delta since', sortValue: (r) => r.since, render: (r) => <span className="admin-table-mono">{r.since ? fmt(r.since) : 'full'}</span> },
  { key: 'wave', header: 'Wave', sortValue: (r) => r.current_wave, render: (r) => r.current_wave ?? '—' },
  { key: 'attempts', header: 'Attempts', sortValue: (r) => r.attempt_count, render: (r) => r.attempt_count },
  { key: 'started', header: 'Started', sortValue: (r) => r.started_at, render: (r) => fmt(r.started_at) },
  { key: 'finished', header: 'Finished', sortValue: (r) => r.finished_at, render: (r) => r.finished_at ? fmt(r.finished_at) : '—' },
]

export function AdminIngestPage() {
  const [page, setPage] = useState(1)
  const runs = useIngestRuns(page)
  const runCount = useIngestRunCount()
  const trigger = useTriggerIngest()
  const qc = useQueryClient()
  const totalPages = Math.max(1, Math.ceil((runCount.data ?? 0) / INGEST_RUNS_PAGE_SIZE))

  const hasActive = runs.data?.some(
    (r) => r.status === 'in_progress' || r.status === 'leased'
  )

  useEffect(() => {
    if (!hasActive) return
    const id = setInterval(() => {
      void qc.invalidateQueries({ queryKey: ['admin', 'ingest-runs'] })
      void qc.invalidateQueries({ queryKey: ['admin', 'ingest-run-count'] })
    }, 10_000)
    return () => clearInterval(id)
  }, [hasActive, qc])

  return (
    <div className="admin-page">
      <div className="admin-page-header">
        <h1 className="admin-page-title">Salesforce Log</h1>
        <button
          className="admin-btn admin-btn--primary"
          disabled={trigger.isPending || hasActive}
          onClick={() => trigger.mutate()}
        >
          {trigger.isPending ? 'Starting…' : 'Trigger new run'}
        </button>
      </div>

      {trigger.isError && (
        <p className="admin-error">{(trigger.error as Error).message}</p>
      )}
      {trigger.isSuccess && (() => {
        const d = trigger.data as { status?: string; reason?: string; run_id?: string } | null
        if (d?.status === 'skipped' && d.reason === 'ran_recently') {
          return <p className="admin-warning">Skipped — a run completed recently (20-hour cooldown). Check the table below.</p>
        }
        if (d?.status === 'skipped' && d.reason === 'run_in_progress') {
          return <p className="admin-warning">Skipped — a run is already in progress.</p>
        }
        return <p className="admin-success">Run started (ID: {d?.run_id ?? '—'}).</p>
      })()}

      {runs.isError && <p className="admin-error">Failed to load ingest runs.</p>}

      <AdminDataTable
        data={runs.data ?? []}
        rowKey={(r) => r.run_id}
        columns={INGEST_COLUMNS}
        isLoading={runs.isLoading}
        emptyMessage="No ingest runs yet."
        renderExpanded={(run) => <RunDetail run={run} />}
        serverPagination={{ page, totalPages, total: runCount.data ?? 0, onPage: setPage }}
      />
    </div>
  )
}

function RunDetail({ run }: { run: IngestRun }) {
  const fnState = useIngestFnState(run.run_id)
  const etlEntry = useEtlBatchLogEntry(run.run_id)
  const deletionEntry = useDeletionRunLogEntry(run.run_id)

  return (
    <>
      {run.error && (
        <div className="admin-detail-section">
          <p className="admin-detail-label">Ingest error</p>
          <pre className="admin-error-pre">{run.error}</pre>
        </div>
      )}
      {fnState.isLoading && <p className="admin-muted">Loading functions…</p>}
      {fnState.data && fnState.data.length > 0 && (
        <div className="admin-detail-section">
          <p className="admin-detail-label">Ingest Functions</p>
          <table className="admin-table admin-table--nested">
            <thead>
              <tr>
                <th>Function</th>
                <th>Status</th>
                <th>Rows fetched</th>
                <th>Attempts</th>
              </tr>
            </thead>
            <tbody>
              {fnState.data.map((fn) => (
                <tr key={fn.fn_name}>
                  <td className="admin-table-mono">{fn.fn_name}</td>
                  <td><StatusBadge status={fn.status} /></td>
                  <td>{fn.rows_fetched}</td>
                  <td>{fn.attempt_count}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}
      {etlEntry.data && (
        <div className="admin-detail-section">
          <p className="admin-detail-label">ETL Transform</p>
          <table className="admin-table admin-table--nested">
            <thead>
              <tr>
                <th>Status</th>
                <th>Started</th>
                <th>Finished</th>
                <th>Error</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td><StatusBadge status={etlEntry.data.status} /></td>
                <td>{fmt(etlEntry.data.started_at)}</td>
                <td>{etlEntry.data.finished_at ? fmt(etlEntry.data.finished_at) : '—'}</td>
                <td>{etlEntry.data.error_message ? <pre className="admin-error-pre">{etlEntry.data.error_message}</pre> : '—'}</td>
              </tr>
            </tbody>
          </table>
        </div>
      )}
      {deletionEntry.data && (
        <div className="admin-detail-section">
          <p className="admin-detail-label">Deletion Detection</p>
          <table className="admin-table admin-table--nested">
            <thead>
              <tr>
                <th>Status</th>
                <th>Objects queried</th>
                <th>Deletions found</th>
                <th>Deletions applied</th>
                <th>Started</th>
                <th>Finished</th>
                <th>Error</th>
              </tr>
            </thead>
            <tbody>
              <tr>
                <td><StatusBadge status={deletionEntry.data.status} /></td>
                <td>{deletionEntry.data.objects_queried ?? '—'}</td>
                <td>{deletionEntry.data.deletions_found ?? '—'}</td>
                <td>{deletionEntry.data.deletions_applied ?? '—'}</td>
                <td>{fmt(deletionEntry.data.started_at)}</td>
                <td>{deletionEntry.data.finished_at ? fmt(deletionEntry.data.finished_at) : '—'}</td>
                <td>{deletionEntry.data.error ? <pre className="admin-error-pre">{deletionEntry.data.error}</pre> : '—'}</td>
              </tr>
            </tbody>
          </table>
        </div>
      )}
    </>
  )
}


function StatusBadge({ status }: { status: string }) {
  let cls = 'admin-badge'
  if (status === 'completed') cls += ' admin-badge--green'
  else if (status === 'failed') cls += ' admin-badge--red'
  else if (status === 'in_progress' || status === 'leased' || status === 'running') cls += ' admin-badge--blue'
  return <span className={cls}>{status}</span>
}

