import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

const portal = () => supabase.schema('rep_portal')

export interface DashboardConfig {
  id: number
  key: string
  label: string
  source_type: 'kpi' | 'salesforce'
  display_order: number
  is_default: boolean
}

// Shared across /kpi-dashboard and /salesforce-dashboard: resolves a
// ?dashboard= URL key to its numeric id, and powers the dashboard-switcher
// dropdown on each page.
export function useDashboards(sourceType: 'kpi' | 'salesforce') {
  return useQuery({
    queryKey: ['dashboards', sourceType],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_dashboards')
      if (error) throw error
      return (data as DashboardConfig[]).filter((d) => d.source_type === sourceType)
    },
    staleTime: 5 * 60 * 1000,
  })
}
