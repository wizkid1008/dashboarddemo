import type { DashboardData } from '@/types/dashboard'
import { D } from '@/data/kpi'
import type { StatisticDefinition } from '@/data/hierarchy'

// Represents what the year dropdown can resolve to.
export type Period =
  | { type: 'year'; year: number }
  | { type: 'cumulative2020'; latestYear: number }
  | { type: 'cumulative2024'; latestYear: number }
  | { type: 'cumulativeAllTime'; latestYear: number }

// Sentinel strings returned by resolveStatisticValue for non-numeric outcomes.
export type SpecialValue = 'NO_CUMULATIVE_DATA' | 'NOT_AVAILABLE'

type CountryMap = {
  Total?: number
  [country: string]: number | undefined
}

function getByPath(source: unknown, path: string): unknown {
  return path
    .split('.')
    .reduce<unknown>((acc, key) => (acc && typeof acc === 'object' ? (acc as Record<string, unknown>)[key] : undefined), source)
}

function sumByCountries(map: CountryMap, countries: string[]): number {
  return countries.reduce((sum, country) => sum + (map[country] ?? 0), 0)
}

function avgByCountries(map: CountryMap, countries: string[]): number | null {
  const values = countries
    .map((country) => map[country])
    .filter((value): value is number => value !== undefined)

  if (!values.length) {
    return null
  }

  return values.reduce((sum, value) => sum + value, 0) / values.length
}

function resolvePath(path: string, countries: string[], allCountriesSelected: boolean, pct = false): number | null {
  const maybeMap = getByPath(D, path)

  if (!maybeMap || typeof maybeMap !== 'object') {
    return null
  }

  const countryMap = maybeMap as CountryMap

  if (pct) {
    return avgByCountries(countryMap, countries)
  }

  if (allCountriesSelected && countryMap.Total !== undefined) {
    return countryMap.Total
  }

  return sumByCountries(countryMap, countries)
}

// Sums a metric for a specific single year; returns null when no rows exist
// (used for cumulative lookups where 0 rows means "Not Available", not legitimate 0).
function ddTotalForYear(
  dashboardData: DashboardData,
  metric: string,
  countries: string[],
  year: number,
): number | null {
  const rows = dashboardData.data.filter(
    (row) =>
      row.metric === metric &&
      countries.includes(row.country) &&
      row.year === year,
  )
  if (rows.length === 0) return null
  return rows.reduce((sum, row) => sum + row.value, 0)
}

function ddTotal(
  dashboardData: DashboardData,
  metric: string,
  countries: string[],
  startYear: number,
  endYear: number,
): number {
  return dashboardData.data
    .filter(
      (row) =>
        row.metric === metric &&
        countries.includes(row.country) &&
        row.year >= startYear &&
        row.year <= endYear,
    )
    .reduce((sum, row) => sum + row.value, 0)
}


export function resolveStatisticValue(
  statistic: StatisticDefinition,
  dashboardData: DashboardData,
  countries: string[],
  allCountriesSelected: boolean,
  period: Period,
): number | SpecialValue | null {
  const isCumulative = period.type !== 'year'

  if (statistic.ddMetric) {
    if (!isCumulative) {
      // Regular year: sum over [year, year]
      return ddTotal(dashboardData, statistic.ddMetric, countries, period.year, period.year)
    }

    // Cumulative period: pick the correct cumulative metric variant
    const latestYear = period.latestYear
    let cumulativeMetric: string | undefined

    if (period.type === 'cumulative2020') cumulativeMetric = statistic.ddMetricCumulative2020
    else if (period.type === 'cumulative2024') cumulativeMetric = statistic.ddMetricCumulative2024
    else if (period.type === 'cumulativeAllTime') cumulativeMetric = statistic.ddMetricCumulativeAllTime

    if (!cumulativeMetric) return 'NO_CUMULATIVE_DATA'

    const result = ddTotalForYear(dashboardData, cumulativeMetric, countries, latestYear)
    return result === null ? 'NOT_AVAILABLE' : result
  }

  // kpi / kpiSum / kpiRatio paths come from static D object — no cumulative data exists
  if (isCumulative) return 'NO_CUMULATIVE_DATA'

  if (statistic.kpi) {
    return resolvePath(statistic.kpi, countries, allCountriesSelected, statistic.pct)
  }

  if (statistic.kpiSum?.length) {
    return statistic.kpiSum
      .map((path: string) => resolvePath(path, countries, allCountriesSelected, false) ?? 0)
      .reduce((sum: number, value: number) => sum + value, 0)
  }

  if (statistic.kpiRatio) {
    const numerator = resolvePath(statistic.kpiRatio.n, countries, allCountriesSelected, false)
    const denominator = resolvePath(statistic.kpiRatio.d, countries, allCountriesSelected, false)

    if (!numerator || !denominator) {
      return null
    }

    return (numerator / denominator) * 100
  }

  return null
}

// Element map shape shared by every dashlet card's BurType-family lookup
// (e.g. BUR_EL, LG_EL, AG_EL in the dashboard section components).
export interface CumulativeElementMap {
  annual: number
  cum2030: number
  cumall: number
  cum2024: number
}

// Resolves which dashlet_element a card should request when the page-level period is a
// cumulative one, given its element map. A card only has "real" cumulative data for a variant
// when that variant's element id differs from its annual id -- several maps just repeat the
// annual id as a placeholder where no cumulative kpi_mapping row exists. Returns null for
// period.type === 'year' -- callers keep using their own local toggle (Annual/Newly) lookup in
// that case, since this map has no 'newly' member. Returns 'no-data' when the current period has
// no real element for this card, so callers can force their NoData state rather than silently
// showing stale annual data.
export function resolveCumulativeElement(period: Period, elMap: CumulativeElementMap): number | 'no-data' | null {
  if (period.type === 'year') return null
  if (period.type === 'cumulative2020') {
    return elMap.cum2030 !== elMap.annual ? elMap.cum2030 : 'no-data'
  }
  if (period.type === 'cumulativeAllTime') {
    return elMap.cumall !== elMap.annual ? elMap.cumall : 'no-data'
  }
  // period.type === 'cumulative2024'
  return elMap.cum2024 !== elMap.annual ? elMap.cum2024 : 'no-data'
}

export function formatValue(value: number | SpecialValue | null, pct = false): string {
  if (value === 'NO_CUMULATIVE_DATA') return 'This KPI does not have Cumulative Data'
  if (value === 'NOT_AVAILABLE') return 'Not Available'
  if (value === null || (typeof value === 'number' && Number.isNaN(value))) return '—'

  if (pct) {
    return `${(value as number).toFixed(1)}%`
  }

  return Math.round(value as number).toLocaleString()
}
