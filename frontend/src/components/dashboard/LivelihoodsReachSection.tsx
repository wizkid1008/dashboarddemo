import { useState } from 'react'
import type { SectionProps } from '@/components/dashboard/DashboardCards'
import { ToggleGroup } from '@/components/dashboard/ToggleGroup'
import { MAP_LEVEL_COLORS } from '@/data/staticData'
import { LR_BUR_LABEL, BS_BUR_LABEL } from '@/components/dashboard/kpiLabels'
import type { LrBurType, BsBurType } from '@/components/dashboard/kpiLabels'
import { useDashletData } from '@/queries/useDashletData'
import {
  DashletCard,
  collectElements,
  type DashletElementMap,
  type DashletSeriesSpec,
} from '@/components/dashboard/DashletCard'

// Elements:
// 41=Ag guides annual, 42=Ag guides newly, 111-113=Ag guides cumulative (2020/all-time/2024)
// 43=Biz guides annual, 44=Biz guides newly, 114-116=Biz guides cumulative (2020/all-time/2024)
// 45=Businesses (Ag) annual, 46=Businesses (Ag) cumulative since 2020, 117=cumulative since 2024
// 47=Businesses (Biz) annual, 48=Businesses (Biz) cumulative since 2020, 118=cumulative since 2024
// 49=Grants # annual, 50=Grants USD annual, 94=Grants # cum since 2024, 95=Grants USD cum since 2024
// 51=Kiva # annual, 52=RIF # annual, 53=Loans USD annual, 119-121=cumulative since 2020 (Kiva/RIF/USD)

// Active Enterprise Guides (kpi 2.2) -- confirmed via live query to have all 3 cumulative variants.
const AG_EL:  DashletElementMap = { annual: 41, newly: 42, cum2030: 111, cumall: 112, cum2024: 113 }
const BIZ_EL: DashletElementMap = { annual: 43, newly: 44, cum2030: 114, cumall: 115, cum2024: 116 }
// Businesses Supported (kpi 2.7) has Annual + Cumulative-since-2020 + Cumulative-since-2024, no
// all-time variant -- cumall repeats the annual id so resolveCumulativeElement correctly reports
// "no real data" for it. No 'newly' key: this KPI has no Newly-supported variant.
const BS_AG_EL:  DashletElementMap = { annual: 45, cum2030: 46, cumall: 45, cum2024: 117 }
const BS_BIZ_EL: DashletElementMap = { annual: 47, cum2030: 48, cumall: 47, cum2024: 118 }
// Business Grants (kpi 2.8a) has Annual + Cumulative-since-2024 only, confirmed for both the
// Count and USD variants -- new elements 94/95. No 2020/all-time data exists for this KPI.
const GRANTS_NUM_EL: DashletElementMap = { annual: 49, cum2030: 49, cumall: 49, cum2024: 94 }
const GRANTS_USD_EL: DashletElementMap = { annual: 50, cum2030: 50, cumall: 50, cum2024: 95 }
// Loans (kpi 2.8b) has Cumulative-since-2020 only, confirmed for all 3 value types -- no
// all-time or since-2024 variant exists.
const LOANS_KIVA_EL: DashletElementMap = { annual: 51, cum2030: 119, cumall: 51, cum2024: 51 }
const LOANS_RIF_EL:  DashletElementMap = { annual: 52, cum2030: 120, cumall: 52, cum2024: 52 }
const LOANS_USD_EL:  DashletElementMap = { annual: 53, cum2030: 121, cumall: 53, cum2024: 53 }

const EG_SERIES: DashletSeriesSpec[] = [
  { label: 'Agriculture Guides', elements: AG_EL,  color: MAP_LEVEL_COLORS[4] },
  { label: 'Business Guides',    elements: BIZ_EL, color: MAP_LEVEL_COLORS[1] },
]
const BS_SERIES: DashletSeriesSpec[] = [
  { label: 'Agriculture Guides', elements: BS_AG_EL,  color: MAP_LEVEL_COLORS[4] },
  { label: 'Business Guides',    elements: BS_BIZ_EL, color: MAP_LEVEL_COLORS[1] },
]
// Kiva and RIF are two elements summed into one "number of loans" series; the USD variant is a
// single element. Module constants so the toggle swaps a stable reference rather than rebuilding.
const LOANS_NUM_SERIES: DashletSeriesSpec[] = [
  { label: '# Loans', elements: [LOANS_KIVA_EL, LOANS_RIF_EL] },
]
const LOANS_USD_SERIES: DashletSeriesSpec[] = [
  { label: 'USD', elements: LOANS_USD_EL },
]

// Derived, so adding a card can't leave an element out of the fetch.
const ALL_ELEMENTS = collectElements(
  EG_SERIES,
  BS_SERIES,
  GRANTS_NUM_EL,
  GRANTS_USD_EL,
  LOANS_NUM_SERIES,
  LOANS_USD_SERIES,
)

const TOGGLE_STYLE = { padding: '6px 16px 4px', flexWrap: 'wrap' as const }
const NUM_VAL_LABELS = { num: 'Number', val: 'USD Value' }

export function LivelihoodsReachSection({ countries, startYear, endYear, period }: SectionProps) {
  const [burType, setBurType] = useState<LrBurType>('annual')
  const [bsMode, setBsMode] = useState<BsBurType>('annual')
  const [grantsValMode, setGrantsValMode] = useState<'num' | 'val'>('num')
  const [loansValMode, setLoansValMode] = useState<'num' | 'val'>('num')

  const isCumulativePeriod = period.type !== 'year'

  const { data: rows = [] } = useDashletData(ALL_ELEMENTS, startYear, endYear)

  const shared = { period, countries, rows }

  return (
    <>
      <div className="er-grid">
        {/* targetMode="all": the target is the combined Agriculture + Business figure. */}
        <DashletCard
          {...shared}
          permissionKey="dashlet:livelihoods_reach:enterprise_guides"
          title="Active Enterprise Guides (Business & Agriculture Guides)"
          kpiId="2.2"
          series={EG_SERIES}
          toggle={burType}
          showLegend
          targetMode="all"
          controls={
            <ToggleGroup
              options={['annual', 'newly'] as LrBurType[]}
              labels={LR_BUR_LABEL}
              value={burType}
              onChange={setBurType}
              style={TOGGLE_STYLE}
              disabled={isCumulativePeriod}
            />
          }
        />

        <DashletCard
          {...shared}
          permissionKey="dashlet:livelihoods_reach:businesses_supported"
          title="Businesses Supported by Enterprise Guides"
          kpiId="2.7"
          series={BS_SERIES}
          toggle={bsMode}
          showLegend
          showTargets={false}
          controls={
            <ToggleGroup
              options={['annual', 'cum2030'] as BsBurType[]}
              labels={BS_BUR_LABEL}
              value={bsMode}
              onChange={setBsMode}
              style={TOGGLE_STYLE}
              disabled={isCumulativePeriod}
            />
          }
        />
      </div>

      <div className="er-grid" style={{ marginTop: 20 }}>
        <DashletCard
          {...shared}
          permissionKey="dashlet:livelihoods_reach:business_grants"
          title="Business Grants Distributed"
          kpiId="2.8a"
          elements={grantsValMode === 'num' ? GRANTS_NUM_EL : GRANTS_USD_EL}
          seriesLabel={grantsValMode === 'num' ? '# Grants' : 'USD'}
          showTargets={false}
          controls={
            <ToggleGroup
              options={['num', 'val'] as const}
              labels={NUM_VAL_LABELS}
              value={grantsValMode}
              onChange={setGrantsValMode}
              style={TOGGLE_STYLE}
            />
          }
        />

        <DashletCard
          {...shared}
          permissionKey="dashlet:livelihoods_reach:loans"
          title="SHF Agriculture Kiva & RIF Loans Distributed"
          kpiId="2.8b"
          series={loansValMode === 'num' ? LOANS_NUM_SERIES : LOANS_USD_SERIES}
          showTargets={false}
          controls={
            <ToggleGroup
              options={['num', 'val'] as const}
              labels={NUM_VAL_LABELS}
              value={loansValMode}
              onChange={setLoansValMode}
              style={TOGGLE_STYLE}
            />
          }
        />
      </div>
    </>
  )
}
