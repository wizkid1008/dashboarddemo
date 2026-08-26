import { useEffect, useMemo, useRef } from 'react'
import { Chart } from 'chart.js/auto'
import ChartDataLabels from 'chartjs-plugin-datalabels'
import { useChartLabels } from '@/contexts/ChartLabelsContext'

const GRID_C = 'rgba(13,79,108,0.12)'
const TICK_C = '#5C5C6E'

function fmtK(v: number): string {
  if (v >= 1_000_000) return (v / 1_000_000).toFixed(1) + 'M'
  if (v >= 1_000) return (v / 1_000).toFixed(0) + 'k'
  return String(v)
}

/** Shared by the tooltip and the on-bar datalabels so both read identically. */
function fmtValue(v: number, pct: boolean, intPct: boolean): string {
  if (intPct) return `${Math.round(v)}%`
  return pct ? `${v.toFixed(2)}%` : Math.round(v).toLocaleString()
}

interface FlexDataset {
  label: string
  /** null renders a gap (no bar) for that category — used when a series has no data for a country. */
  data: (number | null)[]
  color: string | string[]
}

interface FlexChartProps {
  labels: string[]
  datasets: FlexDataset[]
  horizontal?: boolean
  pct?: boolean
  /** Use integer % labels (e.g. "87%") instead of 2dp (e.g. "87.00%") */
  intPct?: boolean
  showLegend?: boolean
  stacked?: boolean
  /** Show datalabels white and centred inside stacked bar segments */
  stackLabels?: boolean
  xLabel?: string
  yLabel?: string
  /** Per-label target values — draws a red dashed line/points at each target. null skips that label (no marker). */
  targetValues?: (number | null)[]
  /** 'line' (default) connects targets with a dashed line, as on the legacy dashboard's multi-target charts.
   *  'points' draws an isolated marker on each bar with no connecting line — used for KPI Dashboard milestones. */
  targetStyle?: 'line' | 'points'
}

const NO_DATA_MSG = 'No data is available for this KPI during this time period'

export function FlexChart({
  labels,
  datasets,
  horizontal = false,
  pct = false,
  intPct = false,
  showLegend = false,
  stacked = false,
  stackLabels = false,
  xLabel,
  yLabel,
  targetValues,
  targetStyle = 'line',
}: FlexChartProps) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null)
  const showLabels = useChartLabels()

  const labelsKey = useMemo(() => JSON.stringify(labels), [labels])
  const datasetsKey = useMemo(() => JSON.stringify(datasets), [datasets])
  const targetKey = useMemo(() => JSON.stringify(targetValues), [targetValues])

  const allZero = datasets.every((d) => d.data.every((v) => !v))

  useEffect(() => {
    if (allZero) return
    const ctx = canvasRef.current
    if (!ctx) return

    const chart = new Chart(ctx, {
      plugins: [ChartDataLabels],
      type: 'bar',
      data: {
        labels,
        datasets: [
          ...datasets.map((d) => ({
            type: 'bar' as const,
            label: d.label,
            data: d.data,
            backgroundColor: d.color,
            borderRadius: 4,
            borderSkipped: false,
            order: 1,
          })),
          ...(targetValues
            ? [{
                type: 'line' as const,
                label: 'Target',
                data: targetValues,
                borderColor: 'rgba(220, 38, 38, 0.85)',
                backgroundColor: 'rgba(220, 38, 38, 0.85)',
                borderWidth: 2,
                borderDash: [5, 4],
                pointRadius: 4,
                pointStyle: 'circle' as const,
                fill: false,
                tension: 0,
                order: 0,
                z: 10,
                showLine: targetStyle !== 'points',
                // Never print labels on the target markers — only on the bars.
                datalabels: { display: false },
              }]
            : []),
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        ] as any[],
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        indexAxis: horizontal ? 'y' : 'x',
        plugins: {
          legend: { display: showLegend || (!!targetValues && targetStyle !== 'points'), labels: { color: TICK_C, font: { size: 10 }, usePointStyle: true } },
          tooltip: {
            callbacks: {
              label(ctx) {
                return ` ${fmtValue(Number(ctx.raw ?? 0), pct, intPct)}`
              },
            },
          },
          // Hover tooltips are unaffected by this — when labels are on you get both.
          // 'auto' lets the plugin drop labels that would collide on crowded charts.
          datalabels: showLabels
            ? {
                display: 'auto',
                anchor: stacked ? 'center' : 'end',
                align: stacked ? 'center' : horizontal ? 'right' : 'top',
                clamp: true,
                offset: 2,
                color: stacked ? '#fff' : TICK_C,
                font: { size: 9, weight: 600 },
                formatter: (v: unknown) => {
                  const n = Number(v)
                  return v === null || !Number.isFinite(n) || n === 0 ? null : fmtValue(n, pct, intPct)
                },
              }
            : { display: false },
        },
        scales: {
          x: {
            stacked,
            grid: { color: horizontal ? 'rgba(0,0,0,0)' : GRID_C },
            ticks: {
              color: TICK_C,
              font: { size: 10 },
              callback: horizontal
                ? (pct ? (v) => `${v}%` : (v) => fmtK(Number(v)))
                : function (v) { return (this as unknown as { getLabelForValue(n: number): string }).getLabelForValue(Number(v)) },
            },
            ...(xLabel ? { title: { display: true, text: xLabel, color: TICK_C, font: { size: 10 } } } : {}),
          },
          y: {
            stacked,
            grid: { color: GRID_C },
            ticks: {
              color: TICK_C,
              font: { size: 10 },
              callback: horizontal
                ? function (v) { return (this as unknown as { getLabelForValue(n: number): string }).getLabelForValue(Number(v)) }
                : (pct ? (v) => `${v}%` : (v) => fmtK(Number(v))),
            },
            ...(yLabel ? { title: { display: true, text: yLabel, color: TICK_C, font: { size: 10 } } } : {}),
          },
        },
        // Extra headroom for vertical bars so a label above a full-height bar isn't cramped.
        // The horizontal right-padding is for end-anchored labels sitting past the bar tip;
        // stacked bars centre their labels inside each segment, so it would just be dead space.
        layout: { padding: { top: showLabels && !horizontal && !stacked ? 18 : 4, right: horizontal && !stacked ? 48 : 8 } },
      },
    })

    return () => {
      chart.destroy()
    }
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [labelsKey, datasetsKey, targetKey, horizontal, pct, intPct, showLegend, stacked, stackLabels, allZero, xLabel, yLabel, targetStyle, showLabels])

  if (allZero) {
    return (
      <div style={{
        display: 'flex', alignItems: 'center', justifyContent: 'center',
        height: '100%', color: 'var(--text-mid)', fontSize: '0.83rem',
        textAlign: 'center', padding: '0 16px', fontStyle: 'italic',
      }}>
        {NO_DATA_MSG}
      </div>
    )
  }

  return <canvas ref={canvasRef} />
}
