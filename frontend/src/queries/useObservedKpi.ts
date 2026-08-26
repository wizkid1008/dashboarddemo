import { useQuery } from '@tanstack/react-query'
import { fetchObservedKpi } from '@/lib/warehouseClient'
import type { ObservedKpiRow } from '@/lib/warehouseClient'

export type { ObservedKpiRow }

export function useObservedKpi(kpiId: string | null) {
  return useQuery({
    queryKey: ['observed-kpi', kpiId],
    queryFn: () => fetchObservedKpi(kpiId!),
    enabled: !!kpiId,
    staleTime: 10 * 60 * 1000,
  })
}

/** Parse a KPI value string — strips currency symbols and thousands separators. */
export function parseKpiValue(raw: string | null | undefined): number {
  if (!raw) return 0
  const n = parseFloat(raw.replace(/[$,£€]/g, ''))
  return isNaN(n) ? 0 : n
}

export function kpiSeriesByCountry(
  rows: ObservedKpiRow[],
  countries: string[],
  levelOne: string,
  startYear: number,
  endYear: number,
  scale = 1,
  rowScope?: string,
): number[] {
  return countries.map((country) => {
    const matching = rows.filter(
      (r) =>
        r.country === country &&
        r.disaggregation_level_one === levelOne &&
        Number(r.year) >= startYear &&
        Number(r.year) <= endYear &&
        (rowScope == null || r.row_scope == null || r.row_scope === rowScope),
    )
    return matching.reduce((sum, r) => sum + parseKpiValue(r.value) * scale, 0)
  })
}
