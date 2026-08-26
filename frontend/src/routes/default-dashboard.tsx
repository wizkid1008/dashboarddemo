import { useMemo, useState } from 'react'
import { useNavigate, useSearch } from '@tanstack/react-router'
import { CountryMultiSelect } from '@/components/CountryMultiSelect'
import { SelectDropdown } from '@/components/SelectDropdown'
import { FilterSection } from '@/components/FilterSection'
import { KpiDashletCard } from '@/components/dashboard/KpiDashletCard'
import { useDefaultDashboardDashlets, type DefaultDashboardDashletConfig } from '@/features/default-dashboard/queries'
import { useKpiDashletData, useKpiDashletMilestones } from '@/features/kpi-dashboard/queries'
import { aggregateDashlet, aggregateMilestone } from '@/features/kpi-dashboard/aggregate'
import { useAuth } from '@/contexts/AuthContext'

// Categories are admin-defined free text, not a fixed 3-entry lookup like
// dashboard.tsx's levelMeta — so the hero image cycles through this set by
// the category's position (in category_display_order) rather than matching
// on name, giving each Level a distinct image without requiring exact
// string matches or new per-category image config.
const HERO_IMAGES = [
  '/images/shf-rice-terraces.jpg',
  '/images/shf-maize-field.jpg',
  '/images/shf-coffee-harvest.jpg',
  '/images/shf-coffee-harvest.jpg',
]

export function DefaultDashboardPage() {
  const { isAdmin } = useAuth()
  if (!isAdmin) {
    return (
      <div className="body-layout">
        <div className="main-content">
          <div style={{ padding: '40px 0', textAlign: 'center' }}>
            <h2 style={{ fontWeight: 600, marginBottom: 8 }}>Access Denied</h2>
            <p style={{ color: 'var(--text-mid)' }}>You do not have permission to view this page.</p>
          </div>
        </div>
      </div>
    )
  }
  return <DefaultDashboardContent />
}

function DefaultDashboardContent() {
  const navigate = useNavigate()
  const search = useSearch({ strict: false }) as {
    level?: string
    subLevel?: string
    countries?: string[]
    year?: number
  }

  // Always the default KPI Dashboard — get_main_dashboard_dashlets(NULL)
  // resolves to it server-side (rep_portal.default_dashboard_id('kpi')),
  // same dashlets/groups as /kpi-dashboard, with categories layered on top.
  const { data: dashlets = [], isLoading: dashletsLoading } = useDefaultDashboardDashlets(null)

  const allKpiIds = useMemo(() => [...new Set(dashlets.map((d) => d.kpi_id))], [dashlets])
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

  // Categories (Level), in the order the RPC sorted dashlets by
  // (category_display_order) — uncategorized dashlets are excluded
  // server-side, so every entry here is a real, admin-assigned category.
  const categories = useMemo(() => {
    const seen = new Set<string>()
    const names: string[] = []
    for (const d of dashlets) {
      if (d.category_name && !seen.has(d.category_name)) {
        seen.add(d.category_name)
        names.push(d.category_name)
      }
    }
    return names
  }, [dashlets])

  const [selectedLevel, setSelectedLevel] = useState(() => search.level ?? '')
  const [selectedSubLevel, setSelectedSubLevel] = useState(() => search.subLevel ?? '')
  const [selectedCountries, setSelectedCountries] = useState<string[]>(() => search.countries ?? ['All'])

  // No level chosen yet (fresh visit, no ?level= in the URL, effect hasn't
  // run) — fall back to the first category in admin-configured
  // display_order at render time (not via a setState-in-effect sync, which
  // would cause an extra render and trip the lint rule) so the page shows
  // something on first paint, same "show something on load" expectation as
  // the KPI Dashboard.
  const effectiveLevel = selectedLevel || categories[0] || ''

  const heroImage = useMemo(() => {
    const idx = categories.indexOf(effectiveLevel)
    return HERO_IMAGES[idx >= 0 ? idx % HERO_IMAGES.length : 0]
  }, [categories, effectiveLevel])

  // Every dashlet row for a given category carries the same
  // category_display_title/category_description (denormalized by the RPC
  // join) — any matching row works as the lookup.
  const selectedCategory = useMemo(
    () => dashlets.find((d) => d.category_name === effectiveLevel),
    [dashlets, effectiveLevel],
  )
  const heroTitle = selectedCategory?.category_display_title || effectiveLevel
  const heroDescription = selectedCategory?.category_description
    || `Programme data for ${effectiveLevel}, grouped by Sub Level below.`

  const subLevels = useMemo(() => {
    const seen = new Set<string>()
    const names: string[] = []
    for (const d of dashlets) {
      if (d.category_name === effectiveLevel && d.group_name && !seen.has(d.group_name)) {
        seen.add(d.group_name)
        names.push(d.group_name)
      }
    }
    return names
  }, [dashlets, effectiveLevel])

  const effectiveSubLevel = selectedSubLevel || subLevels[0] || ''

  const year = search.year ?? allYears[allYears.length - 1] ?? 0

  function updateSearch(next: Partial<{ level: string; subLevel: string; countries: string[]; year: number }>) {
    void navigate({
      search: (prev) => ({
        ...(prev as Record<string, unknown>),
        level: next.level ?? effectiveLevel,
        subLevel: next.subLevel ?? effectiveSubLevel,
        countries: next.countries ?? selectedCountries,
        year: next.year ?? year,
      }) as never,
      replace: true,
    })
  }

  const allCountriesSelected = !selectedCountries.length || selectedCountries.includes('All')
  const resolvedCountries = allCountriesSelected ? allCountries : selectedCountries

  const selectedGroupDashlets = useMemo(
    () => dashlets.filter((d) => d.category_name === effectiveLevel && d.group_name === effectiveSubLevel),
    [dashlets, effectiveLevel, effectiveSubLevel],
  )

  const loading = dashletsLoading || dataLoading

  return (
    <>
      <div style={{
        background: 'var(--red)', color: '#fff', fontSize: '0.8rem', fontWeight: 700,
        padding: '6px 12px', textAlign: 'center', textTransform: 'uppercase', letterSpacing: '0.04em',
      }}>
        Preview — validating the new category-driven Default Dashboard against the existing Data Dashboard. Admin-only.
      </div>

      <FilterSection>
        <div className="filter-bar-item">
          <label className="filter-bar-label">Level</label>
          <SelectDropdown
            options={categories}
            value={effectiveLevel}
            placeholder="Select Level"
            disabled={loading}
            onChange={(nextLevel) => {
              const nextSubLevel = dashlets.find((d) => d.category_name === nextLevel)?.group_name ?? ''
              setSelectedLevel(nextLevel)
              setSelectedSubLevel(nextSubLevel)
              updateSearch({ level: nextLevel, subLevel: nextSubLevel })
            }}
          />
        </div>

        <div className="filter-bar-item">
          <label className="filter-bar-label">Sub Level</label>
          <SelectDropdown
            options={subLevels}
            value={effectiveSubLevel}
            placeholder="Select Sub Level"
            disabled={loading}
            onChange={(nextSubLevel) => {
              setSelectedSubLevel(nextSubLevel)
              updateSearch({ subLevel: nextSubLevel })
            }}
          />
        </div>

        <div className="filter-bar-item">
          <label className="filter-bar-label">Countries</label>
          <CountryMultiSelect
            allCountries={allCountries}
            selected={selectedCountries}
            onChange={(next) => {
              setSelectedCountries(next)
              updateSearch({ countries: next })
            }}
          />
        </div>

        <div className="filter-bar-item">
          <label className="filter-bar-label">Year</label>
          <SelectDropdown
            options={allYears.map(String)}
            value={String(year)}
            disabled={loading}
            onChange={(v) => updateSearch({ year: Number(v) })}
          />
        </div>
      </FilterSection>

      <div className="body-layout">
        <div className="main-content">
          {/* ─── Level banner — same content-header treatment as dashboard.tsx, ───
              driven by the selected category name instead of a fixed per-Level
              lookup, since categories here are admin-defined free text. */}
          {effectiveLevel && (
            <div className="content-header">
              <div className="content-header-text">
                <h1 className="hero-title">{heroTitle}</h1>
                <p className="hero-desc">{heroDescription}</p>
              </div>
              <div className="content-header-img-wrap">
                <img
                  src={heroImage}
                  alt="SHF Agriculture programme"
                  className="content-header-img"
                />
              </div>
            </div>
          )}

          {loading ? (
            <p style={{ color: 'var(--text-mid)' }}>Loading…</p>
          ) : dashlets.length === 0 ? (
            <div className="chart-card chart-card--empty">
              No dashlets configured yet — assign categories to groups on the default KPI Dashboard in Admin → Dashlets.
            </div>
          ) : !effectiveLevel || !effectiveSubLevel ? (
            <div className="chart-card chart-card--empty">Select a Level and Sub Level above to see its dashlets.</div>
          ) : selectedGroupDashlets.length === 0 ? (
            <div className="chart-card chart-card--empty">No dashlets in this Sub Level yet.</div>
          ) : (
            <div className="chart-card-grid">
              {selectedGroupDashlets.map((dashlet: DefaultDashboardDashletConfig) => {
                const dashletRows = rows.filter((r) => r.source_kpi_id === dashlet.kpi_id)
                const result = aggregateDashlet(dashlet, dashletRows, { countries: resolvedCountries, year })
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
          )}
        </div>
      </div>
    </>
  )
}
