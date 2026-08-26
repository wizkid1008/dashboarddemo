import { useState, useRef, useCallback } from 'react'
import { createPortal } from 'react-dom'
import { useDashletCommentsMap } from '@/contexts/DashletCommentsContext'

// ── Types ─────────────────────────────────────────────────────────────────────

interface Coords { top: number; left: number }

// ── Component ─────────────────────────────────────────────────────────────────

/**
 * Small circle-C icon rendered inline next to a dashlet title.
 * On hover/focus, shows a portal-based tooltip with the admin-authored
 * comment for this dashlet, pulled from DashletCommentsContext.
 * Renders nothing if there's no enabled comment for this permissionKey —
 * same fallback behavior as KpiInfoIcon.
 *
 * `override`, when provided, replaces the context lookup entirely — used by
 * the KPI Dashboard's preview mode to show a staged (unpublished) comment
 * edit instead of the live/published-only value everyone else sees.
 */
export function DashletCommentIcon({
  permissionKey,
  override,
}: {
  permissionKey: string
  override?: { comment: string | null; enabled: boolean }
}) {
  const comments = useDashletCommentsMap()
  const entry    = comments.get(permissionKey)
  const comment  = override ? (override.enabled ? override.comment : null) : (entry?.comment ?? null)
  const [coords, setCoords] = useState<Coords | null>(null)
  const btnRef   = useRef<HTMLButtonElement>(null)

  const show = useCallback(() => {
    if (!btnRef.current) return
    const r = btnRef.current.getBoundingClientRect()
    setCoords({ top: r.bottom + 6, left: r.left + r.width / 2 })
  }, [])

  const hide = useCallback(() => setCoords(null), [])

  if (!comment) return null

  return (
    <>
      <button
        ref={btnRef}
        type="button"
        className="dashlet-comment-btn"
        onMouseEnter={show}
        onMouseLeave={hide}
        onFocus={show}
        onBlur={hide}
        aria-label="Comment"
        tabIndex={0}
      >
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
          <text
            x="8"
            y="11"
            textAnchor="middle"
            fontSize="9"
            fontWeight="700"
            fill="currentColor"
            stroke="none"
            fontFamily="Calibri, Aptos, Arial, sans-serif"
          >
            C
          </text>
        </svg>
      </button>

      {coords && createPortal(
        <div
          className="dashlet-comment-tooltip"
          style={{ top: coords.top, left: coords.left }}
          role="tooltip"
        >
          {comment}
        </div>,
        document.body,
      )}
    </>
  )
}
