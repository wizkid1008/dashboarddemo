import { useEffect, useMemo, useRef, useState } from 'react'
import { Chart } from 'chart.js/auto'
import { ChartCard } from '@/components/dashboard/DashboardCards'
import {
  NoData, NumberBody, BarBody, MultiSeriesBarBody, PieBody, TableBody,
  MultiSeriesTableBody, MultiSeriesNumberBody, MultiSeriesPieBody,
  CELL, CELL_HEAD, CELL_RIGHT, CELL_HEAD_RIGHT, COUNTRY_COLORS,
} from '@/components/dashboard/DashletChartBodies'
import { formatKpiValue } from '@/features/kpi-report/trend-utils'
import type { SalesforceDashletConfig } from '@/features/salesforce-dashboard/queries'
import type { SalesforceAggregateResult, SalesforceNumberResult, SalesforceSnapshotResult, YearBreakdownResult } from '@/features/salesforce-dashboard/aggregate'

// Single-metric Table dashlets over a real Start–End range (2+ years) show
// one column per year instead of collapsing to a range-summed total — see
// aggregateSalesforceDashlet's 'year-breakdown' branch.
function YearBreakdownTableBody({ result }: { result: YearBreakdownResult }) {
  const sorted = [...result.rows].sort((a, b) => b.total - a.total)
  const yearTotals = result.years.map((y) => sorted.reduce((sum, r) => sum + (r.byYear[y] ?? 0), 0))
  const grandTotal = yearTotals.reduce((sum, v) => sum + v, 0)
  return (
    <div style={{ height: '100%', overflow: 'auto' }}>
      <table style={{ width: '100%', borderCollapse: 'collapse', fontSize: '0.83rem' }}>
        <thead>
          <tr>
            <th style={{ ...CELL_HEAD, textAlign: 'left' }}>Country</th>
            {result.years.map((y) => <th key={y} style={CELL_HEAD_RIGHT}>{y}</th>)}
            <th style={{ ...CELL_HEAD_RIGHT, fontWeight: 700 }}>Total</th>
          </tr>
        </thead>
        <tbody>
          {sorted.map((r) => (
            <tr key={r.country}>
              <td style={CELL}>{r.country}</td>
              {result.years.map((y) => (
                <td key={y} style={CELL_RIGHT}>{formatKpiValue(result.valueType, String(r.byYear[y] ?? 0)).text}</td>
              ))}
              <td style={{ ...CELL_RIGHT, fontWeight: 700 }}>{formatKpiValue(result.valueType, String(r.total)).text}</td>
            </tr>
          ))}
        </tbody>
        <tfoot>
          <tr>
            <td style={{ padding: '3px 6px', fontWeight: 700 }}>Total</td>
            {yearTotals.map((v, i) => (
              <td key={i} style={{ ...CELL_RIGHT, fontWeight: 700 }}>{formatKpiValue(result.valueType, String(v)).text}</td>
            ))}
            <td style={{ ...CELL_RIGHT, fontWeight: 700 }}>{formatKpiValue(result.valueType, String(grandTotal)).text}</td>
          </tr>
        </tfoot>
      </table>
    </div>
  )
}

// Same shape as YearBreakdownTableBody's source data, plotted as one line
// per country instead of a table — only meaningful over a real multi-year
// range (see aggregateSalesforceDashlet's 'year-breakdown' branch, gated the
// same way for chart_type === 'line').
function LineBody({ result }: { result: YearBreakdownResult }) {
  const canvasRef = useRef<HTMLCanvasElement | null>(null)
  const dataKey = useMemo(() => JSON.stringify(result), [result])

  useEffect(() => {
    const ctx = canvasRef.current
    if (!ctx) return
    const chart = new Chart(ctx, {
      type: 'line',
      data: {
        labels: result.years.map(String),
        datasets: result.rows.map((r, i) => ({
          label: r.country,
          data: result.years.map((y) => r.byYear[y] ?? null),
          borderColor: COUNTRY_COLORS[i % COUNTRY_COLORS.length],
          backgroundColor: COUNTRY_COLORS[i % COUNTRY_COLORS.length],
          spanGaps: true,
          tension: 0.25,
        })),
      },
      options: {
        responsive: true,
        maintainAspectRatio: false,
        scales: { y: { beginAtZero: true } },
        plugins: {
          legend: {
            position: 'bottom',
            labels: { color: '#5C5C6E', font: { size: 10 }, usePointStyle: true, boxWidth: 8 },
          },
          tooltip: {
            callbacks: {
              label(ctx) {
                return ` ${ctx.dataset.label}: ${formatKpiValue(result.valueType, String(ctx.raw ?? 0)).text}`
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

const AXIS_LABEL = { singular: 'year', plural: 'years' }

// Viewer-facing toggle for single-metric Number/Bar/Horizontal Bar/Pie —
// switches between the default by-country breakdown and the by-year one
// (aggregateSalesforceDashlet's optional `byYear`, summed across the selected
// countries instead of by country across the range). Not persisted, resets
// on reload — same "local, per-viewer choice" pattern as the multi-series
// Combined/per-series radio in DashletChartBodies.tsx.
function AxisToggleRow({ axis, onSelect }: { axis: 'country' | 'year'; onSelect: (v: 'country' | 'year') => void }) {
  return (
    <div style={{ display: 'flex', gap: 12, fontSize: '0.75rem', marginBottom: 8 }}>
      <label style={{ display: 'inline-flex', alignItems: 'center', gap: 4, cursor: 'pointer' }}>
        <input type="radio" checked={axis === 'country'} onChange={() => onSelect('country')} />
        By Country
      </label>
      <label style={{ display: 'inline-flex', alignItems: 'center', gap: 4, cursor: 'pointer' }}>
        <input type="radio" checked={axis === 'year'} onChange={() => onSelect('year')} />
        By Year
      </label>
    </div>
  )
}

function AxisToggleNumberBody({ result }: { result: SalesforceNumberResult & { byYear: { country: string; value: number }[] } }) {
  const [axis, setAxis] = useState<'country' | 'year'>('country')
  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
      <AxisToggleRow axis={axis} onSelect={setAxis} />
      <div style={{ flex: 1, minHeight: 0 }}>
        {axis === 'country' ? (
          <NumberBody result={result} />
        ) : (
          <NumberBody result={{ ...result, breakdown: result.byYear }} axisLabel={AXIS_LABEL} sortByLabel />
        )}
      </div>
    </div>
  )
}

function AxisToggleSnapshotBody({ result, chartType, horizontal }: {
  result: SalesforceSnapshotResult & { byYear: { country: string; value: number }[] }
  chartType: 'bar' | 'horizontal_bar' | 'pie'
  horizontal?: boolean
}) {
  const [axis, setAxis] = useState<'country' | 'year'>('country')
  const values = axis === 'country' ? result.values : result.byYear
  return (
    <div style={{ height: '100%', display: 'flex', flexDirection: 'column' }}>
      <AxisToggleRow axis={axis} onSelect={setAxis} />
      <div style={{ flex: 1, minHeight: 0 }}>
        {chartType === 'pie' ? (
          <PieBody values={values} valueType={result.valueType} />
        ) : (
          <BarBody values={values} year={result.year} valueType={result.valueType} horizontal={horizontal} />
        )}
      </div>
    </div>
  )
}

export function SalesforceDashletCard({ dashlet, result }: { dashlet: SalesforceDashletConfig; result: SalesforceAggregateResult }) {
  const horizontal = dashlet.chart_type === 'horizontal_bar'
  // Only populated by get_salesforce_dashlets_admin() (preview mode) — the
  // public RPC never returns status/has_pending_draft, so this is a no-op
  // there. Same pattern as KpiDashletCard.
  const previewBadge = dashlet.status === 'draft' ? 'DRAFT' : dashlet.has_pending_draft ? 'UNPUBLISHED CHANGES' : undefined
  const commentOverride = dashlet.comment !== undefined
    ? { comment: dashlet.comment, enabled: dashlet.comment_enabled ?? false }
    : undefined

  return (
    <ChartCard title={dashlet.label} permissionKey={dashlet.permission_key} badge={previewBadge} commentOverride={commentOverride}>
      {result.kind === 'empty' ? (
        <NoData message="No data for the selected filters." />
      ) : result.kind === 'year-breakdown' ? (
        dashlet.chart_type === 'line' ? <LineBody result={result} /> : <YearBreakdownTableBody result={result} />
      ) : result.kind === 'number' ? (
        result.byYear?.length ? (
          <AxisToggleNumberBody result={{ ...result, byYear: result.byYear }} />
        ) : (
          <NumberBody result={result} />
        )
      ) : result.kind === 'multi-series' ? (
        // Always "split" for multi-series — a Salesforce dashlet's whole
        // point in being wired to 2+ metrics is to compare them, so bar/table
        // always render one series per metric (no admin-configured combine/
        // split toggle like KPI's kpi_split_mode). number/pie keep the
        // viewer-facing combined/single-series radio toggle for free via the
        // shared body. No Country/Year axis toggle here — the axis is already
        // spent comparing metrics (see aggregate.ts).
        dashlet.chart_type === 'number' ? (
          <MultiSeriesNumberBody result={result} />
        ) : dashlet.chart_type === 'pie' ? (
          <MultiSeriesPieBody result={result} />
        ) : dashlet.chart_type === 'table' ? (
          <MultiSeriesTableBody result={result} />
        ) : dashlet.chart_type === 'line' ? (
          <NoData message="Line charts aren't available for dashlets wired to multiple metrics — use a single-metric dashlet instead." />
        ) : (
          <MultiSeriesBarBody result={result} horizontal={horizontal} />
        )
      ) : dashlet.chart_type === 'pie' ? (
        result.byYear?.length ? (
          <AxisToggleSnapshotBody result={{ ...result, byYear: result.byYear }} chartType="pie" />
        ) : (
          <PieBody values={result.values} valueType={result.valueType} />
        )
      ) : dashlet.chart_type === 'table' ? (
        <TableBody values={result.values} year={result.year} valueType={result.valueType} />
      ) : dashlet.chart_type === 'line' ? (
        <NoData message="Line charts show a trend across years — pick a Start Year different from End Year to see one." />
      ) : dashlet.chart_type === 'number' ? (
        // Unreachable in practice — aggregateSalesforceDashlet only ever
        // returns a 'snapshot' result (this branch) when chart_type isn't
        // 'number' (that produces the 'number' result kind, handled above).
        // Kept only so TS narrows chart_type to 'bar' | 'horizontal_bar'
        // below, matching AxisToggleSnapshotBody's prop type.
        <BarBody values={result.values} year={result.year} valueType={result.valueType} horizontal={horizontal} />
      ) : result.byYear?.length ? (
        <AxisToggleSnapshotBody result={{ ...result, byYear: result.byYear }} chartType={dashlet.chart_type} horizontal={horizontal} />
      ) : (
        <BarBody values={result.values} year={result.year} valueType={result.valueType} horizontal={horizontal} />
      )}
    </ChartCard>
  )
}
