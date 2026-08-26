import { createContext, useContext, useMemo, type ReactNode } from 'react'
import { useDashletComments } from '@/queries/useDashletComments'
import type { DashletComment } from '@/queries/useDashletComments'

// ── Types ─────────────────────────────────────────────────────────────────────

type CommentsMap = Map<string, DashletComment>

// ── Context ───────────────────────────────────────────────────────────────────

const DashletCommentsContext = createContext<CommentsMap>(new Map())

// ── Provider ──────────────────────────────────────────────────────────────────

/**
 * Fetches enabled dashlet comments once at app level and provides a
 * Map<permission_key, DashletComment> to all child components via context.
 * Wrap the authenticated shell with this provider (alongside DictionaryProvider).
 */
export function DashletCommentsProvider({ children }: { children: ReactNode }) {
  const { data } = useDashletComments()

  const map = useMemo<CommentsMap>(() => {
    const m = new Map<string, DashletComment>()
    for (const entry of (data ?? [])) {
      m.set(entry.permission_key, entry)
    }
    return m
  }, [data])

  return (
    <DashletCommentsContext.Provider value={map}>
      {children}
    </DashletCommentsContext.Provider>
  )
}

// ── Hook ──────────────────────────────────────────────────────────────────────

export function useDashletCommentsMap(): CommentsMap {
  return useContext(DashletCommentsContext)
}
