export interface DashboardChartEntry {
  kpiId:     string
  section:   string
  chartName: string
  valueType?: 'count' | 'percentage' | 'currency_usd' | 'currency_local'
}

/**
 * Every KPI ID that is directly fetched and displayed in a dashboard section.
 * A KPI may appear more than once if it feeds multiple charts/sections.
 * Derived from the useObservedKpi / useKpiSeries calls in each Section.tsx file.
 */
export const DASHBOARD_CHART_REGISTRY: DashboardChartEntry[] = [
  // ── Education Reach ───────────────────────────────────────────────────────
  { kpiId: '1.1',  section: 'Education Reach',         chartName: 'SHFs Supported with Education Bursaries' },
  { kpiId: '1.2a', section: 'Education Reach',         chartName: 'SHFs Supported by CAMA' },
  { kpiId: '1.2b', section: 'Education Reach',         chartName: 'SHFs Supported by Community Champions' },
  { kpiId: 'P1',   section: 'Education Reach',         chartName: 'Total SHFs & Boys Supported' },

  // ── Education Outcomes ────────────────────────────────────────────────────
  { kpiId: '1.5',  section: 'Education Outcomes',      chartName: 'Dropout Rate',                              valueType: 'percentage' },
  { kpiId: '1.7',  section: 'Education Outcomes',      chartName: 'Grade Progression',                         valueType: 'percentage' },
  { kpiId: '1.4',  section: 'Education Outcomes',      chartName: 'Exam Pass Rates',                           valueType: 'percentage' },
  { kpiId: '1.8',  section: 'Education Outcomes',      chartName: 'School Completion Rate',                    valueType: 'percentage' },

  // ── Learner Guide Programme ───────────────────────────────────────────────
  { kpiId: '1.9',  section: 'Learner Guide Programme', chartName: 'Active Learner Guides' },
  { kpiId: '1.3',  section: 'Learner Guide Programme', chartName: 'Children Receiving SLS / My Better World' },
  { kpiId: 'R3',   section: 'Learner Guide Programme', chartName: 'Learner Guides Reporting Increased Agency',  valueType: 'percentage' },

  // ── Leadership & Tertiary ─────────────────────────────────────────────────
  { kpiId: '2.2',  section: 'Leadership & Tertiary',   chartName: 'Active Transition Guides' },
  { kpiId: '2.1',  section: 'Leadership & Tertiary',   chartName: 'CAMA Members' },
  { kpiId: '2.3',  section: 'Leadership & Tertiary',   chartName: 'Young Women Supported by Transition Guides' },
  { kpiId: '2.5',  section: 'Leadership & Tertiary',   chartName: 'Women in Tertiary Education' },
  { kpiId: '2.13', section: 'Leadership & Tertiary',   chartName: 'CAMA Members in Leadership' },

  // ── Livelihoods Reach ─────────────────────────────────────────────────────
  { kpiId: '2.2',  section: 'Livelihoods Reach',       chartName: 'Active Enterprise Guides' },
  { kpiId: '2.7',  section: 'Livelihoods Reach',       chartName: 'Businesses Supported' },
  { kpiId: '2.8a', section: 'Livelihoods Reach',       chartName: 'Business Grants' },
  { kpiId: '2.8b', section: 'Livelihoods Reach',       chartName: 'Loans' },

  // ── Jobs & Income ─────────────────────────────────────────────────────────
  { kpiId: '2.4',  section: 'Jobs & Income',           chartName: 'Women Progressing to Secure Livelihood',    valueType: 'percentage' },
  { kpiId: '2.11', section: 'Jobs & Income',           chartName: 'Female Entrepreneurs with Increased Income', valueType: 'percentage' },
  { kpiId: '2.9',  section: 'Jobs & Income',           chartName: 'Jobs Created' },
  { kpiId: '2.6',  section: 'Jobs & Income',           chartName: 'New Businesses' },

  // ── Agriculture & Food ────────────────────────────────────────────────────
  { kpiId: 'R4',   section: 'Agriculture & Food',      chartName: 'Household Food Consumption',                valueType: 'percentage' },
  { kpiId: 'R8',   section: 'Agriculture & Food',      chartName: 'Agripreneurs with Increased Yields',        valueType: 'percentage' },
  { kpiId: 'R7',   section: 'Agriculture & Food',      chartName: 'Climate-Smart Techniques' },

  // ── Life Choices ──────────────────────────────────────────────────────────
  { kpiId: '2.14', section: 'Life Choices',            chartName: 'Young Women Married by Age 18',             valueType: 'percentage' },
  { kpiId: '2.15', section: 'Life Choices',            chartName: 'Young Women Giving Birth by Age 18',        valueType: 'percentage' },

  // ── Education Systems 1 ───────────────────────────────────────────────────
  { kpiId: '3.3',  section: 'Education Systems 1',     chartName: '% Resources from Government',               valueType: 'percentage' },
  { kpiId: '3.4',  section: 'Education Systems 1',     chartName: 'Districts with Learner Guides' },
  { kpiId: '3.6',  section: 'Education Systems 1',     chartName: 'National Dropout Rate',                     valueType: 'percentage' },
  { kpiId: '3.2',  section: 'Education Systems 1',     chartName: 'Schools with Learner Guides' },

  // ── Education Systems 2 ───────────────────────────────────────────────────
  { kpiId: 'P18',  section: 'Education Systems 2',     chartName: 'Memoranda of Understanding' },
  { kpiId: '3.5',  section: 'Education Systems 2',     chartName: 'Children Benefitting from Improved Learning' },
  { kpiId: 'P6',   section: 'Education Systems 2',     chartName: 'Active Community Champions' },
]

/** Quick lookup: kpiId → all matching dashboard chart entries */
export const DASHBOARD_BY_KPI = new Map<string, DashboardChartEntry[]>()
for (const entry of DASHBOARD_CHART_REGISTRY) {
  const list = DASHBOARD_BY_KPI.get(entry.kpiId) ?? []
  list.push(entry)
  DASHBOARD_BY_KPI.set(entry.kpiId, list)
}
