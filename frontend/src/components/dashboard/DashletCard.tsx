import { useMemo, type CSSProperties, type ReactNode } from 'react'
import { FlexChart } from '@/components/charts/FlexChart'
import { ChartCard, fmt } from '@/components/dashboard/DashboardCards'
import { NoData } from '@/components/dashboard/NoData'
import { useAuth } from '@/contexts/AuthContext'
import { useTargetValuesFor } from '@/contexts/TargetsContext'
import { getCountryColors } from '@/data/staticData'
import { resolveCumulativeElement, type Period } from '@/utils/dashboard'
import {
  sumDashletByCountry,
  getDashletSeries,
  getDashletRows,
  updateQuarterLabel,
  type DashletDataRow,
} from '@/queries/useDashletData'
import type { BurType } from '@/components/dashboard/kpiLabels'

/**
 * One Data Dashboard card, end to end: permission gate, element resolution for the
 * page-level period, aggregation, total badge, update-quarter badge, empty state and
 * chart. Sections keep owning the single useDashletData() fetch and pass `rows` down,
 * so adding a card costs one <DashletCard /> rather than another ~35 lines of the same
 * markup and plumbing.
 */

/**
 * The element-per-toggle shape a card declares for its period variants.
 *
 * `newly` is optional: a card with no Newly-supported variant simply omits it, and
 * resolution falls back to `annual`. The cumulative keys deliberately keep the older
 * convention where repeating the `annual` id means "no real data for this period" --
 * resolveCumulativeElement() reads that collision, so changing it here would silently
 * turn every no-data card back into one showing annual figures under a cumulative label.
 */
export type DashletElementMap = {
  annual: number
  cum2030: number
  cumall: number
  cum2024: number
  newly?: number
}

/** A fixed element id, or a per-period map resolved against the page period. */
type ElementSpec = number | DashletElementMap

/**
 * One chart series. `elements` is a single element/map, or several that are summed
 * into this one series (e.g. Children Benefitting = four gender/level slices; Loans =
 * Kiva + RIF). Several series on one card produce a grouped or stacked chart.
 */
export interface DashletSeriesSpec {
  label: string
  elements: ElementSpec | ElementSpec[]
  color?: string
}

type ElementSource = ElementSpec | DashletSeriesSpec | ElementSource[]

function isSeriesSpec(x: ElementSource): x is DashletSeriesSpec {
  return typeof x === 'object' && x !== null && !Array.isArray(x) && 'elements' in x
}

/**
 * Every element id a section needs, derived from its card definitions. Sections used to
 * hand-list this as ALL_ELEMENTS; forgetting to add a new id there produced a card that
 * rendered fine and charted nothing, with no error anywhere. Walks element maps, series
 * specs and nested arrays alike, so a section can pass whatever shape it declared.
 */
export function collectElements(...sources: ElementSource[]): number[] {
  const out = new Set<number>()
  const walk = (x: ElementSource): void => {
    if (typeof x === 'number') out.add(x)
    else if (Array.isArray(x)) x.forEach(walk)
    else if (isSeriesSpec(x)) walk(x.elements)
    else for (const v of Object.values(x)) if (typeof v === 'number') out.add(v)
  }
  sources.forEach(walk)
  return [...out].sort((a, b) => a - b)
}

/**
 * How to turn a country's rows into its one value.
 *   sum    — add them (the default; what most cards do)
 *   avg    — mean of the non-NaN values, for "average number of…" KPIs
 *   single — take the first row, for KPIs with one row per country
 *   series — don't collapse; one chart series per distinct data_element
 * `avg` and `single` apply to single-element cards only — a card built from `series`
 * always sums within each of its series.
 */
type DashletAgg = 'sum' | 'avg' | 'single' | 'series'

interface DashletCardProps {
  permissionKey: string
  title: string
  kpiId?: string
  /** A single-series card's element(s). Mutually exclusive with `series`. */
  elements?: ElementSpec
  /** A multi-series card's series. Takes precedence over `elements` and `agg`. */
  series?: DashletSeriesSpec[]
  /** Which entry of a period map to use while the page period is a plain year. */
  toggle?: BurType
  period: Period
  countries: string[]
  /** Shared result of the section's useDashletData() call. */
  rows: DashletDataRow[]
  agg?: DashletAgg
  /** Multiplies each value — pass 100 to render a 0–1 ratio as a percentage. */
  scale?: number
  /** Legend/tooltip label for a single-series card. Defaults to the card title. */
  seriesLabel?: string
  /** One colour per series. Single-series cards fall back to country colours. */
  seriesColors?: string[]
  showTargets?: boolean
  /**
   * Which elements feed the target line. 'first' (default) uses only the first series —
   * matching cards like Children Receiving SLS, which targets SHFs alone. 'all' sums
   * across every series, as Enterprise Guides and Schools with Learner Guides do.
   */
  targetMode?: 'first' | 'all'
  horizontal?: boolean
  showLegend?: boolean
  stacked?: boolean
  stackLabels?: boolean
  pct?: boolean
  intPct?: boolean
  /** null leaves the chart height to brand.css — see ChartCard. */
  height?: number | null
  /** Rendered between header and chart, e.g. a ToggleGroup. */
  controls?: ReactNode
  /** Show the empty state when everything totals zero. Off where zero is a real reading. */
  blankWhenZero?: boolean
  /** Replaces <NoData /> for cards that word their empty state differently. */
  emptyState?: ReactNode
  /**
   * false hides the total badge entirely, for cards showing a rate rather than a countable
   * total. 'whenData' shows it only once something is non-zero — some cards render a bare
   * header while empty, others deliberately show "Total 0" next to their empty state.
   */
  showBadge?: boolean | 'whenData'
  /**
   * The "Update Q1 2026" sub-badge on cumulative periods. Off for cards wired to fixed
   * elements rather than a period map — their figure doesn't change with the page period,
   * so dating it would imply a cumulative reading they don't have.
   */
  showUpdateBadge?: boolean
  /** Grid placement, for sections that lay their cards out by hand. */
  style?: CSSProperties
}

export function DashletCard({
  permissionKey,
  title,
  kpiId,
  elements,
  series,
  toggle = 'annual',
  period,
  countries,
  rows,
  agg = 'sum',
  scale = 1,
  seriesLabel,
  seriesColors,
  showTargets = true,
  targetMode = 'first',
  horizontal,
  showLegend,
  stacked,
  stackLabels,
  pct,
  intPct,
  height = null,
  controls,
  blankWhenZero = true,
  emptyState,
  showBadge = true,
  showUpdateBadge = true,
  style,
}: DashletCardProps) {
  const { hasPermission } = useAuth()

  // Every series this card draws, normalised so the single- and multi-series paths share
  // one resolution pass.
  const specs: DashletSeriesSpec[] = useMemo(
    () => series ?? [{ label: seriesLabel ?? title, elements: elements ?? [] }],
    [series, seriesLabel, title, elements],
  )

  // Which element each series reads. 'no-data' means this card has no real row for the
  // selected cumulative period — it charts zero rather than silently showing annual figures.
  const resolved: Array<Array<number | 'no-data'>> = useMemo(
    () =>
      specs.map(spec => {
        const list = Array.isArray(spec.elements) ? spec.elements : [spec.elements]
        return list.map(one => {
          if (typeof one === 'number') return one
          const cum = resolveCumulativeElement(period, one)
          if (cum !== null) return cum
          return one[toggle] ?? one.annual
        })
      }),
    [specs, period, toggle],
  )

  const liveElements = useMemo(
    () => resolved.flat().filter((e): e is number => typeof e === 'number'),
    [resolved],
  )

  const targetElements = useMemo(() => {
    if (!showTargets) return []
    const scope = targetMode === 'all' ? resolved : resolved.slice(0, 1)
    return scope.flat().filter((e): e is number => typeof e === 'number')
  }, [resolved, showTargets, targetMode])

  // Hooks run unconditionally — the permission check returns below them, not above.
  const targets = useTargetValuesFor(targetElements, countries)
  const countryColors = getCountryColors(countries)

  const chartSeries = useMemo(() => {
    // One element whose several kpi_mapping rows are the series (e.g. CAMA + Community
    // Champions both hanging off element 3).
    if (agg === 'series' && !series) {
      const only = resolved[0]?.[0]
      return typeof only === 'number' ? getDashletSeries(rows, only, countries) : []
    }

    // avg/single stay on the original single-element path so their semantics don't drift.
    if ((agg === 'avg' || agg === 'single') && !series) {
      const only = resolved[0]?.[0]
      const label = seriesLabel ?? title
      if (typeof only !== 'number') return [{ label, vals: countries.map(() => 0) }]
      const elRows = getDashletRows(rows, only)
      const vals = countries.map(c => {
        const nums = elRows
          .filter(r => r.country === c)
          .map(r => parseFloat(r.value))
          .filter(v => !Number.isNaN(v))
        if (!nums.length) return 0
        if (agg === 'avg') return (nums.reduce((s, v) => s + v, 0) / nums.length) * scale
        return nums[0] * scale
      })
      return [{ label, vals }]
    }

    return specs.map((spec, i) => {
      // Delegated rather than reimplemented so summing stays identical to before. Each
      // element is summed once into a per-country array, then the arrays are added —
      // resolving inside countries.map() would re-scan every row per country.
      const perElement = resolved[i].map(el =>
        el === 'no-data' ? countries.map(() => 0) : sumDashletByCountry(rows, el, countries),
      )
      return {
        label: spec.label,
        vals: countries.map((_, ci) => perElement.reduce((s, vals) => s + vals[ci] * scale, 0)),
      }
    })
  }, [rows, resolved, specs, countries, agg, scale, seriesLabel, title, series])

  const total = chartSeries.reduce((s, x) => s + x.vals.reduce((a, b) => a + b, 0), 0)
  const updateLabel =
    showUpdateBadge && period.type !== 'year' ? updateQuarterLabel(rows, liveElements) : null

  // Space + NBSP, reproducing the `Total &nbsp;{…}` these cards rendered by hand. Written
  // as an escape rather than a literal so an editor can't quietly normalise it to a space.
  const badgeVisible = showBadge === 'whenData' ? total > 0 : showBadge
  const totalBadge = badgeVisible ? `Total \u00A0${fmt(total)}` : undefined

  if (!hasPermission(permissionKey)) return null

  const colorFor = (i: number): string | string[] => {
    if (specs[i]?.color) return specs[i].color as string
    if (seriesColors) return seriesColors[i % seriesColors.length]
    return countryColors
  }

  return (
    <ChartCard
      title={title}
      kpiId={kpiId}
      permissionKey={permissionKey}
      badge={totalBadge}
      subBadge={updateLabel}
      height={height}
      controls={controls}
      style={style}
    >
      {total > 0 || !blankWhenZero
        ? (
          <FlexChart
            labels={countries}
            datasets={chartSeries.map(({ label, vals }, i) => ({
              label,
              data: vals,
              color: colorFor(i),
            }))}
            horizontal={horizontal}
            showLegend={showLegend}
            stacked={stacked}
            stackLabels={stackLabels}
            pct={pct}
            intPct={intPct}
            targetValues={showTargets ? targets : undefined}
          />
        )
        : (emptyState ?? <NoData />)}
    </ChartCard>
  )
}
