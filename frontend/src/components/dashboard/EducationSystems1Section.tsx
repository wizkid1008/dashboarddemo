import { useMemo } from 'react'
import { StatCard, fmt } from '@/components/dashboard/DashboardCards'
import type { SectionProps } from '@/components/dashboard/DashboardCards'
import { MAP_LEVEL_COLORS } from '@/data/staticData'
import { parseKpiValue, useObservedKpi } from '@/queries/useObservedKpi'
import { useDashletData, getDashletRows } from '@/queries/useDashletData'
import { DashletCard, collectElements, type DashletSeriesSpec } from '@/components/dashboard/DashletCard'

// Elements:
// 71=resources govt %, 72=districts SHF Agriculture, 73=districts govt,
// 74=national dropout rate, 75=schools SHF Agriculture, 76=schools govt
const GOVT_RESOURCE_EL = 71
const NATIONAL_DROPOUT_EL = 74

// Both cards stack a SHF Agriculture-delivered series on a government-delivered one, so each is two
// fixed elements rather than a period map -- KPIs 3.4 and 3.2 have no cumulative variants.
const DISTRICT_SERIES: DashletSeriesSpec[] = [
  { label: 'SHF Agriculture Partner', elements: 72, color: MAP_LEVEL_COLORS[0] },
  { label: 'Government',     elements: 73, color: MAP_LEVEL_COLORS[3] },
]
const SCHOOL_SERIES: DashletSeriesSpec[] = [
  { label: 'SHF Agriculture Supported',    elements: 75, color: MAP_LEVEL_COLORS[0] },
  { label: 'Government Delivery', elements: 76, color: MAP_LEVEL_COLORS[3] },
]

// Derived, so adding a card can't leave an element out of the fetch. The two stat-strip
// elements are listed explicitly -- they feed the strip above, not a DashletCard.
const ALL_ELEMENTS = collectElements(
  GOVT_RESOURCE_EL,
  NATIONAL_DROPOUT_EL,
  DISTRICT_SERIES,
  SCHOOL_SERIES,
)

export function EducationSystems1Section({ countries, startYear, endYear, period }: SectionProps) {
  const { data: rows = [] } = useDashletData(ALL_ELEMENTS, startYear, endYear)

  // Element 71: % govt resources (avg across countries)
  const res71 = getDashletRows(rows, GOVT_RESOURCE_EL)
    .filter(r => countries.includes(r.country))
    .map(r => parseKpiValue(r.value))
    .filter(v => !isNaN(v))
  const govtResourcePct = res71.length ? res71.reduce((s, v) => s + v, 0) / res71.length : null

  // Element 74: national dropout rate (avg across countries)
  const drop74 = getDashletRows(rows, NATIONAL_DROPOUT_EL)
    .filter(r => countries.includes(r.country))
    .map(r => parseKpiValue(r.value))
    .filter(v => !isNaN(v))
  const dropoutRate = drop74.length ? drop74.reduce((s, v) => s + v, 0) / drop74.length : null

  // Teacher mentors: P6 filtered for teacher/mentor disagg — no dedicated kpi_mapping element yet
  const { data: p6Rows = [] } = useObservedKpi('P6')
  const teacherMentors = useMemo(() => {
    const tmRows = p6Rows.filter(r =>
      countries.includes(r.country) &&
      Number(r.year) >= startYear && Number(r.year) <= endYear &&
      (r.disaggregation_level_one?.toLowerCase().includes('teacher') ||
       r.disaggregation_level_one?.toLowerCase().includes('mentor'))
    )
    const src = tmRows.length ? tmRows : p6Rows.filter(r =>
      countries.includes(r.country) && Number(r.year) >= startYear && Number(r.year) <= endYear
    )
    return src.reduce((s, r) => s + parseKpiValue(r.value), 0)
  }, [p6Rows, countries, startYear, endYear])

  const fmtPct = (v: number | null) => v == null ? 'N/A' : `${Math.round(v * 100)}%`

  const shared = { period, countries, rows, height: 220, showUpdateBadge: false }

  return (
    <>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(3,1fr)', gap: 12, marginBottom: 16 }}>
        <StatCard
          title="% of resources for the Learner Guide Programme contributed by government"
          value={fmtPct(govtResourcePct)}
        />
        <div className="lg-stat-card">
          <div className="lg-stat-title">National Level Dropout Rate for SHFs due to Early Marriage or Pregnancy</div>
          {dropoutRate != null
            ? <div className="lg-stat-value">{fmtPct(dropoutRate)}</div>
            : <div className="lg-stat-na">Data Not Available</div>}
        </div>
        <StatCard title="Community Champion Teacher Mentors" value={fmt(teacherMentors)} />
      </div>
      <div className="er-grid">
        <DashletCard
          {...shared}
          permissionKey="dashlet:education_systems_1:districts_with_lg"
          title="Number of Districts with Learner Guides"
          kpiId="3.4"
          series={DISTRICT_SERIES}
          showLegend
          stacked
          stackLabels
          showTargets={false}
        />

        {/* targetMode="all": the target line is the combined SHF Agriculture + Government figure,
            matching the stack rather than either segment alone. */}
        <DashletCard
          {...shared}
          permissionKey="dashlet:education_systems_1:schools_with_lg"
          title="Number of Schools with Learner Guides"
          kpiId="3.2"
          series={SCHOOL_SERIES}
          showLegend
          stacked
          stackLabels
          targetMode="all"
        />
      </div>
    </>
  )
}
