import { useEffect, useMemo, useState } from 'react'
import { useNavigate, useSearch } from '@tanstack/react-router'
import { CountryMultiSelect } from '@/components/CountryMultiSelect'
import { SelectDropdown } from '@/components/SelectDropdown'
import { FilterSection } from '@/components/FilterSection'
import { SubLevelCharts, CUSTOM_CHART_SUBLEVELS } from '@/components/dashboard/SubLevelCharts'
import { hierarchyData, sectionHasVisibleCards } from '@/data/hierarchy'
import { useDashboardData, type DashboardQueryParams } from '@/queries/useDashboardData'
import { useDashboardMeta } from '@/queries/useDashboardMeta'
import type { DashboardData } from '@/types/dashboard'

const EMPTY_DASHBOARD_DATA: DashboardData = {
  countries: [], provinces: {}, districts: {}, schools: {}, years: [], metrics: [], data: [],
}
import { formatValue, resolveStatisticValue, type Period } from '@/utils/dashboard'
import { useAuth } from '@/contexts/AuthContext'
import { TargetsProvider } from '@/contexts/TargetsContext'
import { ChartLabelsProvider } from '@/contexts/ChartLabelsContext'

const LABELS_STORAGE_KEY = 'dashboard.showDataLabels'

export function DashboardPage() {
  const { hasPermission, permissionsLoaded } = useAuth()
  if (!permissionsLoaded) {
    return (
      <div className="body-layout">
        <div className="main-content">
          <p style={{ padding: '20px 0', color: 'var(--text-mid)' }}>Loading…</p>
        </div>
      </div>
    )
  }
  if (!hasPermission('page:dashboard')) {
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
  return <DashboardContent />
}

// Label strings for cumulative period options in the dropdown
const CUMULATIVE_LABELS = {
  cumulative2020: 'Cumulative since 2020',
  cumulative2024: 'Cumulative since 2024',
  cumulativeAllTime: 'Cumulative all-time',
} as const

function parsePeriod(val: string, latestYear: number): Period {
  if (val === CUMULATIVE_LABELS.cumulative2020) return { type: 'cumulative2020', latestYear }
  if (val === CUMULATIVE_LABELS.cumulative2024) return { type: 'cumulative2024', latestYear }
  if (val === CUMULATIVE_LABELS.cumulativeAllTime) return { type: 'cumulativeAllTime', latestYear }
  const yr = Number(val)
  return { type: 'year', year: Number.isFinite(yr) ? yr : latestYear }
}

function DashboardContent() {
  // Structural data: countries + years for dropdowns — tiny payload, loads instantly.
  // Renamed dashMeta to avoid clashing with the levelMeta local variable below.
  const { data: dashMeta } = useDashboardMeta()
  const { hasPermission, permissionsLoaded } = useAuth()

  const navigate = useNavigate()
  const search = useSearch({ strict: false }) as {
    level?: string
    subLevel?: string
    countries?: string[]
    period?: string
  }

  const levels = useMemo(() => {
    const all = [...new Set(hierarchyData.map((entry) => entry.level))]
    if (!permissionsLoaded) return all
    return all.filter((level) =>
      hierarchyData.some((entry) => entry.level === level && sectionHasVisibleCards(entry.subLevel, hasPermission)),
    )
  }, [hasPermission, permissionsLoaded])

  const [selectedLevel, setSelectedLevel] = useState(
    () => search.level ?? '',
  )

  const subLevels = useMemo(() => {
    const all = hierarchyData
      .filter((entry) => entry.level === selectedLevel)
      .map((entry) => entry.subLevel)
    if (!permissionsLoaded) return all
    return all.filter((subLevel) => sectionHasVisibleCards(subLevel, hasPermission))
  }, [selectedLevel, hasPermission, permissionsLoaded])

  const [selectedSubLevel, setSelectedSubLevel] = useState(
    () => search.subLevel ?? '',
  )
  const [selectedCountries, setSelectedCountries] = useState<string[]>(
    () => search.countries ?? ['All'],
  )

  // Cap at the current calendar year so future rows never appear in the dropdown.
  const currentCalendarYear = new Date().getFullYear()

  const latestDataYear = useMemo(
    () => Math.min(dashMeta?.years.at(-1) ?? currentCalendarYear, currentCalendarYear),
    [dashMeta, currentCalendarYear],
  )

  // Year dropdown: years from 2020 up to the lesser of latest DB year and today's year.
  const dataYears = useMemo(() => {
    if (!dashMeta) return []
    return dashMeta.years.filter(y => y >= 2020 && y <= latestDataYear)
  }, [dashMeta, latestDataYear])

  // All available period options: individual years from DB + cumulative labels
  const periodOptions = useMemo(() => [
    ...dataYears.map(String),
    CUMULATIVE_LABELS.cumulative2020,
    CUMULATIVE_LABELS.cumulative2024,
    CUMULATIVE_LABELS.cumulativeAllTime,
  ], [dataYears])

  // Default to the latest year when no period is stored in the URL
  const defaultPeriod = useMemo(
    () => String(latestDataYear),
    [latestDataYear],
  )

  const [selectedPeriod, setSelectedPeriod] = useState<string>(
    () => search.period ?? defaultPeriod,
  )

  const [howtoDismissed, setHowtoDismissed] = useState(false)

  // Display preference, not part of the shared view — kept out of the URL.
  const [showLabels, setShowLabels] = useState(
    () => localStorage.getItem(LABELS_STORAGE_KEY) === 'true',
  )
  useEffect(() => {
    localStorage.setItem(LABELS_STORAGE_KEY, String(showLabels))
  }, [showLabels])

  const selectedEntry = useMemo(
    () =>
      hierarchyData.find(
        (entry) =>
          entry.level === selectedLevel && entry.subLevel === selectedSubLevel,
      ),
    [selectedLevel, selectedSubLevel],
  )

  // Once period options are populated, reset any stale stored period to the latest year.
  useEffect(() => {
    if (periodOptions.length && !periodOptions.includes(selectedPeriod)) {
      setSelectedPeriod(defaultPeriod)
    }
  }, [periodOptions, defaultPeriod, selectedPeriod])

  // Structured Period object consumed by resolveStatisticValue
  const period = useMemo(
    () => parsePeriod(selectedPeriod || defaultPeriod, latestDataYear),
    [selectedPeriod, defaultPeriod, latestDataYear],
  )

  // Single year passed to SubLevelCharts (charts show data for this year)
  const chartYear = period.type === 'year' ? period.year : latestDataYear

  const updateSearch = (
    next: Partial<{
      level: string
      subLevel: string
      countries: string[]
      period: string
    }>,
  ) => {
    void navigate({
      search: (prev) => ({
        ...(prev as Record<string, unknown>),
        level: next.level ?? selectedLevel,
        subLevel: next.subLevel ?? selectedSubLevel,
        countries: next.countries ?? selectedCountries,
        period: next.period ?? selectedPeriod,
      }) as never,
      replace: true,
    })
  }

  const allCountriesSelected = !selectedCountries.length || selectedCountries.includes('All')
  const countries = allCountriesSelected ? (dashMeta?.countries ?? []) : selectedCountries

  // Build targeted query params for dashboard_data_agg.
  //
  // After auditing all section components:
  //   • Only LearnerGuideProgrammeSection reads from dashboardData (for the
  //     'Active Partner Schools' metric used in the MBW-per-school calculation).
  //   • Every other section fetches its own data via useObservedKpi / useKpiSeries
  //     and never touches dashboardData at all.
  //   • All sublevels are in CUSTOM_CHART_SUBLEVELS, so the stat-card block that
  //     calls resolveStatisticValue(statistic, data, …) is never rendered.
  //
  // Result: passing null (disabled) for every sublevel except Learner Guide
  // Programme drops the expensive get_dashboard_data_scoped full-table dump
  // entirely — the query only runs when it is actually needed, and even then
  // fetches only one metric string for the selected year.
  const dashboardParams = useMemo((): DashboardQueryParams | null => {
    if (!selectedEntry) return null
    if (selectedSubLevel === 'Learner Guide Programme') {
      return {
        countries:  allCountriesSelected ? [] : selectedCountries,
        provinces:  [],
        districts:  [],
        schools:    [],
        yearStart:  chartYear,
        yearEnd:    chartYear,
        metrics:    ['Active Partner Schools'],
      }
    }
    // All other sublevels: disable the query — data is not used.
    return null
  }, [selectedEntry, selectedSubLevel, allCountriesSelected, selectedCountries, chartYear])

  // When the query is disabled (null params), React Query leaves data as
  // undefined — fall back to an empty DashboardData so sections always mount.
  const { data: rawDashboardData, isPending, error } = useDashboardData(dashboardParams)
  const data = rawDashboardData ?? EMPTY_DASHBOARD_DATA

  const levelMeta: Record<string, { title: string; desc: string; img: string; imgPos: string }> = {
    "LEVEL 1: SHF's Education": {
      title: "SHF's Education Impact Dashboard",
      desc: "Track key progress indicators that reflect SHF Agriculture's work in SHF's bursary support, Learner Guides and community-based education across the continent.",
      img: '/images/shf-maize-field.jpg',
      imgPos: 'center 55%',
    },
    'LEVEL 2: Livelihoods & Leadership': {
      title: 'Livelihoods & Leadership Impact Dashboard',
      desc: "Track key progress indicators that reflect SHF Agriculture's work in economic empowerment, leadership development and systems strengthening across the continent.",
      img: '/images/shf-coffee-harvest.jpg',
      imgPos: 'center 50%',
    },
    'LEVEL 3: Education Systems': {
      title: 'Education Reach Impact Dashboard',
      desc: "Track key progress indicators that reflect SHF Agriculture's reach in classroom support, teacher training and learning outcomes across the continent.",
      img: '/images/shf-rice-terraces.jpg',
      imgPos: 'center 50%',
    },
  }

  const meta = levelMeta[selectedLevel]

  const periodLabel = selectedPeriod || defaultPeriod

  return (
    <TargetsProvider rows={[]}>
     <ChartLabelsProvider show={showLabels}>
      {/* Full-width progress bar — visible only while data is loading after sublevel selected */}
      {isPending && selectedEntry && (
        <progress style={{ position: 'fixed', top: 0, left: 0, width: '100%', height: 3, zIndex: 9999 }} />
      )}

      <FilterSection>
          <div className="filter-bar-item">
            <label className="filter-bar-label">
              <svg width="14" height="14" viewBox="0 0 20 20" fill="none" aria-hidden="true">
                <rect x="2" y="2" width="16" height="4" rx="1" stroke="currentColor" strokeWidth="1.7" />
                <rect x="2" y="8" width="16" height="4" rx="1" stroke="currentColor" strokeWidth="1.7" />
                <rect x="2" y="14" width="16" height="4" rx="1" stroke="currentColor" strokeWidth="1.7" />
              </svg>
              Level
            </label>
            <SelectDropdown
              options={levels}
              value={selectedLevel}
              placeholder="Select Level"
              onChange={(nextLevel) => {
                const nextSubLevel =
                  hierarchyData.find((entry) => entry.level === nextLevel)?.subLevel ?? ''
                setSelectedLevel(nextLevel)
                setSelectedSubLevel(nextSubLevel)
                updateSearch({ level: nextLevel, subLevel: nextSubLevel })
              }}
            />
          </div>

          <div className="filter-bar-item">
            <label className="filter-bar-label">
              <svg width="14" height="14" viewBox="0 0 20 20" fill="none" aria-hidden="true">
                <circle cx="10" cy="6" r="3.5" stroke="currentColor" strokeWidth="1.7" />
                <path d="M3 17c0-3.314 3.134-6 7-6s7 2.686 7 6" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
              </svg>
              Sub Level
            </label>
            <SelectDropdown
              options={subLevels}
              value={selectedSubLevel}
              placeholder="Select Sub Level"
              onChange={(nextSubLevel) => {
                setSelectedSubLevel(nextSubLevel)
                updateSearch({ subLevel: nextSubLevel })
              }}
            />
          </div>

          <div className="filter-bar-item">
            <label className="filter-bar-label">
              <svg width="14" height="14" viewBox="0 0 20 20" fill="none" aria-hidden="true">
                <circle cx="10" cy="10" r="8" stroke="currentColor" strokeWidth="1.7" />
                <ellipse cx="10" cy="10" rx="3.5" ry="8" stroke="currentColor" strokeWidth="1.7" />
                <path d="M2 10h16" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
              </svg>
              Country
            </label>
            <CountryMultiSelect
              allCountries={dashMeta?.countries ?? []}
              selected={selectedCountries}
              onChange={(next) => {
                setSelectedCountries(next)
                updateSearch({ countries: next })
              }}
            />
          </div>

          <div className="filter-bar-item">
            <label className="filter-bar-label">
              <svg width="14" height="14" viewBox="0 0 20 20" fill="none" aria-hidden="true">
                <rect x="2" y="4" width="16" height="14" rx="2" stroke="currentColor" strokeWidth="1.7" />
                <path d="M6 2v4M14 2v4M2 9h16" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
              </svg>
              Year / Period
            </label>
            <SelectDropdown
              options={periodOptions}
              value={periodLabel}
              placeholder="Select Period"
              disabled={!dashMeta}
              onChange={(next) => {
                setSelectedPeriod(next)
                updateSearch({ period: next })
              }}
            />
          </div>

          <div className="filter-bar-item">
            <button
              type="button"
              className={`chart-toggle-btn${showLabels ? ' active' : ''}`}
              aria-pressed={showLabels}
              title={showLabels
                ? 'Values are shown on every bar. Click to show them on hover only.'
                : 'Values are shown on hover. Click to show them on every bar.'}
              onClick={() => setShowLabels((v) => !v)}
            >
              Data Labels {showLabels ? 'On' : 'Off'}
            </button>
          </div>
      </FilterSection>

      <div className="body-layout">
        <div className="main-content">
          {error instanceof Error && <p style={{ color: 'red' }}>Data load failed: {error.message}</p>}

          {dashMeta && dashMeta.countries.length === 0 && (
            <div className="admin-empty" style={{ padding: '48px 0', textAlign: 'center' }}>
              You have not been assigned access to any country's data. Contact an administrator.
            </div>
          )}

          {/* ─── How to Use panel (shown until level+sublevel selected, or dismissed) ─── */}
          {dashMeta && dashMeta.countries.length > 0 && !selectedEntry && !howtoDismissed && (
            <div className="landing-section landing-section--how-to">
              <button type="button" className="map-how-to-close" aria-label="Dismiss" onClick={() => setHowtoDismissed(true)}>
                <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
                  <path d="M4 4l8 8M12 4l-8 8" strokeLinecap="round" />
                </svg>
              </button>
              <div className="landing-title">How to Use the Data Dashboard</div>
              <p className="landing-intro">
                Explore programme data by selecting a level, sub level, year or cumulative period, and country
                using the filters above.
              </p>
              <div className="landing-steps">
                <div className="landing-step">
                  <span className="landing-step-num">1</span>
                  <div className="landing-step-text">
                    <strong>Select a Data Level</strong>
                    <span>Choose a programme level from the Level dropdown above.</span>
                  </div>
                </div>
                <div className="landing-step">
                  <span className="landing-step-num">2</span>
                  <div className="landing-step-text">
                    <strong>Select a Sub Level</strong>
                    <span>Narrow down to a specific area within your chosen level.</span>
                  </div>
                </div>
                <div className="landing-step">
                  <span className="landing-step-num">3</span>
                  <div className="landing-step-text">
                    <strong>Select a Year or Cumulative Period</strong>
                    <span>Choose an individual year for a snapshot, or a cumulative period where available.</span>
                  </div>
                </div>
                <div className="landing-step">
                  <span className="landing-step-num">4</span>
                  <div className="landing-step-text">
                    <strong>Select a Country</strong>
                    <span>Filter by a specific country or view all countries together.</span>
                  </div>
                </div>
              </div>
              <div className="landing-tip">
                <span className="landing-tip-arrow">→</span>
                <span>
                  For <strong>school and district level data</strong>, switch to{' '}
                  <span style={{ background: 'var(--purple)', color: 'white', padding: '2px 8px', borderRadius: 4, fontWeight: 700, fontSize: '0.82rem' }}>Dynamic Data</span>{' '}
                  using the view selector at the top.
                </span>
              </div>
            </div>
          )}

          {/* ─── Level banner ─── */}
          {meta && selectedEntry && (
            <div className="content-header">
              <div className="content-header-text">
                <h1 className="hero-title">{meta.title}</h1>
                <p className="hero-desc">{meta.desc}</p>
              </div>
              <div className="content-header-img-wrap">
                <img
                  src={meta.img}
                  alt="SHF Agriculture programme"
                  className="content-header-img"
                  style={{ objectPosition: meta.imgPos }}
                />
              </div>
            </div>
          )}

          {selectedEntry && (
            <p className="dashboard-selection">
              {selectedSubLevel} | {selectedCountries.includes('All') ? 'All Countries' : selectedCountries.join(', ')} | {periodLabel}
            </p>
          )}

          {selectedEntry && (
            <SubLevelCharts
              subLevel={selectedSubLevel}
              dashboardData={data}
              countries={countries}
              startYear={chartYear}
              endYear={chartYear}
              period={period}
            />
          )}

          <div className="card-grid-2">
            {data && !CUSTOM_CHART_SUBLEVELS.has(selectedSubLevel) && selectedEntry?.statistics.map((statistic: import('@/data/hierarchy').StatisticDefinition) => {
              const value = resolveStatisticValue(
                statistic,
                data,
                countries,
                allCountriesSelected,
                period,
              )

              return (
                <article key={statistic.label} className="data-card">
                  <div className="data-card-header">
                    {statistic.label}
                  </div>
                  <div className="data-card-body">
                    <div className="dd-number-display">{formatValue(value, statistic.pct)}</div>
                  </div>
                </article>
              )
            })}
          </div>
        </div>
      </div>
     </ChartLabelsProvider>
    </TargetsProvider>
  )
}
