import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

const portal = () => supabase.schema('rep_portal')

interface ReportDimension {
  column_name: string
  label: string
}

interface ReportMeasure {
  column_name: string | null // null for count
  label: string
  agg_type: 'count' | 'sum'
}

export interface ReportCatalogEntry {
  report_key: string
  label: string
  geography_level: 'school' | 'district'
  dimensions: ReportDimension[]
  measures: ReportMeasure[]
}

interface ReportCatalogPayload {
  reports: ReportCatalogEntry[]
}

export function useReportCatalog() {
  return useQuery({
    queryKey: ['salesforce-report', 'catalog'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_report_catalog')
      if (error) throw error
      return (data as ReportCatalogPayload).reports
    },
    staleTime: 10 * 60 * 1000,
  })
}

interface ReportDimensionValues {
  values: string[]
  truncated: boolean
}

export function useReportDimensionValues(reportKey: string | undefined, column: string | undefined) {
  return useQuery({
    queryKey: ['salesforce-report', 'dimension-values', reportKey, column],
    enabled: !!reportKey && !!column,
    staleTime: 10 * 60 * 1000,
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_report_dimension_values', {
        p_report_key: reportKey,
        p_column: column,
      })
      if (error) throw error
      const payload = data as ReportDimensionValues | null
      return { values: payload?.values ?? [], truncated: payload?.truncated ?? false }
    },
  })
}

export interface ReportFilter {
  column: string
  values: string[]
}

export interface ReportPivotParams {
  reportKey: string
  groupBy: string[]
  measures: string[] // 'count' or a sum column_name
  filters: ReportFilter[]
  yearStart: number
  yearEnd: number
  countries: string[]
  provinces: string[]
  districts: string[]
  schools: string[]
}

type ReportPivotRow = Record<string, string | number | null>

interface ReportPivotPayload {
  data: ReportPivotRow[]
}

export function useReportPivot(params: ReportPivotParams | null) {
  return useQuery({
    queryKey: ['salesforce-report', 'pivot', params],
    enabled: params !== null,
    queryFn: async () => {
      const p = params!
      const filtersObj = Object.fromEntries(p.filters.filter((f) => f.values.length > 0).map((f) => [f.column, f.values]))
      const { data, error } = await portal().rpc('get_report_pivot', {
        p_report_key: p.reportKey,
        p_group_by: p.groupBy,
        p_measures: p.measures,
        p_filters: filtersObj,
        p_year_start: p.yearStart,
        p_year_end: p.yearEnd,
        p_countries: p.countries.length ? p.countries : null,
        p_provinces: p.provinces.length ? p.provinces : null,
        p_districts: p.districts.length ? p.districts : null,
        p_schools: p.schools.length ? p.schools : null,
      })
      if (error) throw error
      return (data as ReportPivotPayload).data
    },
  })
}
