import { Fragment, useState } from 'react'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'

import overviewMd from '@/content/admin-docs/overview.md?raw'
import ingestMd from '@/content/admin-docs/ingest.md?raw'
import kpisMd from '@/content/admin-docs/kpis.md?raw'
import coverageMd from '@/content/admin-docs/coverage.md?raw'
import reconMd from '@/content/admin-docs/recon.md?raw'
import usersMd from '@/content/admin-docs/users.md?raw'
import rolesMd from '@/content/admin-docs/roles.md?raw'
import dashletCommentsMd from '@/content/admin-docs/dashlet-comments.md?raw'
import whatsappMd from '@/content/admin-docs/whatsapp.md?raw'
import usageMd from '@/content/admin-docs/usage.md?raw'

const SECTIONS = [
  { key: 'overview', label: 'Overview', group: 'Getting started', content: overviewMd },
  { key: 'users', label: 'Users', group: 'Getting started', content: usersMd },
  { key: 'roles', label: 'User Roles', group: 'Getting started', content: rolesMd },
  { key: 'dashlet-comments', label: 'Dashlet Comments', group: 'Data', content: dashletCommentsMd },
  { key: 'kpis', label: 'KPI Upload', group: 'Data', content: kpisMd },
  { key: 'coverage', label: 'KPI Data Coverage', group: 'Data', content: coverageMd },
  { key: 'ingest', label: 'Salesforce Ingest', group: 'Data', content: ingestMd },
  { key: 'recon', label: 'Salesforce Recon', group: 'Data', content: reconMd },
  { key: 'whatsapp', label: 'WhatsApp', group: 'Engagement', content: whatsappMd },
  { key: 'usage', label: 'Portal Usage', group: 'Engagement', content: usageMd },
] as const

type SectionKey = (typeof SECTIONS)[number]['key']

const GROUPS = [...new Set(SECTIONS.map((s) => s.group))]

export function AdminDocsPage() {
  const [section, setSection] = useState<SectionKey>('overview')
  const active = SECTIONS.find((s) => s.key === section) ?? SECTIONS[0]

  return (
    <div className="admin-page">
      <h1 className="admin-page-title">Documentation</h1>

      <div className="admin-docs-layout">
        <nav className="admin-docs-nav" aria-label="Documentation sections">
          {GROUPS.map((group) => (
            <Fragment key={group}>
              <div className="admin-docs-nav-group">{group}</div>
              {SECTIONS.filter((s) => s.group === group).map((s) => (
                <button
                  key={s.key}
                  className={`admin-docs-nav-item${section === s.key ? ' admin-docs-nav-item--active' : ''}`}
                  onClick={() => setSection(s.key)}
                >
                  {s.label}
                </button>
              ))}
            </Fragment>
          ))}
        </nav>

        <div className="admin-docs-content">
          <ReactMarkdown remarkPlugins={[remarkGfm]}>{active.content}</ReactMarkdown>
        </div>
      </div>
    </div>
  )
}
