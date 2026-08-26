import { useState } from 'react'
import type { SectionProps } from '@/components/dashboard/DashboardCards'
import { ToggleGroup } from '@/components/dashboard/ToggleGroup'
import { LT_BUR_LABEL } from '@/components/dashboard/kpiLabels'
import type { LtBurType } from '@/components/dashboard/kpiLabels'
import { useDashletData } from '@/queries/useDashletData'
import { DashletCard, collectElements, type DashletElementMap } from '@/components/dashboard/DashletCard'

// Elements: 32=CAMA members, 33=TG annual, 34=TG newly, 35=YW-TG annual, 36=YW-TG newly,
//           37=Tertiary annual, 38=Tertiary newly, 39=CAMA leadership, 102-110=cumulative variants
// (see 20260723020000_wire_remaining_cumulative_dashlets.sql for exact data availability per KPI)

// Support Farmers (2.1) has only one bare 'Cumulative' variant -- reused for both cum2030 and
// cumall since it's the same underlying running total; no cum2024 data exists. No 'newly'
// key: this card has no Newly-supported variant, so it stays on annual whatever the
// section toggle says.
const CAMA_EL:   DashletElementMap = { annual: 32, cum2030: 102, cumall: 103, cum2024: 32 }
// Support Farmers in Leadership Roles (2.13) has no cumulative data at all -- every variant repeats
// the annual id so resolveCumulativeElement correctly reports "no real data".
const LEADER_EL: DashletElementMap = { annual: 39, cum2030: 39, cumall: 39, cum2024: 39 }
const TG_EL:     DashletElementMap = { annual: 33, newly: 34, cum2030: 104, cumall: 105, cum2024: 106 }
// Youth Supported by Farmer Guides (2.3) and Young Women Supported by Farmer Guides (2.5)
// both have since-2020 + all-time only, no confirmed since-2024 data.
const YWTG_EL:   DashletElementMap = { annual: 35, newly: 36, cum2030: 107, cumall: 108, cum2024: 35 }
const TERT_EL:   DashletElementMap = { annual: 37, newly: 38, cum2030: 109, cumall: 110, cum2024: 37 }

// Derived, so adding a card can't leave an element out of the fetch.
const ALL_ELEMENTS = collectElements(CAMA_EL, LEADER_EL, TG_EL, YWTG_EL, TERT_EL)

export function LeadershipTertiarySection({ countries, startYear, endYear, period }: SectionProps) {
  const [burType, setBurType] = useState<LtBurType>('annual')

  const isCumulativePeriod = period.type !== 'year'

  const { data: rows = [] } = useDashletData(ALL_ELEMENTS, startYear, endYear)

  const shared = { period, countries, rows, toggle: burType, height: 220 }

  return (
    <>
      <ToggleGroup options={['annual', 'newly'] as LtBurType[]} labels={LT_BUR_LABEL} value={burType} onChange={setBurType} style={{ marginBottom: 16, flexWrap: 'wrap' }} disabled={isCumulativePeriod} />
      <div className="er-grid">
        <DashletCard
          {...shared}
          permissionKey="dashlet:leadership_tertiary:transition_guides"
          title="Farmer Guides"
          kpiId="2.2"
          elements={TG_EL}
          seriesLabel="Guides"
        />

        <DashletCard
          {...shared}
          permissionKey="dashlet:leadership_tertiary:cama_members"
          title="Number of Support Farmers"
          kpiId="2.1"
          elements={CAMA_EL}
          seriesLabel="Members"
        />

        <DashletCard
          {...shared}
          permissionKey="dashlet:leadership_tertiary:young_women_tg"
          title="Youth Supported by Farmer Guides"
          kpiId="2.3"
          elements={YWTG_EL}
          seriesLabel="Young Women"
          showTargets={false}
        />

        <DashletCard
          {...shared}
          permissionKey="dashlet:leadership_tertiary:women_tertiary"
          title="Young Women Supported by SHF Agriculture in Tertiary Education"
          kpiId="2.5"
          elements={TERT_EL}
          seriesLabel="Women"
          showTargets={false}
        />

        <DashletCard
          {...shared}
          permissionKey="dashlet:leadership_tertiary:cama_leadership"
          title="Support Farmers in Leadership Roles"
          kpiId="2.13"
          elements={LEADER_EL}
          seriesLabel="Members"
          showTargets={false}
        />
      </div>
    </>
  )
}
