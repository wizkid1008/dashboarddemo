import { useMemo } from 'react'
import { useNavigate, useSearch } from '@tanstack/react-router'
import { useAuth } from '@/contexts/AuthContext'
import { useKpiDashlets, useKpiDashletData, useKpiDashletMilestones } from '@/features/kpi-dashboard/queries'
import { useDashboards } from '@/features/dashboards/queries'
import { aggregateDashlet, aggregateMilestone } from '@/features/kpi-dashboard/aggregate'
import { KpiDashboardFilters, type KpiDashboardFilterState } from '@/components/dashboard/KpiDashboardFilters'
import { KpiDashletCard } from '@/components/dashboard/KpiDashletCard'
import type { KpiDashletConfig } from '@/features/kpi-dashboard/queries'

export function KpiDashboardPage() {
  const { isAdmin } = useAuth()
  const navigate = useNavigate()
  const search = useSearch({ strict: false }) as { groups?: string[]; countries?: string[]; year?: number; preview?: string; dashboard?: string }
  // Non-admins hitting ?preview=1 fall back to the normal published-only
  // view — the param alone grants nothing.
  const isPreview = isAdmin && search.preview === '1'

  // No ?dashboard= key -> use the type's default dashboard immediately
  // (id: null, matches get_kpi_dashlets(NULL)'s own fallback). A key present
  // but not yet resolved against the loaded dashboard list -> undefined,
  // which keeps useKpiDashlets() from fetching the wrong dashboard's data
  // while useDashboards() is still loading. An unrecognized key also falls
  // back to null (the default dashboard) once the list has loaded.
  const dashboardsQuery = useDashboards('kpi')
  const dashboardKey = search.dashboard
  const dashboardId: number | null | undefined = !dashboardKey
    ? null
    : dashboardsQuery.data
      ? (dashboardsQuery.data.find((d) => d.key === dashboardKey)?.id ?? null)
      : undefined

  const { data: dashlets = [], isLoading: dashletsLoading } = useKpiDashlets(dashboardId, isPreview)

  const allKpiIds = useMemo(
    () => [...new Set(dashlets.map((d) => d.kpi_id))],
    [dashlets],
  )
  const { data: rows = [], isLoading: dataLoading } = useKpiDashletData(allKpiIds)

  const milestoneKpiIds = useMemo(
    () => [...new Set(dashlets.filter((d) => d.show_milestone).map((d) => d.kpi_id))],
    [dashlets],
  )
  const { data: milestoneRows = [] } = useKpiDashletMilestones(milestoneKpiIds)

  const allCountries = useMemo(
    () => [...new Set(rows.map((r) => r.country))].sort((a, b) => a.localeCompare(b)),
    [rows],
  )
  const allYears = useMemo(
    () => [...new Set(rows.map((r) => r.year))].sort((a, b) => a - b),
    [rows],
  )

  // Groups, in the order the RPC already sorted dashlets by (display_order)
  // — get_kpi_dashlets() excludes ungrouped dashlets entirely, so every
  // dashlet here always has a real group_name.
  const groupNames = useMemo(() => {
    const seen = new Set<string>()
    const names: string[] = []
    for (const d of dashlets) {
      if (!seen.has(d.group_name!)) {
        seen.add(d.group_name!)
        names.push(d.group_name!)
      }
    }
    return names
  }, [dashlets])

  const sections = useMemo(() => {
    const map = new Map<string, KpiDashletConfig[]>()
    for (const d of dashlets) {
      const name = d.group_name!
      if (!map.has(name)) map.set(name, [])
      map.get(name)!.push(d)
    }
    return map
  }, [dashlets])

  // Filter state lives in the URL (like dashboard.tsx/kpi-milestones.tsx) —
  // no local state to seed, search params are the source of truth and fall
  // back to the full range/selection derived from the fetched data.
  function updateSearch(next: Partial<KpiDashboardFilterState>) {
    void navigate({
      search: (prev) => ({ ...(prev as Record<string, unknown>), ...next }) as never,
      replace: true,
    })
  }

  function updateDashboard(key: string) {
    void navigate({
      search: (prev) => ({ ...(prev as Record<string, unknown>), dashboard: key }) as never,
      replace: true,
    })
  }

  // Single selected year — every card (number/bar/line) shows only this
  // year's data, no range. Per explicit direction: KPI data must never be
  // silently pulled from a different year than the one selected.
  const year = search.year ?? allYears[allYears.length - 1] ?? 0
  const groups = search.groups ?? ['All']
  const countries = search.countries ?? ['All']

  const loading = dashletsLoading || dataLoading || dashboardId === undefined

  if (loading) {
    return <p style={{ color: 'var(--text-mid)' }}>Loading…</p>
  }

  const resolvedGroups = groups.includes('All') ? groupNames : groups
  const resolvedCountries = countries.includes('All') ? allCountries : countries
  const visibleGroupNames = groupNames.filter((g) => resolvedGroups.includes(g))

  return (
    <>
      {isPreview && (
        <div style={{
          background: 'var(--red)', color: '#fff', fontSize: '0.8rem', fontWeight: 700,
          padding: '6px 12px', textAlign: 'center', textTransform: 'uppercase', letterSpacing: '0.04em',
        }}>
          Preview mode — showing draft and unpublished changes. The public dashboard only shows published dashlets.
        </div>
      )}
      <KpiDashboardFilters
        allGroups={groupNames}
        allCountries={allCountries}
        allYears={allYears}
        state={{ groups, countries, year }}
        onChange={updateSearch}
        dashboards={dashboardsQuery.data ?? []}
        selectedDashboardId={dashboardId ?? null}
        onDashboardChange={updateDashboard}
      />

      <div className="body-layout">
        <div className="main-content">
          {dashlets.length === 0 ? (
            <div className="chart-card chart-card--empty">No KPI dashlets configured yet.</div>
          ) : visibleGroupNames.length === 0 ? (
            <div className="chart-card chart-card--empty">No groups selected — choose at least one group above to see its dashlets.</div>
          ) : (
            visibleGroupNames.map((name) => (
              <div key={name} style={{ marginBottom: 32 }}>
                <h2 style={{ fontSize: '0.95rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.04em', marginBottom: 12 }}>
                  {name}
                </h2>
                <div className="chart-card-grid">
                  {sections.get(name)!.map((dashlet) => {
                    const dashletRows = rows.filter((r) => r.source_kpi_id === dashlet.kpi_id)
                    const result = aggregateDashlet(dashlet, dashletRows, {
                      countries: resolvedCountries,
                      year,
                    })
                    const milestone = dashlet.show_milestone
                      ? aggregateMilestone(
                          dashlet,
                          milestoneRows.filter((r) => r.source_kpi_id === dashlet.kpi_id),
                          { countries: resolvedCountries, year },
                        )
                      : []
                    return <KpiDashletCard key={dashlet.permission_key} dashlet={dashlet} result={result} milestone={milestone} />
                  })}
                </div>
              </div>
            ))
          )}
        </div>
      </div>
    </>
  )
}
