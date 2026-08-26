import { useState, useMemo, useEffect } from 'react'
import { PAGE_SIZE, fmt } from '@/features/admin/Pagination'
import { AdminDataTable, type AdminColumn } from '@/features/admin/components/AdminDataTable'
import {
  useAdminUsers, useInviteUser, useRemoveUser, useSetUserRole,
  useWhatsAppUsers, useCreateWhatsAppUser, useLinkWhatsAppUser, useUnlinkWhatsAppUser,
  useInviteWhatsAppUser, useRemoveWhatsAppUser, useUpdateWhatsAppPhone, useSetWhatsAppApprover,
  useAssignApproverDistrict, useRemoveApproverDistrict, useDistrictOptions,
  useDistrictAccess, useCreateDistrictAccess, useDecideDistrictAccess,
  useRoles, useAssignUserRole, useRemoveUserRole,
  useAvailableCountries, useSetUserCountries,
  type AdminUser, type WhatsAppUser, type WhatsAppDistrictAccess, type DistrictOption, type WaFilter, type DistrictAccessRow,
} from '@/features/admin/queries'
import { useAuth } from '@/contexts/AuthContext'
import { useQueryClient } from '@tanstack/react-query'

type Tab = 'portal' | 'whatsapp' | 'access'

// ── Portal user status ────────────────────────────────────────────────────────

function portalUserStatus(u: AdminUser): { label: string; cls: string } {
  if (u.banned_until && new Date(u.banned_until) > new Date())
    return { label: 'Banned',    cls: 'admin-badge--red' }
  if (u.last_sign_in_at)
    return { label: 'Active',    cls: 'admin-badge--green' }
  if (u.invited_at && !u.confirmed_at)
    return { label: 'Invited',   cls: 'admin-badge--amber' }
  if (u.confirmed_at)
    return { label: 'Confirmed', cls: 'admin-badge--blue' }
  return   { label: 'Invited',  cls: 'admin-badge--amber' }
}

// ── Status badge ──────────────────────────────────────────────────────────────

function StatusBadge({ status }: { status: 'pending' | 'approved' | 'rejected' }) {
  const cls =
    status === 'approved' ? 'admin-badge admin-badge--green' :
    status === 'rejected' ? 'admin-badge admin-badge--red' :
                            'admin-badge admin-badge--amber'
  return <span className={cls}>{status}</span>
}

// ── District chip ─────────────────────────────────────────────────────────────

function DistrictChip({
  entry,
  isApprover = false,
  onApprove,
  onReject,
}: {
  entry: WhatsAppDistrictAccess
  isApprover?: boolean
  onApprove?: () => void
  onReject?: () => void
}) {
  const cls =
    entry.status === 'approved' ? 'admin-district-chip admin-district-chip--green' :
    entry.status === 'rejected' ? 'admin-district-chip admin-district-chip--red' :
                                  'admin-district-chip admin-district-chip--amber'
  return (
    <span className={cls} title={entry.rejection_reason ?? undefined}>
      {entry.district_name}
      {isApprover && <span className="admin-chip-approver" title="Approver for this district">★</span>}
      {entry.status === 'pending' && onApprove && (
        <button className="admin-chip-btn admin-chip-btn--approve" onClick={onApprove} title="Approve">✓</button>
      )}
      {entry.status === 'pending' && onReject && (
        <button className="admin-chip-btn admin-chip-btn--reject" onClick={onReject} title="Reject">✕</button>
      )}
    </span>
  )
}

// ── Cascading district picker ─────────────────────────────────────────────────

function DistrictPicker({
  districts,
  value,
  onChange,
  inline = false,
}: {
  districts: DistrictOption[]
  value: string
  onChange: (districtId: string) => void
  inline?: boolean
}) {
  const [country, setCountry]   = useState('')
  const [province, setProvince] = useState('')

  const richDistricts = useMemo(
    () => districts.filter((d) => d.country && d.province),
    [districts],
  )
  const countries = useMemo(
    () => [...new Set(richDistricts.map((d) => d.country))].sort(),
    [richDistricts],
  )
  const provinces = useMemo(
    () => country
      ? [...new Set(richDistricts.filter((d) => d.country === country).map((d) => d.province))].sort()
      : [],
    [richDistricts, country],
  )
  const districtList = useMemo(
    () => province
      ? richDistricts.filter((d) => d.country === country && d.province === province)
      : [],
    [richDistricts, country, province],
  )

  function handleCountry(c: string) { setCountry(c); setProvince(''); onChange('') }
  function handleProvince(p: string) { setProvince(p); onChange('') }

  return (
    <div className={inline ? 'admin-district-picker admin-district-picker--inline' : 'admin-district-picker'}>
      <select value={country} onChange={(e) => handleCountry(e.target.value)} className="admin-input admin-input--sm">
        <option value="">Country…</option>
        {countries.map((c) => <option key={c} value={c}>{c}</option>)}
      </select>
      <select value={province} onChange={(e) => handleProvince(e.target.value)} className="admin-input admin-input--sm" disabled={!country}>
        <option value="">Province…</option>
        {provinces.map((p) => <option key={p} value={p}>{p}</option>)}
      </select>
      <select value={value} onChange={(e) => onChange(e.target.value)} className="admin-input admin-input--sm" disabled={!province}>
        <option value="">District…</option>
        {districtList.map((d) => <option key={d.district_id} value={d.district_id}>{d.district_name}</option>)}
      </select>
    </div>
  )
}

// ── User edit panel ───────────────────────────────────────────────────────────

function UserInvitePanel({
  isCountryAdmin = false,
  countryAdminCountries = [],
  onClose,
}: {
  isCountryAdmin?: boolean
  countryAdminCountries?: string[]
  onClose: () => void
}) {
  const available      = useAvailableCountries()
  const invite         = useInviteUser()
  const { data: roles } = useRoles()

  const [email, setEmail]         = useState('')
  const [emailTouched, setEmailTouched] = useState(false)
  const [countries, setCountries] = useState<string[]>([])
  const [roleId, setRoleId]       = useState<number | ''>('')

  const availableList = isCountryAdmin ? countryAdminCountries : (available.data ?? [])

  const emailValid = /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)

  function toggleCountry(c: string) {
    setCountries((prev) => prev.includes(c) ? prev.filter((x) => x !== c) : [...prev, c])
  }

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!email || !emailValid || !roleId) return
    invite.mutate(
      { email, countries, roleId: roleId || undefined },
      { onSuccess: () => { setEmail(''); setEmailTouched(false); setCountries([]); setRoleId(''); onClose() } },
    )
  }

  return (
    <div className="roles-form-panel">
      <div className="roles-form-header">
        <h2 className="roles-form-title">Invite User</h2>
        <button type="button" className="roles-form-close" onClick={onClose}>✕</button>
      </div>

      <form className="roles-form-body" onSubmit={handleSubmit}>
        <div className="roles-form-section-label">Email <span style={{ color: 'var(--red, #c00)', fontWeight: 400 }}>*</span></div>
        <input
          type="email"
          className="admin-input"
          style={{ flex: 'none', borderColor: emailTouched && !emailValid ? 'var(--red, #c00)' : undefined }}
          placeholder="user@example.com"
          value={email}
          onChange={(e) => setEmail(e.target.value)}
          onBlur={() => setEmailTouched(true)}
          required
        />
        {emailTouched && email && !emailValid && (
          <p className="admin-error" style={{ marginTop: -6 }}>Enter a valid email address.</p>
        )}

        <div className="roles-form-section-label">Role <span style={{ color: 'var(--red, #c00)', fontWeight: 400 }}>*</span></div>
        <select
          className="admin-input"
          style={{ flex: 'none' }}
          value={roleId}
          onChange={(e) => setRoleId(e.target.value ? Number(e.target.value) : '')}
          required
        >
          <option value="">— Select a role —</option>
          {(roles ?? []).map((r) => (
            <option key={r.id} value={r.id}>{r.name}</option>
          ))}
        </select>

        <div className="roles-form-section-label">Countries <span style={{ color: 'var(--red, #c00)', fontWeight: 400 }}>*</span></div>
        {!isCountryAdmin && available.isLoading ? (
          <p className="admin-muted">Loading…</p>
        ) : availableList.length === 0 ? (
          <span className="admin-muted">No countries available — run ETL first</span>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.4rem' }}>
            {availableList.map((c) => (
              <label key={c} className="roles-perm-item">
                <input
                  type="checkbox"
                  checked={countries.includes(c)}
                  onChange={() => toggleCountry(c)}
                />
                {c}
              </label>
            ))}
          </div>
        )}
        {countries.length === 0 && availableList.length > 0 && (
          <p className="admin-muted" style={{ fontSize: '0.78rem', marginTop: -6 }}>Select at least one country.</p>
        )}

        {invite.isError && (
          <p className="admin-error">{(invite.error as Error).message}</p>
        )}

        <div className="roles-form-actions">
          <button
            type="submit"
            className="admin-btn admin-btn--primary"
            style={{ flex: 1 }}
            disabled={invite.isPending || !emailValid || !roleId || countries.length === 0}
          >
            {invite.isPending ? 'Sending…' : 'Send invite'}
          </button>
          <button type="button" className="admin-btn admin-btn--secondary" style={{ flex: 1 }} onClick={onClose}>
            Cancel
          </button>
        </div>
      </form>
    </div>
  )
}

function UserEditPanel({
  user,
  currentUserId,
  isCountryAdmin = false,
  countryAdminCountries = [],
  onClose,
}: {
  user: AdminUser
  currentUserId?: string
  isCountryAdmin?: boolean
  countryAdminCountries?: string[]
  onClose: () => void
}) {
  const roles        = useRoles()
  const assignRole   = useAssignUserRole()
  const removeRole   = useRemoveUserRole()
  const available    = useAvailableCountries()
  const setCountries = useSetUserCountries()
  const setAdminRole = useSetUserRole()
  const remove       = useRemoveUser()

  const currentAdminRole = user.role === 'admin' ? 'admin' : user.role === 'country_admin' ? 'country_admin' : ''
  const [selectedAdminRole, setSelectedAdminRole] = useState(currentAdminRole)
  const [pendingAdminRole, setPendingAdminRole] = useState<'admin' | 'country_admin' | null | undefined>(undefined)
  const [confirmRemove, setConfirmRemove] = useState(false)
  const [addRoleId, setAddRoleId]         = useState('')

  const currentCountries = user.countries ?? []
  const isSelf = user.id === currentUserId

  // Country admins can only assign countries from their own set
  const availableCountriesList = isCountryAdmin
    ? countryAdminCountries
    : (available.data ?? [])

  function toggleCountry(country: string) {
    const next = currentCountries.includes(country)
      ? currentCountries.filter((c) => c !== country)
      : [...currentCountries, country]
    setCountries.mutate({ userId: user.id, countries: next })
  }

  const unassignedRoles = (roles.data ?? []).filter((r) => !user.roles.some((ur) => ur.id === r.id))

  return (
    <div className="roles-form-panel">
      <div className="roles-form-header">
        <div>
          <h2 className="roles-form-title">Edit User</h2>
          <div className="admin-muted" style={{ fontSize: '0.8rem', marginTop: 2 }}>{user.email}</div>
        </div>
        <button type="button" className="roles-form-close" onClick={onClose}>✕</button>
      </div>

      <div className="roles-form-body">
        {/* Roles */}
        <div className="roles-form-section-label">Roles</div>
        <div className="admin-role-cell">
          {user.roles.length === 0 && <span className="admin-muted">No roles assigned</span>}
          {user.roles.map((r) => (
            <span key={r.id} className="admin-role-chip">
              {r.name}
              <button
                className="admin-chip-btn admin-chip-btn--reject"
                title="Remove role"
                onClick={() => removeRole.mutate({ userId: user.id, roleId: r.id })}
                disabled={removeRole.isPending}
              >✕</button>
            </span>
          ))}
        </div>
        {unassignedRoles.length > 0 && user.roles.length === 0 && (
          <select
            className="admin-input admin-input--sm"
            style={{ flex: 'none', width: 'auto', padding: '4px 8px' }}
            value={addRoleId}
            onChange={(e) => {
              if (!e.target.value) return
              assignRole.mutate({ userId: user.id, roleId: Number(e.target.value) })
              setAddRoleId('')
            }}
          >
            <option value="">+ Add role…</option>
            {unassignedRoles.map((r) => (
              <option key={r.id} value={r.id}>{r.name}</option>
            ))}
          </select>
        )}
        {(assignRole.isError || removeRole.isError) && (
          <p className="admin-error">
            {((assignRole.error ?? removeRole.error) as Error).message}
          </p>
        )}

        {/* Countries */}
        <div className="roles-form-section-label">Countries</div>
        {(!isCountryAdmin && available.isLoading) ? (
          <p className="admin-muted">Loading…</p>
        ) : user.role === 'admin' ? (
          <span className="admin-muted">Admin users have access to all countries</span>
        ) : availableCountriesList.length === 0 ? (
          <span className="admin-muted">No countries available — run ETL first</span>
        ) : (
          <div style={{ display: 'flex', flexDirection: 'column', gap: '0.4rem' }}>
            {availableCountriesList.map((c) => (
              <label key={c} className="roles-perm-item">
                <input
                  type="checkbox"
                  checked={currentCountries.includes(c)}
                  onChange={() => toggleCountry(c)}
                  disabled={setCountries.isPending}
                />
                {c}
              </label>
            ))}
          </div>
        )}
        {setCountries.isError && (
          <p className="admin-error">{(setCountries.error as Error).message}</p>
        )}

        {/* Admin role selector — full admins only, hidden for self and for country admins */}
        {!isSelf && !isCountryAdmin && (
          <>
            <div className="roles-form-section-label">Admin Role</div>
            {pendingAdminRole === undefined ? (
              <div style={{ display: 'flex', alignItems: 'center', gap: 10 }}>
                <select
                  className="admin-input admin-input--sm"
                  style={{ flex: 1 }}
                  value={selectedAdminRole}
                  onChange={(e) => {
                    const val = e.target.value
                    setSelectedAdminRole(val)
                    setPendingAdminRole(
                      val === 'admin' ? 'admin' :
                      val === 'country_admin' ? 'country_admin' :
                      null
                    )
                  }}
                >
                  <option value="">None</option>
                  <option value="country_admin">Country Admin</option>
                  <option value="admin">Full Admin</option>
                </select>
              </div>
            ) : (
              <>
                <p style={{ margin: 0 }}>
                  {pendingAdminRole === null
                    ? <>Remove admin access from <strong>{user.email}</strong>?</>
                    : pendingAdminRole === 'country_admin'
                    ? <>Set <strong>{user.email}</strong> as Country Admin? They can manage users within their assigned country.</>
                    : <>Set <strong>{user.email}</strong> as Full Admin? They will have unrestricted access to all system settings.</>
                  }
                </p>
                <div style={{ display: 'flex', gap: 10 }}>
                  <button
                    className={`admin-btn${pendingAdminRole ? ' admin-btn--primary' : ' admin-btn--danger'}`}
                    style={{ flex: 1 }}
                    disabled={setAdminRole.isPending}
                    onClick={() => setAdminRole.mutate(
                      { userId: user.id, role: pendingAdminRole as 'admin' | 'country_admin' | null },
                      { onSuccess: () => setPendingAdminRole(undefined) },
                    )}
                  >
                    {setAdminRole.isPending ? '…' : 'Confirm'}
                  </button>
                  <button className="admin-btn" style={{ flex: 1 }} onClick={() => { setSelectedAdminRole(currentAdminRole); setPendingAdminRole(undefined) }}>
                    Cancel
                  </button>
                </div>
                {setAdminRole.isError && (
                  <p className="admin-error">{(setAdminRole.error as Error).message}</p>
                )}
              </>
            )}
          </>
        )}

        {/* Remove user — available to all admins, hidden for self */}
        {!isSelf && (
          <>
            <div className="roles-form-section-label">Danger Zone</div>
            {!confirmRemove ? (
              <button
                className="admin-btn admin-btn--danger"
                style={{ width: '100%' }}
                onClick={() => setConfirmRemove(true)}
              >
                Remove user
              </button>
            ) : (
              <>
                <p style={{ margin: 0 }}>Remove <strong>{user.email}</strong>? This cannot be undone.</p>
                <div style={{ display: 'flex', gap: 10 }}>
                  <button
                    className="admin-btn admin-btn--danger"
                    style={{ flex: 1 }}
                    disabled={remove.isPending}
                    onClick={() => remove.mutate(user.id, { onSuccess: onClose })}
                  >
                    {remove.isPending ? 'Removing…' : 'Remove'}
                  </button>
                  <button className="admin-btn" style={{ flex: 1 }} onClick={() => setConfirmRemove(false)}>
                    Cancel
                  </button>
                </div>
                {remove.isError && <p className="admin-error">{(remove.error as Error).message}</p>}
              </>
            )}
          </>
        )}
      </div>

      <div className="roles-form-actions">
        <button type="button" className="admin-btn admin-btn--secondary" style={{ flex: 1 }} onClick={onClose}>
          Close
        </button>
      </div>
    </div>
  )
}

// ── WhatsApp user edit panel ──────────────────────────────────────────────────

function WaUserEditPanel({
  user,
  districts,
  onClose,
}: {
  user: WhatsAppUser
  districts: DistrictOption[]
  onClose: () => void
}) {
  const inviteWa       = useInviteWhatsAppUser()
  const link           = useLinkWhatsAppUser()
  const unlink         = useUnlinkWhatsAppUser()
  const updatePhone    = useUpdateWhatsAppPhone()
  const setApprover    = useSetWhatsAppApprover()
  const assignDistrict = useAssignApproverDistrict()
  const removeDistrict = useRemoveApproverDistrict()
  const createAccess   = useCreateDistrictAccess()
  const removeWa       = useRemoveWhatsAppUser()
  const decide         = useDecideDistrictAccess()

  const [editPhone, setEditPhone]               = useState(false)
  const [editPhoneValue, setEditPhoneValue]     = useState(user.phone ?? '')
  const [showLinkForm, setShowLinkForm]         = useState(false)
  const [linkEmail, setLinkEmail]               = useState('')
  const [confirmUnlink, setConfirmUnlink]       = useState(false)
  const [confirmApprover, setConfirmApprover]   = useState(false)
  const [addCoverDistrictId, setAddCoverDistrictId] = useState('')
  const [addAccessDistrictId, setAddAccessDistrictId] = useState('')
  const [rejectTarget, setRejectTarget]         = useState<number | null>(null)
  const [rejectReason, setRejectReason]         = useState('')
  const [confirmRemove, setConfirmRemove]       = useState(false)

  const displayName = user.name ?? user.phone ?? user.portal_id

  const coverDistricts = districts.filter((d) => {
    const approved = user.district_access.some((a) => a.district_id === d.district_id && a.status === 'approved')
    const alreadyCover = user.approver_districts.some((a) => a.district_id === d.district_id)
    return approved && !alreadyCover
  })

  return (
    <div className="roles-form-panel">
      <div className="roles-form-header">
        <div>
          <h2 className="roles-form-title"><code>{user.portal_id}</code></h2>
          {displayName !== user.portal_id && (
            <div className="admin-muted" style={{ fontSize: '0.8rem', marginTop: 2 }}>{displayName}</div>
          )}
        </div>
        <button type="button" className="roles-form-close" onClick={onClose}>✕</button>
      </div>

      <div className="roles-form-body">
        {/* Portal Link */}
        <div className="roles-form-section-label">Portal Link</div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: '0.5rem' }}>
          {user.is_linked ? (
            !confirmUnlink ? (
              <button className="admin-btn" style={{ width: '100%' }} onClick={() => setConfirmUnlink(true)}>
                Unlink portal account
              </button>
            ) : (
              <>
                <p style={{ margin: 0 }}>Unlink <strong>{user.email}</strong> from this WhatsApp user?</p>
                <div style={{ display: 'flex', gap: 10 }}>
                  <button
                    className="admin-btn admin-btn--danger"
                    style={{ flex: 1 }}
                    disabled={unlink.isPending}
                    onClick={() => unlink.mutate(user.id, { onSuccess: () => setConfirmUnlink(false) })}
                  >
                    {unlink.isPending ? '…' : 'Unlink'}
                  </button>
                  <button className="admin-btn" style={{ flex: 1 }} onClick={() => setConfirmUnlink(false)}>Cancel</button>
                </div>
              </>
            )
          ) : (
            <>
              <span className="admin-badge admin-badge--grey" style={{ alignSelf: 'flex-start' }}>Unlinked</span>
              {user.email && (
                <button
                  className="admin-btn admin-btn--primary"
                  style={{ width: '100%' }}
                  disabled={inviteWa.isPending}
                  onClick={() => inviteWa.mutate(user.id)}
                >
                  {inviteWa.isPending ? 'Inviting…' : 'Invite to portal'}
                </button>
              )}
              {!showLinkForm ? (
                <button className="admin-btn" style={{ width: '100%' }} onClick={() => setShowLinkForm(true)}>
                  Link to portal account…
                </button>
              ) : (
                <form
                  onSubmit={(e) => {
                    e.preventDefault()
                    link.mutate(
                      { whatsappUserId: user.id, supabaseEmail: linkEmail },
                      { onSuccess: () => { setShowLinkForm(false); setLinkEmail('') } }
                    )
                  }}
                  style={{ display: 'flex', flexDirection: 'column', gap: '0.4rem' }}
                >
                  <input
                    type="email"
                    placeholder="user@example.com"
                    value={linkEmail}
                    onChange={(e) => setLinkEmail(e.target.value)}
                    className="admin-input admin-input--sm"
                    required
                  />
                  <div style={{ display: 'flex', gap: 10 }}>
                    <button type="submit" className="admin-btn admin-btn--primary" style={{ flex: 1 }} disabled={link.isPending}>
                      {link.isPending ? 'Linking…' : 'Link'}
                    </button>
                    <button type="button" className="admin-btn" style={{ flex: 1 }} onClick={() => { setShowLinkForm(false); setLinkEmail('') }}>
                      Cancel
                    </button>
                  </div>
                  {link.isError && <p className="admin-error">{(link.error as Error).message}</p>}
                </form>
              )}
            </>
          )}
        </div>

        {/* Phone */}
        <div className="roles-form-section-label">Phone</div>
        {!editPhone ? (
          <div style={{ display: 'flex', alignItems: 'center', gap: 8 }}>
            <span style={{ flex: 1 }}>{user.phone ?? <span className="admin-muted">—</span>}</span>
            <button
              className="admin-btn admin-btn--sm admin-btn--secondary"
              onClick={() => { setEditPhone(true); setEditPhoneValue(user.phone ?? '') }}
            >
              Edit
            </button>
          </div>
        ) : (
          <form
            onSubmit={(e) => {
              e.preventDefault()
              updatePhone.mutate(
                { whatsappUserId: user.id, phone: editPhoneValue },
                { onSuccess: () => setEditPhone(false) }
              )
            }}
            style={{ display: 'flex', flexDirection: 'column', gap: '0.4rem' }}
          >
            <input
              value={editPhoneValue}
              onChange={(e) => setEditPhoneValue(e.target.value)}
              className="admin-input admin-input--sm"
              placeholder="Phone"
              required
            />
            <div style={{ display: 'flex', gap: 10 }}>
              <button type="submit" className="admin-btn admin-btn--primary" style={{ flex: 1 }} disabled={updatePhone.isPending}>
                {updatePhone.isPending ? 'Saving…' : 'Save'}
              </button>
              <button type="button" className="admin-btn" style={{ flex: 1 }} onClick={() => setEditPhone(false)}>Cancel</button>
            </div>
            {updatePhone.isError && <p className="admin-error">{(updatePhone.error as Error).message}</p>}
          </form>
        )}

        {/* Role */}
        <div className="roles-form-section-label">Role</div>
        <span>{user.role_name ?? <span className="admin-muted">None</span>}</span>

        {/* Approver Role */}
        <div className="roles-form-section-label">Approver Role</div>
        {!confirmApprover ? (
          <button
            className={`admin-btn${user.is_approver ? '' : ' admin-btn--primary'}`}
            style={{ width: '100%' }}
            onClick={() => setConfirmApprover(true)}
          >
            {user.is_approver ? 'Revoke approver role' : 'Make approver'}
          </button>
        ) : (
          <>
            <p style={{ margin: 0 }}>
              {user.is_approver
                ? <>Revoke approver role from <strong>{displayName}</strong>?</>
                : <>Make <strong>{displayName}</strong> an approver? They will be able to approve district access requests.</>
              }
            </p>
            <div style={{ display: 'flex', gap: 10 }}>
              <button
                className={`admin-btn${user.is_approver ? ' admin-btn--danger' : ' admin-btn--primary'}`}
                style={{ flex: 1 }}
                disabled={setApprover.isPending}
                onClick={() => setApprover.mutate(
                  { whatsappUserId: user.id, isApprover: !user.is_approver },
                  { onSuccess: () => setConfirmApprover(false) }
                )}
              >
                {setApprover.isPending ? '…' : 'Confirm'}
              </button>
              <button className="admin-btn" style={{ flex: 1 }} onClick={() => setConfirmApprover(false)}>Cancel</button>
            </div>
          </>
        )}

        {/* Cover Districts — approvers only */}
        {user.is_approver && (
          <>
            <div className="roles-form-section-label">Cover Districts</div>
            <div className="admin-chips-cell" style={{ marginBottom: '0.4rem' }}>
              {user.approver_districts.length === 0
                ? <span className="admin-muted">None assigned</span>
                : user.approver_districts.map((d) => (
                    <span key={d.district_id} className="admin-district-chip admin-district-chip--green">
                      {d.district_name}
                      <button
                        className="admin-chip-btn admin-chip-btn--reject"
                        title="Remove"
                        disabled={removeDistrict.isPending}
                        onClick={() => removeDistrict.mutate({ whatsappUserId: user.id, districtId: d.district_id })}
                      >✕</button>
                    </span>
                  ))
              }
            </div>
            {coverDistricts.length > 0 && (
              <DistrictPicker
                key={`cover-${user.id}-${user.approver_districts.length}`}
                districts={coverDistricts}
                value={addCoverDistrictId}
                onChange={(id) => {
                  if (!id) return
                  const d = districts.find((x) => x.district_id === id)
                  if (!d) return
                  setAddCoverDistrictId(id)
                  assignDistrict.mutate(
                    { whatsappUserId: user.id, districtId: d.district_id, districtName: d.district_name },
                    { onSuccess: () => setAddCoverDistrictId('') }
                  )
                }}
              />
            )}
            {assignDistrict.isError && <p className="admin-error">{(assignDistrict.error as Error).message}</p>}
          </>
        )}

        {/* District Access */}
        <div className="roles-form-section-label">District Access</div>
        <div className="admin-chips-cell" style={{ marginBottom: '0.4rem' }}>
          {user.district_access.length === 0
            ? <span className="admin-muted">No access requests</span>
            : user.district_access.map((d) => (
                <DistrictChip
                  key={d.id}
                  entry={d}
                  isApprover={user.approver_districts.some((a) => a.district_id === d.district_id)}
                  onApprove={() => decide.mutate({ accessId: d.id, decision: 'approved' })}
                  onReject={() => { setRejectTarget(d.id); setRejectReason('') }}
                />
              ))
          }
        </div>
        {rejectTarget !== null && (
          <form
            onSubmit={(e) => {
              e.preventDefault()
              decide.mutate(
                { accessId: rejectTarget, decision: 'rejected', rejectionReason: rejectReason || undefined },
                { onSuccess: () => { setRejectTarget(null); setRejectReason('') } }
              )
            }}
            style={{ display: 'flex', flexDirection: 'column', gap: '0.4rem' }}
          >
            <textarea
              placeholder="Rejection reason (optional)"
              value={rejectReason}
              onChange={(e) => setRejectReason(e.target.value)}
              className="admin-input"
              rows={2}
              style={{ resize: 'vertical' }}
            />
            <div style={{ display: 'flex', gap: 10 }}>
              <button type="submit" className="admin-btn admin-btn--danger" style={{ flex: 1 }} disabled={decide.isPending}>
                {decide.isPending ? 'Rejecting…' : 'Reject'}
              </button>
              <button type="button" className="admin-btn" style={{ flex: 1 }} onClick={() => setRejectTarget(null)}>Cancel</button>
            </div>
          </form>
        )}
        <DistrictPicker
          key={`access-${user.id}-${user.district_access.length}`}
          districts={districts}
          value={addAccessDistrictId}
          onChange={(id) => {
            if (!id) return
            const d = districts.find((x) => x.district_id === id)
            if (!d) return
            setAddAccessDistrictId(id)
            createAccess.mutate(
              { whatsappUserId: user.id, districtId: d.district_id, districtName: d.district_name },
              { onSuccess: () => setAddAccessDistrictId('') }
            )
          }}
        />
        {createAccess.isError && <p className="admin-error">{(createAccess.error as Error).message}</p>}

        {/* Danger Zone */}
        <div className="roles-form-section-label">Danger Zone</div>
        {!confirmRemove ? (
          <button className="admin-btn admin-btn--danger" style={{ width: '100%' }} onClick={() => setConfirmRemove(true)}>
            Remove user
          </button>
        ) : (
          <>
            <p style={{ margin: 0 }}>Remove <strong>{displayName}</strong>? This cannot be undone.</p>
            <div style={{ display: 'flex', gap: 10 }}>
              <button
                className="admin-btn admin-btn--danger"
                style={{ flex: 1 }}
                disabled={removeWa.isPending}
                onClick={() => removeWa.mutate(user.id, { onSuccess: onClose })}
              >
                {removeWa.isPending ? 'Removing…' : 'Remove'}
              </button>
              <button className="admin-btn" style={{ flex: 1 }} onClick={() => setConfirmRemove(false)}>Cancel</button>
            </div>
            {removeWa.isError && <p className="admin-error">{(removeWa.error as Error).message}</p>}
          </>
        )}
      </div>

      <div className="roles-form-actions">
        <button type="button" className="admin-btn admin-btn--secondary" style={{ flex: 1 }} onClick={onClose}>
          Close
        </button>
      </div>
    </div>
  )
}

// ── Main page ─────────────────────────────────────────────────────────────────

export function AdminUsersPage() {
  const { user: currentUser, isCountryAdmin, countries: myCountries } = useAuth()
  const [activeTab, setActiveTab] = useState<Tab>('portal')
  const qc = useQueryClient()

  useEffect(() => {
    // Invalidate all admin queries when tab switches to ensure fresh data
    qc.invalidateQueries({ queryKey: ['admin', 'users'] })
    qc.invalidateQueries({ queryKey: ['admin', 'whatsapp-users'] })
    qc.invalidateQueries({ queryKey: ['admin', 'district-access'] })
  }, [activeTab, qc])

  const availableTabs: Tab[] = ['portal', 'whatsapp', 'access']

  return (
    <div className="admin-page">
      <div className="admin-page-header">
        <h1 className="admin-page-title">Users</h1>
      </div>

      <div className="admin-tabs">
        {availableTabs.map((t) => (
          <button
            key={t}
            className={`admin-tab${activeTab === t ? ' admin-tab--active' : ''}`}
            onClick={() => setActiveTab(t)}
          >
            {t === 'portal' ? 'Portal Users' : t === 'whatsapp' ? 'WhatsApp Users' : 'District Access'}
          </button>
        ))}
      </div>

      {activeTab === 'portal'   && (
        <PortalUsersTab
          currentUserId={currentUser?.id}
          isCountryAdmin={isCountryAdmin}
          countryAdminCountries={myCountries}
        />
      )}
      {activeTab === 'whatsapp' && <WhatsAppUsersTab />}
      {activeTab === 'access'   && <DistrictAccessTab />}
    </div>
  )
}

// ── Portal Users tab ──────────────────────────────────────────────────────────

function portalUserColumns({
  isCountryAdmin,
  currentUserId,
  onEdit,
}: {
  isCountryAdmin: boolean
  currentUserId?: string
  onEdit: (u: AdminUser) => void
}): AdminColumn<AdminUser>[] {
  const cols: AdminColumn<AdminUser>[] = [
    {
      key: 'email', header: 'Email', width: isCountryAdmin ? '32%' : '22%', sortable: true,
      render: (u) => (
        <span style={{ overflow: 'hidden', textOverflow: 'ellipsis', whiteSpace: 'nowrap', display: 'block' }}>
          {u.email}{u.id === currentUserId && <span className="admin-you-badge"> (you)</span>}
        </span>
      ),
    },
  ]
  if (!isCountryAdmin) {
    cols.push({
      key: 'admin', header: 'Admin', width: '13%', sortable: true,
      render: (u) => u.role === 'admin'
        ? <span className="admin-badge admin-badge--purple">Admin</span>
        : u.role === 'country_admin'
        ? <span className="admin-badge admin-badge--teal">Country Admin</span>
        : null,
    })
  }
  cols.push(
    {
      key: 'roles', header: 'Assigned Roles', width: '20%',
      render: (u) => (
        <div className="admin-role-cell">
          {u.roles.length === 0
            ? <span className="admin-muted">—</span>
            : u.roles.map((r) => <span key={r.id} className="admin-role-chip">{r.name}</span>)}
        </div>
      ),
    },
    {
      key: 'countries', header: 'Countries', width: '18%',
      render: (u) => {
        if (u.role === 'admin') return <span className="admin-muted">All</span>
        const cs = u.countries ?? []
        if (cs.length === 0) return <span className="admin-muted">—</span>
        const visible = cs.slice(0, 2)
        const extra = cs.length - 2
        return (
          <div className="admin-role-cell">
            {visible.map((c) => <span key={c} className="admin-role-chip">{c}</span>)}
            {extra > 0 && <span className="admin-muted" style={{ fontSize: '0.78rem' }}>+{extra} more</span>}
          </div>
        )
      },
    },
    { key: 'status', header: 'Status', width: '8%', sortable: true, render: (u) => <span className={`admin-badge ${portalUserStatus(u).cls}`}>{portalUserStatus(u).label}</span> },
    { key: 'last_sign_in', header: 'Last sign in', width: '12%', sortable: true, render: (u) => u.last_sign_in_at ? fmt(u.last_sign_in_at) : '—' },
    {
      key: 'actions', header: '', width: '10%',
      render: (u) => (
        <button className="admin-btn admin-btn--sm admin-btn--secondary" onClick={() => onEdit(u)}>
          Edit
        </button>
      ),
    },
  )
  return cols
}

function PortalUsersTab({
  currentUserId,
  isCountryAdmin = false,
  countryAdminCountries = [],
}: {
  currentUserId?: string
  isCountryAdmin?: boolean
  countryAdminCountries?: string[]
}) {
  const [page, setPage]                           = useState(1)
  const [search, setSearch]                       = useState('')
  const [debouncedSearch, setDebouncedSearch]     = useState('')
  const [adminRoleFilter, setAdminRoleFilter]     = useState('')
  const [roleIdFilter, setRoleIdFilter]           = useState<number | null>(null)
  const [countryFilter, setCountryFilter]         = useState('')
  const [statusFilter, setStatusFilter]           = useState('')
  const [sortKey, setSortKey]                     = useState('email')
  const [sortDir, setSortDir]                     = useState<'asc' | 'desc'>('asc')

  useEffect(() => {
    const t = setTimeout(() => { setDebouncedSearch(search); setPage(1) }, 300)
    return () => clearTimeout(t)
  }, [search])

  useEffect(() => { setPage(1) }, [adminRoleFilter, roleIdFilter, countryFilter, statusFilter])

  function handleSort(key: string) {
    if (key === sortKey) setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'))
    else { setSortKey(key); setSortDir('asc') }
    setPage(1)
  }

  const users   = useAdminUsers(page, PAGE_SIZE, {
    search: debouncedSearch,
    adminRole: adminRoleFilter,
    roleId: roleIdFilter,
    country: countryFilter,
    status: statusFilter,
    sortKey,
    sortDir,
  })
  const roles     = useRoles()
  const countries = useAvailableCountries()

  const pageData   = users.data?.users ?? []
  const total      = users.data?.total ?? 0
  const totalPages = Math.max(1, Math.ceil(total / PAGE_SIZE))

  const [showInvitePanel, setShowInvitePanel] = useState(false)
  const [editTarget, setEditTarget]           = useState<AdminUser | null>(null)

  // Keep the edit panel in sync when user data refreshes (e.g. after role changes)
  const editUser = editTarget ? (users.data?.users ?? []).find((u) => u.id === editTarget.id) ?? editTarget : null

  return (
    <>
      <div className="admin-section-header">
        <button className="admin-btn admin-btn--primary" onClick={() => setShowInvitePanel(true)}>
          Invite user
        </button>
      </div>

      <div className="admin-filter-bar">
        <input
          type="search"
          className="admin-input admin-filter-search"
          placeholder="Search by email…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        {!isCountryAdmin && (
          <select className="admin-select" value={adminRoleFilter} onChange={(e) => setAdminRoleFilter(e.target.value)}>
            <option value="">All admin roles</option>
            <option value="admin">Admin</option>
            <option value="country_admin">Country Admin</option>
            <option value="user">Regular</option>
          </select>
        )}
        <select className="admin-select" value={roleIdFilter ?? ''} onChange={(e) => setRoleIdFilter(e.target.value ? Number(e.target.value) : null)}>
          <option value="">All roles</option>
          {(roles.data ?? []).map((r) => (
            <option key={r.id} value={r.id}>{r.name}</option>
          ))}
        </select>
        <select className="admin-select" value={countryFilter} onChange={(e) => setCountryFilter(e.target.value)}>
          <option value="">All countries</option>
          {(countries.data ?? []).map((c) => (
            <option key={c} value={c}>{c}</option>
          ))}
        </select>
        <select className="admin-select" value={statusFilter} onChange={(e) => setStatusFilter(e.target.value)}>
          <option value="">All statuses</option>
          <option value="active">Active</option>
          <option value="invited">Invited</option>
          <option value="confirmed">Confirmed</option>
          <option value="banned">Banned</option>
        </select>
      </div>

      {users.isError && <p className="admin-error">Failed to load users.</p>}

      {users.data && (
        <AdminDataTable
          data={pageData}
          rowKey={(u) => u.id}
          columns={portalUserColumns({ isCountryAdmin, currentUserId, onEdit: setEditTarget })}
          isLoading={users.isLoading}
          serverPagination={{ page, totalPages, total, onPage: setPage }}
          sort={{ key: sortKey, dir: sortDir, onChange: handleSort }}
          emptyMessage="No users match this filter."
        />
      )}

      {editUser && (
        <UserEditPanel
          user={editUser}
          currentUserId={currentUserId}
          isCountryAdmin={isCountryAdmin}
          countryAdminCountries={countryAdminCountries}
          onClose={() => setEditTarget(null)}
        />
      )}

      {showInvitePanel && (
        <UserInvitePanel
          isCountryAdmin={isCountryAdmin}
          countryAdminCountries={countryAdminCountries}
          onClose={() => setShowInvitePanel(false)}
        />
      )}
    </>
  )
}

// ── WhatsApp Users tab ────────────────────────────────────────────────────────

function WaUserCreatePanel({
  districts,
  onClose,
}: {
  districts: DistrictOption[]
  onClose: () => void
}) {
  const createWa = useCreateWhatsAppUser()
  const { data: roles } = useRoles()
  const waRoles = roles?.filter((r) => r.whatsapp_available) ?? []

  const [createPhone, setCreatePhone]           = useState('')
  const [createName, setCreateName]             = useState('')
  const [createEmail, setCreateEmail]           = useState('')
  const [createDistrictId, setCreateDistrictId] = useState('')
  const [createRoleId, setCreateRoleId]         = useState<number | ''>('')

  function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (!createPhone || !createName) return
    const district = districts.find((d: DistrictOption) => d.district_id === createDistrictId)
    createWa.mutate(
      {
        phone: createPhone,
        name: createName,
        email: createEmail || undefined,
        districtId: district?.district_id,
        districtName: district?.district_name,
        roleId: createRoleId || undefined,
      },
      { onSuccess: () => { onClose() } },
    )
  }

  return (
    <div className="roles-form-panel">
      <div className="roles-form-header">
        <h2 className="roles-form-title">Add WhatsApp User</h2>
        <button type="button" className="roles-form-close" onClick={onClose}>✕</button>
      </div>
      <form className="roles-form-body" onSubmit={handleSubmit}>
        <div className="roles-form-section-label">Phone <span style={{ color: 'var(--red, #c00)', fontWeight: 400 }}>*</span></div>
        <input
          className="admin-input"
          style={{ flex: 'none' }}
          placeholder="e.g. +263771234567"
          value={createPhone}
          onChange={(e) => setCreatePhone(e.target.value)}
          required
        />

        <div className="roles-form-section-label">Name <span style={{ color: 'var(--red, #c00)', fontWeight: 400 }}>*</span></div>
        <input
          className="admin-input"
          style={{ flex: 'none' }}
          placeholder="Full name"
          value={createName}
          onChange={(e) => setCreateName(e.target.value)}
          required
        />

        <div className="roles-form-section-label">Email</div>
        <input
          type="email"
          className="admin-input"
          style={{ flex: 'none' }}
          placeholder="Optional"
          value={createEmail}
          onChange={(e) => setCreateEmail(e.target.value)}
        />

        <div className="roles-form-section-label">Role <span style={{ color: 'var(--red, #c00)', fontWeight: 400 }}>*</span></div>
        <select
          className="admin-input"
          style={{ flex: 'none' }}
          value={createRoleId}
          onChange={(e) => setCreateRoleId(e.target.value ? Number(e.target.value) : '')}
          required
        >
          <option value="">— Select a role —</option>
          {waRoles.map((r) => (
            <option key={r.id} value={r.id}>{r.name}</option>
          ))}
        </select>

        <div className="roles-form-section-label">District <span style={{ color: 'var(--red, #c00)', fontWeight: 400 }}>*</span></div>
        <DistrictPicker
          key="create"
          districts={districts}
          value={createDistrictId}
          onChange={setCreateDistrictId}
        />

        {createWa.isError && <p className="admin-error">{(createWa.error as Error).message}</p>}

        <div className="roles-form-actions">
          <button type="submit" className="admin-btn admin-btn--primary" style={{ flex: 1 }} disabled={createWa.isPending || !createPhone || !createName || !createRoleId || !createDistrictId}>
            {createWa.isPending ? 'Creating…' : 'Create'}
          </button>
          <button type="button" className="admin-btn admin-btn--secondary" style={{ flex: 1 }} onClick={onClose}>
            Cancel
          </button>
        </div>
      </form>
    </div>
  )
}

function waUserColumns(onEdit: (u: WhatsAppUser) => void): AdminColumn<WhatsAppUser>[] {
  return [
    { key: 'portal_id', header: 'Portal ID', sortable: true, render: (u) => <code>{u.portal_id}</code> },
    { key: 'phone', header: 'Phone', sortable: true, render: (u) => u.has_phone ? u.phone : <span className="admin-muted">—</span> },
    { key: 'name', header: 'Name', sortable: true, render: (u) => u.name ?? <span className="admin-muted">—</span> },
    { key: 'email', header: 'Email', sortable: true, render: (u) => u.email ?? <span className="admin-muted">—</span> },
    { key: 'role_name', header: 'Role', sortable: true, render: (u) => u.role_name ?? <span className="admin-muted">—</span> },
    {
      key: 'status', header: 'Status',
      render: (u) => (
        <div className="admin-badge-stack">
          {u.is_linked
            ? <span className="admin-badge admin-badge--green">Linked</span>
            : <span className="admin-badge admin-badge--grey">Unlinked</span>}
          {u.is_approver && <span className="admin-badge admin-badge--teal">Approver</span>}
        </div>
      ),
    },
    {
      key: 'district_access', header: 'District access',
      render: (u) => (
        <div className="admin-chips-cell">
          {u.district_access.map((d) => (
            <DistrictChip
              key={d.id}
              entry={d}
              isApprover={u.approver_districts.some((a) => a.district_id === d.district_id)}
            />
          ))}
        </div>
      ),
    },
    {
      key: 'actions', header: '',
      render: (u) => (
        <button className="admin-btn admin-btn--sm admin-btn--secondary" onClick={() => onEdit(u)}>
          Edit
        </button>
      ),
    },
  ]
}

function WhatsAppUsersTab() {
  const [waFilter, setWaFilter]                 = useState<WaFilter>('all')
  const [search, setSearch]                     = useState('')
  const [debouncedSearch, setDebouncedSearch]   = useState('')
  const [page, setPage]                         = useState(1)
  const [sortKey, setSortKey]                   = useState('created_at')
  const [sortDir, setSortDir]                   = useState<'asc' | 'desc'>('desc')

  useEffect(() => {
    const id = setTimeout(() => { setDebouncedSearch(search); setPage(1) }, 300)
    return () => clearTimeout(id)
  }, [search])

  function handleSort(key: string) {
    if (key === sortKey) setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'))
    else { setSortKey(key); setSortDir('asc') }
    setPage(1)
  }

  const waUsers   = useWhatsAppUsers(page, PAGE_SIZE, { search: debouncedSearch, filter: waFilter, sortKey, sortDir })
  const districts = useDistrictOptions()

  const waPageData   = waUsers.data?.users ?? []
  const waTotal      = waUsers.data?.total ?? 0
  const waTotalPages = Math.max(1, Math.ceil(waTotal / PAGE_SIZE))

  const [showCreate, setShowCreate] = useState(false)
  const [editTarget, setEditTarget] = useState<WhatsAppUser | null>(null)

  const editUser = editTarget ? waPageData.find((u) => u.id === editTarget.id) ?? editTarget : null

  return (
    <>
      <div className="admin-filter-bar">
        {(['all', 'phone-only', 'approvers', 'has-pending'] as WaFilter[]).map((f) => (
          <button key={f}
            className={`admin-filter-btn${waFilter === f ? ' admin-filter-btn--active' : ''}`}
            onClick={() => { setWaFilter(f); setPage(1) }}>
            {f === 'all' ? 'All' : f === 'phone-only' ? 'WhatsApp only' : f === 'approvers' ? 'Approvers' : 'Has pending'}
          </button>
        ))}
        <input
          className="admin-input admin-input--sm"
          placeholder="Search portal ID, name, phone, email, district…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <button className="admin-btn admin-btn--primary admin-btn--sm"
          style={{ marginLeft: 'auto' }}
          onClick={() => setShowCreate(true)}>
          + Add user
        </button>
      </div>

      {waUsers.isError && <p className="admin-error">Failed to load WhatsApp users.</p>}

      {waUsers.data && (
        <AdminDataTable
          data={waPageData}
          rowKey={(u) => u.id}
          columns={waUserColumns(setEditTarget)}
          isLoading={waUsers.isLoading}
          serverPagination={{ page, totalPages: waTotalPages, total: waTotal, onPage: setPage }}
          sort={{ key: sortKey, dir: sortDir, onChange: handleSort }}
          emptyMessage="No users match this filter."
        />
      )}

      {showCreate && (
        <WaUserCreatePanel
          districts={districts.data ?? []}
          onClose={() => setShowCreate(false)}
        />
      )}

      {editUser && (
        <WaUserEditPanel
          user={editUser}
          districts={districts.data ?? []}
          onClose={() => setEditTarget(null)}
        />
      )}
    </>
  )
}

// ── District Access tab ───────────────────────────────────────────────────────

function districtAccessColumns({
  decide,
  onReject,
}: {
  decide: { mutate: (vars: { accessId: number; decision: 'approved' | 'rejected' }) => void; isPending: boolean }
  onReject: (accessId: number) => void
}): AdminColumn<DistrictAccessRow>[] {
  return [
    {
      key: 'requester', header: 'Requester', sortable: true,
      render: (row) => (
        <>
          <code>{row.requester?.portal_id ?? '—'}</code>
          {row.requester?.name && <span className="admin-muted"> {row.requester.name}</span>}
          {!row.requester?.name && row.requester?.phone && <span className="admin-muted"> {row.requester.phone}</span>}
        </>
      ),
    },
    { key: 'district_name', header: 'District', sortable: true, render: (row) => row.district_name },
    { key: 'status', header: 'Status', sortable: true, render: (row) => <StatusBadge status={row.status} /> },
    { key: 'approver', header: 'Decided by', sortable: true, render: (row) => row.approver ? <code>{row.approver.portal_id}</code> : '—' },
    { key: 'decided_at', header: 'Decided at', sortable: true, render: (row) => row.decided_at ? fmt(row.decided_at) : '—' },
    { key: 'rejection_reason', header: 'Reason', sortable: true, render: (row) => row.rejection_reason ?? '—' },
    {
      key: 'actions', header: '',
      render: (row) => row.status === 'pending' && (
        <>
          <button className="admin-btn admin-btn--sm" style={{ width: '5rem' }}
            disabled={decide.isPending}
            onClick={() => decide.mutate({ accessId: row.id, decision: 'approved' })}>
            Approve
          </button>
          <button className="admin-btn admin-btn--danger-sm" style={{ width: '5rem' }}
            onClick={() => onReject(row.id)}>
            Reject
          </button>
        </>
      ),
    },
  ]
}

function DistrictAccessTab() {
  const [districtFilter, setDistrictFilter] = useState('')
  const [statusFilter, setStatusFilter]     = useState('')
  const [search, setSearch]                 = useState('')
  const [debouncedSearch, setDebouncedSearch] = useState('')
  const [filterKey, setFilterKey]           = useState(0)
  const [page, setPage]                     = useState(1)
  const [rejectTarget, setRejectTarget]     = useState<number | null>(null)
  const [rejectReason, setRejectReason]     = useState('')
  const [sortKey, setSortKey]               = useState('created_at')
  const [sortDir, setSortDir]               = useState<'asc' | 'desc'>('desc')

  useEffect(() => {
    const id = setTimeout(() => { setDebouncedSearch(search); setPage(1) }, 300)
    return () => clearTimeout(id)
  }, [search])

  function handleSort(key: string) {
    if (key === sortKey) setSortDir((d) => (d === 'asc' ? 'desc' : 'asc'))
    else { setSortKey(key); setSortDir('asc') }
    setPage(1)
  }

  const access  = useDistrictAccess(page, PAGE_SIZE, {
    districtId:   districtFilter || undefined,
    statusFilter: statusFilter   || undefined,
    search:       debouncedSearch || undefined,
    sortKey,
    sortDir,
  })
  const decide    = useDecideDistrictAccess()
  const districts = useDistrictOptions()

  const acPageData   = access.data?.records ?? []
  const acTotal      = access.data?.total ?? 0
  const acTotalPages = Math.max(1, Math.ceil(acTotal / PAGE_SIZE))

  function clearFilters() {
    setStatusFilter('')
    setDistrictFilter('')
    setSearch('')
    setDebouncedSearch('')
    setFilterKey((k) => k + 1)
    setPage(1)
  }

  function handleRejectSubmit(e: React.FormEvent) {
    e.preventDefault()
    if (rejectTarget === null) return
    decide.mutate(
      { accessId: rejectTarget, decision: 'rejected', rejectionReason: rejectReason },
      { onSuccess: () => { setRejectTarget(null); setRejectReason('') } }
    )
  }

  return (
    <>
      <div className="admin-filter-bar">
        <input
          className="admin-input admin-input--sm"
          placeholder="Search portal ID, name, phone…"
          value={search}
          onChange={(e) => setSearch(e.target.value)}
        />
        <select value={statusFilter} onChange={(e) => { setStatusFilter(e.target.value); setPage(1) }} className="admin-input admin-input--sm" style={{ maxWidth: 140, flex: 'none' }}>
          <option value="">All statuses</option>
          <option value="pending">Pending</option>
          <option value="approved">Approved</option>
          <option value="rejected">Rejected</option>
        </select>
        <DistrictPicker
          key={filterKey}
          districts={districts.data ?? []}
          value={districtFilter}
          onChange={(v) => { setDistrictFilter(v); setPage(1) }}
          inline
        />
        {(search || statusFilter || districtFilter) && (
          <button className="admin-btn admin-btn--sm" onClick={clearFilters}>Clear</button>
        )}
      </div>

      {access.isError && <p className="admin-error">Failed to load district access.</p>}

      {access.data && (
        <AdminDataTable
          data={acPageData}
          rowKey={(row) => row.id}
          columns={districtAccessColumns({ decide, onReject: (id) => { setRejectTarget(id); setRejectReason('') } })}
          isLoading={access.isLoading}
          serverPagination={{ page, totalPages: acTotalPages, total: acTotal, onPage: setPage }}
          sort={{ key: sortKey, dir: sortDir, onChange: handleSort }}
          emptyMessage="No district access records match this filter."
        />
      )}

      {rejectTarget !== null && (
        <div className="admin-modal-overlay">
          <div className="admin-modal">
            <p>Reject this district access request?</p>
            <form onSubmit={handleRejectSubmit}>
              <textarea placeholder="Reason (optional)" value={rejectReason}
                onChange={(e) => setRejectReason(e.target.value)} className="admin-input" rows={3} />
              <div className="admin-modal-actions">
                <button type="submit" className="admin-btn admin-btn--danger" disabled={decide.isPending}>
                  {decide.isPending ? 'Rejecting…' : 'Reject'}
                </button>
                <button type="button" className="admin-btn" onClick={() => setRejectTarget(null)}>Cancel</button>
              </div>
              {decide.isError && <p className="admin-error">{(decide.error as Error).message}</p>}
            </form>
          </div>
        </div>
      )}
    </>
  )
}

