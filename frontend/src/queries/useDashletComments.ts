import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

const WAREHOUSE_URL = import.meta.env.VITE_WAREHOUSE_SUPABASE_URL as string
const WAREHOUSE_KEY = import.meta.env.VITE_WAREHOUSE_SUPABASE_KEY as string

// Matches rep_portal.get_dashlet_comments() — enabled, non-null comments only.
export interface DashletComment {
  permission_key: string
  comment:        string
  updated_at:     string
}

async function fetchDashletComments(): Promise<DashletComment[]> {
  const { data: { session } } = await supabase.auth.getSession()
  const token = session?.access_token ?? WAREHOUSE_KEY

  const response = await fetch(
    `${WAREHOUSE_URL}/rest/v1/rpc/get_dashlet_comments`,
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
    throw new Error(`Dashlet comments fetch failed: ${response.status} — ${text}`)
  }

  return response.json() as Promise<DashletComment[]>
}

export function useDashletComments() {
  return useQuery({
    queryKey:  ['dashlet-comments'],
    queryFn:   fetchDashletComments,
    staleTime: 10 * 60 * 1000, // 10 min — changes only via admin edit
  })
}
