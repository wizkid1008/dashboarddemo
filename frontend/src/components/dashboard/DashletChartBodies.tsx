import { useEffect, useMemo, useRef, useState } from 'react'
import { Chart } from 'chart.js/auto'
import { FlexChart } from '@/components/charts/FlexChart'
import { formatKpiValue } from '@/features/kpi-report/trend-utils'
import type { AggregateResult, MultiSeriesResult } from '@/features/kpi-dashboard/aggregate'
import { combineSeries } from '@/features/kpi-dashboard/aggregate'

// Same categorical palette used on kpi-trends.tsx's cross-country chart —
// assigned by array position, not repainted when the country list changes.
export const COUNTRY_COLORS = [
  '#0D4F6C', '#D9A441', '#D8752C', '#1E7896', '#6FA641',
  '#1E7896', '#6FA641', '#e8a020', '#f07050', '#2d7a5a',
]

export type Values = { country: string; value: number }[]

export const CELL_HEAD = { padding: '2px 6px', color: 'var(--text-mid)', fontWeight: 600, borderBottom: '1px solid var(--cream-dark)' } as const
export const CELL = { padding: '3px 6px', borderBottom: '1px solid var(--cream-dark)' } as const
export const CELL_RIGHT = { ...CELL, textAlign: 'right' as const, fontVariantNumeric: 'tabular-nums' as const }
export const CELL_HEAD_RIGHT = { ...CELL_HEAD, textAlign: 'right' as const }

// Assumes higher actual is better (a milestone is a floor to clear) — true for
// every KPI currently eligible for milestone dashlets (counts of people/
// guides/businesses supported). Revisit if an inverse-direction KPI (e.g. a
// rate you want to decrease) ever gets a milestone dashlet — this would need
// a per-KPI "lower is better" flag to color correctly.
const VARIANCE_POSITIVE = 'rgba(22, 163, 74, 0.9)'
const VARIANCE_NEGATIVE = 'rgba(220, 38, 38, 0.85)'

export function NoData({ message }: { message: string }) {
  return (
    <div style={{
      display: 'flex', alignItems: 'center', justifyContent: 'center',
      height: '100%', color: 'var(--text-mid)', fontSize: '0.83rem',
      textAlign: 'center', padding: '0 16px', fontStyle: 'italic',
    }}>
      {message}
    </div>
  )
}

// axisLabel/sortByLabel let a caller reuse this for breakdowns keyed by
// something other than country (e.g. the Salesforce Dashboard's Country/Year
// axis toggle, where `values[].country` is actually reused as a year label)
// — both default to the original country behavior (value-ranked, "countr{y/ies}"
// wording, "value label" chip order), so every existing caller is unaffected.
function NumberDisplay({ values, year, valueType, milestoneValues, axisLabel = { singular: 'country', plural: 'countries' }, sortByLabel = false }: { values: Values; year: number | string; valueType: string | null; milestoneValues?: Values; axisLabel?: { singular: string; plural: string }; sortByLabel?: boolean }) {
  // Value-ranked reads naturally for countries (biggest first); a year
  // breakdown reads naturally chronologically instead, so sort by the label
  // itself (parsed as a number) rather than value-descending.
  const sorted = sortByLabel
    ? [...values].sort((a, b) => Number(a.country) - Number(b.country))
    : [...values].sort((a, b) => b.value - a.value)
  const total = sorted.reduce((sum, v) => sum + v.value, 0)
  const { text } = formatKpiValue(valueType, String(total))
  const milestoneTotal = milestoneValues?.length ? milestoneValues.reduce((sum, v) => sum + v.value, 0) : null
  return (
    <div style={{ height: '100%', overflowY: 'auto' }}>
      <div style={{ fontSize: '2rem', fontWeight: 800, fontVariantNumeric: 'tabular-nums' }}>{text}</div>
      <div style={{ fontSize: '0.75rem', color: 'var(--text-mid)', marginTop: 2, marginBottom: milestoneTotal != null ? 2 : 10 }}>
        Combined total, {year} — sum across {sorted.length} selected {sorted.length === 1 ? axisLabel.singular : axisLabel.plural}
      </div>
      {milestoneTotal != null && (
        <div style={{ fontSize: '0.8rem', color: total >= milestoneTotal ? VARIANCE_POSITIVE : VARIANCE_NEGATIVE, fontWeight: 600, marginBottom: 10 }}>
          Milestone: {formatKpiValue(valueType, String(milestoneTotal)).text}
        </div>
      )}
      <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px 14px', fontSize: '0.83rem' }}>
        {sorted.map((b, i) => (
          <span key={b.country} style={{ color: COUNTRY_COLORS[i % COUNTRY_COLORS.length] }}>
            {sortByLabel ? (
              <><b>{b.country}:</b> {formatKpiValue(valueType, String(b.value)).text}</>
            ) : (
              <><b>{formatKpiValue(valueType, String(b.value)).text}</b> {b.country}</>
            )}
          </span>
        ))}
      </div>
    </div>
  )
}

export function NumberBody({ result, milestoneValues, axisLabel, sortByLabel }: { result: Extract<AggregateResult, { kind: 'number' }>; milestoneValues?: Values; axisLabel?: { singular: string; plural: string }; sortByLabel?: boolean }) {
  return <NumberDisplay values={result.breakdown} year={result.year} valueType={result.valueType} milestoneValues={milestoneValues} axisLabel={axisLabel} sortByLabel={sortByLabel} />
}

export function BarBody({ values, year, valueType, horizontal, milestoneValues }: { values: Values; year: number | string; valueType: string | null; horizontal?: boolean; milestoneValues?: Values }) {
  const targetValues = milestoneValues?.length
    ? values.map((v) => milestoneValues.find((m) => m.country === v.country)?.value ?? null)
    : undefined
  return (
    <FlexChart
      labels={values.map((v) => v.country)}
      datasets={[{
        label: String(year),
        data: values.map((v) => v.value),
        color: values.map((_, i) => COUNTRY_COLORS[i % COUNTRY_COLORS.length]),
      }]}
      pct={valueType === 'Percentage'}
      horizontal={horizontal}
      targetValues={targetValues}
      targetStyle="points"
    />
  )
}

// One dataset per disagg2 series (grouped bars), colored by series rather
// than by country. Series may not all cover the same countries (a slice can
// be missing data for one), so labels are the union across series and gaps
// render as null (no bar) rather than a misleading zero.
export function MultiSeriesBarBody({ result, horizontal }: { result: MultiSeriesResult; horizontal?: boolean }) {
  const countries = [...new Set(result.series.flatMap((s) => s.values.map((v) => v.country)))]
  return (
    <FlexChart
      labels={countries}
      datasets={result.series.map((s, i) => ({
        label: s.label,
        data: countries.map((c) => s.values.find((v) => v.country === c)?.value ?? null),
        color: COUNTRY_COLORS[i % COUNTRY_COLORS.length],
      }))}
      pct={result.valueType === 'Percentage'}
      horizontal={horizontal}
      showLegend
    />
  )
}

// Only valid for metrics that are genuinely a share of one total (e.g. a
// count summed across countries) — the admin picks 'pie' deliberately for
// those, not for rate/percentage KPIs where countries aren't additive.
export function PieBody({ values, valueType }: { values: Values; valueType: string | null }) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null)
  const dataKey = useMemo(() => JSON.stringify(values), [values])

  useEffect(() => {
    const ctx = canvasRef.current
    if (!ctx) return
    const total = values.reduce((sum, v) => sum + v.value, 0) || 1
    const pctOf = (v: number) => `${((v / total) * 100).toFixed(1)}%`

    const chart = new Chart(ctx, {
      type: 'doughnut',
      data: {
        labels: values.map((v) => v.country),
        datasets: [{
          data: values.map((v) => v.value),
          backgroundColor: values.map((_, i) => COUNTRY_COLORS[i % COUNTRY_COLORS.length]),
          borderWidth: 0,
        }],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        plugins: {
          legend: {
            position: 'bottom',
            labels: {
              color: '#5C5C6E',
              font: { size: 10 },
              usePointStyle: true,
              boxWidth: 8,
              // Value + percentage alongside each country, not crammed onto
              // the slice itself.
              generateLabels(c) {
                const data = c.data.datasets[0]?.data as number[] | undefined
                return (c.data.labels as string[] ?? []).map((label, i) => {
                  const v = data?.[i] ?? 0
                  const color = Array.isArray(c.data.datasets[0]?.backgroundColor)
                    ? (c.data.datasets[0]!.backgroundColor as string[])[i]
                    : undefined
                  return {
                    text: `${label}: ${formatKpiValue(valueType, String(v)).text} (${pctOf(v)})`,
                    fillStyle: color,
                    strokeStyle: color,
                    index: i,
                  }
                })
              },
            },
          },
          tooltip: {
            callbacks: {
              label(ctx) {
                const v = Number(ctx.raw ?? 0)
                return ` ${ctx.label}: ${formatKpiValue(valueType, String(v)).text} (${pctOf(v)})`
              },
            },
          },
        },
      },
    })
    return () => chart.destroy()
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [dataKey])

  return <canvas ref={canvasRef} />
}

function varianceCell(variance: number | null, valueType: string | null) {
  if (variance == null) return <td style={CELL_RIGHT}>—</td>
  const { text } = formatKpiValue(valueType, String(variance))
  const signed = variance > 0 ? `+${text}` : text
  return <td style={{ ...CELL_RIGHT, color: variance >= 0 ? VARIANCE_POSITIVE : VARIANCE_NEGATIVE, fontWeight: 600 }}>{signed}</td>
}

export function TableBody({ values, year, valueType, milestoneValues }: { values: Values; year: number | string; valueType: string | null; milestoneValues?: Values }) {
  const sorted = [...values].sort((a, b) => b.value - a.value)
  const total = values.reduce((sum, v) => sum + v.value, 0)
  const hasMilestone = !!milestoneValues?.length
  const milestoneFor = (country: string) => milestoneValues?.find((m) => m.country === country)?.value
  const milestoneTotal = milestoneValues?.reduce((sum, v) => sum + v.value, 0) ?? 0
  const totalVariance = hasMilestone ? total - milestoneTotal : null
  return (
    <div style={{ height: '100%', overflowY: 'auto' }}>
      <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.83rem' }}>
        <thead>
          <tr>
            <th style={{ ...CELL_HEAD, textAlign: 'left' }}>Country</th>
            <th style={CELL_HEAD_RIGHT}>{year}</th>
            {hasMilestone && <th style={CELL_HEAD_RIGHT}>Milestone</th>}
            {hasMilestone && <th style={CELL_HEAD_RIGHT}>Variance</th>}
          </tr>
        </thead>
        <tbody>
          {sorted.map((v) => {
            const m = milestoneFor(v.country)
            const variance = m != null ? v.value - m : null
            return (
              <tr key={v.country}>
                <td style={CELL}>{v.country}</td>
                <td style={CELL_RIGHT}>{formatKpiValue(valueType, String(v.value)).text}</td>
                {hasMilestone && <td style={CELL_RIGHT}>{m != null ? formatKpiValue(valueType, String(m)).text : '—'}</td>}
                {hasMilestone && varianceCell(variance, valueType)}
              </tr>
            )
          })}
        </tbody>
        <tfoot>
          <tr>
            <td style={{ padding: '3px 6px', fontWeight: 700 }}>Total</td>
            <td style={{ padding: '3px 6px', textAlign: 'right', fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>
              {formatKpiValue(valueType, String(total)).text}
            </td>
            {hasMilestone && (
              <td style={{ padding: '3px 6px', textAlign: 'right', fontWeight: 700, fontVariantNumeric: 'tabular-nums' }}>
                {formatKpiValue(valueType, String(milestoneTotal)).text}
              </td>
            )}
            {hasMilestone && (
              <td style={{ padding: '3px 6px', textAlign: 'right', fontWeight: 700, fontVariantNumeric: 'tabular-nums', color: (totalVariance ?? 0) >= 0 ? VARIANCE_POSITIVE : VARIANCE_NEGATIVE }}>
                {totalVariance != null ? `${totalVariance > 0 ? '+' : ''}${formatKpiValue(valueType, String(totalVariance)).text}` : '—'}
              </td>
            )}
          </tr>
        </tfoot>
      </table>
    </div>
  )
}

// One column per disagg2 series plus a row-level Total column.
export function MultiSeriesTableBody({ result }: { result: MultiSeriesResult }) {
  const countries = [...new Set(result.series.flatMap((s) => s.values.map((v) => v.country)))]
  const rows = countries.map((country) => {
    const perSeries = result.series.map((s) => s.values.find((v) => v.country === country)?.value ?? null)
    const total = perSeries.reduce((sum: number, v) => sum + (v ?? 0), 0)
    return { country, perSeries, total }
  })
  const seriesTotals = result.series.map((s) => s.values.reduce((sum, v) => sum + v.value, 0))
  const grandTotal = seriesTotals.reduce((a, b) => a + b, 0)
  return (
    <div style={{ height: '100%', overflowY: 'auto' }}>
      <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.83rem' }}>
        <thead>
          <tr>
            <th style={{ ...CELL_HEAD, textAlign: 'left' }}>Country</th>
            {result.series.map((s) => <th key={s.label} style={CELL_HEAD_RIGHT}>{s.label}</th>)}
            <th style={{ ...CELL_HEAD_RIGHT, fontWeight: 700 }}>Total</th>
          </tr>
        </thead>
        <tbody>
          {rows.map((r) => (
            <tr key={r.country}>
              <td style={CELL}>{r.country}</td>
              {r.perSeries.map((v, i) => (
                <td key={i} style={CELL_RIGHT}>{v != null ? formatKpiValue(result.valueType, String(v)).text : '—'}</td>
              ))}
              <td style={{ ...CELL_RIGHT, fontWeight: 700 }}>{formatKpiValue(result.valueType, String(r.total)).text}</td>
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr>
            <td style={{ padding: '3px 6px', fontWeight: 700 }}>Total</td>
            {seriesTotals.map((v, i) => (
              <td key={i} style={{ ...CELL_RIGHT, fontWeight: 700 }}>{formatKpiValue(result.valueType, String(v)).text}</td>
            ))}
            <td style={{ ...CELL_RIGHT, fontWeight: 700 }}>{formatKpiValue(result.valueType, String(grandTotal)).text}</td>
          </tr>
        </tfoot>
      </table>
    </div>
  )
}

const COMBINED = '__combined__'

// Viewer-facing toggle for number/pie — they can't show multiple series
// side-by-side the way bar/table can, so instead of an admin-configured
// split, whoever's looking at the page picks one slice (or "Combined") at
// runtime. Not persisted, resets on reload — purely local state.
function MultiSeriesRadioRow({ result, selected, onSelect }: { result: MultiSeriesResult; selected: string; onSelect: (v: string) => void }) {
  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: '4px 12px', fontSize: '0.75rem', marginBottom: 8 }}>
      <label style={{ display: 'inline-flex', alignItems: 'center', gap: 4, cursor: 'pointer' }}>
        <input type="radio" checked={selected === COMBINED} onChange={() => onSelect(COMBINED)} />
        Combined
      </label>
      {result.series.map((s) => (
        <label key={s.label} style={{ display: 'inline-flex', alignItems: 'center', gap: 4, cursor: 'pointer' }}>
          <input type="radio" checked={selected === s.label} onChange={() => onSelect(s.label)} />
          {s.label}
        </label>
      ))}
    </div>
  )
}

function useSelectedSeriesValues(result: MultiSeriesResult): [Values, string, (v: string) => void] {
  const [selected, setSelected] = useState(COMBINED)
  const values = selected === COMBINED ? combineSeries(result.series) : (result.series.find((s) => s.label === selected)?.values ?? [])
  return [values, selected, setSelected]
}

export function MultiSeriesNumberBody({ result }: { result: MultiSeriesResult }) {
  const [values, selected, setSelected] = useSelectedSeriesValues(result)
  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
      <MultiSeriesRadioRow result={result} selected={selected} onSelect={setSelected} />
      <div style={{ flex: 1, minHeight: 0 }}>
        <NumberDisplay values={values} year={result.year} valueType={result.valueType} />
      </div>
    </div>
  )
}

export function MultiSeriesPieBody({ result }: { result: MultiSeriesResult }) {
  const [values, selected, setSelected] = useSelectedSeriesValues(result)
  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
      <MultiSeriesRadioRow result={result} selected={selected} onSelect={setSelected} />
      <div style={{ flex: 1, minHeight: 0 }}>
        <PieBody values={values} valueType={result.valueType} />
      </div>
    </div>
  )
}
