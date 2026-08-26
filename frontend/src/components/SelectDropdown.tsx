import { useEffect, useRef, useState } from 'react'

interface Props {
  options: string[]
  value: string
  onChange: (value: string) => void
  placeholder?: string
  disabled?: boolean
}

export function SelectDropdown({ options, value, onChange, placeholder = 'Select…', disabled = false }: Props) {
  const [open, setOpen] = useState(false)
  const wrapRef = useRef<HTMLDivElement>(null)

  useEffect(() => {
    function onPointerDown(e: PointerEvent) {
      if (wrapRef.current && !wrapRef.current.contains(e.target as Node)) {
        setOpen(false)
      }
    }
    document.addEventListener('pointerdown', onPointerDown)
    return () => document.removeEventListener('pointerdown', onPointerDown)
  }, [])

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
        <span>{value || placeholder}</span>
        <svg width="12" height="12" viewBox="0 0 12 12" fill="none" aria-hidden="true" style={{ flexShrink: 0, transform: open ? 'rotate(180deg)' : undefined, transition: 'transform 0.15s' }}>
          <path d="M2 4l4 4 4-4" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>

      {open && (
        <div className="country-multi-dropdown" role="listbox">
          {options.map((opt) => (
            <label
              key={opt}
              className={`country-multi-opt select-dropdown-opt${value === opt ? ' select-dropdown-opt--active' : ''}`}
              onClick={() => { onChange(opt); setOpen(false) }}
            >
              <span>{opt}</span>
            </label>
          ))}
        </div>
      )}
    </div>
  )
}
