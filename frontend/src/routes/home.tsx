import { Link } from '@tanstack/react-router'
import { useAuth } from '@/contexts/AuthContext'

export function HomePage() {
  const { hasPermission } = useAuth()
  return (
    <div className="body-layout">
      <div className="main-content">
        <div className="landing-section">
          <div className="landing-hero">
            <div className="landing-hero-text">
              <div className="landing-hero-tag">Impact Overview</div>
              <h2 className="landing-hero-title">SHF Agriculture Impact Dashboard</h2>
              <p className="landing-hero-desc">
                Explore programme data across girls' education, livelihoods &amp; leadership,
                and education systems — filtered by country, year, and sub-level.
              </p>
            </div>
            <div className="landing-hero-img-wrap">
              <img src="/images/shf-logo-horizontal.jpg" alt="SHF Agriculture" className="landing-hero-img" />
            </div>
          </div>

          <div className="landing-cards">
            {hasPermission('page:dashboard') && (
              <Link
                to="/dashboard"
                search={{ level: undefined, subLevel: undefined, countries: undefined, startYear: undefined, endYear: undefined }}
                className="landing-card"
              >
                <div className="landing-card-icon">
                  <svg viewBox="0 0 20 20" fill="none">
                    <rect x="2" y="10" width="4" height="8" rx="1" stroke="white" strokeWidth="1.7" />
                    <rect x="8" y="6" width="4" height="12" rx="1" stroke="white" strokeWidth="1.7" />
                    <rect x="14" y="2" width="4" height="16" rx="1" stroke="white" strokeWidth="1.7" />
                  </svg>
                </div>
                <div className="landing-card-label">Data Dashboard</div>
                <div className="landing-card-title">Girls' Education, Livelihoods &amp; Systems</div>
                <div className="landing-card-desc">KPI-level programme data across three impact levels, filterable by country and year.</div>
              </Link>
            )}
            {hasPermission('page:dynamic') && (
              <Link to="/dynamic" className="landing-card">
                <div className="landing-card-icon">
                  <svg viewBox="0 0 20 20" fill="none">
                    <circle cx="10" cy="10" r="8" stroke="white" strokeWidth="1.7" />
                    <path d="M10 2c0 0-3 3-3 8s3 8 3 8M10 2c0 0 3 3 3 8s-3 8-3 8M2 10h16" stroke="white" strokeWidth="1.5" strokeLinecap="round" />
                  </svg>
                </div>
                <div className="landing-card-label">Dynamic Data</div>
                <div className="landing-card-title">District &amp; School Level Data</div>
                <div className="landing-card-desc">Drill down to district and school level with multi-select country, district, and school filters.</div>
              </Link>
            )}
{hasPermission('page:map') && (
              <Link to="/map" className="landing-card">
                <div className="landing-card-icon">
                  <svg viewBox="0 0 20 20" fill="none">
                    <path d="M7 2L2 4.5v13L7 15l6 3 5-2.5V2.5L13 5 7 2z" stroke="white" strokeWidth="1.6" strokeLinejoin="round" />
                    <path d="M7 2v13M13 5v13" stroke="white" strokeWidth="1.6" strokeLinecap="round" />
                  </svg>
                </div>
                <div className="landing-card-label">Data Map</div>
                <div className="landing-card-title">Interactive Geographic Map</div>
                <div className="landing-card-desc">Explore programme reach across countries, districts, and schools on an interactive map.</div>
              </Link>
            )}
          </div>

          <div className="landing-cards landing-cards--row2">
            {/* KPI Milestones and KPI Trends hidden on the demo deployment. Routes stay
                registered and reachable directly at /kpi-milestones and /kpi-trends.
            {hasPermission('page:kpi-milestones') && (
              <Link
                to="/kpi-milestones"
                search={{ year: undefined, group: undefined, indicator: undefined }}
                className="landing-card"
              >
                <div className="landing-card-icon">
                  <svg viewBox="0 0 20 20" fill="none">
                    <path d="M3 17V9M8 17V5M13 17v-9M17 3l-6.5 6.5" stroke="white" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                </div>
                <div className="landing-card-label">KPI Milestones</div>
                <div className="landing-card-title">Annual Targets &amp; Progress</div>
                <div className="landing-card-desc">Track KPI performance against yearly milestones by indicator group.</div>
              </Link>
            )}
            {hasPermission('page:kpi-trends') && (
              <Link
                to="/kpi-trends"
                search={{ country: undefined, group: undefined, indicator: undefined }}
                className="landing-card"
              >
                <div className="landing-card-icon">
                  <svg viewBox="0 0 20 20" fill="none">
                    <path d="M2 15l5-6 4 3 6-7" stroke="white" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
                    <path d="M13 5h4v4" stroke="white" strokeWidth="1.7" strokeLinecap="round" strokeLinejoin="round" />
                  </svg>
                </div>
                <div className="landing-card-label">KPI Trends</div>
                <div className="landing-card-title">Multi-Year Indicator Trends</div>
                <div className="landing-card-desc">Visualize how KPIs move over time by country and indicator.</div>
              </Link>
            )}
            */}
            {hasPermission('page:kpi-report') && (
              <Link
                to="/kpi-report"
                search={{ country: undefined, year: undefined, group: undefined }}
                className="landing-card"
              >
                <div className="landing-card-icon">
                  <svg viewBox="0 0 20 20" fill="none">
                    <rect x="3" y="3" width="14" height="14" rx="2" stroke="white" strokeWidth="1.7" />
                    <path d="M6.5 10h7M6.5 13.5h4.5M6.5 6.5h7" stroke="white" strokeWidth="1.5" strokeLinecap="round" />
                  </svg>
                </div>
                <div className="landing-card-label">KPI Report</div>
                <div className="landing-card-title">Detailed KPI Breakdown</div>
                <div className="landing-card-desc">Browse KPI values by country, year, and group in report form.</div>
              </Link>
            )}
          </div>
        </div>
      </div>
    </div>
  )
}

