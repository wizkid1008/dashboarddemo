import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

const WAREHOUSE_URL = import.meta.env.VITE_WAREHOUSE_SUPABASE_URL as string
const WAREHOUSE_KEY = import.meta.env.VITE_WAREHOUSE_SUPABASE_KEY as string

// Matches the DictionaryEntry shape consumed by KpiInfoIcon and ResourcePanel.
// Source: rep_warehouse.dim_kpi via get_kpi_definitions() RPC.
// Populated by uploading kpi-definitions.xlsx through the admin portal.
export interface DictionaryEntry {
  kpi_id:     string        // source_kpi_id  e.g. "1.1"
  kpi_name:   string        // indicator      e.g. "SHFs Supported with Education Bursaries"
  kpi_number: string | null // source_kpi_id  (same value — used for the badge in the tooltip)
  kpi_group:  string | null // kpi_group      e.g. "SHF's Education"
  definition: string | null // definition     free-text definition
}

interface RpcRow {
  source_kpi_id:       string
  kpi_group:           string | null
  indicator:           string | null
  indicator_frequency: string | null
  indicator_start:     string | null
  definition:          string | null
}

async function fetchDictionary(): Promise<DictionaryEntry[]> {
  const { data: { session } } = await supabase.auth.getSession()
  const token = session?.access_token ?? WAREHOUSE_KEY

  const response = await fetch(
    `${WAREHOUSE_URL}/rest/v1/rpc/get_kpi_definitions`,
    {
      method: 'POST',
      headers: {
        apikey:            WAREHOUSE_KEY,
        Authorization:     `Bearer ${token}`,
        'Content-Type':    'application/json',
        'Content-Profile': 'rep_portal',
      },
      body: '{}',
    },
  )

  if (!response.ok) {
    const text = await response.text()
    throw new Error(`Data dictionary fetch failed: ${response.status} — ${text}`)
  }

  const rows = await response.json() as RpcRow[]

  // Map dim_kpi columns → DictionaryEntry shape so all consumers are unchanged
  return rows.map(r => ({
    kpi_id:     r.source_kpi_id,
    kpi_name:   r.indicator ?? r.source_kpi_id,
    kpi_number: r.source_kpi_id,
    kpi_group:  r.kpi_group   ?? null,
    definition: r.definition  ?? null,
  }))
}

export function useDataDictionary() {
  return useQuery({
    queryKey:  ['data-dictionary'],
    queryFn:   fetchDictionary,
    staleTime: 10 * 60 * 1000, // 10 min — changes only on kpi-definitions.xlsx upload
  })
}
