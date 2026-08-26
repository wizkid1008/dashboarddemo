import { useState, useMemo } from 'react'
import {
  usePermissions, useRoles, useCreateRole, useUpdateRole, useDeleteRole, useAllDashletGroups,
  type Permission, type Role,
} from '@/features/admin/queries'
import { AdminDataTable, type AdminColumn } from '@/features/admin/components/AdminDataTable'

// ── Helpers ───────────────────────────────────────────────────────────────────

const UNGROUPED_LABEL = 'Ungrouped'

// Groups dashlet permissions by their dashlet_groups row (group_name) — the
// same grouping the Dashlet Comments admin page uses (see groupRows() in
// dashlet-comments.tsx) — so section naming stays consistent across both
// pages instead of drifting apart via a separately-maintained key.
function groupByDashletGroup(permissions: Permission[]) {
  const filtered = permissions.filter((p) => p.category === 'dashlet')
  const groups = new Map<string, Permission[]>()
  for (const p of filtered) {
    // parent_key wins over group_name (not just a fallback for permissions
    // with no dashlets row, like dd:metric:*) so a permission's parent_key
    // can deliberately override its dashlet_groups display name on this
    // page only — e.g. the legacy dd:* "Map" relabel — without touching the
    // shared dashlet_groups row other pages (Dashlet Comments, the Dashlets
    // editor, the live dashboard) read directly.
    const group = p.parent_key ?? p.group_name ?? UNGROUPED_LABEL
    if (!groups.has(group)) groups.set(group, [])
    groups.get(group)!.push(p)
  }
  return groups
}

// ── Permission checkbox section ───────────────────────────────────────────────

function PermissionSection({
  title,
  permissions,
  selected,
  onToggle,
}: {
  title: string
  permissions: Permission[]
  selected: Set<number>
  onToggle: (id: number) => void
}) {
  const [open, setOpen] = useState(false)
  const allChecked = permissions.every((p) => selected.has(p.id))
  const someChecked = permissions.some((p) => selected.has(p.id))

  function toggleAll() {
    if (allChecked) {
      permissions.forEach((p) => onToggle(p.id))
    } else {
      permissions.filter((p) => !selected.has(p.id)).forEach((p) => onToggle(p.id))
    }
  }

  return (
    <div className="roles-perm-section">
      <button
        type="button"
        className="roles-perm-section-header"
        onClick={() => setOpen((v) => !v)}
      >
        <span className="roles-perm-section-toggle">{open ? '▾' : '▸'}</span>
        <span className="roles-perm-section-title">{title}</span>
        <span className="roles-perm-section-count">{permissions.filter((p) => selected.has(p.id)).length}/{permissions.length}</span>
      </button>
      {open && (
        <div className="roles-perm-section-body">
          <label className="roles-perm-all">
            <input
              type="checkbox"
              checked={allChecked}
              ref={(el) => { if (el) el.indeterminate = someChecked && !allChecked }}
              onChange={toggleAll}
            />
            Select all
          </label>
          {permissions.map((p) => {
            const shortIds = p.metric_ids.filter((id) => id.length <= 10)
            return (
              <label key={p.id} className="roles-perm-item">
                <input
                  type="checkbox"
                  checked={selected.has(p.id)}
                  onChange={() => onToggle(p.id)}
                />
                {p.label}
                {shortIds.map((id) => (
                  <span key={id} className="roles-perm-kpi-badge">{id}</span>
                ))}
              </label>
            )
          })}
        </div>
      )}
    </div>
  )
}

// ── Role form panel ───────────────────────────────────────────────────────────

function RoleForm({
  role,
  permissions,
  onClose,
}: {
  role: Role | null
  permissions: Permission[]
  onClose: () => void
}) {
  const createRole = useCreateRole()
  const updateRole = useUpdateRole()

  const [name, setName] = useState(role?.name ?? '')
  const [description, setDescription] = useState(role?.description ?? '')
  const [whatsappAvailable, setWhatsappAvailable] = useState(role?.whatsapp_available ?? false)
  const [selectedIds, setSelectedIds] = useState<Set<number>>(
    () => new Set(role?.permissions.map((p) => p.id) ?? []),
  )
  const [error, setError] = useState<string | null>(null)

  function togglePermission(id: number) {
    setSelectedIds((prev) => {
      const next = new Set(prev)
      next.has(id) ? next.delete(id) : next.add(id)
      return next
    })
  }

  const pagePerms = useMemo(() => permissions.filter((p) => p.category === 'page'), [permissions])
  const dashletGroups = useMemo(() => groupByDashletGroup(permissions), [permissions])
  const { data: dashletGroupDefs = [] } = useAllDashletGroups()
  // Same tie-break as get_dashlets_for_comment_edit()'s
  // ORDER BY COALESCE(g.display_order, 999999), g.name NULLS LAST.
  const dashletGroupOrder = useMemo(
    () => new Map(dashletGroupDefs.map((g) => [g.name, g.display_order])),
    [dashletGroupDefs],
  )
  const waReportPerms = useMemo(() => permissions.filter((p) => p.category === 'wa_report'), [permissions])

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    const permissionIds = [...selectedIds]
    try {
      if (role) {
        await updateRole.mutateAsync({ roleId: role.id, roleName: name, roleDescription: description, whatsappAvailable, permissionIds })
      } else {
        await createRole.mutateAsync({ roleName: name, roleDescription: description, whatsappAvailable, permissionIds })
      }
      onClose()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'An error occurred')
    }
  }

  const saving = createRole.isPending || updateRole.isPending

  return (
    <div className="roles-form-panel">
      <div className="roles-form-header">
        <h2 className="roles-form-title">{role ? 'Edit Role' : 'New Role'}</h2>
        <button type="button" className="roles-form-close" onClick={onClose}>✕</button>
      </div>

      <form onSubmit={(e) => void handleSubmit(e)} className="roles-form-body">
        <div className="roles-form-field">
          <label className="roles-form-label">Name</label>
          <input
            className="admin-input"
            value={name}
            onChange={(e) => setName(e.target.value)}
            required
            placeholder="e.g. Zimbabwe KPI Analyst"
          />
        </div>
        <div className="roles-form-field">
          <label className="roles-form-label">Description</label>
          <input
            className="admin-input"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Optional description"
          />
        </div>

        <div className="roles-form-field">
          <label className="roles-perm-all" style={{ gap: 10 }}>
            <input
              type="checkbox"
              checked={whatsappAvailable}
              onChange={(e) => setWhatsappAvailable(e.target.checked)}
            />
            <span>
              <strong>Available in WhatsApp</strong>
              <span className="admin-table-muted" style={{ marginLeft: 6, fontWeight: 'normal' }}>
                Show this role for selection during bot registration
              </span>
            </span>
          </label>
        </div>

        <div className="roles-form-section-label">Permissions</div>

        <div className="roles-perm-category-label">Pages</div>
        <PermissionSection
          title="Page Access"
          permissions={pagePerms}
          selected={selectedIds}
          onToggle={togglePermission}
        />

        <div className="roles-perm-category-label" style={{ marginTop: 16 }}>Dashlets</div>
        {[...dashletGroups.entries()]
          .map(([group, perms]) => ({
            group,
            perms,
            order: dashletGroupOrder.get(group) ?? 999999,
          }))
          .sort((a, b) => a.order - b.order || a.group.localeCompare(b.group))
          .map(({ group, perms }) => (
            <PermissionSection
              key={group}
              title={group}
              permissions={perms}
              selected={selectedIds}
              onToggle={togglePermission}
            />
          ))
        }

        <div className="roles-perm-category-label" style={{ marginTop: 16 }}>WhatsApp Reports</div>
        <PermissionSection
          title="Report Types"
          permissions={waReportPerms}
          selected={selectedIds}
          onToggle={togglePermission}
        />

        {error && <div className="admin-error">{error}</div>}

        <div className="roles-form-actions">
          <button type="button" className="admin-btn admin-btn--secondary" style={{ flex: 1 }} onClick={onClose}>Cancel</button>
          <button type="submit" className="admin-btn admin-btn--primary" style={{ flex: 1 }} disabled={saving || !name.trim()}>
            {saving ? 'Saving…' : role ? 'Save Changes' : 'Create Role'}
          </button>
        </div>
      </form>
    </div>
  )
}

// ── Delete confirm modal ──────────────────────────────────────────────────────

function DeleteConfirm({ role, onConfirm, onCancel, loading }: { role: Role; onConfirm: () => void; onCancel: () => void; loading: boolean }) {
  return (
    <div className="admin-modal-backdrop">
      <div className="admin-modal">
        <h3 className="admin-modal-title">Delete Role</h3>
        <p>Delete <strong>{role.name}</strong>? This cannot be undone.</p>
        <div className="admin-modal-actions">
          <button className="admin-btn admin-btn--secondary" onClick={onCancel}>Cancel</button>
          <button className="admin-btn admin-btn--danger" onClick={onConfirm} disabled={loading}>
            {loading ? 'Deleting…' : 'Delete'}
          </button>
        </div>
      </div>
    </div>
  )
}

// ── Main page ─────────────────────────────────────────────────────────────────

export function RolesPage() {
  const { data: permissions = [], isLoading: permsLoading } = usePermissions()
  const { data: roles = [], isLoading: rolesLoading } = useRoles()
  const deleteRole = useDeleteRole()

  const [formRole, setFormRole] = useState<Role | 'new' | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<Role | null>(null)
  const [deleteError, setDeleteError] = useState<string | null>(null)
  const [search, setSearch] = useState('')

  async function handleDelete(role: Role) {
    setDeleteError(null)
    try {
      await deleteRole.mutateAsync(role.id)
      setDeleteTarget(null)
    } catch (err) {
      setDeleteError(err instanceof Error ? err.message : 'Delete failed')
    }
  }

  const loading = permsLoading || rolesLoading

  const filtered = useMemo(() => {
    const q = search.trim().toLowerCase()
    if (!q) return roles
    return roles.filter((r) =>
      r.name.toLowerCase().includes(q) || (r.description ?? '').toLowerCase().includes(q))
  }, [roles, search])

  const columns: AdminColumn<Role>[] = useMemo(() => [
    { key: 'name', header: 'Name', sortValue: (r) => r.name, render: (r) => <span className="admin-table-name">{r.name}</span> },
    { key: 'description', header: 'Description', sortValue: (r) => r.description, render: (r) => <span className="admin-table-muted">{r.description ?? '—'}</span> },
    { key: 'permissions', header: 'Permissions', sortValue: (r) => r.permissions.length, render: (r) => <span className="admin-badge admin-badge--blue">{r.permissions.length} permissions</span> },
    {
      key: 'users', header: 'Users', sortValue: (r) => r.user_count,
      render: (r) => (
        <span className={`admin-badge ${r.user_count > 0 ? 'admin-badge--green' : 'admin-badge--grey'}`}>
          {r.user_count} {r.user_count === 1 ? 'user' : 'users'}
        </span>
      ),
    },
    {
      key: 'whatsapp', header: 'WhatsApp', sortValue: (r) => (r.whatsapp_available ? 1 : 0),
      render: (r) => r.whatsapp_available
        ? <span className="admin-badge admin-badge--green">✓ Enabled</span>
        : <span className="admin-badge admin-badge--grey">—</span>,
    },
  ], [])

  return (
    <div className="admin-page">
      <div className="admin-page-header">
        <h1 className="admin-page-title">User Roles</h1>
        <button
          className="admin-btn admin-btn--primary"
          onClick={() => setFormRole('new')}
        >
          + New Role
        </button>
      </div>

      {!loading && roles.length > 0 && (
        <div className="admin-filter-bar" style={{ marginBottom: 12 }}>
          <input
            className="admin-input admin-input--sm"
            placeholder="Search roles…"
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            style={{ minWidth: 200 }}
          />
        </div>
      )}

      {loading ? (
        <div className="admin-loading">Loading…</div>
      ) : roles.length === 0 ? (
        <div className="admin-empty">No roles yet. Create one to get started.</div>
      ) : (
        <AdminDataTable
          data={filtered}
          rowKey={(r) => r.id}
          columns={columns}
          emptyMessage="No roles match your search."
          rowActions={(role) => [
            { label: 'Edit', onClick: () => setFormRole(role) },
            {
              label: 'Delete',
              variant: 'danger',
              disabled: role.user_count > 0,
              onClick: () => { setDeleteError(null); setDeleteTarget(role) },
            },
          ]}
        />
      )}

      {deleteError && <div className="admin-error" style={{ marginTop: 12 }}>{deleteError}</div>}

      {formRole !== null && (
        <RoleForm
          role={formRole === 'new' ? null : formRole}
          permissions={permissions}
          onClose={() => setFormRole(null)}
        />
      )}

      {deleteTarget && (
        <DeleteConfirm
          role={deleteTarget}
          onConfirm={() => void handleDelete(deleteTarget)}
          onCancel={() => setDeleteTarget(null)}
          loading={deleteRole.isPending}
        />
      )}
    </div>
  )
}
