export interface StatisticDefinition {
  label: string
  kpi?: string
  pct?: boolean
  ddMetric?: string
  // Cumulative disaggregation variants stored in the DB for specific years only.
  // These are populated for the most recent data year when a cumulative period is selected.
  ddMetricCumulative2020?: string
  ddMetricCumulative2024?: string
  ddMetricCumulativeAllTime?: string
  kpiSum?: string[]
  kpiRatio?: {
    n: string
    d: string
  }
}

export interface HierarchyEntry {
  level: string
  subLevel: string
  statistics: StatisticDefinition[]
}

// All card-level dashlet permission keys grouped by sub-level.
// Used to determine whether a section (and, by extension, its level) has any
// dashlet the current user is permitted to see.
export const SECTION_CARD_KEYS: Record<string, string[]> = {
  'Education Reach': [
    'dashlet:education_reach:bursaries',
    'dashlet:education_reach:cama_community',
    'dashlet:education_reach:total_girls',
    'dashlet:education_reach:total_boys',
  ],
  'Education Outcomes': [
    'dashlet:education_outcomes:dropout_rate',
    'dashlet:education_outcomes:grade_progression',
    'dashlet:education_outcomes:exam_pass_rates',
    'dashlet:education_outcomes:school_completion',
  ],
  'Learner Guide Programme': [
    'dashlet:learner_guide:active_guides',
    'dashlet:learner_guide:guides_by_training',
    'dashlet:learner_guide:children_sls',
  ],
  'Leadership & Tertiary': [
    'dashlet:leadership_tertiary:transition_guides',
    'dashlet:leadership_tertiary:cama_members',
    'dashlet:leadership_tertiary:young_women_tg',
    'dashlet:leadership_tertiary:women_tertiary',
    'dashlet:leadership_tertiary:cama_leadership',
  ],
  'Livelihoods Reach': [
    'dashlet:livelihoods_reach:enterprise_guides',
    'dashlet:livelihoods_reach:businesses_supported',
    'dashlet:livelihoods_reach:business_grants',
    'dashlet:livelihoods_reach:loans',
  ],
  'Jobs & Income': [
    'dashlet:jobs_income:women_livelihood',
    'dashlet:jobs_income:entrepreneurs_income',
    'dashlet:jobs_income:jobs_created',
    'dashlet:jobs_income:new_businesses',
  ],
  'Agriculture & Food': [
    'dashlet:agriculture_food:food_consumption',
    'dashlet:agriculture_food:increased_yields',
    'dashlet:agriculture_food:climate_techniques',
  ],
  'Life Choices': [
    'dashlet:life_choices:married_by_18',
    'dashlet:life_choices:birth_by_18',
  ],
  'Education Systems 1': [
    'dashlet:education_systems_1:districts_with_lg',
    'dashlet:education_systems_1:schools_with_lg',
  ],
  'Education Systems 2': [
    'dashlet:education_systems_2:mou',
    'dashlet:education_systems_2:community_champions',
    'dashlet:education_systems_2:children_learning',
  ],
  'Education Systems': [
    'dashlet:education_systems_1:districts_with_lg',
    'dashlet:education_systems_1:schools_with_lg',
    'dashlet:education_systems_2:mou',
    'dashlet:education_systems_2:community_champions',
    'dashlet:education_systems_2:children_learning',
  ],
}

export function sectionHasVisibleCards(subLevel: string, hasPermission: (key: string) => boolean): boolean {
  const cardKeys = SECTION_CARD_KEYS[subLevel]
  return !cardKeys || cardKeys.some(k => hasPermission(k))
}

export const hierarchyData: HierarchyEntry[] = [
  {
    level: "LEVEL 1: SHF's Education",
    subLevel: 'Education Reach',
    statistics: [
      {
        label: '# SHFs supported in School with Education Bursaries',
        kpi: 'kpi11.annual.total',
        ddMetric: 'Children Supported in School with Education Bursaries',
        ddMetricCumulative2020: 'Children Supported in School with Education Bursaries — Cumulative 2020-2030',
        ddMetricCumulative2024: 'Children Supported in School with Education Bursaries — Cumulative 2024-2030',
        ddMetricCumulativeAllTime: 'Children Supported in School with Education Bursaries — Cumulative all-time',
      },
      {
        label: '# SHFs Supported in School by CAMA & Community Champions',
        kpi: 'kpi12.annual.total',
        ddMetric: 'CAMA Members',
      },
      { label: '# Total SHFs Supported', kpi: 'kpi13.annual.girls' },
      { label: '# Total Boys Supported', kpi: 'kpi13.annual.boys' },
    ],
  },
  {
    level: "LEVEL 1: SHF's Education",
    subLevel: 'Education Outcomes',
    statistics: [
      {
        label: 'Dropout Rate for SHFs with Education Bursaries due to EMP',
        kpi: 'kpi15.pct',
        pct: true,
      },
      { label: 'SHFs with Education Bursaries that Progress to Next Grade' },
      { label: 'Exam Passrates for SHFs with Busaries' },
      { label: 'School Completion Rates for SHFs with busaries' },
    ],
  },
  {
    level: "LEVEL 1: SHF's Education",
    subLevel: 'Learner Guide Programme',
    statistics: [
      {
        label: 'Active Learner Guides',
        kpi: 'kpi19.total',
        ddMetric: 'Active Learner Guides',
      },
      { label: 'SHFs Reporting Increased Agency' },
      { label: 'Learner Guides Reporting Increased Agency' },
      { label: 'Average number of children my better world annually' },
      {
        label: 'Active Learner Guides by Training',
        kpi: 'kpi19.camfed',
        ddMetric: 'Active Learner Guides',
      },
      {
        label: 'Children Receieving Social and Learning Support Including My Better World Sessions',
        kpi: 'kpi13.annual.total',
        ddMetric: 'Number of Clients by Form',
      },
    ],
  },
  {
    level: 'LEVEL 2: Livelihoods & Leadership',
    subLevel: 'Leadership & Tertiary',
    statistics: [
      { label: 'Active Transition Guides', kpi: 'kpi22.transition' },
      { label: 'Numbers of CAMA Members', kpi: 'kpi21.cum' },
      { label: 'Young Women Supported by Transition Guide', kpi: 'kpi213.num' },
      { label: 'Young Women Supported by SHF Agriculture Tertiary Education' },
      { label: 'CAMA Members in Leadership Roles' },
    ],
  },
  {
    level: 'LEVEL 2: Livelihoods & Leadership',
    subLevel: 'Livelihoods Reach',
    statistics: [
      {
        label: 'Active Enerperis Guides (Business & Agriculture Guides)',
        kpiSum: ['kpi22.business', 'kpi22.agriculture'],
      },
      { label: 'Business Supported by Enterprise Guides', kpi: 'kpi27.biz' },
      { label: 'Business Grants Distributed' },
      { label: 'SHF Agriculture KIVA and RIF Loans Distributed' },
    ],
  },
  {
    level: 'LEVEL 2: Livelihoods & Leadership',
    subLevel: 'Jobs & Income',
    statistics: [
      { label: 'Women Progresing Towards a secure livelihood' },
      {
        label: "Females Entrepreeurs with increased incomes after participating in SHF Agriculture's ENteprise Programs",
        kpi: 'kpi210.pct',
        pct: true,
      },
      {
        label: 'Jobs Created through Enterprise Programme including Self Employment',
        kpi: 'kpi29.annual',
      },
      { label: 'New Business' },
      { label: 'Business Survival Rate', kpi: 'kpi212.yr1', pct: true },
    ],
  },
  {
    level: 'LEVEL 2: Livelihoods & Leadership',
    subLevel: 'Agriculture & Food',
    statistics: [
      {
        label: "Percentage of Femal Entrepenuers Reporting and Increased Household Consumption fo Food Since Participating in SHF Agriculture's Enteprise Program",
      },
      {
        label: 'Percentage of FEmals Agripernuers Reporting Increased Yields Since Participating',
      },
      {
        label: 'Average Number of Climate-Smart Techniques Used by Those Receiieng Support from an Agriculture Guide',
      },
    ],
  },
  {
    level: 'LEVEL 2: Livelihoods & Leadership',
    subLevel: 'Life Choices',
    statistics: [
      { label: 'Average of Young Women Married by Age 18 Across All Countries' },
      { label: 'Average of Young Women Giving Birth by Age 18' },
      { label: 'Percentrage of Young Women in CAMA who Were Married by 18' },
      { label: 'Percentage of Young Women CAMA Who have Given Birth by 18' },
    ],
  },
  {
    level: 'LEVEL 3: Education Systems',
    subLevel: 'Education Systems',
    statistics: [
      {
        label: '% of Resources for Learner Guide Programme Contributed by the Government',
        kpiRatio: { n: 'kpi19.govt', d: 'kpi19.total' },
      },
      {
        label: 'National Level Dropout Rate for SHFs due to Early Marriage or Pregnancy',
        kpi: 'kpi15.pct',
        pct: true,
      },
      { label: 'Community Champion Teacher Mentors' },
      { label: 'Number of Districts with Learner Guides', kpi: 'kpi34.districts' },
      { label: 'Number of Schools with Learner Guides', kpi: 'kpi31.total_all' },
      { label: 'Number of Memoranda of Understanding between Government Departments and SHF Agriculture' },
      {
        label: 'Children Benefiting from Improved Learning Environment',
        kpi: 'kpi35.total',
      },
      { label: "Number of Active Community Champions for SHF's Education" },
    ],
  },
]
