import { useEffect, useMemo, useRef, useState } from 'react'
import { createPortal } from 'react-dom'
import {
  usePermissions, useMetricConfigs, useKpiDefinitions, useSaveDashlet,
  useDeletePermission, useMetricConfigList, useCreateMetricConfig, useUpdateMetricConfig, useDeleteMetricConfig, useViewColumns, useViewColumnValues,
  useDashletHistory, useRestoreDashlet, useMetricConfigHistory, useRestoreMetricConfig,
  useDashletGroups, useAllDashletGroups, useCreateDashletGroup, useUpdateDashletGroup, useDeleteDashletGroup,
  useDashletCategories, useCreateDashletCategory, useUpdateDashletCategory, useDeleteDashletCategory,
  useDashboardsAdmin, useCreateDashboard, useUpdateDashboard, useDeleteDashboard,
  useKpiDisaggregations, usePublishDashlet, useUnpublishDashlet, useDiscardDashletDraft,
  type Permission, type MetricConfig, type KpiDefinition, type MetricConfigFull, type ViewColumn, type HistoryEntry, type DashletGroup, type DashletCategory, type Dashboard,
} from '@/features/admin/queries'
import { usePagination, Pagination, PAGE_SIZE } from '@/features/admin/Pagination'
import { RowActionsMenu } from '@/features/admin/components/RowActionsMenu'
import { AdminDataTable, type AdminColumn } from '@/features/admin/components/AdminDataTable'

const SOURCE_VIEWS = [
  'view_children_supported',
  'view_guide_assignment',
  'view_cama_membership',
  'view_post_school_support',
  'view_grants',
  'view_loans',
]

const NUMERIC_TYPES = new Set(['smallint', 'integer', 'bigint', 'numeric', 'real', 'double precision', 'decimal'])

// snake_case a free-text label/section into a key segment — matches the
// convention already used across every existing dashlet key (e.g.
// "Education Reach" + "Bursaries" -> "dashlet:education_reach:bursaries").
function slugify(s: string): string {
  return s.trim().toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_+|_+$/g, '')
}

const DASHLET_KEY_PATTERN = /^dashlet:[a-z0-9_-]+(:[a-z0-9_-]+)*$/

// ── Item picker ───────────────────────────────────────────────────────────────
// Renders its dropdown via a document.body portal, positioned from the
// trigger's bounding rect (same escape hatch DashletCommentIcon uses) —
// a plain position:absolute dropdown breaks when nested inside the
// position:fixed, internally-scrolling roles-form-panel. Generic over the
// item id type so it can back both the metric_config picker (number ids)
// and the legacy KPI-code picker (string ids) without duplicating this.

interface Coords { top?: number; bottom?: number; left: number; width: number; maxHeight: number }
interface PickerItem<T> { id: T; label: string }

const PICKER_DROPDOWN_MAX = 320 // must match .country-multi-dropdown's max-height in brand.css
const PICKER_VIEWPORT_MARGIN = 8

function ItemPicker<T extends string | number>({
  items,
  selected,
  onToggle,
  emptyLabel,
  singularLabel,
  pluralLabel,
  searchPlaceholder,
  closeOnSelect,
}: {
  items: PickerItem<T>[]
  selected: Set<T>
  onToggle: (id: T) => void
  emptyLabel: string
  singularLabel: string
  pluralLabel: string
  searchPlaceholder: string
  // Single-select mode (e.g. a filter's "equals" value): close the dropdown
  // right after a choice instead of leaving it open for further toggling.
  closeOnSelect?: boolean
}) {
  const [open, setOpen] = useState(false)
  const [search, setSearch] = useState('')
  const [coords, setCoords] = useState<Coords | null>(null)
  const btnRef = useRef<HTMLButtonElement>(null)
  const dropRef = useRef<HTMLDivElement>(null)

  function openDropdown() {
    if (btnRef.current) {
      const r = btnRef.current.getBoundingClientRect()
      const spaceBelow = window.innerHeight - r.bottom - PICKER_VIEWPORT_MARGIN
      const spaceAbove = r.top - PICKER_VIEWPORT_MARGIN
      // Prefer opening downward; flip above the trigger only when there's
      // meaningfully more room there — otherwise a long list (e.g. hundreds
      // of distinct filter values) renders past the viewport edge with no
      // way to scroll it into view, since the dropdown is position: fixed.
      if (spaceBelow >= 150 || spaceBelow >= spaceAbove) {
        setCoords({ top: r.bottom + 4, left: r.left, width: r.width, maxHeight: Math.max(120, Math.min(PICKER_DROPDOWN_MAX, spaceBelow)) })
      } else {
        setCoords({ bottom: window.innerHeight - r.top + 4, left: r.left, width: r.width, maxHeight: Math.max(120, Math.min(PICKER_DROPDOWN_MAX, spaceAbove)) })
      }
    }
    setSearch('')
    setOpen(true)
  }

  useEffect(() => {
    if (!open) return
    function onPointerDown(e: PointerEvent) {
      const target = e.target as Node
      if (btnRef.current?.contains(target) || dropRef.current?.contains(target)) return
      setOpen(false)
    }
    function onScroll(e: Event) {
      // Scrolling inside the dropdown's own option list shouldn't close it —
      // only close when an ancestor container scrolls (trigger has moved).
      if (e.target instanceof Node && dropRef.current?.contains(e.target)) return
      setOpen(false)
    }
    function onResize() { setOpen(false) }
    document.addEventListener('pointerdown', onPointerDown)
    window.addEventListener('scroll', onScroll, true)
    window.addEventListener('resize', onResize)
    return () => {
      document.removeEventListener('pointerdown', onPointerDown)
      window.removeEventListener('scroll', onScroll, true)
      window.removeEventListener('resize', onResize)
    }
  }, [open])

  const filtered = items.filter((m) => m.label.toLowerCase().includes(search.toLowerCase()))
  const label = selected.size === 0
    ? emptyLabel
    : selected.size === 1
      ? items.find((m) => selected.has(m.id))?.label ?? singularLabel
      : `${selected.size} ${pluralLabel}`

  return (
    <div className="country-multi-wrap">
      <button
        ref={btnRef}
        type="button"
        className={`country-multi-trigger${open ? ' open' : ''}`}
        onClick={() => (open ? setOpen(false) : openDropdown())}
        aria-haspopup="listbox"
        aria-expanded={open}
      >
        <span>{label}</span>
        <svg width="12" height="12" viewBox="0 0 12 12" fill="none" aria-hidden="true" style={{ flexShrink: 0, transform: open ? 'rotate(180deg)' : undefined, transition: 'transform 0.15s' }}>
          <path d="M2 4l4 4 4-4" stroke="currentColor" strokeWidth="1.6" strokeLinecap="round" strokeLinejoin="round" />
        </svg>
      </button>

      {open && coords && createPortal(
        <div
          ref={dropRef}
          className="country-multi-dropdown"
          style={{
            position: 'fixed', top: coords.top, bottom: coords.bottom, left: coords.left, width: coords.width,
            maxHeight: coords.maxHeight, overflowY: 'auto',
          }}
          role="listbox"
          aria-multiselectable="true"
        >
          <input
            className="multi-drop-search"
            type="search"
            placeholder={searchPlaceholder}
            value={search}
            onChange={(e) => setSearch(e.target.value)}
            style={{ position: 'sticky', top: 0 }}
            autoFocus
          />
          {filtered.map((m) => (
            <label key={m.id} className="country-multi-opt">
              <input
                type="checkbox"
                checked={selected.has(m.id)}
                onChange={() => { onToggle(m.id); if (closeOnSelect) setOpen(false) }}
              />
              <span>{m.label}</span>
            </label>
          ))}
        </div>,
        document.body,
      )}
    </div>
  )
}

// ── Dashlet form panel ────────────────────────────────────────────────────────

function DashletForm({
  permission,
  metrics,
  kpis,
  groups,
  existingKeys,
  dashboardId,
  sourceType,
  onClose,
}: {
  permission: Permission | null
  metrics: MetricConfig[]
  kpis: KpiDefinition[]
  // Already scoped to dashboardId by the caller — a dashlet's group must
  // belong to its own dashboard.
  groups: DashletGroup[]
  existingKeys: string[]
  // Fixed for the lifetime of this form — a dashlet's dashboard (and the
  // source_type it implies) is set once at creation and never edited
  // afterward, so this comes from the page's currently-selected dashboard,
  // not from anything the form itself lets you change.
  dashboardId: number
  sourceType: 'kpi' | 'salesforce'
  onClose: () => void
}) {
  const saveDashlet = useSaveDashlet()

  const [key, setKey] = useState(permission?.key ?? '')
  // Only relevant for new dashlets — the key auto-follows Label/Role editor
  // section (matching the "dashlet:<section>:<name>" convention every
  // existing dashlet already uses) until the admin edits Key directly,
  // at which point auto-sync stops so we never clobber a deliberate edit.
  const [keyManuallyEdited, setKeyManuallyEdited] = useState(false)
  const [label, setLabel] = useState(permission?.label ?? '')
  const [description, setDescription] = useState(permission?.description ?? '')
  // For a new dashlet, defaults to the dashboard's ungrouped placeholder —
  // but `groups` (useDashletGroups()) can still be an empty array on this
  // form's first render if it's opened before that fetch resolves (e.g.
  // right after switching dashboards). A useState initializer only runs
  // once, so seeding groupId from an empty `groups` here would leave it
  // null forever even after groups loads — the <select> would then show a
  // group visually (browsers fall back to the first <option> when the
  // controlled value matches none) that groupId never actually reflects,
  // and Save would silently submit no group. Adjusted during render instead
  // (not an effect) once groups actually has data, same pattern as the
  // dashboardId-change reset below.
  const [groupId, setGroupId] = useState<number | null>(() => permission?.group_id ?? null)
  const [groupDefaultSeeded, setGroupDefaultSeeded] = useState(!!permission || groups.length > 0)
  if (!permission && !groupDefaultSeeded && groups.length > 0) {
    setGroupId(groups.find((g) => g.is_ungrouped)?.id ?? null)
    setGroupDefaultSeeded(true)
  }
  // parentKey (the RBAC "section") is never independently tracked state —
  // it's always exactly the selected group's own name, computed fresh every
  // render. Storing it separately (synced only inside handleGroupChange) let
  // it silently go stale: editing a dashlet whose group had drifted out of
  // sync with its stored parent_key — or one created before this was a
  // derived value — would carry the stale/blank Section forward forever
  // unless the admin happened to re-touch an already-correct-looking Group
  // dropdown. Deriving it structurally makes that drift impossible.
  const parentKey = groups.find((g) => g.id === groupId)?.name ?? ''
  const [chartType, setChartType] = useState<'none' | 'number' | 'bar' | 'horizontal_bar' | 'pie' | 'table' | 'line'>(permission?.chart_type ?? 'none')
  const [displayMode, setDisplayMode] = useState<'aggregate' | 'timeline'>(permission?.display_mode ?? 'aggregate')
  const [metricIds, setMetricIds] = useState<Set<number>>(() => new Set(permission?.metric_config_ids ?? []))
  const [kpiId, setKpiId] = useState<string | null>(permission?.kpi_id ?? null)
  const [kpiDisagg1Filters, setKpiDisagg1Filters] = useState<Set<string>>(() => new Set(permission?.kpi_disagg1_filters ?? []))
  const [kpiDisagg2Filters, setKpiDisagg2Filters] = useState<Set<string>>(() => new Set(permission?.kpi_disagg2_filters ?? []))
  const [kpiSplitMode, setKpiSplitMode] = useState<'combine' | 'split'>(permission?.kpi_split_mode ?? 'combine')
  const [showMilestone, setShowMilestone] = useState(permission?.show_milestone ?? false)
  const [splitAxisError, setSplitAxisError] = useState<string | null>(null)
  const [comment, setCommentText] = useState(permission?.comment ?? '')
  const [commentEnabled, setCommentEnabled] = useState(permission?.comment_enabled ?? false)
  const [error, setError] = useState<string | null>(null)
  const [dirty, setDirty] = useState(false)
  const markDirty = () => setDirty(true)

  const metricItems = useMemo(() => metrics.map((m) => ({ id: m.id, label: m.metric_name })), [metrics])

  // Group-first narrowing — the full KPI list runs into the dozens, hard to
  // scan as one flat dropdown. Defaults to whichever group the already-
  // selected KPI belongs to (edit mode) so its current value stays visible;
  // "All groups" is still offered for anyone who'd rather search the full list.
  const kpiGroupOptions = useMemo(
    () => [...new Set(kpis.map((k) => k.kpi_group).filter((v): v is string => !!v))].sort(),
    [kpis],
  )
  const [kpiGroupFilter, setKpiGroupFilter] = useState(
    () => kpis.find((k) => k.source_kpi_id === permission?.kpi_id)?.kpi_group ?? '',
  )
  const kpisForGroup = useMemo(
    () => (kpiGroupFilter ? kpis.filter((k) => k.kpi_group === kpiGroupFilter) : kpis)
      .slice()
      .sort((a, b) => a.source_kpi_id.localeCompare(b.source_kpi_id, undefined, { numeric: true })),
    [kpis, kpiGroupFilter],
  )
  // Group is now its own field above, so the label doesn't need to repeat it —
  // "kpino - indicator" instead, ordered by kpino (see sort above).
  const kpiItems = useMemo(() => kpisForGroup.map((k) => ({ id: k.source_kpi_id, label: `${k.source_kpi_id} - ${k.indicator ?? k.source_kpi_id}` })), [kpisForGroup])

  function handleKpiGroupChange(next: string) {
    markDirty()
    setKpiGroupFilter(next)
    // The previously selected indicator almost certainly isn't in the newly
    // chosen group — clear it rather than leave a stale, invisible selection
    // (selectKpi already resets the disagg filters that go with it).
    selectKpi(null)
  }

  const { data: disaggregations = [], isLoading: disaggLoading } = useKpiDisaggregations(kpiId)
  const disagg1Options = useMemo(
    () => [...new Set(disaggregations.map((d) => d.disaggregation_level_one).filter((v): v is string => !!v))],
    [disaggregations],
  )
  const disagg2Options = useMemo(
    () => [...new Set(disaggregations.map((d) => d.disaggregation_level_two).filter((v): v is string => !!v))],
    [disaggregations],
  )
  // Previously-saved selections that no longer show up in this KPI's live
  // distinct values (e.g. the underlying data was re-uploaded with different
  // category names). Never auto-pruned — that could silently widen a
  // dashlet's filter — instead merged back into the picker (see items below)
  // so they stay visible/toggleable, and called out in a warning.
  const staleDisagg1 = useMemo(
    () => disaggLoading ? [] : [...kpiDisagg1Filters].filter((v) => !disagg1Options.includes(v)),
    [kpiDisagg1Filters, disagg1Options, disaggLoading],
  )
  const staleDisagg2 = useMemo(
    () => disaggLoading ? [] : [...kpiDisagg2Filters].filter((v) => !disagg2Options.includes(v)),
    [kpiDisagg2Filters, disagg2Options, disaggLoading],
  )
  const supportsSplit = ['bar', 'horizontal_bar', 'table'].includes(chartType)
  const supportsMilestone = ['bar', 'horizontal_bar', 'number', 'table'].includes(chartType)

  // Key is disabled/unchangeable once editing an existing dashlet (see the
  // input below) — some legacy keys (e.g. dd:*, seeded before this pattern
  // existed) predate the dashlet:name convention, so re-validating them here
  // would permanently block Save on dashlets whose key nobody can actually
  // change through this form. Only gate the create-new flow.
  const keyValid = !!permission || !key.trim() || DASHLET_KEY_PATTERN.test(key.trim())
  // Editing has Key disabled, so a conflict can only arise on create — two
  // auto-generated keys colliding (same Label + Group) is the real case this
  // catches, ahead of the DB's own unique constraint / the 409 it'd 500 into.
  const keyConflict = !permission && !!key.trim() && existingKeys.includes(key.trim())

  function suggestKey(nextLabel: string, nextParentKey: string): string {
    const labelSlug = slugify(nextLabel)
    if (!labelSlug) return ''
    const sectionSlug = slugify(nextParentKey)
    return sectionSlug ? `dashlet:${sectionSlug}:${labelSlug}` : `dashlet:${labelSlug}`
  }

  function handleLabelChange(next: string) {
    markDirty()
    setLabel(next)
    if (!permission && !keyManuallyEdited) setKey(suggestKey(next, parentKey))
  }

  function handleKeyChange(next: string) {
    markDirty()
    setKey(next)
    setKeyManuallyEdited(true)
  }

  function handleGroupChange(id: number | null) {
    markDirty()
    setGroupId(id)
    if (!permission && !keyManuallyEdited) setKey(suggestKey(label, groups.find((g) => g.id === id)?.name ?? ''))
  }

  // These stay in local state even once hidden (see Chart type below), so a
  // chart-type change that hides Split mode / Milestone doesn't silently
  // discard whatever was picked earlier — surfaced here instead of resetting
  // reactively, so the warning is visible for as long as the mismatch exists.
  const willDropSplitMode = kpiSplitMode === 'split' && !supportsSplit
  const willDropMilestone = showMilestone && !supportsMilestone
  const kpiConfiguredButNoChart = sourceType === 'kpi' && !!kpiId && chartType === 'none'
  const metricsConfiguredButNoChart = sourceType === 'salesforce' && metricIds.size > 0 && chartType === 'none'

  // Migration edge case: a dashlet backfilled before source_type was exclusive
  // may still have wiring on the "other side" that this form's toggle hides.
  const hiddenKpiCount = sourceType === 'salesforce' && permission?.kpi_id ? 1 : 0
  const hiddenMetricCount = sourceType === 'kpi' ? (permission?.metric_config_ids.length ?? 0) : 0

  function toggleMetric(id: number) {
    markDirty()
    setMetricIds((prev) => {
      const next = new Set(prev)
      if (next.has(id)) next.delete(id)
      else next.add(id)
      return next
    })
  }

  function selectKpi(id: string | null) {
    markDirty()
    // Disaggregation filters are specific to the previously selected KPI —
    // switching to a different one invalidates them.
    setKpiId(id)
    setKpiDisagg1Filters(new Set())
    setKpiDisagg2Filters(new Set())
    setSplitAxisError(null)
  }

  // A dashlet can split on at most one disaggregation axis at a time (DB
  // CHECK dashlet_kpi_config_one_split_axis) — block a toggle that would
  // push both axes to 2+ selected values, rather than silently clearing the
  // other field.
  function toggleDisagg1(value: string) {
    markDirty()
    setKpiDisagg1Filters((prev) => {
      const next = new Set(prev)
      if (next.has(value)) next.delete(value)
      else next.add(value)
      if (next.size > 1 && kpiDisagg2Filters.size > 1) {
        setSplitAxisError('Only one disaggregation can be split at a time — clear Disaggregation 2 first')
        return prev
      }
      setSplitAxisError(null)
      return next
    })
  }

  function toggleDisagg2(value: string) {
    markDirty()
    setKpiDisagg2Filters((prev) => {
      const next = new Set(prev)
      if (next.has(value)) next.delete(value)
      else next.add(value)
      if (next.size > 1 && kpiDisagg1Filters.size > 1) {
        setSplitAxisError('Only one disaggregation can be split at a time — clear Disaggregation 1 first')
        return prev
      }
      setSplitAxisError(null)
      return next
    })
  }

  function handleClose() {
    if (dirty && !window.confirm('Discard unsaved changes to this dashlet?')) return
    onClose()
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    try {
      await saveDashlet.mutateAsync({
        permissionId: permission?.id,
        key,
        label,
        description,
        parentKey,
        dashboardId,
        groupId,
        chartType: chartType === 'none' ? null : chartType,
        displayMode: chartType === 'none' ? null : displayMode,
        metricConfigIds: sourceType === 'salesforce' ? [...metricIds] : [],
        kpiId: sourceType === 'kpi' ? kpiId : null,
        kpiDisagg1Filters: sourceType === 'kpi' ? [...kpiDisagg1Filters] : [],
        kpiDisagg2Filters: sourceType === 'kpi' ? [...kpiDisagg2Filters] : [],
        kpiSplitMode: sourceType === 'kpi' && supportsSplit ? kpiSplitMode : 'combine',
        showMilestone: sourceType === 'kpi' && supportsMilestone ? showMilestone : false,
        comment: comment.trim() || null,
        isEnabled: commentEnabled,
      })
      onClose()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'An error occurred')
    }
  }

  const saving = saveDashlet.isPending

  return (
    <div className="roles-form-panel">
      <div className="roles-form-header">
        <h2 className="roles-form-title">{permission ? 'Edit Dashlet' : 'New Dashlet'}</h2>
        <button type="button" className="roles-form-close" onClick={handleClose}>✕</button>
      </div>

      <form onSubmit={(e) => void handleSubmit(e)} className="roles-form-body">
        {!permission && (
          <div className="admin-error" style={{ background: 'transparent', border: '1px solid currentColor', opacity: 0.85 }}>
            New dashlets are created as a Draft — even with a Chart type set, nothing appears on its
            dashboard until you click <strong>Publish</strong> from the dashlet list. The legacy
            Data Dashboard is different: a card there still needs a chart component and a
            <code> hasPermission()</code> gate added in code before it will appear.
          </div>
        )}
        {permission?.status === 'published' && (
          <div className="admin-error" style={{ background: 'transparent', border: '1px solid currentColor', opacity: 0.85 }}>
            This dashlet is published. Saving stages your changes as a pending draft — the public
            dashboard keeps showing the current published version until you click <strong>Publish</strong>{' '}
            from the dashlet list.
          </div>
        )}

        <div className="roles-form-field">
          <label className="roles-form-label">Label <span style={{ color: 'var(--red)' }}>*</span></label>
          <input
            className="admin-input"
            value={label}
            onChange={(e) => handleLabelChange(e.target.value)}
            required
            placeholder="e.g. Children Supported"
          />
        </div>
        <div className="roles-form-field">
          <label className="roles-form-label">Group</label>
          <select
            className="admin-input"
            value={groupId ?? ''}
            onChange={(e) => handleGroupChange(e.target.value === '' ? null : Number(e.target.value))}
          >
            {groups.map((g) => (
              <option key={g.id} value={g.id}>{g.name}</option>
            ))}
          </select>
          <span className="admin-table-muted" style={{ fontSize: '0.75rem' }}>
            {sourceType === 'kpi'
              ? 'Section this dashlet appears under on the KPI Dashboard page.'
              : 'Organizational group for this Salesforce dashlet.'} Also sets the role editor's (RBAC) section to this same name. Manage the list of groups on the Groups tab.
          </span>
        </div>
        <div className="roles-form-field">
          <label className="roles-form-label">Description</label>
          <input
            className="admin-input"
            value={description}
            onChange={(e) => { markDirty(); setDescription(e.target.value) }}
            placeholder="Optional description"
          />
        </div>
        <div className="roles-form-field">
          <label className="roles-form-label">Key <span style={{ color: 'var(--red)' }}>*</span></label>
          <input
            className="admin-input"
            value={key}
            onChange={(e) => handleKeyChange(e.target.value)}
            required
            disabled={!!permission}
            placeholder="e.g. dashlet:new_metric"
          />
          {!permission && (
            <span className="admin-table-muted" style={{ fontSize: '0.75rem' }}>
              {keyManuallyEdited
                ? 'Auto-fill paused — edit Label or Group to resume.'
                : 'Auto-filled from Label + Group above — edit directly to override.'}
            </span>
          )}
          {!keyValid && (
            <div className="admin-error" style={{ marginTop: 4 }}>
              Key must look like <code>dashlet:name</code> or <code>dashlet:section:name</code> (lowercase, letters/numbers/underscores only).
            </div>
          )}
          {keyValid && keyConflict && (
            <div className="admin-error" style={{ marginTop: 4 }}>
              A dashlet with this key already exists — edit Label or Group above, or the Key field directly, to make it unique.
            </div>
          )}
        </div>

        {sourceType === 'kpi' ? (
          <>
            <div className="roles-form-section-label">KPI Group</div>
            <select
              className="admin-input"
              value={kpiGroupFilter}
              onChange={(e) => handleKpiGroupChange(e.target.value)}
              style={{ marginBottom: 12 }}
            >
              <option value="">All groups</option>
              {kpiGroupOptions.map((g) => (
                <option key={g} value={g}>{g}</option>
              ))}
            </select>

            <div className="roles-form-section-label">KPI Indicator</div>
            <select
              className="admin-input"
              value={kpiId ?? ''}
              onChange={(e) => selectKpi(e.target.value === '' ? null : e.target.value)}
            >
              <option value="">No KPI indicator selected</option>
              {kpiItems.map((k) => (
                <option key={k.id} value={k.id}>{k.label}</option>
              ))}
            </select>
            {hiddenMetricCount > 0 && (
              <span className="admin-table-muted" style={{ fontSize: '0.75rem', display: 'block', marginTop: 4 }}>
                {hiddenMetricCount} metric(s) hidden — switch to Salesforce to view/edit them.
              </span>
            )}

            {kpiId && (
              <>
                <div className="roles-form-field" style={{ marginTop: 12 }}>
                  <label className="roles-form-label">Disaggregation 1</label>
                  {disaggLoading ? (
                    <div className="admin-loading" style={{ fontSize: '0.8rem' }}>Loading values…</div>
                  ) : (
                    <ItemPicker
                      items={[...disagg1Options, ...staleDisagg1].map((v) => ({
                        id: v,
                        label: staleDisagg1.includes(v) ? `${v} (no longer in data)` : v,
                      }))}
                      selected={kpiDisagg1Filters}
                      onToggle={toggleDisagg1}
                      emptyLabel="No filter (all values)"
                      singularLabel="1 value selected"
                      pluralLabel="values selected"
                      searchPlaceholder="Search…"
                    />
                  )}
                  <span className="admin-table-muted" style={{ fontSize: '0.75rem' }}>
                    Which rows to include on this axis (e.g. "Annual" vs "Newly supported", or "Government trained" vs "SHF Agriculture trained"). Leave empty to include every value — selecting 2+ makes this the split axis (see Combine / split below).
                  </span>
                  {staleDisagg1.length > 0 && (
                    <div className="admin-warning" style={{ marginTop: 4 }}>
                      {staleDisagg1.length === 1 ? 'This value is' : 'These values are'} no longer in this KPI's current data: {staleDisagg1.join(', ')}. Still saved as-is unless you uncheck {staleDisagg1.length === 1 ? 'it' : 'them'} above.
                    </div>
                  )}
                </div>

                <div className="roles-form-field">
                  <label className="roles-form-label">Disaggregation 2</label>
                  {disaggLoading ? (
                    <div className="admin-loading" style={{ fontSize: '0.8rem' }}>Loading values…</div>
                  ) : (
                    <ItemPicker
                      items={[...disagg2Options, ...staleDisagg2].map((v) => ({
                        id: v,
                        label: staleDisagg2.includes(v) ? `${v} (no longer in data)` : v,
                      }))}
                      selected={kpiDisagg2Filters}
                      onToggle={toggleDisagg2}
                      emptyLabel="No filter (all values)"
                      singularLabel="1 value selected"
                      pluralLabel="values selected"
                      searchPlaceholder="Search…"
                    />
                  )}
                  <span className="admin-table-muted" style={{ fontSize: '0.75rem' }}>
                    Which rows to include on this axis. Leave empty to include every value — selecting 2+ makes this the split axis instead of Disaggregation 1.
                  </span>
                  {staleDisagg2.length > 0 && (
                    <div className="admin-warning" style={{ marginTop: 4 }}>
                      {staleDisagg2.length === 1 ? 'This value is' : 'These values are'} no longer in this KPI's current data: {staleDisagg2.join(', ')}. Still saved as-is unless you uncheck {staleDisagg2.length === 1 ? 'it' : 'them'} above.
                    </div>
                  )}
                </div>

                {splitAxisError && <div className="admin-error">{splitAxisError}</div>}

              </>
            )}
          </>
        ) : (
          <>
            <div className="roles-form-section-label">Metrics</div>
            <ItemPicker
              items={metricItems}
              selected={metricIds}
              onToggle={toggleMetric}
              emptyLabel="No metrics selected"
              singularLabel="1 metric"
              pluralLabel="metrics selected"
              searchPlaceholder="Search metrics…"
            />
            {hiddenKpiCount > 0 && (
              <span className="admin-table-muted" style={{ fontSize: '0.75rem', display: 'block', marginTop: 4 }}>
                {hiddenKpiCount} KPI indicator(s) hidden — switch to KPI to view/edit them.
              </span>
            )}
          </>
        )}

        <div className="roles-form-field" style={{ marginTop: 16 }}>
          <label className="roles-form-label">Chart type</label>
          <select
            className="admin-input"
            value={chartType}
            onChange={(e) => { markDirty(); setChartType(e.target.value as 'none' | 'number' | 'bar' | 'horizontal_bar' | 'pie' | 'table' | 'line') }}
          >
            <option value="none">
              {sourceType === 'kpi' ? 'None — not shown on KPI Dashboard' : 'None — not shown on Salesforce Dashboard'}
            </option>
            <option value="number">Number (sum across selected countries)</option>
            <option value="bar">Bar (one bar per country)</option>
            <option value="horizontal_bar">Horizontal bar (one bar per country, sideways)</option>
            <option value="pie">Pie (each country's share of the total)</option>
            <option value="table">Table (exact figures per country)</option>
            {sourceType === 'salesforce' && (
              <option value="line">Line (trend across the selected year range — single metric only)</option>
            )}
          </select>
        </div>

        {kpiConfiguredButNoChart && (
          <div className="admin-warning">
            A KPI indicator is selected but Chart type is "None" — this dashlet will not appear on the KPI Dashboard until you pick a chart type.
          </div>
        )}
        {metricsConfiguredButNoChart && (
          <div className="admin-warning">
            Metric(s) are selected but Chart type is "None" — this dashlet will not appear on the Salesforce Dashboard until you pick a chart type.
          </div>
        )}
        {willDropSplitMode && (
          <div className="admin-warning">
            Split mode is set to "Split" but "{chartType}" doesn't support it — saving now will reset it to Combine.
          </div>
        )}
        {willDropMilestone && (
          <div className="admin-warning">
            "Show milestone" is checked but "{chartType}" doesn't support it — saving now will turn it off.
          </div>
        )}

        {sourceType === 'kpi' && kpiId && supportsMilestone && (
          <label className="roles-perm-all" style={{ gap: 10 }}>
            <input
              type="checkbox"
              checked={showMilestone}
              onChange={(e) => { markDirty(); setShowMilestone(e.target.checked) }}
            />
            <span>Show milestone on this dashlet</span>
          </label>
        )}

        {(kpiDisagg1Filters.size > 1 || kpiDisagg2Filters.size > 1) && supportsSplit && (
          <div className="roles-form-field">
            <label className="roles-form-label">Combine / split</label>
            <div role="group" aria-label="Combine or split selected slices" style={{ display: 'flex', gap: 16, fontSize: '0.86rem' }}>
              <label style={{ display: 'inline-flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}>
                <input type="radio" checked={kpiSplitMode === 'combine'} onChange={() => { markDirty(); setKpiSplitMode('combine') }} />
                Combine (sum into one)
              </label>
              <label style={{ display: 'inline-flex', alignItems: 'center', gap: 6, cursor: 'pointer' }}>
                <input type="radio" checked={kpiSplitMode === 'split'} onChange={() => { markDirty(); setKpiSplitMode('split') }} />
                Split (show separately)
              </label>
            </div>
          </div>
        )}

        {chartType !== 'none' && sourceType === 'kpi' && (
          <div className="roles-form-field">
            <label className="roles-form-label">Display mode</label>
            <select
              className="admin-input"
              value={displayMode}
              onChange={(e) => { markDirty(); setDisplayMode(e.target.value as 'aggregate' | 'timeline') }}
            >
              <option value="aggregate">Aggregate (single value/snapshot)</option>
              {/* "Timeline" isn't wired up to any different rendering yet — the KPI
                  Dashboard always renders the aggregate snapshot regardless of this
                  value. Kept selectable only for the handful of dashlets already set
                  to it (so editing them for something unrelated doesn't silently flip
                  this back), not offered as a real choice for anything else. */}
              {(permission?.display_mode === 'timeline' || displayMode === 'timeline') && (
                <option value="timeline">Timeline (not implemented yet — renders identically to Aggregate)</option>
              )}
            </select>
          </div>
        )}

        <div className="roles-form-section-label" style={{ marginTop: 16 }}>Hover comment</div>
        <div className="roles-form-field">
          <textarea
            className="admin-input"
            value={comment}
            onChange={(e) => { markDirty(); setCommentText(e.target.value) }}
            placeholder="Text shown in the dashlet's comment hover"
            rows={3}
          />
        </div>
        <label className="roles-perm-all" style={{ gap: 10 }}>
          <input
            type="checkbox"
            checked={commentEnabled}
            onChange={(e) => { markDirty(); setCommentEnabled(e.target.checked) }}
          />
          <span>Show comment on dashboard</span>
        </label>

        {error && <div className="admin-error">{error}</div>}

        <div className="roles-form-actions">
          <button type="button" className="admin-btn admin-btn--secondary" style={{ flex: 1 }} onClick={handleClose}>Cancel</button>
          <button type="submit" className="admin-btn admin-btn--primary" style={{ flex: 1 }} disabled={saving || !key.trim() || !label.trim() || !keyValid || keyConflict}>
            {saving ? 'Saving…' : permission ? 'Save Changes' : 'Create Dashlet'}
          </button>
        </div>
      </form>
    </div>
  )
}

// ── History panel ─────────────────────────────────────────────────────────────

function summarizeDashletSnapshot(s: Record<string, unknown>): string {
  const metricCount = (Array.isArray(s.metric_config_ids) ? s.metric_config_ids.length : 0) + (s.kpi_id ? 1 : 0)
  const chart = s.chart_type ? ` — ${String(s.chart_type)} chart` : ''
  const disagg1Count = Array.isArray(s.kpi_disagg1_filters) ? s.kpi_disagg1_filters.length : 0
  const disagg2Count = Array.isArray(s.kpi_disagg2_filters) ? s.kpi_disagg2_filters.length : 0
  const disaggParts: string[] = []
  if (disagg1Count > 0) disaggParts.push(`disagg1: ${disagg1Count}`)
  if (disagg2Count > 0) disaggParts.push(`disagg2: ${disagg2Count}`)
  const disagg = disaggParts.length > 0 ? `, ${disaggParts.join(', ')}` : ''
  const split = s.kpi_split_mode === 'split' ? ', split' : ''
  const milestone = s.show_milestone ? ', milestone on' : ''
  return `"${s.label ?? s.key}" — ${s.source_type ?? 'kpi'}, section: ${s.parent_key ?? '—'}, ${metricCount} metric(s), comment ${s.comment_enabled ? 'on' : 'off'}${chart}${disagg}${split}${milestone}`
}

function summarizeMetricConfigSnapshot(s: Record<string, unknown>): string {
  const agg = s.value_agg === 'sum' && s.value_field ? `sum(${s.value_field})` : String(s.value_agg ?? '')
  return `"${s.metric_name}" — ${s.source_view}, ${agg}, ${s.enabled ? 'enabled' : 'disabled'}`
}

function HistoryPanel({
  title,
  entries,
  loading,
  onRestore,
  restoring,
  onClose,
  summarize,
}: {
  title: string
  entries: HistoryEntry[]
  loading: boolean
  onRestore: (historyId: number) => void
  restoring: boolean
  onClose: () => void
  summarize: (snapshot: Record<string, unknown>) => string
}) {
  const [confirmingId, setConfirmingId] = useState<number | null>(null)

  return (
    <div className="roles-form-panel">
      <div className="roles-form-header">
        <h2 className="roles-form-title">{title}</h2>
        <button type="button" className="roles-form-close" onClick={onClose}>✕</button>
      </div>

      <div className="roles-form-body">
        {loading ? (
          <div className="admin-loading">Loading…</div>
        ) : entries.length === 0 ? (
          <div className="admin-empty">No history yet.</div>
        ) : (
          entries.map((h) => (
            <div key={h.id} style={{ border: '1px solid var(--border)', borderRadius: 8, padding: 12 }}>
              <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 6 }}>
                <span className="admin-badge admin-badge--blue">{h.change_type}</span>
                <span className="admin-table-muted" style={{ fontSize: '0.75rem' }}>
                  {new Date(h.changed_at).toLocaleString()}{h.changed_by_email ? ` — ${h.changed_by_email}` : ''}
                </span>
              </div>
              <div style={{ fontSize: '0.85rem', marginBottom: 8 }}>{summarize(h.snapshot)}</div>
              {confirmingId === h.id ? (
                <div style={{ display: 'flex', gap: 8 }}>
                  <span style={{ fontSize: '0.8rem', flex: 1 }}>Overwrite current values with this version?</span>
                  <button type="button" className="admin-btn admin-btn--sm admin-btn--secondary" onClick={() => setConfirmingId(null)}>Cancel</button>
                  <button
                    type="button"
                    className="admin-btn admin-btn--sm admin-btn--danger"
                    disabled={restoring}
                    onClick={() => { onRestore(h.id); setConfirmingId(null) }}
                  >
                    {restoring ? 'Restoring…' : 'Confirm restore'}
                  </button>
                </div>
              ) : (
                <button type="button" className="admin-btn admin-btn--sm admin-btn--secondary" onClick={() => setConfirmingId(h.id)}>
                  Restore this version
                </button>
              )}
            </div>
          ))
        )}
      </div>
    </div>
  )
}

// ── Delete confirm modal ──────────────────────────────────────────────────────

function DeleteConfirm({ permission, onConfirm, onCancel, loading }: { permission: Permission; onConfirm: () => void; onCancel: () => void; loading: boolean }) {
  return (
    <div className="admin-modal-backdrop">
      <div className="admin-modal">
        <h3 className="admin-modal-title">Delete Dashlet</h3>
        <p>Delete <strong>{permission.label}</strong>? This removes its metric mapping and comment, and unassigns it from any roles that have it. This cannot be undone.</p>
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

// Shared confirm dialog for the publish-workflow actions (Publish, Unpublish,
// Discard draft) — same visual pattern as DeleteConfirm, but the message and
// button variant vary per action rather than being three near-identical
// bespoke components.
function ActionConfirm({
  title,
  message,
  confirmLabel,
  confirmingLabel,
  confirmVariant = 'primary',
  onConfirm,
  onCancel,
  loading,
}: {
  title: string
  message: React.ReactNode
  confirmLabel: string
  confirmingLabel: string
  confirmVariant?: 'primary' | 'danger'
  onConfirm: () => void
  onCancel: () => void
  loading: boolean
}) {
  return (
    <div className="admin-modal-backdrop">
      <div className="admin-modal">
        <h3 className="admin-modal-title">{title}</h3>
        <p>{message}</p>
        <div className="admin-modal-actions">
          <button className="admin-btn admin-btn--secondary" onClick={onCancel} disabled={loading}>Cancel</button>
          <button className={`admin-btn admin-btn--${confirmVariant}`} onClick={onConfirm} disabled={loading}>
            {loading ? confirmingLabel : confirmLabel}
          </button>
        </div>
      </div>
    </div>
  )
}

// ── Filter row builder ────────────────────────────────────────────────────────

type FilterOp = 'eq' | 'ilike' | 'bool_true' | 'not_null'
interface FilterRow { field: string; op: FilterOp; value: string }

function parseFilterRows(filters: unknown): FilterRow[] {
  if (!Array.isArray(filters)) return []
  return filters
    .filter((f): f is Record<string, unknown> => typeof f === 'object' && f !== null)
    .map((f) => ({
      field: typeof f.field === 'string' ? f.field : '',
      op: (['eq', 'ilike', 'bool_true', 'not_null'].includes(f.op as string) ? f.op : 'eq') as FilterOp,
      value: typeof f.value === 'string' ? f.value : '',
    }))
}

function FilterBuilderRow({
  row,
  sourceView,
  columns,
  onChange,
  onRemove,
}: {
  row: FilterRow
  sourceView: string
  columns: ViewColumn[]
  onChange: (patch: Partial<FilterRow>) => void
  onRemove: () => void
}) {
  const { data: valuesResult, isLoading, isError } = useViewColumnValues(sourceView, row.op === 'eq' ? row.field : undefined)
  const values = valuesResult?.values ?? []
  const stillFetching = row.op === 'eq' && isLoading && values.length === 0 && !isError
  // Fall back to free text whenever the picker can't offer real values yet —
  // during the initial fetch, on RPC error, or when the column has none —
  // so admins are never blocked from setting a value.
  const usePicker = row.op === 'eq' && !isError && !stillFetching && values.length > 0

  return (
    <div style={{ display: 'flex', flexWrap: 'wrap', gap: 6, marginBottom: 6, alignItems: 'center' }}>
      <select
        className="admin-input"
        value={row.field}
        onChange={(e) => onChange({ field: e.target.value, value: '' })}
        style={{ flex: 1 }}
      >
        {columns.map((c) => <option key={c.column_name} value={c.column_name}>{c.column_name}</option>)}
      </select>
      <select
        className="admin-input"
        value={row.op}
        onChange={(e) => onChange({ op: e.target.value as FilterOp, value: '' })}
        style={{ width: 110, flexShrink: 0 }}
      >
        <option value="eq">equals</option>
        <option value="ilike">contains</option>
        <option value="bool_true">is true</option>
        <option value="not_null">is set</option>
      </select>
      {row.op === 'eq' && usePicker && (
        <span style={{ display: 'flex', flexDirection: 'column', flex: 1 }}>
          <ItemPicker
            items={(row.value && !values.includes(row.value) ? [row.value, ...values] : values).map((v) => ({ id: v, label: v }))}
            selected={row.value ? new Set([row.value]) : new Set<string>()}
            onToggle={(v) => onChange({ value: v === row.value ? '' : v })}
            closeOnSelect
            emptyLabel="Select a value…"
            singularLabel="1 value selected"
            pluralLabel="values selected"
            searchPlaceholder="Search values…"
          />
          {valuesResult?.truncated && (
            <span title="Showing the first 500 values" style={{ color: 'var(--red)', fontSize: '0.7rem', fontWeight: 700 }}>
              500+ values, showing first 500
            </span>
          )}
        </span>
      )}
      {((row.op === 'eq' && !usePicker) || row.op === 'ilike') && (
        <span style={{ position: 'relative', flex: 1, display: 'flex' }}>
          <input
            className="admin-input"
            value={row.value}
            onChange={(e) => onChange({ value: e.target.value })}
            placeholder={stillFetching ? 'Loading values…' : 'value'}
            disabled={stillFetching}
            style={{ flex: 1 }}
          />
          {stillFetching && (
            <span
              aria-hidden="true"
              style={{
                position: 'absolute', right: 8, top: '50%', width: 12, height: 12, marginTop: -6,
                border: '2px solid var(--border)', borderTopColor: 'var(--purple)', borderRadius: '50%',
                animation: 'admin-picker-spin 0.7s linear infinite',
              }}
            />
          )}
        </span>
      )}
      <button type="button" className="admin-btn admin-btn--sm admin-btn--danger" onClick={onRemove}>✕</button>
    </div>
  )
}

function FilterBuilder({
  rows,
  onChange,
  columns,
  sourceView,
}: {
  rows: FilterRow[]
  onChange: (rows: FilterRow[]) => void
  columns: ViewColumn[]
  sourceView: string
}) {
  function updateRow(i: number, patch: Partial<FilterRow>) {
    onChange(rows.map((r, idx) => (idx === i ? { ...r, ...patch } : r)))
  }
  function removeRow(i: number) {
    onChange(rows.filter((_, idx) => idx !== i))
  }
  function addRow() {
    onChange([...rows, { field: columns[0]?.column_name ?? '', op: 'eq', value: '' }])
  }

  return (
    <div className="roles-form-field">
      <label className="roles-form-label">Filters</label>
      {rows.map((row, i) => (
        <FilterBuilderRow
          key={i}
          row={row}
          sourceView={sourceView}
          columns={columns}
          onChange={(patch) => updateRow(i, patch)}
          onRemove={() => removeRow(i)}
        />
      ))}
      <button type="button" className="admin-btn admin-btn--sm admin-btn--secondary" onClick={addRow}>
        + Add filter
      </button>
    </div>
  )
}

// ── Metric config form panel ──────────────────────────────────────────────────

function MetricConfigForm({
  metric,
  onClose,
}: {
  metric: MetricConfigFull | null
  onClose: () => void
}) {
  const createMetric = useCreateMetricConfig()
  const updateMetric = useUpdateMetricConfig()

  const [metricName, setMetricName] = useState(metric?.metric_name ?? '')
  const [sourceView, setSourceView] = useState(metric?.source_view ?? SOURCE_VIEWS[0])
  const [yearField, setYearField] = useState(metric?.year_field ?? 'year')
  const [valueAgg, setValueAgg] = useState<'count' | 'sum'>(metric?.value_agg ?? 'count')
  const [valueField, setValueField] = useState(metric?.value_field ?? '')
  const [geographyLevel, setGeographyLevel] = useState<'school' | 'district'>(metric?.geography_level ?? 'school')
  const [filterRows, setFilterRows] = useState<FilterRow[]>(() => parseFilterRows(metric?.filters))
  const [enabled, setEnabled] = useState(metric?.enabled ?? true)
  const [sortOrder, setSortOrder] = useState(metric?.sort_order != null ? String(metric.sort_order) : '')
  const [error, setError] = useState<string | null>(null)

  const { data: columns = [] } = useViewColumns(sourceView)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    const filters = filterRows
      .filter((r) => r.field)
      .map((r) => (r.op === 'bool_true' || r.op === 'not_null' ? { field: r.field, op: r.op } : { field: r.field, op: r.op, value: r.value }))
    try {
      const payload = {
        metricName,
        sourceView,
        yearField,
        valueAgg,
        valueField: valueAgg === 'sum' ? (valueField.trim() || null) : null,
        geographyLevel,
        filters,
        enabled,
        sortOrder: sortOrder.trim() === '' ? null : Number(sortOrder),
      }
      if (metric) {
        await updateMetric.mutateAsync({ metricId: metric.id, ...payload })
      } else {
        await createMetric.mutateAsync(payload)
      }
      onClose()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'An error occurred')
    }
  }

  const saving = createMetric.isPending || updateMetric.isPending

  return (
    <div className="roles-form-panel">
      <div className="roles-form-header">
        <h2 className="roles-form-title">{metric ? 'Edit Metric' : 'New Metric'}</h2>
        <button type="button" className="roles-form-close" onClick={onClose}>✕</button>
      </div>

      <form onSubmit={(e) => void handleSubmit(e)} className="roles-form-body">
        <div className="roles-form-field">
          <label className="roles-form-label">Metric name</label>
          <input
            className="admin-input"
            value={metricName}
            onChange={(e) => setMetricName(e.target.value)}
            required
            placeholder="e.g. Children Supported — SHFs"
          />
        </div>
        <div className="roles-form-field">
          <label className="roles-form-label">Source view</label>
          <select
            className="admin-input"
            value={sourceView}
            onChange={(e) => { setSourceView(e.target.value); setYearField(''); setFilterRows([]) }}
          >
            {SOURCE_VIEWS.map((v) => <option key={v} value={v}>{v}</option>)}
          </select>
        </div>
        <div className="roles-form-field">
          <label className="roles-form-label">Year field</label>
          <select className="admin-input" value={yearField} onChange={(e) => setYearField(e.target.value)}>
            <option value="" disabled>Select a column…</option>
            {columns.map((c) => <option key={c.column_name} value={c.column_name}>{c.column_name}</option>)}
          </select>
        </div>
        <div className="roles-form-field">
          <label className="roles-form-label">Aggregation</label>
          <select className="admin-input" value={valueAgg} onChange={(e) => setValueAgg(e.target.value as 'count' | 'sum')}>
            <option value="count">count</option>
            <option value="sum">sum</option>
          </select>
        </div>
        {valueAgg === 'sum' && (
          <div className="roles-form-field">
            <label className="roles-form-label">Value field (for sum)</label>
            <select className="admin-input" value={valueField} onChange={(e) => setValueField(e.target.value)}>
              <option value="" disabled>Select a column…</option>
              {columns.filter((c) => NUMERIC_TYPES.has(c.data_type)).map((c) => <option key={c.column_name} value={c.column_name}>{c.column_name}</option>)}
            </select>
            <span className="admin-table-muted" style={{ fontSize: '0.75rem' }}>
              Only numeric columns are shown — summing text/date/boolean columns doesn't make sense.
            </span>
          </div>
        )}
        <div className="roles-form-field">
          <label className="roles-form-label">Geography level</label>
          <select className="admin-input" value={geographyLevel} onChange={(e) => setGeographyLevel(e.target.value as 'school' | 'district')}>
            <option value="school">school</option>
            <option value="district">district</option>
          </select>
        </div>
        <div className="roles-form-field">
          <label className="roles-form-label">Sort order</label>
          <input
            className="admin-input"
            type="number"
            value={sortOrder}
            onChange={(e) => setSortOrder(e.target.value)}
            placeholder="e.g. 10"
          />
        </div>

        <FilterBuilder rows={filterRows} onChange={setFilterRows} columns={columns} sourceView={sourceView} />

        <label className="roles-perm-all" style={{ gap: 10 }}>
          <input
            type="checkbox"
            checked={enabled}
            onChange={(e) => setEnabled(e.target.checked)}
          />
          <span>Enabled</span>
        </label>

        {error && <div className="admin-error">{error}</div>}

        <div className="roles-form-actions">
          <button type="button" className="admin-btn admin-btn--secondary" style={{ flex: 1 }} onClick={onClose}>Cancel</button>
          <button type="submit" className="admin-btn admin-btn--primary" style={{ flex: 1 }} disabled={saving || !metricName.trim() || !sourceView.trim() || !yearField}>
            {saving ? 'Saving…' : metric ? 'Save Changes' : 'Create Metric'}
          </button>
        </div>
      </form>
    </div>
  )
}

// ── Delete metric confirm modal ───────────────────────────────────────────────

function DeleteMetricConfirm({ metric, onConfirm, onCancel, loading }: { metric: MetricConfigFull; onConfirm: () => void; onCancel: () => void; loading: boolean }) {
  return (
    <div className="admin-modal-backdrop">
      <div className="admin-modal">
        <h3 className="admin-modal-title">Delete Metric</h3>
        <p>Delete <strong>{metric.metric_name}</strong>? This unwires it from any dashlets currently using it. This cannot be undone.</p>
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

// ── Metric config tab ─────────────────────────────────────────────────────────

function MetricConfigTab() {
  const { data: metrics = [], isLoading } = useMetricConfigList()
  const { data: dashletGroups = [] } = useAllDashletGroups()
  const deleteMetric = useDeleteMetricConfig()
  const restoreMetric = useRestoreMetricConfig()

  const [formMetric, setFormMetric] = useState<MetricConfigFull | 'new' | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<MetricConfigFull | null>(null)
  const [deleteError, setDeleteError] = useState<string | null>(null)
  const [historyMetricId, setHistoryMetricId] = useState<number | null>(null)
  const [groupFilter, setGroupFilter] = useState('')
  const { data: historyEntries = [], isLoading: historyLoading } = useMetricConfigHistory(historyMetricId)

  // metric_config is always Salesforce-side.
  const salesforceGroups = useMemo(() => dashletGroups.filter((g) => g.source_type === 'salesforce'), [dashletGroups])
  const filteredMetrics = useMemo(
    () => groupFilter ? metrics.filter((m) => m.groups.some((g) => String(g.id) === groupFilter)) : metrics,
    [metrics, groupFilter],
  )

  const columns: AdminColumn<MetricConfigFull>[] = useMemo(() => [
    { key: 'metric_name', header: 'Metric name', sortValue: (m) => m.metric_name, render: (m) => <span className="admin-table-name">{m.metric_name}</span> },
    { key: 'source_view', header: 'Source view', sortValue: (m) => m.source_view, render: (m) => <span className="admin-table-muted">{m.source_view}</span> },
    { key: 'value_agg', header: 'Aggregation', sortValue: (m) => m.value_agg, render: (m) => <span className="admin-table-muted">{m.value_agg}{m.value_agg === 'sum' && m.value_field ? ` (${m.value_field})` : ''}</span> },
    { key: 'geography_level', header: 'Geography', sortValue: (m) => m.geography_level, render: (m) => <span className="admin-table-muted">{m.geography_level}</span> },
    { key: 'groups', header: 'Group(s)', render: (m) => <span className="admin-table-muted">{m.groups.length > 0 ? m.groups.map((g) => g.name).join(', ') : '—'}</span> },
    {
      key: 'enabled', header: 'Enabled', sortValue: (m) => (m.enabled ? 1 : 0),
      render: (m) => m.enabled
        ? <span className="admin-badge admin-badge--green">✓ Enabled</span>
        : <span className="admin-badge admin-badge--grey">—</span>,
    },
  ], [])

  async function handleDelete(metric: MetricConfigFull) {
    setDeleteError(null)
    try {
      await deleteMetric.mutateAsync(metric.id)
      setDeleteTarget(null)
    } catch (err) {
      setDeleteError(err instanceof Error ? err.message : 'Delete failed')
    }
  }

  return (
    <div>
      <div className="admin-page-header">
        <select className="admin-select" value={groupFilter} onChange={(e) => setGroupFilter(e.target.value)}>
          <option value="">All groups</option>
          {salesforceGroups.map((g) => (
            <option key={g.id} value={g.id}>{g.name}</option>
          ))}
        </select>
        <button className="admin-btn admin-btn--primary" onClick={() => setFormMetric('new')}>
          + New Metric
        </button>
      </div>

      {metrics.length === 0 && !isLoading ? (
        <div className="admin-empty">No metrics yet. Create one to get started.</div>
      ) : (
        <AdminDataTable
          data={filteredMetrics}
          rowKey={(m) => m.id}
          columns={columns}
          isLoading={isLoading}
          emptyMessage="No metrics match this filter."
          rowActions={(m) => [
            { label: 'Edit', onClick: () => setFormMetric(m) },
            { label: 'History', onClick: () => setHistoryMetricId(m.id) },
            { label: 'Delete', variant: 'danger', onClick: () => { setDeleteError(null); setDeleteTarget(m) } },
          ]}
        />
      )}

      {deleteError && <div className="admin-error" style={{ marginTop: 12 }}>{deleteError}</div>}

      {formMetric !== null && (
        <MetricConfigForm
          metric={formMetric === 'new' ? null : formMetric}
          onClose={() => setFormMetric(null)}
        />
      )}

      {deleteTarget && (
        <DeleteMetricConfirm
          metric={deleteTarget}
          onConfirm={() => void handleDelete(deleteTarget)}
          onCancel={() => setDeleteTarget(null)}
          loading={deleteMetric.isPending}
        />
      )}

      {historyMetricId !== null && (
        <HistoryPanel
          title="Metric History"
          entries={historyEntries}
          loading={historyLoading}
          onRestore={(historyId) => restoreMetric.mutate(historyId)}
          restoring={restoreMetric.isPending}
          onClose={() => setHistoryMetricId(null)}
          summarize={summarizeMetricConfigSnapshot}
        />
      )}
    </div>
  )
}

// ── Dashlets tab ──────────────────────────────────────────────────────────────

function DashletsListTab({ dashboard }: { dashboard: Dashboard }) {
  const dashboardId = dashboard.id
  const { data: permissions = [], isLoading: permsLoading } = usePermissions()
  const { data: metrics = [], isLoading: metricsLoading } = useMetricConfigs()
  const { data: kpis = [], isLoading: kpisLoading } = useKpiDefinitions()
  const { data: dashletGroups = [] } = useDashletGroups(dashboardId)
  const deletePermission = useDeletePermission()
  const restorePermission = useRestoreDashlet()
  const publishDashlet = usePublishDashlet()
  const unpublishDashlet = useUnpublishDashlet()
  const discardDraft = useDiscardDashletDraft()

  const [formPermission, setFormPermission] = useState<Permission | 'new' | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<Permission | null>(null)
  const [deleteError, setDeleteError] = useState<string | null>(null)
  const [actionError, setActionError] = useState<string | null>(null)
  const [publishTarget, setPublishTarget] = useState<Permission | null>(null)
  const [unpublishTarget, setUnpublishTarget] = useState<Permission | null>(null)
  const [discardTarget, setDiscardTarget] = useState<Permission | null>(null)
  const [groupFilter, setGroupFilter] = useState('')
  const [historyKey, setHistoryKey] = useState<string | null>(null)
  const { data: historyEntries = [], isLoading: historyLoading } = useDashletHistory(historyKey)

  // Switching dashboards clears a group filter that almost certainly doesn't
  // apply to the new one — groups are scoped per dashboard, so a stale id
  // would otherwise silently filter the list to nothing. Adjusted during
  // render (not an effect) per React's reset-state-on-prop-change pattern.
  const [groupFilterDashboardId, setGroupFilterDashboardId] = useState(dashboardId)
  if (dashboardId !== groupFilterDashboardId) {
    setGroupFilterDashboardId(dashboardId)
    setGroupFilter('')
  }

  const allDashlets = useMemo(
    () => permissions
      .filter((p) => p.category === 'dashlet' && p.dashboard_id === dashboardId)
      .sort((a, b) => (a.parent_key ?? '').localeCompare(b.parent_key ?? '') || a.label.localeCompare(b.label)),
    [permissions, dashboardId],
  )

  const groupOptions = useMemo(
    () => dashletGroups
      .slice()
      .sort((a, b) => a.display_order - b.display_order || a.name.localeCompare(b.name)),
    [dashletGroups],
  )

  const dashlets = useMemo(
    () => allDashlets.filter((p) => !groupFilter || String(p.group_id ?? '') === groupFilter),
    [allDashlets, groupFilter],
  )
  const { page, setPage, pageData: pagedDashlets, totalPages, total } = usePagination(dashlets)

  async function handleDelete(permission: Permission) {
    setDeleteError(null)
    try {
      await deletePermission.mutateAsync(permission.id)
      setDeleteTarget(null)
    } catch (err) {
      setDeleteError(err instanceof Error ? err.message : 'Delete failed')
    }
  }

  async function handlePublish(permission: Permission) {
    setActionError(null)
    try {
      await publishDashlet.mutateAsync(permission.id)
      setPublishTarget(null)
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'Publish failed')
    }
  }

  async function handleUnpublish(permission: Permission) {
    setActionError(null)
    try {
      await unpublishDashlet.mutateAsync(permission.id)
      setUnpublishTarget(null)
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'Unpublish failed')
    }
  }

  async function handleDiscardDraft(permission: Permission) {
    setActionError(null)
    try {
      await discardDraft.mutateAsync(permission.id)
      setDiscardTarget(null)
    } catch (err) {
      setActionError(err instanceof Error ? err.message : 'Discard failed')
    }
  }

  const loading = permsLoading || metricsLoading || kpisLoading

  return (
    <div>
      <div className="admin-page-header">
        <div className="admin-header-group">
          <select className="admin-select" value={groupFilter} onChange={(e) => setGroupFilter(e.target.value)}>
            <option value="">All groups</option>
            {groupOptions.map((g) => (
              <option key={g.id} value={g.id}>{g.name}</option>
            ))}
          </select>
        </div>
        <div className="admin-header-group">
          <button
            className="admin-btn admin-btn--primary"
            onClick={() => setFormPermission('new')}
          >
            + New Dashlet
          </button>
          <a
            className="admin-btn admin-btn--secondary"
            href={`/${dashboard.source_type}-dashboard?preview=1${dashboard.is_default ? '' : `&dashboard=${encodeURIComponent(dashboard.key)}`}`}
            target="_blank"
            rel="noreferrer"
          >
            Preview {dashboard.label}
          </a>
        </div>
      </div>

      {actionError && <div className="admin-error" style={{ marginTop: 12 }}>{actionError}</div>}

      {loading ? (
        <div className="admin-loading">Loading…</div>
      ) : allDashlets.length === 0 ? (
        <div className="admin-empty">No dashlets on this dashboard yet. Create one to get started.</div>
      ) : dashlets.length === 0 ? (
        <div className="admin-empty">No dashlets match this filter.</div>
      ) : (
        <div className="admin-table-wrap">
          <table className="admin-table">
            <thead>
              <tr>
                <th>Dashlet</th>
                <th>Section</th>
                <th>Status</th>
                <th>Group</th>
                <th>Metrics</th>
                <th>Comment</th>
                <th>Action</th>
              </tr>
            </thead>
            <tbody>
              {pagedDashlets.map((p) => (
                <tr key={p.id}>
                  <td className="admin-table-name">{p.label}</td>
                  <td className="admin-table-muted">{p.parent_key ?? '—'}</td>
                  <td>
                    <span className={`admin-badge ${p.status === 'published' ? 'admin-badge--green' : 'admin-badge--grey'}`}>
                      {p.status === 'published' ? 'Published' : 'Draft'}
                    </span>
                    {p.has_pending_draft && (
                      <span className="admin-badge admin-badge--blue" style={{ marginLeft: 6 }}>Unpublished changes</span>
                    )}
                  </td>
                  <td className="admin-table-muted">
                    {p.group_name ?? '—'}{p.chart_type ? ` (${p.chart_type})` : ''}
                  </td>
                  <td>
                    {p.source_type === 'salesforce' && (
                      <span className="admin-badge admin-badge--blue">{p.metric_config_ids.length} metric(s)</span>
                    )}
                    {p.kpi_id && (
                      <span className="admin-badge admin-badge--grey" style={{ marginLeft: p.source_type === 'salesforce' ? 6 : 0 }}>{p.kpi_id}</span>
                    )}
                  </td>
                  <td>
                    {p.comment_enabled && p.comment
                      ? <span className="admin-badge admin-badge--green">✓ {p.comment.slice(0, 40)}{p.comment.length > 40 ? '…' : ''}</span>
                      : <span className="admin-badge admin-badge--grey">—</span>
                    }
                  </td>
                  <td className="admin-table-actions">
                    <RowActionsMenu actions={[
                      { label: 'Edit', onClick: () => setFormPermission(p) },
                      ...(p.status === 'draft' || p.has_pending_draft
                        ? [{ label: 'Publish', onClick: () => { setActionError(null); setPublishTarget(p) } }]
                        : []),
                      ...(p.status === 'published'
                        ? [{ label: 'Unpublish', onClick: () => { setActionError(null); setUnpublishTarget(p) } }]
                        : []),
                      ...(p.has_pending_draft
                        ? [{ label: 'Discard draft', onClick: () => { setActionError(null); setDiscardTarget(p) } }]
                        : []),
                      { label: 'History', onClick: () => setHistoryKey(p.key) },
                      { label: 'Delete', onClick: () => { setDeleteError(null); setDeleteTarget(p) }, variant: 'danger' },
                    ]} />
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <Pagination page={page} totalPages={totalPages} total={total} pageSize={PAGE_SIZE} onPage={setPage} />

      {deleteError && <div className="admin-error" style={{ marginTop: 12 }}>{deleteError}</div>}

      {formPermission !== null && (
        <DashletForm
          permission={formPermission === 'new' ? null : formPermission}
          metrics={metrics}
          kpis={kpis}
          groups={dashletGroups}
          existingKeys={permissions.map((p) => p.key)}
          dashboardId={dashboardId}
          sourceType={dashboard.source_type}
          onClose={() => setFormPermission(null)}
        />
      )}

      {deleteTarget && (
        <DeleteConfirm
          permission={deleteTarget}
          onConfirm={() => void handleDelete(deleteTarget)}
          onCancel={() => setDeleteTarget(null)}
          loading={deletePermission.isPending}
        />
      )}

      {publishTarget && (
        <ActionConfirm
          title="Publish Dashlet"
          message={
            <>
              Publish <strong>{publishTarget.label}</strong>?{' '}
              {publishTarget.has_pending_draft
                ? `This applies your pending unpublished changes and makes them visible on the public ${dashboard.label} immediately.`
                : `This makes it visible on the public ${dashboard.label} immediately.`}
            </>
          }
          confirmLabel="Publish"
          confirmingLabel="Publishing…"
          confirmVariant="primary"
          onConfirm={() => void handlePublish(publishTarget)}
          onCancel={() => setPublishTarget(null)}
          loading={publishDashlet.isPending}
        />
      )}

      {unpublishTarget && (
        <ActionConfirm
          title="Unpublish Dashlet"
          message={
            <>
              Unpublish <strong>{unpublishTarget.label}</strong>? It will be removed from the public {dashboard.label}
              immediately. Any pending unpublished changes are kept and can still be published later.
            </>
          }
          confirmLabel="Unpublish"
          confirmingLabel="Unpublishing…"
          confirmVariant="danger"
          onConfirm={() => void handleUnpublish(unpublishTarget)}
          onCancel={() => setUnpublishTarget(null)}
          loading={unpublishDashlet.isPending}
        />
      )}

      {discardTarget && (
        <ActionConfirm
          title="Discard Draft"
          message={
            <>
              Discard the pending unpublished changes for <strong>{discardTarget.label}</strong>? The dashlet
              reverts to its currently published version. This cannot be undone.
            </>
          }
          confirmLabel="Discard draft"
          confirmingLabel="Discarding…"
          confirmVariant="danger"
          onConfirm={() => void handleDiscardDraft(discardTarget)}
          onCancel={() => setDiscardTarget(null)}
          loading={discardDraft.isPending}
        />
      )}

      {historyKey !== null && (
        <HistoryPanel
          title="Dashlet History"
          entries={historyEntries}
          loading={historyLoading}
          onRestore={(historyId) => restorePermission.mutate(historyId)}
          restoring={restorePermission.isPending}
          onClose={() => setHistoryKey(null)}
          summarize={summarizeDashletSnapshot}
        />
      )}
    </div>
  )
}

// ── Groups form panel ──────────────────────────────────────────────────────────

function GroupForm({
  group,
  dashboardId,
  onClose,
}: {
  group: DashletGroup | null
  // Fixed for the lifetime of this form — a group belongs to exactly one
  // dashboard, set at creation and never moved afterward.
  dashboardId: number
  onClose: () => void
}) {
  const createGroup = useCreateDashletGroup()
  const updateGroup = useUpdateDashletGroup()
  const { data: allCategories = [] } = useDashletCategories(dashboardId)
  const categories = useMemo(() => allCategories.filter((c) => !c.is_uncategorized), [allCategories])

  const [name, setName] = useState(group?.name ?? '')
  const [categoryId, setCategoryId] = useState<number | null>(group?.category_id ?? null)
  const [displayOrder, setDisplayOrder] = useState(group ? String(group.display_order) : '0')
  const [error, setError] = useState<string | null>(null)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    try {
      const order = Number(displayOrder) || 0
      if (group) {
        await updateGroup.mutateAsync({ id: group.id, name, categoryId, displayOrder: order })
      } else {
        await createGroup.mutateAsync({ name, dashboardId, categoryId, displayOrder: order })
      }
      onClose()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'An error occurred')
    }
  }

  const saving = createGroup.isPending || updateGroup.isPending

  return (
    <div className="roles-form-panel">
      <div className="roles-form-header">
        <h2 className="roles-form-title">{group ? 'Edit Group' : 'New Group'}</h2>
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
            placeholder="e.g. Education Reach"
          />
        </div>
        <div className="roles-form-field">
          <label className="roles-form-label">Category</label>
          <select
            className="admin-select"
            value={categoryId ?? ''}
            onChange={(e) => setCategoryId(e.target.value === '' ? null : Number(e.target.value))}
          >
            <option value="">Uncategorized</option>
            {categories.map((c) => (
              <option key={c.id} value={c.id}>{c.name}</option>
            ))}
          </select>
          <span className="admin-table-muted" style={{ fontSize: '0.75rem' }}>
            The Level this group appears under. Manage the list of categories on the Categories tab.
          </span>
        </div>
        <div className="roles-form-field">
          <label className="roles-form-label">Display order</label>
          <input
            className="admin-input"
            type="number"
            value={displayOrder}
            onChange={(e) => setDisplayOrder(e.target.value)}
            placeholder="e.g. 0"
          />
          <span className="admin-table-muted" style={{ fontSize: '0.75rem' }}>
            Sections render lowest-first on the dashboard page.
          </span>
        </div>

        {error && <div className="admin-error">{error}</div>}

        <div className="roles-form-actions">
          <button type="button" className="admin-btn admin-btn--secondary" style={{ flex: 1 }} onClick={onClose}>Cancel</button>
          <button type="submit" className="admin-btn admin-btn--primary" style={{ flex: 1 }} disabled={saving || !name.trim()}>
            {saving ? 'Saving…' : group ? 'Save Changes' : 'Create Group'}
          </button>
        </div>
      </form>
    </div>
  )
}

function DeleteGroupConfirm({ group, onConfirm, onCancel, loading }: { group: DashletGroup; onConfirm: () => void; onCancel: () => void; loading: boolean }) {
  const blocked = group.dashlet_count > 0
  return (
    <div className="admin-modal-backdrop">
      <div className="admin-modal">
        <h3 className="admin-modal-title">Delete Group</h3>
        {blocked ? (
          <p>{group.dashlet_count} dashlet(s) still use <strong>{group.name}</strong> — reassign them to another group first.</p>
        ) : (
          <p>Delete <strong>{group.name}</strong>? This cannot be undone.</p>
        )}
        <div className="admin-modal-actions">
          <button className="admin-btn admin-btn--secondary" onClick={onCancel}>Cancel</button>
          {!blocked && (
            <button className="admin-btn admin-btn--danger" onClick={onConfirm} disabled={loading}>
              {loading ? 'Deleting…' : 'Delete'}
            </button>
          )}
        </div>
      </div>
    </div>
  )
}

// ── Groups tab ───────────────────────────────────────────────────────────────

function GroupsTab({ dashboard }: { dashboard: Dashboard }) {
  const dashboardId = dashboard.id
  const { data: allGroups = [], isLoading } = useDashletGroups(dashboardId)
  const { data: allCategories = [] } = useDashletCategories(dashboardId)
  const deleteGroup = useDeleteDashletGroup()

  const [formGroup, setFormGroup] = useState<DashletGroup | 'new' | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<DashletGroup | null>(null)
  const [deleteError, setDeleteError] = useState<string | null>(null)

  const categoryNameById = useMemo(
    () => new Map(allCategories.map((c) => [c.id, c.name])),
    [allCategories],
  )

  // The system "no group chosen" row isn't a real, admin-managed group —
  // hide it here the same way it's excluded from the public dashboard.
  const groups = useMemo(() => allGroups.filter((g) => !g.is_ungrouped), [allGroups])
  const { page, setPage, pageData: pagedGroups, totalPages, total } = usePagination(groups)

  async function handleDelete(group: DashletGroup) {
    setDeleteError(null)
    try {
      await deleteGroup.mutateAsync(group.id)
      setDeleteTarget(null)
    } catch (err) {
      setDeleteError(err instanceof Error ? err.message : 'Delete failed')
    }
  }

  return (
    <div>
      <div className="admin-page-header">
        <button className="admin-btn admin-btn--primary" onClick={() => setFormGroup('new')}>
          + New Group
        </button>
      </div>

      {isLoading ? (
        <div className="admin-loading">Loading…</div>
      ) : groups.length === 0 ? (
        <div className="admin-empty">No groups on this dashboard yet. Create one to get started.</div>
      ) : (
        <div className="admin-table-wrap">
          <table className="admin-table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Category</th>
                <th>Display order</th>
                <th>Dashlets</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {pagedGroups.map((g) => (
                <tr key={g.id}>
                  <td className="admin-table-name">{g.name}</td>
                  <td className="admin-table-muted">{g.category_id !== null ? (categoryNameById.get(g.category_id) ?? '—') : 'Uncategorized'}</td>
                  <td className="admin-table-muted">{g.display_order}</td>
                  <td><span className="admin-badge admin-badge--blue">{g.dashlet_count} dashlet(s)</span></td>
                  <td className="admin-table-actions">
                    <button
                      className="admin-btn admin-btn--sm admin-btn--secondary"
                      style={{ width: '5.5rem' }}
                      onClick={() => setFormGroup(g)}
                    >
                      Edit
                    </button>
                    <button
                      className="admin-btn admin-btn--sm admin-btn--danger"
                      style={{ width: '5.5rem' }}
                      onClick={() => { setDeleteError(null); setDeleteTarget(g) }}
                    >
                      Delete
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <Pagination page={page} totalPages={totalPages} total={total} pageSize={PAGE_SIZE} onPage={setPage} />

      {deleteError && <div className="admin-error" style={{ marginTop: 12 }}>{deleteError}</div>}

      {formGroup !== null && (
        <GroupForm
          group={formGroup === 'new' ? null : formGroup}
          dashboardId={dashboardId}
          onClose={() => setFormGroup(null)}
        />
      )}

      {deleteTarget && (
        <DeleteGroupConfirm
          group={deleteTarget}
          onConfirm={() => void handleDelete(deleteTarget)}
          onCancel={() => setDeleteTarget(null)}
          loading={deleteGroup.isPending}
        />
      )}
    </div>
  )
}

// ── Categories form panel ────────────────────────────────────────────────────

function CategoryForm({
  category,
  dashboardId,
  onClose,
}: {
  category: DashletCategory | null
  dashboardId: number
  onClose: () => void
}) {
  const createCategory = useCreateDashletCategory()
  const updateCategory = useUpdateDashletCategory()

  const [name, setName] = useState(category?.name ?? '')
  const [displayOrder, setDisplayOrder] = useState(category ? String(category.display_order) : '0')
  const [displayTitle, setDisplayTitle] = useState(category?.display_title ?? '')
  const [description, setDescription] = useState(category?.description ?? '')
  const [error, setError] = useState<string | null>(null)

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    try {
      const order = Number(displayOrder) || 0
      const displayTitleValue = displayTitle.trim() || null
      const descriptionValue = description.trim() || null
      if (category) {
        await updateCategory.mutateAsync({ id: category.id, name, displayOrder: order, displayTitle: displayTitleValue, description: descriptionValue })
      } else {
        await createCategory.mutateAsync({ name, dashboardId, displayOrder: order, displayTitle: displayTitleValue, description: descriptionValue })
      }
      onClose()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'An error occurred')
    }
  }

  const saving = createCategory.isPending || updateCategory.isPending

  return (
    <div className="roles-form-panel">
      <div className="roles-form-header">
        <h2 className="roles-form-title">{category ? 'Edit Category' : 'New Category'}</h2>
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
            placeholder="e.g. LEVEL 1: SHF's Education"
          />
        </div>
        <div className="roles-form-field">
          <label className="roles-form-label">Display order</label>
          <input
            className="admin-input"
            type="number"
            value={displayOrder}
            onChange={(e) => setDisplayOrder(e.target.value)}
            placeholder="e.g. 0"
          />
          <span className="admin-table-muted" style={{ fontSize: '0.75rem' }}>
            Categories render lowest-first on the dashboard page.
          </span>
        </div>
        <div className="roles-form-field">
          <label className="roles-form-label">Display title</label>
          <input
            className="admin-input"
            value={displayTitle}
            onChange={(e) => setDisplayTitle(e.target.value)}
            placeholder="Leave blank to use the category name as the hero title"
          />
        </div>
        <div className="roles-form-field">
          <label className="roles-form-label">Description</label>
          <textarea
            className="admin-input"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Leave blank to use the default generic description"
            rows={3}
          />
        </div>

        {error && <div className="admin-error">{error}</div>}

        <div className="roles-form-actions">
          <button type="button" className="admin-btn admin-btn--secondary" style={{ flex: 1 }} onClick={onClose}>Cancel</button>
          <button type="submit" className="admin-btn admin-btn--primary" style={{ flex: 1 }} disabled={saving || !name.trim()}>
            {saving ? 'Saving…' : category ? 'Save Changes' : 'Create Category'}
          </button>
        </div>
      </form>
    </div>
  )
}

function DeleteCategoryConfirm({ category, onConfirm, onCancel, loading }: { category: DashletCategory; onConfirm: () => void; onCancel: () => void; loading: boolean }) {
  const blocked = category.group_count > 0
  return (
    <div className="admin-modal-backdrop">
      <div className="admin-modal">
        <h3 className="admin-modal-title">Delete Category</h3>
        {blocked ? (
          <p>{category.group_count} group(s) still use <strong>{category.name}</strong> — reassign them to another category first.</p>
        ) : (
          <p>Delete <strong>{category.name}</strong>? This cannot be undone.</p>
        )}
        <div className="admin-modal-actions">
          <button className="admin-btn admin-btn--secondary" onClick={onCancel}>Cancel</button>
          {!blocked && (
            <button className="admin-btn admin-btn--danger" onClick={onConfirm} disabled={loading}>
              {loading ? 'Deleting…' : 'Delete'}
            </button>
          )}
        </div>
      </div>
    </div>
  )
}

// ── Categories tab ───────────────────────────────────────────────────────────

function CategoriesTab({ dashboard }: { dashboard: Dashboard }) {
  const dashboardId = dashboard.id
  const { data: allCategories = [], isLoading } = useDashletCategories(dashboardId)
  const deleteCategory = useDeleteDashletCategory()

  const [formCategory, setFormCategory] = useState<DashletCategory | 'new' | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<DashletCategory | null>(null)
  const [deleteError, setDeleteError] = useState<string | null>(null)

  // The "Uncategorized" fallback isn't a real, admin-managed category —
  // hide it here the same way _ungrouped_* groups are hidden on the Groups tab.
  const categories = useMemo(() => allCategories.filter((c) => !c.is_uncategorized), [allCategories])
  const { page, setPage, pageData: pagedCategories, totalPages, total } = usePagination(categories)

  async function handleDelete(category: DashletCategory) {
    setDeleteError(null)
    try {
      await deleteCategory.mutateAsync(category.id)
      setDeleteTarget(null)
    } catch (err) {
      setDeleteError(err instanceof Error ? err.message : 'Delete failed')
    }
  }

  return (
    <div>
      <div className="admin-page-header">
        <button className="admin-btn admin-btn--primary" onClick={() => setFormCategory('new')}>
          + New Category
        </button>
      </div>

      {isLoading ? (
        <div className="admin-loading">Loading…</div>
      ) : categories.length === 0 ? (
        <div className="admin-empty">No categories on this dashboard yet. Create one to get started.</div>
      ) : (
        <div className="admin-table-wrap">
          <table className="admin-table">
            <thead>
              <tr>
                <th>Name</th>
                <th>Display order</th>
                <th>Groups</th>
                <th></th>
              </tr>
            </thead>
            <tbody>
              {pagedCategories.map((c) => (
                <tr key={c.id}>
                  <td className="admin-table-name">{c.name}</td>
                  <td className="admin-table-muted">{c.display_order}</td>
                  <td><span className="admin-badge admin-badge--blue">{c.group_count} group(s)</span></td>
                  <td className="admin-table-actions">
                    <button
                      className="admin-btn admin-btn--sm admin-btn--secondary"
                      style={{ width: '5.5rem' }}
                      onClick={() => setFormCategory(c)}
                    >
                      Edit
                    </button>
                    <button
                      className="admin-btn admin-btn--sm admin-btn--danger"
                      style={{ width: '5.5rem' }}
                      onClick={() => { setDeleteError(null); setDeleteTarget(c) }}
                    >
                      Delete
                    </button>
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      )}

      <Pagination page={page} totalPages={totalPages} total={total} pageSize={PAGE_SIZE} onPage={setPage} />

      {deleteError && <div className="admin-error" style={{ marginTop: 12 }}>{deleteError}</div>}

      {formCategory !== null && (
        <CategoryForm
          category={formCategory === 'new' ? null : formCategory}
          dashboardId={dashboardId}
          onClose={() => setFormCategory(null)}
        />
      )}

      {deleteTarget && (
        <DeleteCategoryConfirm
          category={deleteTarget}
          onConfirm={() => void handleDelete(deleteTarget)}
          onCancel={() => setDeleteTarget(null)}
          loading={deleteCategory.isPending}
        />
      )}
    </div>
  )
}

// ── Dashboard form panel ──────────────────────────────────────────────────────

function DashboardForm({
  dashboard,
  defaultSourceType,
  onClose,
}: {
  dashboard: Dashboard | null
  // New dashboards inherit the type of whichever dashboard was selected when
  // "Manage dashboards" was opened — a dashboard's type can't be changed
  // after creation (it decides which RPC family every dashlet under it uses).
  defaultSourceType: 'kpi' | 'salesforce'
  onClose: () => void
}) {
  const createDashboard = useCreateDashboard()
  const updateDashboard = useUpdateDashboard()

  const [key, setKey] = useState(dashboard?.key ?? '')
  const [keyManuallyEdited, setKeyManuallyEdited] = useState(!!dashboard)
  const [label, setLabel] = useState(dashboard?.label ?? '')
  const [sourceType] = useState<'kpi' | 'salesforce'>(dashboard?.source_type ?? defaultSourceType)
  const [displayOrder, setDisplayOrder] = useState(dashboard ? String(dashboard.display_order) : '0')
  const [isDefault, setIsDefault] = useState(dashboard?.is_default ?? false)
  const [error, setError] = useState<string | null>(null)

  function handleLabelChange(next: string) {
    setLabel(next)
    if (!dashboard && !keyManuallyEdited) setKey(slugify(next))
  }

  async function handleSubmit(e: React.FormEvent) {
    e.preventDefault()
    setError(null)
    try {
      const order = Number(displayOrder) || 0
      if (dashboard) {
        // Only ever sent as a promotion (false -> true) — the checkbox is
        // disabled once a dashboard is already default (see below), so
        // there's no UI path that would try to send `false` here. The
        // server rejects `isDefault: false` outright; the only supported way
        // to move the default is checking it on a different dashboard.
        const promotingToDefault = isDefault && !dashboard.is_default
        await updateDashboard.mutateAsync({
          id: dashboard.id, label, displayOrder: order,
          ...(promotingToDefault ? { isDefault: true } : {}),
        })
      } else {
        await createDashboard.mutateAsync({ key, label, sourceType, displayOrder: order })
      }
      onClose()
    } catch (err) {
      setError(err instanceof Error ? err.message : 'An error occurred')
    }
  }

  const saving = createDashboard.isPending || updateDashboard.isPending

  return (
    <div className="roles-form-panel">
      <div className="roles-form-header">
        <h2 className="roles-form-title">{dashboard ? 'Edit Dashboard' : `New ${defaultSourceType === 'kpi' ? 'KPI' : 'Salesforce'} Dashboard`}</h2>
        <button type="button" className="roles-form-close" onClick={onClose}>✕</button>
      </div>

      <form onSubmit={(e) => void handleSubmit(e)} className="roles-form-body">
        <div className="roles-form-field">
          <label className="roles-form-label">Label <span style={{ color: 'var(--red)' }}>*</span></label>
          <input
            className="admin-input"
            value={label}
            onChange={(e) => handleLabelChange(e.target.value)}
            required
            placeholder="e.g. Regional Overview"
          />
        </div>
        <div className="roles-form-field">
          <label className="roles-form-label">Key <span style={{ color: 'var(--red)' }}>*</span></label>
          <input
            className="admin-input"
            value={key}
            onChange={(e) => { setKey(e.target.value); setKeyManuallyEdited(true) }}
            required
            disabled={!!dashboard}
            placeholder="e.g. regional-overview"
          />
          <span className="admin-table-muted" style={{ fontSize: '0.75rem' }}>
            {dashboard
              ? 'Fixed after creation — this is the ?dashboard= value in the page URL.'
              : 'Used in the page URL as ?dashboard=<key>. Auto-filled from Label — edit to override.'}
          </span>
        </div>
        <div className="roles-form-field">
          <label className="roles-form-label">Display order</label>
          <input
            className="admin-input"
            type="number"
            value={displayOrder}
            onChange={(e) => setDisplayOrder(e.target.value)}
            placeholder="e.g. 0"
          />
        </div>
        <div className="roles-form-field">
          <label style={{ display: 'inline-flex', alignItems: 'center', gap: 6, cursor: dashboard && !dashboard.is_default ? 'pointer' : 'default', fontSize: '0.86rem' }}>
            <input
              type="checkbox"
              checked={isDefault}
              onChange={(e) => setIsDefault(e.target.checked)}
              // Can only be promoted here, never unset — a dashboard stops
              // being default only by another one becoming default instead,
              // so once this one already is, the box is locked checked.
              // New dashboards likewise can't set this at creation.
              disabled={!dashboard || dashboard.is_default}
            />
            Default {sourceType === 'kpi' ? 'KPI' : 'Salesforce'} dashboard
          </label>
          <span className="admin-table-muted" style={{ fontSize: '0.75rem' }}>
            {dashboard?.is_default
              ? 'This is the current default — make another dashboard default to change it.'
              : 'Shown when the page is opened with no ?dashboard= key — only one dashboard per type can hold this.'}
          </span>
        </div>

        {error && <div className="admin-error">{error}</div>}

        <div className="roles-form-actions">
          <button type="button" className="admin-btn admin-btn--secondary" style={{ flex: 1 }} onClick={onClose}>Cancel</button>
          <button type="submit" className="admin-btn admin-btn--primary" style={{ flex: 1 }} disabled={saving || !label.trim() || !key.trim()}>
            {saving ? 'Saving…' : dashboard ? 'Save Changes' : 'Create Dashboard'}
          </button>
        </div>
      </form>
    </div>
  )
}

function DeleteDashboardConfirm({ dashboard, dashletCount, onConfirm, onCancel, loading }: {
  dashboard: Dashboard; dashletCount: number; onConfirm: () => void; onCancel: () => void; loading: boolean
}) {
  const blocked = dashletCount > 0 || dashboard.is_default
  return (
    <div className="admin-modal-backdrop">
      <div className="admin-modal">
        <h3 className="admin-modal-title">Delete Dashboard</h3>
        {dashboard.is_default ? (
          <p>Cannot delete <strong>{dashboard.label}</strong> — it's the default {dashboard.source_type} dashboard. Make another dashboard the default first.</p>
        ) : dashletCount > 0 ? (
          <p>{dashletCount} dashlet(s) still live on <strong>{dashboard.label}</strong> — move or delete them first.</p>
        ) : (
          <p>Delete <strong>{dashboard.label}</strong>? This cannot be undone.</p>
        )}
        <div className="admin-modal-actions">
          <button className="admin-btn admin-btn--secondary" onClick={onCancel}>Cancel</button>
          {!blocked && (
            <button className="admin-btn admin-btn--danger" onClick={onConfirm} disabled={loading}>
              {loading ? 'Deleting…' : 'Delete'}
            </button>
          )}
        </div>
      </div>
    </div>
  )
}

// ── Manage dashboards panel ───────────────────────────────────────────────────
// Opened from the dashboard selector on the Dashboards tab — CRUD for the
// dashboards list itself, kept one click away from the selector rather than
// as a separate top-level tab disconnected from the Dashlets/Groups it scopes.

function ManageDashboardsPanel({
  dashboards,
  onClose,
}: {
  dashboards: Dashboard[]
  onClose: () => void
}) {
  const deleteDashboard = useDeleteDashboard()
  // 'new' creation always carries its own explicit type — a single "+ New
  // Dashboard" button that silently created whatever type happened to be
  // selected elsewhere on the page was the reported source of confusion, so
  // the two "+ New … Dashboard" buttons below each set their own type here.
  const [formDashboard, setFormDashboard] = useState<Dashboard | { newType: 'kpi' | 'salesforce' } | null>(null)
  const [deleteTarget, setDeleteTarget] = useState<Dashboard | null>(null)
  const [deleteError, setDeleteError] = useState<string | null>(null)
  // Groups tab count needs each dashboard's own dashlet count — reuse the
  // same list-by-dashboard hook the delete guard on the server also checks.
  const permissionsQuery = usePermissions()
  const dashletCountFor = (id: number) => (permissionsQuery.data ?? []).filter((p) => p.category === 'dashlet' && p.dashboard_id === id).length

  async function handleDelete(dashboard: Dashboard) {
    setDeleteError(null)
    try {
      await deleteDashboard.mutateAsync(dashboard.id)
      setDeleteTarget(null)
    } catch (err) {
      setDeleteError(err instanceof Error ? err.message : 'Delete failed')
    }
  }

  const kpiDashboards = dashboards.filter((d) => d.source_type === 'kpi')
  const sfDashboards = dashboards.filter((d) => d.source_type === 'salesforce')

  function renderGroup(label: string, list: Dashboard[], newType: 'kpi' | 'salesforce') {
    return (
      <div key={label} style={{ marginBottom: 20 }}>
        <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'space-between', marginBottom: 8 }}>
          <h3 style={{ fontSize: '0.8rem', fontWeight: 700, textTransform: 'uppercase', letterSpacing: '0.04em', color: 'var(--text-mid)', margin: 0 }}>
            {label}
          </h3>
          <button className="admin-btn admin-btn--sm admin-btn--primary" onClick={() => setFormDashboard({ newType })}>
            + New {newType === 'kpi' ? 'KPI' : 'Salesforce'} Dashboard
          </button>
        </div>
        <div style={{ display: 'flex', flexDirection: 'column', gap: 6 }}>
          {list.length === 0 ? (
            <div className="admin-table-muted" style={{ fontSize: '0.8rem' }}>None yet.</div>
          ) : list.map((d) => (
            <div key={d.id} style={{ display: 'flex', alignItems: 'center', gap: 8, border: '1px solid var(--border)', borderRadius: 8, padding: '8px 10px' }}>
              <div style={{ flex: 1, minWidth: 0 }}>
                <div style={{ fontWeight: 600, fontSize: '0.86rem' }}>
                  {d.label} {d.is_default && <span className="admin-badge admin-badge--green" style={{ marginLeft: 6 }}>Default</span>}
                </div>
                <div className="admin-table-muted" style={{ fontSize: '0.75rem' }}>?dashboard={d.key} · order {d.display_order}</div>
              </div>
              <button className="admin-btn admin-btn--sm admin-btn--secondary" onClick={() => setFormDashboard(d)}>Edit</button>
              <button className="admin-btn admin-btn--sm admin-btn--danger" onClick={() => { setDeleteError(null); setDeleteTarget(d) }}>Delete</button>
            </div>
          ))}
        </div>
      </div>
    )
  }

  return (
    <div className="roles-form-panel">
      <div className="roles-form-header">
        <h2 className="roles-form-title">Manage Dashboards</h2>
        <button type="button" className="roles-form-close" onClick={onClose}>✕</button>
      </div>

      <div className="roles-form-body">
        {deleteError && <div className="admin-error" style={{ marginBottom: 12 }}>{deleteError}</div>}

        {renderGroup('KPI dashboards', kpiDashboards, 'kpi')}
        {renderGroup('Salesforce dashboards', sfDashboards, 'salesforce')}
      </div>

      {formDashboard !== null && (
        <DashboardForm
          dashboard={'newType' in formDashboard ? null : formDashboard}
          defaultSourceType={'newType' in formDashboard ? formDashboard.newType : formDashboard.source_type}
          onClose={() => setFormDashboard(null)}
        />
      )}

      {deleteTarget && (
        <DeleteDashboardConfirm
          dashboard={deleteTarget}
          dashletCount={dashletCountFor(deleteTarget.id)}
          onConfirm={() => void handleDelete(deleteTarget)}
          onCancel={() => setDeleteTarget(null)}
          loading={deleteDashboard.isPending}
        />
      )}
    </div>
  )
}

// ── Dashboards tab ─────────────────────────────────────────────────────────────
// The dashboard selector is the page's primary scoping control, taking over
// the role source_type played before dashboards existed — Dashlets and
// Groups stay visibly nested under whichever dashboard is selected here,
// rather than living in their own flat tabs beside Metric Config.

function DashboardsTab() {
  const { data: dashboards = [], isLoading } = useDashboardsAdmin()
  const [selectedId, setSelectedId] = useState<number | null>(null)
  const [subTab, setSubTab] = useState<'dashlets' | 'groups' | 'categories'>('dashlets')
  const [managingDashboards, setManagingDashboards] = useState(false)

  const selected = dashboards.find((d) => d.id === selectedId)
    ?? dashboards.find((d) => d.is_default)
    ?? dashboards[0]

  if (isLoading) {
    return <div className="admin-loading">Loading…</div>
  }

  if (!selected) {
    return (
      <div>
        <div className="admin-empty">No dashboards yet.</div>
        <button className="admin-btn admin-btn--primary" style={{ marginTop: 12 }} onClick={() => setManagingDashboards(true)}>
          + New Dashboard
        </button>
        {managingDashboards && (
          <ManageDashboardsPanel dashboards={dashboards} onClose={() => setManagingDashboards(false)} />
        )}
      </div>
    )
  }

  return (
    <div>
      <div className="admin-page-header">
        <div className="admin-header-group">
          <select
            className="admin-select"
            value={selected.id}
            onChange={(e) => setSelectedId(Number(e.target.value))}
          >
            <optgroup label="KPI Dashboards">
              {dashboards.filter((d) => d.source_type === 'kpi').map((d) => (
                <option key={d.id} value={d.id}>{d.label}{d.is_default ? ' (default)' : ''}</option>
              ))}
            </optgroup>
            <optgroup label="Salesforce Dashboards">
              {dashboards.filter((d) => d.source_type === 'salesforce').map((d) => (
                <option key={d.id} value={d.id}>{d.label}{d.is_default ? ' (default)' : ''}</option>
              ))}
            </optgroup>
          </select>
          <button className="admin-btn admin-btn--secondary" onClick={() => setManagingDashboards(true)}>
            Manage dashboards
          </button>
        </div>
      </div>

      <div className="admin-tabs" style={{ marginTop: 16 }}>
        <button
          className={`admin-tab${subTab === 'dashlets' ? ' admin-tab--active' : ''}`}
          onClick={() => setSubTab('dashlets')}
        >
          Dashlets
        </button>
        <button
          className={`admin-tab${subTab === 'groups' ? ' admin-tab--active' : ''}`}
          onClick={() => setSubTab('groups')}
        >
          Groups
        </button>
        <button
          className={`admin-tab${subTab === 'categories' ? ' admin-tab--active' : ''}`}
          onClick={() => setSubTab('categories')}
        >
          Categories
        </button>
      </div>

      {subTab === 'dashlets' ? <DashletsListTab dashboard={selected} /> : subTab === 'groups' ? <GroupsTab dashboard={selected} /> : <CategoriesTab dashboard={selected} />}

      {managingDashboards && (
        <ManageDashboardsPanel dashboards={dashboards} onClose={() => setManagingDashboards(false)} />
      )}
    </div>
  )
}

// ── Main page ─────────────────────────────────────────────────────────────────

export function AdminDashletsPage() {
  const [tab, setTab] = useState<'dashboards' | 'metrics'>('dashboards')

  return (
    <div className="admin-page">
      <h1 className="admin-page-title">Dashlets</h1>

      <div className="admin-tabs">
        <button
          className={`admin-tab${tab === 'dashboards' ? ' admin-tab--active' : ''}`}
          onClick={() => setTab('dashboards')}
        >
          Dashboards
        </button>
        <button
          className={`admin-tab${tab === 'metrics' ? ' admin-tab--active' : ''}`}
          onClick={() => setTab('metrics')}
        >
          Metric Config
        </button>
      </div>

      {tab === 'dashboards' ? <DashboardsTab /> : <MetricConfigTab />}
    </div>
  )
}
