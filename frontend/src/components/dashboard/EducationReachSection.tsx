import { useState } from 'react'
import { MAP_LEVEL_COLORS } from '@/data/staticData'
import { useDashletData } from '@/queries/useDashletData'
import { ToggleGroup } from '@/components/dashboard/ToggleGroup'
import { BUR_LABELS, type BurType } from '@/components/dashboard/kpiLabels'
import type { SectionProps } from '@/components/dashboard/DashboardCards'
import { DashletCard, collectElements, type DashletElementMap } from '@/components/dashboard/DashletCard'

// Maps burType to dashlet_element for each dashlet group. cum2024 elements 91/92 (Bursaries/CAMA)
// and cum2030/cumall elements 96-101 (CAMA, Total SHFs, Total Boys) are confirmed via
// view_observed_kpi to have real cumulative data. P1 (Total SHFs/Boys) has no 'Cumulative since
// 2024' rows at all, so cum2024 stays mapped to the annual id there ('no-data' via
// resolveCumulativeElement) -- a genuine data gap, not unwired.
const BUR_EL:   DashletElementMap = { annual: 1, newly: 2, cum2030: 9,   cumall: 10,  cum2024: 91 }
const CAMA_EL:  DashletElementMap = { annual: 3, newly: 4, cum2030: 96,  cumall: 97,  cum2024: 92 }
const GIRLS_EL: DashletElementMap = { annual: 5, newly: 6, cum2030: 98,  cumall: 99,  cum2024: 5  }
const BOYS_EL:  DashletElementMap = { annual: 7, newly: 8, cum2030: 100, cumall: 101, cum2024: 7  }

// Derived, so adding a card can't leave an element out of the fetch.
const ALL_ELEMENTS = collectElements(BUR_EL, CAMA_EL, GIRLS_EL, BOYS_EL)

export function EducationReachSection({ countries, startYear, endYear, period }: SectionProps) {
  const [burType, setBurType] = useState<BurType>('newly')

  const { data: rows = [] } = useDashletData(ALL_ELEMENTS, startYear, endYear)

  const isCumulativePeriod = period.type !== 'year'

  // Only the Bursaries card labels its series by the resolved period rather than the toggle.
  const burLabel: string =
    period.type === 'cumulative2020'    ? BUR_LABELS.cum2030 :
    period.type === 'cumulativeAllTime' ? BUR_LABELS.cumall  :
    period.type === 'cumulative2024'    ? 'Since 2024'       :
    BUR_LABELS[burType]

  const shared = { period, countries, rows, toggle: burType }

  return (
    <div className="er-grid">
      <DashletCard
        {...shared}
        permissionKey="dashlet:education_reach:bursaries"
        title="SHFs Supported in School with Education Bursaries"
        kpiId="1.1"
        elements={BUR_EL}
        seriesLabel={burLabel}
        controls={
          <ToggleGroup
            options={['newly', 'annual'] as BurType[]}
            labels={BUR_LABELS}
            value={burType}
            onChange={setBurType}
            style={{ padding: '8px 16px 4px' }}
            disabled={isCumulativePeriod}
          />
        }
      />

      <DashletCard
        {...shared}
        permissionKey="dashlet:education_reach:cama_community"
        title="SHFs Supported in School by Support Farmers & Community Champions"
        kpiId="1.2a"
        elements={CAMA_EL}
        agg="series"
        showLegend
        seriesColors={[MAP_LEVEL_COLORS[0], MAP_LEVEL_COLORS[3]]}
      />

      <DashletCard
        {...shared}
        permissionKey="dashlet:education_reach:total_girls"
        title="Total SHFs Supported"
        kpiId="P1"
        elements={GIRLS_EL}
        seriesLabel="SHFs"
        horizontal
      />

      <DashletCard
        {...shared}
        permissionKey="dashlet:education_reach:total_boys"
        title="Total Boys Supported"
        kpiId="P1"
        elements={BOYS_EL}
        seriesLabel="Boys"
        horizontal
      />
    </div>
  )
}
