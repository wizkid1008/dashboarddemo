import { useMemo, useState } from 'react'
import { useNavigate, useSearch } from '@tanstack/react-router'
import { FilterSection } from '@/components/FilterSection'
import { SelectDropdown } from '@/components/SelectDropdown'
import { useAuth } from '@/contexts/AuthContext'
import { useDashboardMeta } from '@/queries/useDashboardMeta'
import { useSetKpiMilestoneChartVisibility } from '@/features/admin/queries'
import {
  useKpiMilestoneYears,
  useKpiMilestoneGroups,
  useKpiMilestoneIndicators,
  useKpiMilestoneReport,
} from '@/features/kpi-report/queries'
import type { KpiReportIndicator, KpiMilestoneReportRow } from '@/features/kpi-report/queries'
import { disaggregationLabel, formatKpiValue, kpiMilestoneChartKey } from '@/features/kpi-report/trend-utils'

function indicatorLabel(ind: KpiReportIndicator): string {
  return ind.source_kpi_id ? `${ind.source_kpi_id} — ${ind.indicator}` : ind.indicator
}

// Grouped bar chart, all countries, one disaggregation slide — matches the
// format of SHF Agriculture's own "Spotlight KPIs" deck: colored bar = actual, gray
// bar = IP milestone, direct value labels, honest "N/A" for a country with
// no milestone set (e.g. a newer market) rather than a phantom 0% target.
function MilestoneBarChart({
  label,
  rows,
  valueType,
  isHidden,
  onToggleVisibility,
}: {
  label: string
  rows: { country: string; actual: number | null; milestone: number | null }[]
  valueType: string | null
  isHidden?: boolean
  onToggleVisibility?: () => void
}) {
  const w = 640, h = 260, padL = 52, padR = 12, padT = 16, padB = 26

  const maxVal = Math.max(1, ...rows.flatMap((r) => [r.actual ?? 0, r.milestone ?? 0]))
  const niceMax = Math.ceil(maxVal / Math.pow(10, Math.floor(Math.log10(maxVal)))) * Math.pow(10, Math.floor(Math.log10(maxVal)))
  const yOf = (v: number) => padT + (1 - v / niceMax) * (h - padT - padB)
  const groupW = (w - padL - padR) / rows.length
  const barW = groupW * 0.32
  const ticks = [0, 0.25, 0.5, 0.75, 1].map((t) => Math.round(niceMax * t))

  return (
    <div className={`chart-card${isHidden ? ' chart-card--hidden' : ''}`}>
      <div className="chart-title" style={{ marginBottom: 8, display: 'flex', alignItems: 'center', gap: 8 }}>
        {label}
        {onToggleVisibility && (
          <button type="button" className="admin-btn admin-btn--secondary" style={{ marginLeft: 'auto' }} onClick={onToggleVisibility}>
            {isHidden ? 'Show' : 'Hide'}
          </button>
        )}
      </div>
      <svg width="100%" viewBox={`0 0 ${w} ${h}`} preserveAspectRatio="xMidYMid meet" style={{ display: 'block' }}>
        {ticks.map((t) => {
          const y = yOf(t)
          return (
            <g key={t}>
              <line x1={padL} y1={y} x2={w - padR} y2={y} className="grid-line" />
              <text x={padL - 6} y={y + 3} textAnchor="end" className="axis-label">{t.toLocaleString()}</text>
            </g>
          )
        })}
        {rows.map((r, i) => {
          const groupX = padL + i * groupW
          const aX = groupX + groupW * 0.14
          const mX = aX + barW + 4
          return (
            <g key={r.country}>
              {r.actual != null && (() => {
                const ay = yOf(r.actual)
                const { text } = formatKpiValue(valueType, String(r.actual))
                return (
                  <>
                    <rect x={aX} y={ay} width={barW} height={h - padB - ay} rx={2} fill="var(--purple)" />
                    <text x={aX + barW / 2} y={ay - 5} textAnchor="middle" className="milestone-bar-label" fill="var(--purple)">{text}</text>
                  </>
                )
              })()}
              {r.milestone != null ? (() => {
                const my = yOf(r.milestone)
                const { text } = formatKpiValue(valueType, String(r.milestone))
                return (
                  <>
                    <rect x={mX} y={my} width={barW} height={h - padB - my} rx={2} fill="var(--text-light)" />
                    <text x={mX + barW / 2} y={my - 5} textAnchor="middle" className="milestone-bar-label" fill="var(--text-light)">{text}</text>
                  </>
                )
              })() : (
                <text x={mX + barW / 2} y={h - padB - 6} textAnchor="middle" className="milestone-na-label">N/A</text>
              )}
              <text x={groupX + groupW / 2} y={h - 6} textAnchor="middle" className="axis-label">{r.country}</text>
            </g>
          )
        })}
      </svg>
      <div className="chart-legend">
        <span className="chart-legend-item"><span className="chart-legend-swatch" style={{ background: 'var(--purple)' }} /> Actual</span>
        <span className="chart-legend-item"><span className="chart-legend-swatch" style={{ background: 'var(--text-light)' }} /> IP Milestone</span>
      </div>
    </div>
  )
}

export function KpiMilestonesPage() {
  const { hasPermission, permissionsLoaded } = useAuth()
  if (!permissionsLoaded) {
    return <div className="body-layout"><div className="main-content"><p style={{ padding: '20px 0', color: 'var(--text-mid)' }}>Loading…</p></div></div>
  }
  if (!hasPermission('page:kpi-milestones')) {
    return (
      <div className="body-layout"><div className="main-content">
        <div style={{ padding: '40px 0', textAlign: 'center' }}>
          <h2 style={{ fontWeight: 600, marginBottom: 8 }}>Access Denied</h2>
          <p style={{ color: 'var(--text-mid)' }}>You do not have permission to view this page.</p>
        </div>
      </div></div>
    )
  }
  return <KpiMilestonesContent />
}

function KpiMilestonesContent() {
  const navigate = useNavigate()
  const search = useSearch({ strict: false }) as { year?: number; group?: string; indicator?: string }
  const { isAdmin } = useAuth()
  const { data: meta } = useDashboardMeta()
  const setChartVisibility = useSetKpiMilestoneChartVisibility()
  // Admin-only, both default to off — an admin's default view matches a
  // regular user's exactly (hidden charts stay hidden, no controls shown).
  const [showHidden, setShowHidden] = useState(false)
  const [editVisibility, setEditVisibility] = useState(false)
  const revealHidden = showHidden || editVisibility

  const { data: years } = useKpiMilestoneYears()
  const currentYear = new Date().getFullYear()
  const defaultYear = years?.includes(currentYear) ? currentYear : years?.[0]
  const year = search.year ?? defaultYear

  const { data: groups } = useKpiMilestoneGroups()
  const group = search.group ?? groups?.[0] ?? ''

  const { data: indicators, isPending: indicatorsPending } = useKpiMilestoneIndicators(group || undefined)
  const indicator = search.indicator ?? indicators?.[0]?.indicator

  const { data: reportRows, isPending: reportPending } = useKpiMilestoneReport(year, group || undefined, indicator)

  function updateSearch(next: Partial<{ year: number; group: string; indicator: string }>) {
    void navigate({
      search: (prev) => ({ ...(prev as Record<string, unknown>), ...next }) as never,
      replace: true,
    })
  }

  const sectionsAll = useMemo(() => {
    const map = new Map<string, {
      label: string
      valueType: string | null
      rows: KpiMilestoneReportRow[]
      isVisible: boolean
      rawLevelOne: string | null
      rawLevelTwo: string | null
    }>()
    ;(reportRows ?? []).forEach((r) => {
      const key = `${r.disaggregation_level_one ?? ''}|${r.disaggregation_level_two ?? ''}`
      if (!map.has(key)) {
        map.set(key, {
          label: disaggregationLabel(r.disaggregation_level_one, r.disaggregation_level_two),
          valueType: r.value_type,
          rows: [],
          isVisible: r.is_visible,
          rawLevelOne: r.disaggregation_level_one,
          rawLevelTwo: r.disaggregation_level_two,
        })
      }
      map.get(key)!.rows.push(r)
    })
    return [...map.values()].map((s) => ({
      label: s.label,
      valueType: s.valueType,
      isVisible: s.isVisible,
      rawLevelOne: s.rawLevelOne,
      rawLevelTwo: s.rawLevelTwo,
      rows: s.rows
        .slice()
        .sort((a, b) => a.country.localeCompare(b.country))
        .map((r) => ({ country: r.country, actual: r.actual_value, milestone: r.milestone_value })),
    }))
  }, [reportRows])
  const sections = useMemo(
    () => (isAdmin && revealHidden ? sectionsAll : sectionsAll.filter((s) => s.isVisible)),
    [sectionsAll, isAdmin, revealHidden],
  )
  const hiddenCount = useMemo(() => sectionsAll.filter((s) => !s.isVisible).length, [sectionsAll])

  return (
    <>
      {isAdmin && (
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'flex-end', gap: 16, flexWrap: 'wrap', paddingRight: 16 }}>
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

      <FilterSection>
        <div className="filter-bar-item">
          <label className="filter-bar-label">
            <svg width="14" height="14" viewBox="0 0 20 20" fill="none" aria-hidden="true">
              <rect x="3" y="4" width="14" height="13" rx="2" stroke="currentColor" strokeWidth="1.7" />
              <path d="M3 8h14M7 3v3M13 3v3" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
            </svg>
            Year
          </label>
          <SelectDropdown
            options={(years ?? []).map(String)}
            value={year != null ? String(year) : ''}
            placeholder="Select Year"
            onChange={(next) => updateSearch({ year: Number(next) })}
          />
        </div>
      </FilterSection>

      <div className="body-layout">
        <div className="main-content">
          {meta && meta.countries.length === 0 && (
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
                  onClick={() => updateSearch({ group: g, indicator: undefined })}
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
                  updateSearch({ indicator: match.indicator })
                }}
              />
            </div>
          )}

          {!indicator ? (
            <div className="chart-card chart-card--empty">Select an indicator above to see actual vs. milestone.</div>
          ) : reportPending ? (
            <p style={{ color: 'var(--text-mid)' }}>Loading…</p>
          ) : !sections.length ? (
            <div className="chart-card chart-card--empty">No milestone or actual data for this indicator in {year}.</div>
          ) : (
            <div className="chart-card-grid">
              {sections.map((s) => (
                <MilestoneBarChart
                  key={s.label}
                  label={s.label}
                  rows={s.rows}
                  valueType={s.valueType}
                  isHidden={isAdmin && revealHidden ? !s.isVisible : undefined}
                  onToggleVisibility={
                    isAdmin && editVisibility
                      ? () =>
                          setChartVisibility.mutate({
                            chartKey: kpiMilestoneChartKey(group, indicator, s.rawLevelOne, s.rawLevelTwo),
                            isVisible: !s.isVisible,
                            kpiGroup: group,
                            indicator,
                          })
                      : undefined
                  }
                />
              ))}
            </div>
          )}
        </div>
      </div>
    </>
  )
}
