import { useMemo } from 'react'
import { useObservedKpi, kpiSeriesByCountry } from '@/queries/useObservedKpi'

interface KpiSeriesOptions {
  multiplier?: number
  rowScope?: string
}

/**
 * Standard hook for a single-level KPI dashlet.
 * Fetches rows for `kpiId`, filters by `levelOne` and year range,
 * and returns per-country values + total.
 *
 * To add a new KPI dashlet using the standard pattern:
 *   const { vals, total } = useKpiSeries('X.Y', countries, 'Annual', startYear, endYear)
 *
 * Options:
 *   multiplier — scale each value (e.g. 100 to convert a 0–1 fraction to %)
 *   rowScope   — filter to a specific row_scope value in the DB
 */
export function useKpiSeries(
  kpiId: string,
  countries: string[],
  levelOne: string,
  startYear: number,
  endYear: number,
  options: KpiSeriesOptions = {},
): { vals: number[]; total: number } {
  const { data: rows = [] } = useObservedKpi(kpiId)
  const { multiplier = 1, rowScope } = options

  const vals = useMemo(
    () => kpiSeriesByCountry(rows, countries, levelOne, startYear, endYear, multiplier, rowScope),
    // eslint-disable-next-line react-hooks/exhaustive-deps
    [rows, countries, levelOne, startYear, endYear, multiplier, rowScope],
  )

  const total = vals.reduce((s, v) => s + v, 0)
  return { vals, total }
}
