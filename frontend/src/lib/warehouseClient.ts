import { supabase } from '@/lib/supabase'

const WAREHOUSE_URL = import.meta.env.VITE_WAREHOUSE_SUPABASE_URL as string
const WAREHOUSE_KEY = import.meta.env.VITE_WAREHOUSE_SUPABASE_KEY as string

export interface ObservedKpiRow {
  country: string
  kpi_id: string
  disaggregation_level_one: string
  disaggregation_level_two: string
  year: number
  year_quarter: number | null
  row_scope: string | null
  value: string
}

export interface DashletDataRow {
  dashlet_element: number
  data_element: string
  toggle: string | null
  country: string
  kpi_id: string
  disaggregation_level_one: string
  disaggregation_level_two: string
  year: number
  year_quarter: number | null
  row_scope: string | null
  value: string
  update_quarter: string | null
}

export async function fetchObservedKpi(kpiId: string): Promise<ObservedKpiRow[]> {
  const { data: { session } } = await supabase.auth.getSession()
  const token = session?.access_token ?? WAREHOUSE_KEY

  const response = await fetch(`${WAREHOUSE_URL}/rest/v1/rpc/get_observed_kpi`, {
    method: 'POST',
    headers: {
      apikey:            WAREHOUSE_KEY,
      Authorization:     `Bearer ${token}`,
      'Content-Type':    'application/json',
      'Content-Profile': 'rep_portal',
    },
    body: JSON.stringify({ p_kpi_id: kpiId }),
  })

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`get_observed_kpi failed (${kpiId}): ${response.status} — ${text}`)
  }

  return response.json() as Promise<ObservedKpiRow[]>
}

export async function fetchDashletData(
  elements: number[],
  startYear: number,
  endYear: number,
): Promise<DashletDataRow[]> {
  const { data: { session } } = await supabase.auth.getSession()
  const token = session?.access_token ?? WAREHOUSE_KEY

  const response = await fetch(`${WAREHOUSE_URL}/rest/v1/rpc/get_dashlet_data`, {
    method: 'POST',
    headers: {
      apikey:            WAREHOUSE_KEY,
      Authorization:     `Bearer ${token}`,
      'Content-Type':    'application/json',
      'Content-Profile': 'rep_portal',
    },
    body: JSON.stringify({
      p_dashlet_elements: elements,
      p_start_year: startYear,
      p_end_year: endYear,
    }),
  })

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`get_dashlet_data failed: ${response.status} — ${text}`)
  }

  return response.json() as Promise<DashletDataRow[]>
}
