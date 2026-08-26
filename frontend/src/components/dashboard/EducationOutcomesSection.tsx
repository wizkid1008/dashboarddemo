import { useMemo, useState } from 'react'
import { FlexChart } from '@/components/charts/FlexChart'
import { ChartCard, TableCard } from '@/components/dashboard/DashboardCards'
import { KpiInfoIcon } from '@/components/KpiInfoIcon'
import { DashletCommentIcon } from '@/components/DashletCommentIcon'
import type { SectionProps } from '@/components/dashboard/DashboardCards'
import { NoData } from '@/components/dashboard/NoData'
import { ToggleGroup } from '@/components/dashboard/ToggleGroup'
import { getCountryColors } from '@/data/staticData'
import { parseKpiValue } from '@/queries/useObservedKpi'
import { useKpiSeries } from '@/queries/useKpiSeries'
import { useAuth } from '@/contexts/AuthContext'
import { useDashletData, getDashletRows } from '@/queries/useDashletData'

// Elements: 11=dropout, 12=exam lower, 13=exam upper, 14-17=promotion Form 1-4,
//           125-126=promotion Form 5-6, 18=completion lower, 19=completion upper
const ALL_ELEMENTS = [11, 12, 13, 14, 15, 16, 17, 125, 126, 18, 19]

// KPI 1.7 stores a country-neutral 'Form 1'..'Form 6' slot for every country; which grades a
// country actually uses is expressed by the value being 'Not applicable', not by rows being
// absent. These are the dashlet elements for those six slots, in order.
const FORM_ELEMENTS = [14, 15, 16, 17, 125, 126] as const

// Display-only renaming of those neutral slots. Position n names Form n+1, and the array length
// is how many columns that country shows -- Kenya genuinely stops at Form 4, Zambia at Form 5.
// A new programme country needs a line here (same pattern as PRIORITY_COUNTRIES in map.tsx);
// anything unlisted falls back to Form 1-4.
const GRADE_LABELS: Record<string, string[]> = {
  Ghana:    ['JHS1', 'JHS2', 'JHS3', 'SHS1', 'SHS2', 'SHS3'],
  Tanzania: ['Form 1', 'Form 2', 'Form 3', 'Form 4', 'Form 5', 'Form 6'],
  Uganda: ['Form 1', 'Form 2', 'Form 3', 'Form 4', 'Form 5', 'Form 6'],
  Zambia:   ['Grade 8 / Form 1', 'Grade 9 / Form 2', 'Grade 10', 'Grade 11', 'Grade 12'],
  Kenya:   ['Form 1', 'Form 2', 'Form 3', 'Form 4'],
}
const DEFAULT_GRADE_LABELS = ['Form 1', 'Form 2', 'Form 3', 'Form 4']

const gradeLabels = (country: string) => GRADE_LABELS[country] ?? DEFAULT_GRADE_LABELS

/**
 * Rate parser that keeps a real 0 distinct from a non-numeric placeholder -- unlike
 * parseKpiValue, which returns 0 for both. KPI 1.7 values are literally 'Not applicable' /
 * 'Not available' for grades a country doesn't run, and folding those to 0 makes "no such
 * grade" indistinguishable from "no SHFs progressed".
 */
function parseRate(raw: string | null | undefined): number | null {
  if (!raw) return null
  const n = parseFloat(raw.replace(/[$,£€%]/g, ''))
  return isNaN(n) ? null : n
}

export function EducationOutcomesSection({ countries, startYear, endYear }: SectionProps) {
  const [examLevel, setExamLevel] = useState<'lower' | 'upper'>('lower')
  const { hasPermission } = useAuth()

  const { data: rows = [] } = useDashletData(ALL_ELEMENTS, startYear, endYear)

  const colors = getCountryColors(countries)

  // Element 11: dropout (disagg from mapping — level_one used in useKpiSeries)
  // Still using useKpiSeries for the multiplier/fraction conversion
  const dropL1 = getDashletRows(rows, 11)[0]?.disaggregation_level_one ?? 'Annual'
  const { vals: dropVals } = useKpiSeries('1.5', countries, dropL1, startYear, endYear, { multiplier: 100 })

  // Elements 12/13: exam pass rates (lower/upper secondary)
  const examEl = examLevel === 'lower' ? 12 : 13
  const examRows = getDashletRows(rows, examEl)

  const examByCountry = useMemo(() =>
    Object.fromEntries(
      countries.map((c) => {
        const cRows = examRows.filter(r => r.country === c)
        const get = (l2: string) => {
          const r = cRows.find(r => r.disaggregation_level_two === l2)
          const v = r ? parseKpiValue(r.value) : null
          return v != null && !isNaN(v) && v > 0 ? v : null
        }
        return [c, { benchmark: get('Benchmark'), clients: get('Clients') }]
      }),
    ),
    [examRows, countries],
  )

  // Elements 14-17 / 125-126: grade promotion per form slot, indexed Form 1..Form 6.
  // Resolves to the most recent year carrying a real numeric value rather than averaging the
  // selected range. The range average folded 'Not applicable' years in as zeros (parseKpiValue
  // returns 0, never NaN, so the old !isNaN guard was a no-op), which understated every
  // country/form with a partial history -- Ghana Form 1 across 2020-2025 rendered 32.2% instead
  // of ~96%, since 2020-2023 are 'Not applicable' and only 2024-25 hold real values.
  const promotionByForm = useMemo(() =>
    FORM_ELEMENTS.map((el) => {
      const elRows = getDashletRows(rows, el)
      return Object.fromEntries(
        countries.map((c) => {
          const latest = elRows
            .filter(r => r.country === c && parseRate(r.value) != null)
            .sort((a, b) => b.year - a.year)[0]
          return [c, latest ? parseRate(latest.value) : null]
        }),
      )
    }),
    [rows, countries],
  )

  // Countries sharing a grade vocabulary share one header row (Tanzania and Uganda are both
  // plain Form 1-6), preserving the caller's country order.
  const gradeGroups = useMemo(() => {
    const groups: Array<{ labels: string[]; countries: string[] }> = []
    for (const c of countries) {
      const labels = gradeLabels(c)
      const match = groups.find(g => g.labels.join('|') === labels.join('|'))
      if (match) match.countries.push(c)
      else groups.push({ labels, countries: [c] })
    }
    return groups
  }, [countries])

  // Elements 18/19: school completion (lower/upper secondary)
  const completionRows18 = getDashletRows(rows, 18)
  const completionRows19 = getDashletRows(rows, 19)

  const hasPromotionData = promotionByForm.some(m => Object.values(m).some(v => v != null))
  const hasExamData = Object.values(examByCountry).some(d => d.benchmark != null || d.clients != null)
  const hasCompletionData = [...completionRows18, ...completionRows19].some(r =>
    countries.includes(r.country) && parseKpiValue(r.value) > 0
  )

  return (
    <div className="er-grid">
      {hasPermission('dashlet:education_outcomes:dropout_rate') && (
        <ChartCard title="Dropout Rate for SHFs with Education Bursaries (EMP)" kpiId="1.5" permissionKey="dashlet:education_outcomes:dropout_rate">
          <FlexChart
            labels={countries}
            datasets={[{ label: 'Dropout %', data: dropVals, color: colors }]}
            pct
          />
        </ChartCard>
      )}

      {hasPermission('dashlet:education_outcomes:grade_progression') && (
        <TableCard title="Progression to Next Grade" kpiId="1.7" permissionKey="dashlet:education_outcomes:grade_progression">
          {!hasPromotionData ? <NoData /> : (
            <table className="er-table">
              {gradeGroups.map(group => (
                <tbody key={group.labels.join('|')}>
                  <tr className="er-table-subhead">
                    <th>Country</th>
                    {group.labels.map(label => <th key={label}>{label}</th>)}
                  </tr>
                  {group.countries.map(c => (
                    <tr key={c}>
                      <td>{c}</td>
                      {group.labels.map((label, i) => {
                        const v = promotionByForm[i]?.[c] ?? null
                        return <td key={label}>{v != null ? (v * 100).toFixed(1) + '%' : 'n/a'}</td>
                      })}
                    </tr>
                  ))}
                </tbody>
              ))}
            </table>
          )}
        </TableCard>
      )}

      {hasPermission('dashlet:education_outcomes:exam_pass_rates') && (
        <div className="er-card">
          <div className="er-card-header">
            <span className="er-card-title-row">
              <span className="er-card-title">Exam Pass Rates</span>
              <KpiInfoIcon kpiId="1.4" />
              <DashletCommentIcon permissionKey="dashlet:education_outcomes:exam_pass_rates" />
            </span>
          </div>
          <ToggleGroup
            options={['lower', 'upper'] as const}
            labels={{ lower: 'Lower Sec.', upper: 'Upper Sec.' }}
            value={examLevel}
            onChange={setExamLevel}
            style={{ padding: '6px 16px 4px' }}
          />
          <div className="er-table-wrap">
            {!hasExamData ? <NoData /> : (
              <table className="er-table">
                <thead>
                  <tr>
                    <th>Country</th>
                    <th>Benchmark</th>
                    <th>Clients</th>
                  </tr>
                </thead>
                <tbody>
                  {countries.map(c => {
                    const d = examByCountry[c]
                    const fmtPct = (v: number | null) => v != null ? (v * 100).toFixed(1) + '%' : '—'
                    return (
                      <tr key={c}>
                        <td>{c}</td>
                        <td>{fmtPct(d?.benchmark ?? null)}</td>
                        <td>{fmtPct(d?.clients ?? null)}</td>
                      </tr>
                    )
                  })}
                </tbody>
              </table>
            )}
          </div>
        </div>
      )}

      {hasPermission('dashlet:education_outcomes:school_completion') && (
        <TableCard title="School Completion Rate" kpiId="1.8" permissionKey="dashlet:education_outcomes:school_completion">
          {!hasCompletionData ? <NoData /> : (
            <table className="er-table">
              <thead>
                <tr>
                  <th>Country</th>
                  <th>Lower Sec.</th>
                  <th>Upper Sec.</th>
                </tr>
              </thead>
              <tbody>
                {countries.map(c => {
                  const getVal = (elRows: typeof completionRows18) => {
                    const r = elRows.find(r => r.country === c)
                    const v = r ? parseKpiValue(r.value) : null
                    return v != null && !isNaN(v) && v > 0 ? (v * 100).toFixed(1) + '%' : '—'
                  }
                  return (
                    <tr key={c}>
                      <td>{c}</td>
                      <td>{getVal(completionRows18)}</td>
                      <td>{getVal(completionRows19)}</td>
                    </tr>
                  )
                })}
              </tbody>
            </table>
          )}
        </TableCard>
      )}
    </div>
  )
}
