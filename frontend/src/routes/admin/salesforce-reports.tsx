import { useEffect, useMemo, useState } from 'react'
import {
  useAdminReportConfig,
  useSourceViewColumns,
  useSetReportDimensions,
  useSetReportMeasures,
  type AdminReportDimension,
  type AdminReportMeasure,
  type AdminReportEntry,
} from '@/features/admin/reportConfigQueries'

const NUMERIC_TYPES = new Set(['integer', 'numeric', 'bigint', 'double precision', 'real', 'smallint'])

function titleize(col: string) {
  return col.replace(/_/g, ' ').replace(/\b\w/g, (c) => c.toUpperCase())
}

function renumber<T extends { sort_order: number }>(rows: T[]): T[] {
  return rows.map((r, i) => ({ ...r, sort_order: (i + 1) * 10 }))
}

function moveItem<T>(arr: T[], from: number, to: number): T[] {
  if (to < 0 || to >= arr.length) return arr
  const next = [...arr]
  const [item] = next.splice(from, 1)
  next.splice(to, 0, item)
  return next
}

// ── Confirm modal ────────────────────────────────────────────────────────────

function ConfirmModal({
  title,
  message,
  confirmLabel,
  confirmVariant = 'primary',
  onConfirm,
  onCancel,
}: {
  title: string
  message: React.ReactNode
  confirmLabel: string
  confirmVariant?: 'primary' | 'danger'
  onConfirm: () => void
  onCancel: () => void
}) {
  return (
    <div className="admin-modal-backdrop">
      <div className="admin-modal">
        <h3 className="admin-modal-title">{title}</h3>
        <p>{message}</p>
        <div className="admin-modal-actions">
          <button className="admin-btn admin-btn--secondary" onClick={onCancel}>Cancel</button>
          <button className={`admin-btn admin-btn--${confirmVariant}`} onClick={onConfirm}>{confirmLabel}</button>
        </div>
      </div>
    </div>
  )
}

export function AdminSalesforceReportsPage() {
  const { data: reports, isLoading } = useAdminReportConfig()
  const [reportKey, setReportKey] = useState<string | null>(null)
  const [dirty, setDirty] = useState<{ dim: boolean; mea: boolean }>({ dim: false, mea: false })

  const activeReportKey = reportKey ?? reports?.[0]?.report_key ?? null

  const report: AdminReportEntry | undefined = useMemo(
    () => reports?.find((r) => r.report_key === activeReportKey),
    [reports, activeReportKey],
  )

  function switchReport(key: string) {
    if (key === activeReportKey) return
    if ((dirty.dim || dirty.mea) && !window.confirm('Discard unsaved changes?')) return
    setDirty({ dim: false, mea: false })
    setReportKey(key)
  }

  return (
    <div className="admin-page">
      <div className="admin-page-header">
        <h1 className="admin-page-title">Salesforce Reports</h1>
        <a
          className="admin-btn admin-btn--secondary admin-btn--sm"
          href="/salesforce-report"
          target="_blank"
          rel="noreferrer"
        >
          Preview /salesforce-report
        </a>
      </div>
      <p className="admin-table-muted" style={{ marginBottom: 16 }}>
        Control which columns show up as group-by dimensions and measures on the{' '}
        <strong>/salesforce-report</strong> page, and set friendlier display names for them.
      </p>

      {isLoading ? (
        <div className="admin-loading">Loading…</div>
      ) : (
        <>
          <div className="admin-page-header" style={{ marginBottom: 12 }}>
            <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
              {(reports ?? []).map((r) => (
                <button
                  key={r.report_key}
                  className={`admin-btn admin-btn--sm ${activeReportKey === r.report_key ? 'admin-btn--primary' : 'admin-btn--secondary'}`}
                  onClick={() => switchReport(r.report_key)}
                >
                  {r.label}
                </button>
              ))}
            </div>
          </div>

          {report && (
            <>
              <DimensionsPanel key={`dim-${report.report_key}`} report={report} onDirtyChange={(d) => setDirty((prev) => ({ ...prev, dim: d }))} />
              <MeasuresPanel key={`mea-${report.report_key}`} report={report} onDirtyChange={(d) => setDirty((prev) => ({ ...prev, mea: d }))} />
            </>
          )}
        </>
      )}
    </div>
  )
}

// ── Dimensions panel ─────────────────────────────────────────────────────────

function DimensionsPanel({ report, onDirtyChange }: { report: AdminReportEntry; onDirtyChange: (dirty: boolean) => void }) {
  const { data: sourceColumns } = useSourceViewColumns(report.report_key)
  const setDimensions = useSetReportDimensions()
  const [rows, setRows] = useState<AdminReportDimension[]>(report.dimensions)
  const [error, setError] = useState<string | null>(null)
  const [pendingRemove, setPendingRemove] = useState<number | null>(null)
  const [confirmSave, setConfirmSave] = useState(false)

  const availableToAdd = useMemo(
    () => (sourceColumns ?? []).filter((c) => !rows.some((r) => r.column_name === c.column_name)),
    [sourceColumns, rows],
  )
  const [addCol, setAddCol] = useState('')

  const errors = useMemo(() => {
    const byIndex = new Map<number, string>()
    const labelCounts = new Map<string, number>()
    rows.forEach((r) => {
      const key = r.label.trim().toLowerCase()
      if (key) labelCounts.set(key, (labelCounts.get(key) ?? 0) + 1)
    })
    rows.forEach((r, i) => {
      const key = r.label.trim().toLowerCase()
      if (!key) byIndex.set(i, 'Label is required')
      else if ((labelCounts.get(key) ?? 0) > 1) byIndex.set(i, 'Duplicate label')
    })
    return byIndex
  }, [rows])
  const isValid = errors.size === 0

  const isDirty = useMemo(() => {
    const normalize = (list: AdminReportDimension[]) =>
      list.map((r) => ({ column_name: r.column_name, label: r.label, enabled: r.enabled, sort_order: r.sort_order }))
    return JSON.stringify(normalize(rows)) !== JSON.stringify(normalize(report.dimensions))
  }, [rows, report.dimensions])

  useEffect(() => onDirtyChange(isDirty), [isDirty, onDirtyChange])

  useEffect(() => {
    if (!isDirty) return
    const handler = (e: BeforeUnloadEvent) => {
      e.preventDefault()
      e.returnValue = ''
    }
    window.addEventListener('beforeunload', handler)
    return () => window.removeEventListener('beforeunload', handler)
  }, [isDirty])

  function addRow() {
    if (!addCol) return
    setDimensions.reset()
    setRows((prev) => renumber([...prev, { id: -Date.now(), column_name: addCol, label: titleize(addCol), enabled: true, sort_order: 0 }]))
    setAddCol('')
  }

  function updateRow(i: number, patch: Partial<AdminReportDimension>) {
    setDimensions.reset()
    setRows((prev) => prev.map((r, idx) => (idx === i ? { ...r, ...patch } : r)))
  }

  function moveRow(i: number, direction: -1 | 1) {
    setDimensions.reset()
    setRows((prev) => renumber(moveItem(prev, i, i + direction)))
  }

  function doRemove(i: number) {
    setDimensions.reset()
    setRows((prev) => renumber(prev.filter((_, idx) => idx !== i)))
  }

  function removeRow(i: number) {
    const row = rows[i]
    if (row.id > 0) {
      setPendingRemove(i)
    } else {
      doRemove(i)
    }
  }

  const isRisky = useMemo(
    () => report.dimensions.some((orig) => orig.enabled && (!rows.some((r) => r.id === orig.id && r.enabled))),
    [report.dimensions, rows],
  )

  async function doSave() {
    setError(null)
    try {
      await setDimensions.mutateAsync({
        reportKey: report.report_key,
        dimensions: rows.map((r) => ({ column_name: r.column_name, label: r.label, enabled: r.enabled, sort_order: r.sort_order })),
      })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Save failed')
    }
  }

  function save() {
    if (isRisky) {
      setConfirmSave(true)
      return
    }
    void doSave()
  }

  return (
    <div style={{ marginBottom: 24 }}>
      <div
        className="admin-page-header"
        style={{ marginBottom: 8, position: 'sticky', top: 0, zIndex: 1, background: 'var(--cream)', paddingBottom: 8, borderBottom: '1px solid var(--border)' }}
      >
        <h2 className="admin-page-title" style={{ fontSize: '1.1rem' }}>
          Dimensions (group by / filter)
          {isDirty && <span className="admin-badge admin-badge--amber" style={{ marginLeft: 10, verticalAlign: 'middle' }}>Unsaved changes</span>}
        </h2>
        <button className="admin-btn admin-btn--primary admin-btn--sm" onClick={save} disabled={setDimensions.isPending || !isValid || !isDirty}>
          {setDimensions.isPending ? 'Saving…' : 'Save Dimensions'}
        </button>
      </div>
      {setDimensions.isSuccess && !setDimensions.isPending && (
        <p className="admin-success" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8 }}>
          Dimensions saved.
          <button
            type="button"
            onClick={() => setDimensions.reset()}
            title="Dismiss"
            style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'inherit', fontWeight: 700, lineHeight: 1 }}
          >✕</button>
        </p>
      )}
      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead>
            <tr>
              <th>Enabled</th>
              <th>Column</th>
              <th>Display Label</th>
              <th>Order</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 && (
              <tr>
                <td colSpan={5} className="admin-table-muted">No dimensions configured yet — add one below.</td>
              </tr>
            )}
            {rows.map((r, i) => (
              <tr key={r.id}>
                <td>
                  <input type="checkbox" checked={r.enabled} onChange={(e) => updateRow(i, { enabled: e.target.checked })} />
                </td>
                <td className="admin-table-muted">{r.column_name}</td>
                <td>
                  <input className="admin-input" value={r.label} onChange={(e) => updateRow(i, { label: e.target.value })} />
                  {errors.has(i) && <div className="admin-error" style={{ fontSize: '0.8rem' }}>{errors.get(i)}</div>}
                </td>
                <td>
                  <div style={{ display: 'flex', gap: 2 }}>
                    <button className="admin-btn admin-btn--sm admin-btn--secondary" onClick={() => moveRow(i, -1)} disabled={i === 0} title="Move up">▲</button>
                    <button className="admin-btn admin-btn--sm admin-btn--secondary" onClick={() => moveRow(i, 1)} disabled={i === rows.length - 1} title="Move down">▼</button>
                  </div>
                </td>
                <td>
                  <button className="admin-btn admin-btn--sm admin-btn--danger" onClick={() => removeRow(i)}>Remove</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div style={{ display: 'flex', gap: 8, alignItems: 'center', padding: '12px 0' }}>
        <select className="admin-input" value={addCol} onChange={(e) => setAddCol(e.target.value)} style={{ minWidth: 220 }}>
          <option value="">Add column…</option>
          {availableToAdd.map((c) => (
            <option key={c.column_name} value={c.column_name}>{c.column_name} ({c.data_type})</option>
          ))}
        </select>
        <button className="admin-btn admin-btn--secondary admin-btn--sm" onClick={addRow} disabled={!addCol}>+ Add</button>
      </div>

      {error && <div className="admin-error">{error}</div>}

      {pendingRemove !== null && (
        <ConfirmModal
          title="Remove dimension"
          message={`Remove "${rows[pendingRemove]?.label}"? Users using this on /salesforce-report will lose it once you save.`}
          confirmLabel="Remove"
          confirmVariant="danger"
          onCancel={() => setPendingRemove(null)}
          onConfirm={() => {
            doRemove(pendingRemove)
            setPendingRemove(null)
          }}
        />
      )}

      {confirmSave && (
        <ConfirmModal
          title="Save dimensions"
          message="This will remove or disable one or more columns currently available to users on /salesforce-report. Continue?"
          confirmLabel="Save"
          onCancel={() => setConfirmSave(false)}
          onConfirm={() => {
            setConfirmSave(false)
            void doSave()
          }}
        />
      )}
    </div>
  )
}

// ── Measures panel ───────────────────────────────────────────────────────────

function MeasuresPanel({ report, onDirtyChange }: { report: AdminReportEntry; onDirtyChange: (dirty: boolean) => void }) {
  const { data: sourceColumns } = useSourceViewColumns(report.report_key)
  const setMeasures = useSetReportMeasures()
  const [rows, setRows] = useState<AdminReportMeasure[]>(report.measures)
  const [error, setError] = useState<string | null>(null)
  const [pendingRemove, setPendingRemove] = useState<number | null>(null)
  const [confirmSave, setConfirmSave] = useState(false)

  const numericColumns = useMemo(
    () => (sourceColumns ?? []).filter((c) => NUMERIC_TYPES.has(c.data_type)),
    [sourceColumns],
  )
  const availableToAdd = useMemo(
    () => numericColumns.filter((c) => !rows.some((r) => r.column_name === c.column_name)),
    [numericColumns, rows],
  )
  const [addCol, setAddCol] = useState('')
  const hasCount = rows.some((r) => r.agg_type === 'count')

  const errors = useMemo(() => {
    const byIndex = new Map<number, string>()
    const labelCounts = new Map<string, number>()
    rows.forEach((r) => {
      const key = r.label.trim().toLowerCase()
      if (key) labelCounts.set(key, (labelCounts.get(key) ?? 0) + 1)
    })
    rows.forEach((r, i) => {
      const key = r.label.trim().toLowerCase()
      if (!key) byIndex.set(i, 'Label is required')
      else if ((labelCounts.get(key) ?? 0) > 1) byIndex.set(i, 'Duplicate label')
    })
    return byIndex
  }, [rows])
  const isValid = errors.size === 0

  const isDirty = useMemo(() => {
    const normalize = (list: AdminReportMeasure[]) =>
      list.map((r) => ({ column_name: r.column_name, label: r.label, agg_type: r.agg_type, enabled: r.enabled, sort_order: r.sort_order }))
    return JSON.stringify(normalize(rows)) !== JSON.stringify(normalize(report.measures))
  }, [rows, report.measures])

  useEffect(() => onDirtyChange(isDirty), [isDirty, onDirtyChange])

  useEffect(() => {
    if (!isDirty) return
    const handler = (e: BeforeUnloadEvent) => {
      e.preventDefault()
      e.returnValue = ''
    }
    window.addEventListener('beforeunload', handler)
    return () => window.removeEventListener('beforeunload', handler)
  }, [isDirty])

  function addCountRow() {
    setMeasures.reset()
    setRows((prev) => renumber([...prev, { id: -Date.now(), column_name: null, label: 'Count', agg_type: 'count', enabled: true, sort_order: 0 }]))
  }

  function addSumRow() {
    if (!addCol) return
    setMeasures.reset()
    setRows((prev) => renumber([...prev, { id: -Date.now(), column_name: addCol, label: `Total ${titleize(addCol)}`, agg_type: 'sum', enabled: true, sort_order: 0 }]))
    setAddCol('')
  }

  function updateRow(i: number, patch: Partial<AdminReportMeasure>) {
    setMeasures.reset()
    setRows((prev) => prev.map((r, idx) => (idx === i ? { ...r, ...patch } : r)))
  }

  function moveRow(i: number, direction: -1 | 1) {
    setMeasures.reset()
    setRows((prev) => renumber(moveItem(prev, i, i + direction)))
  }

  function doRemove(i: number) {
    setMeasures.reset()
    setRows((prev) => renumber(prev.filter((_, idx) => idx !== i)))
  }

  function removeRow(i: number) {
    const row = rows[i]
    if (row.id > 0) {
      setPendingRemove(i)
    } else {
      doRemove(i)
    }
  }

  const isRisky = useMemo(
    () => report.measures.some((orig) => orig.enabled && (!rows.some((r) => r.id === orig.id && r.enabled))),
    [report.measures, rows],
  )

  async function doSave() {
    setError(null)
    try {
      await setMeasures.mutateAsync({
        reportKey: report.report_key,
        measures: rows.map((r) => ({ column_name: r.column_name, label: r.label, agg_type: r.agg_type, enabled: r.enabled, sort_order: r.sort_order })),
      })
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Save failed')
    }
  }

  function save() {
    if (isRisky) {
      setConfirmSave(true)
      return
    }
    void doSave()
  }

  return (
    <div>
      <div
        className="admin-page-header"
        style={{ marginBottom: 8, position: 'sticky', top: 0, zIndex: 1, background: 'var(--cream)', paddingBottom: 8, borderBottom: '1px solid var(--border)' }}
      >
        <h2 className="admin-page-title" style={{ fontSize: '1.1rem' }}>
          Measures (aggregates)
          {isDirty && <span className="admin-badge admin-badge--amber" style={{ marginLeft: 10, verticalAlign: 'middle' }}>Unsaved changes</span>}
        </h2>
        <button className="admin-btn admin-btn--primary admin-btn--sm" onClick={save} disabled={setMeasures.isPending || !isValid || !isDirty}>
          {setMeasures.isPending ? 'Saving…' : 'Save Measures'}
        </button>
      </div>
      {setMeasures.isSuccess && !setMeasures.isPending && (
        <p className="admin-success" style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', gap: 8 }}>
          Measures saved.
          <button
            type="button"
            onClick={() => setMeasures.reset()}
            title="Dismiss"
            style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'inherit', fontWeight: 700, lineHeight: 1 }}
          >✕</button>
        </p>
      )}
      <div className="admin-table-wrap">
        <table className="admin-table">
          <thead>
            <tr>
              <th>Enabled</th>
              <th>Type</th>
              <th>Column</th>
              <th>Display Label</th>
              <th>Order</th>
              <th></th>
            </tr>
          </thead>
          <tbody>
            {rows.length === 0 && (
              <tr>
                <td colSpan={6} className="admin-table-muted">No measures configured yet — add one below.</td>
              </tr>
            )}
            {rows.map((r, i) => (
              <tr key={r.id}>
                <td>
                  <input type="checkbox" checked={r.enabled} onChange={(e) => updateRow(i, { enabled: e.target.checked })} />
                </td>
                <td className="admin-table-muted">{r.agg_type === 'count' ? 'Count' : 'Sum'}</td>
                <td className="admin-table-muted">{r.column_name ?? '—'}</td>
                <td>
                  <input className="admin-input" value={r.label} onChange={(e) => updateRow(i, { label: e.target.value })} />
                  {errors.has(i) && <div className="admin-error" style={{ fontSize: '0.8rem' }}>{errors.get(i)}</div>}
                </td>
                <td>
                  <div style={{ display: 'flex', gap: 2 }}>
                    <button className="admin-btn admin-btn--sm admin-btn--secondary" onClick={() => moveRow(i, -1)} disabled={i === 0} title="Move up">▲</button>
                    <button className="admin-btn admin-btn--sm admin-btn--secondary" onClick={() => moveRow(i, 1)} disabled={i === rows.length - 1} title="Move down">▼</button>
                  </div>
                </td>
                <td>
                  <button className="admin-btn admin-btn--sm admin-btn--danger" onClick={() => removeRow(i)}>Remove</button>
                </td>
              </tr>
            ))}
          </tbody>
        </table>
      </div>

      <div style={{ display: 'flex', gap: 8, alignItems: 'center', padding: '12px 0', flexWrap: 'wrap' }}>
        <button
          className="admin-btn admin-btn--secondary admin-btn--sm"
          onClick={addCountRow}
          disabled={hasCount}
          title={hasCount ? 'Only one Count measure is allowed per report' : undefined}
        >
          + Add Count
        </button>
        <select className="admin-input" value={addCol} onChange={(e) => setAddCol(e.target.value)} style={{ minWidth: 220 }}>
          <option value="">Add sum of column…</option>
          {availableToAdd.map((c) => (
            <option key={c.column_name} value={c.column_name}>{c.column_name} ({c.data_type})</option>
          ))}
        </select>
        <button className="admin-btn admin-btn--secondary admin-btn--sm" onClick={addSumRow} disabled={!addCol}>+ Add Sum</button>
      </div>

      {error && <div className="admin-error">{error}</div>}

      {pendingRemove !== null && (
        <ConfirmModal
          title="Remove measure"
          message={`Remove "${rows[pendingRemove]?.label}"? Users using this on /salesforce-report will lose it once you save.`}
          confirmLabel="Remove"
          confirmVariant="danger"
          onCancel={() => setPendingRemove(null)}
          onConfirm={() => {
            doRemove(pendingRemove)
            setPendingRemove(null)
          }}
        />
      )}

      {confirmSave && (
        <ConfirmModal
          title="Save measures"
          message="This will remove or disable one or more measures currently available to users on /salesforce-report. Continue?"
          confirmLabel="Save"
          onCancel={() => setConfirmSave(false)}
          onConfirm={() => {
            setConfirmSave(false)
            void doSave()
          }}
        />
      )}
    </div>
  )
}
