import { useState } from 'react'
import {
  useDashletCommentsAdmin, useSetDashletCommentDirect,
  type DashletCommentEditRow,
} from '@/features/admin/queries'

const UNGROUPED_LABEL = 'Ungrouped'

function groupRows(rows: DashletCommentEditRow[]) {
  const groups = new Map<string, DashletCommentEditRow[]>()
  for (const row of rows) {
    const key = row.group_name ?? UNGROUPED_LABEL
    if (!groups.has(key)) groups.set(key, [])
    groups.get(key)!.push(row)
  }
  return groups
}

function CommentRow({ row }: { row: DashletCommentEditRow }) {
  const [comment, setComment] = useState(row.comment ?? '')
  const [enabled, setEnabled] = useState(row.comment_enabled)
  const [showSaved, setShowSaved] = useState(false)
  const save = useSetDashletCommentDirect()

  function handleSave() {
    save.mutate(
      { permissionKey: row.permission_key, comment: comment.trim() === '' ? null : comment, isEnabled: enabled },
      {
        onSuccess: () => {
          setShowSaved(true)
          setTimeout(() => setShowSaved(false), 2200)
        },
      },
    )
  }

  return (
    <li style={{ background: 'var(--white)', border: '1.5px solid var(--border)', borderRadius: 'var(--radius-sm)', padding: '16px 20px' }}>
      <div style={{ fontWeight: 600, fontSize: '0.95rem', marginBottom: 10 }}>{row.label}</div>
      <textarea
        className="admin-input"
        style={{ width: '100%', minHeight: 60, resize: 'vertical', marginBottom: 10 }}
        placeholder="No comment set"
        value={comment}
        onChange={(e) => setComment(e.target.value)}
      />
      <div style={{ display: 'flex', alignItems: 'center', gap: 14 }}>
        <label style={{ display: 'inline-flex', alignItems: 'center', gap: 7, fontSize: '0.85rem', color: 'var(--text-light)', cursor: 'pointer' }}>
          <input type="checkbox" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} />
          Show on dashboard
        </label>
        <span style={{ flex: 1 }} />
        {showSaved && <span className="admin-success" style={{ padding: '4px 10px' }}>Saved ✓</span>}
        {save.isError && <span className="admin-error" style={{ padding: '4px 10px' }}>Failed to save</span>}
        <button className="admin-btn admin-btn--primary" onClick={handleSave} disabled={save.isPending}>
          {save.isPending ? 'Saving…' : 'Save'}
        </button>
      </div>
    </li>
  )
}

export function AdminDashletCommentsPage() {
  const { data, isLoading, isError } = useDashletCommentsAdmin()

  return (
    <div className="admin-page">
      <div className="admin-page-header">
        <h1 className="admin-page-title">Dashlet Comments</h1>
      </div>

      <p className="admin-muted" style={{ marginBottom: 24, lineHeight: 1.5 }}>
        <strong style={{ color: 'var(--text)' }}>Edits publish straight to the live dashboard.</strong>{' '}
        Each group below matches its sub-level on the dashboard.
      </p>

      {isLoading && <p className="admin-muted">Loading…</p>}
      {isError && <p className="admin-error">Failed to load dashlets.</p>}

      {data && Array.from(groupRows(data)).map(([groupName, rows]) => (
        <div key={groupName} style={{ marginBottom: 32 }}>
          <h2 className="admin-section-title" style={{ margin: '0 0 12px' }}>{groupName}</h2>
          <ul style={{ listStyle: 'none', margin: 0, padding: 0, display: 'flex', flexDirection: 'column', gap: 12 }}>
            {rows.map((row) => (
              <CommentRow key={row.permission_key} row={row} />
            ))}
          </ul>
        </div>
      ))}
    </div>
  )
}
