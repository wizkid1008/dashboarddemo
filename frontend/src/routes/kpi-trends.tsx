import { useMemo, useState } from 'react'
import { useNavigate, useSearch } from '@tanstack/react-router'
import { FilterSection } from '@/components/FilterSection'
import { SelectDropdown } from '@/components/SelectDropdown'
import { useDashboardMeta } from '@/queries/useDashboardMeta'
import { useAuth } from '@/contexts/AuthContext'
import { useSetKpiTrendChartVisibility } from '@/features/admin/queries'
import {
  useKpiReportYears,
  useKpiReportAllGroups,
  useKpiReportAllIndicators,
  useKpiReportIndicatorTrend,
  useKpiReportIndicatorTrendAllCountries,
} from '@/features/kpi-report/queries'
import { formatKpiValue, trendKey, kpiTrendChartKey, disaggregationLabel, linreg, trendPoints, trendSegments } from '@/features/kpi-report/trend-utils'
import type { KpiReportIndicator } from '@/features/kpi-report/queries'

type Mode = 'country' | 'indicator'

function indicatorLabel(ind: KpiReportIndicator): string {
  return ind.source_kpi_id ? `${ind.source_kpi_id} — ${ind.indicator}` : ind.indicator
}

// Full-size trend chart (By Country mode) — gridlines, year axis, filled area,
// dashed linear trend, direct end-label. Gaps in the line are years with no
// submitted data, not zero — every year is an independent upload snapshot.
function FullTrendChart({
  label,
  years,
  values,
  valueType,
  isHidden,
  onToggleVisibility,
}: {
  label: string
  years: number[]
  values: Record<number, string>
  valueType: string | null
  isHidden?: boolean
  onToggleVisibility?: () => void
}) {
  const w = 600, h = 150, padL = 8, padR = 46, padT = 22, padB = 22

  const points = trendPoints(years, values)
  if (!points.length) return null

  const vals = points.map((p) => p.value)
  const min = Math.min(...vals)
  const max = Math.max(...vals)
  const range = (max - min) || 1
  const yearMin = years[0]
  const yearMax = years[years.length - 1]
  const xStep = yearMax > yearMin ? (w - padL - padR) / (yearMax - yearMin) : 0
  const xOf = (y: number) => padL + (y - yearMin) * xStep
  const yOf = (v: number) => padT + (1 - (v - min) / range) * (h - padT - padB)

  const segments = trendSegments(years, values)
  const lastPoint = points[points.length - 1]

  let trendPath: string | null = null
  if (points.length >= 2) {
    const { slope, intercept } = linreg(points)
    const firstYear = points[0].year
    const lastYear = points[points.length - 1].year
    const y1 = intercept + slope * firstYear
    const y2 = intercept + slope * lastYear
    trendPath = `M${xOf(firstYear).toFixed(1)},${yOf(y1).toFixed(1)} L${xOf(lastYear).toFixed(1)},${yOf(y2).toFixed(1)}`
  }

  const missing = years.length - points.length
  const { text: lastText } = formatKpiValue(valueType, String(lastPoint.value))

  return (
    <div className={`chart-card${isHidden ? ' chart-card--hidden' : ''}`}>
      <div className="chart-card-head">
        <span className="chart-title">{label}</span>
        <span className="chart-current">
          Latest ({lastPoint.year}) <b>{lastText}</b>
        </span>
        {onToggleVisibility && (
          <button type="button" className="admin-btn admin-btn--secondary" style={{ marginLeft: 'auto' }} onClick={onToggleVisibility}>
            {isHidden ? 'Show' : 'Hide'}
          </button>
        )}
      </div>
      <svg width="100%" viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" style={{ display: 'block' }}>
        {[0, 0.5, 1].map((t) => {
          const y = padT + t * (h - padT - padB)
          return <line key={t} x1={padL} y1={y} x2={w - padR} y2={y} className="grid-line" />
        })}
        {segments.map((seg, si) => {
          const top = seg.map((p, i) => `${i === 0 ? 'M' : 'L'}${xOf(p.year).toFixed(1)},${yOf(p.value).toFixed(1)}`).join(' ')
          const area = `${top} L${xOf(seg[seg.length - 1].year).toFixed(1)},${h - padB} L${xOf(seg[0].year).toFixed(1)},${h - padB} Z`
          return <path key={si} d={area} className="trend-area" />
        })}
        {trendPath && <path d={trendPath} className="trend-dash" />}
        {segments.map((seg, si) => (
          <g key={si}>
            <path d={seg.map((p, i) => `${i === 0 ? 'M' : 'L'}${xOf(p.year).toFixed(1)},${yOf(p.value).toFixed(1)}`).join(' ')} className="trend-line" />
            {seg.map((p) => (
              <circle key={p.year} cx={xOf(p.year)} cy={yOf(p.value)} r={3.5} className="trend-dot" />
            ))}
          </g>
        ))}
        {points.map((p) => {
          if (p.year === lastPoint.year) return null
          const anchor = p.year === points[0].year ? 'start' : 'middle'
          return (
            <text key={p.year} x={xOf(p.year)} y={yOf(p.value) - 8} textAnchor={anchor} className="point-label">
              {formatKpiValue(valueType, String(p.value)).text}
            </text>
          )
        })}
        <text x={xOf(lastPoint.year) + 8} y={yOf(lastPoint.value) + 4} className="end-label">
          {lastText}
        </text>
        {years.map((y) => (
          <text key={y} x={xOf(y)} y={h - 4} className="axis-label" textAnchor="middle">
            {y}
          </text>
        ))}
      </svg>
      {missing > 0 && <div className="chart-note">{missing} year(s) with no submitted data for this disaggregation.</div>}
    </div>
  )
}

// Fixed categorical order — same brand palette used elsewhere in the app
// (DDChart.tsx MULTI_COLORS) — assigned by country identity, never cycled
// or repainted when the country list changes.
const COUNTRY_COLORS = [
  '#0D4F6C', '#D9A441', '#D8752C', '#1E7896', '#6FA641',
  '#1E7896', '#6FA641', '#e8a020', '#f07050', '#2d7a5a',
]

// Combined chart (By Indicator / cross-country mode) — every country on one
// shared axis so magnitude is directly comparable, not just shape/direction.
function CombinedTrendChart({
  countries,
  years,
  valueType,
}: {
  countries: { country: string; values: Record<number, string> }[]
  years: number[]
  valueType: string | null
}) {
  const w = 640, h = 220, padL = 8, padR = 12, padT = 14, padB = 22

  const perCountry = countries
    .map((c) => ({ country: c.country, points: trendPoints(years, c.values), segments: trendSegments(years, c.values) }))
    .filter((c) => c.points.length > 0)
  if (!perCountry.length) return null

  const allVals = perCountry.flatMap((c) => c.points.map((p) => p.value))
  const min = Math.min(0, ...allVals)
  const max = Math.max(...allVals)
  const range = (max - min) || 1
  const yearMin = years[0]
  const yearMax = years[years.length - 1]
  const xStep = yearMax > yearMin ? (w - padL - padR) / (yearMax - yearMin) : 0
  const xOf = (y: number) => padL + (y - yearMin) * xStep
  const yOf = (v: number) => padT + (1 - (v - min) / range) * (h - padT - padB)

  const showDirectLabels = perCountry.length <= 4

  return (
    <div className="chart-card">
      <svg width="100%" viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" style={{ display: 'block' }}>
        {[0, 0.5, 1].map((t) => {
          const y = padT + t * (h - padT - padB)
          return <line key={t} x1={padL} y1={y} x2={w - padR} y2={y} className="grid-line" />
        })}
        {perCountry.map((c, ci) => {
          const color = COUNTRY_COLORS[ci % COUNTRY_COLORS.length]
          const lastPoint = c.points[c.points.length - 1]
          return (
            <g key={c.country}>
              {c.segments.map((seg, si) => (
                <path
                  key={si}
                  d={seg.map((p, i) => `${i === 0 ? 'M' : 'L'}${xOf(p.year).toFixed(1)},${yOf(p.value).toFixed(1)}`).join(' ')}
                  fill="none"
                  stroke={color}
                  strokeWidth={2}
                  strokeLinecap="round"
                />
              ))}
              {c.points.map((p) => (
                <circle key={p.year} cx={xOf(p.year)} cy={yOf(p.value)} r={3} fill={color}>
                  <title>{c.country}: {formatKpiValue(valueType, String(p.value)).text} ({p.year})</title>
                </circle>
              ))}
              {showDirectLabels && (
                <text x={xOf(lastPoint.year) + 6} y={yOf(lastPoint.value) + 3} fontSize={9} fill={color}>
                  {c.country}
                </text>
              )}
            </g>
          )
        })}
        {years.map((y) => (
          <text key={y} x={xOf(y)} y={h - 4} className="axis-label" textAnchor="middle">
            {y}
          </text>
        ))}
      </svg>
      <div className="chart-legend">
        {perCountry.map((c, ci) => {
          const lastPoint = c.points[c.points.length - 1]
          const { text } = formatKpiValue(valueType, String(lastPoint.value))
          return (
            <span key={c.country} className="chart-legend-item">
              <span className="chart-legend-swatch" style={{ background: COUNTRY_COLORS[ci % COUNTRY_COLORS.length] }} />
              {c.country} <b>{text}</b> ({lastPoint.year})
            </span>
          )
        })}
      </div>
    </div>
  )
}

export function KpiTrendsPage() {
  const { hasPermission, permissionsLoaded } = useAuth()
  if (!permissionsLoaded) {
    return <div className="body-layout"><div className="main-content"><p style={{ padding: '20px 0', color: 'var(--text-mid)' }}>Loading…</p></div></div>
  }
  if (!hasPermission('page:kpi-trends')) {
    return (
      <div className="body-layout"><div className="main-content">
        <div style={{ padding: '40px 0', textAlign: 'center' }}>
          <h2 style={{ fontWeight: 600, marginBottom: 8 }}>Access Denied</h2>
          <p style={{ color: 'var(--text-mid)' }}>You do not have permission to view this page.</p>
        </div>
      </div></div>
    )
  }
  return <KpiTrendsContent />
}

function KpiTrendsContent() {
  const navigate = useNavigate()
  const search = useSearch({ strict: false }) as { country?: string; group?: string; indicator?: string }
  const { isAdmin } = useAuth()
  const setChartVisibility = useSetKpiTrendChartVisibility()

  const { data: meta } = useDashboardMeta()
  const countries = useMemo(() => (meta?.countries ?? []).filter((c) => c !== 'International'), [meta])

  const [mode, setMode] = useState<Mode>('country')
  const [countryOverride, setCountryOverride] = useState<string | undefined>(undefined)
  const [groupOverride, setGroupOverride] = useState<string | undefined>(undefined)
  const [indicatorOverride, setIndicatorOverride] = useState<string | undefined>(undefined)
  // Admin-only, both default to off — an admin's default view matches a
  // regular user's exactly (hidden charts stay hidden, no controls shown).
  // Two distinct intents: "reveal" (read-only review of what's hidden) vs
  // "edit" (add Hide/Show buttons to curate). Edit implies reveal — you can't
  // usefully un-hide a chart you can't see — but reveal alone stays read-only.
  const [showHidden, setShowHidden] = useState(false)
  const [editVisibility, setEditVisibility] = useState(false)
  const revealHidden = showHidden || editVisibility

  const country = countryOverride ?? search.country ?? countries[0] ?? ''

  // Country years still drive the "By Country" chart's year axis, but the
  // group/indicator picker below is catalog-wide (dim_kpi), not scoped to this
  // country or any particular year — see useKpiReportAllGroups/Indicators.
  const { data: years } = useKpiReportYears(country || undefined)

  const { data: groups } = useKpiReportAllGroups()
  const group = groupOverride ?? search.group ?? groups?.[0] ?? ''

  const { data: indicators, isPending: indicatorsPending } = useKpiReportAllIndicators(group || undefined)
  const indicator = indicatorOverride ?? search.indicator ?? indicators?.[0]?.indicator

  function updateSearch(next: Partial<{ country: string; group: string; indicator: string }>) {
    void navigate({
      search: (prev) => ({ ...(prev as Record<string, unknown>), ...next }) as never,
      replace: true,
    })
  }

  // ── By Country: full trend per disaggregation, this country only ──
  const { data: countryTrendRows } = useKpiReportIndicatorTrend(
    mode === 'country' ? country || undefined : undefined,
    group || undefined,
    mode === 'country' ? indicator : undefined,
  )
  const countryYears = useMemo(() => [...(years ?? [])].sort((a, b) => a - b), [years])
  const countrySeriesAll = useMemo(() => {
    const map = new Map<string, {
      label: string
      valueType: string | null
      values: Record<number, string>
      isVisible: boolean
      rawLevelOne: string | null
      rawLevelTwo: string | null
    }>()
    ;(countryTrendRows ?? []).forEach((r) => {
      if (r.value == null) return
      const key = trendKey(r.disaggregation_level_one, r.disaggregation_level_two)
      if (!map.has(key)) {
        map.set(key, {
          label: disaggregationLabel(r.disaggregation_level_one, r.disaggregation_level_two),
          valueType: r.value_type,
          values: {},
          isVisible: r.is_visible,
          rawLevelOne: r.disaggregation_level_one,
          rawLevelTwo: r.disaggregation_level_two,
        })
      }
      map.get(key)!.values[r.year] = r.value
    })
    return [...map.values()]
  }, [countryTrendRows])
  const countrySeries = useMemo(
    () => (isAdmin && revealHidden ? countrySeriesAll : countrySeriesAll.filter((s) => s.isVisible)),
    [countrySeriesAll, isAdmin, revealHidden],
  )

  // ── By Indicator: small multiples per country, one section per disaggregation ──
  const { data: allCountryRows } = useKpiReportIndicatorTrendAllCountries(
    mode === 'indicator' ? group || undefined : undefined,
    mode === 'indicator' ? indicator : undefined,
  )
  const indicatorSectionsAll = useMemo(() => {
    const sections = new Map<string, {
      label: string
      valueType: string | null
      byCountry: Map<string, Record<number, string>>
      allYears: Set<number>
      isVisible: boolean
      rawLevelOne: string | null
      rawLevelTwo: string | null
    }>()
    ;(allCountryRows ?? []).forEach((r) => {
      if (r.value == null) return
      const key = trendKey(r.disaggregation_level_one, r.disaggregation_level_two)
      if (!sections.has(key)) {
        sections.set(key, {
          label: disaggregationLabel(r.disaggregation_level_one, r.disaggregation_level_two),
          valueType: r.value_type,
          byCountry: new Map(),
          allYears: new Set(),
          isVisible: r.is_visible,
          rawLevelOne: r.disaggregation_level_one,
          rawLevelTwo: r.disaggregation_level_two,
        })
      }
      const section = sections.get(key)!
      if (!section.byCountry.has(r.country)) section.byCountry.set(r.country, {})
      section.byCountry.get(r.country)![r.year] = r.value
      section.allYears.add(r.year)
    })
    return [...sections.values()].map((s) => ({
      label: s.label,
      valueType: s.valueType,
      years: [...s.allYears].sort((a, b) => a - b),
      countries: [...s.byCountry.keys()].sort().map((c) => ({ country: c, values: s.byCountry.get(c)! })),
      isVisible: s.isVisible,
      rawLevelOne: s.rawLevelOne,
      rawLevelTwo: s.rawLevelTwo,
    }))
  }, [allCountryRows])
  const indicatorSections = useMemo(
    () => (isAdmin && revealHidden ? indicatorSectionsAll : indicatorSectionsAll.filter((s) => s.isVisible)),
    [indicatorSectionsAll, isAdmin, revealHidden],
  )
  const hiddenCount = useMemo(
    () =>
      (mode === 'country' ? countrySeriesAll : indicatorSectionsAll).filter((s) => !s.isVisible).length,
    [mode, countrySeriesAll, indicatorSectionsAll],
  )

  return (
    <>
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', flexWrap: 'wrap', gap: 8 }}>
        <div className="admin-tabs" role="group" aria-label="View mode">
          <button
            type="button"
            className={`admin-tab${mode === 'country' ? ' admin-tab--active' : ''}`}
            style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}
            onClick={() => setMode('country')}
          >
            <svg width="14" height="14" viewBox="0 0 20 20" fill="none" aria-hidden="true" style={{ flexShrink: 0 }}>
              <circle cx="10" cy="10" r="8" stroke="currentColor" strokeWidth="1.7" />
              <ellipse cx="10" cy="10" rx="3.5" ry="8" stroke="currentColor" strokeWidth="1.7" />
              <path d="M2 10h16" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
            </svg>
            By Country
          </button>
          <button
            type="button"
            className={`admin-tab${mode === 'indicator' ? ' admin-tab--active' : ''}`}
            style={{ display: 'inline-flex', alignItems: 'center', gap: 6 }}
            onClick={() => setMode('indicator')}
          >
            <svg width="14" height="14" viewBox="0 0 20 20" fill="none" aria-hidden="true" style={{ flexShrink: 0 }}>
              <path d="M3 16l4.5-6 3.5 3 6-8" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
              <path d="M13.5 5h3.5v3.5" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
            </svg>
            By Indicator
          </button>
        </div>

        {isAdmin && (
          <div style={{ display: 'flex', alignItems: 'center', gap: 16, flexWrap: 'wrap', paddingRight: 16 }}>
            <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: '0.85rem', color: 'var(--text-mid)' }}>
              <input
                type="checkbox"
                checked={revealHidden}
                disabled={editVisibility}
                onChange={(e) => setShowHidden(e.target.checked)}
              />
              Show hidden charts{hiddenCount > 0 ? ` — ${hiddenCount} hidden` : ''}
            </label>
            <label style={{ display: 'flex', alignItems: 'center', gap: 6, fontSize: '0.85rem', color: 'var(--text-mid)' }}>
              <input type="checkbox" checked={editVisibility} onChange={(e) => setEditVisibility(e.target.checked)} />
              Edit chart visibility
            </label>
          </div>
        )}
      </div>

      {mode === 'country' && (
        <FilterSection>
          <div className="filter-bar-item">
            <label className="filter-bar-label">
              <svg width="14" height="14" viewBox="0 0 20 20" fill="none" aria-hidden="true">
                <circle cx="10" cy="10" r="8" stroke="currentColor" strokeWidth="1.7" />
                <ellipse cx="10" cy="10" rx="3.5" ry="8" stroke="currentColor" strokeWidth="1.7" />
                <path d="M2 10h16" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
              </svg>
              Country
            </label>
            <SelectDropdown
              options={countries}
              value={country}
              placeholder="Select Country"
              onChange={(next) => {
                setCountryOverride(next)
                setGroupOverride(undefined)
                setIndicatorOverride(undefined)
                updateSearch({ country: next, group: undefined, indicator: undefined })
              }}
            />
          </div>
        </FilterSection>
      )}

      <div className="body-layout">
        <div className="main-content">
          {meta && countries.length === 0 && (
            <div className="admin-empty" style={{ padding: '48px 0', textAlign: 'center' }}>
              You have not been assigned access to any country's data. Contact an administrator.
            </div>
          )}

          {!!groups?.length && (
            <div className="admin-tabs">
              {groups.map((g) => (
                <button
                  key={g}
                  type="button"
                  className={`admin-tab${g === group ? ' admin-tab--active' : ''}`}
                  onClick={() => {
                    setGroupOverride(g)
                    setIndicatorOverride(undefined)
                    updateSearch({ group: g, indicator: undefined })
                  }}
                >
                  {g}
                </button>
              ))}
            </div>
          )}

          {indicatorsPending ? (
            <p style={{ color: 'var(--text-mid)' }}>Loading…</p>
          ) : !indicators?.length ? (
            <p style={{ color: 'var(--text-mid)' }}>No indicators found for this group.</p>
          ) : (
            <div style={{ marginBottom: 16, maxWidth: 720 }}>
              <SelectDropdown
                options={indicators.map((ind) => indicatorLabel(ind))}
                value={indicator ? (indicators.find((i) => i.indicator === indicator) ? indicatorLabel(indicators.find((i) => i.indicator === indicator)!) : '') : ''}
                placeholder="Select Indicator"
                onChange={(label) => {
                  const match = indicators.find((ind) => indicatorLabel(ind) === label)
                  if (!match) return
                  setIndicatorOverride(match.indicator)
                  updateSearch({ indicator: match.indicator })
                }}
              />
            </div>
          )}

          {!indicator ? (
            <div className="chart-card chart-card--empty">Select an indicator above to see its trend.</div>
          ) : mode === 'country' ? (
            !countrySeries.length ? (
              <div className="chart-card chart-card--empty">No ANNUAL/DETAIL history for this indicator in {country}.</div>
            ) : (
              <div className="chart-card-grid">
                {countrySeries.map((s) => (
                  <FullTrendChart
                    key={s.label}
                    label={s.label}
                    years={countryYears}
                    values={s.values}
                    valueType={s.valueType}
                    isHidden={isAdmin && revealHidden ? !s.isVisible : undefined}
                    onToggleVisibility={
                      isAdmin && editVisibility
                        ? () =>
                            setChartVisibility.mutate({
                              chartKey: kpiTrendChartKey(group, indicator, s.rawLevelOne, s.rawLevelTwo),
                              isVisible: !s.isVisible,
                              kpiGroup: group,
                              indicator,
                            })
                        : undefined
                    }
                  />
                ))}
              </div>
            )
          ) : !indicatorSections.length ? (
            <div className="chart-card chart-card--empty">No ANNUAL/DETAIL history for this indicator across countries.</div>
          ) : (
            <>
              <p className="method-note">
                All countries share one axis, so bars/lines are directly comparable in magnitude. A country with only a couple of years on file is shown honestly as a short line, not padded or hidden.
              </p>
              <div className="chart-card-grid">
                {indicatorSections.map((section) => (
                  <div key={section.label} className={isAdmin && revealHidden && !section.isVisible ? 'chart-card--hidden' : undefined}>
                    <div className="chart-title" style={{ marginBottom: 8, display: 'flex', alignItems: 'center', gap: 8 }}>
                      {section.label}
                      {isAdmin && editVisibility && (
                        <button
                          type="button"
                          className="admin-btn admin-btn--secondary"
                          style={{ marginLeft: 'auto' }}
                          onClick={() =>
                            setChartVisibility.mutate({
                              chartKey: kpiTrendChartKey(group, indicator, section.rawLevelOne, section.rawLevelTwo),
                              isVisible: !section.isVisible,
                              kpiGroup: group,
                              indicator,
                            })
                          }
                        >
                          {section.isVisible ? 'Hide' : 'Show'}
                        </button>
                      )}
                    </div>
                    <CombinedTrendChart countries={section.countries} years={section.years} valueType={section.valueType} />
                  </div>
                ))}
              </div>
            </>
          )}
        </div>
      </div>
    </>
  )
}
