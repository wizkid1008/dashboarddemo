import { useEffect, useRef, useState } from 'react'
import { createPortal } from 'react-dom'

// A per-row "⋮" trigger for tables where a row can have several actions
// (Edit/Delete/etc). Renders its menu via a document.body portal, positioned
// from the trigger's bounding rect, so it isn't clipped by a table's
// horizontal-scroll container.

interface Coords { top: number; left: number; width: number }

export interface RowAction {
  label: string
  onClick: () => void
  variant?: 'danger'
  disabled?: boolean
}

export function RowActionsMenu({ actions }: { actions: RowAction[] }) {
  const [open, setOpen] = useState(false)
  const [coords, setCoords] = useState<Coords | null>(null)
  const btnRef = useRef<HTMLButtonElement>(null)
  const menuRef = useRef<HTMLDivElement>(null)

  function openMenu() {
    if (btnRef.current) {
      const r = btnRef.current.getBoundingClientRect()
      // Right-aligned to the trigger — the table's action column sits at the
      // row's right edge, so a left-aligned menu would frequently overflow
      // the viewport.
      setCoords({ top: r.bottom + 4, left: r.right - 170, width: 170 })
    }
    setOpen(true)
  }

  useEffect(() => {
    if (!open) return
    function onPointerDown(e: PointerEvent) {
      const target = e.target as Node
      if (btnRef.current?.contains(target) || menuRef.current?.contains(target)) return
      setOpen(false)
    }
    function onScroll(e: Event) {
      if (e.target instanceof Node && menuRef.current?.contains(e.target)) return
      setOpen(false)
    }
    function onResize() { setOpen(false) }
    document.addEventListener('pointerdown', onPointerDown)
    window.addEventListener('scroll', onScroll, true)
    window.addEventListener('resize', onResize)
    return () => {
      document.removeEventListener('pointerdown', onPointerDown)
      window.removeEventListener('scroll', onScroll, true)
      window.removeEventListener('resize', onResize)
    }
  }, [open])

  return (
    <div className="row-actions-wrap">
      <button
        ref={btnRef}
        type="button"
        className={`row-actions-trigger${open ? ' open' : ''}`}
        onClick={() => (open ? setOpen(false) : openMenu())}
        aria-haspopup="menu"
        aria-expanded={open}
        aria-label="Actions"
      >
        ⋮
      </button>

      {open && coords && createPortal(
        <div
          ref={menuRef}
          className="row-actions-menu"
          style={{ position: 'fixed', top: coords.top, left: coords.left, width: coords.width }}
          role="menu"
        >
          {actions.map((a) => (
            <button
              key={a.label}
              type="button"
              role="menuitem"
              className={`row-actions-item${a.variant === 'danger' ? ' row-actions-item--danger' : ''}`}
              disabled={a.disabled}
              onClick={() => { setOpen(false); a.onClick() }}
            >
              {a.label}
            </button>
          ))}
        </div>,
        document.body,
      )}
    </div>
  )
}
