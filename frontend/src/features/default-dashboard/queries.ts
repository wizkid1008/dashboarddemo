import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import type { KpiDashletConfig } from '@/features/kpi-dashboard/queries'

const portal = () => supabase.schema('rep_portal')

// Category-aware sibling of KpiDashletConfig — same fields plus the Level
// tier above group_name (see supabase/migrations/20260721060240_add_dashlet_categories.sql).
export interface DefaultDashboardDashletConfig extends KpiDashletConfig {
  category_id: number | null
  category_name: string | null
  category_display_order: number | null
  // Admin-configurable public-facing hero content — null means "fall back
  // to category_name / a generic description" (see
  // supabase/migrations/20260721105550_add_category_display_fields.sql).
  category_display_title: string | null
  category_description: string | null
}

// dashboardId: null means "use the default KPI Dashboard" (the RPC's own
// NULL fallback, rep_portal.default_dashboard_id('kpi') — same dashlets as
// /kpi-dashboard). undefined means "not resolved yet" — keeps the query
// disabled rather than fetching against the wrong dashboard while it loads.
export function useDefaultDashboardDashlets(dashboardId: number | null | undefined) {
  return useQuery({
    queryKey: ['default-dashboard', 'dashlets', dashboardId],
    enabled: dashboardId !== undefined,
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_main_dashboard_dashlets', {
        p_dashboard_id: dashboardId,
      })
      if (error) throw error
      return data as DefaultDashboardDashletConfig[]
    },
    staleTime: 5 * 60 * 1000,
  })
}
