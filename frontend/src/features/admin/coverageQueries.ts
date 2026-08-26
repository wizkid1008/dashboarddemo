import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { parseKpiValue } from '@/queries/useObservedKpi'
import { DASHBOARD_BY_KPI } from '@/data/dashboardChartRegistry'
import type { DashboardChartEntry } from '@/data/dashboardChartRegistry'

const WAREHOUSE_URL = import.meta.env.VITE_WAREHOUSE_SUPABASE_URL as string
const WAREHOUSE_KEY = import.meta.env.VITE_WAREHOUSE_SUPABASE_KEY as string

interface RawCoverageRow {
  kpi_id: string
  indicator: string | null
  kpi_group: string | null
  country: string
  year: number
  value: string
  row_scope: string | null
  updated_date: string | null
}

interface KpiCoverageCell {
  covered: boolean
  count: number
}

export interface KpiCoverageSummary {
  kpi_id: string
  name: string
  group: string
  totalRecords: number
  countriesWithData: string[]
  yearsWithData: number[]
  latestYear: number | null
  lastUpdated: string | null
  status: 'complete' | 'partial' | 'missing'
  countryYearMap: Record<string, Record<number, KpiCoverageCell>>
  dashboardCharts: DashboardChartEntry[]   // empty = not shown on dashboard
}

export interface CoverageData {
  summaries: KpiCoverageSummary[]
  allCountries: string[]
  allYears: number[]
}

async function fetchPrimaryRows(): Promise<RawCoverageRow[]> {
  const { data: { session } } = await supabase.auth.getSession()
  const token = session?.access_token ?? WAREHOUSE_KEY

  // Query the kpi_coverage_data materialized view directly.
  // It pre-computes DISTINCT ON (kpi_id, country, year) so the row count is
  // small enough to avoid PostgREST's max_rows cap (one row per combination
  // instead of one per row_scope).
  const params = new URLSearchParams({
    select: 'kpi_id,indicator,kpi_group,country,year,value,row_scope,updated_date',
  })

  const response = await fetch(
    `${WAREHOUSE_URL}/rest/v1/kpi_coverage_data?${params}`,
    {
      headers: {
        apikey:           WAREHOUSE_KEY,
        Authorization:    `Bearer ${token}`,
        'Accept-Profile': 'rep_portal',
        Prefer:           'count=none',
      },
    },
  )

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`KPI coverage fetch failed: ${response.status} — ${text}`)
  }

  return response.json() as Promise<RawCoverageRow[]>
}

function aggregateCoverage(rows: RawCoverageRow[]): CoverageData {
  const allCountriesSet = new Set<string>()
  const allYearsSet     = new Set<number>()
  for (const row of rows) {
    allCountriesSet.add(row.country)
    allYearsSet.add(row.year)
  }
  const allCountries = [...allCountriesSet].sort()
  const allYears     = [...allYearsSet].sort((a, b) => a - b)

  const byKpi = new Map<string, RawCoverageRow[]>()
  for (const row of rows) {
    const list = byKpi.get(row.kpi_id) ?? []
    list.push(row)
    byKpi.set(row.kpi_id, list)
  }

  const summaries: KpiCoverageSummary[] = []

  for (const [kpiId, kpiRows] of byKpi) {
    const first = kpiRows[0]
    const countryYearMap: Record<string, Record<number, KpiCoverageCell>> = {}
    let lastUpdated: string | null = null

    // One representative row per (country, year) — already deduplicated by the RPC
    // (DISTINCT ON with SUBTOTAL preferred, then ANNUAL, then other scopes).
    for (const row of kpiRows) {
      const covered = parseKpiValue(row.value) !== 0

      if (!countryYearMap[row.country]) countryYearMap[row.country] = {}
      countryYearMap[row.country][row.year] = { covered, count: 1 }

      if (row.updated_date && (!lastUpdated || row.updated_date > lastUpdated)) {
        lastUpdated = row.updated_date
      }
    }

    const countriesWithData = allCountries.filter(c =>
      Object.values(countryYearMap[c] ?? {}).some(cell => cell.covered),
    )
    const yearsWithData = allYears.filter(y =>
      allCountries.some(c => countryYearMap[c]?.[y]?.covered === true),
    )
    const latestYear = yearsWithData.length > 0 ? Math.max(...yearsWithData) : null

    let status: 'complete' | 'partial' | 'missing' = 'missing'
    if (latestYear !== null) {
      const n = allCountries.filter(c => countryYearMap[c]?.[latestYear]?.covered === true).length
      if (n === allCountries.length) status = 'complete'
      else if (n > 0)                status = 'partial'
    }

    summaries.push({
      kpi_id:          kpiId,
      name:            first.indicator ?? kpiId,
      group:           first.kpi_group ?? '—',
      totalRecords:    kpiRows.length,
      countriesWithData,
      yearsWithData,
      latestYear,
      lastUpdated,
      status,
      countryYearMap,
      dashboardCharts: DASHBOARD_BY_KPI.get(kpiId) ?? [],
    })
  }

  // Dashboard KPIs first, then alphabetical by kpi_id within each group
  summaries.sort((a, b) => {
    const aDash = a.dashboardCharts.length > 0 ? 0 : 1
    const bDash = b.dashboardCharts.length > 0 ? 0 : 1
    if (aDash !== bDash) return aDash - bDash
    return a.kpi_id.localeCompare(b.kpi_id, undefined, { numeric: true })
  })

  return { summaries, allCountries, allYears }
}

export function useKpiCoverage() {
  return useQuery({
    queryKey: ['admin', 'kpi-coverage'],
    queryFn:  async () => {
      const rows = await fetchPrimaryRows()
      return aggregateCoverage(rows)
    },
    staleTime: 5 * 60 * 1000,
  })
}
