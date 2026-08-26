import { createContext, useContext, type ReactNode } from 'react'

export interface TargetRow {
  dashlet_element: number
  country: string
  target_value: number
}

interface TargetsCtx {
  rows: TargetRow[]
}

const TargetsContext = createContext<TargetsCtx | null>(null)

export function TargetsProvider({ rows, children }: { rows: TargetRow[]; children: ReactNode }) {
  return <TargetsContext.Provider value={{ rows }}>{children}</TargetsContext.Provider>
}

/**
 * Per-country target values summed across the given dashlet elements, in one hook call.
 * Returns undefined if no TargetsProvider is mounted, no elements were passed, or every
 * value is zero (targets toggled off, or a cumulative period where targets don't apply) --
 * in each case the caller draws no target line.
 *
 * This takes an element array rather than a single element deliberately: a card built from a
 * variable number of elements can't call a per-element hook once per element -- the hook count
 * would change between renders as its period/toggle resolves to different element sets, which
 * React forbids. Reading the context once and summing keeps the hook count fixed at one
 * however many elements are passed.
 *
 * Summing the rows is equivalent to summing the per-element results the callers used to
 * compute by hand (`agTargets.map((v, i) => v + (bizTargets[i] ?? 0))`), including the
 * "undefined when nothing has a target" behaviour -- an element with no target rows simply
 * contributes nothing.
 */
export function useTargetValuesFor(elements: number[], countries: string[]): number[] | undefined {
  const ctx = useContext(TargetsContext)
  if (!ctx || !elements.length) return undefined
  const vals = countries.map(c =>
    ctx.rows
      .filter(r => elements.includes(r.dashlet_element) && r.country === c)
      .reduce((s, r) => s + r.target_value, 0),
  )
  return vals.some(v => v > 0) ? vals : undefined
}
