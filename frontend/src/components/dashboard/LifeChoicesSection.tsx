import type { SectionProps } from '@/components/dashboard/DashboardCards'
import { useDashletData } from '@/queries/useDashletData'
import { DashletCard, collectElements } from '@/components/dashboard/DashletCard'

// Elements: 89=married by 18, 90=birth by 18
const MARRIED_BY_18_EL = 89
const BIRTH_BY_18_EL = 90

// Derived, so adding a card can't leave an element out of the fetch.
const ALL_ELEMENTS = collectElements(MARRIED_BY_18_EL, BIRTH_BY_18_EL)

// These two KPIs are uploaded later than the rest, so an empty card here normally means
// "not in yet" rather than "no such data" -- worded accordingly instead of the shared NoData.
const NotUploaded = (
  <div className="lg-stat-na" style={{ padding: '40px 0', textAlign: 'center' }}>Data not yet uploaded</div>
)

export function LifeChoicesSection({ countries, startYear, endYear, period }: SectionProps) {
  const { data: rows = [] } = useDashletData(ALL_ELEMENTS, startYear, endYear)

  const shared = {
    period,
    countries,
    rows,
    height: 220,
    pct: true,
    showTargets: false,
    showBadge: 'whenData' as const,
    showUpdateBadge: false,
    emptyState: NotUploaded,
  }

  return (
    <div className="er-grid">
      <DashletCard
        {...shared}
        permissionKey="dashlet:life_choices:married_by_18"
        title="Young Women Married by Age 18 (KPI 2.14)"
        kpiId="2.14"
        elements={MARRIED_BY_18_EL}
        seriesLabel="Married by 18"
      />

      <DashletCard
        {...shared}
        permissionKey="dashlet:life_choices:birth_by_18"
        title="Young Women Giving Birth / CAMA Marriage &amp; Birth Rates (KPI 2.15)"
        kpiId="2.15"
        elements={BIRTH_BY_18_EL}
        seriesLabel="KPI 2.15"
      />
    </div>
  )
}
