import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

const portal = () => supabase.schema('rep_portal')

export interface AdminReportDimension {
  id: number
  column_name: string
  label: string
  enabled: boolean
  sort_order: number
}

export interface AdminReportMeasure {
  id: number
  column_name: string | null
  label: string
  agg_type: 'count' | 'sum'
  enabled: boolean
  sort_order: number
}

export interface AdminReportEntry {
  report_key: string
  label: string
  geography_level: 'school' | 'district'
  dimensions: AdminReportDimension[]
  measures: AdminReportMeasure[]
}

interface AdminReportConfigPayload {
  reports: AdminReportEntry[]
}

export function useAdminReportConfig() {
  return useQuery({
    queryKey: ['admin', 'report-config'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('admin_get_report_config')
      if (error) throw error
      return (data as AdminReportConfigPayload).reports
    },
  })
}

interface SourceViewColumn {
  column_name: string
  data_type: string
}

export function useSourceViewColumns(reportKey: string | undefined) {
  return useQuery({
    queryKey: ['admin', 'report-config', 'source-columns', reportKey],
    enabled: !!reportKey,
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_source_view_columns', { p_report_key: reportKey })
      if (error) throw error
      return data as SourceViewColumn[]
    },
  })
}

function invalidateReportConfig(qc: ReturnType<typeof useQueryClient>) {
  void qc.invalidateQueries({ queryKey: ['admin', 'report-config'] })
  void qc.invalidateQueries({ queryKey: ['salesforce-report', 'catalog'] })
}

export interface SetDimensionsInput {
  column_name: string
  label: string
  enabled: boolean
  sort_order: number
}

export function useSetReportDimensions() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ reportKey, dimensions }: { reportKey: string; dimensions: SetDimensionsInput[] }) => {
      const { error } = await portal().rpc('admin_set_report_dimensions', {
        p_report_key: reportKey,
        p_dimensions: dimensions,
      })
      if (error) throw error
    },
    onSuccess: () => invalidateReportConfig(qc),
  })
}

export interface SetMeasuresInput {
  column_name: string | null
  label: string
  agg_type: 'count' | 'sum'
  enabled: boolean
  sort_order: number
}

export function useSetReportMeasures() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ reportKey, measures }: { reportKey: string; measures: SetMeasuresInput[] }) => {
      const { error } = await portal().rpc('admin_set_report_measures', {
        p_report_key: reportKey,
        p_measures: measures,
      })
      if (error) throw error
    },
    onSuccess: () => invalidateReportConfig(qc),
  })
}
