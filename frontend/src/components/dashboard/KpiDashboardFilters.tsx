import { CountryMultiSelect } from '@/components/CountryMultiSelect'
import { SelectDropdown } from '@/components/SelectDropdown'
import { FilterSection } from '@/components/FilterSection'
import type { DashboardConfig } from '@/features/dashboards/queries'

export interface KpiDashboardFilterState {
  groups: string[] // ['All'] means all groups
  countries: string[] // ['All'] means all countries
  year: number // snapshot year — number/bar cards show data as of this year, line cards trend up to it
}

export function KpiDashboardFilters({
  allGroups,
  allCountries,
  allYears,
  state,
  onChange,
  dashboards,
  selectedDashboardId,
  onDashboardChange,
}: {
  allGroups: string[]
  allCountries: string[]
  allYears: number[]
  state: KpiDashboardFilterState
  onChange: (next: KpiDashboardFilterState) => void
  // Only rendered once there's more than one KPI dashboard to choose from —
  // with a single (the default) dashboard, a switcher has nothing to add.
  dashboards: DashboardConfig[]
  selectedDashboardId: number | null
  onDashboardChange: (key: string) => void
}) {
  function reset() {
    onChange({ groups: ['All'], countries: ['All'], year: allYears[allYears.length - 1] })
  }

  const selectedDashboard = dashboards.find((d) => d.id === selectedDashboardId) ?? dashboards.find((d) => d.is_default)

  return (
    <FilterSection sticky>
      {dashboards.length > 1 && (
        <div className="filter-bar-item">
          <label className="filter-bar-label">Dashboard</label>
          <SelectDropdown
            options={dashboards.map((d) => d.label)}
            value={selectedDashboard?.label ?? ''}
            onChange={(label) => {
              const match = dashboards.find((d) => d.label === label)
              if (match) onDashboardChange(match.key)
            }}
          />
        </div>
      )}
      <div className="filter-bar-item">
        <label className="filter-bar-label">Groups</label>
        <CountryMultiSelect
          allCountries={allGroups}
          selected={state.groups}
          onChange={(groups) => onChange({ ...state, groups })}
          entityName="Groups"
        />
      </div>
      <div className="filter-bar-item">
        <label className="filter-bar-label">Countries</label>
        <CountryMultiSelect
          allCountries={allCountries}
          selected={state.countries}
          onChange={(countries) => onChange({ ...state, countries })}
          entityName="Countries"
        />
      </div>
      <div className="filter-bar-item">
        <label className="filter-bar-label">Year</label>
        <SelectDropdown
          options={allYears.map(String)}
          value={String(state.year)}
          onChange={(v) => onChange({ ...state, year: Number(v) })}
        />
      </div>
      <button type="button" className="admin-btn" onClick={reset}>
        Reset filters
      </button>
    </FilterSection>
  )
}
