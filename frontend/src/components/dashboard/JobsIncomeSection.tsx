import type { SectionProps } from '@/components/dashboard/DashboardCards'
import { useDashletData } from '@/queries/useDashletData'
import { DashletCard, collectElements, type DashletElementMap } from '@/components/dashboard/DashletCard'

// Elements: 56=women livelihood %, 57=female entrepreneurs %, 58=jobs annual, 59=jobs cum since 2020,
//           60=new businesses annual, 61=new businesses cum since 2020, 93=new businesses cum since 2024
const WOMEN_LIVELIHOOD_EL = 56
const ENTREPRENEUR_INCOME_EL = 57

// Neither KPI has a "Newly supported" variant (no `newly` key) or an all-time cumulative row --
// cumall repeats the annual id so resolveCumulativeElement correctly reports "no real data" for
// it. Jobs Created (2.9) has no confirmed 'Cumulative since 2024' data either, so cum2024 repeats
// annual there too.
const JOBS_EL: DashletElementMap = { annual: 58, cum2030: 59, cumall: 58, cum2024: 58 }
const BIZ_EL:  DashletElementMap = { annual: 60, cum2030: 61, cumall: 60, cum2024: 93 }

// Derived, so adding a card can't leave an element out of the fetch.
const ALL_ELEMENTS = collectElements(WOMEN_LIVELIHOOD_EL, ENTREPRENEUR_INCOME_EL, JOBS_EL, BIZ_EL)

export function JobsIncomeSection({ countries, startYear, endYear, period }: SectionProps) {
  const { data: rows = [] } = useDashletData(ALL_ELEMENTS, startYear, endYear)

  const shared = { period, countries, rows }

  return (
    <>
      <div className="er-grid">
        {/* The two rate cards read a 0-1 ratio, so they scale to a percentage, show no total
            badge (a summed percentage is meaningless) and keep charting at zero rather than
            falling back to an empty state. */}
        <DashletCard
          {...shared}
          permissionKey="dashlet:jobs_income:women_livelihood"
          title="Women Progressing Towards a Secure Livelihood (Employment, Enterprise, Continuing Education) Following Transitions Programme"
          kpiId="2.4"
          elements={WOMEN_LIVELIHOOD_EL}
          seriesLabel="% Women"
          scale={100}
          pct
          intPct
          horizontal
          height={240}
          showBadge={false}
          showUpdateBadge={false}
          showTargets={false}
          blankWhenZero={false}
        />

        <DashletCard
          {...shared}
          permissionKey="dashlet:jobs_income:entrepreneurs_income"
          title="Female Entrepreneurs with Increased Incomes after Participating in SHF Agriculture's Enterprise Programme"
          kpiId="2.11"
          elements={ENTREPRENEUR_INCOME_EL}
          seriesLabel="% Entrepreneurs"
          scale={100}
          pct
          intPct
          height={220}
          showBadge={false}
          showUpdateBadge={false}
          showTargets={false}
          blankWhenZero={false}
        />
      </div>

      <div className="er-grid">
        <DashletCard
          {...shared}
          permissionKey="dashlet:jobs_income:jobs_created"
          title="Jobs Created through Enterprise Programme Including Self-Employment"
          kpiId="2.9"
          elements={JOBS_EL}
          seriesLabel="Jobs"
          height={220}
          showTargets={false}
          blankWhenZero={false}
        />

        <DashletCard
          {...shared}
          permissionKey="dashlet:jobs_income:new_businesses"
          title="New Businesses"
          kpiId="2.6"
          elements={BIZ_EL}
          seriesLabel="Businesses"
          height={220}
          blankWhenZero={false}
        />
      </div>
    </>
  )
}
