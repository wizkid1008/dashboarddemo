import { ChartCard } from '@/components/dashboard/DashboardCards'
import {
  NoData, NumberBody, BarBody, MultiSeriesBarBody, PieBody, TableBody,
  MultiSeriesTableBody, MultiSeriesNumberBody, MultiSeriesPieBody,
  type Values,
} from '@/components/dashboard/DashletChartBodies'
import type { KpiDashletConfig } from '@/features/kpi-dashboard/queries'
import type { AggregateResult } from '@/features/kpi-dashboard/aggregate'
import { combineSeries } from '@/features/kpi-dashboard/aggregate'

export function KpiDashletCard({ dashlet, result, milestone }: { dashlet: KpiDashletConfig; result: AggregateResult; milestone?: Values }) {
  const horizontal = dashlet.chart_type === 'horizontal_bar'
  // Only populated by get_kpi_dashlets_admin() (preview mode) — the public
  // RPC never returns status/has_pending_draft, so this is a no-op there.
  const previewBadge = dashlet.status === 'draft' ? 'DRAFT' : dashlet.has_pending_draft ? 'UNPUBLISHED CHANGES' : undefined
  // Same preview-only story for the comment tooltip — get_kpi_dashlets_admin()
  // returns the merged (draft-over-live) comment; the public RPC omits the
  // field entirely, so `undefined` here means "fall back to the normal
  // live/published-only global lookup" (see DashletCommentIcon).
  const commentOverride = dashlet.comment !== undefined
    ? { comment: dashlet.comment, enabled: dashlet.comment_enabled ?? false }
    : undefined

  return (
    <ChartCard title={dashlet.label} kpiId={dashlet.kpi_id} permissionKey={dashlet.permission_key} badge={previewBadge} commentOverride={commentOverride}>
      {result.kind === 'empty' ? (
        <NoData message="No data for the selected filters." />
      ) : result.kind === 'number' ? (
        <NumberBody result={result} milestoneValues={milestone} />
      ) : result.kind === 'multi-series' ? (
        dashlet.chart_type === 'number' ? (
          <MultiSeriesNumberBody result={result} />
        ) : dashlet.chart_type === 'pie' ? (
          <MultiSeriesPieBody result={result} />
        ) : dashlet.kpi_split_mode === 'split' ? (
          dashlet.chart_type === 'table' ? (
            <MultiSeriesTableBody result={result} />
          ) : (
            <MultiSeriesBarBody result={result} horizontal={horizontal} />
          )
        ) : dashlet.chart_type === 'table' ? (
          <TableBody values={combineSeries(result.series)} year={result.year} valueType={result.valueType} milestoneValues={milestone} />
        ) : (
          <BarBody values={combineSeries(result.series)} year={result.year} valueType={result.valueType} horizontal={horizontal} milestoneValues={milestone} />
        )
      ) : dashlet.chart_type === 'pie' ? (
        <PieBody values={result.values} valueType={result.valueType} />
      ) : dashlet.chart_type === 'table' ? (
        <TableBody values={result.values} year={result.year} valueType={result.valueType} milestoneValues={milestone} />
      ) : (
        <BarBody values={result.values} year={result.year} valueType={result.valueType} horizontal={horizontal} milestoneValues={milestone} />
      )}
    </ChartCard>
  )
}
