import type { CSSProperties, ReactNode } from 'react'
import { KpiInfoIcon } from '@/components/KpiInfoIcon'
import { DashletCommentIcon } from '@/components/DashletCommentIcon'
import type { Period } from '@/utils/dashboard'

export interface SectionProps {
  countries: string[]
  startYear: number
  endYear: number
  period: Period
}

export function fmt(n: number | null | undefined): string {
  if (n == null) return '—'
  return Math.round(n).toLocaleString()
}

export function ChartCard({
  title,
  badge,
  subBadge,
  height = 220,
  kpiId,
  permissionKey,
  commentOverride,
  controls,
  style,
  children,
}: {
  title: string
  badge?: string
  /** Small label rendered under the total badge, e.g. "Update Q1" for cumulative cards. */
  subBadge?: string | null
  /**
   * Chart-area height in px. Pass null to leave it to brand.css instead — .er-chart-wrap
   * is 220px but widens to 260px under a media query, and an inline height silently wins
   * over that. Cards written by hand (rather than through this component) have always
   * been CSS-driven, so null is what preserves their behaviour when they move over.
   */
  height?: number | null
  kpiId?: string
  permissionKey?: string
  commentOverride?: { comment: string | null; enabled: boolean }
  /** Rendered between header and chart — the slot a per-card ToggleGroup sits in. */
  controls?: ReactNode
  /** Grid placement for sections that lay their cards out by hand (gridColumn/gridRow/span). */
  style?: CSSProperties
  children: ReactNode
}) {
  return (
    <div className="er-card" style={style}>
      <div className="er-card-header">
        <span className="er-card-title-row">
          <span className="er-card-title">{title}</span>
          {kpiId && <KpiInfoIcon kpiId={kpiId} />}
          {permissionKey && <DashletCommentIcon permissionKey={permissionKey} override={commentOverride} />}
        </span>
        {(badge || subBadge) && (
          <span className="er-badge-group">
            {badge && <span className="er-total-badge">{badge}</span>}
            {subBadge && <span className="er-update-badge">{subBadge}</span>}
          </span>
        )}
      </div>
      {controls}
      <div className="er-chart-wrap" style={height == null ? undefined : { height }}>
        {children}
      </div>
    </div>
  )
}

export function TableCard({
  title,
  kpiId,
  permissionKey,
  children,
}: {
  title: string
  kpiId?: string
  permissionKey?: string
  children: ReactNode
}) {
  return (
    <div className="er-card">
      <div className="er-card-header">
        <span className="er-card-title-row">
          <span className="er-card-title">{title}</span>
          {kpiId && <KpiInfoIcon kpiId={kpiId} />}
          {permissionKey && <DashletCommentIcon permissionKey={permissionKey} />}
        </span>
      </div>
      <div className="er-table-wrap">{children}</div>
    </div>
  )
}

export function StatCard({ title, value }: { title: string; value: string }) {
  return (
    <div className="lg-stat-card">
      <div className="lg-stat-title">{title}</div>
      <div className="lg-stat-value">{value}</div>
    </div>
  )
}
