import { useMemo, useState } from 'react'
import { StatCard } from '@/components/dashboard/DashboardCards'
import type { SectionProps } from '@/components/dashboard/DashboardCards'
import { ToggleGroup } from '@/components/dashboard/ToggleGroup'
import { MAP_LEVEL_COLORS } from '@/data/staticData'
import { parseKpiValue } from '@/queries/useObservedKpi'
import type { DashboardData } from '@/types/dashboard'
import { LG_BUR_LABEL } from '@/components/dashboard/kpiLabels'
import type { LgBurType } from '@/components/dashboard/kpiLabels'
import { useDashletData, getDashletRows, sumDashletByCountry } from '@/queries/useDashletData'
import {
  DashletCard,
  collectElements,
  type DashletElementMap,
  type DashletSeriesSpec,
} from '@/components/dashboard/DashletCard'

// LG total active: annual=21, newly=22, cum2030=23, cumall=24, cum2024=122 (kpi 1.9).
const LG_EL: DashletElementMap = { annual: 21, newly: 22, cum2030: 23, cumall: 24, cum2024: 122 }
// SLS children (kpi 1.3): girls annual=27, newly=28, cum2030=123; boys annual=29, newly=30, cum2030=124.
// 'Cumulative all-time' exists for kpi 1.3 but only as a combined (non-gender-split) total, which
// doesn't fit these two per-gender cards -- cumall repeats the annual id there. No 'since 2024'
// data exists for kpi 1.3 either.
const SLS_GIRLS_EL: DashletElementMap = { annual: 27, newly: 28, cum2030: 123, cumall: 27, cum2024: 27 }
const SLS_BOYS_EL:  DashletElementMap = { annual: 29, newly: 30, cum2030: 124, cumall: 29, cum2024: 29 }
// LG by training: SHF Agriculture=25, Govt=26 (always annual from mapping)
const TRAINING_SERIES: DashletSeriesSpec[] = [
  { label: 'SHF Agriculture Trained', elements: 25, color: MAP_LEVEL_COLORS[0] },
  { label: 'Gov Trained',    elements: 26, color: MAP_LEVEL_COLORS[3] },
]
const SLS_SERIES: DashletSeriesSpec[] = [
  { label: 'Girls', elements: SLS_GIRLS_EL, color: MAP_LEVEL_COLORS[0] },
  { label: 'Boys',  elements: SLS_BOYS_EL,  color: MAP_LEVEL_COLORS[3] },
]
// R3 (element 31) and the MBW divisors feed the stat strip, not a DashletCard.
const R3_EL = 31
const MBW_GIRLS_EL = 27
const LG_ANNUAL_EL = 21

// Cumulative all-time is a running total with no meaningful year bound, so it comes from its
// own unbounded fetch rather than the section's year-ranged one.
const CUMALL_ELEMENTS = [LG_EL.cumall]

// Derived, so adding a card can't leave an element out of the fetch -- minus the all-time
// element, which is fetched separately just below.
const ANNUAL_ELEMENTS = collectElements(
  LG_EL,
  SLS_GIRLS_EL,
  SLS_BOYS_EL,
  TRAINING_SERIES,
  R3_EL,
  MBW_GIRLS_EL,
  LG_ANNUAL_EL,
).filter(el => !CUMALL_ELEMENTS.includes(el))

export function LearnerGuideProgrammeSection({
  dashboardData,
  countries,
  startYear,
  endYear,
  period,
}: SectionProps & { dashboardData: DashboardData }) {
  const [mbwMode, setMbwMode] = useState<'perLG' | 'perSchool'>('perLG')
  const [lgBurType, setLgBurType] = useState<LgBurType>('annual')

  const isCumulativePeriod = period.type !== 'year'

  // Fetch year-ranged data (annual/newly/cum2030) and cumulative all-time separately.
  const { data: rows = [] }       = useDashletData(ANNUAL_ELEMENTS, startYear, endYear)
  const { data: cumAllRows = [] } = useDashletData(CUMALL_ELEMENTS, 0, 9999)

  // Merged unconditionally: every lookup filters by element id, so the all-time rows are inert
  // for the cards that never ask for element 24.
  const allRows = useMemo(() => [...rows, ...cumAllRows], [rows, cumAllRows])

  // R3: element 31 — LG reporting increased agency (avg % across countries)
  const r3Rows = getDashletRows(rows, R3_EL)
  const r3Display = useMemo(() => {
    const vals = r3Rows
      .filter(r => countries.includes(r.country))
      .map(r => parseKpiValue(r.value))
      .filter(v => v > 0)
    if (!vals.length) return 'Data Not Available'
    const avg = vals.reduce((s, v) => s + v, 0) / vals.length
    return (avg * 100).toFixed(1) + '%'
  }, [r3Rows, countries])

  // MBW: girls annually (element 27) / LG total annual (element 21) or school count
  const mbwGirlsTotal = useMemo(
    () => sumDashletByCountry(rows, MBW_GIRLS_EL, countries).reduce((s, v) => s + v, 0),
    [rows, countries],
  )
  const lgTotalAnnual = useMemo(
    () => sumDashletByCountry(rows, LG_ANNUAL_EL, countries).reduce((s, v) => s + v, 0),
    [rows, countries],
  )
  const schoolCount = useMemo(
    () => dashboardData.data
      .filter(r =>
        r.metric === 'Active Partner Schools' &&
        r.year >= startYear && r.year <= endYear &&
        countries.includes(r.country),
      )
      .reduce((s, r) => s + r.value, 0),
    [dashboardData, countries, startYear, endYear],
  )
  const mbwDisplay = useMemo(() => {
    const divisor = mbwMode === 'perLG' ? lgTotalAnnual : schoolCount
    if (!divisor || !mbwGirlsTotal) return 'N/A'
    return String(Math.round(mbwGirlsTotal / divisor))
  }, [mbwMode, lgTotalAnnual, schoolCount, mbwGirlsTotal])

  const shared = {
    period,
    countries,
    rows: allRows,
    toggle: lgBurType,
    height: 300,
    blankWhenZero: false,
  }

  return (
    <>
      <div className="lg-stat-strip">
        <StatCard title="Girls Reporting Increased Agency" value="Data Not Available" />
        <StatCard title="Learner Guides Reporting Increased Agency" value={r3Display} />
        <div className="lg-stat-card">
          <div className="lg-stat-title">
            Average number of children receiving My Better World annually.
          </div>
          <div style={{ display: 'flex', alignItems: 'center', gap: 14, marginTop: 6 }}>
            <span className="lg-stat-value">{mbwDisplay}</span>
            <ToggleGroup
              options={['perLG', 'perSchool'] as const}
              labels={{ perLG: 'per LG', perSchool: 'per School' }}
              value={mbwMode}
              onChange={setMbwMode}
              style={{ flexDirection: 'column', gap: 5, marginBottom: 0 }}
            />
          </div>
        </div>
      </div>

      <ToggleGroup options={['annual', 'newly'] as LgBurType[]} labels={LG_BUR_LABEL} value={lgBurType} onChange={setLgBurType} style={{ padding: '8px 0 12px' }} disabled={isCumulativePeriod} />

      <div className="er-grid">
        <DashletCard
          {...shared}
          permissionKey="dashlet:learner_guide:active_guides"
          title="Active Learner Guides"
          kpiId="1.9"
          elements={LG_EL}
          seriesLabel="Learner Guides"
        />

        <DashletCard
          {...shared}
          permissionKey="dashlet:learner_guide:guides_by_training"
          title="Active Learner Guides by Training"
          kpiId="1.9"
          series={TRAINING_SERIES}
          showLegend
          showTargets={false}
          showUpdateBadge={false}
        />

        {/* Targets stay on the Girls series alone (targetMode's 'first' default), as this
            card has always done -- there is no combined boys+girls target for KPI 1.3. */}
        <DashletCard
          {...shared}
          permissionKey="dashlet:learner_guide:children_sls"
          title="Children Receiving Social and Learning Support Including My Better World Sessions"
          kpiId="1.3"
          series={SLS_SERIES}
          showLegend
        />
      </div>
    </>
  )
}
