import { useQuery } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'

const portal = () => supabase.schema('rep_portal')

export function useKpiReportYears(country: string | undefined) {
  return useQuery({
    queryKey: ['kpi-report', 'years', country],
    enabled: !!country,
    queryFn: async () => {
      const { data, error } = await portal().rpc('kpi_report_years', { p_country: country })
      if (error) throw error
      return (data as { year: number }[]).map((r) => r.year)
    },
  })
}

export function useKpiReportGroups(country: string | undefined, year: number | undefined) {
  return useQuery({
    queryKey: ['kpi-report', 'groups', country, year],
    enabled: !!country && !!year,
    queryFn: async () => {
      const { data, error } = await portal().rpc('kpi_report_groups', { p_country: country, p_year: year })
      if (error) throw error
      return (data as { kpi_group: string }[]).map((r) => r.kpi_group)
    },
  })
}

// Catalog-wide (dim_kpi, no country/year filter) — for the Trends page picker,
// where an indicator a country stopped reporting (or never got to this year)
// should still be selectable. kpi_report_groups/kpi_report_indicators below
// stay scoped to country+year for the KPI Report snapshot page, where "what
// did this country report this year" is the right question.
export function useKpiReportAllGroups() {
  return useQuery({
    queryKey: ['kpi-report', 'all-groups'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('kpi_report_all_groups')
      if (error) throw error
      return (data as { kpi_group: string }[]).map((r) => r.kpi_group)
    },
  })
}

export function useKpiReportAllIndicators(kpiGroup: string | undefined) {
  return useQuery({
    queryKey: ['kpi-report', 'all-indicators', kpiGroup],
    enabled: !!kpiGroup,
    queryFn: async () => {
      const { data, error } = await portal().rpc('kpi_report_all_indicators', { p_kpi_group: kpiGroup })
      if (error) throw error
      return data as KpiReportIndicator[]
    },
  })
}

export interface KpiReportIndicator {
  indicator: string
  short_label: string | null
  source_kpi_id: string | null
}

export function useKpiReportIndicators(
  country: string | undefined,
  year: number | undefined,
  kpiGroup: string | undefined,
) {
  return useQuery({
    queryKey: ['kpi-report', 'indicators', country, year, kpiGroup],
    enabled: !!country && !!year && !!kpiGroup,
    queryFn: async () => {
      const { data, error } = await portal().rpc('kpi_report_indicators', {
        p_country: country,
        p_year: year,
        p_kpi_group: kpiGroup,
      })
      if (error) throw error
      return data as KpiReportIndicator[]
    },
  })
}

interface KpiReportDetailRow {
  disaggregation_level_one: string | null
  disaggregation_level_two: string | null
  value_type: string | null
  value: string | null
  definition: string | null
  source_kpi_id: string | null
}

export function useKpiReportIndicatorDetail(
  country: string | undefined,
  year: number | undefined,
  kpiGroup: string | undefined,
  indicator: string | undefined,
) {
  return useQuery({
    queryKey: ['kpi-report', 'indicator-detail', country, year, kpiGroup, indicator],
    enabled: !!country && !!year && !!kpiGroup && !!indicator,
    queryFn: async () => {
      const { data, error } = await portal().rpc('kpi_report_indicator_detail', {
        p_country: country,
        p_year: year,
        p_kpi_group: kpiGroup,
        p_indicator: indicator,
      })
      if (error) throw error
      return data as KpiReportDetailRow[]
    },
  })
}

interface KpiReportTrendRow {
  year: number
  disaggregation_level_one: string | null
  disaggregation_level_two: string | null
  value_type: string | null
  value: string | null
  is_visible: boolean
}

export function useKpiReportIndicatorTrend(
  country: string | undefined,
  kpiGroup: string | undefined,
  indicator: string | undefined,
) {
  return useQuery({
    queryKey: ['kpi-report', 'indicator-trend', country, kpiGroup, indicator],
    enabled: !!country && !!kpiGroup && !!indicator,
    queryFn: async () => {
      const { data, error } = await portal().rpc('kpi_report_indicator_trend', {
        p_country: country,
        p_kpi_group: kpiGroup,
        p_indicator: indicator,
      })
      if (error) throw error
      return data as KpiReportTrendRow[]
    },
  })
}

interface KpiReportTrendAllCountriesRow {
  country: string
  year: number
  disaggregation_level_one: string | null
  disaggregation_level_two: string | null
  value_type: string | null
  value: string | null
  is_visible: boolean
}

export function useKpiReportIndicatorTrendAllCountries(
  kpiGroup: string | undefined,
  indicator: string | undefined,
) {
  return useQuery({
    queryKey: ['kpi-report', 'indicator-trend-all-countries', kpiGroup, indicator],
    enabled: !!kpiGroup && !!indicator,
    queryFn: async () => {
      const { data, error } = await portal().rpc('kpi_report_indicator_trend_all_countries', {
        p_kpi_group: kpiGroup,
        p_indicator: indicator,
      })
      if (error) throw error
      return data as KpiReportTrendAllCountriesRow[]
    },
  })
}

// ── KPI Milestones (actual vs. IP milestone, all countries, one year) ──

export function useKpiMilestoneYears() {
  return useQuery({
    queryKey: ['kpi-milestone', 'years'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('kpi_milestone_years')
      if (error) throw error
      return (data as { year: number }[]).map((r) => r.year)
    },
  })
}

// Scoped to indicators/groups that actually have a milestone set — showing
// the full KPI catalog here would list indicators that always render as
// "N/A" once selected, which is a bad experience.
export function useKpiMilestoneGroups() {
  return useQuery({
    queryKey: ['kpi-milestone', 'groups'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('kpi_milestone_groups')
      if (error) throw error
      return (data as { kpi_group: string }[]).map((r) => r.kpi_group)
    },
  })
}

export function useKpiMilestoneIndicators(kpiGroup: string | undefined) {
  return useQuery({
    queryKey: ['kpi-milestone', 'indicators', kpiGroup],
    enabled: !!kpiGroup,
    queryFn: async () => {
      const { data, error } = await portal().rpc('kpi_milestone_indicators', { p_kpi_group: kpiGroup })
      if (error) throw error
      return data as KpiReportIndicator[]
    },
  })
}

export interface KpiMilestoneReportRow {
  country: string
  disaggregation_level_one: string | null
  disaggregation_level_two: string | null
  milestone_value: number | null
  actual_value: number | null
  value_type: string | null
  is_visible: boolean
}

export function useKpiMilestoneReport(
  year: number | undefined,
  kpiGroup: string | undefined,
  indicator: string | undefined,
) {
  return useQuery({
    queryKey: ['kpi-milestone', 'report', year, kpiGroup, indicator],
    enabled: !!year && !!kpiGroup && !!indicator,
    queryFn: async () => {
      const { data, error } = await portal().rpc('kpi_milestone_report', {
        p_year: year,
        p_kpi_group: kpiGroup,
        p_indicator: indicator,
      })
      if (error) throw error
      return data as KpiMilestoneReportRow[]
    },
  })
}
