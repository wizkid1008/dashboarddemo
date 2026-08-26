import type { CSSProperties } from 'react'

interface ToggleGroupProps<T extends string> {
  options: readonly T[]
  labels: Record<T, string>
  value: T
  onChange: (v: T) => void
  variant?: 'button' | 'radio'
  name?: string
  style?: CSSProperties
  disabled?: boolean
}

export function ToggleGroup<T extends string>({
  options, labels, value, onChange, variant = 'button', name, style, disabled,
}: ToggleGroupProps<T>) {
  if (variant === 'radio') {
    return (
      <div className="er-radio-group" style={style}>
        {options.map((t) => (
          <label key={t} className="er-radio-opt">
            <input type="radio" name={name} value={t} checked={value === t} onChange={() => onChange(t)} disabled={disabled} />{' '}
            {labels[t]}
          </label>
        ))}
      </div>
    )
  }
  return (
    <div className="chart-type-toggle" style={style}>
      {options.map((t) => (
        <button key={t} type="button" className={`chart-toggle-btn${value === t ? ' active' : ''}`} onClick={() => onChange(t)} disabled={disabled}>
          {labels[t]}
        </button>
      ))}
    </div>
  )
}
