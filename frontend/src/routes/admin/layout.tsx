import { useState } from 'react'
import { Link, Outlet, useRouterState } from '@tanstack/react-router'
import { useAuth } from '@/contexts/AuthContext'

// Nav links gated behind this stay in the codebase (and their routes stay
// directly reachable by URL) but are hidden from the admin nav pending
// approval — see conversation 2026-07-18.
const SHOW_PENDING_APPROVAL_NAV = false

export function AdminLayout() {
  const { isAdmin, isCountryAdmin, user, signOut } = useAuth()
  const pathname = useRouterState({ select: (s) => s.location.pathname })
  const [sidebarOpen, setSidebarOpen] = useState(false)

  function closeNav() { setSidebarOpen(false) }

  if (!isAdmin && !isCountryAdmin) {
    return (
      <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center', height: '100vh', flexDirection: 'column', gap: '12px' }}>
        <h1 style={{ fontSize: '24px', fontWeight: 600 }}>Access Denied</h1>
        <p style={{ color: '#6b7280' }}>You do not have admin access.</p>
        <Link to="/" style={{ color: '#2563eb', textDecoration: 'underline' }}>Go to home</Link>
      </div>
    )
  }

  function navClass(prefix: string, exact = false) {
    const active = exact ? pathname === prefix : pathname.startsWith(prefix)
    return `admin-nav-item${active ? ' admin-nav-item--active' : ''}`
  }

  return (
    <div className="admin-shell">
      <aside className={`admin-sidebar${sidebarOpen ? ' admin-sidebar--open' : ''}`}>
        <div className="admin-sidebar-logo">
          <img src="/images/shf-logo-horizontal.jpg" alt="SHF Agriculture" className="admin-sidebar-logo-img" />
          <span className="admin-sidebar-label">{isCountryAdmin ? 'Country Admin' : 'Admin'}</span>
        </div>

        <nav className="admin-nav">
          {!isCountryAdmin && (
            <Link to="/admin" className={navClass('/admin', true)} activeOptions={{ exact: true }} onClick={closeNav}>
              <OverviewIcon />
              Overview
            </Link>
          )}
          <Link to="/admin/users" className={navClass('/admin/users')} onClick={closeNav}>
            <UsersIcon />
            Users
          </Link>
          {!isCountryAdmin && (
            <>
              <Link to="/admin/roles" className={navClass('/admin/roles')} onClick={closeNav}>
                <RolesIcon />
                User Roles
              </Link>
              {SHOW_PENDING_APPROVAL_NAV && (
                <Link to="/admin/dashlets" className={navClass('/admin/dashlets')} onClick={closeNav}>
                  <DashletsIcon />
                  Dashlets
                </Link>
              )}
              <Link to="/admin/dashlet-comments" className={navClass('/admin/dashlet-comments')} onClick={closeNav}>
                <DashletCommentIcon />
                Dashlet Comments
              </Link>
              <Link to="/admin/kpis" className={navClass('/admin/kpis')} onClick={closeNav}>
                <KpiIcon />
                KPI Upload
              </Link>
              <Link to="/admin/coverage" className={navClass('/admin/coverage')} onClick={closeNav}>
                <CoverageIcon />
                KPI Data Coverage
              </Link>
              <Link to="/admin/ingest" className={navClass('/admin/ingest')} onClick={closeNav}>
                <IngestIcon />
                Salesforce Log
              </Link>
              <Link to="/admin/recon" className={navClass('/admin/recon')} onClick={closeNav}>
                <ReconIcon />
                Salesforce Recon
              </Link>
              {SHOW_PENDING_APPROVAL_NAV && (
                <Link to="/admin/salesforce-reports" className={navClass('/admin/salesforce-reports')} onClick={closeNav}>
                  <SalesforceReportsIcon />
                  Salesforce Reports
                </Link>
              )}
              <Link to="/admin/whatsapp" className={navClass('/admin/whatsapp')} onClick={closeNav}>
                <WhatsAppIcon />
                WhatsApp
              </Link>
              <Link to="/admin/usage" className={navClass('/admin/usage')} onClick={closeNav}>
                <UsageIcon />
                Portal Usage
              </Link>
            </>
          )}
          <Link to="/admin/docs" className={navClass('/admin/docs')} onClick={closeNav}>
            <HelpIcon />
            Documentation
          </Link>
        </nav>

        <div className="admin-sidebar-footer">
          <span className="admin-user-email"><UserCircleIcon /> {user?.email}</span>
          <button className="admin-signout-btn" onClick={() => void signOut()}><ExitIcon /> Sign out</button>
          <Link to="/" className="admin-btn admin-btn--primary" style={{ textDecoration: 'none', textAlign: 'center' }}>Back to portal</Link>
        </div>
      </aside>

      {sidebarOpen && (
        <div className="admin-sidebar-backdrop" onClick={closeNav} />
      )}

      <main className="admin-main">
        <div className="admin-mobile-header">
          <button className="admin-hamburger" onClick={() => setSidebarOpen(true)} aria-label="Open menu">
            <span /><span /><span />
          </button>
          <img src="/images/shf-logo-horizontal.jpg" alt="SHF Agriculture" className="admin-mobile-logo" />
          <span className="admin-sidebar-label">Admin</span>
        </div>
        <Outlet />
      </main>
    </div>
  )
}

function UserCircleIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 20 20" fill="none" style={{ flexShrink: 0 }}>
      <circle cx="10" cy="10" r="8" stroke="currentColor" strokeWidth="1.7" />
      <circle cx="10" cy="8" r="3" stroke="currentColor" strokeWidth="1.5" />
      <path d="M4 16.5c0-2.5 2.686-4.5 6-4.5s6 2 6 4.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  )
}

function ExitIcon() {
  return (
    <svg width="14" height="14" viewBox="0 0 20 20" fill="none" style={{ flexShrink: 0 }}>
      <path d="M8 3H4a1 1 0 00-1 1v12a1 1 0 001 1h4" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
      <path d="M13 14l3-4-3-4" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M16 10H8" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
    </svg>
  )
}

function OverviewIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
      <rect x="2" y="2" width="7" height="7" rx="1.5" stroke="currentColor" strokeWidth="1.7" />
      <rect x="11" y="2" width="7" height="7" rx="1.5" stroke="currentColor" strokeWidth="1.7" />
      <rect x="2" y="11" width="7" height="7" rx="1.5" stroke="currentColor" strokeWidth="1.7" />
      <rect x="11" y="11" width="7" height="7" rx="1.5" stroke="currentColor" strokeWidth="1.7" />
    </svg>
  )
}

function IngestIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
      <path d="M10 3v10M10 13l-3-3M10 13l3-3" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
      <path d="M3 15h14" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
    </svg>
  )
}

function KpiIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
      <path d="M4 14l4-4 3 3 5-6" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
      <rect x="2" y="2" width="16" height="16" rx="2" stroke="currentColor" strokeWidth="1.5" />
    </svg>
  )
}

function UsersIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
      <circle cx="8" cy="7" r="3" stroke="currentColor" strokeWidth="1.7" />
      <path d="M2 17c0-3.314 2.686-6 6-6s6 2.686 6 6" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
      <path d="M14 4a3 3 0 010 6M17 17c0-2.21-1.343-4.1-3.25-5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
    </svg>
  )
}


function WhatsAppIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
      <path d="M10 2a8 8 0 016.32 12.9L17.5 18l-3.22-1.14A8 8 0 1110 2z" stroke="currentColor" strokeWidth="1.7" strokeLinejoin="round" />
      <path d="M7.5 8.5c.3.9.9 1.8 1.8 2.5s1.7 1.1 2.5 1.2c.1 0 .3-.1.5-.4l.3-.5c.1-.2.1-.4 0-.5l-.8-.7c-.2-.2-.4-.2-.6-.1l-.3.2c-.3-.5-.7-1-.9-1.5l.2-.3c.1-.2.1-.4 0-.6l-.7-.8c-.1-.2-.3-.2-.5-.1l-.5.3c-.3.3-.4.5-.3.6z" stroke="currentColor" strokeWidth="1.2" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

function UsageIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
      <path d="M3 17V9M9 17V4M15 17v-6" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
      <path d="M2 17h16" stroke="currentColor" strokeWidth="1.7" strokeLinecap="round" />
    </svg>
  )
}

function CoverageIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
      <rect x="2" y="2" width="7" height="7" rx="1" stroke="currentColor" strokeWidth="1.7" />
      <rect x="11" y="2" width="7" height="7" rx="1" stroke="currentColor" strokeWidth="1.7" />
      <rect x="2" y="11" width="7" height="7" rx="1" stroke="currentColor" strokeWidth="1.7" />
      <rect x="11" y="11" width="7" height="7" rx="1" fill="currentColor" opacity="0.25" stroke="currentColor" strokeWidth="1.7" />
      <path d="M12.5 14.5l1.5 1.5 2.5-2.5" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

function ReconIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
      <rect x="2" y="2" width="7" height="7" rx="1" stroke="currentColor" strokeWidth="1.7" />
      <rect x="11" y="2" width="7" height="7" rx="1" stroke="currentColor" strokeWidth="1.7" />
      <rect x="2" y="11" width="7" height="7" rx="1" stroke="currentColor" strokeWidth="1.7" />
      <rect x="11" y="11" width="7" height="7" rx="1" stroke="currentColor" strokeWidth="1.7" />
      <path d="M12.5 14.5l1.5 1.5 3-3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}

function SalesforceReportsIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
      <rect x="2" y="3" width="16" height="14" rx="1.5" stroke="currentColor" strokeWidth="1.7" />
      <path d="M2 8h16M7 8v9" stroke="currentColor" strokeWidth="1.5" />
    </svg>
  )
}

function DashletsIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
      <rect x="2" y="2" width="7" height="7" rx="1.5" stroke="currentColor" strokeWidth="1.7" />
      <rect x="11" y="2" width="7" height="7" rx="1.5" stroke="currentColor" strokeWidth="1.7" />
      <path d="M2.5 14h6M5.5 11v6" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" />
      <path d="M12 13.5l1.5 1.5 3-3" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
      <rect x="11" y="11" width="7" height="7" rx="1.5" stroke="currentColor" strokeWidth="1.7" />
    </svg>
  )
}

function DashletCommentIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
      <path d="M2.5 4.5A1.5 1.5 0 0 1 4 3h12a1.5 1.5 0 0 1 1.5 1.5v8A1.5 1.5 0 0 1 16 14H8l-3.5 3v-3H4a1.5 1.5 0 0 1-1.5-1.5v-8Z" stroke="currentColor" strokeWidth="1.7" strokeLinejoin="round" />
    </svg>
  )
}

function HelpIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
      <circle cx="10" cy="10" r="8" stroke="currentColor" strokeWidth="1.7" />
      <path d="M7.6 7.8a2.4 2.4 0 114.15 1.65c-.55.5-1.15.85-1.15 1.85" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
      <circle cx="10" cy="14.2" r="0.9" fill="currentColor" />
    </svg>
  )
}

function RolesIcon() {
  return (
    <svg width="16" height="16" viewBox="0 0 20 20" fill="none">
      <path d="M10 2l2.5 2H17v5c0 3.5-3 6-7 7-4-1-7-3.5-7-7V4h4.5L10 2z" stroke="currentColor" strokeWidth="1.7" strokeLinejoin="round" />
      <path d="M7 10l2 2 4-4" stroke="currentColor" strokeWidth="1.5" strokeLinecap="round" strokeLinejoin="round" />
    </svg>
  )
}
