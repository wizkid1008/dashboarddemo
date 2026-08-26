import { useState, useRef, useCallback } from 'react'
import { createPortal } from 'react-dom'
import { useDictionary } from '@/contexts/DictionaryContext'

// ── Types ─────────────────────────────────────────────────────────────────────

interface Coords { top: number; left: number }

// ── Component ─────────────────────────────────────────────────────────────────

/**
 * Small ℹ circle icon rendered inline next to a dashlet title.
 * On hover/focus, shows a portal-based tooltip with the KPI definition
 * pulled from the DictionaryContext — bypasses any overflow:hidden on cards.
 * Renders nothing if the KPI has no definition in the dictionary.
 */
export function KpiInfoIcon({ kpiId }: { kpiId: string }) {
  const dict    = useDictionary()
  const entry   = dict.get(kpiId)
  const [coords, setCoords] = useState<Coords | null>(null)
  const btnRef  = useRef<HTMLButtonElement>(null)

  const show = useCallback(() => {
    if (!btnRef.current) return
    const r = btnRef.current.getBoundingClientRect()
    setCoords({ top: r.bottom + 6, left: r.left + r.width / 2 })
  }, [])

  const hide = useCallback(() => setCoords(null), [])

  // Render nothing if there's no definition yet (data still loading or KPI not seeded)
  if (!entry?.definition) return null

  return (
    <>
      <button
        ref={btnRef}
        type="button"
        className="kpi-info-btn"
        onMouseEnter={show}
        onMouseLeave={hide}
        onFocus={show}
        onBlur={hide}
        aria-label={`Definition: ${entry.kpi_name}`}
        tabIndex={0}
      >
        {/* Circle-i info icon, matches the 13-14px stroke style used elsewhere */}
        <svg
          width="13"
          height="13"
          viewBox="0 0 16 16"
          fill="none"
          stroke="currentColor"
          strokeWidth="1.8"
          aria-hidden="true"
        >
          <circle cx="8" cy="8" r="7" />
          <path d="M8 7.5v4.5" strokeLinecap="round" strokeLinejoin="round" />
          <circle cx="8" cy="4.5" r="1" fill="currentColor" stroke="none" />
        </svg>
      </button>

      {coords && createPortal(
        <div
          className="kpi-info-tooltip"
          style={{ top: coords.top, left: coords.left }}
          role="tooltip"
        >
          {entry.kpi_number && (
            <span className="kpi-info-tooltip-num">{entry.kpi_number}</span>
          )}
          {entry.definition}
        </div>,
        document.body,
      )}
    </>
  )
}
