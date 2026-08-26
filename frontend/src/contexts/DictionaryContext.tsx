import { createContext, useContext, useMemo, type ReactNode } from 'react'
import { useDataDictionary } from '@/queries/useDataDictionary'
import type { DictionaryEntry } from '@/queries/useDataDictionary'

// ── Types ─────────────────────────────────────────────────────────────────────

type DictionaryMap = Map<string, DictionaryEntry>

// ── Context ───────────────────────────────────────────────────────────────────

const DictionaryContext = createContext<DictionaryMap>(new Map())

// ── Provider ──────────────────────────────────────────────────────────────────

/**
 * Fetches the data dictionary once at app level and provides a
 * Map<kpiId, DictionaryEntry> to all child components via context.
 * Wrap the authenticated shell with this provider.
 */
export function DictionaryProvider({ children }: { children: ReactNode }) {
  const { data } = useDataDictionary()

  const map = useMemo<DictionaryMap>(() => {
    const m = new Map<string, DictionaryEntry>()
    for (const entry of (data ?? [])) {
      m.set(entry.kpi_id, entry)
    }
    return m
  }, [data])

  return (
    <DictionaryContext.Provider value={map}>
      {children}
    </DictionaryContext.Provider>
  )
}

// ── Hook ──────────────────────────────────────────────────────────────────────

export function useDictionary(): DictionaryMap {
  return useContext(DictionaryContext)
}
