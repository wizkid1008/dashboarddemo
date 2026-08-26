import { useState } from 'react'

/**
 * Wraps the hero filter bar with a mobile-collapse toggle.
 * On desktop (> 600px): filters always visible, toggle hidden.
 * On mobile (≤ 600px): toggle button shown; filters collapsed by default.
 */
export function FilterSection({ children, sticky = false }: { children: React.ReactNode; sticky?: boolean }) {
  const [open, setOpen] = useState(false)

  return (
    <section className={`hero-section${sticky ? ' hero-section--sticky' : ''}`}>
      <button
        type="button"
        className="filters-toggle-btn"
        onClick={() => setOpen((o) => !o)}
        aria-expanded={open}
      >
        <svg width="16" height="16" viewBox="0 0 20 20" fill="none" aria-hidden="true">
          <path d="M3 5h14M5 10h10M8 15h4" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
        </svg>
        Filters
        <svg
          width="14"
          height="14"
          viewBox="0 0 20 20"
          fill="none"
          aria-hidden="true"
          style={{ marginLeft: 'auto', transition: 'transform 0.2s', transform: open ? 'rotate(180deg)' : 'none' }}
        >
          <path d="M5 8l5 5 5-5" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>

      <div className={`hero-filters${open ? ' hero-filters--open' : ''}`}>
        {children}
      </div>
    </section>
  )
}
