// ── Education Reach ───────────────────────────────────────────────────────────
/** Toggle states shared by the Education Reach dashlets and their label maps. */
export type BurType = 'newly' | 'annual' | 'cum2030' | 'cumall'

export const BUR_LABELS: Record<BurType, string> = {
  newly:   'Newly Supported',
  annual:  'Annual Total',
  cum2030: 'Since 2020',
  cumall:  'Cumulative All-time',
}

// ── Learner Guide Programme ───────────────────────────────────────────────────
export type LgBurType = 'annual' | 'cum2030' | 'newly' | 'cumall'

export const LG_BUR_LABEL: Record<LgBurType, string> = {
  annual:  'Annual',
  cum2030: 'Since 2020',
  newly:   'Newly trained',
  cumall:  'Cumulative (all-time)',
}

// ── Leadership & Tertiary ─────────────────────────────────────────────────────
export type LtBurType = 'annual' | 'newly'

export const LT_BUR_LABEL: Record<LtBurType, string> = {
  annual: 'Annual',
  newly:  'Newly Supported',
}

// ── Livelihoods Reach ─────────────────────────────────────────────────────────
export type LrBurType = 'annual' | 'newly' | 'cum2030' | 'cumall'

export const LR_BUR_LABEL: Record<LrBurType, string> = {
  annual:  'Annual',
  newly:   'Newly Supported',
  cum2030: 'Since 2020',
  cumall:  'Cumulative (all-time)',
}

// ── Livelihoods Reach: Businesses Supported ──────────────────────────────────
// This KPI (2.7) only has Annual and Cumulative-since-2020 kpi_mapping rows -- no
// Newly-supported or all-time variant exists.
export type BsBurType = 'annual' | 'cum2030'

export const BS_BUR_LABEL: Record<BsBurType, string> = {
  annual:  'Annual',
  cum2030: 'Since 2020',
}
