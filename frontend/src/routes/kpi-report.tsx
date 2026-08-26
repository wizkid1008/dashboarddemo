import { useMemo, useState } from 'react'
import { useNavigate, useSearch } from '@tanstack/react-router'
import { FilterSection } from '@/components/FilterSection'
import { SelectDropdown } from '@/components/SelectDropdown'
import { useDashboardMeta } from '@/queries/useDashboardMeta'
import { useAuth } from '@/contexts/AuthContext'
import {
  useKpiReportYears,
  useKpiReportGroups,
  useKpiReportIndicators,
  useKpiReportIndicatorDetail,
  useKpiReportIndicatorTrend,
  type KpiReportIndicator,
} from '@/features/kpi-report/queries'
import { formatKpiValue, trendKey, linreg, trendPoints, trendSegments } from '@/features/kpi-report/trend-utils'

// Only ANNUAL/DETAIL values are independent per-year measurements — every
// year is an upload snapshot, so a gap here means no data was submitted that
// year, not zero. Segments break at gaps instead of interpolating through them.
function TrendSparkline({ years, values }: { years: number[]; values: Record<number, string> }) {
  const w = 130, h = 28, pad = 4

  const points = trendPoints(years, values)
  if (!points.length) return <span className="kpi-trend-empty">—</span>

  const vals = points.map((p) => p.value)
  const min = Math.min(...vals)
  const max = Math.max(...vals)
  const range = (max - min) || 1
  const yearMin = years[0]
  const yearMax = years[years.length - 1]
  const xStep = yearMax > yearMin ? (w - pad * 2) / (yearMax - yearMin) : 0
  const xOf = (year: number) => pad + (year - yearMin) * xStep
  const yOf = (v: number) => pad + (1 - (v - min) / range) * (h - pad * 2)

  const segments = trendSegments(years, values)

  let trendPath: string | null = null
  if (points.length >= 2) {
    const { slope, intercept } = linreg(points)
    const firstYear = points[0].year
    const lastYear = points[points.length - 1].year
    const y1 = intercept + slope * firstYear
    const y2 = intercept + slope * lastYear
    trendPath = `M${xOf(firstYear).toFixed(1)},${yOf(y1).toFixed(1)} L${xOf(lastYear).toFixed(1)},${yOf(y2).toFixed(1)}`
  }

  return (
    <span className="kpi-trend-spark">
      <svg width="100%" viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="none" style={{ display: 'block' }}>
        {trendPath && <path d={trendPath} className="kpi-trend-dash" />}
        {segments.map((seg, si) => (
          <g key={si}>
            <path
              d={seg.map((p, i) => `${i === 0 ? 'M' : 'L'}${xOf(p.year).toFixed(1)},${yOf(p.value).toFixed(1)}`).join(' ')}
              className="kpi-trend-line"
            />
            {seg.map((p) => (
              <circle key={p.year} cx={xOf(p.year)} cy={yOf(p.value)} r={2.4} className="kpi-trend-dot" />
            ))}
          </g>
        ))}
      </svg>
    </span>
  )
}

export function KpiReportPage() {
  const { hasPermission, permissionsLoaded } = useAuth()
  if (!permissionsLoaded) {
    return <div className="body-layout"><div className="main-content"><p style={{ padding: '20px 0', color: 'var(--text-mid)' }}>Loading…</p></div></div>
  }
  if (!hasPermission('page:kpi-report')) {
    return (
      <div className="body-layout"><div className="main-content">
        <div style={{ padding: '40px 0', textAlign: 'center' }}>
          <h2 style={{ fontWeight: 600, marginBottom: 8 }}>Access Denied</h2>
          <p style={{ color: 'var(--text-mid)' }}>You do not have permission to view this page.</p>
        </div>
      </div></div>
    )
  }
  return <KpiReportContent />
}

function KpiReportContent() {
  const navigate = useNavigate()
  const search = useSearch({ strict: false }) as { country?: string; year?: number; group?: string }

  const { data: meta } = useDashboardMeta()
  const countries = useMemo(() => (meta?.countries ?? []).filter((c) => c !== 'International'), [meta])

  // Each "override" is only ever set by an explicit user selection; when unset,
  // the value falls back to the URL search param, then to the first available
  // option once its list has loaded — all derived at render time, no effects.
  const [countryOverride, setCountryOverride] = useState<string | undefined>(undefined)
  const [yearOverride, setYearOverride] = useState<number | undefined>(undefined)
  const [groupOverride, setGroupOverride] = useState<string | undefined>(undefined)
  const [expanded, setExpanded] = useState<string | null>(null)

  const country = countryOverride ?? search.country ?? countries[0] ?? ''

  const { data: years } = useKpiReportYears(country || undefined)
  const yearCandidate = yearOverride ?? search.year
  const year = yearCandidate != null && years?.includes(yearCandidate) ? yearCandidate : years?.[0]

  const { data: groups } = useKpiReportGroups(country || undefined, year)
  const groupCandidate = groupOverride ?? search.group
  const group = groupCandidate != null && groups?.includes(groupCandidate) ? groupCandidate : (groups?.[0] ?? '')

  const { data: indicators, isPending: indicatorsPending } = useKpiReportIndicators(
    country || undefined,
    year,
    group || undefined,
  )

  // kpi_report_years returns years newest-first (so the Year select defaults to
  // the latest year); the trend sparkline's x-axis needs them oldest-first, and
  // capped at the selected year — the row shows that year's value, so the trend
  // should end there too rather than running past it into later snapshots.
  const trendYears = useMemo(
    () => [...(years ?? [])].filter((y) => year == null || y <= year).sort((a, b) => a - b),
    [years, year],
  )

  function updateSearch(next: Partial<{ country: string; year: number; group: string }>) {
    void navigate({
      search: (prev) => ({ ...(prev as Record<string, unknown>), ...next }) as never,
      replace: true,
    })
  }

  return (
    <>
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
              setYearOverride(undefined)
              setGroupOverride(undefined)
              setExpanded(null)
              updateSearch({ country: next, year: undefined, group: undefined })
            }}
          />
        </div>

        <div className="filter-bar-item">
          <label className="filter-bar-label">
            <svg width="14" height="14" viewBox="0 0 20 20" fill="none" aria-hidden="true">
              <rect x="2" y="4" width="16" height="14" rx="2" stroke="currentColor" strokeWidth="1.7" />
              <path d="M6 2v4M14 2v4M2 9h16" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
            </svg>
            Year
          </label>
          <SelectDropdown
            options={(years ?? []).map(String)}
            value={year != null ? String(year) : ''}
            placeholder="Select Year"
            disabled={!years?.length}
            onChange={(next) => {
              const y = Number(next)
              setYearOverride(y)
              setGroupOverride(undefined)
              setExpanded(null)
              updateSearch({ year: y, group: undefined })
            }}
          />
        </div>
      </FilterSection>

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
                    setExpanded(null)
                    updateSearch({ group: g })
                  }}
                >
                  {g}
                </button>
              ))}
            </div>
          )}

          {!country || !year ? (
            <p style={{ color: 'var(--text-mid)' }}>Select a country and year to see KPIs.</p>
          ) : indicatorsPending ? (
            <p style={{ color: 'var(--text-mid)' }}>Loading…</p>
          ) : !indicators?.length ? (
            <p style={{ color: 'var(--text-mid)' }}>No KPIs found for {country}, {year}.</p>
          ) : (
            <div className="kpi-report-list">
              {indicators.map((ind) => (
                <KpiReportIndicatorRow
                  key={ind.indicator}
                  indicator={ind}
                  open={expanded === ind.indicator}
                  onToggle={() => setExpanded((cur) => (cur === ind.indicator ? null : ind.indicator))}
                  country={country}
                  year={year}
                  group={group}
                  years={trendYears}
                />
              ))}
            </div>
          )}
        </div>
      </div>
    </>
  )
}

function KpiReportIndicatorRow({
  indicator,
  open,
  onToggle,
  country,
  year,
  group,
  years,
}: {
  indicator: KpiReportIndicator
  open: boolean
  onToggle: () => void
  country: string
  year: number
  group: string
  years: number[]
}) {
  const { data: rows, isPending } = useKpiReportIndicatorDetail(
    country,
    year,
    group,
    open ? indicator.indicator : undefined,
  )
  const { data: trendRows } = useKpiReportIndicatorTrend(
    country,
    group,
    open ? indicator.indicator : undefined,
  )

  const trendByKey = useMemo(() => {
    const map: Record<string, Record<number, string>> = {}
    ;(trendRows ?? []).forEach((r) => {
      if (r.value == null) return
      const key = trendKey(r.disaggregation_level_one, r.disaggregation_level_two)
      if (!map[key]) map[key] = {}
      map[key][r.year] = r.value
    })
    return map
  }, [trendRows])

  return (
    <div className="kpi-report-item">
      <button
        type="button"
        className={`kpi-report-row${open ? ' kpi-report-row--open' : ''}`}
        onClick={onToggle}
      >
        <span className="kpi-report-caret">▸</span>
        {indicator.source_kpi_id && (
          <span className="kpi-report-kpi-badge">{indicator.source_kpi_id}</span>
        )}
        <span className="kpi-report-name">{indicator.indicator}</span>
      </button>

      {open && (
        <div className="kpi-report-detail">
          {!isPending && rows?.[0]?.definition && (
            <p className="kpi-report-definition">{rows[0].definition}</p>
          )}
          {isPending ? (
            <p className="kpi-report-muted-note">Loading…</p>
          ) : !rows?.length ? (
            <p className="kpi-report-muted-note">No disaggregated rows for this indicator.</p>
          ) : (
            rows.map((r, i) => {
              // disaggregation_level_two is sometimes literally "0" as a placeholder
              // for "no second disaggregation" — treat that the same as absent.
              const hasLevelTwo = !!r.disaggregation_level_two && r.disaggregation_level_two !== '0'
              const label = hasLevelTwo
                ? `${r.disaggregation_level_one ?? '—'} — ${r.disaggregation_level_two}`
                : (r.disaggregation_level_one ?? '—')
              const { text, muted } = formatKpiValue(r.value_type, r.value)
              const key = trendKey(r.disaggregation_level_one, r.disaggregation_level_two)
              return (
                <div className="kpi-report-detail-row" key={i}>
                  <span>{label}</span>
                  <TrendSparkline years={years} values={trendByKey[key] ?? {}} />
                  <span className={`kpi-report-val${muted ? ' kpi-report-val--muted' : ''}`}>{text}</span>
                </div>
              )
            })
          )}
        </div>
      )}
    </div>
  )
}
