import { useEffect, useState } from 'react'
import {
  Link,
  Outlet,
  createRootRouteWithContext,
  createRoute,
  createRouter,
  lazyRouteComponent,
  redirect,
  useRouterState,
} from '@tanstack/react-router'
import { ResourcePanel } from '@/components/ResourcePanel'
import type { PanelType } from '@/components/ResourcePanel'
import { DashboardPage } from '@/routes/dashboard'
import { DefaultDashboardPage } from '@/routes/default-dashboard'
import { DynamicPage } from '@/routes/dynamic'
import { SalesforceReportPage } from '@/routes/salesforce-report'
import { KpiReportPage } from '@/routes/kpi-report'
import { KpiTrendsPage } from '@/routes/kpi-trends'
import { KpiMilestonesPage } from '@/routes/kpi-milestones'
import { KpiDashboardPage } from '@/routes/kpi-dashboard'
import { SalesforceDashboardPage } from '@/routes/salesforce-dashboard'
import { HomePage } from '@/routes/home'
// MapPage is lazy-loaded — its JS chunk is only downloaded when the user
// navigates to /map, keeping it out of the main bundle entirely.
const MapPage = lazyRouteComponent(
  () => import('@/routes/map').then(m => ({ default: m.MapPage })),
)
import { SlicerPage } from '@/routes/slicer'
import { LoginPage } from '@/routes/login'
import { SetPasswordPage } from '@/routes/set-password'
import { ForgotPasswordPage } from '@/routes/forgot-password'
import { ResetPasswordPage } from '@/routes/reset-password'
import { AdminLayout } from '@/routes/admin/layout'
import { AdminIndexPage } from '@/routes/admin/index'
import { AdminIngestPage } from '@/routes/admin/ingest'
import { AdminKpisPage } from '@/routes/admin/kpis'
import { AdminUsersPage } from '@/routes/admin/users'
import { AdminLogsPage } from '@/routes/admin/logs'
import { AdminWhatsAppPage } from '@/routes/admin/whatsapp'
import { AdminUsagePage } from '@/routes/admin/usage'
import { AdminDocsPage } from '@/routes/admin/docs'
import { RolesPage } from '@/routes/admin/roles'
import { AdminDashletsPage } from '@/routes/admin/dashlets'
import { AdminDashletCommentsPage } from '@/routes/admin/dashlet-comments'
import { AdminSalesforceReportsPage } from '@/routes/admin/salesforce-reports'
import { AdminCoveragePage } from '@/routes/admin/coverage'
import { AdminReconPage } from '@/routes/admin/recon'
import { useAuth } from '@/contexts/AuthContext'
import { DictionaryProvider } from '@/contexts/DictionaryContext'
import { DashletCommentsProvider } from '@/contexts/DashletCommentsContext'
import { isDemoOpenAccess, isSupabaseConfigured, supabase } from '@/lib/supabase'

type AuthContext = ReturnType<typeof useAuth>

interface RouterContext {
  auth: AuthContext
}

// ── Root (no auth guard — just provides context) ─────────────────────────────
const rootRoute = createRootRouteWithContext<RouterContext>()({
  component: () => <Outlet />,
})

// ── Login (public) ────────────────────────────────────────────────────────────
const loginRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/login',
  component: LoginPage,
})

// ── Set password (public — handles invite-link flow) ─────────────────────────
const setPasswordRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/set-password',
  component: SetPasswordPage,
})

// ── Forgot password (public) ──────────────────────────────────────────────────
const forgotPasswordRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/forgot-password',
  component: ForgotPasswordPage,
})

// ── Reset password (public — handles recovery-link flow) ─────────────────────
const resetPasswordRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/reset-password',
  component: ResetPasswordPage,
})

// ── Protected layout (pathless — wraps all authenticated pages) ───────────────
const authRoute = createRoute({
  getParentRoute: () => rootRoute,
  id: '_auth',
  beforeLoad: ({ context, location }) => {
    if (context.auth.loading) return
    if (!isSupabaseConfigured || isDemoOpenAccess) return
    if (!context.auth.session) {
      throw redirect({
        to: '/login',
        search: { redirect: location.href },
      })
    }
    if (context.auth.needsPasswordSet) {
      throw redirect({ to: '/set-password' })
    }
    if (context.auth.needsPasswordReset) {
      throw redirect({ to: '/reset-password' })
    }
  },
  component: RootLayout,
})

// ── Existing routes (now under authRoute) ────────────────────────────────────
const indexRoute = createRoute({
  getParentRoute: () => authRoute,
  path: '/',
  component: HomePage,
})

const dashboardRoute = createRoute({
  getParentRoute: () => authRoute,
  path: '/dashboard',
  validateSearch: (search: Record<string, unknown>) => ({
    level: typeof search.level === 'string' ? search.level : undefined,
    subLevel: typeof search.subLevel === 'string' ? search.subLevel : undefined,
    countries: Array.isArray(search.countries)
      ? (search.countries as string[]).filter((c): c is string => typeof c === 'string')
      : typeof search.countries === 'string'
        ? [search.countries]
        : undefined,
    startYear: typeof search.startYear === 'number' ? search.startYear : undefined,
    endYear: typeof search.endYear === 'number' ? search.endYear : undefined,
  }),
  component: DashboardPage,
})

const defaultDashboardRoute = createRoute({
  getParentRoute: () => authRoute,
  path: '/default-dashboard',
  validateSearch: (search: Record<string, unknown>) => ({
    level: typeof search.level === 'string' ? search.level : undefined,
    subLevel: typeof search.subLevel === 'string' ? search.subLevel : undefined,
    countries: Array.isArray(search.countries)
      ? (search.countries as string[]).filter((c): c is string => typeof c === 'string')
      : typeof search.countries === 'string'
        ? [search.countries]
        : undefined,
    year: typeof search.year === 'number' ? search.year : undefined,
  }),
  component: DefaultDashboardPage,
})

const dynamicRoute = createRoute({
  getParentRoute: () => authRoute,
  path: '/dynamic',
  component: DynamicPage,
})

const salesforceReportRoute = createRoute({
  getParentRoute: () => authRoute,
  path: '/salesforce-report',
  component: SalesforceReportPage,
})

const kpiReportRoute = createRoute({
  getParentRoute: () => authRoute,
  path: '/kpi-report',
  validateSearch: (search: Record<string, unknown>) => ({
    country: typeof search.country === 'string' ? search.country : undefined,
    year: typeof search.year === 'number' ? search.year : undefined,
    group: typeof search.group === 'string' ? search.group : undefined,
  }),
  component: KpiReportPage,
})

const kpiTrendsRoute = createRoute({
  getParentRoute: () => authRoute,
  path: '/kpi-trends',
  validateSearch: (search: Record<string, unknown>) => ({
    country: typeof search.country === 'string' ? search.country : undefined,
    group: typeof search.group === 'string' ? search.group : undefined,
    indicator: typeof search.indicator === 'string' ? search.indicator : undefined,
  }),
  component: KpiTrendsPage,
})

const kpiMilestonesRoute = createRoute({
  getParentRoute: () => authRoute,
  path: '/kpi-milestones',
  validateSearch: (search: Record<string, unknown>) => ({
    year: typeof search.year === 'number' ? search.year : undefined,
    group: typeof search.group === 'string' ? search.group : undefined,
    indicator: typeof search.indicator === 'string' ? search.indicator : undefined,
  }),
  component: KpiMilestonesPage,
})

const kpiDashboardRoute = createRoute({
  getParentRoute: () => authRoute,
  path: '/kpi-dashboard',
  validateSearch: (search: Record<string, unknown>) => ({
    groups: Array.isArray(search.groups)
      ? (search.groups as string[]).filter((g): g is string => typeof g === 'string')
      : typeof search.groups === 'string'
        ? [search.groups]
        : undefined,
    countries: Array.isArray(search.countries)
      ? (search.countries as string[]).filter((c): c is string => typeof c === 'string')
      : typeof search.countries === 'string'
        ? [search.countries]
        : undefined,
    year: typeof search.year === 'number' ? search.year : undefined,
    // Router default search parsing JSON.parse's each raw query value, so
    // ?preview=1 arrives as the number 1, not the string "1" — accept both
    // forms rather than silently dropping the number case.
    preview: search.preview === 1 || search.preview === '1' ? '1' : undefined,
    // Which KPI dashboard to show — omitted resolves server-side to the
    // type's is_default dashboard (get_kpi_dashlets(NULL)), so existing
    // links/bookmarks without this param keep working unchanged.
    dashboard: typeof search.dashboard === 'string' ? search.dashboard : undefined,
  }),
  component: KpiDashboardPage,
})

const salesforceDashboardRoute = createRoute({
  getParentRoute: () => authRoute,
  path: '/salesforce-dashboard',
  validateSearch: (search: Record<string, unknown>) => ({
    groups: Array.isArray(search.groups)
      ? (search.groups as string[]).filter((g): g is string => typeof g === 'string')
      : typeof search.groups === 'string'
        ? [search.groups]
        : undefined,
    countries: Array.isArray(search.countries)
      ? (search.countries as string[]).filter((c): c is string => typeof c === 'string')
      : typeof search.countries === 'string'
        ? [search.countries]
        : undefined,
    yearStart: typeof search.yearStart === 'number' ? search.yearStart : undefined,
    yearEnd: typeof search.yearEnd === 'number' ? search.yearEnd : undefined,
    // Router default search parsing JSON.parse's each raw query value, so
    // ?preview=1 arrives as the number 1, not the string "1" — accept both
    // forms rather than silently dropping the number case.
    preview: search.preview === 1 || search.preview === '1' ? '1' : undefined,
    // Which Salesforce dashboard to show — omitted resolves server-side to
    // the type's is_default dashboard (get_salesforce_dashlets(NULL)), so
    // existing links/bookmarks without this param keep working unchanged.
    dashboard: typeof search.dashboard === 'string' ? search.dashboard : undefined,
  }),
  component: SalesforceDashboardPage,
})

const slicerRoute = createRoute({
  getParentRoute: () => authRoute,
  path: '/slicer',
  component: SlicerPage,
})

const mapRoute = createRoute({
  getParentRoute: () => authRoute,
  path: '/map',
  component: MapPage,
})

// ── Admin routes ──────────────────────────────────────────────────────────────
const adminRoute = createRoute({
  getParentRoute: () => rootRoute,
  path: '/admin',
  beforeLoad: ({ context }) => {
    if (!context.auth.session) {
      throw redirect({ to: '/login' })
    }
  },
  component: AdminLayout,
})

const adminIndexRoute = createRoute({
  getParentRoute: () => adminRoute,
  path: '/',
  component: AdminIndexPage,
})

function blockCountryAdmin({ context }: { context: RouterContext }) {
  if (context.auth.isCountryAdmin) throw redirect({ to: '/admin/users' })
}

const adminIngestRoute = createRoute({
  getParentRoute: () => adminRoute,
  path: '/ingest',
  beforeLoad: blockCountryAdmin,
  component: AdminIngestPage,
})

const adminKpisRoute = createRoute({
  getParentRoute: () => adminRoute,
  path: '/kpis',
  beforeLoad: blockCountryAdmin,
  component: AdminKpisPage,
})

const adminUsersRoute = createRoute({
  getParentRoute: () => adminRoute,
  path: '/users',
  component: AdminUsersPage,
})

const adminLogsRoute = createRoute({
  getParentRoute: () => adminRoute,
  path: '/logs',
  beforeLoad: blockCountryAdmin,
  component: AdminLogsPage,
})

const adminWhatsAppRoute = createRoute({
  getParentRoute: () => adminRoute,
  path: '/whatsapp',
  beforeLoad: blockCountryAdmin,
  component: AdminWhatsAppPage,
})

const adminUsageRoute = createRoute({
  getParentRoute: () => adminRoute,
  path: '/usage',
  beforeLoad: blockCountryAdmin,
  component: AdminUsagePage,
})

const adminRolesRoute = createRoute({
  getParentRoute: () => adminRoute,
  path: '/roles',
  beforeLoad: blockCountryAdmin,
  component: RolesPage,
})

const adminDashletsRoute = createRoute({
  getParentRoute: () => adminRoute,
  path: '/dashlets',
  beforeLoad: blockCountryAdmin,
  component: AdminDashletsPage,
})

const adminDashletCommentsRoute = createRoute({
  getParentRoute: () => adminRoute,
  path: '/dashlet-comments',
  beforeLoad: blockCountryAdmin,
  component: AdminDashletCommentsPage,
})

const adminSalesforceReportsRoute = createRoute({
  getParentRoute: () => adminRoute,
  path: '/salesforce-reports',
  beforeLoad: blockCountryAdmin,
  component: AdminSalesforceReportsPage,
})

const adminCoverageRoute = createRoute({
  getParentRoute: () => adminRoute,
  path: '/coverage',
  beforeLoad: blockCountryAdmin,
  component: AdminCoveragePage,
})

const adminReconRoute = createRoute({
  getParentRoute: () => adminRoute,
  path: '/recon',
  beforeLoad: blockCountryAdmin,
  component: AdminReconPage,
})

const adminDocsRoute = createRoute({
  getParentRoute: () => adminRoute,
  path: '/docs',
  component: AdminDocsPage,
})

// ── Route tree ────────────────────────────────────────────────────────────────
const routeTree = rootRoute.addChildren([
  loginRoute,
  setPasswordRoute,
  forgotPasswordRoute,
  resetPasswordRoute,
  authRoute.addChildren([
    indexRoute,
    dashboardRoute,
    defaultDashboardRoute,
    dynamicRoute,
    salesforceReportRoute,
    kpiReportRoute,
    kpiTrendsRoute,
    kpiMilestonesRoute,
    kpiDashboardRoute,
    salesforceDashboardRoute,
    slicerRoute,
    mapRoute,
  ]),
  adminRoute.addChildren([
    adminIndexRoute,
    adminIngestRoute,
    adminKpisRoute,
    adminUsersRoute,
    adminLogsRoute,
    adminWhatsAppRoute,
    adminUsageRoute,
    adminRolesRoute,
    adminDashletsRoute,
    adminDashletCommentsRoute,
    adminSalesforceReportsRoute,
    adminCoverageRoute,
    adminReconRoute,
    adminDocsRoute,
  ]),
])

export const router = createRouter({
  routeTree,
  defaultPreload: 'intent',
  context: {
    auth: undefined!,
  },
})

declare module '@tanstack/react-router' {
  interface Register {
    router: typeof router
  }
}

// ── RootLayout (authenticated pages) ─────────────────────────────────────────
function RootLayout() {
  const [sidebarOpen,  setSidebarOpen]  = useState(false)
  const [activePanel,  setActivePanel]  = useState<PanelType | null>(null)
  const closeSidebar = () => setSidebarOpen(false)
  const openPanel = (p: PanelType) => (e: React.MouseEvent) => {
    e.preventDefault()
    setSidebarOpen(false)
    setActivePanel(p)
  }
  const { user, isAdmin, isCountryAdmin, signOut, hasPermission, permissionsLoaded } = useAuth()

  const pathname = useRouterState({ select: (s) => s.location.pathname })
  const pageTitle =
    pathname === '/'                     ? 'Home'
    : pathname.startsWith('/default-dashboard') ? 'Default Dashboard (Preview)'
    : pathname.startsWith('/dashboard')  ? 'Data Dashboard'
    : pathname.startsWith('/dynamic')    ? 'Dynamic Data'
    : pathname.startsWith('/salesforce-report') ? 'Salesforce Report'
    : pathname.startsWith('/kpi-report') ? 'KPI Report'
    : pathname.startsWith('/kpi-trends') ? 'KPI Trends'
    : pathname.startsWith('/kpi-milestones') ? 'KPI Milestones'
    : pathname.startsWith('/kpi-dashboard') ? 'KPI Dashboard'
    : pathname.startsWith('/salesforce-dashboard') ? 'Salesforce Dashboard'
    : pathname.startsWith('/slicer')     ? 'My Slicer'
    : pathname.startsWith('/map')        ? 'Data Map'
    : 'SHF Agriculture'

  const trackedPage =
    pathname.startsWith('/default-dashboard') ? 'default-dashboard'
    : pathname.startsWith('/dashboard')  ? 'dashboard'
    : pathname.startsWith('/dynamic')  ? 'dynamic'
    : pathname.startsWith('/salesforce-report') ? 'salesforce-report'
    : pathname.startsWith('/kpi-report') ? 'kpi-report'
    : pathname.startsWith('/kpi-trends') ? 'kpi-trends'
    : pathname.startsWith('/kpi-milestones') ? 'kpi-milestones'
    : pathname.startsWith('/kpi-dashboard') ? 'kpi-dashboard'
    : pathname.startsWith('/salesforce-dashboard') ? 'salesforce-dashboard'
    : pathname.startsWith('/map')      ? 'map'
    : null

  useEffect(() => {
    // Page-view logging writes as the signed-in user; an open demo has none, so skip it.
    if (!trackedPage || !isSupabaseConfigured || isDemoOpenAccess) return
    void supabase.schema('rep_portal').rpc('log_page_view', { p_page: trackedPage }).then(({ error }) => {
      if (error) console.error('log_page_view failed', error)
    })
  }, [trackedPage])

  return (
    <DictionaryProvider>
    <DashletCommentsProvider>
    <div className="app-shell">
      {sidebarOpen && (
        <div className="sidebar-backdrop" onClick={closeSidebar} aria-hidden="true" />
      )}

      <aside className={`sidebar${sidebarOpen ? ' sidebar--open' : ''}`}>
        <div className="sidebar-logo">
          <img src="/images/shf-logo-horizontal.jpg" alt="SHF Agriculture" className="sidebar-logo-img" />
          <button className="sidebar-close-btn" onClick={closeSidebar} aria-label="Close menu">
            <svg width="18" height="18" viewBox="0 0 20 20" fill="none">
              <path d="M5 5l10 10M15 5L5 15" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
            </svg>
          </button>
        </div>

        <nav className="sidebar-mobile-nav">
          <div className="sidebar-section-label">Navigation</div>
          <Link to="/" className="sidebar-nav-item" onClick={closeSidebar} activeProps={{ className: 'sidebar-nav-item sidebar-nav-item--active' }}>
            <svg className="sidebar-nav-icon" viewBox="0 0 20 20" fill="none">
              <path d="M3 9.5L10 3l7 6.5V17a1 1 0 01-1 1h-4v-4H8v4H4a1 1 0 01-1-1V9.5z" stroke="currentColor" strokeWidth="1.8" strokeLinejoin="round" />
            </svg>
            Home
          </Link>
          {(!permissionsLoaded || hasPermission('page:dashboard')) && (
            <Link
              to="/dashboard"
              className="sidebar-nav-item"
              onClick={closeSidebar}
              activeProps={{ className: 'sidebar-nav-item sidebar-nav-item--active' }}
              search={{ level: undefined, subLevel: undefined, countries: undefined, startYear: undefined, endYear: undefined }}
            >
              <svg className="sidebar-nav-icon" viewBox="0 0 20 20" fill="none">
                <rect x="2" y="10" width="4" height="8" rx="1" stroke="currentColor" strokeWidth="1.7" />
                <rect x="8" y="6" width="4" height="12" rx="1" stroke="currentColor" strokeWidth="1.7" />
                <rect x="14" y="2" width="4" height="16" rx="1" stroke="currentColor" strokeWidth="1.7" />
              </svg>
              Data Dashboard
            </Link>
          )}
          {(!permissionsLoaded || hasPermission('page:dynamic')) && (
            <Link to="/dynamic" className="sidebar-nav-item" onClick={closeSidebar} activeProps={{ className: 'sidebar-nav-item sidebar-nav-item--active' }}>
              <svg className="sidebar-nav-icon" viewBox="0 0 20 20" fill="none">
                <circle cx="10" cy="10" r="8" stroke="currentColor" strokeWidth="1.7" />
                <path d="M10 2c0 0-3 3-3 8s3 8 3 8M10 2c0 0 3 3 3 8s-3 8-3 8M2 10h16" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
              </svg>
              Dynamic Data
            </Link>
          )}
          {(!permissionsLoaded || hasPermission('page:map')) && (
            <Link to="/map" className="sidebar-nav-item" onClick={closeSidebar} activeProps={{ className: 'sidebar-nav-item sidebar-nav-item--active' }}>
              <svg className="sidebar-nav-icon" viewBox="0 0 20 20" fill="none">
                <path d="M3 5.5l4-2 6 2 4-2v11l-4 2-6-2-4 2v-11z" stroke="currentColor" strokeWidth="1.7" strokeLinejoin="round" />
                <path d="M7 3.5v11M13 5.5v11" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
              </svg>
              Data Map
            </Link>
          )}
          {/* KPI Milestones and KPI Trends hidden on the demo deployment. Routes stay
              registered and reachable directly at /kpi-milestones and /kpi-trends.
          {(!permissionsLoaded || hasPermission('page:kpi-milestones')) && (
            <Link
              to="/kpi-milestones"
              className="sidebar-nav-item"
              onClick={closeSidebar}
              activeProps={{ className: 'sidebar-nav-item sidebar-nav-item--active' }}
              search={{ year: undefined, group: undefined, indicator: undefined }}
            >
              <svg className="sidebar-nav-icon" viewBox="0 0 20 20" fill="none">
                <path d="M3 17V9M8 17V5M13 17v-9M17 3l-6.5 6.5" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              KPI Milestones
            </Link>
          )}
          {(!permissionsLoaded || hasPermission('page:kpi-trends')) && (
            <Link
              to="/kpi-trends"
              className="sidebar-nav-item"
              onClick={closeSidebar}
              activeProps={{ className: 'sidebar-nav-item sidebar-nav-item--active' }}
              search={{ country: undefined, group: undefined, indicator: undefined }}
            >
              <svg className="sidebar-nav-icon" viewBox="0 0 20 20" fill="none">
                <path d="M2 15l5-6 4 3 6-7" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
                <path d="M13 5h4v4" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
              </svg>
              KPI Trends
            </Link>
          )}
          */}
          {/* Hidden for now — pending approval, see conversation 2026-07-18. Route still reachable directly.
          <Link
            to="/kpi-dashboard"
            className="sidebar-nav-item"
            onClick={closeSidebar}
            activeProps={{ className: 'sidebar-nav-item sidebar-nav-item--active' }}
            search={{ groups: undefined, countries: undefined, year: undefined }}
          >
            <svg className="sidebar-nav-icon" viewBox="0 0 20 20" fill="none">
              <rect x="2" y="10" width="4" height="8" rx="1" stroke="currentColor" strokeWidth="1.7" />
              <rect x="8" y="6" width="4" height="12" rx="1" stroke="currentColor" strokeWidth="1.7" />
              <rect x="14" y="3" width="4" height="15" rx="1" stroke="currentColor" strokeWidth="1.7" />
            </svg>
            KPI Dashboard
          </Link>
          <Link
            to="/salesforce-dashboard"
            className="sidebar-nav-item"
            onClick={closeSidebar}
            activeProps={{ className: 'sidebar-nav-item sidebar-nav-item--active' }}
            search={{ groups: undefined, countries: undefined, yearStart: undefined, yearEnd: undefined }}
          >
            <svg className="sidebar-nav-icon" viewBox="0 0 20 20" fill="none">
              <rect x="2" y="10" width="4" height="8" rx="1" stroke="currentColor" strokeWidth="1.7" />
              <rect x="8" y="6" width="4" height="12" rx="1" stroke="currentColor" strokeWidth="1.7" />
              <rect x="14" y="3" width="4" height="15" rx="1" stroke="currentColor" strokeWidth="1.7" />
            </svg>
            Salesforce Dashboard
          </Link>
          */}
          {(!permissionsLoaded || hasPermission('page:kpi-report')) && (
            <Link
              to="/kpi-report"
              className="sidebar-nav-item"
              onClick={closeSidebar}
              activeProps={{ className: 'sidebar-nav-item sidebar-nav-item--active' }}
              search={{ country: undefined, year: undefined, group: undefined }}
            >
              <svg className="sidebar-nav-icon" viewBox="0 0 20 20" fill="none">
                <rect x="3" y="3" width="14" height="14" rx="2" stroke="currentColor" strokeWidth="1.7" />
                <path d="M6.5 10h7M6.5 13.5h4.5M6.5 6.5h7" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
              </svg>
              KPI Report
            </Link>
          )}
          {/* Hidden for now — see conversation 2026-07-15
          <Link to="/salesforce-report" className="sidebar-nav-item" onClick={closeSidebar} activeProps={{ className: 'sidebar-nav-item sidebar-nav-item--active' }}>
            <svg className="sidebar-nav-icon" viewBox="0 0 20 20" fill="none">
              <rect x="2" y="3" width="16" height="14" rx="1.5" stroke="currentColor" strokeWidth="1.7" />
              <path d="M2 8h16M7 8v9" stroke="currentColor" strokeWidth="1.5" />
            </svg>
            Salesforce Report
          </Link>
          */}
        </nav>

        <div className="sidebar-resources">
          <div className="sidebar-section-label">Resources</div>
          <a href="#" className="sidebar-nav-item sidebar-nav-item--resource" onClick={openPanel('guides')}>
            <svg className="sidebar-nav-icon" viewBox="0 0 20 20" fill="none">
              <rect x="4" y="2" width="12" height="16" rx="2" stroke="currentColor" strokeWidth="1.7" />
              <path d="M7 6h6M7 10h6M7 14h4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
            </svg>
            <span className="sidebar-nav-item-content">
              Guides &amp; Documentation
              <span className="sidebar-nav-item-hint">Click to view how-to guides</span>
            </span>
          </a>
          <a href="#" className="sidebar-nav-item sidebar-nav-item--resource" onClick={openPanel('dictionary')}>
            <svg className="sidebar-nav-icon" viewBox="0 0 20 20" fill="none">
              <rect x="4" y="2" width="12" height="16" rx="2" stroke="currentColor" strokeWidth="1.7" />
              <path d="M7 6h6M7 10h4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
              <circle cx="13" cy="14" r="2.5" stroke="currentColor" strokeWidth="1.4" />
              <path d="M15 16l1.5 1.5" stroke="currentColor" strokeWidth="1.4" strokeLinecap="round" />
            </svg>
            <span className="sidebar-nav-item-content">
              Data Dictionary
              <span className="sidebar-nav-item-hint">Click to browse KPI definitions</span>
            </span>
          </a>
        </div>

        <div className="sidebar-user">
          <span className="sidebar-user-email">{user?.email}</span>
          <div className="sidebar-user-actions">
            {(isAdmin || isCountryAdmin) && (
              <a href="/admin" className="sidebar-user-admin" onClick={closeSidebar}>Admin</a>
            )}
            <button className="sidebar-user-signout" onClick={() => { closeSidebar(); void signOut() }}>
              Sign out
            </button>
          </div>
        </div>

        <div className="sidebar-deco-bottom" aria-hidden="true">
          <svg viewBox="0 0 160 120" xmlns="http://www.w3.org/2000/svg" preserveAspectRatio="xMidYMax slice">
            <circle cx="20" cy="130" r="90" fill="rgba(255,255,255,0.06)" />
            <circle cx="110" cy="140" r="70" fill="rgba(255,255,255,0.05)" />
            <circle cx="150" cy="90" r="55" fill="rgba(255,255,255,0.04)" />
            <circle cx="-10" cy="80" r="40" fill="rgba(255,255,255,0.05)" />
          </svg>
        </div>
      </aside>

      <div className="app">
        <div className="header">
          <button
            className="hamburger-btn"
            onClick={() => setSidebarOpen(true)}
            aria-label="Open menu"
          >
            <svg width="20" height="20" viewBox="0 0 20 20" fill="none">
              <path d="M3 5h14M3 10h14M3 15h14" stroke="currentColor" strokeWidth="2" strokeLinecap="round" />
            </svg>
          </button>
          <span className="mobile-page-title">{pageTitle}</span>
          <nav className="top-nav">
            <Link to="/" className="top-nav-item" activeProps={{ className: 'top-nav-item top-nav-item--active' }}>
              <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
                <path d="M3 9.5L10 3l7 6.5V17a1 1 0 01-1 1h-4v-4H8v4H4a1 1 0 01-1-1V9.5z" stroke="currentColor" strokeWidth="1.8" strokeLinejoin="round" />
              </svg>
              Home
            </Link>
            {(!permissionsLoaded || hasPermission('page:dashboard')) && (
              <>
                <span className="top-nav-divider" />
                <Link
                  to="/dashboard"
                  className="top-nav-item"
                  activeProps={{ className: 'top-nav-item top-nav-item--active' }}
                  search={{ level: undefined, subLevel: undefined, countries: undefined, startYear: undefined, endYear: undefined }}
                >
                  <svg width="15" height="15" viewBox="0 0 20 20" fill="none" aria-hidden="true">
                    <rect x="2" y="10" width="4" height="8" rx="1" stroke="currentColor" strokeWidth="1.7" />
                    <rect x="8" y="6" width="4" height="12" rx="1" stroke="currentColor" strokeWidth="1.7" />
                    <rect x="14" y="2" width="4" height="16" rx="1" stroke="currentColor" strokeWidth="1.7" />
                  </svg>
                  Data Dashboard
                </Link>
              </>
            )}
            {(!permissionsLoaded || hasPermission('page:dynamic')) && (
              <>
                <span className="top-nav-divider" />
                <Link to="/dynamic" className="top-nav-item" activeProps={{ className: 'top-nav-item top-nav-item--active' }}>
                  <svg width="15" height="15" viewBox="0 0 20 20" fill="none" aria-hidden="true">
                    <circle cx="10" cy="10" r="8" stroke="currentColor" strokeWidth="1.7" />
                    <path d="M10 2c0 0-3 3-3 8s3 8 3 8M10 2c0 0 3 3 3 8s-3 8-3 8M2 10h16" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
                  </svg>
                  Dynamic Data
                </Link>
              </>
            )}
            {(!permissionsLoaded || hasPermission('page:map')) && (
              <>
                <span className="top-nav-divider" />
                <Link to="/map" className="top-nav-item" activeProps={{ className: 'top-nav-item top-nav-item--active' }}>
                  <svg width="15" height="15" viewBox="0 0 20 20" fill="none" aria-hidden="true">
                    <path d="M3 5.5l4-2 6 2 4-2v11l-4 2-6-2-4 2v-11z" stroke="currentColor" strokeWidth="1.7" strokeLinejoin="round" />
                    <path d="M7 3.5v11M13 5.5v11" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
                  </svg>
                  Data Map
                </Link>
              </>
            )}
            {/* KPI Milestones and KPI Trends hidden on the demo deployment. Routes stay
                registered and reachable directly.
            {(!permissionsLoaded || hasPermission('page:kpi-milestones')) && (
              <>
                <span className="top-nav-divider" />
                <Link
                  to="/kpi-milestones"
                  className="top-nav-item"
                  activeProps={{ className: 'top-nav-item top-nav-item--active' }}
                  search={{ year: undefined, group: undefined, indicator: undefined }}
                >
                  <svg width="15" height="15" viewBox="0 0 20 20" fill="none" aria-hidden="true">
                    <path d="M3 17V9M8 17V5M13 17v-9M17 3l-6.5 6.5" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                  KPI Milestones
                </Link>
              </>
            )}
            {(!permissionsLoaded || hasPermission('page:kpi-trends')) && (
              <>
                <span className="top-nav-divider" />
                <Link
                  to="/kpi-trends"
                  className="top-nav-item"
                  activeProps={{ className: 'top-nav-item top-nav-item--active' }}
                  search={{ country: undefined, group: undefined, indicator: undefined }}
                >
                  <svg width="15" height="15" viewBox="0 0 20 20" fill="none" aria-hidden="true">
                    <path d="M2 15l5-6 4 3 6-7" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
                    <path d="M13 5h4v4" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                  KPI Trends
                </Link>
              </>
            )}
            */}
            {/* Hidden for now — pending approval, see conversation 2026-07-18. Route still reachable directly.
            <span className="top-nav-divider" />
            <Link
              to="/kpi-dashboard"
              className="top-nav-item"
              activeProps={{ className: 'top-nav-item top-nav-item--active' }}
              search={{ groups: undefined, countries: undefined, year: undefined }}
            >
              <svg width="15" height="15" viewBox="0 0 20 20" fill="none" aria-hidden="true">
                <rect x="2" y="10" width="4" height="8" rx="1" stroke="currentColor" strokeWidth="1.7" />
                <rect x="8" y="6" width="4" height="12" rx="1" stroke="currentColor" strokeWidth="1.7" />
                <rect x="14" y="3" width="4" height="15" rx="1" stroke="currentColor" strokeWidth="1.7" />
              </svg>
              KPI Dashboard
            </Link>
            <span className="top-nav-divider" />
            <Link
              to="/salesforce-dashboard"
              className="top-nav-item"
              activeProps={{ className: 'top-nav-item top-nav-item--active' }}
              search={{ groups: undefined, countries: undefined, yearStart: undefined, yearEnd: undefined }}
            >
              <svg width="15" height="15" viewBox="0 0 20 20" fill="none" aria-hidden="true">
                <rect x="2" y="10" width="4" height="8" rx="1" stroke="currentColor" strokeWidth="1.7" />
                <rect x="8" y="6" width="4" height="12" rx="1" stroke="currentColor" strokeWidth="1.7" />
                <rect x="14" y="3" width="4" height="15" rx="1" stroke="currentColor" strokeWidth="1.7" />
              </svg>
              Salesforce Dashboard
            </Link>
            */}
            {(!permissionsLoaded || hasPermission('page:kpi-report')) && (
              <>
                <span className="top-nav-divider" />
                <Link
                  to="/kpi-report"
                  className="top-nav-item"
                  activeProps={{ className: 'top-nav-item top-nav-item--active' }}
                  search={{ country: undefined, year: undefined, group: undefined }}
                >
                  <svg width="15" height="15" viewBox="0 0 20 20" fill="none" aria-hidden="true">
                    <rect x="3" y="3" width="14" height="14" rx="2" stroke="currentColor" strokeWidth="1.7" />
                    <path d="M6.5 10h7M6.5 13.5h4.5M6.5 6.5h7" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
                  </svg>
                  KPI Report
                </Link>
              </>
            )}
            {/* Hidden for now — see conversation 2026-07-15
            <span className="top-nav-divider" />
            <Link to="/salesforce-report" className="top-nav-item" activeProps={{ className: 'top-nav-item top-nav-item--active' }}>
              <svg width="15" height="15" viewBox="0 0 20 20" fill="none" aria-hidden="true">
                <rect x="2" y="3" width="16" height="14" rx="1.5" stroke="currentColor" strokeWidth="1.7" />
                <path d="M2 8h16M7 8v9" stroke="currentColor" strokeWidth="1.5" />
              </svg>
              Salesforce Report
            </Link>
            */}
          </nav>
          <div className="header-user">
            <span className="header-user-email">{user?.email}</span>
            {(isAdmin || isCountryAdmin) && (
              <a href="/admin" className="header-user-link">Admin</a>
            )}
            <button className="header-signout-btn" onClick={() => void signOut()}>
              Sign out
            </button>
          </div>
        </div>

        <Outlet />
      </div>

      {activePanel && (
        <ResourcePanel panel={activePanel} onClose={() => setActivePanel(null)} />
      )}
    </div>
    </DashletCommentsProvider>
    </DictionaryProvider>
  )
}
