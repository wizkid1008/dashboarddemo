import { EducationReachSection } from '@/components/dashboard/EducationReachSection'
import { EducationOutcomesSection } from '@/components/dashboard/EducationOutcomesSection'
import { LearnerGuideProgrammeSection } from '@/components/dashboard/LearnerGuideProgrammeSection'
import { LeadershipTertiarySection } from '@/components/dashboard/LeadershipTertiarySection'
import { LivelihoodsReachSection } from '@/components/dashboard/LivelihoodsReachSection'
import { JobsIncomeSection } from '@/components/dashboard/JobsIncomeSection'
import { AgricultureFoodSection } from '@/components/dashboard/AgricultureFoodSection'
import { LifeChoicesSection } from '@/components/dashboard/LifeChoicesSection'
import { EducationSystems1Section } from '@/components/dashboard/EducationSystems1Section'
import { EducationSystems2Section } from '@/components/dashboard/EducationSystems2Section'
import { useAuth } from '@/contexts/AuthContext'
import { sectionHasVisibleCards } from '@/data/hierarchy'
import type { SectionProps } from '@/components/dashboard/DashboardCards'
import type { DashboardData } from '@/types/dashboard'

// Sub-levels that render a custom chart view (stat cards should be hidden for these)
export const CUSTOM_CHART_SUBLEVELS = new Set([
  'Education Reach',
  'Education Outcomes',
  'Learner Guide Programme',
  'Leadership & Tertiary',
  'Livelihoods Reach',
  'Jobs & Income',
  'Agriculture & Food',
  'Life Choices',
  'Education Systems 1',
  'Education Systems 2',
  'Education Systems',
])

interface SubLevelChartsProps extends SectionProps {
  subLevel: string
  dashboardData: DashboardData
}

export function SubLevelCharts({
  subLevel,
  dashboardData,
  countries,
  startYear,
  endYear,
  period,
}: SubLevelChartsProps) {
  const { hasPermission } = useAuth()
  const props: SectionProps = { countries, startYear, endYear, period }

  if (!sectionHasVisibleCards(subLevel, hasPermission)) {
    return (
      <div className="admin-empty" style={{ padding: '48px 0', textAlign: 'center' }}>
        You do not have access to this section.
      </div>
    )
  }

  switch (subLevel) {
    case 'Education Reach':
      return <EducationReachSection {...props} />
    case 'Education Outcomes':
      return <EducationOutcomesSection {...props} />
    case 'Learner Guide Programme':
      return <LearnerGuideProgrammeSection {...props} dashboardData={dashboardData} />
    case 'Leadership & Tertiary':
      return <LeadershipTertiarySection {...props} />
    case 'Livelihoods Reach':
      return <LivelihoodsReachSection {...props} />
    case 'Jobs & Income':
      return <JobsIncomeSection {...props} />
    case 'Agriculture & Food':
      return <AgricultureFoodSection {...props} />
    case 'Life Choices':
      return <LifeChoicesSection {...props} />
    case 'Education Systems 1':
      return <EducationSystems1Section {...props} />
    case 'Education Systems 2':
      return <EducationSystems2Section {...props} />
    case 'Education Systems':
      return (
        <>
          <EducationSystems1Section {...props} />
          <div style={{ marginTop: 24 }}>
            <EducationSystems2Section {...props} />
          </div>
        </>
      )
    default:
      return null
  }
}
