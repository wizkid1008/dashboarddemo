import { useEffect, useRef, useState } from 'react'

interface Props {
  allCountries: string[]
  selected: string[] // ['All'] means all selected
  onChange: (next: string[]) => void
  entityName?: string // e.g. 'Countries', 'Districts', 'Schools'
  singleSelect?: boolean
  hideAllOption?: boolean // hide the in-list "All X" checkbox row; top "All"/"None" links stay
  disabled?: boolean // disable the trigger entirely (e.g. parent geography not yet selected)
  disabledLabel?: string // label shown on the trigger while disabled
}

function triggerLabel(selected: string[], entityName: string): string {
  if (!selected.length || selected.includes('All')) return `All ${entityName}`
  if (selected.length === 1) return selected[0]
  return `${selected[0]} +${selected.length - 1} more`
}

export function CountryMultiSelect({ allCountries, selected, onChange, entityName = 'Countries', singleSelect = false, hideAllOption = false, disabled = false, disabledLabel }: Props) {
  const [open, setOpen] = useState(false)
  const [search, setSearch] = useState('')
  const searchRef = useRef<HTMLInputElement>(null)
  const wrapRef = useRef<HTMLDivElement>(null)

  const allChecked = selected.includes('All')

  // Close on outside click
  useEffect(() => {
    function onPointerDown(e: PointerEvent) {
      if (wrapRef.current && !wrapRef.current.contains(e.target as Node)) {
        setOpen(false)
      }
    }
    document.addEventListener('pointerdown', onPointerDown)
    return () => document.removeEventListener('pointerdown', onPointerDown)
  }, [])

  // Focus search input and clear it when dropdown opens
  useEffect(() => {
    if (open) {
      setSearch('')
      setTimeout(() => searchRef.current?.focus(), 0)
    }
  }, [open])

  function toggleAll(checked: boolean) {
    onChange(checked ? ['All'] : [])
  }

  function toggleCountry(country: string, checked: boolean) {
    if (singleSelect) {
      onChange(checked ? [country] : [])
      if (checked) setOpen(false)
      return
    }
    let next: string[]
    if (checked) {
      // Add country — remove the 'All' sentinel first
      const base = allChecked ? [] : selected.filter((c) => c !== 'All')
      next = [...base, country]
    } else {
      // Remove country — if in "All" mode, expand to full list first then subtract
      const base = allChecked ? [...allCountries] : selected.filter((c) => c !== 'All')
      next = base.filter((c) => c !== country)
    }
    // Pass the explicit selection through as-is — do not collapse a manually
    // built full/empty selection into the 'All' sentinel. Only the "All"/
    // "None" controls (toggleAll/selectAll/selectNone) set that sentinel.
    onChange(next)
  }

  function selectAll() {
    onChange(['All'])
    setOpen(false)
  }

  function selectNone() {
    // Uncheck everything — keep dropdown open so user can pick individual countries
    onChange([])
  }

  return (
    <div className="country-multi-wrap" ref={wrapRef}>
      <button
        type="button"
        className={`country-multi-trigger${open ? ' open' : ''}`}
        onClick={() => !disabled && setOpen((v) => !v)}
        disabled={disabled}
        aria-haspopup="listbox"
        aria-expanded={open}
      >
        <span>{disabled ? (disabledLabel ?? `Select a ${entityName.replace(/s$/, '')} first`) : triggerLabel(selected, entityName)}</span>
        <svg width="12" height="12" viewBox="0 0 12 12" fill="none" aria-hidden="true" style={{ flexShrink: 0, transform: open ? 'rotate(180deg)' : undefined, transition: 'transform 0.15s' }}>
          <path d="M2 4l4 4 4-4" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>

      {open && !disabled && (
        <div className="country-multi-dropdown" role="listbox" aria-multiselectable="true">
          <input
            ref={searchRef}
            className="multi-drop-search"
            type="search"
            placeholder={`Search ${entityName.toLowerCase()}…`}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
          />

          {!singleSelect && (
            <>
              <div className="multi-drop-controls">
                <div className="multi-drop-actions">
                  <button type="button" className="multi-drop-act" onClick={selectAll}>All</button>
                  <span className="multi-drop-sep">·</span>
                  <button type="button" className="multi-drop-act" onClick={selectNone}>None</button>
                </div>
              </div>

              {/* All option — only show when search is empty */}
              {!hideAllOption && !search && (
                <label className="country-multi-opt">
                  <input
                    type="checkbox"
                    checked={allChecked}
                    onChange={(e) => toggleAll(e.target.checked)}
                  />
                  <span>All {entityName}</span>
                </label>
              )}
            </>
          )}

          {allCountries
            .filter((c) => c != null && c.toLowerCase().includes(search.toLowerCase()))
            .map((c) => (
              <label key={c} className="country-multi-opt">
                <input
                  type="checkbox"
                  checked={allChecked || selected.includes(c)}
                  onChange={(e) => toggleCountry(c, e.target.checked)}
                />
                <span>{c}</span>
              </label>
            ))}
        </div>
      )}
    </div>
  )
}
