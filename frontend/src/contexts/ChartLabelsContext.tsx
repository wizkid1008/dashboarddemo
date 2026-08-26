import { createContext, useContext, type ReactNode } from 'react'

const ChartLabelsContext = createContext(false)

/**
 * Wraps a page whose FlexCharts should honour a "show data labels" toggle.
 * Charts rendered outside a provider keep the default (labels off, hover only).
 */
export function ChartLabelsProvider({ show, children }: { show: boolean; children: ReactNode }) {
  return <ChartLabelsContext.Provider value={show}>{children}</ChartLabelsContext.Provider>
}

/** true when values should be printed on every bar as well as shown on hover. */
export function useChartLabels(): boolean {
  return useContext(ChartLabelsContext)
}
