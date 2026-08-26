import { useQuery } from '@tanstack/react-query'
import { fetchDashletData, type DashletDataRow } from '@/lib/warehouseClient'

export type { DashletDataRow }

export function useDashletData(elements: number[], startYear: number, endYear: number) {
  return useQuery({
    queryKey: ['dashlet-data', elements.slice().sort((a, b) => a - b), startYear, endYear],
    queryFn: () => fetchDashletData(elements, startYear, endYear),
    enabled: elements.length > 0,
    staleTime: 10 * 60 * 1000,
  })
}

/** All rows for a specific dashlet element */
export function getDashletRows(rows: DashletDataRow[], element: number): DashletDataRow[] {
  return rows.filter(r => r.dashlet_element === element)
}

/** Sum values per country for a single dashlet element */
export function sumDashletByCountry(
  rows: DashletDataRow[],
  element: number,
  countries: string[],
): number[] {
  const elRows = getDashletRows(rows, element)
  return countries.map(c =>
    elRows
      .filter(r => r.country === c)
      .reduce((s, r) => s + (parseFloat(r.value) || 0), 0),
  )
}

/**
 * Multi-series data grouped by data_element label, one series per unique label.
 * Used for dashlets that have multiple kpi_mapping rows per element (e.g. CAMA + Community Champions).
 */
export function getDashletSeries(
  rows: DashletDataRow[],
  element: number,
  countries: string[],
): Array<{ label: string; vals: number[] }> {
  const elRows = getDashletRows(rows, element)
  const labels = [...new Set(elRows.map(r => r.data_element))]
  return labels.map(label => ({
    label,
    vals: countries.map(c =>
      elRows
        .filter(r => r.country === c && r.data_element === label)
        .reduce((s, r) => s + (parseFloat(r.value) || 0), 0),
    ),
  }))
}

/**
 * "Update Q1 2026"-style label for a cumulative dashlet card, sourced from update_quarter +
 * year on the card's own resolved element(s) -- the value lives per fact row, not per page, so
 * each card shows its own upload quarter/year rather than one shared page-level value. The year
 * is included because a card whose KPI hasn't been re-uploaded this year still resolves to its
 * latest available year (e.g. 2025), and showing just the cadence ("Annual") without which year
 * it's from would read as if it were current. Pass every element that feeds the card (e.g.
 * Agriculture + Business Guides) to merge their quarters into one label -- if they resolved to
 * different years, both are shown, newest first. Returns null when no element is a real
 * cumulative one ('no-data'/null) or no row carries a quarter yet.
 */
export function updateQuarterLabel(
  rows: DashletDataRow[],
  elements: Array<number | 'no-data' | null>,
): string | null {
  const validElements = elements.filter((e): e is number => typeof e === 'number')
  if (!validElements.length) return null

  const entries = new Map<string, number>()
  for (const r of rows) {
    if (validElements.includes(r.dashlet_element) && r.update_quarter) {
      entries.set(`${r.update_quarter.trim()} ${r.year}`, r.year)
    }
  }
  if (!entries.size) return null
  const sorted = [...entries.entries()].sort((a, b) => b[1] - a[1]).map(([label]) => label)
  return `Update ${sorted.join(', ')}`
}
