import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

const portal = () => supabase.schema('rep_portal')

export interface KpiDashletConfig {
  permission_key: string
  label: string
  description: string | null
  group_id: number | null
  group_name: string | null
  group_display_order: number | null
  chart_type: 'number' | 'bar' | 'horizontal_bar' | 'pie' | 'table'
  display_mode: 'aggregate' | 'timeline' | null
  kpi_id: string
  kpi_disagg1_filters: string[]
  kpi_disagg2_filters: string[]
  kpi_split_mode: 'combine' | 'split'
  show_milestone: boolean
  status?: 'draft' | 'published'
  has_pending_draft?: boolean
  // Only populated by get_kpi_dashlets_admin() (preview mode) — merged
  // draft-over-live, so the comment tooltip can show a staged edit. The
  // public RPC omits these entirely; undefined means "use the normal
  // live/published-only global comment lookup" (see DashletCommentIcon).
  comment?: string | null
  comment_enabled?: boolean
}

// No permission filtering — matches the existing KPI Trends/Milestones RPCs,
// which are gated only by "any authenticated user." When preview is true
// (admin-only — see kpi-dashboard.tsx's gate), calls get_kpi_dashlets_admin()
// instead, which returns every dashlet regardless of publish status with any
// pending draft merged over its live fields.
//
// dashboardId: null means "use that type's default dashboard" (the RPC's own
// NULL fallback — correct immediately when the URL has no ?dashboard= key).
// undefined means "a ?dashboard= key is present but not resolved to an id
// yet" (useDashboards() still loading) — the query stays disabled rather
// than fetching the wrong (default) dashboard's data in the meantime.
export function useKpiDashlets(dashboardId: number | null | undefined, preview = false) {
  return useQuery({
    queryKey: ['kpi-dashboard', 'dashlets', dashboardId, preview],
    enabled: dashboardId !== undefined,
    queryFn: async () => {
      const { data, error } = await portal().rpc(preview ? 'get_kpi_dashlets_admin' : 'get_kpi_dashlets', {
        p_dashboard_id: dashboardId,
      })
      if (error) throw error
      return data as KpiDashletConfig[]
    },
    staleTime: 5 * 60 * 1000,
  })
}

export interface KpiDashletDataRow {
  source_kpi_id: string
  country: string
  year: number
  disaggregation_level_one: string | null
  disaggregation_level_two: string | null
  value_type: string | null
  value: string | null
}

// Fetched broad (all countries/years for the given kpi codes) — filters are
// applied client-side to this one result set, not re-fetched per filter
// change (see features/kpi-dashboard/aggregate.ts).
export function useKpiDashletData(kpiIds: string[]) {
  return useQuery({
    queryKey: ['kpi-dashboard', 'data', [...kpiIds].sort()],
    enabled: kpiIds.length > 0,
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_kpi_dashlet_data', { p_kpi_ids: kpiIds })
      if (error) throw error
      return data as KpiDashletDataRow[]
    },
  })
}

export interface KpiDashletMilestoneRow {
  source_kpi_id: string
  country: string
  year: number
  disaggregation_level_one: string | null
  disaggregation_level_two: string | null
  value: number
  value_type: string | null
}

// Only fetched for KPIs backing a show_milestone dashlet — see kpi-dashboard.tsx.
export function useKpiDashletMilestones(kpiIds: string[]) {
  return useQuery({
    queryKey: ['kpi-dashboard', 'milestones', [...kpiIds].sort()],
    enabled: kpiIds.length > 0,
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_kpi_dashlet_milestones', { p_kpi_ids: kpiIds })
      if (error) throw error
      return data as KpiDashletMilestoneRow[]
    },
  })
}
