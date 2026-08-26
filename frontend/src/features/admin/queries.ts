import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { supabase } from '@/lib/supabase'
import { kpiTrendChartKey, kpiMilestoneChartKey } from '@/features/kpi-report/trend-utils'

async function callAdminFn(fnName: string, body: unknown) {
  const { data, error } = await supabase.functions.invoke(fnName, { body: body as Record<string, unknown> })
  if (error) {
    const context = (error as { context?: Response }).context
    if (context && typeof context.json === 'function') {
      const payload = await context.clone().json().catch(() => null)
      if (typeof payload?.error === 'string') throw new Error(payload.error)
    }
    throw error
  }
  return data
}

const portal = () => supabase.schema('rep_portal')

// ── Ingest ────────────────────────────────────────────────────────────────────

export interface IngestRun {
  run_id: string
  status: string
  since: string | null
  started_by: string
  current_wave: number | null
  attempt_count: number
  lease_expires_at: string | null
  started_at: string
  finished_at: string | null
  error: string | null
}

interface IngestFnState {
  fn_name: string
  status: string
  rows_fetched: number
  attempt_count: number
  cursor: string | null
}

export const INGEST_RUNS_PAGE_SIZE = 10

export function useIngestRuns(page: number) {
  return useQuery({
    queryKey: ['admin', 'ingest-runs', page],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_ingest_runs', {
        p_limit: INGEST_RUNS_PAGE_SIZE,
        p_offset: (page - 1) * INGEST_RUNS_PAGE_SIZE,
      })
      if (error) throw error
      return data as IngestRun[]
    },
  })
}

export function useIngestRunCount() {
  return useQuery({
    queryKey: ['admin', 'ingest-run-count'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('count_ingest_runs')
      if (error) throw error
      return data as number
    },
  })
}

export function useIngestFnState(runId: string | null) {
  return useQuery({
    queryKey: ['admin', 'ingest-fn-state', runId],
    enabled: !!runId,
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_ingest_fn_state', { p_run_id: runId! })
      if (error) throw error
      return data as IngestFnState[]
    },
  })
}

export function useTriggerIngest() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: () => callAdminFn('admin-trigger', {}),
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['admin', 'ingest-runs'] })
      void qc.invalidateQueries({ queryKey: ['admin', 'ingest-run-count'] })
    },
  })
}

// ── ETL batch log ─────────────────────────────────────────────────────────────

interface EtlBatchLog {
  batch_id: string
  status: string
  source_system: string | null
  started_at: string
  finished_at: string | null
  error_message: string | null
}

export function useEtlBatchLog() {
  return useQuery({
    queryKey: ['admin', 'etl-batch-log'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_etl_batch_log')
      if (error) throw error
      return data as EtlBatchLog[]
    },
  })
}

export function useEtlBatchLogEntry(batchId: string | null) {
  return useQuery({
    queryKey: ['admin', 'etl-batch-log', batchId],
    enabled: !!batchId,
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_etl_batch_log_entry', { p_batch_id: batchId! })
      if (error) throw error
      return ((data as EtlBatchLog[] | null)?.[0] ?? null) as EtlBatchLog | null
    },
  })
}

// ── Deletion detection log ───────────────────────────────────────────────────
// Keyed by the same run_id as the triggering ingest run (ingest-deletions
// reuses ingest_run.run_id as deletion_run_log.run_id — see CLAUDE.md →
// Deletion tracking) — no match means detection hasn't fired for that run yet.

export interface DeletionRunLogEntry {
  run_id: string
  status: string
  objects_queried: number | null
  deletions_found: number | null
  deletions_applied: number | null
  started_at: string
  finished_at: string | null
  error: string | null
}

export function useDeletionRunLogEntry(runId: string | null) {
  return useQuery({
    queryKey: ['admin', 'deletion-run-log', runId],
    enabled: !!runId,
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_deletion_run_log_entry', { p_run_id: runId! })
      if (error) throw error
      return ((data as DeletionRunLogEntry[] | null)?.[0] ?? null) as DeletionRunLogEntry | null
    },
  })
}

// ── KPI upload history ────────────────────────────────────────────────────────

export interface UploadLog {
  batch_id: string
  year: number
  row_count: number
  rows_loaded: number
  rows_unmatched: number
  rows_duplicate: number
  status: string
  uploaded_by: string
  source_file: string
  inserted_at: string
  error_msg: string | null
}

export const UPLOAD_LOG_PAGE_SIZE = 10

export function useUploadLog(page: number) {
  return useQuery({
    queryKey: ['admin', 'upload-log', page],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_upload_log', {
        p_limit: UPLOAD_LOG_PAGE_SIZE,
        p_offset: (page - 1) * UPLOAD_LOG_PAGE_SIZE,
      })
      if (error) throw error
      return data as UploadLog[]
    },
  })
}

export function useUploadLogCount() {
  return useQuery({
    queryKey: ['admin', 'upload-log-count'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('count_upload_log')
      if (error) throw error
      return data as number
    },
  })
}

export interface LevelOneUploadLog {
  batch_id: string
  rows_added: number
  rows_updated: number
  total_rows: number
  status: string
  uploaded_by: string
  source_file: string
  inserted_at: string
  error_msg: string | null
}

export const LEVEL_ONE_UPLOAD_LOG_PAGE_SIZE = 10

export function useLevelOneUploadLog(page: number) {
  return useQuery({
    queryKey: ['admin', 'level-one-upload-log', page],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_level_one_upload_log', {
        p_limit: LEVEL_ONE_UPLOAD_LOG_PAGE_SIZE,
        p_offset: (page - 1) * LEVEL_ONE_UPLOAD_LOG_PAGE_SIZE,
      })
      if (error) throw error
      return data as LevelOneUploadLog[]
    },
  })
}

export function useLevelOneUploadLogCount() {
  return useQuery({
    queryKey: ['admin', 'level-one-upload-log-count'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('count_level_one_upload_log')
      if (error) throw error
      return data as number
    },
  })
}

export interface MilestoneUploadLog {
  batch_id: string
  source_file: string | null
  uploaded_by: string | null
  rows_loaded: number | null
  status: string
  error_msg: string | null
  inserted_at: string
}

export const MILESTONE_UPLOAD_LOG_PAGE_SIZE = 10

export function useMilestoneUploadLog(page: number) {
  return useQuery({
    queryKey: ['admin', 'milestone-upload-log', page],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_milestone_upload_log', {
        p_limit: MILESTONE_UPLOAD_LOG_PAGE_SIZE,
        p_offset: (page - 1) * MILESTONE_UPLOAD_LOG_PAGE_SIZE,
      })
      if (error) throw error
      return data as MilestoneUploadLog[]
    },
  })
}

export function useMilestoneUploadLogCount() {
  return useQuery({
    queryKey: ['admin', 'milestone-upload-log-count'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('count_milestone_upload_log')
      if (error) throw error
      return data as number
    },
  })
}


interface DuplicateRow {
  kpi_id: string
  kpi_group: string | null
  year: number | null
  disaggregation_level_one: string | null
  disaggregation_level_two: string | null
  row_scope: string | null
  occurrences: number
  row_ids: string[] | null
}

interface KpiDefinitionsSummary {
  total: number
  last_loaded_at: string | null
  last_source_file: string | null
}

export function useKpiDefinitionsSummary() {
  return useQuery({
    queryKey: ['admin', 'kpi-definitions-summary'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_kpi_definitions_summary')
      if (error) throw error
      return data as KpiDefinitionsSummary
    },
  })
}

export interface KpiDefinition {
  source_kpi_id:       string
  kpi_group:           string | null
  indicator:           string | null
  short_label:         string | null
  indicator_frequency: string | null
  indicator_start:     string | null
  definition:          string | null
}

export function useKpiDefinitions() {
  return useQuery({
    queryKey: ['admin', 'kpi-definitions'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_kpi_definitions')
      if (error) throw error
      return data as KpiDefinition[]
    },
  })
}

export function useDuplicateRows(batchId: string | null) {
  return useQuery({
    queryKey: ['admin', 'duplicate-rows', batchId],
    enabled: !!batchId,
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_duplicate_rows', { p_batch_id: batchId! })
      if (error) throw error
      return data as DuplicateRow[]
    },
  })
}

interface LoadedYear {
  year: number
  rows_loaded: number
  rows_duplicate: number
  uploaded_by: string
  source_file: string
  inserted_at: string
  update_quarter: string | null
}

export function useLoadedYears() {
  return useQuery({
    queryKey: ['admin', 'loaded-years'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_loaded_years')
      if (error) throw error
      return data as LoadedYear[]
    },
  })
}

// ── Users ─────────────────────────────────────────────────────────────────────

export interface AdminUser {
  id: string
  email: string
  role: string
  created_at: string
  last_sign_in_at: string | null
  confirmed_at: string | null
  invited_at: string | null
  banned_until: string | null
  roles: { id: number; name: string }[]
  countries: string[]
}

export interface UserListFilters {
  search: string
  adminRole: string
  roleId: number | null
  country: string
  status: string
  sortKey?: string
  sortDir?: 'asc' | 'desc'
}

interface UserListResponse {
  users: AdminUser[]
  total: number
  page: number
  pageSize: number
}

export function useAdminUsers(page: number, pageSize: number, filters: UserListFilters) {
  return useQuery({
    queryKey: ['admin', 'users', page, pageSize, filters],
    queryFn: () => callAdminFn('admin-users', {
      action: 'list',
      page,
      pageSize,
      ...filters,
    }) as Promise<UserListResponse>,
  })
}

// ── Roles & Permissions ───────────────────────────────────────────────────────

export interface Permission {
  id: number
  key: string
  label: string
  description: string | null
  category: 'dashlet' | 'wa_report' | 'page'
  parent_key: string | null
  source_type: 'kpi' | 'salesforce'
  dashboard_id: number | null
  group_id: number | null
  group_name: string | null
  chart_type: 'number' | 'bar' | 'horizontal_bar' | 'pie' | 'table' | 'line' | null
  display_mode: 'aggregate' | 'timeline' | null
  metric_ids: string[]
  metric_config_ids: number[]
  kpi_id: string | null
  kpi_disagg1_filters: string[]
  kpi_disagg2_filters: string[]
  kpi_split_mode: 'combine' | 'split'
  show_milestone: boolean
  comment: string | null
  comment_enabled: boolean
  comment_updated_at: string | null
  status: 'draft' | 'published'
  has_pending_draft: boolean
}

export interface DashletGroup {
  id: number
  name: string
  dashboard_id: number
  category_id: number | null
  source_type: 'kpi' | 'salesforce'
  display_order: number
  is_ungrouped: boolean
  dashlet_count: number
}

export interface DashletCategory {
  id: number
  name: string
  dashboard_id: number
  display_order: number
  is_uncategorized: boolean
  display_title: string | null
  description: string | null
  group_count: number
}

export interface Dashboard {
  id: number
  key: string
  label: string
  source_type: 'kpi' | 'salesforce'
  display_order: number
  is_default: boolean
}

export interface MetricConfig {
  id: number
  metric_name: string
  sort_order: number
  enabled: boolean
}

export interface MetricConfigFull {
  id: number
  metric_name: string
  source_view: string
  year_field: string
  value_agg: 'count' | 'sum'
  value_field: string | null
  geography_level: 'school' | 'district'
  filters: unknown
  enabled: boolean
  sort_order: number | null
  groups: { id: number; name: string }[]
}

export interface Role {
  id: number
  name: string
  description: string | null
  whatsapp_available: boolean
  permissions: Permission[]
  user_count: number
  created_at: string
  updated_at: string
}

export function usePermissions() {
  return useQuery({
    queryKey: ['admin', 'permissions'],
    queryFn: () => callAdminFn('admin-users', { action: 'permission-list' }) as Promise<Permission[]>,
    staleTime: 60 * 60 * 1000,
  })
}

export function useRoles() {
  return useQuery({
    queryKey: ['admin', 'roles'],
    queryFn: () => callAdminFn('admin-users', { action: 'role-list' }) as Promise<Role[]>,
  })
}

export function useCreateRole() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ roleName, roleDescription, whatsappAvailable, permissionIds }: { roleName: string; roleDescription?: string; whatsappAvailable?: boolean; permissionIds: number[] }) =>
      callAdminFn('admin-users', { action: 'role-create', roleName, roleDescription, whatsappAvailable, permissionIds }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin', 'roles'] }),
  })
}

export function useUpdateRole() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ roleId, roleName, roleDescription, whatsappAvailable, permissionIds }: { roleId: number; roleName?: string; roleDescription?: string; whatsappAvailable?: boolean; permissionIds?: number[] }) =>
      callAdminFn('admin-users', { action: 'role-update', roleId, roleName, roleDescription, whatsappAvailable, permissionIds }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin', 'roles'] }),
  })
}

export function useDeleteRole() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (roleId: number) => callAdminFn('admin-users', { action: 'role-delete', roleId }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin', 'roles'] }),
  })
}

// ── Dashlet comments — quick edit (direct publish, no draft/staging) ─────────
// Deliberately separate from the dashlet editor hooks below: this bypasses
// dashlet_drafts on purpose via set_dashlet_comment_direct(), an interim tool
// until the full editor's staging flow is trusted for comment-only edits.

export interface DashletCommentEditRow {
  permission_key: string
  label: string
  group_id: number | null
  group_name: string | null
  group_display_order: number | null
  comment: string | null
  comment_enabled: boolean
}

export function useDashletCommentsAdmin() {
  return useQuery({
    queryKey: ['dashlet-comments-admin'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_dashlets_for_comment_edit')
      if (error) throw error
      return data as DashletCommentEditRow[]
    },
  })
}

export function useSetDashletCommentDirect() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (args: { permissionKey: string; comment: string | null; isEnabled: boolean }) => {
      const { error } = await portal().rpc('set_dashlet_comment_direct', {
        p_permission_key: args.permissionKey,
        p_comment: args.comment,
        p_is_enabled: args.isEnabled,
      })
      if (error) throw error
    },
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['dashlet-comments-admin'] })
      qc.invalidateQueries({ queryKey: ['dashlet-comments'] })
    },
  })
}

// ── Dashlets (permissions, metric mapping, comments) ──────────────────────────

function invalidateDashlets(qc: ReturnType<typeof useQueryClient>) {
  qc.invalidateQueries({ queryKey: ['admin', 'permissions'] })
  qc.invalidateQueries({ queryKey: ['admin', 'dashlet-history'] })
}

export function useSaveDashlet() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (dashlet: {
      permissionId?: number | null; key: string; label: string; description?: string; parentKey?: string
      // Required when creating (no permissionId) — a dashlet's dashboard is
      // fixed at creation and never sent on edit; the server reads the
      // existing row's dashboard_id/source_type instead.
      dashboardId?: number; groupId: number | null; chartType: 'number' | 'bar' | 'horizontal_bar' | 'pie' | 'table' | 'line' | null; displayMode: 'aggregate' | 'timeline' | null
      metricConfigIds: number[]; kpiId: string | null; kpiDisagg1Filters: string[]; kpiDisagg2Filters: string[]; kpiSplitMode: 'combine' | 'split'
      showMilestone: boolean
      comment: string | null; isEnabled: boolean
    }) => callAdminFn('admin-users', { action: 'dashlet-save', ...dashlet }) as Promise<{ ok: true; key: string; staged?: boolean }>,
    onSuccess: () => {
      invalidateDashlets(qc)
      qc.invalidateQueries({ queryKey: ['dashlet-comments'] })
    },
  })
}

// Applies a pending draft (if any) onto the live row and marks the dashlet
// published — first-time publish of a never-staged dashlet just flips status.
export function usePublishDashlet() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (permissionId: number) =>
      callAdminFn('admin-users', { action: 'dashlet-publish', permissionId }) as Promise<{ ok: true }>,
    onSuccess: () => {
      invalidateDashlets(qc)
      qc.invalidateQueries({ queryKey: ['dashlet-comments'] })
      qc.invalidateQueries({ queryKey: ['kpi-dashboard'] })
    },
  })
}

// Takes a published dashlet off the public dashboard immediately. Any
// pending draft is left untouched.
export function useUnpublishDashlet() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (permissionId: number) =>
      callAdminFn('admin-users', { action: 'dashlet-unpublish', permissionId }) as Promise<{ ok: true }>,
    onSuccess: () => {
      invalidateDashlets(qc)
      qc.invalidateQueries({ queryKey: ['dashlet-comments'] })
      qc.invalidateQueries({ queryKey: ['kpi-dashboard'] })
    },
  })
}

// Abandons in-progress edits to a published dashlet without publishing them —
// the edit form reverts back to the live version.
export function useDiscardDashletDraft() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (permissionId: number) =>
      callAdminFn('admin-users', { action: 'dashlet-discard-draft', permissionId }) as Promise<{ ok: true }>,
    onSuccess: () => invalidateDashlets(qc),
  })
}

// ── Dashboards (KPI Dashboard / Salesforce Dashboard, and any others an
// admin creates) ────────────────────────────────────────────────────────────

export function useDashboardsAdmin() {
  return useQuery({
    queryKey: ['admin', 'dashboards'],
    queryFn: () => callAdminFn('admin-users', { action: 'dashboard-list' }) as Promise<Dashboard[]>,
    staleTime: 60 * 1000,
  })
}

function invalidateDashboards(qc: ReturnType<typeof useQueryClient>) {
  qc.invalidateQueries({ queryKey: ['admin', 'dashboards'] })
  qc.invalidateQueries({ queryKey: ['dashboards'] })
}

export function useCreateDashboard() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ key, label, sourceType, displayOrder }: { key: string; label: string; sourceType: 'kpi' | 'salesforce'; displayOrder: number }) =>
      callAdminFn('admin-users', { action: 'dashboard-create', key, label, sourceType, displayOrder }) as Promise<{ ok: true; id: number }>,
    onSuccess: () => invalidateDashboards(qc),
  })
}

export function useUpdateDashboard() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, label, displayOrder, isDefault }: { id: number; label?: string; displayOrder?: number; isDefault?: boolean }) =>
      callAdminFn('admin-users', { action: 'dashboard-update', id, label, displayOrder, isDefault }),
    onSuccess: () => invalidateDashboards(qc),
  })
}

export function useDeleteDashboard() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: number) => callAdminFn('admin-users', { action: 'dashboard-delete', id }),
    onSuccess: () => invalidateDashboards(qc),
  })
}

// ── Dashlet groups (curated grouping/ordering within a dashboard) ────────────

export function useDashletGroups(dashboardId: number | undefined) {
  return useQuery({
    queryKey: ['admin', 'dashlet-groups', dashboardId],
    enabled: dashboardId !== undefined,
    queryFn: () => callAdminFn('admin-users', { action: 'dashlet-group-list', dashboardId }) as Promise<DashletGroup[]>,
    staleTime: 60 * 1000,
  })
}

// Every group across every dashboard — metric_config is a shared catalog,
// not scoped to one dashboard, so its group filter (Metric Config tab) needs
// the full list rather than one dashboard's slice.
export function useAllDashletGroups() {
  return useQuery({
    queryKey: ['admin', 'dashlet-groups', 'all'],
    queryFn: () => callAdminFn('admin-users', { action: 'dashlet-group-list' }) as Promise<DashletGroup[]>,
    staleTime: 60 * 1000,
  })
}

function invalidateDashletGroups(qc: ReturnType<typeof useQueryClient>) {
  qc.invalidateQueries({ queryKey: ['admin', 'dashlet-groups'] })
  qc.invalidateQueries({ queryKey: ['admin', 'permissions'] })
}

export function useCreateDashletGroup() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ name, dashboardId, categoryId, displayOrder }: { name: string; dashboardId: number; categoryId?: number | null; displayOrder: number }) =>
      callAdminFn('admin-users', { action: 'dashlet-group-create', name, dashboardId, categoryId, displayOrder }) as Promise<{ ok: true; id: number }>,
    onSuccess: () => invalidateDashletGroups(qc),
  })
}

export function useUpdateDashletGroup() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, name, categoryId, displayOrder }: { id: number; name?: string; categoryId?: number | null; displayOrder?: number }) =>
      callAdminFn('admin-users', { action: 'dashlet-group-update', id, name, categoryId, displayOrder }),
    onSuccess: () => invalidateDashletGroups(qc),
  })
}

export function useDeleteDashletGroup() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: number) => callAdminFn('admin-users', { action: 'dashlet-group-delete', id }),
    onSuccess: () => invalidateDashletGroups(qc),
  })
}

// ── Dashlet categories (Level tier above groups, dashboard-scoped) ──────────

export function useDashletCategories(dashboardId: number | undefined) {
  return useQuery({
    queryKey: ['admin', 'dashlet-categories', dashboardId],
    enabled: dashboardId !== undefined,
    queryFn: () => callAdminFn('admin-users', { action: 'dashlet-category-list', dashboardId }) as Promise<DashletCategory[]>,
    staleTime: 60 * 1000,
  })
}

function invalidateDashletCategories(qc: ReturnType<typeof useQueryClient>) {
  qc.invalidateQueries({ queryKey: ['admin', 'dashlet-categories'] })
  qc.invalidateQueries({ queryKey: ['admin', 'dashlet-groups'] })
}

export function useCreateDashletCategory() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ name, dashboardId, displayOrder, displayTitle, description }: { name: string; dashboardId: number; displayOrder: number; displayTitle?: string | null; description?: string | null }) =>
      callAdminFn('admin-users', { action: 'dashlet-category-create', name, dashboardId, displayOrder, displayTitle, description }) as Promise<{ ok: true; id: number }>,
    onSuccess: () => invalidateDashletCategories(qc),
  })
}

export function useUpdateDashletCategory() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ id, name, displayOrder, displayTitle, description }: { id: number; name?: string; displayOrder?: number; displayTitle?: string | null; description?: string | null }) =>
      callAdminFn('admin-users', { action: 'dashlet-category-update', id, name, displayOrder, displayTitle, description }),
    onSuccess: () => invalidateDashletCategories(qc),
  })
}

export function useDeleteDashletCategory() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (id: number) => callAdminFn('admin-users', { action: 'dashlet-category-delete', id }),
    onSuccess: () => invalidateDashletCategories(qc),
  })
}

// ── KPI Trends chart visibility (per-disaggregation-chart curation on /kpi-trends only) ──

interface KpiTrendVisibilityRow {
  disaggregation_level_one: string | null
  disaggregation_level_two: string | null
  is_visible: boolean
}

export function useSetKpiTrendChartVisibility() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (v: { chartKey: string; isVisible: boolean; kpiGroup: string; indicator: string }) =>
      callAdminFn('admin-users', { action: 'kpi-trend-chart-visibility-set', chartKey: v.chartKey, isVisible: v.isVisible }),
    onMutate: async (v) => {
      await qc.cancelQueries({ queryKey: ['kpi-report'] })
      const previous = qc.getQueriesData<KpiTrendVisibilityRow[]>({ queryKey: ['kpi-report'] })
      qc.setQueriesData<KpiTrendVisibilityRow[]>({ queryKey: ['kpi-report'] }, (old) =>
        Array.isArray(old)
          ? old.map((row) =>
              kpiTrendChartKey(v.kpiGroup, v.indicator, row.disaggregation_level_one, row.disaggregation_level_two) === v.chartKey
                ? { ...row, is_visible: v.isVisible }
                : row,
            )
          : old,
      )
      return { previous }
    },
    onError: (_err, _v, ctx) => {
      ctx?.previous.forEach(([key, data]) => qc.setQueryData(key, data))
    },
    onSettled: () => qc.invalidateQueries({ queryKey: ['kpi-report'] }),
  })
}

// ── KPI Milestones chart visibility (per-disaggregation-chart curation on /kpi-milestones only) ──

interface KpiMilestoneVisibilityRow {
  disaggregation_level_one: string | null
  disaggregation_level_two: string | null
  is_visible: boolean
}

export function useSetKpiMilestoneChartVisibility() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (v: { chartKey: string; isVisible: boolean; kpiGroup: string; indicator: string }) =>
      callAdminFn('admin-users', { action: 'kpi-milestone-chart-visibility-set', chartKey: v.chartKey, isVisible: v.isVisible }),
    onMutate: async (v) => {
      await qc.cancelQueries({ queryKey: ['kpi-milestone'] })
      const previous = qc.getQueriesData<KpiMilestoneVisibilityRow[]>({ queryKey: ['kpi-milestone'] })
      qc.setQueriesData<KpiMilestoneVisibilityRow[]>({ queryKey: ['kpi-milestone'] }, (old) =>
        Array.isArray(old)
          ? old.map((row) =>
              kpiMilestoneChartKey(v.kpiGroup, v.indicator, row.disaggregation_level_one, row.disaggregation_level_two) === v.chartKey
                ? { ...row, is_visible: v.isVisible }
                : row,
            )
          : old,
      )
      return { previous }
    },
    onError: (_err, _v, ctx) => {
      ctx?.previous.forEach(([key, data]) => qc.setQueryData(key, data))
    },
    onSettled: () => qc.invalidateQueries({ queryKey: ['kpi-milestone'] }),
  })
}

interface KpiDisaggregation {
  disaggregation_level_one: string | null
  disaggregation_level_two: string | null
}

// Populates the disagg1/disagg2 pickers in the Dashlets form from real
// values instead of free text — service_role-only RPC, called through
// admin-users like metric-config-list.
export function useKpiDisaggregations(kpiId: string | null) {
  return useQuery({
    queryKey: ['admin', 'kpi-disaggregations', kpiId],
    queryFn: () => callAdminFn('admin-users', { action: 'kpi-disaggregations-list', kpiId }) as Promise<KpiDisaggregation[]>,
    enabled: !!kpiId,
    staleTime: 5 * 60 * 1000,
  })
}

export function useDeletePermission() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (permissionId: number) =>
      callAdminFn('admin-users', { action: 'permission-delete', permissionId }) as Promise<{ ok: true; roles_affected: number }>,
    onSuccess: () => invalidateDashlets(qc),
  })
}

export function useMetricConfigs() {
  return useQuery({
    queryKey: ['admin', 'metric-config'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_metric_config')
      if (error) throw error
      return data as MetricConfig[]
    },
    staleTime: 60 * 60 * 1000,
  })
}

export interface ViewColumn {
  column_name: string
  data_type: string
}

export function useViewColumns(sourceView: string) {
  return useQuery({
    queryKey: ['admin', 'view-columns', sourceView],
    enabled: !!sourceView,
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_view_columns', { p_view_name: sourceView })
      if (error) throw error
      return data as ViewColumn[]
    },
    staleTime: 60 * 60 * 1000,
  })
}

interface ViewColumnValues {
  values: string[]
  truncated: boolean
}

export function useViewColumnValues(sourceView: string | undefined, columnName: string | undefined) {
  return useQuery({
    queryKey: ['admin', 'view-column-values', sourceView, columnName],
    enabled: !!sourceView && !!columnName,
    staleTime: 10 * 60 * 1000,
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_view_column_values', {
        p_view_name: sourceView,
        p_column_name: columnName,
      })
      if (error) throw error
      const payload = data as ViewColumnValues | null
      return { values: payload?.values ?? [], truncated: payload?.truncated ?? false }
    },
  })
}

export function useMetricConfigList() {
  return useQuery({
    queryKey: ['admin', 'metric-config-full'],
    queryFn: () => callAdminFn('admin-users', { action: 'metric-config-list' }) as Promise<MetricConfigFull[]>,
  })
}

function invalidateMetricConfig(qc: ReturnType<typeof useQueryClient>) {
  qc.invalidateQueries({ queryKey: ['admin', 'metric-config-full'] })
  qc.invalidateQueries({ queryKey: ['admin', 'metric-config'] })
  qc.invalidateQueries({ queryKey: ['admin', 'metric-config-history'] })
}

export function useCreateMetricConfig() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (metric: {
      metricName: string; sourceView: string; yearField?: string; valueAgg?: 'count' | 'sum'
      valueField?: string | null; geographyLevel?: 'school' | 'district'; filters?: unknown; enabled?: boolean; sortOrder?: number | null
    }) => callAdminFn('admin-users', { action: 'metric-config-create', ...metric }) as Promise<{ ok: true; id: number }>,
    onSuccess: () => invalidateMetricConfig(qc),
  })
}

export function useUpdateMetricConfig() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ metricId, ...metric }: {
      metricId: number; metricName?: string; sourceView?: string; yearField?: string; valueAgg?: 'count' | 'sum'
      valueField?: string | null; geographyLevel?: 'school' | 'district'; filters?: unknown; enabled?: boolean; sortOrder?: number | null
    }) => callAdminFn('admin-users', { action: 'metric-config-update', metricId, ...metric }),
    onSuccess: () => invalidateMetricConfig(qc),
  })
}

export function useDeleteMetricConfig() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (metricId: number) =>
      callAdminFn('admin-users', { action: 'metric-config-delete', metricId }) as Promise<{ ok: true; dashlets_affected: number }>,
    onSuccess: () => invalidateMetricConfig(qc),
  })
}

// ── History / revert ──────────────────────────────────────────────────────────

export interface HistoryEntry {
  id: number
  change_type: 'create' | 'update' | 'delete' | 'restore'
  snapshot: Record<string, unknown>
  changed_by_email: string | null
  changed_at: string
}

export function useDashletHistory(permissionKey: string | null) {
  return useQuery({
    queryKey: ['admin', 'dashlet-history', permissionKey],
    enabled: !!permissionKey,
    queryFn: () => callAdminFn('admin-users', { action: 'dashlet-history-list', permissionKey }) as Promise<HistoryEntry[]>,
  })
}

export function useRestoreDashlet() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (historyId: number) => callAdminFn('admin-users', { action: 'dashlet-restore', historyId }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['admin', 'permissions'] })
      qc.invalidateQueries({ queryKey: ['admin', 'dashlet-history'] })
      qc.invalidateQueries({ queryKey: ['dashlet-comments'] })
    },
  })
}

export function useMetricConfigHistory(metricId: number | null) {
  return useQuery({
    queryKey: ['admin', 'metric-config-history', metricId],
    enabled: metricId != null,
    queryFn: () => callAdminFn('admin-users', { action: 'metric-config-history-list', metricId }) as Promise<HistoryEntry[]>,
  })
}

export function useRestoreMetricConfig() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (historyId: number) => callAdminFn('admin-users', { action: 'metric-config-restore', historyId }),
    onSuccess: () => {
      invalidateMetricConfig(qc)
      qc.invalidateQueries({ queryKey: ['admin', 'metric-config-history'] })
    },
  })
}

export function useAssignUserRole() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ userId, roleId }: { userId: string; roleId: number }) =>
      callAdminFn('admin-users', { action: 'user-assign-role', userId, roleId }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin', 'users'] }),
  })
}

export function useRemoveUserRole() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ userId, roleId }: { userId: string; roleId: number }) =>
      callAdminFn('admin-users', { action: 'user-remove-role', userId, roleId }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin', 'users'] }),
  })
}

export async function fetchMyPermissions(): Promise<string[]> {
  const { data, error } = await supabase.schema('rep_portal').rpc('get_my_permissions')
  if (error) throw error
  return ((data as { key: string }[] | null) ?? []).map((r) => r.key)
}

export async function fetchMyCountries(): Promise<string[]> {
  const { data, error } = await supabase.schema('rep_portal').rpc('get_my_countries')
  if (error) throw error
  return (data as string[] | null) ?? []
}

export function useAvailableCountries() {
  return useQuery({
    queryKey: ['available-countries'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_available_countries')
      if (error) throw error
      return ((data as { country: string }[] | null) ?? []).map((r) => r.country)
    },
    staleTime: 10 * 60 * 1000,
  })
}

export function useSetUserCountries() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async ({ userId, countries }: { userId: string; countries: string[] }) => {
      const { error } = await portal().rpc('set_user_countries', { p_user_id: userId, p_countries: countries })
      if (error) throw error
    },
    onSuccess: (_data, { userId }) => {
      void qc.invalidateQueries({ queryKey: ['user-countries', userId] })
      void qc.invalidateQueries({ queryKey: ['admin', 'all-user-countries'] })
      void qc.invalidateQueries({ queryKey: ['admin', 'users'] })
    },
  })
}

export function useInviteUser() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ email, countries, roleId }: { email: string; countries: string[]; roleId?: number }) =>
      callAdminFn('admin-users', { action: 'invite', email, countries, roleId }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin', 'users'] }),
  })
}

export function useRemoveUser() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (userId: string) => callAdminFn('admin-users', { action: 'remove', userId }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin', 'users'] }),
  })
}

export function useSetUserRole() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ userId, role }: { userId: string; role: 'admin' | 'country_admin' | null }) =>
      callAdminFn('admin-users', { action: 'set-role', userId, role }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin', 'users'] }),
  })
}

// ── WhatsApp users ────────────────────────────────────────────────────────────

export interface WhatsAppDistrictAccess {
  id: number
  district_id: string
  district_name: string
  status: 'pending' | 'approved' | 'rejected'
  approver_id: number | null
  decided_at: string | null
  rejection_reason: string | null
}

export interface WhatsAppUser {
  id: number
  portal_id: string
  phone: string
  name: string | null
  email: string | null
  supabase_user_id: string | null
  is_approver: boolean
  linked_at: string | null
  created_at: string
  is_linked: boolean
  has_phone: boolean
  role_name: string | null
  approver_districts: { district_id: string; district_name: string }[]
  district_access: WhatsAppDistrictAccess[]
}

export interface DistrictOption {
  district_id: string
  district_name: string
  country: string
  province: string
}

export interface DistrictAccessRow {
  id: number
  district_id: string
  district_name: string
  status: 'pending' | 'approved' | 'rejected'
  decided_at: string | null
  rejection_reason: string | null
  created_at: string
  requester: { id: number; portal_id: string; name: string | null; phone: string } | null
  approver: { id: number; portal_id: string; name: string | null } | null
}

export function useCreateWhatsAppUser() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ phone, name, email, districtId, districtName, roleId }: { phone?: string; name?: string; email?: string; districtId?: string; districtName?: string; roleId?: number }) =>
      callAdminFn('admin-users', { action: 'whatsapp-create', phone, name, email, districtId, districtName, roleId }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['admin', 'whatsapp-users'] })
      qc.invalidateQueries({ queryKey: ['admin', 'district-access'] })
    },
  })
}

interface WhatsAppUsersPage {
  users: WhatsAppUser[]
  total: number
  page: number
  pageSize: number
}

export type WaFilter = 'all' | 'phone-only' | 'approvers' | 'has-pending'

export function useWhatsAppUsers(
  page: number,
  pageSize: number,
  filters: { search: string; filter: WaFilter; sortKey?: string; sortDir?: 'asc' | 'desc' },
) {
  return useQuery({
    queryKey: ['admin', 'whatsapp-users', page, pageSize, filters],
    queryFn: () =>
      callAdminFn('admin-users', {
        action: 'whatsapp-list',
        page,
        pageSize,
        ...filters,
      }) as Promise<WhatsAppUsersPage>,
  })
}

export function useLinkWhatsAppUser() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ whatsappUserId, supabaseEmail }: { whatsappUserId: number; supabaseEmail: string }) =>
      callAdminFn('admin-users', { action: 'whatsapp-link', whatsappUserId, supabaseEmail }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['admin', 'whatsapp-users'] })
      qc.invalidateQueries({ queryKey: ['admin', 'users'] })
    },
  })
}

export function useUnlinkWhatsAppUser() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (whatsappUserId: number) =>
      callAdminFn('admin-users', { action: 'whatsapp-unlink', whatsappUserId }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin', 'whatsapp-users'] }),
  })
}

export function useInviteWhatsAppUser() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (whatsappUserId: number) =>
      callAdminFn('admin-users', { action: 'whatsapp-invite', whatsappUserId }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['admin', 'whatsapp-users'] })
      qc.invalidateQueries({ queryKey: ['admin', 'users'] })
    },
  })
}

export function useRemoveWhatsAppUser() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: (whatsappUserId: number) =>
      callAdminFn('admin-users', { action: 'whatsapp-remove', whatsappUserId }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin', 'whatsapp-users'] }),
  })
}

export function useUpdateWhatsAppPhone() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ whatsappUserId, phone }: { whatsappUserId: number; phone: string }) =>
      callAdminFn('admin-users', { action: 'whatsapp-update-phone', whatsappUserId, phone }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin', 'whatsapp-users'] }),
  })
}

export function useSetWhatsAppApprover() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ whatsappUserId, isApprover }: { whatsappUserId: number; isApprover: boolean }) =>
      callAdminFn('admin-users', { action: 'whatsapp-set-approver', whatsappUserId, isApprover }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin', 'whatsapp-users'] }),
  })
}

export function useAssignApproverDistrict() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ whatsappUserId, districtId, districtName }: { whatsappUserId: number; districtId: string; districtName: string }) =>
      callAdminFn('admin-users', { action: 'approver-assign-district', whatsappUserId, districtId, districtName }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin', 'whatsapp-users'] }),
  })
}

export function useRemoveApproverDistrict() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ whatsappUserId, districtId }: { whatsappUserId: number; districtId: string }) =>
      callAdminFn('admin-users', { action: 'approver-remove-district', whatsappUserId, districtId }),
    onSuccess: () => qc.invalidateQueries({ queryKey: ['admin', 'whatsapp-users'] }),
  })
}

export function useDistrictOptions() {
  return useQuery({
    queryKey: ['admin', 'districts'],
    queryFn: () => callAdminFn('admin-users', { action: 'whatsapp-list-districts' }) as Promise<DistrictOption[]>,
    staleTime: 10 * 60 * 1000,
  })
}

// ── District access ───────────────────────────────────────────────────────────

interface DistrictAccessPage {
  records: DistrictAccessRow[]
  total: number
  page: number
  pageSize: number
}

export function useDistrictAccess(
  page: number,
  pageSize: number,
  filters: { districtId?: string; statusFilter?: string; search?: string; sortKey?: string; sortDir?: 'asc' | 'desc' },
) {
  return useQuery({
    queryKey: ['admin', 'district-access', page, pageSize, filters],
    queryFn: () =>
      callAdminFn('admin-users', {
        action:      'access-list',
        page,
        pageSize,
        districtId:   filters.districtId,
        statusFilter: filters.statusFilter,
        search:       filters.search,
        sortKey:      filters.sortKey,
        sortDir:      filters.sortDir,
      }) as Promise<DistrictAccessPage>,
  })
}

export function useCreateDistrictAccess() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ whatsappUserId, districtId, districtName }: { whatsappUserId: number; districtId: string; districtName: string }) =>
      callAdminFn('admin-users', { action: 'access-create', whatsappUserId, districtId, districtName }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['admin', 'district-access'] })
      qc.invalidateQueries({ queryKey: ['admin', 'whatsapp-users'] })
    },
  })
}

// ── KPI coverage summary (Overview page snapshot) ────────────────────────────

interface KpiCoverageSummaryRow {
  total_kpis: number
  kpis_with_data: number
  countries_covered: number
  years_covered: number
  last_updated: string | null
}

export function useKpiCoverageSummary() {
  return useQuery({
    queryKey: ['admin', 'kpi-coverage-summary'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_kpi_coverage_summary')
      if (error) throw error
      return (data as KpiCoverageSummaryRow[])[0] ?? null
    },
    staleTime: 5 * 60 * 1000,
  })
}

// ── KPI raw rows (year detail view) ──────────────────────────────────────────

interface AllKpiRow {
  row_id: number
  kpi_no: string | null
  indicator_group: string | null
  indicator: string | null
  disaggregation1: string | null
  disaggregation2: string | null
  value_type: string | null
  countries: Record<string, string | null> | null
  total: string | null
  updated_date: string | null
}

export const KPI_PAGE_SIZE = 100

export function useAllKpiRows(year: number | null, page: number) {
  return useQuery({
    queryKey: ['admin', 'kpi-rows', year, page],
    enabled: year !== null,
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_all_kpi_rows', {
        p_year: year!,
        p_limit: KPI_PAGE_SIZE,
        p_offset: (page - 1) * KPI_PAGE_SIZE,
      })
      if (error) throw error
      return data as AllKpiRow[]
    },
  })
}

export function useAllKpiRowCount(year: number | null) {
  return useQuery({
    queryKey: ['admin', 'kpi-row-count', year],
    enabled: year !== null,
    queryFn: async () => {
      const { data, error } = await portal().rpc('count_all_kpi_rows', { p_year: year! })
      if (error) throw error
      return data as number
    },
  })
}

export function useDeleteKpiYear() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: async (year: number) => {
      const { data, error } = await portal().rpc('kpi_delete_year', { p_year: year })
      if (error) throw error
      return data as { status: string; year: number }
    },
    onSuccess: () => {
      void qc.invalidateQueries({ queryKey: ['admin', 'loaded-years'] })
      void qc.invalidateQueries({ queryKey: ['admin', 'upload-log'] })
    },
  })
}

export function useDecideDistrictAccess() {
  const qc = useQueryClient()
  return useMutation({
    mutationFn: ({ accessId, decision, rejectionReason }: { accessId: number; decision: 'approved' | 'rejected'; rejectionReason?: string }) =>
      callAdminFn('admin-users', { action: 'access-decide', accessId, decision, rejectionReason }),
    onSuccess: () => {
      qc.invalidateQueries({ queryKey: ['admin', 'district-access'] })
      qc.invalidateQueries({ queryKey: ['admin', 'whatsapp-users'] })
    },
  })
}

// ── WhatsApp analytics ────────────────────────────────────────────────────────

export interface WaDaily {
  day: string
  unique_users: number
  total_events: number
  completions: number
  errors: number
}

export interface WaFlowSummary {
  flow: string
  unique_users: number
  started: number
  completed: number
  abandoned: number
  errors: number
  completion_pct: number | null
}

export interface WaFunnelRow {
  flow: string
  step: string
  entries: number
  unique_users: number
}

export interface WaError {
  id: number
  flow: string
  from_step: string | null
  to_step: string
  occurred_at: string
}

export function useWaDaily() {
  return useQuery({
    queryKey: ['admin', 'wa-daily'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_wa_daily')
      if (error) throw error
      return data as WaDaily[]
    },
  })
}

export function useWaFlowSummary() {
  return useQuery({
    queryKey: ['admin', 'wa-flow-summary'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_wa_flow_summary')
      if (error) throw error
      return data as WaFlowSummary[]
    },
  })
}

export function useWaFunnel(flow: string | null) {
  return useQuery({
    queryKey: ['admin', 'wa-funnel', flow],
    enabled: !!flow,
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_wa_funnel', { p_flow: flow })
      if (error) throw error
      return data as WaFunnelRow[]
    },
  })
}

export const WA_ERRORS_PAGE_SIZE = 10

export function useWaErrors(page: number) {
  return useQuery({
    queryKey: ['admin', 'wa-errors', page],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_wa_errors', {
        p_limit: WA_ERRORS_PAGE_SIZE,
        p_offset: (page - 1) * WA_ERRORS_PAGE_SIZE,
      })
      if (error) throw error
      return data as WaError[]
    },
  })
}

export function useWaErrorsCount() {
  return useQuery({
    queryKey: ['admin', 'wa-errors-count'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('count_wa_errors')
      if (error) throw error
      return data as number
    },
  })
}

// ── Portal usage analytics ──────────────────────────────────────────────────────

export interface UsageDaily {
  day: string
  page: string
  unique_users: number
  total_views: number
}

interface UsageByPage {
  page: string
  unique_users: number
  total_views: number
}

export interface UsageByUser {
  user_id: string
  user_email: string | null
  last_seen: string
  dashboard_views: number
  dynamic_views: number
  map_views: number
  total_views: number
}

export interface UsageMonthly {
  usage_month: string
  page: string
  unique_users: number
  total_views: number
}

export function useUsageDaily() {
  return useQuery({
    queryKey: ['admin', 'usage-daily'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_usage_daily')
      if (error) throw error
      return data as UsageDaily[]
    },
  })
}

export function useUsageByPage() {
  return useQuery({
    queryKey: ['admin', 'usage-by-page'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_usage_by_page')
      if (error) throw error
      return data as UsageByPage[]
    },
  })
}

export function useUsageByUser() {
  return useQuery({
    queryKey: ['admin', 'usage-by-user'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_usage_by_user')
      if (error) throw error
      return data as UsageByUser[]
    },
  })
}

export function useUsageMonthly() {
  return useQuery({
    queryKey: ['admin', 'usage-monthly'],
    queryFn: async () => {
      const { data, error } = await portal().rpc('get_usage_monthly')
      if (error) throw error
      return data as UsageMonthly[]
    },
  })
}
