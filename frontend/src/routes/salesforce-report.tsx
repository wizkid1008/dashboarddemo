import { useMemo, useState } from 'react'
import { useDashboardMeta } from '@/queries/useDashboardMeta'
import { SelectDropdown } from '@/components/SelectDropdown'
import { CountryMultiSelect } from '@/components/CountryMultiSelect'
import {
  useReportCatalog,
  useReportDimensionValues,
  useReportPivot,
  type ReportCatalogEntry,
  type ReportFilter,
  type ReportPivotParams,
} from '@/features/salesforce-report/queries'

export function SalesforceReportPage() {
  const { data: catalog, isPending: catalogPending, error: catalogError } = useReportCatalog()
  const { data: meta } = useDashboardMeta()

  const [reportKey, setReportKey] = useState<string | null>(null)
  const [countries, setCountries] = useState<string[]>([])
  const [provinces, setProvinces] = useState<string[]>([])
  const [districts, setDistricts] = useState<string[]>([])
  const [schools, setSchools] = useState<string[]>([])
  const [yearStart, setYearStart] = useState(2020)
  const [yearEnd, setYearEnd] = useState(new Date().getFullYear())
  const [groupByLabels, setGroupByLabels] = useState<string[]>([])
  // null = user hasn't touched measure selection for the current report yet —
  // default to the first measure. An explicit [] means the user cleared it.
  const [measureLabels, setMeasureLabels] = useState<string[] | null>(null)
  const [filters, setFilters] = useState<ReportFilter[]>([])
  const [applied, setApplied] = useState<ReportPivotParams | null>(null)

  // Default to the first report once the catalog loads — derived, not synced via effect
  const activeReportKey = reportKey ?? catalog?.[0]?.report_key ?? null

  const report: ReportCatalogEntry | undefined = useMemo(
    () => catalog?.find((r) => r.report_key === activeReportKey),
    [catalog, activeReportKey],
  )

  const dimByLabel = useMemo(() => {
    const m = new Map<string, string>()
    report?.dimensions.forEach((d) => m.set(d.label, d.column_name))
    return m
  }, [report])

  const measureByLabel = useMemo(() => {
    const m = new Map<string, string>()
    report?.measures.forEach((mm) => m.set(mm.label, mm.column_name ?? 'count'))
    return m
  }, [report])

  // Province/district/school breakdowns only make sense once narrowed to a
  // single parent: "Province" needs exactly one Country selected, "District"
  // needs exactly one Province selected, and "School" needs exactly one
  // District selected. Otherwise they're hidden from Group By and Filter
  // Column pickers.
  const hiddenDimensionColumns = useMemo(() => {
    const hidden: string[] = []
    if (countries.length !== 1) hidden.push('province')
    if (provinces.length !== 1) hidden.push('district')
    if (districts.length !== 1) hidden.push('school_name')
    return hidden
  }, [countries, provinces, districts])

  const availableDimensions = useMemo(() => {
    if (!report) return []
    return report.dimensions.filter((d) => !hiddenDimensionColumns.includes(d.column_name))
  }, [report, hiddenDimensionColumns])

  // Drop any group-by/filter selections targeting columns that just became
  // hidden (per hiddenCols), e.g. after a Country/Province change.
  function pruneHiddenSelections(hiddenCols: string[]) {
    if (!hiddenCols.length) return
    setGroupByLabels((prev) => prev.filter((l) => {
      const col = dimByLabel.get(l)
      return !col || !hiddenCols.includes(col)
    }))
    setFilters((prev) => prev.filter((f) => !hiddenCols.includes(f.column)))
  }

  function handleReportChange(key: string) {
    setReportKey(key)
    setGroupByLabels([])
    setMeasureLabels(null)
    setFilters([])
    setApplied(null)
  }

  // Default to the first measure once the report's catalog entry is known —
  // derived, not synced via effect. Once the user makes any selection
  // (including clearing it to []), that takes over.
  const effectiveMeasureLabels = measureLabels ?? (report?.measures[0] ? [report.measures[0].label] : [])

  const allYears = meta?.years ?? []
  const schoolLayer = report?.geography_level === 'school'

  const provinceOptions = useMemo(
    () => [...new Set(countries.flatMap((c) => meta?.provinces[c] ?? []))].sort(),
    [meta, countries],
  )
  const districtOptions = useMemo(
    () => [...new Set(provinces.flatMap((p) => meta?.districts[p] ?? []))].sort(),
    [meta, provinces],
  )
  const schoolOptions = useMemo(
    () => [...new Set(districts.flatMap((d) => meta?.schools[d] ?? []))].sort(),
    [meta, districts],
  )

  function handleRun() {
    if (!report) return
    setApplied({
      reportKey: report.report_key,
      groupBy: groupByLabels.map((l) => dimByLabel.get(l)).filter((v): v is string => !!v),
      measures: effectiveMeasureLabels.map((l) => measureByLabel.get(l)).filter((v): v is string => !!v),
      filters,
      yearStart,
      yearEnd,
      countries,
      provinces,
      districts,
      schools: schoolLayer ? schools : [],
    })
  }

  const { data: rows, isPending: pivotPending, error } = useReportPivot(applied)

  return (
    <div id="salesforce-report-view">
      {catalogError != null && (
        <p style={{
          color: 'var(--red)', background: 'var(--red-light)', border: '1px solid var(--red)',
          borderRadius: 6, padding: '10px 14px', marginBottom: 16, fontSize: '0.85rem', fontWeight: 500,
        }}>
          Could not load report definitions: {catalogError instanceof Error ? catalogError.message : 'An unexpected error occurred.'}
        </p>
      )}

      {/* ── Report picker ─────────────────────────────────────────────────── */}
      <div className="filter-bar" style={{ gap: '12px 20px', alignItems: 'flex-end', borderBottom: '1px solid var(--line)', paddingBottom: 12 }}>
        <div className="filter-bar-item">
          <label className="filter-bar-label">Report</label>
          <div className="seg-control" role="radiogroup" aria-label="Report">
            {(catalog ?? []).map((r) => (
              <label key={r.report_key} className="seg-opt">
                <input
                  type="radio"
                  name="reportKey"
                  value={r.report_key}
                  checked={activeReportKey === r.report_key}
                  onChange={() => handleReportChange(r.report_key)}
                />
                <span>{r.label}</span>
              </label>
            ))}
          </div>
        </div>
      </div>

      {/* ── Geography ─────────────────────────────────────────────────────── */}
      <div className="filter-bar" style={{ gap: '12px 20px', alignItems: 'flex-end', borderBottom: '1px solid var(--line)', paddingBottom: 12 }}>
        <div className="filter-bar-item">
          <label className="filter-bar-label">Country</label>
          <CountryMultiSelect
            allCountries={(meta?.countries ?? []).filter((c) => c !== 'International')}
            selected={countries}
            onChange={(v) => {
              const nextCountries = v.filter((x) => x !== 'All')
              setCountries(nextCountries)
              setProvinces([])
              setDistricts([])
              setSchools([])
              pruneHiddenSelections(nextCountries.length !== 1 ? ['province', 'district', 'school_name'] : ['district', 'school_name'])
            }}
            entityName="Countries"
            hideAllOption
          />
        </div>
        <div className="filter-bar-item">
          <label className="filter-bar-label">Province</label>
          <CountryMultiSelect
            allCountries={provinceOptions}
            selected={provinces}
            onChange={(v) => {
              const nextProvinces = v.filter((x) => x !== 'All')
              setProvinces(nextProvinces)
              setDistricts([])
              setSchools([])
              pruneHiddenSelections(nextProvinces.length !== 1 ? ['district', 'school_name'] : ['school_name'])
            }}
            entityName="Provinces"
            hideAllOption
            disabled={countries.length !== 1}
          />
        </div>
        <div className="filter-bar-item">
          <label className="filter-bar-label">District</label>
          <CountryMultiSelect
            allCountries={districtOptions}
            selected={districts}
            onChange={(v) => {
              const nextDistricts = v.filter((x) => x !== 'All')
              setDistricts(nextDistricts)
              setSchools([])
              if (nextDistricts.length !== 1) pruneHiddenSelections(['school_name'])
            }}
            entityName="Districts"
            hideAllOption
            disabled={provinces.length !== 1}
          />
        </div>
        {schoolLayer && (
          <div className="filter-bar-item">
            <label className="filter-bar-label">School</label>
            <CountryMultiSelect
              allCountries={schoolOptions}
              selected={schools}
              onChange={(v) => setSchools(v.filter((x) => x !== 'All'))}
              entityName="Schools"
              hideAllOption
              disabled={districts.length !== 1}
            />
          </div>
        )}
      </div>

      {/* ── Years, group by, measures ────────────────────────────────────── */}
      <div className="filter-bar" style={{ gap: '12px 20px', alignItems: 'flex-end', borderBottom: '1px solid var(--line)', paddingBottom: 12 }}>
        <div className="filter-bar-item">
          <label className="filter-bar-label">Start Year</label>
          <SelectDropdown
            options={allYears.filter((y) => y <= yearEnd).map(String)}
            value={String(yearStart)}
            onChange={(v) => setYearStart(Number(v))}
          />
        </div>
        <div className="filter-bar-item">
          <label className="filter-bar-label">End Year</label>
          <SelectDropdown
            options={allYears.filter((y) => y >= yearStart).map(String)}
            value={String(yearEnd)}
            onChange={(v) => setYearEnd(Number(v))}
          />
        </div>
        <div className="filter-bar-item" style={{ minWidth: 220, flex: '1 1 220px' }}>
          <label className="filter-bar-label">Group By</label>
          <CountryMultiSelect
            allCountries={availableDimensions.map((d) => d.label)}
            selected={groupByLabels}
            onChange={setGroupByLabels}
            entityName="Columns"
            hideAllOption
          />
        </div>
        <div className="filter-bar-item" style={{ minWidth: 180, flex: '1 1 180px' }}>
          <label className="filter-bar-label">Measures</label>
          <CountryMultiSelect
            allCountries={report?.measures.map((m) => m.label) ?? []}
            selected={effectiveMeasureLabels}
            onChange={setMeasureLabels}
            entityName="Measures"
            hideAllOption
          />
        </div>
      </div>

      {/* ── Group by order ────────────────────────────────────────────────── */}
      {groupByLabels.length > 0 && (
        <div className="filter-bar" style={{ gap: '12px 20px', alignItems: 'center', borderBottom: '1px solid var(--line)', paddingBottom: 12 }}>
          <label className="filter-bar-label" style={{ marginRight: 4 }}>Group Order</label>
          <GroupByOrderChips labels={groupByLabels} onChange={setGroupByLabels} />
        </div>
      )}

      {/* ── Filters + Export / Run ───────────────────────────────────────── */}
      {report && (
        <FilterBuilder
          reportKey={report.report_key}
          dimensions={availableDimensions}
          filters={filters}
          onChange={setFilters}
          trailing={
            <div style={{ display: 'flex', gap: 12, marginLeft: 'auto' }}>
              <button
                type="button"
                className="dd-run-btn"
                style={{ background: 'transparent', color: 'var(--purple)', border: '1px solid var(--purple)' }}
                onClick={() => {
                  if (!report || !applied || !rows?.length) return
                  const dimLabel = (col: string) => report.dimensions.find((d) => d.column_name === col)?.label ?? col
                  const measureLabel = (key: string) => report.measures.find((m) => (m.column_name ?? 'count') === key)?.label ?? key
                  const headerFor = (key: string) => (applied.groupBy.includes(key) ? dimLabel(key) : measureLabel(key))
                  exportPivotCsv({ rows, groupBy: applied.groupBy, measures: applied.measures, headerFor, reportLabel: report.label })
                }}
                disabled={!applied || !rows?.length}
              >
                Export CSV
              </button>
              <button
                className="dd-run-btn"
                onClick={handleRun}
                disabled={!report || !effectiveMeasureLabels.length || catalogPending}
              >
                Run Report
              </button>
            </div>
          }
        />
      )}

      {/* ── Body ──────────────────────────────────────────────────────────── */}
      <div className="body-layout">
        <div className="main-content">
          {error != null && (
            <p style={{
              color: 'var(--red)', background: 'var(--red-light)', border: '1px solid var(--red)',
              borderRadius: 6, padding: '10px 14px', marginBottom: 16, fontSize: '0.85rem', fontWeight: 500,
            }}>
              Report failed to run: {error instanceof Error ? error.message : 'An unexpected error occurred.'}
            </p>
          )}

          {pivotPending && applied && (
            <div>
              <div className="dd-progress-bar" />
              <p style={{ fontSize: '0.82rem', color: 'var(--text-mid)', marginBottom: 16 }}>Fetching data…</p>
            </div>
          )}

          {applied && rows && report && (
            <PivotTable
              rows={rows}
              groupBy={applied.groupBy}
              dimensions={report.dimensions}
              measures={applied.measures}
              measureCatalog={report.measures}
            />
          )}
        </div>
      </div>
    </div>
  )
}

// ── Group-by order chips ─────────────────────────────────────────────────────

function GroupByOrderChips({ labels, onChange }: { labels: string[]; onChange: (next: string[]) => void }) {
  function move(i: number, dir: -1 | 1) {
    const j = i + dir
    if (j < 0 || j >= labels.length) return
    const next = [...labels]
    ;[next[i], next[j]] = [next[j], next[i]]
    onChange(next)
  }

  function remove(i: number) {
    onChange(labels.filter((_, idx) => idx !== i))
  }

  return (
    <div style={{ display: 'flex', gap: 8, flexWrap: 'wrap' }}>
      {labels.map((label, i) => (
        <div
          key={label}
          style={{
            display: 'flex', alignItems: 'center', gap: 4,
            border: '1px solid var(--line)', borderRadius: 6,
            padding: '4px 6px 4px 10px', fontSize: '0.82rem', background: 'var(--surface)',
          }}
        >
          <span style={{ color: 'var(--muted)', marginRight: 2 }}>{i + 1}.</span>
          <span>{label}</span>
          <button
            type="button"
            onClick={() => move(i, -1)}
            disabled={i === 0}
            title="Move earlier"
            style={{
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
              width: 18, height: 18, borderRadius: 4, border: 'none',
              background: 'var(--purple)', opacity: i === 0 ? 0.35 : 1,
              color: '#fff', cursor: i === 0 ? 'default' : 'pointer',
              padding: 0, fontSize: '0.7rem', lineHeight: 1,
            }}
          >▲</button>
          <button
            type="button"
            onClick={() => move(i, 1)}
            disabled={i === labels.length - 1}
            title="Move later"
            style={{
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
              width: 18, height: 18, borderRadius: 4, border: 'none',
              background: 'var(--purple)', opacity: i === labels.length - 1 ? 0.35 : 1,
              color: '#fff', cursor: i === labels.length - 1 ? 'default' : 'pointer',
              padding: 0, fontSize: '0.7rem', lineHeight: 1,
            }}
          >▼</button>
          <button
            type="button"
            onClick={() => remove(i)}
            title="Remove"
            style={{
              display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
              width: 18, height: 18, borderRadius: 4, border: 'none',
              background: 'var(--red)', color: '#fff', fontWeight: 700,
              cursor: 'pointer', padding: 0, fontSize: '0.7rem', lineHeight: 1,
            }}
          >✕</button>
        </div>
      ))}
    </div>
  )
}

// ── Filter builder ──────────────────────────────────────────────────────────

function FilterBuilder({ reportKey, dimensions, filters, onChange, trailing }: {
  reportKey: string
  dimensions: ReportCatalogEntry['dimensions']
  filters: ReportFilter[]
  onChange: (f: ReportFilter[]) => void
  trailing?: React.ReactNode
}) {
  function addFilter() {
    const firstUnused = dimensions.find((d) => !filters.some((f) => f.column === d.column_name))
    if (!firstUnused) return
    onChange([...filters, { column: firstUnused.column_name, values: [] }])
  }

  function updateFilter(index: number, next: ReportFilter) {
    onChange(filters.map((f, i) => (i === index ? next : f)))
  }

  function removeFilter(index: number) {
    onChange(filters.filter((_, i) => i !== index))
  }

  return (
    <div className="filter-bar" style={{ gap: '12px 20px', alignItems: 'flex-end', borderBottom: '1px solid var(--line)', paddingBottom: 12, flexWrap: 'wrap' }}>
      {filters.map((f, i) => (
        <FilterRow
          key={f.column + i}
          reportKey={reportKey}
          dimensions={dimensions}
          filter={f}
          onChange={(next) => updateFilter(i, next)}
          onRemove={() => removeFilter(i)}
        />
      ))}
      <div className="filter-bar-item">
        <button
          type="button"
          className="dd-run-btn"
          style={{ background: 'transparent', color: 'var(--purple)', border: '1px solid var(--purple)' }}
          onClick={addFilter}
          disabled={filters.length >= dimensions.length}
        >
          + Add Filter
        </button>
      </div>
      {trailing}
    </div>
  )
}

function FilterRow({ reportKey, dimensions, filter, onChange, onRemove }: {
  reportKey: string
  dimensions: { column_name: string; label: string }[]
  filter: ReportFilter
  onChange: (f: ReportFilter) => void
  onRemove: () => void
}) {
  const { data: valuesResult } = useReportDimensionValues(reportKey, filter.column)
  const currentLabel = dimensions.find((d) => d.column_name === filter.column)?.label ?? filter.column

  return (
    <div className="filter-bar-item" style={{ display: 'flex', gap: 6, alignItems: 'flex-end' }}>
      <div>
        <label className="filter-bar-label">Filter Column</label>
        <SelectDropdown
          options={dimensions.map((d) => d.label)}
          value={currentLabel}
          onChange={(label) => {
            const col = dimensions.find((d) => d.label === label)?.column_name
            if (col) onChange({ column: col, values: [] })
          }}
        />
      </div>
      <div style={{ minWidth: 180 }}>
        <label className="filter-bar-label">
          Value
          {valuesResult?.truncated && (
            <span title="Showing the first 500 values — narrow by geography to see more" style={{ color: 'var(--red)', marginLeft: 4, fontWeight: 700 }}>
              500+
            </span>
          )}
        </label>
        <CountryMultiSelect
          allCountries={valuesResult?.values ?? []}
          selected={filter.values}
          onChange={(v) => onChange({ ...filter, values: v.filter((x) => x !== 'All') })}
          entityName="Values"
          hideAllOption
        />
      </div>
      <button
        type="button"
        onClick={onRemove}
        title="Remove filter"
        style={{
          display: 'inline-flex', alignItems: 'center', justifyContent: 'center',
          width: 20, height: 20, borderRadius: 4, border: 'none',
          background: 'var(--red)', color: '#fff', fontWeight: 700,
          cursor: 'pointer', padding: 0, fontSize: '0.75rem', lineHeight: 1, marginBottom: 8,
        }}
      >✕</button>
    </div>
  )
}

// ── Pivot table ──────────────────────────────────────────────────────────────

function exportPivotCsv(opts: {
  rows: Record<string, string | number | null>[]
  groupBy: string[]
  measures: string[]
  headerFor: (key: string) => string
  reportLabel: string
}) {
  const { rows, groupBy, measures, headerFor, reportLabel } = opts
  const cols = [...groupBy, ...measures]
  const headers = cols.map(headerFor)
  const lines = rows.map((row) =>
    cols.map((c) => {
      const v = row[c]
      return v === null || v === undefined ? '' : String(v)
    }),
  )
  const csv = [headers, ...lines]
    .map((row) => row.map((c) => `"${c.replace(/"/g, '""')}"`).join(','))
    .join('\n')
  const blob = new Blob([csv], { type: 'text/csv' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `${reportLabel.toLowerCase().replace(/[^a-z0-9]+/g, '-')}-pivot.csv`
  a.click()
  URL.revokeObjectURL(url)
}

function PivotTable({ rows, groupBy, dimensions, measures, measureCatalog }: {
  rows: Record<string, string | number | null>[]
  groupBy: string[]
  dimensions: { column_name: string; label: string }[]
  measures: string[]
  measureCatalog: { column_name: string | null; label: string; agg_type: 'count' | 'sum' }[]
}) {
  const dimLabel = (col: string) => dimensions.find((d) => d.column_name === col)?.label ?? col
  const measureLabel = (key: string) => measureCatalog.find((m) => (m.column_name ?? 'count') === key)?.label ?? key

  const totals = useMemo(() => {
    const t: Record<string, number> = {}
    measures.forEach((m) => {
      t[m] = rows.reduce((s, r) => s + (Number(r[m]) || 0), 0)
    })
    return t
  }, [rows, measures])

  if (!rows.length) {
    return <p style={{ padding: '20px 0', color: 'var(--text-mid)' }}>No data for the selected filters.</p>
  }

  return (
    <div className="data-card" style={{ overflowX: 'auto' }}>
      <table style={{ borderCollapse: 'collapse', width: '100%', fontSize: '0.82rem' }}>
        <thead>
          <tr>
            {groupBy.map((g) => (
              <th key={g} style={{ textAlign: 'left', padding: '8px 12px', color: 'var(--text-mid)', fontWeight: 600, borderBottom: '2px solid var(--line)' }}>
                {dimLabel(g)}
              </th>
            ))}
            {measures.map((m) => (
              <th key={m} style={{ textAlign: 'right', padding: '8px 12px', color: 'var(--text-mid)', fontWeight: 600, borderBottom: '2px solid var(--line)' }}>
                {measureLabel(m)}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row, i) => (
            <tr key={i} style={{ background: i % 2 === 0 ? 'transparent' : 'rgba(102,47,108,0.04)' }}>
              {groupBy.map((g) => (
                <td key={g} style={{ padding: '6px 12px', color: 'var(--text-dark)' }}>{row[g] ?? '—'}</td>
              ))}
              {measures.map((m) => (
                <td key={m} style={{ padding: '6px 12px', textAlign: 'right', fontWeight: 600, color: 'var(--purple)' }}>
                  {(Number(row[m]) || 0).toLocaleString()}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr>
            <td colSpan={Math.max(groupBy.length, 1)} style={{ padding: '8px 12px', fontWeight: 700, borderTop: '2px solid var(--line)' }}>Total</td>
            {measures.map((m) => (
              <td key={m} style={{ padding: '8px 12px', textAlign: 'right', fontWeight: 700, color: 'var(--purple)', borderTop: '2px solid var(--line)' }}>
                {totals[m].toLocaleString()}
              </td>
            ))}
          </tr>
        </tfoot>
      </table>
    </div>
  )
}
