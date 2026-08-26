import { isNumericLike } from '@/features/kpi-report/trend-utils'
import type { KpiDashletConfig, KpiDashletDataRow, KpiDashletMilestoneRow } from './queries'

export interface DashletFilters {
  /** Resolved list of country codes — never the 'All' sentinel. */
  countries: string[]
  /** The single selected year — every chart type shows only this year's data, never a range. */
  year: number
}

function filterByDisaggregation(
  rows: KpiDashletDataRow[],
  disagg1Filters: string[],
  disagg2Filters: string[],
): KpiDashletDataRow[] {
  return rows.filter((r) =>
    (disagg1Filters.length === 0 || disagg1Filters.includes(r.disaggregation_level_one ?? '')) &&
    (disagg2Filters.length === 0 || disagg2Filters.includes(r.disaggregation_level_two ?? '')))
}

// `year` is `number` for KPI dashlets (a single snapshot year) and `string`
// for Salesforce dashlets (a Start–End range label, e.g. "2020–2024" — see
// features/salesforce-dashboard/aggregate.ts) — shared here rather than
// redefined so both dashboards' card components take the same result shape.
export interface NumberResult {
  kind: 'number'
  total: number
  year: number | string
  valueType: string | null
  breakdown: { country: string; value: number }[]
}

// Shared by 'bar', 'horizontal_bar', 'pie', and 'table' chart types — same
// one-value-per-country snapshot for the selected year, rendered differently
// per dashlet.chart_type.
export interface SnapshotResult {
  kind: 'snapshot'
  year: number | string
  valueType: string | null
  values: { country: string; value: number }[]
}

// Produced whenever a dashlet's split axis (whichever of kpi_disagg1_filters/
// kpi_disagg2_filters has 2+ selected values — dashlet_kpi_config_one_
// split_axis guarantees at most one does) has 2+ selected values — for every
// chart type, not just the ones that can render multiple series side-by-side.
// bar/horizontal_bar/table branch on dashlet.kpi_split_mode (admin-configured,
// page-wide) to decide whether to flatten this into one combined series or
// show all of them; number/pie always get a viewer-facing radio toggle
// instead (kpi_split_mode doesn't apply to them — see KpiDashletCard.tsx).
export interface MultiSeriesResult {
  kind: 'multi-series'
  year: number | string
  valueType: string | null
  series: { label: string; values: { country: string; value: number }[] }[]  // one entry per selected value on the split axis, in selection order
}

export type AggregateResult =
  | NumberResult
  | SnapshotResult
  | MultiSeriesResult
  | { kind: 'empty' }

function numericRows(rows: KpiDashletDataRow[]) {
  return rows.filter((r) => r.value != null && isNumericLike(r.value))
}

function sumByCountryYear(rows: KpiDashletDataRow[]): Map<string, Map<number, number>> {
  const byCountry = new Map<string, Map<number, number>>()
  for (const r of rows) {
    if (!r.country) continue
    const val = parseFloat(r.value!.trim())
    if (!byCountry.has(r.country)) byCountry.set(r.country, new Map())
    const byYear = byCountry.get(r.country)!
    byYear.set(r.year, (byYear.get(r.year) ?? 0) + val)
  }
  return byCountry
}

function valuesForYear(byCountry: Map<string, Map<number, number>>, countries: string[], year: number): { country: string; value: number }[] {
  const out: { country: string; value: number }[] = []
  for (const country of countries) {
    const v = byCountry.get(country)?.get(year)
    if (v != null) out.push({ country, value: v })
  }
  return out
}

function firstValueType(rows: KpiDashletDataRow[]): string | null {
  return rows.find((r) => r.value_type)?.value_type ?? null
}

// Flattens a MultiSeriesResult into the same shape aggregateDashlet would
// have produced without any disagg2 selection — used by BarBody/TableBody
// when the admin has set kpi_split_mode = 'combine', and by NumberBody/
// PieBody's "Combined" radio option.
export function combineSeries(series: MultiSeriesResult['series']): { country: string; value: number }[] {
  const byCountry = new Map<string, number>()
  for (const s of series) {
    for (const v of s.values) {
      byCountry.set(v.country, (byCountry.get(v.country) ?? 0) + v.value)
    }
  }
  return [...byCountry.entries()].map(([country, value]) => ({ country, value }))
}

export function aggregateDashlet(
  dashlet: KpiDashletConfig,
  rows: KpiDashletDataRow[],
  filters: DashletFilters,
): AggregateResult {
  const relevant = numericRows(rows).filter((r) => filters.countries.includes(r.country))
  if (!relevant.length) return { kind: 'empty' }

  const disaggFiltered = filterByDisaggregation(relevant, dashlet.kpi_disagg1_filters, dashlet.kpi_disagg2_filters)
  if (!disaggFiltered.length) return { kind: 'empty' }

  const valueType = firstValueType(disaggFiltered)

  // dashlet_kpi_config_one_split_axis guarantees at most one of these is
  // ever 2+ — whichever is, it's the split axis for this dashlet.
  const splitAxis: { field: 'disaggregation_level_one' | 'disaggregation_level_two'; values: string[] } | null =
    dashlet.kpi_disagg1_filters.length > 1 ? { field: 'disaggregation_level_one', values: dashlet.kpi_disagg1_filters }
    : dashlet.kpi_disagg2_filters.length > 1 ? { field: 'disaggregation_level_two', values: dashlet.kpi_disagg2_filters }
    : null

  if (splitAxis) {
    const series = splitAxis.values
      .map((label) => {
        const byCountry = sumByCountryYear(disaggFiltered.filter((r) => r[splitAxis.field] === label))
        const values = valuesForYear(byCountry, filters.countries, filters.year)
        return values.length ? { label, values } : null
      })
      .filter((s): s is { label: string; values: { country: string; value: number }[] } => s !== null)
    if (!series.length) return { kind: 'empty' }
    return { kind: 'multi-series', year: filters.year, valueType, series }
  }

  const byCountry = sumByCountryYear(disaggFiltered)

  if (dashlet.chart_type === 'number') {
    const breakdown = valuesForYear(byCountry, filters.countries, filters.year)
    if (!breakdown.length) return { kind: 'empty' }
    breakdown.sort((a, b) => b.value - a.value)
    const total = breakdown.reduce((sum, b) => sum + b.value, 0)
    return { kind: 'number', total, year: filters.year, valueType, breakdown }
  }

  // bar / horizontal_bar / pie / table — same snapshot shape, rendering differs per chart_type
  const values = valuesForYear(byCountry, filters.countries, filters.year)
  if (!values.length) return { kind: 'empty' }
  return { kind: 'snapshot', year: filters.year, valueType, values }
}

// Milestone rows for a dashlet with show_milestone = true — filtered by the
// same disagg1/disagg2 filters as its actual values, then summed per country
// for the selected year. Always combined across any split axis (a milestone
// is one target, not a per-series target), regardless of kpi_split_mode —
// only bar/horizontal_bar/number/table dashlets ever call this (enforced by
// the admin form + admin-users edge function, not here).
export function aggregateMilestone(
  dashlet: KpiDashletConfig,
  milestoneRows: KpiDashletMilestoneRow[],
  filters: DashletFilters,
): { country: string; value: number }[] {
  if (!dashlet.show_milestone) return []

  const relevant = milestoneRows.filter((r) => filters.countries.includes(r.country) && r.year === filters.year)
  const disaggFiltered = relevant.filter((r) =>
    (dashlet.kpi_disagg1_filters.length === 0 || dashlet.kpi_disagg1_filters.includes(r.disaggregation_level_one ?? '')) &&
    (dashlet.kpi_disagg2_filters.length === 0 || dashlet.kpi_disagg2_filters.includes(r.disaggregation_level_two ?? '')))
  if (!disaggFiltered.length) return []

  const byCountry = new Map<string, number>()
  for (const r of disaggFiltered) {
    byCountry.set(r.country, (byCountry.get(r.country) ?? 0) + r.value)
  }
  return [...byCountry.entries()].map(([country, value]) => ({ country, value }))
}
