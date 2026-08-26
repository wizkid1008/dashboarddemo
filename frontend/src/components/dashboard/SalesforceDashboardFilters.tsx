import { CountryMultiSelect } from '@/components/CountryMultiSelect'
import { SelectDropdown } from '@/components/SelectDropdown'
import { FilterSection } from '@/components/FilterSection'
import type { DashboardConfig } from '@/features/dashboards/queries'

export interface SalesforceDashboardFilterState {
  groups: string[] // ['All'] means all groups
  countries: string[] // ['All'] means all countries
  yearStart: number
  yearEnd: number
}

// Defaults to the current calendar year when the underlying data actually
// has it; otherwise falls back to the latest year present (allYears[0] —
// callers pass it sorted descending) rather than defaulting to a year with
// no data to show.
export function defaultSalesforceYear(allYears: number[]): number {
  const currentYear = new Date().getFullYear()
  return allYears.includes(currentYear) ? currentYear : (allYears[0] ?? 0)
}

export function SalesforceDashboardFilters({
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
  state: SalesforceDashboardFilterState
  onChange: (next: SalesforceDashboardFilterState) => void
  // Only rendered once there's more than one Salesforce dashboard to choose
  // from — with a single (the default) dashboard, a switcher has nothing to add.
  dashboards: DashboardConfig[]
  selectedDashboardId: number | null
  onDashboardChange: (key: string) => void
}) {
  function reset() {
    const year = defaultSalesforceYear(allYears)
    onChange({ groups: ['All'], countries: ['All'], yearStart: year, yearEnd: year })
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
        <label className="filter-bar-label">Start Year</label>
        <SelectDropdown
          options={allYears.filter((y) => y <= state.yearEnd).map(String)}
          value={String(state.yearStart)}
          onChange={(v) => onChange({ ...state, yearStart: Number(v) })}
        />
      </div>
      <div className="filter-bar-item">
        <label className="filter-bar-label">End Year</label>
        <SelectDropdown
          options={allYears.filter((y) => y >= state.yearStart).map(String)}
          value={String(state.yearEnd)}
          onChange={(v) => onChange({ ...state, yearEnd: Number(v) })}
        />
      </div>
      <button type="button" className="admin-btn" onClick={reset}>
        Reset filters
      </button>
    </FilterSection>
  )
}
