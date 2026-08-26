import { useState, useRef } from 'react'
import { useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { fmt } from '@/features/admin/Pagination'
import { AdminDataTable, type AdminColumn } from '@/features/admin/components/AdminDataTable'
import {
  useUploadLog, useUploadLogCount, UPLOAD_LOG_PAGE_SIZE,
  useLevelOneUploadLog, useLevelOneUploadLogCount, LEVEL_ONE_UPLOAD_LOG_PAGE_SIZE,
  useMilestoneUploadLog, useMilestoneUploadLogCount, MILESTONE_UPLOAD_LOG_PAGE_SIZE,
  useDuplicateRows, useLoadedYears, useAllKpiRows, useAllKpiRowCount, useDeleteKpiYear,
  useKpiDefinitionsSummary, useKpiDefinitions, KPI_PAGE_SIZE,
  type UploadLog, type LevelOneUploadLog, type MilestoneUploadLog, type KpiDefinition,
} from '@/features/admin/queries'
import type { ServerPaginationInfo } from '@/features/admin/components/AdminDataTable'

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL as string

// ── Shared parsing helpers ────────────────────────────────────────────────────

function cleanCol(name: unknown, idx: number): string {
  const s = String(name ?? '').trim()
  const cleaned = s
    .replace(/[^\w\s]/g, '')
    .replace(/\s+/g, '_')
    .replace(/_+/g, '_')
    .toLowerCase()
    .replace(/^_+|_+$/g, '')
  return cleaned || `col_${idx}`
}

function toStr(v: unknown): string | null {
  if (v === null || v === undefined || v === '') return null
  if (v instanceof Date) return v.toISOString().slice(0, 10)
  if (typeof v === 'boolean') return v ? 'TRUE' : 'FALSE'
  return String(v)
}

const REQUIRED_COLS: Record<string, string> = {
  year_of_kpis:    'Year of KPIs',
  indicator_group: 'Indicator Group',
  kpi_no:          'KPI No',
  indicator:       'Indicator',
  disaggregation1: 'Disaggregation1',
  disaggregation2: 'Disaggregation2',
  updated_date:    'Updated Date',
  value_type:      'Value Type',
}

type ParsedAllKpis = { rows: Record<string, unknown>[]; year: number }
type ParsedLevelOne = { rows: Record<string, unknown>[] }
type ParsedDefinitions = { rows: Record<string, unknown>[] }
type ParsedMilestones = { rows: Record<string, unknown>[] }

const DEFINITIONS_REQUIRED_COLS: Record<string, string> = {
  kpi_no:               'KPI No',
  indicator_group:      'Indicator Group',
  indicator:            'Indicator',
  indicator_frequency:  'Indicator Frequency',
  indicator_start:      'Indicator Start',
  definition:           'Definition',
}

async function parseKpiDefinitionsFile(file: File): Promise<ParsedDefinitions | { error: string }> {
  let raw: unknown[][]
  try {
    const XLSX = await import('@e965/xlsx')
    const bytes = await file.arrayBuffer()
    const wb = XLSX.read(new Uint8Array(bytes), { type: 'array', cellDates: true })
    if (!wb.SheetNames.includes('kpi_definitions'))
      return { error: "Sheet 'kpi_definitions' not found in uploaded workbook" }
    raw = XLSX.utils.sheet_to_json<unknown[]>(wb.Sheets['kpi_definitions'], {
      header: 1, defval: null, raw: true,
    }) as unknown[][]
  } catch {
    return { error: 'Failed to parse Excel file' }
  }
  if (raw.length < 2) return { error: 'No data rows found in kpi_definitions sheet' }

  const headers = (raw[0] as unknown[]).map((h, i) => cleanCol(h, i))

  const missing = Object.keys(DEFINITIONS_REQUIRED_COLS).filter(c => !headers.includes(c))
  if (missing.length > 0)
    return { error: `Required columns missing from kpi_definitions sheet: ${missing.map(c => DEFINITIONS_REQUIRED_COLS[c]).join(', ')}` }

  const allRows = raw.slice(1)
    .map((row, idx) => {
      const obj: Record<string, unknown> = { _row_id: idx + 2 }
      headers.forEach((h, i) => { obj[h] = toStr((row as unknown[])[i] ?? null) })
      return obj
    })
    .filter(r => r['kpi_no'] !== null)

  if (allRows.length === 0) return { error: 'No valid rows found (KPI No must be populated)' }

  const rows = allRows.map(r => ({
    kpi_no:              r['kpi_no'],
    indicator_group:     r['indicator_group'],
    indicator:           r['indicator'],
    indicator_frequency: r['indicator_frequency'],
    indicator_start:     r['indicator_start'],
    definition:          r['definition'],
    short_label:         r['short_label'],
  }))

  return { rows }
}

async function parseAllKpisFile(file: File): Promise<ParsedAllKpis | { error: string }> {
  let raw: unknown[][]
  try {
    const XLSX = await import('@e965/xlsx')
    const bytes = await file.arrayBuffer()
    const wb = XLSX.read(new Uint8Array(bytes), { type: 'array', cellDates: true })
    if (!wb.SheetNames.includes('All_KPIs'))
      return { error: "Sheet 'All_KPIs' not found in uploaded workbook" }
    raw = XLSX.utils.sheet_to_json<unknown[]>(wb.Sheets['All_KPIs'], {
      header: 1, defval: null, raw: true,
    }) as unknown[][]
  } catch {
    return { error: 'Failed to parse Excel file' }
  }
  if (raw.length < 2) return { error: 'No data rows found in All_KPIs sheet' }

  const headers = (raw[0] as unknown[]).map((h, i) => cleanCol(h, i))

  const missing = Object.keys(REQUIRED_COLS).filter(c => !headers.includes(c))
  if (missing.length > 0)
    return { error: `Required columns missing from All_KPIs sheet: ${missing.map(c => REQUIRED_COLS[c]).join(', ')}` }

  // Dynamically detect country columns: all headers between disaggregation2 and total.
  const disagg2Idx = headers.indexOf('disaggregation2')
  const totalIdx   = headers.indexOf('total')
  if (disagg2Idx === -1 || totalIdx === -1 || totalIdx <= disagg2Idx + 1)
    return { error: 'Could not locate country columns between Disaggregation2 and Total in the header row' }
  const countryHeaders = headers.slice(disagg2Idx + 1, totalIdx)
  if (countryHeaders.length === 0)
    return { error: 'No country value columns found between Disaggregation2 and Total' }

  const allRows = raw.slice(1)
    .map((row, idx) => {
      const obj: Record<string, unknown> = { _row_id: idx + 2 }
      headers.forEach((h, i) => { obj[h] = toStr((row as unknown[])[i] ?? null) })
      return obj
    })
    .filter(r => headers.some(h => h !== '_row_id' && r[h] !== null))

  const rowsWithYear = allRows.filter(r => r['year_of_kpis'] !== null)
  if (rowsWithYear.length === 0) return { error: 'No valid year_of_kpis values found in the sheet' }

  const yearSet = new Set(rowsWithYear.map(r => parseInt(r['year_of_kpis'] as string)))
  if (yearSet.size > 1)
    return { error: `File contains mixed years: ${[...yearSet].sort()}. Each upload must contain data for a single year only.` }
  const year = [...yearSet][0]

  const badDisagg = rowsWithYear
    .filter(r => r['disaggregation2'] !== null && r['disaggregation1'] === null)
    .map(r => r['_row_id'])
  if (badDisagg.length > 0)
    return { error: `Disaggregation2 is filled but Disaggregation1 is empty at rows: ${badDisagg.slice(0, 5).join(', ')}${badDisagg.length > 5 ? ` (and ${badDisagg.length - 5} more)` : ''}` }

  for (const col of countryHeaders) {
    const bad = rowsWithYear.filter(r => r[col] === null).map(r => r['_row_id']).slice(0, 5)
    if (bad.length > 0)
      return { error: `Column '${col.charAt(0).toUpperCase() + col.slice(1)}' must be populated on every row. Missing at rows: ${bad}` }
  }

  const rows = rowsWithYear.map(r => {
    const countries: Record<string, unknown> = {}
    for (const col of countryHeaders)
      countries[col.charAt(0).toUpperCase() + col.slice(1)] = r[col]
    return {
      row_id:          r['_row_id'],
      kpi_no:          r['kpi_no'],
      indicator_group: r['indicator_group'],
      indicator:       r['indicator'],
      disaggregation1: r['disaggregation1'],
      disaggregation2: r['disaggregation2'],
      updated_date:    r['updated_date'],
      update_quarter:  r['update_quarter'] ?? null,
      year_of_kpis:    r['year_of_kpis'],
      value_type:      r['value_type'],
      countries,
      total:           r['total'],
    }
  })

  return { rows, year }
}

async function parseLevelOneFile(file: File): Promise<ParsedLevelOne | { error: string }> {
  let raw: unknown[][]
  try {
    const XLSX = await import('@e965/xlsx')
    const bytes = await file.arrayBuffer()
    const wb = XLSX.read(new Uint8Array(bytes), { type: 'array', cellDates: true })
    if (!wb.SheetNames.includes('level_kpis'))
      return { error: "Sheet 'level_kpis' not found in uploaded workbook" }
    raw = XLSX.utils.sheet_to_json<unknown[]>(wb.Sheets['level_kpis'], {
      header: 1, defval: null, raw: true,
    }) as unknown[][]
  } catch {
    return { error: 'Failed to parse Excel file' }
  }
  if (raw.length < 2) return { error: 'No data rows found in level_kpis sheet' }

  const headers = (raw[0] as unknown[]).map((h, i) => cleanCol(h, i))

  for (const [col, label] of [['country', 'Country'], ['year', 'Year'], ['kpi', 'KPI']] as const) {
    if (!headers.includes(col))
      return { error: `Column '${label}' not found in level_kpis sheet` }
  }

  const allRows = raw.slice(1)
    .map((row, idx) => {
      const obj: Record<string, unknown> = { _row_id: idx + 2 }
      headers.forEach((h, i) => { obj[h] = toStr((row as unknown[])[i] ?? null) })
      return obj
    })
    .filter(r => headers.some(h => h !== '_row_id' && r[h] !== null))

  const rowsWithYear = allRows.filter(r => r['year'] !== null)
  if (rowsWithYear.length === 0) return { error: 'No valid Year values found in the sheet' }

  for (const [col, label] of [['country', 'Country'], ['kpi', 'KPI']] as const) {
    const bad = rowsWithYear.filter(r => r[col] === null).map(r => r['_row_id']).slice(0, 5)
    if (bad.length > 0)
      return { error: `Column '${label}' must be populated on every row. Missing at rows: ${bad}` }
  }

  const rows = rowsWithYear.map(r => ({
    row_id:                r['_row_id'],
    country:               r['country'],
    year:                  r['year'],
    kpi:                   r['kpi'],
    school_level:          r['school_level'] ?? null,
    annual_newly_supported: r['annual_newly_supported'] ?? null,
    type:                  r['type'] ?? null,
    gender:                r['gender'] ?? null,
    disaggregation_gender: r['disaggregation_gender'] ?? null,
    value:                 r['value'] ?? null,
  }))

  return { rows }
}

interface UploadResult {
  message?: string
  rows_loaded?: number
  rows_skipped_duplicate?: number
  total_staged?: number
  warnings?: string[]
  duplicate_rows?: Array<{ kpi_id: string; year: string; occurrences: number }>
  rows_added?: number
  rows_updated?: number
  total_rows?: number
  rows_inserted?: number
  rows_skipped?: number
  total?: number
  status?: string
  error?: string
  unmatched_kpi_nos?: string[]
  unmatched_countries?: string[]
}

const MILESTONES_REQUIRED_COLS: Record<string, string> = {
  kpi_no:          'KPI No',
  indicator:       'Indicator',
  disaggregation1: 'Disaggregation1',
  disaggregation2: 'Disaggregation2',
  country:         'Country',
  year_of_kpis:    'Year of KPIs',
  value:           'Value',
  value_type:      'Value Type',
}

async function parseMilestonesFile(file: File): Promise<ParsedMilestones | { error: string }> {
  let raw: unknown[][]
  try {
    const XLSX = await import('@e965/xlsx')
    const bytes = await file.arrayBuffer()
    const wb = XLSX.read(new Uint8Array(bytes), { type: 'array', cellDates: true })
    if (!wb.SheetNames.includes('Milestones'))
      return { error: "Sheet 'Milestones' not found in uploaded workbook" }
    raw = XLSX.utils.sheet_to_json<unknown[]>(wb.Sheets['Milestones'], {
      header: 1, defval: null, raw: true,
    }) as unknown[][]
  } catch {
    return { error: 'Failed to parse Excel file' }
  }
  if (raw.length < 2) return { error: 'No data rows found in Milestones sheet' }

  const headers = (raw[0] as unknown[]).map((h, i) => cleanCol(h, i))

  const missing = Object.keys(MILESTONES_REQUIRED_COLS).filter(c => !headers.includes(c))
  if (missing.length > 0)
    return { error: `Required columns missing from Milestones sheet: ${missing.map(c => MILESTONES_REQUIRED_COLS[c]).join(', ')}` }

  const rows = raw.slice(1)
    .map((row, idx) => {
      const obj: Record<string, unknown> = { _row_id: idx + 2 }
      headers.forEach((h, i) => { obj[h] = toStr((row as unknown[])[i] ?? null) })
      return obj
    })
    .filter(r => r['kpi_no'] !== null && r['country'] !== null && r['value'] !== null)
    .map(r => ({
      row_id:          r['_row_id'],
      kpi_no:          r['kpi_no'],
      indicator:       r['indicator'],
      disaggregation1: r['disaggregation1'],
      disaggregation2: r['disaggregation2'],
      country:         r['country'],
      year:            r['year_of_kpis'],
      value:           r['value'],
      value_type:      r['value_type'],
    }))

  if (rows.length === 0) return { error: 'No valid rows found (KPI No, Country and Value must be populated)' }

  return { rows }
}

const MILESTONES_RULES = [
  { icon: '📄', text: <>File must be <code>.xlsx</code> with a sheet named <strong>Milestones</strong></> },
  { icon: '🔢', text: 'Required columns: KPI No, Indicator, Disaggregation1, Disaggregation2, Country, Year of KPIs, Value, Value Type' },
  { icon: '🔁', text: 'Uploading replaces all existing milestone data (full truncate + reload)' },
  { icon: '🔑', text: 'All KPI Nos must exist in KPI Definitions — upload is rejected if any are unrecognised' },
  { icon: '🗺️', text: 'All countries must exist in the geography dimension (populated by Salesforce ingest)' },
]

const DEFINITIONS_RULES = [
  { icon: '📄', text: <>File must be <code>.xlsx</code> with a sheet named <strong>kpi_definitions</strong></> },
  { icon: '🔢', text: 'Required columns: KPI No, Indicator Group, Indicator, Indicator Frequency, Indicator Start, Definition' },
  { icon: '🔑', text: 'KPI No is the primary identifier — each KPI No must be unique within the sheet' },
  { icon: '🔁', text: 'Existing definitions are updated in-place; new KPI Nos are inserted; unchanged rows are skipped' },
  { icon: '⚠️', text: 'KPI data uploads (All KPIs, Level 1 KPIs) will fail if the KPI No is not present in this definitions list' },
  { icon: '💬', text: 'Short Label is optional but recommended — used for WhatsApp bot menus (≤24 chars); missing values are flagged as a warning, not an error' },
]

const ALL_KPIS_RULES = [
  { icon: '📄', text: <>File must be <code>.xlsx</code> with a sheet named <strong>All_KPIs</strong></> },
  { icon: '🔢', text: 'Required columns: Year of KPIs, Indicator Group, KPI No, Indicator, Disaggregation1, Disaggregation2, Updated Date, Value Type' },
  { icon: '🌍', text: 'All country columns present (Ghana, Malawi, Tanzania, Zambia, Zimbabwe, Total) must be populated on every row' },
  { icon: '📅', text: 'All rows must belong to a single year — mixed years in one file are rejected' },
  { icon: '🔁', text: 'Each year can only be uploaded once — re-uploading an existing year is rejected' },
  { icon: '📊', text: 'Disaggregation 2 cannot be filled if Disaggregation 1 is empty' },
  { icon: '🗺️', text: 'All countries must exist in the geography dimension (populated by Salesforce ingest)' },
]

const LEVEL_ONE_RULES = [
  { icon: '📄', text: <>File must be <code>.xlsx</code> with a sheet named <strong>level_kpis</strong></> },
  { icon: '🔢', text: 'Columns Country, Year, KPI must be present and populated on every row' },
  { icon: '📅', text: 'Mixed-year uploads are supported' },
  { icon: '🔁', text: 'Existing rows matching the same year / country / school level / fund type / gender key will be updated (upsert)' },
  { icon: '🗺️', text: 'All countries must exist in the geography dimension (populated by Salesforce ingest)' },
]

function ValidationRules({ rules }: { rules: typeof ALL_KPIS_RULES }) {
  return (
    <div className="admin-rules">
      <p className="admin-rules-title">Validation rules</p>
      <ul className="admin-rules-list">
        {rules.map((r, i) => (
          <li key={i} className="admin-rules-item">
            <span className="admin-rules-icon">{r.icon}</span>
            <span>{r.text}</span>
          </li>
        ))}
      </ul>
    </div>
  )
}

export function AdminKpisPage() {
  const [tab, setTab] = useState<'definitions' | 'all' | 'milestones' | 'levelone'>('definitions')

  return (
    <div className="admin-page">
      <h1 className="admin-page-title">KPI Upload</h1>

      <div className="admin-tabs">
        <button
          className={`admin-tab${tab === 'definitions' ? ' admin-tab--active' : ''}`}
          onClick={() => setTab('definitions')}
        >
          KPI Definitions
        </button>
        <button
          className={`admin-tab${tab === 'all' ? ' admin-tab--active' : ''}`}
          onClick={() => setTab('all')}
        >
          Annual KPIs
        </button>
        <button
          className={`admin-tab${tab === 'milestones' ? ' admin-tab--active' : ''}`}
          onClick={() => setTab('milestones')}
        >
          Milestones
        </button>
        <button
          className={`admin-tab${tab === 'levelone' ? ' admin-tab--active' : ''}`}
          onClick={() => setTab('levelone')}
        >
          Level 1 KPIs
        </button>
      </div>

      {tab === 'definitions' && <KpiDefinitionsUpload />}
      {tab === 'all' && <AllKpisUpload />}
      {tab === 'milestones' && <MilestonesUpload />}
      {tab === 'levelone' && <LevelOneUpload />}
    </div>
  )
}

function KpiDefinitionsUpload() {
  const fileRef     = useRef<HTMLInputElement>(null)
  const qc          = useQueryClient()
  const summary     = useKpiDefinitionsSummary()
  const definitions = useKpiDefinitions()
  const [dragging, setDragging]       = useState(false)
  const [loading, setLoading]         = useState(false)
  const [parseError, setParseError]   = useState<string | null>(null)
  const [result, setResult]           = useState<UploadResult | null>(null)
  const [rowCount, setRowCount]       = useState<number | null>(null)
  const [pendingRows, setPendingRows] = useState<Record<string, unknown>[] | null>(null)
  const [fileName, setFileName]       = useState<string>('')

  async function handleFile(file: File) {
    setParseError(null)
    setResult(null)
    setPendingRows(null)
    setRowCount(null)
    setFileName(file.name)

    const parsed = await parseKpiDefinitionsFile(file)
    if ('error' in parsed) {
      setParseError(parsed.error)
      return
    }
    setPendingRows(parsed.rows)
    setRowCount(parsed.rows.length)
  }

  async function handleUpload() {
    if (!pendingRows || !fileName) return
    setLoading(true)
    setParseError(null)

    try {
      const { data: { session } } = await supabase.auth.getSession()
      const token = session?.access_token
      if (!token) { setResult({ error: 'Not authenticated' }); return }

      const res = await fetch(`${SUPABASE_URL}/functions/v1/kpi-definitions-upload`, {
        method:  'POST',
        headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${token}` },
        body:    JSON.stringify({ fileName, rows: pendingRows }),
      })
      const data: UploadResult = await res.json()
      setResult(data)
      if (!data.error) {
        setPendingRows(null)
        setRowCount(null)
        if (fileRef.current) fileRef.current.value = ''
        void qc.invalidateQueries({ queryKey: ['admin', 'kpi-definitions-summary'] })
        void qc.invalidateQueries({ queryKey: ['admin', 'kpi-definitions'] })
      }
    } catch (err) {
      setResult({ error: err instanceof Error ? err.message : 'Unexpected error' })
    } finally {
      setLoading(false)
    }
  }

  function onFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (file) void handleFile(file)
    e.target.value = ''
  }

  function onDrop(e: React.DragEvent) {
    e.preventDefault()
    setDragging(false)
    const file = e.dataTransfer.files?.[0]
    if (file) void handleFile(file)
  }

  return (
    <div>
      <ValidationRules rules={DEFINITIONS_RULES} />

      {summary.data && (
        <div className={`admin-result ${summary.data.total > 0 ? 'admin-result--success' : 'admin-result--error'}`}>
          {summary.data.total > 0 ? (
            <>
              <strong>{summary.data.total} KPI definitions loaded</strong>
              {summary.data.last_source_file && (
                <span className="admin-muted"> · from {summary.data.last_source_file}</span>
              )}
              {summary.data.last_loaded_at && (
                <span className="admin-muted"> · {new Date(summary.data.last_loaded_at).toLocaleDateString()}</span>
              )}
            </>
          ) : (
            <strong>No KPI definitions loaded — upload kpi-definitions.xlsx before uploading KPI data</strong>
          )}
        </div>
      )}

      <div
        className={`admin-dropzone${dragging ? ' admin-dropzone--active' : ''}`}
        onDragOver={(e) => { e.preventDefault(); setDragging(true) }}
        onDragLeave={() => setDragging(false)}
        onDrop={onDrop}
        onClick={() => !loading && fileRef.current?.click()}
      >
        <input ref={fileRef} type="file" accept=".xlsx" style={{ display: 'none' }} onChange={onFileChange} disabled={loading} />
        {loading
          ? <span>Uploading…</span>
          : rowCount !== null
            ? <span>{rowCount} definition{rowCount !== 1 ? 's' : ''} ready — <strong>{fileName}</strong></span>
            : <span>Drop <code>.xlsx</code> here or click to browse</span>}
      </div>

      {parseError && <div className="admin-result admin-result--error"><strong>Error:</strong> {parseError}</div>}

      {pendingRows && !loading && (
        <div style={{ display: 'flex', gap: 8, marginTop: 12 }}>
          <button className="admin-btn admin-btn--primary" onClick={handleUpload}>
            Upload {rowCount} definition{rowCount !== 1 ? 's' : ''}
          </button>
          <button className="admin-btn admin-btn--ghost" onClick={() => { setPendingRows(null); setRowCount(null); setFileName('') }}>
            Cancel
          </button>
        </div>
      )}

      {result && <UploadResultPanel result={result} />}

      {definitions.data && definitions.data.length > 0 && (
        <KpiDefinitionsTable rows={definitions.data} />
      )}
    </div>
  )
}

function KpiDefinitionsTable({ rows }: { rows: KpiDefinition[] }) {
  const [filterGroup, setFilterGroup]     = useState('')
  const [filterFreq, setFilterFreq]       = useState('')
  const [filterStart, setFilterStart]     = useState('')

  const groups      = [...new Set(rows.map(r => r.kpi_group).filter(Boolean))].sort() as string[]
  const frequencies = [...new Set(rows.map(r => r.indicator_frequency).filter(Boolean))].sort() as string[]
  const starts      = [...new Set(rows.map(r => r.indicator_start).filter(Boolean))].sort() as string[]

  const filtered = rows.filter(r =>
    (!filterGroup || r.kpi_group === filterGroup) &&
    (!filterFreq  || r.indicator_frequency === filterFreq) &&
    (!filterStart || r.indicator_start === filterStart)
  )

  return (
    <div style={{ marginTop: 24 }}>
      <div style={{ display: 'flex', alignItems: 'center', gap: 12, marginBottom: 12, flexWrap: 'wrap' }}>
        <h3 className="admin-section-title" style={{ margin: 0 }}>
          Loaded definitions
          <span className="admin-muted" style={{ fontWeight: 400, marginLeft: 6 }}>
            {filtered.length !== rows.length ? `${filtered.length} of ${rows.length}` : rows.length}
          </span>
        </h3>

        <select
          className="admin-select"
          value={filterGroup}
          onChange={e => setFilterGroup(e.target.value)}
        >
          <option value="">All groups</option>
          {groups.map(g => <option key={g} value={g}>{g}</option>)}
        </select>

        <select
          className="admin-select"
          value={filterFreq}
          onChange={e => setFilterFreq(e.target.value)}
        >
          <option value="">All frequencies</option>
          {frequencies.map(f => <option key={f} value={f}>{f}</option>)}
        </select>

        <select
          className="admin-select"
          value={filterStart}
          onChange={e => setFilterStart(e.target.value)}
        >
          <option value="">All starts</option>
          {starts.map(s => <option key={s} value={s}>{s}</option>)}
        </select>

        {(filterGroup || filterFreq || filterStart) && (
          <button
            className="admin-btn admin-btn--ghost admin-btn--sm"
            onClick={() => { setFilterGroup(''); setFilterFreq(''); setFilterStart('') }}
          >
            Clear filters
          </button>
        )}
      </div>

      <AdminDataTable
        data={filtered}
        rowKey={(d) => d.source_kpi_id}
        columns={KPI_DEFINITIONS_COLUMNS}
        emptyMessage="No definitions match the selected filters."
      />
    </div>
  )
}

const KPI_DEFINITIONS_COLUMNS: AdminColumn<KpiDefinition>[] = [
  { key: 'source_kpi_id', header: 'KPI No', sortValue: (d) => d.source_kpi_id, render: (d) => <span className="admin-badge admin-badge--purple">{d.source_kpi_id}</span> },
  { key: 'kpi_group', header: 'Group', sortValue: (d) => d.kpi_group, render: (d) => d.kpi_group ?? <span className="admin-muted">—</span> },
  { key: 'indicator', header: 'Indicator', sortValue: (d) => d.indicator, render: (d) => d.indicator ?? <span className="admin-muted">—</span> },
  { key: 'short_label', header: 'Short Label', sortValue: (d) => d.short_label, render: (d) => d.short_label ?? <span className="admin-badge admin-badge--amber">Missing</span> },
  { key: 'indicator_frequency', header: 'Frequency', sortValue: (d) => d.indicator_frequency, render: (d) => d.indicator_frequency ?? <span className="admin-muted">—</span> },
  { key: 'indicator_start', header: 'Start', sortValue: (d) => d.indicator_start, render: (d) => d.indicator_start ?? <span className="admin-muted">—</span> },
  { key: 'definition', header: 'Definition', render: (d) => <span style={{ maxWidth: 320, whiteSpace: 'normal', display: 'inline-block' }}>{d.definition ?? <span className="admin-muted">—</span>}</span> },
]

function AllKpisUpload() {
  const [view, setView] = useState<'years' | 'upload' | number>('years')

  if (view === 'upload') return <AllKpisUploadView onBack={() => setView('years')} onSuccess={() => setView('years')} />
  if (typeof view === 'number') return <AllKpisDetailView year={view} onBack={() => setView('years')} />
  return <AllKpisYearsView onUpload={() => setView('upload')} onView={setView} />
}

function DeleteYearModal({ year, onConfirm, onCancel, isLoading, error }: {
  year: number
  onConfirm: () => void
  onCancel: () => void
  isLoading: boolean
  error: string | null
}) {
  const [input, setInput] = useState('')
  const confirmed = input.trim() === String(year)

  return (
    <div className="admin-modal-overlay" onClick={onCancel}>
      <div className="admin-modal" onClick={e => e.stopPropagation()}>
        <p><strong>Delete KPI data for {year}?</strong></p>
        <p>
          This will permanently remove all raw rows, upload history, and warehouse facts for{' '}
          <strong>{year}</strong>. The year can be re-uploaded afterwards.
        </p>
        <div className="admin-modal-form">
          <label style={{ fontSize: '0.875rem', color: 'var(--text)' }}>
            Type <strong>{year}</strong> to confirm
            <input
              className="admin-input"
              style={{ marginTop: 6, display: 'block', width: '100%' }}
              type="text"
              value={input}
              onChange={e => setInput(e.target.value)}
              autoFocus
              disabled={isLoading}
            />
          </label>
        </div>
        {error && <p className="admin-error">{error}</p>}
        <div className="admin-modal-actions">
          <button className="admin-btn admin-btn--danger" onClick={onConfirm} disabled={!confirmed || isLoading}>
            {isLoading ? 'Deleting…' : 'Delete'}
          </button>
          <button className="admin-btn admin-btn--ghost" onClick={onCancel} disabled={isLoading}>
            Cancel
          </button>
        </div>
      </div>
    </div>
  )
}

function AllKpisYearsView({ onUpload, onView }: { onUpload: () => void; onView: (year: number) => void }) {
  const { data: years, isLoading: yearsLoading } = useLoadedYears()
  const [historyPage, setHistoryPage] = useState(1)
  const history = useUploadLog(historyPage)
  const historyCount = useUploadLogCount()
  const historyTotalPages = Math.max(1, Math.ceil((historyCount.data ?? 0) / UPLOAD_LOG_PAGE_SIZE))
  const [deleteYear, setDeleteYear] = useState<number | null>(null)
  const deleteKpiYear = useDeleteKpiYear()

  function handleDeleteConfirm() {
    if (deleteYear === null) return
    deleteKpiYear.mutate(deleteYear, {
      onSuccess: () => setDeleteYear(null),
    })
  }

  return (
    <div>
      {deleteYear !== null && (
        <DeleteYearModal
          year={deleteYear}
          onConfirm={handleDeleteConfirm}
          onCancel={() => { setDeleteYear(null); deleteKpiYear.reset() }}
          isLoading={deleteKpiYear.isPending}
          error={deleteKpiYear.error ? (deleteKpiYear.error as Error).message : null}
        />
      )}

      <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 16 }}>
        <h2 className="admin-section-title" style={{ margin: 0 }}>Loaded years</h2>
        <button className="admin-btn admin-btn--primary" onClick={onUpload}>Upload new year</button>
      </div>

      {yearsLoading && <p className="admin-muted">Loading…</p>}
      {!yearsLoading && years && years.length === 0 && (
        <div style={{ marginBottom: 24 }}>
          <p className="admin-muted">No data uploaded yet.</p>
          <button className="admin-btn admin-btn--primary" style={{ marginTop: 12 }} onClick={onUpload}>Upload first year</button>
        </div>
      )}
      {years && years.length > 0 && (
        <div className="admin-stat-grid" style={{ gridTemplateColumns: 'repeat(auto-fill, minmax(220px, 1fr))', marginBottom: 24 }}>
          {years.map(y => (
            <div key={y.year} className="admin-stat-card admin-stat-card--green" style={{ position: 'relative' }}>
              {y.update_quarter && (
                <span className="admin-badge" style={{ position: 'absolute', top: 10, right: 10 }}>{y.update_quarter}</span>
              )}
              <div className="admin-stat-label">Year</div>
              <div className="admin-stat-value">{y.year}</div>
              <div className="admin-stat-sub">{y.rows_loaded.toLocaleString()} rows loaded</div>
              {y.rows_duplicate > 0 && (
                <div className="admin-stat-sub">{y.rows_duplicate} duplicates skipped</div>
              )}
              <div className="admin-stat-sub" style={{ marginTop: 4 }}>
                {fmt(y.inserted_at)} · {y.uploaded_by}
              </div>
              <div style={{ display: 'flex', gap: 8, marginTop: 10 }}>
                <button
                  className="admin-btn admin-btn--sm"
                  onClick={() => onView(y.year)}
                >
                  View rows
                </button>
                <button
                  className="admin-btn admin-btn--danger-sm"
                  onClick={() => { deleteKpiYear.reset(); setDeleteYear(y.year) }}
                >
                  Remove
                </button>
              </div>
            </div>
          ))}
        </div>
      )}

      <h2 className="admin-section-title">Upload history</h2>
      <AllKpisHistoryTable
        rows={history.data ?? []}
        isLoading={history.isLoading}
        serverPagination={{ page: historyPage, totalPages: historyTotalPages, total: historyCount.data ?? 0, onPage: setHistoryPage }}
      />
    </div>
  )
}

function AllKpisUploadView({ onBack, onSuccess }: { onBack: () => void; onSuccess: () => void }) {
  const qc = useQueryClient()
  const fileRef = useRef<HTMLInputElement>(null)
  const [dragging, setDragging] = useState(false)
  const [loading, setLoading] = useState(false)
  const [result, setResult] = useState<UploadResult | null>(null)

  async function upload(file: File) {
    setLoading(true)
    setResult(null)
    try {
      const parsed = await parseAllKpisFile(file)
      if ('error' in parsed) { setResult({ error: parsed.error }); return }

      const { data: existingRows } = await supabase
        .schema('rep_portal')
        .rpc('check_upload_exists', { p_year: parsed.year })
      const existing = existingRows?.[0] ?? null
      if (existing) {
        setResult({ error: `Year ${parsed.year} already has a successful upload (${fmt(existing.inserted_at as string)} by ${existing.uploaded_by}). Delete the existing data before uploading again.` })
        return
      }

      const { data } = await supabase.auth.getSession()
      const token = data.session?.access_token ?? ''
      const res = await fetch(`${SUPABASE_URL}/functions/v1/kpi-upload`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ fileName: file.name, year: parsed.year, rows: parsed.rows }),
      })
      const json = (await res.json()) as UploadResult
      setResult(json)
      if (!json.error) {
        void qc.invalidateQueries({ queryKey: ['admin', 'upload-log'] })
        void qc.invalidateQueries({ queryKey: ['admin', 'loaded-years'] })
      }
    } catch (e) {
      setResult({ error: (e as Error).message })
    } finally {
      setLoading(false)
    }
  }

  function onFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (file) void upload(file)
    e.target.value = ''
  }

  function onDrop(e: React.DragEvent) {
    e.preventDefault()
    setDragging(false)
    const file = e.dataTransfer.files?.[0]
    if (file) void upload(file)
  }

  return (
    <div>
      <button className="admin-btn admin-btn--ghost" style={{ marginBottom: 16 }} onClick={onBack}>
        ← Back to years
      </button>

      <ValidationRules rules={ALL_KPIS_RULES} />

      <div
        className={`admin-dropzone${dragging ? ' admin-dropzone--active' : ''}`}
        onDragOver={(e) => { e.preventDefault(); setDragging(true) }}
        onDragLeave={() => setDragging(false)}
        onDrop={onDrop}
        onClick={() => fileRef.current?.click()}
      >
        <input ref={fileRef} type="file" accept=".xlsx" style={{ display: 'none' }} onChange={onFileChange} />
        {loading
          ? <span>Uploading…</span>
          : <span>Drop <code>.xlsx</code> here or click to browse</span>}
      </div>

      {result && <UploadResultPanel result={result} />}
      {result && !result.error && (
        <button className="admin-btn admin-btn--primary" style={{ marginTop: 12 }} onClick={onSuccess}>
          Back to years
        </button>
      )}
    </div>
  )
}

function AllKpisDetailView({ year, onBack }: { year: number; onBack: () => void }) {
  const [page, setPage] = useState(1)
  const { data: rows, isLoading } = useAllKpiRows(year, page)
  const { data: totalCount } = useAllKpiRowCount(year)
  const totalPages = totalCount !== undefined ? Math.ceil(totalCount / KPI_PAGE_SIZE) : undefined

  return (
    <div>
      <div style={{ display: 'flex', alignItems: 'center', gap: 16, marginBottom: 16 }}>
        <button className="admin-btn admin-btn--ghost" onClick={onBack}>← Back to years</button>
        <h2 className="admin-section-title" style={{ margin: 0 }}>
          Annual KPIs — {year}
          {totalCount !== undefined && <span className="admin-muted"> ({totalCount.toLocaleString()} rows)</span>}
        </h2>
      </div>

      {isLoading && <p className="admin-muted">Loading…</p>}

      {rows && (
        <div style={{ overflowX: 'auto' }}>
          <table className="admin-table">
            <thead>
              <tr>
                <th>#</th>
                <th>KPI No</th>
                <th>Group</th>
                <th>Indicator</th>
                <th>Disagg 1</th>
                <th>Disagg 2</th>
                <th>Type</th>
                {Object.keys(rows[0]?.countries ?? {}).sort().map(k => <th key={k}>{k}</th>)}
                <th>Total</th>
                <th>Updated</th>
              </tr>
            </thead>
            <tbody>
              {rows.map(r => {
                const countryKeys = Object.keys(r.countries ?? {}).sort()
                return (
                  <tr key={r.row_id}>
                    <td className="admin-table-mono">{r.row_id}</td>
                    <td className="admin-table-mono">{r.kpi_no ?? '—'}</td>
                    <td>{r.indicator_group ?? '—'}</td>
                    <td>{r.indicator ?? '—'}</td>
                    <td>{r.disaggregation1 ?? '—'}</td>
                    <td>{r.disaggregation2 ?? '—'}</td>
                    <td>{r.value_type ?? '—'}</td>
                    {countryKeys.map(k => (
                      <td key={k} className="admin-table-mono">{r.countries?.[k] ?? '—'}</td>
                    ))}
                    <td className="admin-table-mono">{r.total ?? '—'}</td>
                    <td>{r.updated_date ?? '—'}</td>
                  </tr>
                )
              })}
            </tbody>
          </table>
        </div>
      )}

      {totalPages !== undefined && totalPages > 1 && (
        <div className="admin-pagination">
          <button
            className="admin-btn admin-btn--sm"
            disabled={page <= 1}
            onClick={() => setPage(p => p - 1)}
          >
            ← Prev
          </button>
          <span className="admin-muted">Page {page} of {totalPages}</span>
          <button
            className="admin-btn admin-btn--sm"
            disabled={page >= totalPages}
            onClick={() => setPage(p => p + 1)}
          >
            Next →
          </button>
        </div>
      )}
    </div>
  )
}

const ALL_KPIS_HISTORY_COLUMNS: AdminColumn<UploadLog>[] = [
  { key: 'year', header: 'Year', sortValue: (r) => r.year, render: (r) => r.year },
  { key: 'status', header: 'Status', sortValue: (r) => r.status, render: (r) => <StatusBadge status={r.status} /> },
  { key: 'rows_loaded', header: 'Rows loaded', sortValue: (r) => r.rows_loaded, render: (r) => r.rows_loaded },
  { key: 'rows_duplicate', header: 'Duplicate', sortValue: (r) => r.rows_duplicate, render: (r) => r.rows_duplicate },
  { key: 'uploaded_by', header: 'Uploaded by', sortValue: (r) => r.uploaded_by, render: (r) => r.uploaded_by },
  { key: 'source_file', header: 'File', sortValue: (r) => r.source_file, render: (r) => r.source_file },
  { key: 'inserted_at', header: 'Date', sortValue: (r) => r.inserted_at, render: (r) => fmt(r.inserted_at) },
]

function AllKpisHistoryTable({ rows, isLoading, serverPagination }: { rows: UploadLog[]; isLoading?: boolean; serverPagination: ServerPaginationInfo }) {
  return (
    <AdminDataTable
      data={rows}
      rowKey={(r) => r.batch_id}
      columns={ALL_KPIS_HISTORY_COLUMNS}
      isLoading={isLoading}
      emptyMessage="No uploads yet."
      canExpand={(r) => r.rows_duplicate > 0 || r.status === 'FAILED'}
      renderExpanded={(r) => r.status === 'FAILED'
        ? <p className="admin-error" style={{ margin: 0 }}>{r.error_msg ?? 'Unknown error'}</p>
        : <DuplicateDetail batchId={r.batch_id} />}
      serverPagination={serverPagination}
    />
  )
}

function DuplicateDetail({ batchId }: { batchId: string }) {
  const { data, isLoading } = useDuplicateRows(batchId)
  if (isLoading) return <p className="admin-muted">Loading…</p>
  if (!data || data.length === 0) return <p className="admin-muted">No duplicates recorded.</p>
  return (
    <table className="admin-table admin-table--nested">
      <thead>
        <tr>
          <th>KPI ID</th>
          <th>Group</th>
          <th>Year</th>
          <th>Disagg 1</th>
          <th>Disagg 2</th>
          <th>Scope</th>
          <th>Occurrences</th>
        </tr>
      </thead>
      <tbody>
        {data.map((r, i) => (
          <tr key={i}>
            <td className="admin-table-mono">{r.kpi_id}</td>
            <td>{r.kpi_group ?? '—'}</td>
            <td>{r.year ?? '—'}</td>
            <td>{r.disaggregation_level_one ?? '—'}</td>
            <td>{r.disaggregation_level_two ?? '—'}</td>
            <td>{r.row_scope ?? '—'}</td>
            <td>{r.occurrences}</td>
          </tr>
        ))}
      </tbody>
    </table>
  )
}

function MilestonesUpload() {
  const qc = useQueryClient()
  const fileRef = useRef<HTMLInputElement>(null)
  const [dragging, setDragging] = useState(false)
  const [loading, setLoading] = useState(false)
  const [result, setResult] = useState<UploadResult | null>(null)
  const [historyPage, setHistoryPage] = useState(1)
  const history = useMilestoneUploadLog(historyPage)
  const historyCount = useMilestoneUploadLogCount()
  const historyTotalPages = Math.max(1, Math.ceil((historyCount.data ?? 0) / MILESTONE_UPLOAD_LOG_PAGE_SIZE))

  async function upload(file: File) {
    setLoading(true)
    setResult(null)
    try {
      const parsed = await parseMilestonesFile(file)
      if ('error' in parsed) { setResult({ error: parsed.error }); return }

      const { data } = await supabase.auth.getSession()
      const token = data.session?.access_token ?? ''
      const res = await fetch(`${SUPABASE_URL}/functions/v1/milestones-upload`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ fileName: file.name, rows: parsed.rows }),
      })
      const json = (await res.json()) as UploadResult
      setResult(json)
      if (!json.error && json.status !== 'FAILED') {
        void qc.invalidateQueries({ queryKey: ['admin', 'milestone-upload-log'] })
        void qc.invalidateQueries({ queryKey: ['admin', 'milestone-upload-log-count'] })
      }
    } catch (e) {
      setResult({ error: (e as Error).message })
    } finally {
      setLoading(false)
    }
  }

  function onFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (file) void upload(file)
    e.target.value = ''
  }

  function onDrop(e: React.DragEvent) {
    e.preventDefault()
    setDragging(false)
    const file = e.dataTransfer.files?.[0]
    if (file) void upload(file)
  }

  return (
    <div>
      <ValidationRules rules={MILESTONES_RULES} />

      <div
        className={`admin-dropzone${dragging ? ' admin-dropzone--active' : ''}`}
        onDragOver={(e) => { e.preventDefault(); setDragging(true) }}
        onDragLeave={() => setDragging(false)}
        onDrop={onDrop}
        onClick={() => fileRef.current?.click()}
      >
        <input ref={fileRef} type="file" accept=".xlsx" style={{ display: 'none' }} onChange={onFileChange} />
        {loading
          ? <span>Uploading…</span>
          : <span>Drop <code>.xlsx</code> here or click to browse</span>}
      </div>

      {result && <MilestonesResultPanel result={result} />}

      <h2 className="admin-section-title">Upload history</h2>
      <MilestonesHistoryTable
        rows={history.data ?? []}
        isLoading={history.isLoading}
        serverPagination={{ page: historyPage, totalPages: historyTotalPages, total: historyCount.data ?? 0, onPage: setHistoryPage }}
      />
    </div>
  )
}

function MilestonesResultPanel({ result }: { result: UploadResult }) {
  if (result.error || result.status === 'FAILED') {
    return (
      <div className="admin-result admin-result--error">
        <p><strong>Error:</strong> {result.error}</p>
        {(result.unmatched_kpi_nos ?? []).length > 0 && (
          <details style={{ marginTop: 8 }}>
            <summary>Unmatched KPI Nos ({result.unmatched_kpi_nos!.length})</summary>
            <p style={{ fontFamily: 'monospace', marginTop: 4 }}>{result.unmatched_kpi_nos!.join(', ')}</p>
          </details>
        )}
        {(result.unmatched_countries ?? []).length > 0 && (
          <details style={{ marginTop: 8 }}>
            <summary>Unmatched countries ({result.unmatched_countries!.length})</summary>
            <p style={{ fontFamily: 'monospace', marginTop: 4 }}>{result.unmatched_countries!.join(', ')}</p>
          </details>
        )}
      </div>
    )
  }
  return (
    <div className="admin-result admin-result--success">
      <p><strong>{result.message}</strong></p>
      {result.rows_loaded !== undefined && <p>Rows loaded: {result.rows_loaded.toLocaleString()}</p>}
    </div>
  )
}

const MILESTONES_HISTORY_COLUMNS: AdminColumn<MilestoneUploadLog>[] = [
  { key: 'status', header: 'Status', sortValue: (r) => r.status, render: (r) => <StatusBadge status={r.status} /> },
  { key: 'rows_loaded', header: 'Rows loaded', sortValue: (r) => r.rows_loaded, render: (r) => r.rows_loaded ?? '—' },
  { key: 'uploaded_by', header: 'Uploaded by', sortValue: (r) => r.uploaded_by, render: (r) => r.uploaded_by ?? '—' },
  { key: 'source_file', header: 'File', sortValue: (r) => r.source_file, render: (r) => r.source_file ?? '—' },
  { key: 'inserted_at', header: 'Date', sortValue: (r) => r.inserted_at, render: (r) => fmt(r.inserted_at) },
]

function MilestonesHistoryTable({ rows, isLoading, serverPagination }: { rows: MilestoneUploadLog[]; isLoading?: boolean; serverPagination: ServerPaginationInfo }) {
  return (
    <AdminDataTable
      data={rows}
      rowKey={(r) => r.batch_id}
      columns={MILESTONES_HISTORY_COLUMNS}
      isLoading={isLoading}
      emptyMessage="No uploads yet."
      serverPagination={serverPagination}
    />
  )
}

function LevelOneUpload() {
  const qc = useQueryClient()
  const fileRef = useRef<HTMLInputElement>(null)
  const [dragging, setDragging] = useState(false)
  const [loading, setLoading] = useState(false)
  const [result, setResult] = useState<UploadResult | null>(null)
  const [historyPage, setHistoryPage] = useState(1)
  const history = useLevelOneUploadLog(historyPage)
  const historyCount = useLevelOneUploadLogCount()
  const historyTotalPages = Math.max(1, Math.ceil((historyCount.data ?? 0) / LEVEL_ONE_UPLOAD_LOG_PAGE_SIZE))

  async function upload(file: File) {
    setLoading(true)
    setResult(null)
    try {
      const parsed = await parseLevelOneFile(file)
      if ('error' in parsed) { setResult({ error: parsed.error }); return }

      const { data } = await supabase.auth.getSession()
      const token = data.session?.access_token ?? ''
      const res = await fetch(`${SUPABASE_URL}/functions/v1/kpi-level-one-upload`, {
        method: 'POST',
        headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' },
        body: JSON.stringify({ fileName: file.name, rows: parsed.rows }),
      })
      const json = (await res.json()) as UploadResult
      setResult(json)
      void qc.invalidateQueries({ queryKey: ['admin', 'level-one-upload-log'] })
      void qc.invalidateQueries({ queryKey: ['admin', 'level-one-upload-log-count'] })
    } catch (e) {
      setResult({ error: (e as Error).message })
    } finally {
      setLoading(false)
    }
  }

  function onFileChange(e: React.ChangeEvent<HTMLInputElement>) {
    const file = e.target.files?.[0]
    if (file) void upload(file)
    e.target.value = ''
  }

  function onDrop(e: React.DragEvent) {
    e.preventDefault()
    setDragging(false)
    const file = e.dataTransfer.files?.[0]
    if (file) void upload(file)
  }

  return (
    <div>
      <ValidationRules rules={LEVEL_ONE_RULES} />

      <div
        className={`admin-dropzone${dragging ? ' admin-dropzone--active' : ''}`}
        onDragOver={(e) => { e.preventDefault(); setDragging(true) }}
        onDragLeave={() => setDragging(false)}
        onDrop={onDrop}
        onClick={() => fileRef.current?.click()}
      >
        <input ref={fileRef} type="file" accept=".xlsx" style={{ display: 'none' }} onChange={onFileChange} />
        {loading
          ? <span>Uploading…</span>
          : <span>Drop <code>.xlsx</code> here or click to browse</span>}
      </div>

      {result && <UploadResultPanel result={result} />}

      <h2 className="admin-section-title">Upload history</h2>
      <LevelOneHistoryTable
        rows={history.data ?? []}
        isLoading={history.isLoading}
        serverPagination={{ page: historyPage, totalPages: historyTotalPages, total: historyCount.data ?? 0, onPage: setHistoryPage }}
      />
    </div>
  )
}

const LEVEL_ONE_HISTORY_COLUMNS: AdminColumn<LevelOneUploadLog>[] = [
  { key: 'status', header: 'Status', sortValue: (r) => r.status, render: (r) => <StatusBadge status={r.status} /> },
  { key: 'rows_added', header: 'Rows added', sortValue: (r) => r.rows_added, render: (r) => r.rows_added },
  { key: 'rows_updated', header: 'Rows updated', sortValue: (r) => r.rows_updated, render: (r) => r.rows_updated },
  { key: 'total_rows', header: 'Total rows', sortValue: (r) => r.total_rows, render: (r) => r.total_rows },
  { key: 'uploaded_by', header: 'Uploaded by', sortValue: (r) => r.uploaded_by, render: (r) => r.uploaded_by },
  { key: 'source_file', header: 'File', sortValue: (r) => r.source_file, render: (r) => r.source_file },
  { key: 'inserted_at', header: 'Date', sortValue: (r) => r.inserted_at, render: (r) => fmt(r.inserted_at) },
]

function LevelOneHistoryTable({ rows, isLoading, serverPagination }: { rows: LevelOneUploadLog[]; isLoading?: boolean; serverPagination: ServerPaginationInfo }) {
  return (
    <AdminDataTable
      data={rows}
      rowKey={(r) => r.batch_id}
      columns={LEVEL_ONE_HISTORY_COLUMNS}
      isLoading={isLoading}
      emptyMessage="No uploads yet."
      serverPagination={serverPagination}
    />
  )
}

function UploadResultPanel({ result }: { result: UploadResult }) {
  if (result.error) {
    return <div className="admin-result admin-result--error"><strong>Error:</strong> {result.error}</div>
  }
  return (
    <div className="admin-result admin-result--success">
      <p><strong>{result.message}</strong></p>
      {result.rows_loaded !== undefined && <p>Rows loaded: {result.rows_loaded}</p>}
      {result.rows_added !== undefined && <p>Rows added: {result.rows_added} · updated: {result.rows_updated}</p>}
      {result.rows_inserted !== undefined && (
        <p>Inserted: {result.rows_inserted} · updated: {result.rows_updated ?? 0} · skipped: {result.rows_skipped ?? 0}</p>
      )}
      {(result.warnings ?? []).map((w, i) => (
        <p key={i} className="admin-result-warning">⚠ {w}</p>
      ))}
      {(result.duplicate_rows ?? []).length > 0 && (
        <details className="admin-result-detail">
          <summary>Duplicate rows ({result.duplicate_rows!.length})</summary>
          <table className="admin-table admin-table--nested">
            <thead><tr><th>KPI ID</th><th>Year</th><th>Occurrences</th></tr></thead>
            <tbody>
              {result.duplicate_rows!.map((r, i) => (
                <tr key={i}>
                  <td className="admin-table-mono">{r.kpi_id}</td>
                  <td>{r.year}</td>
                  <td>{r.occurrences}</td>
                </tr>
              ))}
            </tbody>
          </table>
        </details>
      )}
    </div>
  )
}

function StatusBadge({ status }: { status: string }) {
  let cls = 'admin-badge'
  if (status === 'SUCCESS') cls += ' admin-badge--green'
  else if (status === 'FAILED') cls += ' admin-badge--red'
  return <span className={cls}>{status}</span>
}

