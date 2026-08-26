// Brand colour palette and per-country colour assignment, shared by the Data Dashboard
// sublevel chart sections, the slicer, and the map.

// Official SHF Agriculture brand palette — Pantone refs in brand guidelines
export const MAP_LEVEL_COLORS = ['#0D4F6C', '#D9A441', '#D8752C', '#1E7896', '#6FA641']
// [0] SHF Agriculture Deep Blue  [1] SHF Agriculture Harvest Gold  [2] SHF Agriculture Warm Orange  [3] SHF Agriculture Sky Blue  [4] SHF Agriculture Leaf Green

// Fixed per-country colors (SHF Agriculture brand palette, including Chocolate as the 6th brand color)
// so each programme country always renders in the same color across every Data Dashboard
// dashlet, regardless of selection order -- previously colors were assigned by array index
// (countries.map((_, i) => MAP_LEVEL_COLORS[i % MAP_LEVEL_COLORS.length])), so Ghana would
// render purple only when selected first; selecting Kenya first would make Kenya purple instead.
// Named distinctly from DashletChartBodies.tsx's COUNTRY_COLORS (an unrelated positional array
// used by the separate Salesforce Dashboard page) to avoid confusion between the two.
const DASHBOARD_COUNTRY_COLORS: Record<string, string> = {
  Ghana:    '#0D4F6C', // SHF Agriculture Deep Blue
  Kenya:    '#D9A441', // SHF Agriculture Harvest Gold
  Malawi:   '#D8752C', // SHF Agriculture Warm Orange
  Tanzania: '#1E7896', // SHF Agriculture Sky Blue
  Zambia:   '#6FA641', // SHF Agriculture Leaf Green
  Zimbabwe: '#243238', // SHF Agriculture Charcoal
}

// Fallback cycle for any country not in DASHBOARD_COUNTRY_COLORS (e.g. a future programme
// country added before its brand color is assigned).
const FALLBACK_COUNTRY_COLORS = MAP_LEVEL_COLORS

export function getCountryColor(country: string, fallbackIndex = 0): string {
  return DASHBOARD_COUNTRY_COLORS[country] ?? FALLBACK_COUNTRY_COLORS[fallbackIndex % FALLBACK_COUNTRY_COLORS.length]
}

export function getCountryColors(countries: string[]): string[] {
  return countries.map((c, i) => getCountryColor(c, i))
}
