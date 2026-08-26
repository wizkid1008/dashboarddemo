import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

const WAREHOUSE_URL = import.meta.env.VITE_WAREHOUSE_SUPABASE_URL as string
const WAREHOUSE_KEY = import.meta.env.VITE_WAREHOUSE_SUPABASE_KEY as string

/** Key for schoolTypeOf — school names are only unique within a district. */
export function schoolTypeKey(district: string, school: string): string {
  return `${district}||${school}`
}

interface DashboardMeta {
  countries:  string[]
  years:      number[]
  metrics:    string[]
  provinces:  Record<string, string[]>   // country  → sorted province list
  districts:  Record<string, string[]>   // province → sorted district list
  schools:    Record<string, string[]>   // district → sorted school list
  schoolTypes: Record<string, string[]>  // district → sorted distinct school types
  schoolTypeOf: Record<string, string>   // schoolTypeKey(district, school) → school type
}

interface MetaPayload {
  countries:  string[] | null
  years:      number[] | null
  metrics:    string[] | null
  geography:  Array<{ country: string; province: string; district: string; school: string; school_type: string | null }> | null
}

async function fetchDashboardMeta(): Promise<DashboardMeta> {
  const { data: { session } } = await supabase.auth.getSession()
  const token = session?.access_token ?? WAREHOUSE_KEY

  const response = await fetch(`${WAREHOUSE_URL}/rest/v1/rpc/get_dashboard_metadata`, {
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
    throw new Error(`Dashboard metadata failed: ${response.status} — ${text}`)
  }

  const payload  = await response.json() as MetaPayload | null
  const countries = payload?.countries ?? []
  const years     = payload?.years     ?? []
  const metrics   = payload?.metrics   ?? []
  const geoRows   = payload?.geography ?? []

  const provinces: Record<string, string[]> = {}
  const districts: Record<string, string[]> = {}
  const schools:   Record<string, string[]> = {}
  const schoolTypes:  Record<string, string[]> = {}
  const schoolTypeOf: Record<string, string>   = {}

  for (const { country, province, district, school, school_type } of geoRows) {
    if (province) {
      if (!provinces[country]) provinces[country] = []
      if (!provinces[country].includes(province)) provinces[country].push(province)
    }
    if (district) {
      const pKey = province ?? country
      if (!districts[pKey]) districts[pKey] = []
      if (!districts[pKey].includes(district)) districts[pKey].push(district)
    }
    if (school && district) {
      if (!schools[district]) schools[district] = []
      if (!schools[district].includes(school)) schools[district].push(school)

      if (school_type) {
        schoolTypeOf[schoolTypeKey(district, school)] = school_type
        if (!schoolTypes[district]) schoolTypes[district] = []
        if (!schoolTypes[district].includes(school_type)) schoolTypes[district].push(school_type)
      }
    }
  }

  for (const key of Object.keys(provinces))   provinces[key].sort()
  for (const key of Object.keys(districts))   districts[key].sort()
  for (const key of Object.keys(schools))     schools[key].sort()
  for (const key of Object.keys(schoolTypes)) schoolTypes[key].sort()

  return { countries, years, metrics, provinces, districts, schools, schoolTypes, schoolTypeOf }
}

export function useDashboardMeta() {
  return useQuery({
    queryKey: ['dashboard-meta'],
    queryFn:  fetchDashboardMeta,
    staleTime: 10 * 60 * 1000,
  })
}
