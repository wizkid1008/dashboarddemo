import { useMemo } from 'react'
import { TableCard } from '@/components/dashboard/DashboardCards'
import type { SectionProps } from '@/components/dashboard/DashboardCards'
import { NoData } from '@/components/dashboard/NoData'
import { parseKpiValue } from '@/queries/useObservedKpi'
import { useAuth } from '@/contexts/AuthContext'
import { useDashletData, getDashletRows } from '@/queries/useDashletData'
import { DashletCard, collectElements } from '@/components/dashboard/DashletCard'

// Elements: 66=food consumption %, 67=increased yields %, 68=climate techniques avg
const FOOD_CONSUMPTION_EL = 66
const INCREASED_YIELDS_EL = 67
const CLIMATE_TECHNIQUES_EL = 68

// Derived, so adding a card can't leave an element out of the fetch. The two table elements
// are listed explicitly -- they feed the TableCards below, not a DashletCard.
const ALL_ELEMENTS = collectElements(
  FOOD_CONSUMPTION_EL,
  INCREASED_YIELDS_EL,
  CLIMATE_TECHNIQUES_EL,
)

export function AgricultureFoodSection({ countries, startYear, endYear, period }: SectionProps) {
  const { hasPermission } = useAuth()

  const { data: rows = [] } = useDashletData(ALL_ELEMENTS, startYear, endYear)

  // Element 67: increased yields % per country (single row, convert to %)
  const yieldRows = getDashletRows(rows, INCREASED_YIELDS_EL)
  const yieldsByCountry = useMemo(() =>
    Object.fromEntries(
      countries.map(c => {
        const row = yieldRows.find(r => r.country === c)
        const v = row ? parseKpiValue(row.value) : null
        return [c, v != null && !isNaN(v) && v > 0 ? v * 100 : null]
      }),
    ),
    [yieldRows, countries],
  )

  // Element 68: climate techniques avg per country
  const climateRows = getDashletRows(rows, CLIMATE_TECHNIQUES_EL)
  const climateByCountry = useMemo(() =>
    Object.fromEntries(
      countries.map(c => {
        const vals = climateRows
          .filter(r => r.country === c)
          .map(r => parseKpiValue(r.value))
          .filter(v => !isNaN(v))
        const avg = vals.length ? vals.reduce((s, v) => s + v, 0) / vals.length : null
        return [c, avg != null && avg > 0 ? avg : null]
      }),
    ),
    [climateRows, countries],
  )

  return (
    <div style={{ display: 'grid', gridTemplateColumns: '1fr 1fr', gap: 18 }}>
      <DashletCard
        period={period}
        countries={countries}
        rows={rows}
        permissionKey="dashlet:agriculture_food:food_consumption"
        title="Percentage of Female Entrepreneurs Reporting an Increased Household Consumption of Food Since Participating in SHF Agriculture's Enterprise Programme"
        kpiId="R4"
        elements={FOOD_CONSUMPTION_EL}
        seriesLabel="% Entrepreneurs"
        scale={100}
        pct
        intPct
        height={400}
        showBadge={false}
        showUpdateBadge={false}
        showTargets={false}
        blankWhenZero={false}
        style={{ gridRow: 'span 2' }}
      />

      {hasPermission('dashlet:agriculture_food:increased_yields') && (
        <TableCard title="Percentage of Female Agripreneurs Reporting Increased Yields Since Participating in the Agriculture Guide Programme" kpiId="R8" permissionKey="dashlet:agriculture_food:increased_yields">
          {Object.values(yieldsByCountry).every(v => v == null)
            ? <NoData />
            : (
              <table className="er-table">
                <thead><tr><th>Country</th><th>Value</th></tr></thead>
                <tbody>
                  {countries.map(c => {
                    const v = yieldsByCountry[c] ?? null
                    return (
                      <tr key={c}>
                        <td>{c}</td>
                        <td>{v != null ? Math.round(v) + '%' : <em>Not Available</em>}</td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            )}
        </TableCard>
      )}

      {hasPermission('dashlet:agriculture_food:climate_techniques') && (
        <TableCard title="Average Number of Climate-Smart Techniques Used by Those Receiving Support from an Agriculture Guide" kpiId="R7" permissionKey="dashlet:agriculture_food:climate_techniques">
          {Object.values(climateByCountry).every(v => v == null)
            ? <NoData />
            : (
              <table className="er-table">
                <thead><tr><th>Country</th><th>Indicator</th></tr></thead>
                <tbody>
                  {countries.map(c => {
                    const v = climateByCountry[c] ?? null
                    return (
                      <tr key={c}>
                        <td>{c}</td>
                        <td>{v != null ? v.toFixed(1) : <em>Not Available</em>}</td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            )}
        </TableCard>
      )}
    </div>
  )
}
