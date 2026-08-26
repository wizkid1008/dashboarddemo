import { useState, useEffect, useRef } from 'react'
import { useDataDictionary } from '@/queries/useDataDictionary'
import type { DictionaryEntry } from '@/queries/useDataDictionary'

// ── Types ─────────────────────────────────────────────────────────────────────

export type PanelType = 'guides' | 'dictionary'

interface ResourcePanelProps {
  panel:   PanelType
  onClose: () => void
}

// ── Guides content ────────────────────────────────────────────────────────────

type GuideTab = 'dashboard' | 'dynamic' | 'map'

const GUIDE_TABS: { id: GuideTab; label: string }[] = [
  { id: 'dashboard', label: 'Data Dashboard' },
  { id: 'dynamic',   label: 'Dynamic Data'   },
  { id: 'map',       label: 'Data Map'       },
]

interface GuideStep { title: string; desc: string }
interface GuideContent { steps: GuideStep[]; tip?: string }

const GUIDE_CONTENT: Record<GuideTab, GuideContent> = {
  dashboard: {
    steps: [
      { title: 'Select a Level',           desc: 'Choose a programme area from the Level dropdown — SHFs\' Education, Livelihoods & Leadership, or Education Systems.' },
      { title: 'Select a Sub Level',       desc: 'Narrow to a specific focus within your chosen level using the Sub Level dropdown.' },
      { title: 'Choose a Year or Period',  desc: 'Pick an individual year for a snapshot, or a cumulative period (e.g. since 2020) to see totals over time.' },
      { title: 'Select a Country',         desc: 'Filter to one or more countries, or leave as All Countries to view the full picture.' },
    ],
  },
  dynamic: {
    steps: [
      { title: 'Select a Country',             desc: 'Choose one or more countries from the Country dropdown to scope your query.' },
      { title: 'Filter by District or School', desc: 'Optionally drill down to specific districts or schools within your country selection.' },
      { title: 'Set the Year Range',           desc: 'Use Start Year and End Year to define the period you want to analyse.' },
      { title: 'Click Run',                    desc: 'Charts do not update automatically — press Run to fetch and display data for your selection.' },
    ],
  },
  map: {
    steps: [
      { title: 'Select a Layer',       desc: 'Choose Country, District, or School to control what level of geography is shown on the map.' },
      { title: 'Filter the Geography', desc: 'Use the Country, District, and School dropdowns to zoom the map to specific places.' },
      { title: 'Choose a KPI',         desc: 'The map colours, legend, and inspector summary update based on the selected KPI.' },
      { title: 'Hover for Details',    desc: 'Hover over any country, district, or school to see details in the Inspector panel on the right.' },
    ],
  },
}

function GuidesContent() {
  const [activeTab, setActiveTab] = useState<GuideTab>('dashboard')
  const { steps, tip } = GUIDE_CONTENT[activeTab]

  return (
    <div className="rpanel-guides">
      <div className="rpanel-tabs" role="tablist">
        {GUIDE_TABS.map(tab => (
          <button
            key={tab.id}
            role="tab"
            aria-selected={activeTab === tab.id}
            className={`rpanel-tab${activeTab === tab.id ? ' rpanel-tab--active' : ''}`}
            onClick={() => setActiveTab(tab.id)}
          >
            {tab.label}
          </button>
        ))}
      </div>

      <div className="rpanel-steps" role="tabpanel">
        {steps.map((step, i) => (
          <div key={i} className="rpanel-step">
            <span className="rpanel-step-num">{i + 1}</span>
            <div className="rpanel-step-body">
              <strong>{step.title}</strong>
              <span>{step.desc}</span>
            </div>
          </div>
        ))}

        {tip && (
          <div className="rpanel-tip">
            <span className="rpanel-tip-arrow">→</span>
            <span>{tip}</span>
          </div>
        )}
      </div>
    </div>
  )
}

// ── Dictionary content ────────────────────────────────────────────────────────

function DictionaryContent() {
  const { data, isLoading, error } = useDataDictionary()
  const [search, setSearch] = useState('')

  const entries: DictionaryEntry[] = data ?? []

  const filtered = search.trim()
    ? entries.filter(e =>
        e.kpi_name.toLowerCase().includes(search.toLowerCase()) ||
        (e.kpi_number ?? '').toLowerCase().includes(search.toLowerCase()) ||
        (e.definition ?? '').toLowerCase().includes(search.toLowerCase()) ||
        (e.kpi_group ?? '').toLowerCase().includes(search.toLowerCase())
      )
    : entries

  // Group by kpi_group, then sort each group by kpi_number numerically
  // (e.g. 2.9 < 2.11 < 2.13, P1 < P6 < P18)
  const numericSort = (a: DictionaryEntry, b: DictionaryEntry) =>
    (a.kpi_number ?? '').localeCompare(b.kpi_number ?? '', undefined, { numeric: true })

  const groups = filtered.reduce<Record<string, DictionaryEntry[]>>((acc, e) => {
    const g = e.kpi_group ?? 'Other'
    ;(acc[g] ??= []).push(e)
    return acc
  }, {})

  for (const g of Object.keys(groups)) {
    groups[g].sort(numericSort)
  }

  return (
    <div className="rpanel-dict">
      <div className="rpanel-dict-search-wrap">
        <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.8" aria-hidden="true">
          <circle cx="6.5" cy="6.5" r="5" />
          <path d="M10.5 10.5L14 14" strokeLinecap="round" />
        </svg>
        <input
          className="rpanel-dict-search"
          type="search"
          placeholder="Search KPI name, number, or definition…"
          value={search}
          onChange={e => setSearch(e.target.value)}
          autoFocus
        />
      </div>

      {isLoading && <p className="rpanel-dict-status">Loading…</p>}
      {error   && <p className="rpanel-dict-status rpanel-dict-status--error">Failed to load dictionary.</p>}

      {!isLoading && filtered.length === 0 && (
        <p className="rpanel-dict-status">No entries match "{search}".</p>
      )}

      {Object.entries(groups).map(([group, items]) => (
        <div key={group} className="rpanel-dict-group">
          <div className="rpanel-dict-group-label">{group}</div>
          {items.map(entry => (
            <div key={entry.kpi_id} className="rpanel-dict-entry">
              <div className="rpanel-dict-entry-header">
                <span className="rpanel-dict-name">{entry.kpi_name}</span>
                {entry.kpi_number && (
                  <span className="rpanel-dict-number">{entry.kpi_number}</span>
                )}
              </div>
              {entry.definition && (
                <p className="rpanel-dict-def">{entry.definition}</p>
              )}
            </div>
          ))}
        </div>
      ))}
    </div>
  )
}

// ── Panel shell ───────────────────────────────────────────────────────────────

export function ResourcePanel({ panel, onClose }: ResourcePanelProps) {
  const panelRef = useRef<HTMLDivElement>(null)

  // Close on Escape
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => { if (e.key === 'Escape') onClose() }
    document.addEventListener('keydown', onKey)
    return () => document.removeEventListener('keydown', onKey)
  }, [onClose])

  // Trap focus loosely — just focus the panel on open
  useEffect(() => { panelRef.current?.focus() }, [])

  const title = panel === 'guides' ? 'Guides & Documentation' : 'Data Dictionary'

  return (
    <>
      {/* Backdrop */}
      <div className="rpanel-backdrop" onClick={onClose} aria-hidden="true" />

      {/* Panel */}
      <div
        ref={panelRef}
        className="rpanel"
        role="dialog"
        aria-modal="true"
        aria-label={title}
        tabIndex={-1}
      >
        <div className="rpanel-header">
          <h2 className="rpanel-title">{title}</h2>
          <button className="rpanel-close" onClick={onClose} aria-label="Close">
            <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
              <path d="M4 4l8 8M12 4l-8 8" strokeLinecap="round" />
            </svg>
          </button>
        </div>

        <div className="rpanel-body">
          {panel === 'guides'     && <GuidesContent />}
          {panel === 'dictionary' && <DictionaryContent />}
        </div>
      </div>
    </>
  )
}
