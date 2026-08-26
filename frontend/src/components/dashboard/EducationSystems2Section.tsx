import { useMemo, useState } from 'react'
import { FlexChart } from '@/components/charts/FlexChart'
import { KpiInfoIcon } from '@/components/KpiInfoIcon'
import { DashletCommentIcon } from '@/components/DashletCommentIcon'
import type { SectionProps } from '@/components/dashboard/DashboardCards'
import { ToggleGroup } from '@/components/dashboard/ToggleGroup'
import { getCountryColor } from '@/data/staticData'
import { parseKpiValue } from '@/queries/useObservedKpi'
import { useAuth } from '@/contexts/AuthContext'
import { useDashletData, getDashletRows } from '@/queries/useDashletData'
import { DashletCard, collectElements, type DashletSeriesSpec } from '@/components/dashboard/DashletCard'

// Elements:
// 77/78/79 = community champion types (CDCs, SBCs, PSGs)
// 80 = MoU count
// 81 = children benefitting annual, 85 = children benefitting newly
// 82-84 = children subcategories annual (Primary SHFs/boys, Secondary SHFs/boys)
// 86-88 = children subcategories newly
const MOU_EL = 80
const CHAMP_ELEMENTS = [77, 78, 79]

// Children Benefitting is one series summed from four gender/level slices, and its Annual /
// Newly toggle swaps the whole set rather than resolving a period map. Both arrays are module
// constants so switching the toggle swaps a stable reference rather than rebuilding one.
// (confirmed against kpi_mapping — all four elements per mode carry one gender/level slice each)
const KIDS_ANNUAL_SERIES: DashletSeriesSpec[] = [{ label: 'Children', elements: [81, 82, 83, 84] }]
const KIDS_NEWLY_SERIES:  DashletSeriesSpec[] = [{ label: 'Children', elements: [85, 86, 87, 88] }]

// Derived, so adding a card can't leave an element out of the fetch.
const ALL_ELEMENTS = collectElements(
  MOU_EL,
  CHAMP_ELEMENTS,
  KIDS_ANNUAL_SERIES,
  KIDS_NEWLY_SERIES,
)

export function EducationSystems2Section({ countries, startYear, endYear, period }: SectionProps) {
  const [kidsMode, setKidsMode] = useState<'annual' | 'newly'>('annual')
  const { hasPermission } = useAuth()

  const { data: rows = [] } = useDashletData(ALL_ELEMENTS, startYear, endYear)

  const champTypeLabels = useMemo(() => {
    return CHAMP_ELEMENTS.map(el => {
      const r = getDashletRows(rows, el)[0]
      return r?.data_element ?? (el === 77 ? 'CDCs' : el === 78 ? 'SBCs' : 'PSGs')
    })
  }, [rows])

  const champByCountry = (country: string) =>
    CHAMP_ELEMENTS.map(el =>
      getDashletRows(rows, el)
        .filter(r => r.country === country)
        .reduce((s, r) => s + parseKpiValue(r.value), 0)
    )

  // Per-type country breakdown, transposed from champByCountry so each champion type can be
  // drawn as its own panel. Rendered as small multiples with independent scales rather than one
  // shared-axis stacked chart: CDCs total ~3k against SBCs' ~67k, so on a shared axis the CDC
  // bar was ~4% of chart height and its six country segments were a few pixels each -- unreadable,
  // and the datalabels inside it collided and got dropped. The three types are also counted at
  // different units (district committees vs schools vs parent groups), so their relative heights
  // were never a meaningful quantity to preserve.
  const champByType = useMemo(() => {
    const byCountry = countries.map(c => ({ country: c, values: champByCountry(c) }))
    return CHAMP_ELEMENTS.map((_, typeIndex) =>
      byCountry.map(({ country, values }) => ({ country, value: values[typeIndex] })),
    )
  }, [rows, countries])

  // 'Community Champions - CDCs' -> 'CDCs'; the card title already says Community Champions.
  const shortTypeLabel = (label: string) =>
    label.replace(/^Community Champions\s*[-–—]\s*/, '')

  const shared = { period, countries, rows, showTargets: false, showUpdateBadge: false }

  return (
    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 18 }}>
      <DashletCard
        {...shared}
        permissionKey="dashlet:education_systems_2:mou"
        title="Number of Memoranda of Understanding between Government Departments and SHF Agriculture"
        kpiId="P18"
        elements={MOU_EL}
        seriesLabel="MoUs"
        horizontal
        height={220}
        blankWhenZero={false}
        style={{ gridColumn: 1, gridRow: 1 }}
      />

      {/* Flex column so the three panels share the height of the two-row span, the way the
          single 440px chart used to fill it. */}
      {hasPermission('dashlet:education_systems_2:community_champions') && (
        <div className="er-card" style={{ gridColumn: 2, gridRow: '1 / 3', display: 'flex', flexDirection: 'column' }}>
          <div className="er-card-header">
            <span className="er-card-title-row">
              <span className="er-card-title">Number of Active Community Champions for SHF's Education</span>
              <KpiInfoIcon kpiId="P6" />
              <DashletCommentIcon permissionKey="dashlet:education_systems_2:community_champions" />
            </span>
          </div>
          <div style={{ padding: '12px 16px', display: 'flex', flexDirection: 'column', flex: 1, minHeight: 0 }}>
            {champByType.map((typeRows, typeIndex) => (
              <div
                key={CHAMP_ELEMENTS[typeIndex]}
                style={{
                  display: 'flex',
                  flexDirection: 'column',
                  flex: 1,
                  minHeight: 140,
                  marginBottom: typeIndex < champByType.length - 1 ? 10 : 0,
                }}
              >
                <div className="cc-panel-title">{shortTypeLabel(champTypeLabels[typeIndex] ?? '')}</div>
                <div className="cc-panel" style={{ flex: 1 }}>
                  {/* One bar per country, not one stacked bar per type: the countries are separate
                      quantities rather than parts of a whole, so segmenting a single bar made them
                      readable only by colour lookup. Country names now sit on the y-axis, which is
                      why these panels no longer share a colour legend. */}
                  <FlexChart
                    labels={typeRows.map(({ country }) => country)}
                    datasets={[{
                      label: shortTypeLabel(champTypeLabels[typeIndex] ?? ''),
                      data: typeRows.map(({ value }) => value),
                      color: typeRows.map(({ country }) => getCountryColor(country)),
                    }]}
                    horizontal
                  />
                </div>
              </div>
            ))}

            {/* Independent scales are the whole point of the split, but a reader scanning down
                would otherwise assume a shared axis and misread the bar lengths. */}
            <div className="cc-panel-note">Each panel is scaled to its own values — bar lengths are not comparable between panels.</div>
          </div>
        </div>
      )}

      <DashletCard
        {...shared}
        permissionKey="dashlet:education_systems_2:children_learning"
        title="Children Benefitting from Improved Learning Environment"
        kpiId="3.5"
        series={kidsMode === 'annual' ? KIDS_ANNUAL_SERIES : KIDS_NEWLY_SERIES}
        height={260}
        style={{ gridColumn: 1, gridRow: 2 }}
        controls={
          <ToggleGroup
            options={['annual', 'newly'] as const}
            labels={{ annual: 'Annual', newly: 'Newly Supported' }}
            value={kidsMode}
            onChange={setKidsMode}
            style={{ padding: '6px 16px 4px' }}
          />
        }
      />
    </div>
  )
}
