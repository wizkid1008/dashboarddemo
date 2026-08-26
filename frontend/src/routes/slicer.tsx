import { useState, useMemo, useCallback, useEffect, useRef } from 'react'
import { Chart } from 'chart.js/auto'
import { useObservedKpi, parseKpiValue } from '@/queries/useObservedKpi'
import type { ObservedKpiRow } from '@/lib/warehouseClient'
import { CountryMultiSelect } from '@/components/CountryMultiSelect'
import { SelectDropdown } from '@/components/SelectDropdown'
import { FlexChart } from '@/components/charts/FlexChart'
import { MAP_LEVEL_COLORS } from '@/data/staticData'
import { DASHBOARD_CHART_REGISTRY } from '@/data/dashboardChartRegistry'

// ── KPI option list ───────────────────────────────────────────────────────────

const KPI_OPTIONS = DASHBOARD_CHART_REGISTRY.map(e => ({
  kpiId:     e.kpiId,
  label:     `${e.kpiId} – ${e.chartName}`,
  valueType: e.valueType ?? 'count',
}))
const KPI_LABELS      = KPI_OPTIONS.map(o => o.label)
const LABEL_TO_KPI    = new Map(KPI_OPTIONS.map(o => [o.label, o.kpiId]))
const LABEL_TO_VTYPE  = new Map(KPI_OPTIONS.map(o => [o.label, o.valueType as DashletConfig['valueType']]))

const NONE = '— All —'

const GRID_C = 'rgba(13,79,108,0.12)'
const TICK_C = '#5C5C6E'

// ── Types ─────────────────────────────────────────────────────────────────────

interface DashletConfig {
  id:                string
  kpiId:             string | null
  kpiLabel:          string | null
  valueType:         'count' | 'percentage' | 'currency_usd' | 'currency_local'
  countries:         string[]           // ['All'] = all countries
  yearStart:         number
  yearEnd:           number
  chartType:         'bar' | 'number'   // aggregate mode chart type
  subElement1:       string | null      // disaggregation_level_one
  subElement2:       string | null      // disaggregation_level_two
  configured:        boolean
  displayMode:       'aggregate' | 'timeline'
  timelineChartType: 'line' | 'grouped' | 'stacked'
  timelineBreakdown: 'per-country' | 'combined'
}

// ── localStorage ──────────────────────────────────────────────────────────────

const LS_KEY = 'camfed_dashlets_v1'

function loadDashlets(): DashletConfig[] {
  try {
    const raw = localStorage.getItem(LS_KEY)
    if (raw) {
      const parsed = JSON.parse(raw) as DashletConfig[]
      // Always resolve valueType from registry — overrides any stale 'count' default
      return parsed.map(d => ({
        ...d,
        valueType: LABEL_TO_VTYPE.get(d.kpiLabel ?? '') ?? d.valueType ?? 'count',
      }))
    }
  } catch { /* ignore */ }
  return []
}

function saveDashlets(ds: DashletConfig[]): void {
  localStorage.setItem(LS_KEY, JSON.stringify(ds))
}

// ── Helpers ───────────────────────────────────────────────────────────────────

function uid(): string { return Math.random().toString(36).slice(2, 10) }

function newDashlet(): DashletConfig {
  return {
    id: uid(), kpiId: null, kpiLabel: null, valueType: 'count',
    countries: ['All'], yearStart: 2020, yearEnd: 2030,
    chartType: 'bar', subElement1: null, subElement2: null, configured: false,
    displayMode: 'aggregate', timelineChartType: 'line', timelineBreakdown: 'per-country',
  }
}

function fmtNum(n: number): string {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M'
  if (n >= 1_000)     return Math.round(n / 1_000) + 'k'
  return Math.round(n).toLocaleString()
}

type ValueType = DashletConfig['valueType']

function fmtVal(n: number, vt: ValueType | undefined): string {
  if (vt === 'percentage')      return n.toFixed(1) + '%'
  if (vt === 'currency_usd')    return '$' + fmtNum(n)
  if (vt === 'currency_local')  return fmtNum(n)
  return fmtNum(n)
}

function level1Options(rows: ObservedKpiRow[]): string[] {
  return [...new Set(rows.map(r => r.disaggregation_level_one).filter(Boolean))].sort()
}

function level2Options(rows: ObservedKpiRow[], l1: string | null): string[] {
  const base = l1 ? rows.filter(r => r.disaggregation_level_one === l1) : rows
  return [...new Set(base.map(r => r.disaggregation_level_two).filter(Boolean))].sort()
}

function countryOptions(rows: ObservedKpiRow[]): string[] {
  return [...new Set(rows.map(r => r.country).filter(Boolean))].sort()
}

function yearBounds(rows: ObservedKpiRow[]): [number, number] {
  if (!rows.length) return [2020, 2030]
  const yrs = rows.map(r => Number(r.year))
  return [Math.min(...yrs), Math.max(...yrs)]
}

function yearRange(min: number, max: number): number[] {
  const out: number[] = []
  for (let y = min; y <= max; y++) out.push(y)
  return out
}

function describeConfig(cfg: DashletConfig): string {
  const parts: string[] = []
  if (cfg.countries.includes('All') || !cfg.countries.length) {
    parts.push('All Countries')
  } else if (cfg.countries.length <= 2) {
    parts.push(cfg.countries.join(', '))
  } else {
    parts.push(`${cfg.countries[0]}, ${cfg.countries[1]} +${cfg.countries.length - 2}`)
  }
  parts.push(cfg.yearStart === cfg.yearEnd ? String(cfg.yearStart) : `${cfg.yearStart}–${cfg.yearEnd}`)
  if (cfg.subElement1) parts.push(cfg.subElement1)
  if (cfg.subElement2) parts.push(cfg.subElement2)
  return parts.join(' · ')
}

// ── Data computation ──────────────────────────────────────────────────────────

function computeAggregate(cfg: DashletConfig, rows: ObservedKpiRow[]) {
  const allCountries = countryOptions(rows)
  const active = cfg.countries.includes('All') ? allCountries : cfg.countries
  const filtered = rows.filter(r =>
    active.includes(r.country) &&
    (!cfg.subElement1 || r.disaggregation_level_one === cfg.subElement1) &&
    (!cfg.subElement2 || r.disaggregation_level_two === cfg.subElement2) &&
    Number(r.year) >= cfg.yearStart && Number(r.year) <= cfg.yearEnd,
  )
  const vals  = active.map(c => filtered.filter(r => r.country === c).reduce((s, r) => s + parseKpiValue(r.value), 0))
  const total = vals.reduce((s, v) => s + v, 0)
  return { countries: active, vals, total }
}

interface TimelineSeries { label: string; data: number[]; color: string }

function computeTimeline(cfg: DashletConfig, rows: ObservedKpiRow[]): { years: number[]; series: TimelineSeries[] } {
  const allCountries = countryOptions(rows)
  const active    = cfg.countries.includes('All') ? allCountries : cfg.countries
  const years     = yearRange(cfg.yearStart, cfg.yearEnd)
  const breakdown = cfg.timelineBreakdown ?? 'per-country'

  const filtered = rows.filter(r =>
    active.includes(r.country) &&
    (!cfg.subElement1 || r.disaggregation_level_one === cfg.subElement1) &&
    (!cfg.subElement2 || r.disaggregation_level_two === cfg.subElement2) &&
    Number(r.year) >= cfg.yearStart && Number(r.year) <= cfg.yearEnd,
  )

  if (breakdown === 'combined') {
    const data = years.map(yr =>
      filtered.filter(r => Number(r.year) === yr).reduce((s, r) => s + parseKpiValue(r.value), 0)
    )
    return { years, series: [{ label: 'All Countries', data, color: MAP_LEVEL_COLORS[0] }] }
  }

  const series = active.map((country, i) => ({
    label: country,
    data:  years.map(yr =>
      filtered.filter(r => r.country === country && Number(r.year) === yr)
               .reduce((s, r) => s + parseKpiValue(r.value), 0)
    ),
    color: MAP_LEVEL_COLORS[i % MAP_LEVEL_COLORS.length],
  }))
  return { years, series }
}

// ── TimelineChart ─────────────────────────────────────────────────────────────

const VALUE_TYPE_LABEL: Record<string, string> = {
  count:           'Count',
  percentage:      '%',
  currency_usd:    'USD',
  currency_local:  'Value',
}

function TimelineChart({ id, years, series, type, valueType = 'count', yLabel }: {
  id:         string
  years:      number[]
  series:     TimelineSeries[]
  type:       'line' | 'grouped' | 'stacked'
  valueType?: ValueType
  yLabel?:    string
}) {
  const ref = useRef<HTMLCanvasElement | null>(null)

  useEffect(() => {
    const ctx = ref.current
    if (!ctx || !series.length) return

    const isLine    = type === 'line'
    const isStacked = type === 'stacked'

    const chart = new Chart(ctx, {
      type: isLine ? 'line' : 'bar',
      data: {
        labels: years.map(String),
        datasets: series.map(s => isLine ? ({
          label:           s.label,
          data:            s.data,
          borderColor:     s.color,
          backgroundColor: s.color + '33',
          tension:         0.35,
          pointRadius:     years.length > 10 ? 2 : 3,
          fill:            false,
        }) : ({
          label:           s.label,
          data:            s.data,
          backgroundColor: s.color,
          borderRadius:    isStacked ? 0 : 3,
          borderSkipped:   false as const,
        })),
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            display: series.length > 1,
            labels: { color: TICK_C, font: { size: 10 }, usePointStyle: true },
          },
          tooltip: {
            callbacks: {
              label: (ctx) => ` ${ctx.dataset.label}: ${fmtVal(Number(ctx.raw ?? 0), valueType)}`,
            },
          },
        },
        scales: {
          x: {
            stacked: isStacked,
            grid:  { color: GRID_C },
            ticks: { color: TICK_C, font: { size: 10 } },
            title: { display: true, text: 'Year', color: TICK_C, font: { size: 10 } },
          },
          y: {
            stacked: isStacked,
            grid:  { color: GRID_C },
            ticks: { color: TICK_C, font: { size: 10 }, callback: (v) => fmtVal(Number(v), valueType) },
            title: {
              display: true,
              text: yLabel ?? VALUE_TYPE_LABEL[valueType ?? 'count'] ?? 'Value',
              color: TICK_C,
              font: { size: 10 },
            },
          },
        },
      },
    })

    return () => chart.destroy()
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, years, series, type])

  return <canvas ref={ref} />
}

// ── DashletEditor ─────────────────────────────────────────────────────────────

interface EditorProps {
  draft:    DashletConfig
  onChange: (d: DashletConfig) => void
  onApply:  () => void
  onCancel: (() => void) | null
  onDelete: () => void
}

function DashletEditor({ draft, onChange, onApply, onCancel, onDelete }: EditorProps) {
  const { data: rows = [], isPending } = useObservedKpi(draft.kpiId)
  const l1Opts = useMemo(() => level1Options(rows), [rows])
  const l2Opts = useMemo(() => level2Options(rows, draft.subElement1), [rows, draft.subElement1])
  const cOpts  = useMemo(() => countryOptions(rows), [rows])
  const [minYr, maxYr] = useMemo(() => yearBounds(rows), [rows])

  function set<K extends keyof DashletConfig>(k: K, v: DashletConfig[K]) {
    onChange({ ...draft, [k]: v } as DashletConfig)
  }

  return (
    <div className="dashlet-card dashlet-card--editing">
      <div className="dashlet-card-header">
        <span className="dashlet-card-title">Configure Dashlet</span>
        <div className="dashlet-actions">
          {onCancel && (
            <button className="dashlet-action-btn dashlet-action-btn--cancel" onClick={onCancel}>Cancel</button>
          )}
          <button className="dashlet-delete-btn" onClick={onDelete} title="Remove dashlet">✕</button>
        </div>
      </div>

      <div className="dashlet-config-body">
        {/* KPI */}
        <div className="dashlet-field">
          <label className="dashlet-field-label">KPI</label>
          <SelectDropdown
            options={KPI_LABELS}
            value={draft.kpiLabel ?? ''}
            placeholder="Select a KPI…"
            onChange={label => {
              const kpiId     = LABEL_TO_KPI.get(label) ?? null
              const valueType = LABEL_TO_VTYPE.get(label) ?? 'count'
              onChange({ ...draft, kpiId, kpiLabel: label, valueType, subElement1: null, subElement2: null, countries: ['All'] })
            }}
          />
        </div>

        {/* Sub-element 1 */}
        {draft.kpiId && (
          <div className="dashlet-field">
            <label className="dashlet-field-label">Sub-element 1</label>
            {isPending
              ? <span className="dashlet-loading">Loading…</span>
              : <SelectDropdown
                  options={[NONE, ...l1Opts]}
                  value={draft.subElement1 ?? NONE}
                  onChange={v => onChange({ ...draft, subElement1: v === NONE ? null : v, subElement2: null })}
                />
            }
          </div>
        )}

        {/* Sub-element 2 */}
        {draft.kpiId && l2Opts.length > 0 && (
          <div className="dashlet-field">
            <label className="dashlet-field-label">Sub-element 2</label>
            <SelectDropdown
              options={[NONE, ...l2Opts]}
              value={draft.subElement2 ?? NONE}
              onChange={v => set('subElement2', v === NONE ? null : v)}
            />
          </div>
        )}

        {/* Countries */}
        {draft.kpiId && (
          <div className="dashlet-field">
            <label className="dashlet-field-label">Countries</label>
            <CountryMultiSelect
              allCountries={cOpts}
              selected={draft.countries}
              onChange={next => set('countries', next)}
              entityName="Countries"
            />
          </div>
        )}

        {/* Year range */}
        {draft.kpiId && (
          <div className="dashlet-field">
            <label className="dashlet-field-label">Year Range</label>
            <div className="dashlet-year-dropdowns">
              <SelectDropdown
                options={yearRange(minYr, maxYr).map(String)}
                value={String(draft.yearStart)}
                onChange={v => set('yearStart', Math.min(Number(v), draft.yearEnd))}
              />
              <span className="dashlet-year-sep">to</span>
              <SelectDropdown
                options={yearRange(minYr, maxYr).map(String)}
                value={String(draft.yearEnd)}
                onChange={v => set('yearEnd', Math.max(Number(v), draft.yearStart))}
              />
            </div>
          </div>
        )}

        {draft.kpiId && (
          <button className="dashlet-apply-btn" onClick={onApply}>Apply</button>
        )}
      </div>
    </div>
  )
}

// ── DashletViewer ─────────────────────────────────────────────────────────────

interface ViewerProps {
  config:   DashletConfig
  onEdit:   () => void
  onDelete: () => void
  onUpdate: (cfg: DashletConfig) => void
}

// ── Control value maps ────────────────────────────────────────────────────────

const MODE_LABELS: Record<string, string> = { aggregate: 'Aggregate', timeline: 'Timeline' }
const MODE_VALUES: Record<string, string> = { Aggregate: 'aggregate', Timeline: 'timeline' }

const BREAKDOWN_LABELS: Record<string, string> = { 'per-country': 'Per Country', combined: 'Combined' }
const BREAKDOWN_VALUES: Record<string, string> = { 'Per Country': 'per-country', Combined: 'combined' }

const TL_CHART_LABELS: Record<string, string> = { line: 'Line', grouped: 'Bar', stacked: 'Stacked' }
const TL_CHART_VALUES: Record<string, string> = { Line: 'line', Bar: 'grouped', Stacked: 'stacked' }

const AGG_CHART_LABELS: Record<string, string> = { bar: 'Bar', number: 'Number' }
const AGG_CHART_VALUES: Record<string, string> = { Bar: 'bar', Number: 'number' }

function DashletViewer({ config, onEdit, onDelete, onUpdate }: ViewerProps) {
  const { data: rows = [] } = useObservedKpi(config.kpiId)

  // Coerce fields that may be absent on older saved configs
  const displayMode       = config.displayMode       ?? 'aggregate'
  const timelineChartType = config.timelineChartType ?? 'line'
  const timelineBreakdown = config.timelineBreakdown ?? 'per-country'

  const agg      = useMemo(() => computeAggregate(config, rows), [config, rows])
  const timeline = useMemo(() => computeTimeline({ ...config, displayMode, timelineBreakdown }, rows), [config, rows, displayMode, timelineBreakdown])

  // Scale decimal percentages (0–1) to 0–100 for display
  const isPct = config.valueType === 'percentage'
  const scale = isPct ? 100 : 1
  const displayAgg = useMemo(() => ({
    ...agg,
    vals:  agg.vals.map(v => v * scale),
    total: agg.total * scale,
  }), [agg, scale])
  const displayTimeline = useMemo(() => ({
    ...timeline,
    series: timeline.series.map(s => ({ ...s, data: s.data.map(v => v * scale) })),
  }), [timeline, scale])

  const aggColors = agg.countries.map((_, i) => MAP_LEVEL_COLORS[i % MAP_LEVEL_COLORS.length])

  const title  = config.kpiLabel?.replace(/^[\w.]+\s*–\s*/, '') ?? 'KPI'
  const kpiTag = config.kpiId ?? ''
  const desc   = describeConfig(config)

  // Include valueType in chartId so Chart.js re-renders when it changes
  const chartId = `${config.id}-${displayMode}-${timelineChartType}-${timelineBreakdown}-${config.valueType}`

  function patch(partial: Partial<DashletConfig>) {
    onUpdate({ ...config, ...partial })
  }

  return (
    <div className="dashlet-card">
      {/* Header */}
      <div className="dashlet-card-header">
        <span className="dashlet-card-title">{title}</span>
        <div className="dashlet-actions">
          {kpiTag && <span className="dashlet-kpi-tag">{kpiTag}</span>}
          <button className="dashlet-action-btn" onClick={onEdit} title="Edit dashlet">
            <svg width="13" height="13" viewBox="0 0 20 20" fill="none" aria-hidden="true">
              <circle cx="10" cy="10" r="2.5" stroke="currentColor" strokeWidth="1.8" />
              <path d="M10 2v2M10 16v2M2 10h2M16 10h2M4.22 4.22l1.41 1.41M14.37 14.37l1.41 1.41M4.22 15.78l1.41-1.41M14.37 5.63l1.41-1.41"
                stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
            </svg>
          </button>
          <button className="dashlet-delete-btn" onClick={onDelete} title="Remove dashlet">✕</button>
        </div>
      </div>

      {/* Description */}
      <div className="dashlet-desc">{desc}</div>

      {/* Controls bar */}
      <div className="dashlet-controls">
        <SelectDropdown
          options={['Aggregate', 'Timeline']}
          value={MODE_LABELS[displayMode] ?? 'Aggregate'}
          onChange={v => patch({ displayMode: MODE_VALUES[v] as 'aggregate' | 'timeline' })}
        />
        {displayMode === 'timeline' && (
          <SelectDropdown
            options={['Per Country', 'Combined']}
            value={BREAKDOWN_LABELS[timelineBreakdown] ?? 'Per Country'}
            onChange={v => patch({ timelineBreakdown: BREAKDOWN_VALUES[v] as 'per-country' | 'combined' })}
          />
        )}
        {displayMode === 'timeline' ? (
          <SelectDropdown
            options={['Line', 'Bar', 'Stacked']}
            value={TL_CHART_LABELS[timelineChartType] ?? 'Line'}
            onChange={v => patch({ timelineChartType: TL_CHART_VALUES[v] as 'line' | 'grouped' | 'stacked' })}
          />
        ) : (
          <SelectDropdown
            options={['Bar', 'Number']}
            value={AGG_CHART_LABELS[config.chartType] ?? 'Bar'}
            onChange={v => patch({ chartType: AGG_CHART_VALUES[v] as 'bar' | 'number' })}
          />
        )}
      </div>

      {/* Chart area */}
      {displayMode === 'aggregate' && config.chartType === 'number' ? (
        <div className="dashlet-body">
          <div className="dashlet-number">{fmtVal(displayAgg.total, config.valueType)}</div>
        </div>
      ) : displayMode === 'aggregate' ? (
        <div className="dashlet-chart-wrap">
          <FlexChart
            labels={displayAgg.countries}
            datasets={[{ label: title, data: displayAgg.vals, color: aggColors }]}
            pct={isPct}
            intPct={isPct}
            xLabel="Country"
            yLabel={title}
          />
        </div>
      ) : (
        <div className="dashlet-chart-wrap">
          <TimelineChart
            id={chartId}
            years={displayTimeline.years}
            series={displayTimeline.series}
            type={timelineChartType}
            valueType={config.valueType}
            yLabel={title}
          />
        </div>
      )}
    </div>
  )
}

// ── DashletCard ───────────────────────────────────────────────────────────────

function DashletCard({
  config, onUpdate, onDelete,
}: {
  config: DashletConfig; onUpdate: (c: DashletConfig) => void; onDelete: () => void
}) {
  const [editing, setEditing] = useState(!config.configured)
  const [draft,   setDraft]   = useState<DashletConfig>({ ...config })

  function apply() {
    const committed = { ...draft, configured: true }
    onUpdate(committed)
    setEditing(false)
  }

  function startEdit() { setDraft({ ...config }); setEditing(true) }

  if (editing) {
    return (
      <DashletEditor
        draft={draft}
        onChange={setDraft}
        onApply={apply}
        onCancel={config.configured ? () => setEditing(false) : null}
        onDelete={onDelete}
      />
    )
  }
  return (
    <DashletViewer
      config={config}
      onEdit={startEdit}
      onDelete={onDelete}
      onUpdate={onUpdate}
    />
  )
}

// ── Main Page ─────────────────────────────────────────────────────────────────

export function SlicerPage() {
  const [dashlets, setDashlets] = useState<DashletConfig[]>(loadDashlets)

  const update = useCallback((id: string, cfg: DashletConfig) => {
    setDashlets(prev => { const next = prev.map(d => d.id === id ? cfg : d); saveDashlets(next); return next })
  }, [])

  const remove = useCallback((id: string) => {
    setDashlets(prev => { const next = prev.filter(d => d.id !== id); saveDashlets(next); return next })
  }, [])

  function addDashlet() {
    if (dashlets.length >= 10) return
    setDashlets(prev => { const next = [...prev, newDashlet()]; saveDashlets(next); return next })
  }

  return (
    <div className="body-layout">
      <div className="main-content">
        <div className="dashlets-toolbar">
          <h2 className="dashlets-heading">My Slicer</h2>
          <button className="dashlets-add-btn" onClick={addDashlet} disabled={dashlets.length >= 10}>
            + Add Dashlet
            {dashlets.length > 0 && <span className="dashlets-count">{dashlets.length}/10</span>}
          </button>
        </div>

        {dashlets.length === 0 ? (
          <div className="landing-section landing-section--how-to">
            <div className="landing-title">Custom Slicer</div>
            <p className="landing-intro">
              Build a personal view with up to 10 dashlets. Each panel shows a KPI with your own filters — saved automatically to this browser.
            </p>
            <div className="landing-steps">
              <div className="landing-step">
                <span className="landing-step-num">1</span>
                <div className="landing-step-text">
                  <strong>Add a Dashlet</strong>
                  <span>Click "+ Add Dashlet" above to get started.</span>
                </div>
              </div>
              <div className="landing-step">
                <span className="landing-step-num">2</span>
                <div className="landing-step-text">
                  <strong>Select a KPI</strong>
                  <span>Choose any KPI from the main dashboard chart list.</span>
                </div>
              </div>
              <div className="landing-step">
                <span className="landing-step-num">3</span>
                <div className="landing-step-text">
                  <strong>Set Sub-elements &amp; Filters</strong>
                  <span>Pick disaggregation levels, countries, and year range.</span>
                </div>
              </div>
              <div className="landing-step">
                <span className="landing-step-num">4</span>
                <div className="landing-step-text">
                  <strong>Apply &amp; Explore</strong>
                  <span>Switch between Aggregate and Timeline views directly on the chart.</span>
                </div>
              </div>
            </div>
          </div>
        ) : (
          <div className="dashlets-grid">
            {dashlets.map(d => (
              <DashletCard
                key={d.id}
                config={d}
                onUpdate={cfg => update(d.id, cfg)}
                onDelete={() => remove(d.id)}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}
