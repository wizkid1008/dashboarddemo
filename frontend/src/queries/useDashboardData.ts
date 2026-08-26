import { useQuery } from '@tanstack/react-query'
import type { DashboardData, DashboardRow } from '@/types/dashboard'
import { supabase } from '@/lib/supabase'

const WAREHOUSE_URL = import.meta.env.VITE_WAREHOUSE_SUPABASE_URL as string
const WAREHOUSE_KEY = import.meta.env.VITE_WAREHOUSE_SUPABASE_KEY as string

/** Parameters for a targeted query. Built when the user clicks Run in dynamic.tsx. */
export interface DashboardQueryParams {
  countries:  string[]
  provinces:  string[]
  districts:  string[]
  schools:    string[]
  yearStart:  number
  yearEnd:    number
  metrics:    string[]
  /** School layer only. Empty means no school-type filter. */
  schoolTypes?: string[]
}

interface SupabasePayload {
  data?: DashboardRow[]
}

function buildDashboardData(rows: DashboardRow[]): DashboardData {
  const countriesSet = new Set<string>()
  const yearsSet     = new Set<number>()
  const metricsSet   = new Set<string>()
  const provinces:   Record<string, string[]> = {}
  const districts:   Record<string, string[]> = {}
  const schools:     Record<string, string[]> = {}

  for (const row of rows) {
    if (!row.country) continue
    countriesSet.add(row.country)
    yearsSet.add(row.year)
    metricsSet.add(row.metric)

    if (row.province) {
      if (!provinces[row.country]) provinces[row.country] = []
      if (!provinces[row.country].includes(row.province)) provinces[row.country].push(row.province)
    }
    if (row.district) {
      const pKey = row.province ?? row.country
      if (!districts[pKey]) districts[pKey] = []
      if (!districts[pKey].includes(row.district)) districts[pKey].push(row.district)

      if (row.school && !['District Total', 'National'].includes(row.school)) {
        if (!schools[row.district]) schools[row.district] = []
        if (!schools[row.district].includes(row.school)) schools[row.district].push(row.school)
      }
    }
  }

  return {
    countries: [...countriesSet].sort(),
    provinces,
    districts,
    schools,
    years:   [...yearsSet].sort((a, b) => a - b),
    metrics: [...metricsSet].sort(),
    data:    rows,
  }
}

// ── Full fetch (backward-compat for dashboard.tsx / slicer.tsx) ───────────────

async function fetchAllDashboardData(): Promise<DashboardData> {
  const { data: { session } } = await supabase.auth.getSession()
  const token = session?.access_token ?? WAREHOUSE_KEY

  const response = await fetch(`${WAREHOUSE_URL}/rest/v1/rpc/get_dashboard_data_scoped`, {
    method: 'POST',
    headers: {
      apikey:            WAREHOUSE_KEY,
      Authorization:     `Bearer ${token}`,
      'Content-Type':    'application/json',
      'Content-Profile': 'rep_portal',
    },
    body: JSON.stringify({}),
  })

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`Data request failed: ${response.status} — ${text}`)
  }

  const payload = await response.json() as SupabasePayload | null
  return buildDashboardData(payload?.data ?? [])
}

// ── Filtered fetch (used by dynamic.tsx after Run) ────────────────────────────

async function fetchDashboardData(params: DashboardQueryParams): Promise<DashboardData> {
  const { data: { session } } = await supabase.auth.getSession()
  const token = session?.access_token ?? WAREHOUSE_KEY

  const response = await fetch(`${WAREHOUSE_URL}/rest/v1/rpc/get_dashboard_data_filtered`, {
    method: 'POST',
    headers: {
      apikey:            WAREHOUSE_KEY,
      Authorization:     `Bearer ${token}`,
      'Content-Type':    'application/json',
      'Content-Profile': 'rep_portal',
    },
    body: JSON.stringify({
      p_countries:  params.countries.length  ? params.countries  : null,
      p_provinces:  params.provinces.length  ? params.provinces  : null,
      p_districts:  params.districts.length  ? params.districts  : null,
      p_schools:    params.schools.length    ? params.schools    : null,
      p_year_start: params.yearStart,
      p_year_end:   params.yearEnd,
      p_metrics:    params.metrics.length    ? params.metrics    : null,
      p_school_types: params.schoolTypes?.length ? params.schoolTypes : null,
    }),
  })

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`Data request failed: ${response.status} — ${text}`)
  }

  const payload = await response.json() as SupabasePayload | null
  return buildDashboardData(payload?.data ?? [])
}

// ── Hook ──────────────────────────────────────────────────────────────────────

/**
 * Overloaded hook:
 *   useDashboardData()        — fetches all permitted rows (used by dashboard.tsx / slicer.tsx)
 *   useDashboardData(params)  — fetches only the filtered rows needed for a Run (dynamic.tsx)
 *   useDashboardData(null)    — disabled; no fetch until params are provided
 */
export function useDashboardData(params?: DashboardQueryParams | null) {
  const isFiltered = params !== undefined   // explicit call with params (or null)
  const isDisabled = params === null        // explicitly disabled

  return useQuery({
    queryKey: isFiltered ? ['dashboard-data', params] : ['dashboard-data-all'],
    queryFn:  isDisabled
      ? () => Promise.resolve(buildDashboardData([]))
      : isFiltered
        ? () => fetchDashboardData(params!)
        : fetchAllDashboardData,
    enabled:  !isDisabled,
    staleTime: 5 * 60 * 1000,
  })
}
