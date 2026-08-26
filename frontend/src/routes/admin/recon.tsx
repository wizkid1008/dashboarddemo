import { useState, useMemo } from 'react'
import { useWarehouseCounts, type WarehouseCountRow } from '@/features/admin/reconQueries'
import { AdminDataTable, type AdminColumn } from '@/features/admin/components/AdminDataTable'

// ── Helpers ───────────────────────────────────────────────────────────────────

function exportCsv(rows: WarehouseCountRow[]) {
  const headers = ['Source Object', 'Country', 'Year', 'Row Count']
  const lines = rows.map(r => [
    r.source_object,
    r.country ?? '—',
    r.year != null ? String(r.year) : '—',
    String(r.row_count),
  ])
  const csv = [headers, ...lines]
    .map(row => row.map(c => `"${c.replace(/"/g, '""')}"`).join(','))
    .join('\n')
  const blob = new Blob([csv], { type: 'text/csv' })
  const url  = URL.createObjectURL(blob)
  const a    = document.createElement('a')
  a.href     = url
  a.download = 'warehouse-recon.csv'
  a.click()
  URL.revokeObjectURL(url)
}

// ── Notes ─────────────────────────────────────────────────────────────────────

const NOTES = [
  {
    table: 'fact_children_supported',
    desc:  'Counts active school-programme academic records (Salesforce Academic_Record__c where record type is School). Grouped by country and year. Rows with no geography match are excluded.',
  },
  {
    table: 'fact_post_school_support',
    desc:  'Counts post-school academic records (same Salesforce object, Post School record type). Grouped by country and year.',
  },
  {
    table: 'fact_guide_assignment',
    desc:  'Counts active guide roles (Salesforce Guide_Role__c). Year is derived from the date the guide joined the programme. Guides with no join date appear under year "—".',
  },
  {
    table: 'fact_grants',
    desc:  'Counts grant/bursary records (Salesforce Grant_Loan__c). Year is derived from the grant date. Grants with no date appear under year "—".',
  },
  {
    table: 'fact_loans',
    desc:  'Counts loan records (Salesforce Loan__c). Year is derived from the disbursal date. Loans with no disbursal date appear under year "—".',
  },
  {
    table: 'fact_cama_membership',
    desc:  'Counts CAMA memberships (derived from Salesforce Contact where record type is Cama). Year is derived from the date the member joined CAMA. Members with no join date appear under year "—".',
  },
  {
    table: 'dim_contact',
    desc:  'Counts current contact dimension records (SCD Type 2 — only the latest version of each contact is counted). No year breakdown; country comes directly from the contact record.',
  },
  {
    table: 'dim_school',
    desc:  'Counts current school dimension records (SCD Type 2 — only the latest version of each school is counted). No year breakdown.',
  },
]

function ReconNotes() {
  const [open, setOpen] = useState(false)
  return (
    <div style={{ marginBottom: 20, border: '1px solid var(--admin-border, #e5e7eb)', borderRadius: 8 }}>
      <button
        onClick={() => setOpen(o => !o)}
        style={{
          width: '100%',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between',
          padding: '10px 14px',
          background: 'none',
          border: 'none',
          cursor: 'pointer',
          fontWeight: 600,
          fontSize: 13,
          color: 'inherit',
          textAlign: 'left',
        }}
      >
        <span>How values are calculated</span>
        <svg
          width="14" height="14" viewBox="0 0 20 20" fill="none"
          style={{ transform: open ? 'rotate(180deg)' : 'rotate(0deg)', transition: 'transform 0.15s' }}
        >
          <path d="M5 7l5 5 5-5" stroke="currentColor" strokeWidth="1.8" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>
      {open && (
        <div style={{ padding: '0 14px 14px', borderTop: '1px solid var(--admin-border, #e5e7eb)' }}>
          <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: 13, marginTop: 12 }}>
            <thead>
              <tr>
                <th style={{ textAlign: 'left', paddingBottom: 6, paddingRight: 16, whiteSpace: 'nowrap', fontWeight: 600, opacity: 0.6 }}>Table</th>
                <th style={{ textAlign: 'left', paddingBottom: 6, fontWeight: 600, opacity: 0.6 }}>How it's counted</th>
              </tr>
            </thead>
            <tbody>
              {NOTES.map(n => (
                <tr key={n.table} style={{ verticalAlign: 'top' }}>
                  <td style={{ paddingRight: 16, paddingTop: 6, paddingBottom: 6, whiteSpace: 'nowrap', fontFamily: 'monospace', fontSize: 12 }}>{n.table}</td>
                  <td style={{ paddingTop: 6, paddingBottom: 6, lineHeight: 1.5 }}>{n.desc}</td>
                </tr>
              ))}
            </tbody>
          </table>
          <p style={{ marginTop: 12, fontSize: 12, opacity: 0.6, marginBottom: 0 }}>
            All counts filter to currently-active rows only (lin_is_current = true for facts, scd_is_current = true for dimensions).
            Rows where geography or date could not be resolved appear with country or year shown as "—" and can be filtered using the dropdowns above.
          </p>
        </div>
      )}
    </div>
  )
}

// ── Page ─────────────────────────────────────────────────────────────────────

export function AdminReconPage() {
  const { data, isLoading, error } = useWarehouseCounts()

  const [filterObject,  setFilterObject]  = useState('')
  const [filterCountry, setFilterCountry] = useState('')
  const [filterYear,    setFilterYear]    = useState('')

  const rows = data ?? []

  const summary = useMemo(() => {
    const totals = new Map<string, number>()
    for (const r of rows) totals.set(r.source_object, (totals.get(r.source_object) ?? 0) + r.row_count)
    return [...totals.entries()]
      .map(([source_object, row_count]) => ({ source_object, row_count }))
      .sort((a, b) => b.row_count - a.row_count)
  }, [rows])

  const allObjects = useMemo(
    () => [...new Set(rows.map(r => r.source_object))].sort(),
    [rows],
  )
  const allCountries = useMemo(
    () => [...new Set(rows.map(r => r.country).filter((c): c is string => c != null))].sort(),
    [rows],
  )
  const allYears = useMemo(
    () => [...new Set(rows.map(r => r.year).filter((y): y is number => y != null))].sort((a, b) => a - b),
    [rows],
  )

  const filtered = useMemo(() => rows.filter(r => {
    if (filterObject && r.source_object !== filterObject) return false
    if (filterCountry) {
      if (filterCountry === 'null') { if (r.country != null) return false }
      else { if (r.country !== filterCountry) return false }
    }
    if (filterYear) {
      if (filterYear === 'null') { if (r.year != null) return false }
      else { if (String(r.year) !== filterYear) return false }
    }
    return true
  }), [rows, filterObject, filterCountry, filterYear])

  return (
    <div className="admin-page">
      <div className="admin-page-header">
        <h1 className="admin-page-title">Salesforce Reconciliation</h1>
        <button
          className="admin-btn admin-btn--ghost"
          onClick={() => exportCsv(filtered)}
          disabled={filtered.length === 0}
        >
          Export CSV
        </button>
      </div>

      {error && (
        <p className="admin-error" style={{ marginBottom: 16 }}>
          Failed to load warehouse counts: {(error as Error).message}
        </p>
      )}

      <ReconNotes />

      {summary.length > 0 && (
        <div style={{ marginBottom: 20 }}>
          <AdminDataTable data={summary} rowKey={(s) => s.source_object} columns={SUMMARY_COLUMNS} />
        </div>
      )}

      <div className="admin-section-header" style={{ marginBottom: 12, flexWrap: 'wrap', gap: 8 }}>
        <select className="admin-select" value={filterObject} onChange={e => setFilterObject(e.target.value)}>
          <option value="">All objects</option>
          {allObjects.map(o => <option key={o} value={o}>{o}</option>)}
        </select>
        <select className="admin-select" value={filterCountry} onChange={e => setFilterCountry(e.target.value)}>
          <option value="">All countries</option>
          {allCountries.map(c => <option key={c} value={c}>{c}</option>)}
          <option value="null">— (no country)</option>
        </select>
        <select className="admin-select" value={filterYear} onChange={e => setFilterYear(e.target.value)}>
          <option value="">All years</option>
          {allYears.map(y => <option key={y} value={y}>{y}</option>)}
          <option value="null">— (no year)</option>
        </select>
      </div>

      <AdminDataTable
        data={filtered}
        rowKey={(r) => `${r.source_object}-${r.country ?? ''}-${r.year ?? ''}`}
        columns={DETAIL_COLUMNS}
        isLoading={isLoading}
        loadingMessage="Loading warehouse counts…"
        emptyMessage="No rows match the current filters."
      />
    </div>
  )
}

const SUMMARY_COLUMNS: AdminColumn<{ source_object: string; row_count: number }>[] = [
  { key: 'source_object', header: 'Source Object', sortValue: (s) => s.source_object, render: (s) => s.source_object },
  {
    key: 'row_count', header: 'Total Row Count', align: 'right', sortValue: (s) => s.row_count,
    render: (s) => <span style={{ fontVariantNumeric: 'tabular-nums' }}>{s.row_count.toLocaleString()}</span>,
  },
]

const DETAIL_COLUMNS: AdminColumn<WarehouseCountRow>[] = [
  { key: 'source_object', header: 'Source Object', sortValue: (r) => r.source_object, render: (r) => r.source_object },
  { key: 'country', header: 'Country', sortValue: (r) => r.country, render: (r) => r.country ?? <span className="admin-muted">—</span> },
  { key: 'year', header: 'Year', sortValue: (r) => r.year, render: (r) => r.year ?? <span className="admin-muted">—</span> },
  {
    key: 'row_count', header: 'Row Count', align: 'right', sortValue: (r) => r.row_count,
    render: (r) => <span style={{ fontVariantNumeric: 'tabular-nums' }}>{r.row_count.toLocaleString()}</span>,
  },
]
