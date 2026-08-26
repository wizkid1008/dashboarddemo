export function isNumericLike(raw: string): boolean {
  return /^-?[0-9.]+$/.test(raw.trim())
}

export function formatKpiValue(valueType: string | null, raw: string | null): { text: string; muted: boolean } {
  if (raw == null) return { text: '—', muted: true }
  const trimmed = raw.trim()
  if (!isNumericLike(trimmed)) return { text: trimmed, muted: true } // "Not available", "Not applicable", "6.71%*", etc.
  const num = parseFloat(trimmed)
  if (valueType === 'Percentage') return { text: `${(num * 100).toFixed(1)}%`, muted: false }
  if (valueType?.startsWith('Currency')) return { text: `$${num.toFixed(2)}`, muted: false }
  return { text: Math.round(num).toLocaleString(), muted: false }
}

export function trendKey(l1: string | null, l2: string | null): string {
  return `${l1 ?? ''}${l2 ?? ''}`
}

// Must stay in exact sync with rep_warehouse.kpi_trend_chart_key() (SQL) — same
// '::'-joined format, same NULL→'' coalescing for the disaggregation levels.
export function kpiTrendChartKey(kpiGroup: string, indicator: string, l1: string | null, l2: string | null): string {
  return `${kpiGroup}::${indicator}::${l1 ?? ''}::${l2 ?? ''}`
}

// Must stay in exact sync with rep_warehouse.kpi_milestone_chart_key() (SQL) —
// same '::'-joined format, same NULL→'' coalescing for the disaggregation levels.
export function kpiMilestoneChartKey(kpiGroup: string, indicator: string, l1: string | null, l2: string | null): string {
  return `${kpiGroup}::${indicator}::${l1 ?? ''}::${l2 ?? ''}`
}

// disaggregation_level_two is sometimes literally "0" as a placeholder for
// "no second disaggregation" — treat that the same as absent.
export function disaggregationLabel(l1: string | null, l2: string | null): string {
  const hasLevelTwo = !!l2 && l2 !== '0'
  return hasLevelTwo ? `${l1 ?? '—'} — ${l2}` : (l1 ?? '—')
}

export interface TrendPoint {
  year: number
  value: number
}

export function linreg(points: TrendPoint[]): { slope: number; intercept: number } {
  const n = points.length
  let sumX = 0, sumY = 0, sumXY = 0, sumXX = 0
  points.forEach((p) => {
    sumX += p.year
    sumY += p.value
    sumXY += p.year * p.value
    sumXX += p.year * p.year
  })
  const denom = n * sumXX - sumX * sumX
  const slope = denom !== 0 ? (n * sumXY - sumX * sumY) / denom : 0
  const intercept = (sumY - slope * sumX) / n
  return { slope, intercept }
}

// Only ANNUAL/DETAIL values are independent per-year measurements — every year
// is an upload snapshot, so a missing year means no data was submitted, not
// zero. Splits a sparse {year: raw value} map into contiguous present-year
// point segments (numeric-only; non-numeric values like "Not available" are
// treated as gaps too), for gap-aware line drawing.
export function trendSegments(years: number[], values: Record<number, string>): TrendPoint[][] {
  const points = years
    .filter((y) => values[y] != null && isNumericLike(values[y]))
    .map((y) => ({ year: y, value: parseFloat(values[y]) }))
  const presentByYear = new Map(points.map((p) => [p.year, p]))

  const segments: TrendPoint[][] = []
  let current: TrendPoint[] = []
  years.forEach((y) => {
    const p = presentByYear.get(y)
    if (p) {
      current.push(p)
    } else if (current.length) {
      segments.push(current)
      current = []
    }
  })
  if (current.length) segments.push(current)
  return segments
}

export function trendPoints(years: number[], values: Record<number, string>): TrendPoint[] {
  return years
    .filter((y) => values[y] != null && isNumericLike(values[y]))
    .map((y) => ({ year: y, value: parseFloat(values[y]) }))
}
