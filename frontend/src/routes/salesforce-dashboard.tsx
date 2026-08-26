import { useMemo } from 'react'
import { useNavigate, useSearch } from '@tanstack/react-router'
import { useAuth } from '@/contexts/AuthContext'
import { useSalesforceDashlets, useSalesforceDashletData } from '@/features/salesforce-dashboard/queries'
import { useDashboards } from '@/features/dashboards/queries'
import { aggregateSalesforceDashlet } from '@/features/salesforce-dashboard/aggregate'
import { SalesforceDashboardFilters, defaultSalesforceYear, type SalesforceDashboardFilterState } from '@/components/dashboard/SalesforceDashboardFilters'
import { SalesforceDashletCard } from '@/components/dashboard/SalesforceDashletCard'
import type { SalesforceDashletConfig } from '@/features/salesforce-dashboard/queries'

export function SalesforceDashboardPage() {
  const { isAdmin } = useAuth()
  const navigate = useNavigate()
  const search = useSearch({ strict: false }) as { groups?: string[]; countries?: string[]; yearStart?: number; yearEnd?: number; preview?: string; dashboard?: string }
  // Non-admins hitting ?preview=1 fall back to the normal published-only
  // view — the param alone grants nothing.
  const isPreview = isAdmin && search.preview === '1'

  // See kpi-dashboard.tsx for the null/undefined contract: null -> use the
  // type's default dashboard, undefined -> ?dashboard= key present but not
  // yet resolved against the loaded list.
  const dashboardsQuery = useDashboards('salesforce')
  const dashboardKey = search.dashboard
  const dashboardId: number | null | undefined = !dashboardKey
    ? null
    : dashboardsQuery.data
      ? (dashboardsQuery.data.find((d) => d.key === dashboardKey)?.id ?? null)
      : undefined

  const { data: dashlets = [], isLoading: dashletsLoading } = useSalesforceDashlets(dashboardId, isPreview)

  const allMetricConfigIds = useMemo(
    () => [...new Set(dashlets.flatMap((d) => d.metric_config_ids))],
    [dashlets],
  )
  const { data: rows = [], isLoading: dataLoading } = useSalesforceDashletData(allMetricConfigIds)

  const allCountries = useMemo(
    () => [...new Set(rows.map((r) => r.country))].sort((a, b) => a.localeCompare(b)),
    [rows],
  )
  // Descending — newest year first in the Start/End Year dropdowns.
  const allYears = useMemo(
    () => [...new Set(rows.map((r) => r.year))].sort((a, b) => b - a),
    [rows],
  )

  // Groups, in the order the RPC already sorted dashlets by (display_order)
  // — get_salesforce_dashlets() excludes ungrouped dashlets entirely, so
  // every dashlet here always has a real group_name.
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
    const map = new Map<string, SalesforceDashletConfig[]>()
    for (const d of dashlets) {
      const name = d.group_name!
      if (!map.has(name)) map.set(name, [])
      map.get(name)!.push(d)
    }
    return map
  }, [dashlets])

  // Filter state lives in the URL (same pattern as kpi-dashboard.tsx) — no
  // local state to seed, search params are the source of truth and fall back
  // to the full range/selection derived from the fetched data.
  function updateSearch(next: Partial<SalesforceDashboardFilterState>) {
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

  const yearStart = search.yearStart ?? defaultSalesforceYear(allYears)
  const yearEnd = search.yearEnd ?? defaultSalesforceYear(allYears)
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
      <SalesforceDashboardFilters
        allGroups={groupNames}
        allCountries={allCountries}
        allYears={allYears}
        state={{ groups, countries, yearStart, yearEnd }}
        onChange={updateSearch}
        dashboards={dashboardsQuery.data ?? []}
        selectedDashboardId={dashboardId ?? null}
        onDashboardChange={updateDashboard}
      />

      <div className="body-layout">
        <div className="main-content">
          {dashlets.length === 0 ? (
            <div className="chart-card chart-card--empty">No Salesforce dashlets configured yet.</div>
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
                    const dashletRows = rows.filter((r) => dashlet.metric_config_ids.includes(r.metric_config_id))
                    const result = aggregateSalesforceDashlet(dashlet, dashletRows, {
                      countries: resolvedCountries,
                      yearStart,
                      yearEnd,
                    })
                    return <SalesforceDashletCard key={dashlet.permission_key} dashlet={dashlet} result={result} />
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
