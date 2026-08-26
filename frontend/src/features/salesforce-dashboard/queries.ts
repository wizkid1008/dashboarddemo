import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

const portal = () => supabase.schema('rep_portal')

export interface SalesforceDashletConfig {
  permission_key: string
  label: string
  description: string | null
  group_id: number | null
  group_name: string | null
  group_display_order: number | null
  chart_type: 'number' | 'bar' | 'horizontal_bar' | 'pie' | 'table' | 'line'
  metric_config_ids: number[]
  metric_names: string[] // parallel array, order-aligned with metric_config_ids — series labels
  status?: 'draft' | 'published'
  has_pending_draft?: boolean
  // Only populated by get_salesforce_dashlets_admin() (preview mode) — see
  // KpiDashletConfig.comment for the same undefined-means-"use the normal
  // live/published-only lookup" contract.
  comment?: string | null
  comment_enabled?: boolean
}

// No permission filtering — matches get_kpi_dashlets()'s "any authenticated
// user" model. When preview is true (admin-only — see
// salesforce-dashboard.tsx's gate), calls get_salesforce_dashlets_admin()
// instead, which returns every dashlet regardless of publish status with any
// pending draft merged over its live fields.
//
// dashboardId: null means "use that type's default dashboard" (correct
// immediately when the URL has no ?dashboard= key). undefined means a
// ?dashboard= key is present but not yet resolved to an id (useDashboards()
// still loading) — the query stays disabled rather than briefly fetching the
// wrong (default) dashboard's data.
export function useSalesforceDashlets(dashboardId: number | null | undefined, preview = false) {
  return useQuery({
    queryKey: ['salesforce-dashboard', 'dashlets', dashboardId, preview],
    enabled: dashboardId !== undefined,
    queryFn: async () => {
      const { data, error } = await portal().rpc(preview ? 'get_salesforce_dashlets_admin' : 'get_salesforce_dashlets', {
        p_dashboard_id: dashboardId,
      })
      if (error) throw error
      return data as SalesforceDashletConfig[]
    },
    staleTime: 5 * 60 * 1000,
  })
}

export interface SalesforceDashletDataRow {
  metric_config_id: number
  metric_name: string
  country: string
  year: number
  value: number
}

// Fetched broad (all countries/years for the given metric_config ids) —
// filters, including the Start/End year range sum, are applied client-side
// to this one result set (see features/salesforce-dashboard/aggregate.ts).
export function useSalesforceDashletData(metricConfigIds: number[]) {
  return useQuery({
    queryKey: ['salesforce-dashboard', 'data', [...metricConfigIds].sort((a, b) => a - b)],
    enabled: metricConfigIds.length > 0,
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_salesforce_dashlet_data', { p_metric_config_ids: metricConfigIds })
      if (error) throw error
      return data as SalesforceDashletDataRow[]
    },
  })
}
