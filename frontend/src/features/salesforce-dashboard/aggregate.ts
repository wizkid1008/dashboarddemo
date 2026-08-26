import type { NumberResult, SnapshotResult, MultiSeriesResult } from '@/features/kpi-dashboard/aggregate'
import type { SalesforceDashletConfig, SalesforceDashletDataRow } from './queries'

export interface SalesforceDashletFilters {
  /** Resolved list of country codes — never the 'All' sentinel. */
  countries: string[]
  yearStart: number
  yearEnd: number
}

// Table and Line only: a real Start–End range (2+ years) for a single-metric
// dashlet breaks down by year — Table renders it as one column per year,
// Line plots it as one line per country — instead of collapsing to a
// range-summed total. Years ascending (reads chronologically left-to-right
// regardless of the filter dropdowns' newest-first order). Multi-metric
// dashlets stay on MultiSeriesResult (one column/bar per metric, summed over
// the range) — combining a per-year breakdown with a per-metric one is a
// bigger redesign, not in scope here.
export interface YearBreakdownResult {
  kind: 'year-breakdown'
  years: number[]
  valueType: string | null
  rows: { country: string; byYear: Record<number, number>; total: number }[]
}

// Number/Bar/Horizontal Bar/Pie for a single-metric dashlet carry an extra,
// optional `byYear` breakdown — the same data, summed by year across the
// selected countries instead of by country across the selected range — so
// the card can offer a viewer-facing Country/Year axis toggle (SalesforceDashletCard.tsx)
// without a second round trip. `country` is reused as the year label
// (stringified) so the existing country-keyed Body components render it
// with zero new chart code. Absent (undefined) for multi-metric dashlets,
// where the one axis is already spent comparing metrics.
export type SalesforceNumberResult = NumberResult & { byYear?: { country: string; value: number }[] }
export type SalesforceSnapshotResult = SnapshotResult & { byYear?: { country: string; value: number }[] }

export type SalesforceAggregateResult =
  | SalesforceNumberResult
  | SalesforceSnapshotResult
  | MultiSeriesResult
  | YearBreakdownResult
  | { kind: 'empty' }

function yearLabel(yearStart: number, yearEnd: number): string {
  return yearStart === yearEnd ? String(yearStart) : `${yearStart}–${yearEnd}`
}

function numericRows(rows: SalesforceDashletDataRow[]) {
  return rows.filter((r) => r.value != null && !Number.isNaN(Number(r.value)))
}

// Sums across the whole Start Year–End Year range per country (not a
// single-year lookup like the KPI dashboard's sumByCountryYear/valuesForYear
// — see features/kpi-dashboard/aggregate.ts for that model).
function sumByCountryOverRange(rows: SalesforceDashletDataRow[], countries: string[], yearStart: number, yearEnd: number): { country: string; value: number }[] {
  const byCountry = new Map<string, number>()
  for (const r of rows) {
    if (!r.country || !countries.includes(r.country)) continue
    if (r.year < yearStart || r.year > yearEnd) continue
    byCountry.set(r.country, (byCountry.get(r.country) ?? 0) + Number(r.value))
  }
  return [...byCountry.entries()].map(([country, value]) => ({ country, value }))
}

// Same rows as sumByCountryOverRange, summed the other way — one value per
// year across the selected countries, feeding the Country/Year axis toggle
// on Number/Bar/Horizontal Bar/Pie (single-metric only, see
// SalesforceNumberResult/SalesforceSnapshotResult above).
function sumByYearOverRange(rows: SalesforceDashletDataRow[], countries: string[], yearStart: number, yearEnd: number): { country: string; value: number }[] {
  const byYear = new Map<number, number>()
  for (const r of rows) {
    if (!r.country || !countries.includes(r.country)) continue
    if (r.year < yearStart || r.year > yearEnd) continue
    byYear.set(r.year, (byYear.get(r.year) ?? 0) + Number(r.value))
  }
  return [...byYear.entries()].sort((a, b) => a[0] - b[0]).map(([year, value]) => ({ country: String(year), value }))
}

function yearBreakdownByCountry(rows: SalesforceDashletDataRow[], countries: string[], yearStart: number, yearEnd: number): YearBreakdownResult['rows'] {
  const byCountry = new Map<string, Record<number, number>>()
  for (const r of rows) {
    if (!r.country || !countries.includes(r.country)) continue
    if (r.year < yearStart || r.year > yearEnd) continue
    if (!byCountry.has(r.country)) byCountry.set(r.country, {})
    const byYear = byCountry.get(r.country)!
    byYear[r.year] = (byYear[r.year] ?? 0) + Number(r.value)
  }
  return [...byCountry.entries()].map(([country, byYear]) => ({
    country,
    byYear,
    total: Object.values(byYear).reduce((sum, v) => sum + v, 0),
  }))
}

export function aggregateSalesforceDashlet(
  dashlet: SalesforceDashletConfig,
  rows: SalesforceDashletDataRow[],
  filters: SalesforceDashletFilters,
): SalesforceAggregateResult {
  const relevant = numericRows(rows)
  if (!relevant.length) return { kind: 'empty' }

  const year = yearLabel(filters.yearStart, filters.yearEnd)

  if ((dashlet.chart_type === 'table' || dashlet.chart_type === 'line') && dashlet.metric_config_ids.length === 1 && filters.yearStart !== filters.yearEnd) {
    const years = [...new Set(relevant.map((r) => r.year))]
      .filter((y) => y >= filters.yearStart && y <= filters.yearEnd)
      .sort((a, b) => a - b)
    const rowsOut = yearBreakdownByCountry(relevant, filters.countries, filters.yearStart, filters.yearEnd)
    if (!years.length || !rowsOut.length) return { kind: 'empty' }
    return { kind: 'year-breakdown', years, valueType: null, rows: rowsOut }
  }

  if (dashlet.metric_config_ids.length > 1) {
    const series = dashlet.metric_config_ids
      .map((id, i) => {
        const label = dashlet.metric_names[i] ?? String(id)
        const values = sumByCountryOverRange(
          relevant.filter((r) => r.metric_config_id === id),
          filters.countries, filters.yearStart, filters.yearEnd,
        )
        return values.length ? { label, values } : null
      })
      .filter((s): s is { label: string; values: { country: string; value: number }[] } => s !== null)
    if (!series.length) return { kind: 'empty' }
    return { kind: 'multi-series', year, valueType: null, series }
  }

  // Reached only for single-metric dashlets — the multi-metric branch above
  // already returned for metric_config_ids.length > 1.
  const byYear = sumByYearOverRange(relevant, filters.countries, filters.yearStart, filters.yearEnd)

  if (dashlet.chart_type === 'number') {
    const breakdown = sumByCountryOverRange(relevant, filters.countries, filters.yearStart, filters.yearEnd)
    if (!breakdown.length) return { kind: 'empty' }
    breakdown.sort((a, b) => b.value - a.value)
    const total = breakdown.reduce((sum, b) => sum + b.value, 0)
    return { kind: 'number', total, year, valueType: null, breakdown, byYear }
  }

  // bar / horizontal_bar / pie / table (single-year selection only — a real
  // range on Table already returned via the year-breakdown branch above) —
  // same snapshot shape, rendering differs per chart_type.
  const values = sumByCountryOverRange(relevant, filters.countries, filters.yearStart, filters.yearEnd)
  if (!values.length) return { kind: 'empty' }
  return { kind: 'snapshot', year, valueType: null, values, byYear }
}
