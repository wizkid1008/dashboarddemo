import { useMemo, useState, useRef, useEffect } from 'react'
import { Chart } from 'chart.js/auto'
import { useDashboardMeta, schoolTypeKey } from '@/queries/useDashboardMeta'
import { useDashboardData } from '@/queries/useDashboardData'
import { useAuth } from '@/contexts/AuthContext'
import { SelectDropdown } from '@/components/SelectDropdown'
import { CountryMultiSelect } from '@/components/CountryMultiSelect'

// ── Types ─────────────────────────────────────────────────────────────────────

type GeoLayer = 'country' | 'province' | 'district' | 'school'

// Metrics only available at district level (no school_id in source)
const DISTRICT_ONLY_METRICS = [
  'Post-School Support — Total',
  'Post-School Support — Received Financial Support',
  'Grants — Count',
  'Grants — Total Value (USD)',
  'Loans — Count',
  'Loans — Total Value',
]

// Metrics counting people *currently* supported, one source row per person per
// year. Summing years counts the same person once per year of support, so these
// metrics offer Timeline only — there is no single-number answer we can honestly
// give for a multi-year range without a distinct count at the source.
// Geography still sums normally — different districts are different people.
const NON_ADDITIVE_METRICS = [
  'Children Supported — Total',
  'Post-School Support — Total',
]

function isNonAdditive(metric: string) { return NON_ADDITIVE_METRICS.includes(metric) }

type ChartMode   = 'aggregate' | 'timeline'
type ChartType   = 'bar' | 'horizontal-bar' | 'line' | 'stacked' | 'number'
type BreakdownBy = 'country' | 'province' | 'district' | 'school' | 'combined'

interface CardConfig {
  id:        string
  metric:    string
  mode:      ChartMode
  chartType: ChartType
  breakdown: BreakdownBy
  maxBars:   number
}

const MAX_BAR_OPTIONS = [10, 15, 25, 50]

const GRID_C = 'rgba(13,79,108,0.12)'
const TICK_C = '#5C5C6E'
const COLORS = [
  '#5e2580','#c9a227','#d9534f','#5b9bd5','#4a7c59',
  '#9b59b6','#e67e22','#1abc9c','#e74c3c','#3498db',
]

function uid() { return Math.random().toString(36).slice(2, 9) }

function pluralBreakdown(breakdown: BreakdownBy, count?: number): string {
  const singular: Record<BreakdownBy, string> = {
    country:  'Country',
    province: 'Province',
    district: 'District',
    school:   'School',
    combined: 'Combined',
  }
  const plural: Record<BreakdownBy, string> = {
    country:  'Countries',
    province: 'Provinces',
    district: 'Districts',
    school:   'Schools',
    combined: 'Combined',
  }
  if (count === 1) return singular[breakdown]
  return plural[breakdown]
}

function fmtNum(n: number) {
  if (n >= 1_000_000) return (n / 1_000_000).toFixed(1) + 'M'
  if (n >= 1_000)     return Math.round(n / 1_000) + 'k'
  return Math.round(n).toLocaleString()
}

// ── Access guard ──────────────────────────────────────────────────────────────

export function DynamicPage() {
  const { hasPermission, permissionsLoaded } = useAuth()
  if (!permissionsLoaded) return <div className="body-layout"><div className="main-content"><p style={{ padding: '20px 0', color: 'var(--text-mid)' }}>Loading…</p></div></div>
  if (!hasPermission('page:dynamic')) return (
    <div className="body-layout"><div className="main-content">
      <div style={{ padding: '40px 0', textAlign: 'center' }}>
        <h2 style={{ fontWeight: 600, marginBottom: 8 }}>Access Denied</h2>
        <p style={{ color: 'var(--text-mid)' }}>You do not have permission to view this page.</p>
      </div>
    </div></div>
  )
  return <DynamicContent />
}

// ── Main component ────────────────────────────────────────────────────────────

function DynamicContent() {
  const { data: meta, isPending: metaPending } = useDashboardMeta()

  // ── Filter state ─────────────────────────────────────────────────────────────
  const [layer,      setLayer]      = useState<GeoLayer>('country')
  const [countries,  setCountries]  = useState<string[]>([])
  const [provinces,  setProvinces]  = useState<string[]>([])
  const [districts,  setDistricts]  = useState<string[]>([])
  const [schools,    setSchools]    = useState<string[]>([])
  const [schoolTypes, setSchoolTypes] = useState<string[]>([])
  const [yearStart,  setYearStart]  = useState(2020)
  const [yearEnd,    setYearEnd]    = useState(new Date().getFullYear())
  const [selMetrics, setSelMetrics] = useState<string[]>([])
  const [applied,    setApplied]    = useState<typeof queryParams | null>(null)
  const [cards,      setCards]      = useState<CardConfig[]>([])
  const [howtoDismissed, setHowtoDismissed] = useState(false)

  // ── Cascading options — each level requires its parent to be selected first ──
  const provinceOptions = useMemo(() => {
    if (!meta || !countries.length) return []
    return [...new Set(countries.flatMap(c => meta.provinces[c] ?? []))].sort()
  }, [meta, countries])

  const districtOptions = useMemo(() => {
    if (!meta || !provinces.length) return []
    const all = [...new Set(provinces.flatMap(p => meta.districts[p] ?? []))].sort()
    // At the School layer, hide districts with no schools — otherwise selecting
    // one leaves the School dropdown empty with no explanation.
    if (layer === 'school') return all.filter(d => (meta.schools[d] ?? []).length > 0)
    return all
  }, [meta, provinces, layer])

  // School type options come from the schools in the selected district(s), so the
  // list only ever offers types that actually exist in the current scope.
  const schoolTypeOptions = useMemo(() => {
    if (!meta || !districts.length) return []
    return [...new Set(districts.flatMap(d => meta.schoolTypes[d] ?? []))].sort()
  }, [meta, districts])

  const schoolOptions = useMemo(() => {
    if (!meta || !districts.length) return []
    const all = [...new Set(districts.flatMap(d => meta.schools[d] ?? []))].sort()
    if (!schoolTypes.length) return all
    // Narrow to schools of the selected type(s). Schools with no school_type in
    // dim_school drop out once a type filter is active — matching the server,
    // which excludes NULL school_type rows when p_school_types is set.
    return all.filter(s =>
      districts.some(d => {
        const t = meta.schoolTypeOf[schoolTypeKey(d, s)]
        return t ? schoolTypes.includes(t) : false
      }),
    )
  }, [meta, districts, schoolTypes])

  // ── Available metrics filtered by layer ──────────────────────────────────────
  const availableMetrics = useMemo(() => {
    if (!meta) return []
    if (layer === 'school') return meta.metrics.filter(m => !DISTRICT_ONLY_METRICS.includes(m))
    return meta.metrics
  }, [meta, layer])

  // ── Reset downstream selections when layer changes ───────────────────────────
  function handleLayerChange(l: GeoLayer) {
    setLayer(l)
    setProvinces([])
    setDistricts([])
    setSchools([])
    setSchoolTypes([])
    setSelMetrics([])
    // Re-sync every existing card's breakdown to the new layer, not just new ones.
    setCards(prev => prev.map(c => ({ ...c, breakdown: l as BreakdownBy })))
  }

  // ── Query params ──────────────────────────────────────────────────────────────
  const queryParams = useMemo(() => ({
    countries,
    provinces,
    districts,
    schools,
    yearStart,
    yearEnd,
    metrics: selMetrics,
    // Only meaningful at the School layer — district/country rows carry NULL
    // school_type and would be filtered out entirely.
    schoolTypes: layer === 'school' ? schoolTypes : [],
  }), [countries, provinces, districts, schools, yearStart, yearEnd, selMetrics, layer, schoolTypes])

  const { data, isPending: dataPending, error } = useDashboardData(applied)

  // ── Run ───────────────────────────────────────────────────────────────────────
  function handleRun() {
    setApplied(queryParams)
    // Create a card for each selected metric if not already present
    setCards(prev => {
      const existing = new Set(prev.map(c => c.metric))
      const newCards = selMetrics
        .filter(m => !existing.has(m))
        .map(m => ({
          id:        uid(),
          metric:    m,
          mode:      'timeline' as ChartMode,
          chartType: 'bar'      as ChartType,
          breakdown: layer      as BreakdownBy,
          maxBars:   15,
        }))
      return [...prev, ...newCards]
    })
  }

  // ── Geo label for card description ───────────────────────────────────────────
  const geoLabel = useMemo(() => {
    // School type isn't geography, but without it two runs that differ only by
    // type produce identically-labelled cards.
    const typeSuffix = schoolTypes.length
      ? ` · ${schoolTypes.length === 1 ? schoolTypes[0] : `${schoolTypes.length} School Types`}`
      : ''
    if (schools.length)   return (schools.length   === 1 ? schools[0]   : `${schools.length} Schools`) + typeSuffix
    if (districts.length) return (districts.length === 1 ? districts[0] : `${districts.length} Districts`) + typeSuffix
    if (provinces.length) return provinces.length === 1 ? provinces[0] : `${provinces.length} Provinces`
    if (countries.length) return countries.length === 1 ? countries[0] : `${countries.length} Countries`
    return ''
  }, [countries, provinces, districts, schools, schoolTypes])

  // ── Years available ───────────────────────────────────────────────────────────
  const allYears = meta?.years ?? []

  // ── Single-select constraints: every level above the active layer is locked to 1 ──
  const countrySingle = layer !== 'country'
  const provinceSingle = layer === 'district' || layer === 'school'
  const districtSingle = layer === 'school'

  return (
    <div id="dynamic-data-view">

      {/* ── Row 1: Geography ─────────────────────────────────────────────────── */}
      <div className="filter-bar" style={{ gap: '12px 20px', alignItems: 'flex-end', borderBottom: '1px solid var(--line)', paddingBottom: 12 }}>

        {/* Layer toggle */}
        <div className="filter-bar-item">
          <label className="filter-bar-label">
            <svg width="14" height="14" viewBox="0 0 20 20" fill="none" aria-hidden="true"><path d="M2 5h16M2 10h16M2 15h16" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round"/></svg>
            Layer
          </label>
          <div className="seg-control" role="radiogroup" aria-label="Data layer">
            <label className="seg-opt">
              <input type="radio" name="ddLayer" value="country" checked={layer === 'country'} onChange={() => handleLayerChange('country')} />
              <span><svg viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true"><circle cx="7" cy="7" r="5.5"/><path d="M7 1.5c-1.2 1.6-2 3.4-2 5.5s.8 3.9 2 5.5M7 1.5c1.2 1.6 2 3.4 2 5.5s-.8 3.9-2 5.5M1.5 7h11"/></svg>Country</span>
            </label>
            <label className="seg-opt">
              <input type="radio" name="ddLayer" value="province" checked={layer === 'province'} onChange={() => handleLayerChange('province')} />
              <span><svg viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true"><path d="M2 12L7 2l5 10"/><path d="M3.5 8.5h7"/></svg>Province</span>
            </label>
            <label className="seg-opt">
              <input type="radio" name="ddLayer" value="district" checked={layer === 'district'} onChange={() => handleLayerChange('district')} />
              <span><svg viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true"><path d="M7 12.5S2 8.5 2 5.5a5 5 0 0110 0c0 3-5 7-5 7z"/><circle cx="7" cy="5.5" r="1.5"/></svg>District</span>
            </label>
            <label className="seg-opt">
              <input type="radio" name="ddLayer" value="school" checked={layer === 'school'} onChange={() => handleLayerChange('school')} />
              <span><svg viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true"><rect x="1.5" y="6" width="11" height="6.5" rx="1"/><path d="M0.5 6L7 2l6.5 4"/><rect x="5" y="9" width="4" height="3.5"/></svg>School</span>
            </label>
          </div>
        </div>

        {/* Country — single-select when layer is Province, District, or School */}
        <div className="filter-bar-item">
          <label className="filter-bar-label">
            <svg width="14" height="14" viewBox="0 0 20 20" fill="none" aria-hidden="true"><circle cx="10" cy="10" r="8" stroke="currentColor" strokeWidth="1.7"/><ellipse cx="10" cy="10" rx="3.5" ry="8" stroke="currentColor" strokeWidth="1.7"/><path d="M2 10h16" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round"/></svg>
            Country
          </label>
          <CountryMultiSelect
            allCountries={(meta?.countries ?? []).filter(c => c !== 'International')}
            selected={countries}
            onChange={v => { setCountries(v.filter(x => x !== 'All')); setProvinces([]); setDistricts([]); setSchools([]); setSchoolTypes([]) }}
            entityName="Countries"
            singleSelect={countrySingle}
            hideAllOption
          />
        </div>

        {/* Province — visible when layer ≠ country; single-select when layer is District or School */}
        {layer !== 'country' && (
          <div className="filter-bar-item">
            <label className="filter-bar-label">
              <svg width="14" height="14" viewBox="0 0 20 20" fill="none" aria-hidden="true"><path d="M10 2l2 6h6l-5 4 2 6-5-4-5 4 2-6-5-4h6z" stroke="currentColor" strokeWidth="1.5"/></svg>
              Province
            </label>
            <CountryMultiSelect
              allCountries={provinceOptions}
              selected={provinces}
              onChange={v => { setProvinces(v.filter(x => x !== 'All')); setDistricts([]); setSchools([]); setSchoolTypes([]) }}
              entityName="Provinces"
              singleSelect={provinceSingle}
              hideAllOption
              disabled={!countries.length}
            />
          </div>
        )}

        {/* District — visible when layer is District or School; single-select when layer is School */}
        {(layer === 'district' || layer === 'school') && (
          <div className="filter-bar-item">
            <label className="filter-bar-label">
              <svg width="14" height="14" viewBox="0 0 20 20" fill="none" aria-hidden="true"><circle cx="10" cy="8" r="3" stroke="currentColor" strokeWidth="1.7"/><path d="M10 2C6.13 2 3 5.13 3 9c0 5.25 7 11 7 11s7-5.75 7-11c0-3.87-3.13-7-7-7z" stroke="currentColor" strokeWidth="1.7"/></svg>
              District
            </label>
            <CountryMultiSelect
              allCountries={districtOptions}
              selected={districts}
              onChange={v => { setDistricts(v.filter(x => x !== 'All')); setSchools([]); setSchoolTypes([]) }}
              entityName="Districts"
              singleSelect={districtSingle}
              hideAllOption
              disabled={!provinces.length}
            />
          </div>
        )}

        {/* School Type — School layer only; narrows the School list below it */}
        {layer === 'school' && (
          <div className="filter-bar-item">
            <label className="filter-bar-label">
              <svg width="14" height="14" viewBox="0 0 20 20" fill="none" aria-hidden="true"><path d="M3 7l7-4 7 4-7 4-7-4z" stroke="currentColor" strokeWidth="1.7" strokeLinejoin="round"/><path d="M6 9v4c0 1.1 1.8 2 4 2s4-.9 4-2V9" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round"/></svg>
              School Type
            </label>
            <CountryMultiSelect
              allCountries={schoolTypeOptions}
              selected={schoolTypes}
              onChange={v => { setSchoolTypes(v.filter(x => x !== 'All')); setSchools([]) }}
              entityName="School Types"
              hideAllOption
              disabled={!districts.length}
            />
          </div>
        )}

        {/* School */}
        {layer === 'school' && (
          <div className="filter-bar-item">
            <label className="filter-bar-label">
              <svg width="14" height="14" viewBox="0 0 20 20" fill="none" aria-hidden="true"><path d="M2 18V8l8-6 8 6v10" stroke="currentColor" strokeWidth="1.7" strokeLinejoin="round"/><rect x="7" y="12" width="6" height="6" rx="1" stroke="currentColor" strokeWidth="1.5"/></svg>
              School
            </label>
            <CountryMultiSelect
              allCountries={schoolOptions}
              selected={schools}
              onChange={v => setSchools(v.filter(x => x !== 'All'))}
              entityName="Schools"
              hideAllOption
              disabled={!districts.length}
            />
          </div>
        )}
      </div>

      {/* ── Row 2: Time, KPIs, Run ────────────────────────────────────────────── */}
      <div className="filter-bar" style={{ gap: '12px 20px', alignItems: 'flex-end' }}>

        {/* Start Year */}
        <div className="filter-bar-item">
          <label className="filter-bar-label">
            <svg width="14" height="14" viewBox="0 0 20 20" fill="none" aria-hidden="true"><rect x="2" y="4" width="16" height="14" rx="2" stroke="currentColor" strokeWidth="1.7"/><path d="M6 2v4M14 2v4M2 9h16" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/></svg>
            Start Year
          </label>
          <SelectDropdown
            options={allYears.filter(y => y <= yearEnd).map(String)}
            value={String(yearStart)}
            onChange={v => setYearStart(Number(v))}
          />
        </div>

        {/* End Year */}
        <div className="filter-bar-item">
          <label className="filter-bar-label">
            <svg width="14" height="14" viewBox="0 0 20 20" fill="none" aria-hidden="true"><rect x="2" y="4" width="16" height="14" rx="2" stroke="currentColor" strokeWidth="1.7"/><path d="M6 2v4M14 2v4M2 9h16" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round"/></svg>
            End Year
          </label>
          <SelectDropdown
            options={allYears.filter(y => y >= yearStart).map(String)}
            value={String(yearEnd)}
            onChange={v => setYearEnd(Number(v))}
          />
        </div>

        {/* Metrics */}
        <div className="filter-bar-item" style={{ minWidth: 240, flex: '1 1 240px' }}>
          <label className="filter-bar-label">
            <svg width="14" height="14" viewBox="0 0 20 20" fill="none" aria-hidden="true"><path d="M4 10h12M4 6h12M4 14h8" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round"/></svg>
            Metrics
          </label>
          <CountryMultiSelect
            allCountries={availableMetrics}
            selected={selMetrics.length ? selMetrics : []}
            onChange={v => setSelMetrics(v.includes('All') ? availableMetrics : v)}
            entityName="Metrics"
            hideAllOption
          />
        </div>

        {/* Run */}
        <div className="filter-bar-item" style={{ alignSelf: 'flex-end' }}>
          <button
            className="dd-run-btn"
            onClick={handleRun}
            disabled={!selMetrics.length || metaPending}
          >
            Run
          </button>
        </div>
      </div>

      {/* ── Body ─────────────────────────────────────────────────────────────── */}
      <div className="body-layout">
        <div className="main-content">

          {!metaPending && meta && meta.countries.length === 0 && (
            <div className="admin-empty" style={{ padding: '48px 0', textAlign: 'center' }}>
              You have not been assigned access to any country's data. Contact an administrator.
            </div>
          )}

          {/* How-to panel */}
          {!applied && !howtoDismissed && (
            <div id="dd-choose-geo" className="landing-section landing-section--how-to">
              <button type="button" className="map-how-to-close" aria-label="Dismiss" onClick={() => setHowtoDismissed(true)}>
                <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
                  <path d="M4 4l8 8M12 4l-8 8" strokeLinecap="round" />
                </svg>
              </button>
              <div className="landing-title">How to Use Dynamic Data</div>
              <p className="landing-intro">
                Drill into country, province, district, and school-level data for any metric across any year range.
              </p>
              <div className="landing-steps">
                <div className="landing-step"><span className="landing-step-num">1</span><div className="landing-step-text"><strong>Select a Layer</strong><span>Choose Country, Province, District, or School to set the geographic detail level.</span></div></div>
                <div className="landing-step"><span className="landing-step-num">2</span><div className="landing-step-text"><strong>Filter the Geography</strong><span>Use the cascading dropdowns to narrow to specific countries, provinces, districts, or schools.</span></div></div>
                <div className="landing-step"><span className="landing-step-num">3</span><div className="landing-step-text"><strong>Set the Year Range</strong><span>Choose a start and end year.</span></div></div>
                <div className="landing-step"><span className="landing-step-num">4</span><div className="landing-step-text"><strong>Select Metrics</strong><span>Pick one or more metrics. Available metrics update based on your selected layer.</span></div></div>
                <div className="landing-step"><span className="landing-step-num">5</span><div className="landing-step-text"><strong>Click Run</strong><span>Charts appear below — one per metric. Use each card's controls to switch chart type or view.</span></div></div>
              </div>
              <div className="landing-tip">
                <span className="landing-tip-arrow">→</span>
                <span>Use <strong>Layer</strong> on the{' '}
                  <span style={{ background: 'var(--purple)', color: 'white', padding: '2px 8px', borderRadius: 4, fontWeight: 700, fontSize: '0.82rem' }}>Data Map</span>{' '}
                  to visualise this data geographically.
                </span>
              </div>
            </div>
          )}

          {error instanceof Error && (
            <p style={{ color: 'red' }}>Query failed: {error.message}</p>
          )}

          {dataPending && applied && (
            <div>
              <div className="dd-progress-bar" />
              <p style={{ fontSize: '0.82rem', color: 'var(--text-mid)', marginBottom: 16 }}>
                Fetching data…
              </p>
            </div>
          )}

          {/* ── Card grid ──────────────────────────────────────────────────── */}
          {applied && data && cards.length > 0 && (
            <div className="card-grid-2">
              {cards
                .filter(card => data.data.some(r => r.metric === card.metric))
                .map(card => (
                  <MetricCard
                    key={card.id}
                    config={card}
                    data={data.data}
                    layer={layer}
                    yearStart={yearStart}
                    yearEnd={yearEnd}
                    geoLabel={geoLabel}
                    onUpdate={updated => setCards(prev => prev.map(c => c.id === updated.id ? updated : c))}
                    onRemove={() => setCards(prev => prev.filter(c => c.id !== card.id))}
                  />
                ))}
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

// ── MetricCard ────────────────────────────────────────────────────────────────

const MODE_OPTIONS    = ['Aggregate', 'Timeline']
// NON_ADDITIVE_METRICS get Timeline only. Collapsing their year axis to one
// number previously showed the peak year, which is never an overstatement but
// also isn't the reach figure a reader assumes it is, so the mode is gone
// rather than relabelled again.
const MODE_OPTIONS_NON_ADDITIVE = ['Timeline']
const CHART_OPTIONS   = ['Bar', 'Horizontal Bar', 'Line', 'Stacked', 'Number']

interface MetricCardProps {
  config:    CardConfig
  data:      import('@/types/dashboard').DashboardRow[]
  layer:     GeoLayer
  yearStart: number
  yearEnd:   number
  geoLabel:  string
  onUpdate:  (c: CardConfig) => void
  onRemove:  () => void
}

function MetricCard({ config, data, layer, yearStart, yearEnd, geoLabel, onUpdate, onRemove }: MetricCardProps) {
  const rows = useMemo(() => data.filter(r => r.metric === config.metric), [data, config.metric])
  const years  = useMemo(() => {
    const s = new Set<number>()
    rows.forEach(r => s.add(r.year))
    return [...s].sort((a, b) => a - b)
  }, [rows])

  // Breakdown dimension key
  const dimKey: keyof import('@/types/dashboard').DashboardRow = useMemo(() => {
    if (config.breakdown === 'school')   return 'school'
    if (config.breakdown === 'district') return 'district'
    if (config.breakdown === 'province') return 'province'
    return 'country'
  }, [config.breakdown])

  // Entities for this breakdown
  const entities = useMemo(() => {
    const s = new Set<string>()
    rows.forEach(r => { const v = r[dimKey]; if (v && !['District Total','National'].includes(String(v))) s.add(String(v)) })
    return [...s].sort()
  }, [rows, dimKey])

  // Aggregate totals per entity (sorted by value desc, capped at MAX_BARS).
  // Two stages, because the two directions aren't equivalent: summing across
  // geography within a year is always right, but summing across years is only
  // right for metrics counting one-off events. See NON_ADDITIVE_METRICS.
  const nonAdditive = isNonAdditive(config.metric)

  // Non-additive metrics have no Aggregate mode to select, but a config could still
  // carry mode: 'aggregate' — so the whole card reads this, not config.mode, and the
  // dead branch can never render a person-year sum.
  const mode = nonAdditive ? 'timeline' : config.mode

  const aggData = useMemo(() => {
    const totals = entities.map(e => {
      const byYear = years.map(yr =>
        rows.filter(r => String(r[dimKey]) === e && r.year === yr)
            .reduce((s, r) => s + r.value, 0))
      return {
        // For non-additive metrics this value is never displayed — it only ranks
        // entities for the timeline's top-N. Peak keeps that ranking honest; a sum
        // would rank by person-years, favouring long-supported cohorts.
        label: e,
        value: nonAdditive
          ? byYear.reduce((m, v) => Math.max(m, v), 0)
          : byYear.reduce((s, v) => s + v, 0),
      }
    })
    totals.sort((a, b) => b.value - a.value)
    return totals
  }, [rows, entities, years, dimKey, nonAdditive])

  const maxBars       = config.maxBars ?? 15
  const aggCapped     = aggData.slice(0, maxBars)
  const totalEntities = aggData.length

  // Timeline series per entity
  const timelineData = useMemo(() => {
    const topEntities = config.breakdown === 'combined'
      ? ['All']
      : aggData.slice(0, maxBars).map(d => d.label)

    return topEntities.map((e, i) => ({
      label: e,
      color: COLORS[i % COLORS.length],
      data:  years.map(yr => {
        if (e === 'All') return rows.filter(r => r.year === yr).reduce((s, r) => s + r.value, 0)
        return rows.filter(r => String(r[dimKey]) === e && r.year === yr).reduce((s, r) => s + r.value, 0)
      }),
    }))
  }, [rows, aggData, years, dimKey, config.breakdown])

  const chartId = `${config.id}-${mode}-${config.chartType}-${config.breakdown}`

  const breakdownOptions: BreakdownBy[] = useMemo(() => {
    const opts: BreakdownBy[] = ['combined']
    if (layer === 'school')   return [...opts, 'school', 'district', 'province', 'country']
    if (layer === 'district') return [...opts, 'district', 'province', 'country']
    if (layer === 'province') return [...opts, 'province', 'country']
    return [...opts, 'country']
  }, [layer])

  const breakdownLabels: Record<BreakdownBy, string> = {
    combined: 'Combined', country: 'Per Country', province: 'Per Province',
    district: 'Per District', school: 'Per School',
  }

  function patch(p: Partial<CardConfig>) { onUpdate({ ...config, ...p }) }



  return (
    <div className="data-card">
      {/* Header */}
      <div className="data-card-header" style={{ alignItems: 'flex-start' }}>
        <span style={{ flex: 1, fontSize: '0.92rem', fontWeight: 600 }}>{config.metric}</span>
        <div style={{ display: 'flex', gap: 6, alignItems: 'center', flexShrink: 0 }}>
          <button
            onClick={onRemove}
            title="Remove card"
            style={{ background: 'none', border: 'none', cursor: 'pointer', color: 'var(--muted)', fontSize: '1rem', lineHeight: 1 }}
          >✕</button>
        </div>
      </div>

      {/* Subtitle */}
      <div className="dd-breadcrumb-bar" style={{ padding: '4px 16px 8px', fontSize: '0.78rem', color: 'var(--text-mid)' }}>
        {geoLabel ? `${geoLabel} · ` : ''}{yearStart}–{yearEnd}
        {totalEntities > maxBars && mode === 'aggregate' && (
          <span style={{ marginLeft: 8, color: 'var(--muted)', fontStyle: 'italic' }}>
            (top {maxBars} of {totalEntities})
          </span>
        )}
        {nonAdditive && (
          <div style={{ marginTop: 4, color: 'var(--muted)', fontStyle: 'italic' }}>
            Counts people supported in each year — the same person recurs across years,
            so years cannot be added together and this metric is shown per year only.
          </div>
        )}
      </div>

      {/* Controls */}
      <div className="dashlet-controls" style={{ padding: '0 16px 10px', display: 'flex', gap: 8, flexWrap: 'wrap' }}>
        <SelectDropdown
          options={nonAdditive ? MODE_OPTIONS_NON_ADDITIVE : MODE_OPTIONS}
          value={mode === 'aggregate' ? 'Aggregate' : 'Timeline'}
          onChange={v => patch({ mode: v === 'Timeline' ? 'timeline' : 'aggregate' })}
        />
        <SelectDropdown
          options={CHART_OPTIONS}
          value={config.chartType === 'bar' ? 'Bar' : config.chartType === 'horizontal-bar' ? 'Horizontal Bar' : config.chartType === 'line' ? 'Line' : config.chartType === 'stacked' ? 'Stacked' : 'Number'}
          onChange={v => patch({ chartType: v === 'Bar' ? 'bar' : v === 'Horizontal Bar' ? 'horizontal-bar' : v === 'Line' ? 'line' : v === 'Stacked' ? 'stacked' : 'number' })}
        />
        <SelectDropdown
          options={breakdownOptions.map(b => breakdownLabels[b])}
          value={breakdownLabels[config.breakdown] ?? 'Combined'}
          onChange={v => {
            const found = breakdownOptions.find(b => breakdownLabels[b] === v)
            if (found) patch({ breakdown: found })
          }}
        />
        <SelectDropdown
          options={MAX_BAR_OPTIONS.map(n => `Top ${n}`)}
          value={`Top ${maxBars}`}
          onChange={v => patch({ maxBars: Number(v.replace('Top ', '')) })}
        />
      </div>

      {/* Chart */}
      <div className="data-card-body" style={{ padding: '0 16px 16px' }}>
        {/* Geographic unit count — showing X of Y */}
        <div style={{ padding: '4px 16px 10px', display: 'flex', alignItems: 'baseline', gap: 6 }}>
          <span style={{ fontSize: '1.1rem', fontWeight: 700, color: 'var(--purple)', lineHeight: 1 }}>
            {Math.min(aggCapped.length, totalEntities)}
          </span>
          {totalEntities > aggCapped.length && (
            <>
              <span style={{ fontSize: '0.85rem', color: 'var(--text-mid)' }}>of</span>
              <span style={{ fontSize: '1.1rem', fontWeight: 700, color: 'var(--purple)', lineHeight: 1 }}>
                {totalEntities}
              </span>
            </>
          )}
          <span style={{ fontSize: '0.78rem', color: 'var(--text-mid)' }}>
            {totalEntities > aggCapped.length
              ? `${pluralBreakdown(config.breakdown)} shown`
              : pluralBreakdown(config.breakdown, totalEntities)}
          </span>
        </div>

        {config.chartType === 'number' ? (
          <div style={{ padding: '8px 16px 16px', overflowX: 'auto' }}>
            {config.breakdown === 'combined' ? (
              /* Combined — one number per year */
              <div style={{ display: 'flex', gap: 24, flexWrap: 'wrap' }}>
                {years.map(yr => (
                  <div key={yr} style={{ textAlign: 'center', minWidth: 80 }}>
                    <div style={{ fontSize: '0.72rem', color: 'var(--text-mid)', marginBottom: 2 }}>{yr}</div>
                    <div style={{ fontSize: '1.8rem', fontWeight: 700, color: 'var(--purple)', lineHeight: 1 }}>
                      {rows.filter(r => r.year === yr).reduce((s, r) => s + r.value, 0).toLocaleString()}
                    </div>
                  </div>
                ))}
              </div>
            ) : (
              /* Per entity — table: rows = entities, cols = years */
              <table style={{ borderCollapse: 'collapse', width: '100%', fontSize: '0.82rem' }}>
                <thead>
                  <tr>
                    <th style={{ textAlign: 'left', padding: '4px 8px', color: 'var(--text-mid)', fontWeight: 500 }}>
                      {breakdownLabels[config.breakdown]}
                    </th>
                    {years.map(yr => (
                      <th key={yr} style={{ textAlign: 'right', padding: '4px 8px', color: 'var(--text-mid)', fontWeight: 500 }}>{yr}</th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {aggCapped.map((e, i) => (
                    <tr key={e.label} style={{ background: i % 2 === 0 ? 'transparent' : 'rgba(102,47,108,0.04)' }}>
                      <td style={{ padding: '4px 8px', color: 'var(--text-dark)', fontWeight: 500 }}>{e.label}</td>
                      {years.map(yr => (
                        <td key={yr} style={{ padding: '4px 8px', textAlign: 'right', fontWeight: 600, color: 'var(--purple)' }}>
                          {rows.filter(r => String(r[dimKey]) === e.label && r.year === yr)
                               .reduce((s, r) => s + r.value, 0)
                               .toLocaleString()}
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            )}
          </div>
        ) : mode === 'aggregate' ? (
          <div className="chart-container h220">
            <AggChart
              id={chartId}
              labels={aggCapped.map(d => d.label)}
              values={aggCapped.map(d => d.value)}
              horizontal={config.chartType === 'horizontal-bar'}
              yLabel={config.metric}
              xLabel={breakdownLabels[config.breakdown]}
            />
          </div>
        ) : (
          <div className="chart-container h220">
            <TimelineChart
              id={chartId}
              years={years}
              series={timelineData}
              stacked={config.chartType === 'stacked'}
              isLine={config.chartType === 'line'}
              yLabel={config.metric}
            />
          </div>
        )}
      </div>
    </div>
  )
}

// ── AggChart ──────────────────────────────────────────────────────────────────

function AggChart({ id, labels, values, horizontal, yLabel, xLabel }: {
  id: string; labels: string[]; values: number[]
  horizontal: boolean; yLabel: string; xLabel: string
}) {
  const ref = useRef<HTMLCanvasElement | null>(null)
  useEffect(() => {
    const ctx = ref.current; if (!ctx) return
    const chart = new Chart(ctx, {
      type: 'bar',
      data: {
        labels,
        datasets: [{ data: values, backgroundColor: COLORS, borderRadius: 4, borderSkipped: false }],
      },
      options: {
        responsive: true, maintainAspectRatio: false,
        indexAxis: horizontal ? 'y' : 'x',
        plugins: {
          legend: { display: false },
          tooltip: { callbacks: { label: ctx => ` ${Math.round(Number(ctx.raw ?? 0)).toLocaleString()}` } },
        },
        scales: {
          x: { grid: { color: horizontal ? 'transparent' : GRID_C }, ticks: { color: TICK_C, font: { size: 10 } },
               title: { display: !horizontal, text: xLabel, color: TICK_C, font: { size: 10 } },
               ...(horizontal ? { ticks: { color: TICK_C, font: { size: 10 }, callback: (v) => fmtNum(Number(v)) } } : {}) },
          y: { grid: { color: GRID_C }, ticks: { color: TICK_C, font: { size: 10 } },
               title: { display: horizontal, text: yLabel, color: TICK_C, font: { size: 10 } },
               ...(horizontal ? {} : { ticks: { color: TICK_C, font: { size: 10 }, callback: (v) => fmtNum(Number(v)) } }) },
        },
        layout: { padding: { right: horizontal ? 40 : 8 } },
      },
    })
    return () => chart.destroy()
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, JSON.stringify(labels), JSON.stringify(values), horizontal])
  return <canvas ref={ref} />
}

// ── TimelineChart ─────────────────────────────────────────────────────────────

function TimelineChart({ id, years, series, stacked, isLine, yLabel }: {
  id: string; years: number[]
  series: { label: string; color: string; data: number[] }[]
  stacked: boolean; isLine: boolean; yLabel: string
}) {
  const ref = useRef<HTMLCanvasElement | null>(null)
  useEffect(() => {
    const ctx = ref.current; if (!ctx || !series.length) return
    const chart = new Chart(ctx, {
      type: isLine ? 'line' : 'bar',
      data: {
        labels: years.map(String),
        datasets: series.map(s => isLine ? ({
          label: s.label, data: s.data, borderColor: s.color,
          backgroundColor: s.color + '33', tension: 0.35, pointRadius: 3, fill: false,
        }) : ({
          label: s.label, data: s.data, backgroundColor: s.color,
          borderRadius: stacked ? 0 : 3, borderSkipped: false as const,
        })),
      },
      options: {
        responsive: true, maintainAspectRatio: false,
        plugins: {
          legend: { display: series.length > 1, labels: { color: TICK_C, font: { size: 10 }, usePointStyle: true } },
          tooltip: { callbacks: { label: ctx => ` ${ctx.dataset.label}: ${Math.round(Number(ctx.raw ?? 0)).toLocaleString()}` } },
        },
        scales: {
          x: { stacked, grid: { color: GRID_C }, ticks: { color: TICK_C, font: { size: 10 } },
               title: { display: true, text: 'Year', color: TICK_C, font: { size: 10 } } },
          y: { stacked, grid: { color: GRID_C },
               ticks: { color: TICK_C, font: { size: 10 }, callback: v => fmtNum(Number(v)) },
               title: { display: true, text: yLabel, color: TICK_C, font: { size: 10 } } },
        },
      },
    })
    return () => chart.destroy()
  // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [id, JSON.stringify(years), JSON.stringify(series), stacked, isLine])
  return <canvas ref={ref} />
}
