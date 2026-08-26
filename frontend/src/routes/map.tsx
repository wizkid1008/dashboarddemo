// @ts-nocheck
import { useEffect, useRef, useState } from 'react'
import { FilterSection } from '@/components/FilterSection'
import { supabase } from '@/lib/supabase'
import { useAuth } from '@/contexts/AuthContext'

const WAREHOUSE_URL = import.meta.env.VITE_WAREHOUSE_SUPABASE_URL as string
const WAREHOUSE_KEY = import.meta.env.VITE_WAREHOUSE_SUPABASE_KEY as string

async function portalRpc(fnName: string) {
  const { data: { session } } = await supabase.auth.getSession()
  const token = session?.access_token ?? WAREHOUSE_KEY
  const response = await fetch(`${WAREHOUSE_URL}/rest/v1/rpc/${fnName}`, {
    method: 'POST',
    headers: {
      apikey:            WAREHOUSE_KEY,
      Authorization:     `Bearer ${token}`,
      'Content-Type':    'application/json',
      'Content-Profile': 'rep_portal',
    },
    body: '{}',
  })
  if (!response.ok) {
    const text = await response.text()
    throw new Error(`${fnName} failed: ${response.status} — ${text}`)
  }
  return response.json()
}

// ── Constants ─────────────────────────────────────────────────────────────────

// Boundary GeoJSON lives in a public Supabase Storage bucket named MapShapes. The base URL is
// configurable so a demo deployment can serve shapes from its own project instead of the
// production warehouse; it falls back to the production bucket when the env var is unset.
const MAP_SHAPES_BASE_URL =
  (import.meta.env.VITE_MAP_SHAPES_BASE_URL as string | undefined) ||
  'https://qlvayqyihfixikfqfelu.supabase.co/storage/v1/object/public/MapShapes'

const SUPABASE_STORAGE_ADM0_OPTIMIZED_URL = `${MAP_SHAPES_BASE_URL}/africa_adm0_simplified.geojson`
const SUPABASE_STORAGE_ADM2_OPTIMIZED_URL = `${MAP_SHAPES_BASE_URL}/priority_adm2_v2.geojson`
const SUPABASE_STORAGE_ADM0_URL = `${MAP_SHAPES_BASE_URL}/geoBoundariesCGAZ_ADM0.geojson`
const SUPABASE_STORAGE_ADM2_URL = `${MAP_SHAPES_BASE_URL}/geoBoundariesCGAZ_ADM2.geojson`

const PRIORITY_COUNTRIES = ['tanzania', 'ghana', 'malawi', 'zambia', 'zimbabwe', 'kenya']
const YEARS = Array.from({ length: 11 }, (_, i) => 2020 + i)

// currentDataYear holds the most recent year that has actual data values in the loaded
// dataset. It is set after Supabase data loads via computeLatestDataYear() and replaces
// the user-controlled year range that was previously driven by the slider UI.
// Default is the last year in YEARS; it will be overwritten once real data arrives.
let currentDataYear = String(YEARS[YEARS.length - 1])

// The map now shows a single KPI: SHFs Supported in School with Education Bursaries.
// All other KPIs have been removed — the metric selector is kept in the UI but has
// only this one option so the map always displays bursary data.
// The underlying Supabase key (education_bursaries_children) is unchanged; only the
// display label has been updated from "Children…" to "SHFs…" to match CAMFED reporting.
// permissionKey retained from the remote branch — it gates visibility via the role system.
// Keys must match the jsonb_build_object keys in get_district_kpi_data() and get_school_point_data().
const KPI_DEFINITIONS = [
  { key: 'education_bursaries_children', label: 'SHFs Supported in School with Education Bursaries', permissionKey: 'dd:children_supported' },
]

const SCHOOL_LEVEL_METRICS = new Set([
  'education_bursaries_children',
  'active_learner_guides',
  'clients_by_form',
  'clients_by_form_girls',
  'clients_by_form_boys',
  'active_partner_schools',
  'active_guides_by_type',
  'cama_members',
  'active_guides_transition',
  'active_guides_agriculture',
  'active_guides_business',
])

const AFRICA_ISO3_CODES = [
  'DZA','AGO','BEN','BWA','BFA','BDI','CPV','CMR','CAF','TCD','COM','COG','COD','CIV',
  'DJI','EGY','GNQ','ERI','SWZ','ETH','GAB','GMB','GHA','GIN','GNB','KEN','LSO','LBR',
  'LBY','MDG','MWI','MLI','MRT','MUS','MAR','MOZ','NAM','NER','NGA','RWA','STP','SEN',
  'SYC','SLE','SOM','ZAF','SSD','SDN','TZA','TGO','TUN','UGA','ZMB','ZWE',
]

const ISO3_TO_COUNTRY: Record<string, { slug: string; name: string }> = {
  DZA:{slug:'algeria',name:'Algeria'},AGO:{slug:'angola',name:'Angola'},BEN:{slug:'benin',name:'Benin'},
  BWA:{slug:'botswana',name:'Botswana'},BFA:{slug:'burkina-faso',name:'Burkina Faso'},BDI:{slug:'burundi',name:'Burundi'},
  CPV:{slug:'cabo-verde',name:'Cabo Verde'},CMR:{slug:'cameroon',name:'Cameroon'},CAF:{slug:'central-african-republic',name:'Central African Republic'},
  TCD:{slug:'chad',name:'Chad'},COM:{slug:'comoros',name:'Comoros'},COG:{slug:'congo',name:'Republic of the Congo'},
  COD:{slug:'dr-congo',name:'Democratic Republic of the Congo'},CIV:{slug:'cote-divoire',name:"Cote d'Ivoire"},
  DJI:{slug:'djibouti',name:'Djibouti'},EGY:{slug:'egypt',name:'Egypt'},GNQ:{slug:'equatorial-guinea',name:'Equatorial Guinea'},
  ERI:{slug:'eritrea',name:'Eritrea'},SWZ:{slug:'eswatini',name:'Eswatini'},ETH:{slug:'ethiopia',name:'Ethiopia'},
  GAB:{slug:'gabon',name:'Gabon'},GMB:{slug:'gambia',name:'The Gambia'},TZA:{slug:'tanzania',name:'Tanzania'},
  GHA:{slug:'ghana',name:'Ghana'},GIN:{slug:'guinea',name:'Guinea'},GNB:{slug:'guinea-bissau',name:'Guinea-Bissau'},
  KEN:{slug:'kenya',name:'Kenya'},LSO:{slug:'lesotho',name:'Lesotho'},LBR:{slug:'liberia',name:'Liberia'},
  LBY:{slug:'libya',name:'Libya'},MDG:{slug:'madagascar',name:'Madagascar'},MWI:{slug:'malawi',name:'Malawi'},
  MLI:{slug:'mali',name:'Mali'},MRT:{slug:'mauritania',name:'Mauritania'},MUS:{slug:'mauritius',name:'Mauritius'},
  MAR:{slug:'morocco',name:'Morocco'},MOZ:{slug:'mozambique',name:'Mozambique'},NAM:{slug:'namibia',name:'Namibia'},
  NER:{slug:'niger',name:'Niger'},NGA:{slug:'nigeria',name:'Nigeria'},RWA:{slug:'rwanda',name:'Rwanda'},
  STP:{slug:'sao-tome-and-principe',name:'Sao Tome and Principe'},SEN:{slug:'senegal',name:'Senegal'},
  SYC:{slug:'seychelles',name:'Seychelles'},SLE:{slug:'sierra-leone',name:'Sierra Leone'},SOM:{slug:'somalia',name:'Somalia'},
  ZAF:{slug:'south-africa',name:'South Africa'},SSD:{slug:'south-sudan',name:'South Sudan'},SDN:{slug:'sudan',name:'Sudan'},
  TGO:{slug:'togo',name:'Togo'},TUN:{slug:'tunisia',name:'Tunisia'},UGA:{slug:'uganda',name:'Uganda'},
  ZMB:{slug:'zambia',name:'Zambia'},ZWE:{slug:'zimbabwe',name:'Zimbabwe'},
}

const LEVEL_ZERO_COLOR = '#ffffff'
const LEVEL_COLORS = ['#662f6c', '#d69929', '#de4826', '#5e98bd', '#4a783b']

// ── Module-level pure functions ───────────────────────────────────────────────

async function fetchGeojsonWithFallback(primaryUrl: string, fallbackUrl: string) {
  const r = await fetch(primaryUrl)
  if (r.ok) return r.json()
  console.warn(`Optimized GeoJSON unavailable, falling back to ${fallbackUrl}`)
  const r2 = await fetch(fallbackUrl)
  if (!r2.ok) throw new Error(`Could not load ${primaryUrl} or ${fallbackUrl}`)
  return r2.json()
}

function normalizeStorageFeature(feature: any) {
  const country = ISO3_TO_COUNTRY[feature.properties.shapeGroup]
  const shapeType = feature.properties.shapeType || 'ADM'
  return {
    id: feature.properties.shapeID,
    country_slug: country.slug,
    country_name: country.name,
    district_name: feature.properties.shapeName,
    boundary_level: shapeType,
    program_count: 0,
    beneficiary_count: 0,
    risk_score: 0,
    geometry: feature.geometry,
    kpis: {} as Record<string, any>,
  }
}


function normalizeSupabaseSchool(row: any) {
  return {
    ...row,
    school_id: String(row.school_id),
    latitude: Number(row.latitude),
    longitude: Number(row.longitude),
    kpis: normalizeKpis(row.kpis),
  }
}

function normalizeKpis(kpis: any) {
  if (!kpis) return {}
  return typeof kpis === 'string' ? JSON.parse(kpis) : kpis
}

function getDistrictKey(district: any) {
  return `${district.country_slug}::${district.district_name}`.toLowerCase()
}

function getNormalizedDistrictName(name: string) {
  return String(name || '').toLowerCase()
    .replace(/&/g, ' and ')
    .replace(/[^a-z0-9]+/g, ' ')
    .replace(/\b(district|municipal|municipality|metropolitan|metro|city|town|council|province|region)\b/g, ' ')
    .replace(/\s+/g, ' ').trim()
}

function isDistrictNameMatch(leftName: string, rightName: string) {
  const left = getNormalizedDistrictName(leftName)
  const right = getNormalizedDistrictName(rightName)
  if (!left || !right) return false
  return left === right || left.includes(right) || right.includes(left)
}

function isPointInGeometry(point: [number, number], geometry: any): boolean {
  if (!geometry) return false
  if (geometry.type === 'Polygon') return isPointInPolygon(point, geometry.coordinates)
  if (geometry.type === 'MultiPolygon') return geometry.coordinates.some((p: any) => isPointInPolygon(point, p))
  return false
}

function isPointInPolygon(point: [number, number], rings: any[]): boolean {
  if (!rings?.length || !isPointInRing(point, rings[0])) return false
  return !rings.slice(1).some((ring) => isPointInRing(point, ring))
}

function isPointInRing([x, y]: [number, number], ring: [number, number][]): boolean {
  let inside = false
  for (let i = 0, j = ring.length - 1; i < ring.length; j = i++) {
    const [xi, yi] = ring[i]; const [xj, yj] = ring[j]
    const intersects = yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi
    if (intersects) inside = !inside
  }
  return inside
}

function isPriorityCountry(district: any) {
  return PRIORITY_COUNTRIES.includes(district.country_slug)
}

function getMergedKpiValues(district: any, kpisByDistrict: Map<string, any>) {
  const row = kpisByDistrict.get(getDistrictKey(district))
  if (!row) return { program_count: 0, beneficiary_count: 0, risk_score: 0, kpis: {} }
  return {
    program_count: Number(row.program_count || 0),
    beneficiary_count: Number(row.beneficiary_count || 0),
    risk_score: Number(row.risk_score || 0),
    kpis: row.kpis || {},
  }
}

function indexKpiRows(rows: any[]) {
  const index = new Map<string, any>()
  rows.forEach((row) => index.set(getDistrictKey(row), row))
  return index
}

function aggregateDistrictsToCountries(districts: any[]) {
  const countries = new Map<string, any>()
  districts.filter(isPriorityCountry).forEach((district) => {
    const current = countries.get(district.country_slug) || {
      country_slug: district.country_slug, country_name: district.country_name,
      district_name: district.country_name, boundary_level: 'ADM0',
      program_count: 0, beneficiary_count: 0, risk_score_total: 0, risk_score_count: 0,
      kpis: { years: {} },
    }
    current.program_count += Number(district.program_count || 0)
    current.beneficiary_count += Number(district.beneficiary_count || 0)
    current.risk_score_total += Number(district.risk_score || 0)
    current.risk_score_count += 1
    KPI_DEFINITIONS.forEach((kpi) => {
      const flatValue = district.kpis?.[kpi.key]
      if (flatValue !== undefined) {
        current.kpis[kpi.key] = Number(current.kpis[kpi.key] || 0) + Number(flatValue || 0)
      }
      YEARS.forEach((year) => {
        const yearKey = String(year)
        const value = getRawDistrictMetric(district, kpi.key, yearKey, { yearlyOnly: true })
        if (value === undefined || value === null) return
        current.kpis.years[yearKey] ||= {}
        current.kpis.years[yearKey][kpi.key] = Number(current.kpis.years[yearKey][kpi.key] || 0) + Number(value || 0)
      })
    })
    countries.set(district.country_slug, current)
  })
  return new Map(Array.from(countries.entries()).map(([slug, c]) => [slug, {
    ...c,
    risk_score: c.risk_score_count > 0 ? c.risk_score_total / c.risk_score_count : 0,
  }]))
}

function getCountryNameFromSlug(slug: string) {
  return Object.values(ISO3_TO_COUNTRY).find((c) => c.slug === slug)?.name || slug
}

function formatNumber(value: any) {
  return new Intl.NumberFormat().format(Number(value || 0))
}

function formatMetric(value: any, metric: string) {
  if (metric === 'risk_score') return Number(value || 0).toFixed(1)
  return formatNumber(value)
}

function formatRoundedLegendNumber(value: number) {
  const n = Number(value || 0)
  if (n < 50)   return formatNumber(Math.round(n))
  if (n < 500)  return formatNumber(Math.round(n / 10) * 10)
  if (n < 5000) return formatNumber(Math.round(n / 100) * 100)
  return formatNumber(Math.round(n / 1000) * 1000)
}

function getLegendRangeLabel(start: number, end: number, level: number) {
  const rs = formatRoundedLegendNumber(start)
  const re = formatRoundedLegendNumber(end)
  return level === 1 ? `0 - <=${re}` : `>${rs} - <=${re}`
}

function formatButtonText(selected: number, total: number, label: string) {
  if (total === 0 || selected === 0) return `No ${label}`
  if (selected === total) return `All ${label}`
  if (selected === 1) return `1 ${label.slice(0, -1)}`
  return `${selected} of ${total}`
}

function escapeHtml(value: any) {
  return String(value).replace(/[&<>"']/g, (c) =>
    ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#039;' }[c] ?? c)
  )
}

function getRawDistrictMetric(district: any, metric: string, year: string, options: { yearlyOnly?: boolean } = {}) {
  if (!district.kpis) return district[metric]
  if (district.kpis.years && district.kpis.years[year]?.[metric] !== undefined) return district.kpis.years[year][metric]
  if (district.kpis[year] && district.kpis[year][metric] !== undefined) return district.kpis[year][metric]
  if (options.yearlyOnly) return undefined
  if (Object.hasOwn(district.kpis, metric)) return district.kpis[metric]
  return district[metric]
}

function getMetricLevel(value: number, max: number) {
  if (max <= 0) return 1
  const r = value / max
  if (r < 0.2) return 1
  if (r < 0.4) return 2
  if (r < 0.6) return 3
  if (r < 0.8) return 4
  return 5
}

function renderCheckboxRow({ type, value, label, meta = '', checked }: {
  type: string; value: string; label: string; meta?: string; checked: boolean
}) {
  return `
    <label class="check-row">
      <input type="checkbox" data-type="${type}" value="${escapeHtml(value)}" ${checked ? 'checked' : ''} />
      <span>
        ${escapeHtml(label)}
        ${meta ? `<small>${escapeHtml(meta)}</small>` : ''}
      </span>
    </label>
  `
}

function renderInspectorRows(rows: [string, string][]) {
  return rows.map(([label, value]) => `<dt>${escapeHtml(label)}</dt><dd>${escapeHtml(value)}</dd>`).join('')
}

// ── Fallback sample data (shown when Supabase is unavailable) ─────────────────

const sampleDistricts: any[] = [
  {
    id:'tz-arusha', country_slug:'tanzania', country_name:'Tanzania', district_name:'Arusha',
    boundary_level:'ADM2', program_count:18, beneficiary_count:12400, risk_score:34,
    kpis:{ education_bursaries_children:34004, active_learner_guides:260, clients_by_form:39735,
           clients_by_form_girls:21500, clients_by_form_boys:18235, active_partner_schools:210,
           women_supported_tertiary:480, grants_disbursed:142000, cama_members:11800 },
    geometry:{ type:'Polygon', coordinates:[[[36.25,-3.05],[37.35,-3.05],[37.35,-3.85],[36.25,-3.85],[36.25,-3.05]]] },
  },
  {
    id:'gh-tamale', country_slug:'ghana', country_name:'Ghana', district_name:'Tamale',
    boundary_level:'ADM2', program_count:12, beneficiary_count:8100, risk_score:28,
    kpis:{ education_bursaries_children:4986, active_learner_guides:75, clients_by_form:12460,
           clients_by_form_girls:7600, clients_by_form_boys:4860, active_partner_schools:62,
           women_supported_tertiary:110, grants_disbursed:42000, cama_members:4200 },
    geometry:{ type:'Polygon', coordinates:[[[-1.25,9.75],[-0.45,9.75],[-0.45,9.15],[-1.25,9.15],[-1.25,9.75]]] },
  },
  {
    id:'mw-lilongwe', country_slug:'malawi', country_name:'Malawi', district_name:'Lilongwe',
    boundary_level:'ADM2', program_count:21, beneficiary_count:16300, risk_score:42,
    kpis:{ education_bursaries_children:15506, active_learner_guides:180, clients_by_form:34049,
           clients_by_form_girls:18600, clients_by_form_boys:15449, active_partner_schools:140,
           women_supported_tertiary:320, grants_disbursed:98000, cama_members:9200 },
    geometry:{ type:'Polygon', coordinates:[[[33.35,-13.55],[34.2,-13.55],[34.2,-14.25],[33.35,-14.25],[33.35,-13.55]]] },
  },
  {
    id:'zm-lusaka', country_slug:'zambia', country_name:'Zambia', district_name:'Lusaka',
    boundary_level:'ADM2', program_count:15, beneficiary_count:9800, risk_score:38,
    kpis:{ education_bursaries_children:28266, active_learner_guides:230, clients_by_form:18792,
           clients_by_form_girls:9900, clients_by_form_boys:8892, active_partner_schools:175,
           women_supported_tertiary:260, grants_disbursed:79000, cama_members:7600 },
    geometry:{ type:'Polygon', coordinates:[[[28.0,-15.15],[28.75,-15.15],[28.75,-15.8],[28.0,-15.8],[28.0,-15.15]]] },
  },
  {
    id:'zw-harare', country_slug:'zimbabwe', country_name:'Zimbabwe', district_name:'Harare',
    boundary_level:'ADM2', program_count:9, beneficiary_count:6900, risk_score:47,
    kpis:{ education_bursaries_children:12966, active_learner_guides:135, clients_by_form:31754,
           clients_by_form_girls:16800, clients_by_form_boys:14954, active_partner_schools:115,
           women_supported_tertiary:210, grants_disbursed:64000, cama_members:6900 },
    geometry:{ type:'Polygon', coordinates:[[[30.65,-17.55],[31.45,-17.55],[31.45,-18.1],[30.65,-18.1],[30.65,-17.55]]] },
  },
]

// ── Component ─────────────────────────────────────────────────────────────────

export function MapPage() {
  const { hasPermission, permissionsLoaded } = useAuth()
  if (!permissionsLoaded) {
    return (
      <div className="body-layout">
        <div className="main-content">
          <p style={{ padding: '20px 0', color: 'var(--text-mid)' }}>Loading…</p>
        </div>
      </div>
    )
  }
  if (!hasPermission('page:map')) {
    return (
      <div className="body-layout">
        <div className="main-content">
          <div style={{ padding: '40px 0', textAlign: 'center' }}>
            <h2 style={{ fontWeight: 600, marginBottom: 8 }}>Access Denied</h2>
            <p style={{ color: 'var(--text-mid)' }}>You do not have permission to view this page.</p>
          </div>
        </div>
      </div>
    )
  }
  return <MapContent />
}

function MapContent() {
  const { hasPermission } = useAuth()
  const hasPermissionRef = useRef(hasPermission)
  const mapContainerRef = useRef<HTMLDivElement>(null)
  const [showHowTo, setShowHowTo] = useState(true)

  useEffect(() => { hasPermissionRef.current = hasPermission }, [hasPermission])

  useEffect(() => {
    const mapEl = mapContainerRef.current
    if (!mapEl) return

    let cancelled = false

    // ── Mutable state ─────────────────────────────────────────────────────────
    let allDistricts: any[] = []
    let allSchools: any[] = []
    let boundaryLayer: L.GeoJSON | null = null
    let schoolLayer: L.GeoJSON | null = null
    let countryOptions: { slug: string; name: string }[] = []
    let districtOptions: { key: string; name: string; countrySlug: string; countryName: string }[] = []
    let schoolOptions: { id: string; name: string; districtName: string; countryName: string }[] = []
    let selectedCountries = new Set<string>()
    let selectedDistricts = new Set<string>()
    let selectedSchools = new Set<string>()
    let districtSelectionMode = 'all'
    let schoolSelectionMode = 'all'
    let loadedKpiRowCount = 0
    let loadedSchoolRowCount = 0

    // ── DOM refs ──────────────────────────────────────────────────────────────
    const $ = <T extends HTMLElement>(id: string) => document.getElementById(id) as T
    const countrySearch     = $<HTMLInputElement>('countrySearch')
    const countryMenu       = $<HTMLElement>('countryMenu')
    const countryButtonText = $<HTMLElement>('countryButtonText')
    const countryList       = $<HTMLElement>('countryList')
    const countryAll        = $<HTMLButtonElement>('countryAll')
    const countryNone       = $<HTMLButtonElement>('countryNone')
    const districtSearch    = $<HTMLInputElement>('districtSearch')
    const districtMenu      = $<HTMLElement>('districtMenu')
    const districtButtonText = $<HTMLElement>('districtButtonText')
    const districtList      = $<HTMLElement>('districtList')
    const districtAll       = $<HTMLButtonElement>('districtAll')
    const districtNone      = $<HTMLButtonElement>('districtNone')
    const schoolSearch      = $<HTMLInputElement>('schoolSearch')
    const schoolMenu        = $<HTMLElement>('schoolMenu')
    const schoolButtonText  = $<HTMLElement>('schoolButtonText')
    const schoolList        = $<HTMLElement>('schoolList')
    const schoolAll         = $<HTMLButtonElement>('schoolAll')
    const schoolNone        = $<HTMLButtonElement>('schoolNone')
    const metricSelect      = $<HTMLSelectElement>('metricSelect')
    // yearStart, yearEnd, and yearRangeText refs removed — the year-range slider was
    // taken out of the filter bar. Year is now fixed to the most current data year.
    const countryLayerToggle  = $<HTMLInputElement>('countryLayerToggle')
    const districtLayerToggle = $<HTMLInputElement>('districtLayerToggle')
    const schoolLayerToggle   = $<HTMLInputElement>('schoolLayerToggle')
    const statusText        = $<HTMLElement>('statusText')
    const chartTitle        = $<HTMLElement>('chartTitle')
    const chartMetricLabel  = $<HTMLElement>('chartMetricLabel')
    const countryChart      = $<HTMLElement>('countryChart')
    const mapEmpty          = $<HTMLElement>('mapEmpty')
    const legendTitle       = $<HTMLElement>('legendTitle')
    const legendSubtitle    = $<HTMLElement>('legendSubtitle')
    const legendRows        = $<HTMLElement>('legendRows')
    const inspectorType     = $<HTMLElement>('inspectorType')
    const inspectorTitle    = $<HTMLElement>('inspectorTitle')
    const inspectorDetails  = $<HTMLElement>('inspectorDetails')
    const countryToggle     = $<HTMLButtonElement>('countryToggle')
    const districtToggle    = $<HTMLButtonElement>('districtToggle')
    const schoolToggle      = $<HTMLButtonElement>('schoolToggle')

    // ── Leaflet map ───────────────────────────────────────────────────────────
    const mapInstance = L.map(mapEl, { zoomControl: true, minZoom: 4, attributionControl: false }).setView([-8, 24], 4)

    // ── Helper functions ──────────────────────────────────────────────────────

    function setStatus(msg: string) { if (statusText) statusText.textContent = msg }

    function getActiveLayer() {
      if (schoolLayerToggle?.checked) return 'school'
      if (districtLayerToggle?.checked) return 'district'
      return 'country'
    }

    function getMetricLabel(metric: string) {
      return metricSelect?.querySelector(`option[value="${metric}"]`)?.textContent ?? metric
    }

    // getSelectedYears() previously read from the year-range slider in the filter bar.
    // The slider has been removed — the map now always shows the single most recent year
    // with data, stored in the module-level currentDataYear variable.
    function getSelectedYears() {
      return [currentDataYear]
    }

    // getYearRangeLabel() is used in popup tooltips and the inspector panel to label
    // the year being displayed. It now returns the single current year instead of a range.
    function getYearRangeLabel() {
      return currentDataYear
    }

    function getDistrictMetric(district: any, metric: string) {
      const selectedYears = getSelectedYears()
      const yearlyValues = selectedYears
        .map((y) => getRawDistrictMetric(district, metric, y, { yearlyOnly: true }))
        .filter((v) => v !== undefined && v !== null)
      if (yearlyValues.length > 0) return yearlyValues.reduce((t, v) => t + Number(v || 0), 0)
      const value = getRawDistrictMetric(district, metric, selectedYears[0], { yearlyOnly: false })
      return Number(value || 0)
    }

    function hasMetricData(district: any, metric: string) {
      if (!district) return false
      const hasYearValue = getSelectedYears().some((y) => {
        const v = getRawDistrictMetric(district, metric, y, { yearlyOnly: true })
        return v !== undefined && v !== null && v !== ''
      })
      if (hasYearValue) return true
      if (district.kpis && Object.hasOwn(district.kpis, metric)) return true
      return Object.hasOwn(district, metric)
    }

    function getMaxMetricValue(metric: string, districts: any[], boundaryLevel: string | null = null) {
      const comparable = getComparableMetricBoundaries(districts, metric, boundaryLevel)
      return Math.max(...comparable.map((d) => getDistrictMetric(d, metric)).filter(Number.isFinite), 0)
    }

    function getComparableMetricBoundaries(boundaries: any[], metric: string, boundaryLevel: string | null = null) {
      const priority = boundaries.filter((b) =>
        isPriorityCountry(b) && selectedCountries.has(b.country_slug) && hasMetricData(b, metric)
      )
      if (boundaryLevel) return priority.filter((b) => b.boundary_level === boundaryLevel)
      const districts = priority.filter((b) => b.boundary_level !== 'ADM0')
      return districts.length > 0 ? districts : priority.filter((b) => b.boundary_level === 'ADM0')
    }

    function colorForValue(value: number, metric: string, boundaryLevel: string | null = null) {
      const max = getMaxMetricValue(metric, allDistricts, boundaryLevel)
      if (max <= 0) return LEVEL_ZERO_COLOR
      return LEVEL_COLORS[getMetricLevel(value, max) - 1]
    }

    function isSchoolInSelectedDistricts(school: any) {
      if (districtSelectionMode === 'all') return true
      if (selectedDistricts.has(getDistrictKey(school))) return true
      return districtOptions.some((district) => {
        if (!selectedDistricts.has(district.key) || district.countrySlug !== school.country_slug) return false
        if (isDistrictNameMatch(district.name, school.district_name)) return true
        const boundary = allDistricts.find(
          (item) => item.boundary_level !== 'ADM0' && getDistrictKey(item) === district.key
        )
        return (
          boundary?.geometry &&
          Number.isFinite(school.latitude) && Number.isFinite(school.longitude) &&
          !(school.latitude === 0 && school.longitude === 0) &&
          school.geo_source !== 'invalid_nulled' &&
          school.geo_source !== 'regeocode_failed_manual_needed' &&
          isPointInGeometry([school.longitude, school.latitude], boundary.geometry)
        )
      })
    }

    function getVisibleBoundaryContext() {
      return allDistricts.filter((d) => {
        if (d.boundary_level === 'ADM0') return true
        if (getActiveLayer() === 'country') {
          // Show district outlines under the country layer for programme countries
          return isPriorityCountry(d) && selectedCountries.has(d.country_slug)
        }
        return isPriorityCountry(d) && selectedCountries.has(d.country_slug) && selectedDistricts.has(getDistrictKey(d))
      })
    }

    function getVisibleSchools() {
      return allSchools.filter((s) =>
        selectedCountries.has(s.country_slug) && isSchoolInSelectedDistricts(s) && selectedSchools.has(s.school_id)
      )
    }

    function getLegendMetricSource(boundaries: any[], schools: any[]) {
      const active = getActiveLayer()
      if (active === 'school') return schools
      return boundaries.filter((b) =>
        active === 'country' ? b.boundary_level === 'ADM0' : b.boundary_level !== 'ADM0'
      )
    }

    function updateMapEmptyState(count: number) {
      if (mapEmpty) mapEmpty.hidden = count > 0
    }

    function districtStyle(feature: any): L.PathOptions {
      const metric = metricSelect?.value ?? ''
      const props = feature.properties
      const isCountryCtx = props.boundary_level === 'ADM0'
      const priority = isPriorityCountry(props)
      const hasData = hasMetricData(props, metric)
      const isSelectedPrio = priority && selectedCountries.has(props.country_slug)
      const isLayerColored = isCountryCtx ? countryLayerToggle?.checked : districtLayerToggle?.checked
      const isDataLayer = isLayerColored && hasData && (
        isCountryCtx ? isSelectedPrio : priority && selectedDistricts.has(getDistrictKey(props))
      )
      const value = getDistrictMetric(props, metric)
      const isInteractive =
        (countryLayerToggle?.checked && isCountryCtx) || (districtLayerToggle?.checked && !isCountryCtx)

      // Programme countries with no data get a distinct purple tint
      const isProgrammeNoData = isCountryCtx && priority && isSelectedPrio && !hasData

      return {
        interactive: isInteractive,
        bubblingMouseEvents: false,
        color: isDataLayer ? '#4e2352' : isProgrammeNoData ? '#5a4a7a' : '#9A9AB0',
        weight: isCountryCtx ? (isDataLayer ? 1.2 : isProgrammeNoData ? 1.4 : 1) : isDataLayer ? 1.4 : 0.7,
        opacity: isCountryCtx ? (isDataLayer ? 0.8 : 0.7) : isDataLayer ? 0.92 : 0.45,
        fillColor: isDataLayer ? colorForValue(value, metric, props.boundary_level) : isProgrammeNoData ? '#b8a8d8' : LEVEL_ZERO_COLOR,
        fillOpacity: isCountryCtx ? (isDataLayer ? 0.66 : isProgrammeNoData ? 0.55 : 0.12) : isDataLayer ? 0.72 : 0.28,
      }
    }

    function getSchoolMarkerStyle(school: any, maxValue: number): L.CircleMarkerOptions {
      const metric = metricSelect?.value ?? ''
      const value = getDistrictMetric(school, metric)
      const hasData = hasMetricData(school, metric)
      const ratio = maxValue > 0 ? value / maxValue : 0
      return {
        interactive: true,
        bubblingMouseEvents: false,
        radius: 1 + ratio * 4,
        color: hasData ? '#4e2352' : '#9A9AB0',
        weight: hasData ? 1.4 : 1,
        opacity: hasData ? 0.92 : 0.65,
        fillColor: hasData && maxValue > 0 ? LEVEL_COLORS[getMetricLevel(value, maxValue) - 1] : LEVEL_ZERO_COLOR,
        fillOpacity: hasData ? 0.88 : 0.45,
        className: 'school-marker',
      }
    }

    function isDistrictHoverActive(district: any) {
      const active = getActiveLayer()
      const isCtry = district.boundary_level === 'ADM0'
      if (active === 'country') return isCtry && isPriorityCountry(district) && selectedCountries.has(district.country_slug)
      if (active === 'district') return !isCtry && isPriorityCountry(district) && selectedCountries.has(district.country_slug) && selectedDistricts.has(getDistrictKey(district))
      return false
    }

    function updateInspectorForDistrict(district: any) {
      const metric = metricSelect?.value ?? ''
      const value = getDistrictMetric(district, metric)
      if (inspectorType) inspectorType.textContent = district.boundary_level === 'ADM0' ? 'Country' : 'District'
      if (inspectorTitle) inspectorTitle.textContent =
        district.boundary_level === 'ADM0' ? district.country_name : `${district.district_name}, ${district.country_name}`
      const rows: [string, string][] = district.boundary_level === 'ADM0'
        ? [['Country', district.country_name], [getYearRangeLabel(), formatMetric(value, metric)], ['Programs', formatNumber(district.program_count)], ['Beneficiaries', formatNumber(district.beneficiary_count)]]
        : [['Country', district.country_name], ['District', district.district_name], [getYearRangeLabel(), formatMetric(value, metric)], ['Programs', formatNumber(district.program_count)], ['Beneficiaries', formatNumber(district.beneficiary_count)]]
      if (inspectorDetails) inspectorDetails.innerHTML = renderInspectorRows(rows)
    }

    function updateInspectorForSchool(school: any) {
      const metric = metricSelect?.value ?? ''
      const value = getDistrictMetric(school, metric)
      if (inspectorType) inspectorType.textContent = 'School'
      if (inspectorTitle) inspectorTitle.textContent = school.school_name
      if (inspectorDetails) inspectorDetails.innerHTML = renderInspectorRows([
        ['Country', school.country_name],
        ['District', school.district_name],
        ['Province', school.province || 'Not listed'],
        [getYearRangeLabel(), formatMetric(value, metric)],
        ['GPS Source', school.geo_source || 'GPS'],
      ])
    }

    function bindDistrictPopup(feature: any, layer: L.Layer) {
      const d = feature.properties
      const metric = metricSelect?.value ?? ''
      const value = getDistrictMetric(d, metric)
      ;(layer as L.Polygon).bindPopup(`
        <div class="district-popup">
          <strong>${escapeHtml(d.district_name)}, ${escapeHtml(d.country_name)}</strong>
          <dl>
            <dt>${escapeHtml(getMetricLabel(metric))}</dt><dd>${formatMetric(value, metric)}</dd>
            <dt>Programs</dt><dd>${formatNumber(d.program_count)}</dd>
            <dt>Beneficiaries</dt><dd>${formatNumber(d.beneficiary_count)}</dd>
          </dl>
        </div>
      `, { autoPan: false })
      const tooltipName = d.boundary_level === 'ADM0' ? d.country_name : d.district_name
      ;(layer as L.Polygon).bindTooltip(tooltipName, { sticky: true, direction: 'top', className: 'map-feature-tooltip' })
      ;(layer as L.Polygon).on({
        mouseover: (e: L.LeafletMouseEvent) => {
          if (!isDistrictHoverActive(d)) { (layer as L.Polygon).closeTooltip(); return }
          updateInspectorForDistrict(d)
          ;(layer as L.Polygon).openTooltip(e.latlng)
          if ((layer as any).bringToFront) (layer as any).bringToFront()
        },
        mousemove: (e: L.LeafletMouseEvent) => {
          if (isDistrictHoverActive(d)) (layer as L.Polygon).openTooltip(e.latlng)
        },
        mouseout: () => (layer as L.Polygon).closeTooltip(),
      })
    }

    function bindSchoolPopup(feature: any, layer: L.Layer) {
      const s = feature.properties
      const metric = metricSelect?.value ?? ''
      const value = getDistrictMetric(s, metric)
      ;(layer as L.CircleMarker).bindPopup(`
        <div class="district-popup">
          <strong>${escapeHtml(s.school_name)}</strong>
          <dl>
            <dt>District</dt><dd>${escapeHtml(s.district_name)}</dd>
            <dt>Country</dt><dd>${escapeHtml(s.country_name)}</dd>
            <dt>${escapeHtml(getMetricLabel(metric))}</dt><dd>${formatMetric(value, metric)}</dd>
            <dt>Location</dt><dd>${escapeHtml(s.geo_source || 'GPS')}</dd>
          </dl>
        </div>
      `, { autoPan: false })
      ;(layer as L.CircleMarker).bindTooltip(s.school_name || 'Unknown', { sticky: true, direction: 'top', className: 'map-feature-tooltip' })
      ;(layer as L.CircleMarker).on({
        mouseover: (e: L.LeafletMouseEvent) => {
          if (!schoolLayerToggle?.checked) { (layer as L.CircleMarker).closeTooltip(); return }
          updateInspectorForSchool(s)
          ;(layer as L.CircleMarker).openTooltip(e.latlng)
          if ((layer as any).bringToFront) (layer as any).bringToFront()
        },
        mousemove: (e: L.LeafletMouseEvent) => {
          if (schoolLayerToggle?.checked) (layer as L.CircleMarker).openTooltip(e.latlng)
        },
        mouseout: () => (layer as L.CircleMarker).closeTooltip(),
      })
    }

    function renderSchools(visibleSchools: any[]) {
      if (schoolLayer) { schoolLayer.remove(); schoolLayer = null }
      if (!schoolLayerToggle?.checked) return
      const maxValue = Math.max(...visibleSchools.filter((s) => hasMetricData(s, metricSelect?.value ?? '')).map((s) => getDistrictMetric(s, metricSelect?.value ?? '')), 0)
      const fc = { type: 'FeatureCollection', features: visibleSchools.map((s) => ({ type: 'Feature', geometry: { type: 'Point', coordinates: [s.longitude, s.latitude] }, properties: s })) }
      schoolLayer = L.geoJSON(fc as any, {
        pointToLayer: (feature: any, latlng: any) => L.circleMarker(latlng, getSchoolMarkerStyle(feature.properties, maxValue)),
        onEachFeature: bindSchoolPopup,
      }).addTo(mapInstance)
    }

    function fitMapToActiveLayer(boundaries: any[], schools: any[]) {
      const active = getActiveLayer()
      let bounds: L.LatLngBounds | null = null
      if (active === 'school' && schools.length > 0) {
        bounds = L.latLngBounds(schools.map((s) => [s.latitude, s.longitude] as L.LatLngTuple))
      } else {
        const activeBoundaries = boundaries.filter((b) => {
          if (active === 'country') return b.boundary_level === 'ADM0' && isPriorityCountry(b) && selectedCountries.has(b.country_slug)
          return b.boundary_level !== 'ADM0' && selectedDistricts.has(getDistrictKey(b))
        })
        if (activeBoundaries.length > 0) {
          bounds = L.geoJSON({ type: 'FeatureCollection', features: activeBoundaries.map((b) => ({ type: 'Feature', geometry: b.geometry, properties: b })) } as any).getBounds()
        }
      }
      if (bounds?.isValid()) {
        mapInstance.fitBounds(bounds, { padding: [34, 34], maxZoom: active === 'school' ? 9 : 8 })
      } else if (boundaryLayer?.getBounds().isValid()) {
        mapInstance.fitBounds(boundaryLayer.getBounds(), { padding: [28, 28] })
      }
    }

    function renderLayerChart(boundaries: any[], schools: any[]) {
      const metric = metricSelect?.value ?? ''
      const active = getActiveLayer()
      const rows = getLayerChartRows(boundaries, schools, metric, active)
      const maxValue = Math.max(...rows.map((r) => r.value), 0)
      if (chartTitle) chartTitle.textContent = getLayerChartTitle(active)
      if (chartMetricLabel) chartMetricLabel.textContent = getMetricLabel(metric)
      if (!countryChart) return
      countryChart.innerHTML = ''
      if (rows.length === 0) {
        countryChart.innerHTML = `<p class="empty-chart">No matching ${escapeHtml(active)} data.</p>`
        return
      }
      rows.forEach((row) => {
        const barWidth = maxValue > 0 ? Math.max((row.value / maxValue) * 100, 4) : 4
        const item = document.createElement('div')
        item.className = 'bar-row'
        item.innerHTML = `
          <div class="bar-meta">
            <span>${escapeHtml(row.label)}</span>
            <strong>${formatMetric(row.value, metric)}</strong>
          </div>
          <div class="bar-track" aria-hidden="true">
            <span class="bar-fill" style="width: ${barWidth}%"></span>
          </div>
        `
        countryChart.appendChild(item)
      })
    }

    function getLayerChartRows(boundaries: any[], schools: any[], metric: string, active: string) {
      const source = active === 'school'
        ? schools
        : boundaries.filter((b) =>
            active === 'country'
              ? b.boundary_level === 'ADM0' && isPriorityCountry(b) && selectedCountries.has(b.country_slug)
              : b.boundary_level !== 'ADM0' && isPriorityCountry(b)
          )
      return source
        .filter((item) => hasMetricData(item, metric))
        .map((item) => ({ label: getFeatureLabel(item, active), value: getDistrictMetric(item, metric) }))
        .sort((a, b) => b.value - a.value)
    }

    function getLayerChartTitle(active: string) {
      const titles: Record<string, string> = {
        country: selectedCountries.size === countryOptions.length ? 'Selected Countries' : 'Filtered Countries',
        district: 'Selected Districts',
        school: 'Selected Schools',
      }
      return titles[active] ?? ''
    }

    function getFeatureLabel(feature: any, active: string) {
      if (active === 'school') return feature.school_name
      if (active === 'country') return feature.country_name
      return feature.district_name
    }

    function renderLegend(districts: any[]) {
      const metric = metricSelect?.value ?? ''
      const label = getMetricLabel(metric)
      const yearLabel = getYearRangeLabel()
      const max = getMaxMetricValue(metric, districts)
      if (legendTitle) legendTitle.textContent = label
      if (legendSubtitle) legendSubtitle.textContent = yearLabel
      if (!legendRows) return
      if (max <= 0) {
        legendRows.innerHTML = `
          <div class="legend-row legend-row-zero">
            <span class="swatch" style="background: ${LEVEL_ZERO_COLOR}"></span>
            <span class="legend-level">Level 0</span>
            <span class="legend-range">No data or not selected</span>
          </div>`
        return
      }
      const levelZeroRow = `
        <div class="legend-row legend-row-zero" style="grid-column: 1; grid-row: 1;">
          <span class="swatch" style="background: ${LEVEL_ZERO_COLOR}"></span>
          <span class="legend-level">Level 0</span>
          <span class="legend-range">No data or not selected</span>
        </div>`
      const dataRows = LEVEL_COLORS.map((color, i) => {
        const level = i + 1
        const start = (max * i) / 5
        const end = (max * level) / 5
        const gridCol = i + 1 < 3 ? 1 : 2
        const gridRow = i + 1 < 3 ? i + 2 : i - 1
        return `
          <div class="legend-row" style="grid-column: ${gridCol}; grid-row: ${gridRow};">
            <span class="swatch" style="background: ${color}"></span>
            <span class="legend-level">Level ${level}</span>
            <span class="legend-range">${getLegendRangeLabel(start, end, level)}</span>
          </div>`
      }).join('')
      legendRows.innerHTML = levelZeroRow + dataRows
    }

    function renderDistricts() {
      const filtered = getVisibleBoundaryContext()
      const visibleSchools = getVisibleSchools()
      if (boundaryLayer) { boundaryLayer.remove(); boundaryLayer = null }
      const fc = {
        type: 'FeatureCollection',
        features: filtered.map((d) => ({ type: 'Feature', geometry: d.geometry, properties: d })),
      }
      boundaryLayer = L.geoJSON(fc as any, { style: districtStyle, onEachFeature: bindDistrictPopup }).addTo(mapInstance)
      updateMapEmptyState(filtered.length + (schoolLayerToggle?.checked ? visibleSchools.length : 0))
      mapInstance.invalidateSize()
      renderSchools(visibleSchools)
      fitMapToActiveLayer(filtered, visibleSchools)
      renderLayerChart(filtered, visibleSchools)
      renderLegend(getLegendMetricSource(filtered, visibleSchools))
      const active = getActiveLayer()
      setStatus(allDistricts.length === 0
        ? 'Supabase connected, but no boundary rows were returned.'
        : `Showing ${filtered.length} boundary layer${filtered.length === 1 ? '' : 's'} and ${schoolLayerToggle?.checked ? visibleSchools.length : 0} school point${visibleSchools.length === 1 ? '' : 's'}. KPI rows: ${loadedKpiRowCount}. School rows: ${loadedSchoolRowCount}. ${getKpiAvailabilityMessage(getLegendMetricSource(filtered, visibleSchools))} Layer: ${active}.`
      )
    }

    function getKpiAvailabilityMessage(districts: any[]) {
      const metric = metricSelect?.value ?? ''
      const yearLabel = getYearRangeLabel()
      const matching = getComparableMetricBoundaries(districts, metric).map((d) => getDistrictMetric(d, metric)).filter((v) => v !== undefined && v !== null)
      if (matching.length === 0) return `No KPI values found for ${getMetricLabel(metric)} in ${yearLabel}.`
      return `${matching.length} KPI value${matching.length === 1 ? '' : 's'} found for ${yearLabel}.`
    }

    // ── Slicer functions ──────────────────────────────────────────────────────

    function getCountryOptions() {
      const metric = metricSelect?.value ?? ''
      const countries = new Map<string, { slug: string; name: string }>()
      // Only include priority countries that have at least one district with non-zero data
      allDistricts
        .filter((d) => d.boundary_level !== 'ADM0')
        .filter(isPriorityCountry)
        .filter((d) => !metric || (hasMetricData(d, metric) && getDistrictMetric(d, metric) > 0))
        .forEach((d) => {
          countries.set(d.country_slug, { slug: d.country_slug, name: d.country_name })
        })
      return Array.from(countries.values()).sort((a, b) => a.name.localeCompare(b.name))
    }

    function refreshDistrictOptions() {
      const prev = new Set(selectedDistricts)
      const metric = metricSelect?.value ?? ''
      const districts = new Map<string, any>()
      allDistricts.filter((d) => d.boundary_level !== 'ADM0').filter(isPriorityCountry)
        .filter((d) => selectedCountries.has(d.country_slug))
        .filter((d) => !metric || (hasMetricData(d, metric) && getDistrictMetric(d, metric) > 0))
        .forEach((d) => {
          districts.set(getDistrictKey(d), { key: getDistrictKey(d), name: d.district_name, countrySlug: d.country_slug, countryName: d.country_name })
        })
      districtOptions = Array.from(districts.values()).sort((a, b) => a.countryName.localeCompare(b.countryName) || a.name.localeCompare(b.name))
      if (districtSelectionMode === 'all') {
        selectedDistricts = new Set(districtOptions.map((d) => d.key))
      } else {
        selectedDistricts = new Set(districtOptions.filter((d) => prev.has(d.key)).map((d) => d.key))
      }
      refreshSchoolOptions()
    }

    function refreshSchoolOptions() {
      const prev = new Set(selectedSchools)
      const metric = metricSelect?.value ?? ''
      const schools = new Map<string, any>()
      allSchools.filter((s) => selectedCountries.has(s.country_slug)).filter(isSchoolInSelectedDistricts)
        .filter((s) => !metric || (hasMetricData(s, metric) && getDistrictMetric(s, metric) > 0))
        .forEach((s) => {
          schools.set(s.school_id, { id: s.school_id, name: s.school_name, districtName: s.district_name, countryName: s.country_name })
        })
      schoolOptions = Array.from(schools.values()).sort((a, b) =>
        a.countryName.localeCompare(b.countryName) || a.districtName.localeCompare(b.districtName) || a.name.localeCompare(b.name)
      )
      if (schoolSelectionMode === 'all') {
        selectedSchools = new Set(schoolOptions.map((s) => s.id))
      } else {
        selectedSchools = new Set(schoolOptions.filter((s) => prev.has(s.id)).map((s) => s.id))
      }
    }

    function renderCountryList() {
      const term = (countrySearch?.value ?? '').trim().toLowerCase()
      const visible = countryOptions.filter((c) => c.name.toLowerCase().includes(term))
      if (countryList) countryList.innerHTML = visible.map((c) => renderCheckboxRow({ type: 'country', value: c.slug, label: c.name, checked: selectedCountries.has(c.slug) })).join('')
    }

    function renderDistrictList() {
      const term = (districtSearch?.value ?? '').trim().toLowerCase()
      const visible = districtOptions.filter((d) => `${d.name} ${d.countryName}`.toLowerCase().includes(term))
      if (districtList) districtList.innerHTML = visible.map((d) => renderCheckboxRow({ type: 'district', value: d.key, label: d.name, meta: d.countryName, checked: selectedDistricts.has(d.key) })).join('')
    }

    function renderSchoolList() {
      const term = (schoolSearch?.value ?? '').trim().toLowerCase()
      const visible = schoolOptions.filter((s) => `${s.name} ${s.districtName} ${s.countryName}`.toLowerCase().includes(term))
      if (schoolList) schoolList.innerHTML = visible.map((s) => renderCheckboxRow({ type: 'school', value: s.id, label: s.name, meta: `${s.districtName}, ${s.countryName}`, checked: selectedSchools.has(s.id) })).join('')
    }

    function updateSlicerCounts() {
      if (countryButtonText) countryButtonText.textContent = formatButtonText(selectedCountries.size, countryOptions.length, 'Countries')
      if (districtButtonText) districtButtonText.textContent = formatButtonText(selectedDistricts.size, districtOptions.length, 'Districts')
      if (schoolButtonText) schoolButtonText.textContent = formatButtonText(selectedSchools.size, schoolOptions.length, 'Schools')
    }

    function updateFilterVisibility() {
      const layer = getActiveLayer()
      document.getElementById('districtControl')?.classList.toggle('chip-hidden', layer === 'country')
      document.getElementById('schoolControl')?.classList.toggle('chip-hidden', layer === 'country' || layer === 'district')
    }

    function updateLayerAvailability() {
      const metric = metricSelect?.value ?? ''
      const supported = SCHOOL_LEVEL_METRICS.has(metric)
      if (schoolLayerToggle) schoolLayerToggle.disabled = !supported
      document.getElementById('schoolLayerLabel')?.classList.toggle('seg-opt--disabled', !supported)
      if (!supported && schoolLayerToggle?.checked) {
        if (districtLayerToggle) districtLayerToggle.checked = true
        updateFilterVisibility()
      }
    }

    function initializeSlicers() {
      countryOptions = getCountryOptions()
      selectedCountries = new Set(countryOptions.map((c) => c.slug))
      districtSelectionMode = 'all'
      schoolSelectionMode = 'all'
      refreshDistrictOptions()
      refreshSchoolOptions()
      renderCountryList()
      renderDistrictList()
      renderSchoolList()
      updateSlicerCounts()
    }

    function initializePlaceholderSlicers() {
      countryOptions = PRIORITY_COUNTRIES.map((slug) => ({ slug, name: getCountryNameFromSlug(slug) }))
      selectedCountries = new Set(countryOptions.map((c) => c.slug))
      districtOptions = []; selectedDistricts = new Set()
      schoolOptions = []; selectedSchools = new Set()
      districtSelectionMode = 'all'; schoolSelectionMode = 'all'
      renderCountryList(); renderDistrictList(); renderSchoolList(); updateSlicerCounts()
    }

    function populateKpiOptions() {
      if (!metricSelect) return
      metricSelect.innerHTML = KPI_DEFINITIONS.filter((k) => hasPermissionRef.current(k.permissionKey)).map((k) => `<option value="${k.key}">${escapeHtml(k.label)}</option>`).join('')
    }

    function filterKpiOptionsToAvailableData(districts: any[], schools: any[]) {
      const available = new Set<string>()
      districts.filter((d) => d.boundary_level !== 'ADM0' && isPriorityCountry(d)).forEach((d) => {
        if (!d.kpis) return
        KPI_DEFINITIONS.forEach((kpi) => { if (!available.has(kpi.key) && d.kpis[kpi.key] !== undefined && Number(d.kpis[kpi.key]) > 0) available.add(kpi.key) })
      })
      schools.forEach((s) => {
        if (!s.kpis) return
        KPI_DEFINITIONS.forEach((kpi) => { if (!available.has(kpi.key) && s.kpis[kpi.key] !== undefined && Number(s.kpis[kpi.key]) > 0) available.add(kpi.key) })
      })
      if (!metricSelect) return
      const current = metricSelect.value
      metricSelect.innerHTML = KPI_DEFINITIONS.filter((k) => available.has(k.key) && hasPermissionRef.current(k.permissionKey)).map((k) => `<option value="${k.key}">${escapeHtml(k.label)}</option>`).join('')
      if (available.has(current)) metricSelect.value = current
      else if (metricSelect.options.length > 0) metricSelect.value = metricSelect.options[0].value
      updateLayerAvailability()
    }

    // computeLatestDataYear() scans all loaded district and school rows to find the
    // highest year that contains at least one non-zero KPI value. This ensures the map
    // always shows the most recently reported data without requiring user input.
    // Called once after Supabase data finishes loading.
    function computeLatestDataYear(districts: any[], schools: any[]) {
      let maxYear = YEARS[0]
      ;[...districts, ...schools].forEach((item) => {
        if (!item.kpis?.years) return
        Object.keys(item.kpis.years).forEach((y) => {
          const yr = Number(y)
          if (yr > maxYear) {
            const vals = Object.values(item.kpis.years[y] as Record<string, any>)
            // Only count this year if at least one KPI value is a positive number
            if (vals.some((v) => Number(v) > 0)) maxYear = yr
          }
        })
      })
      return String(maxYear)
    }

    function toggleMenu(menuToToggle: HTMLElement | null, ...menusToClose: (HTMLElement | null)[]) {
      menusToClose.forEach((m) => { if (m) m.hidden = true })
      if (!menuToToggle) return
      const willOpen = menuToToggle.hidden
      menuToToggle.hidden = !willOpen
      if (willOpen) {
        const btn = menuToToggle.previousElementSibling as HTMLElement | null
        if (btn) {
          const rect = btn.getBoundingClientRect()
          menuToToggle.style.top = (rect.bottom + 6) + 'px'
          menuToToggle.style.left = rect.left + 'px'
        }
      }
    }

    function closeSlicerMenus() {
      if (countryMenu) countryMenu.hidden = true
      if (districtMenu) districtMenu.hidden = true
      if (schoolMenu) schoolMenu.hidden = true
    }

    function handleLayerChange() {
      updateFilterVisibility()
      renderDistricts()
    }

    // ── Supabase data loaders ─────────────────────────────────────────────────

    async function loadSupabaseKpiRows() {
      setStatus('Loading district KPI data from Supabase...')
      const data = await portalRpc('get_district_kpi_data').catch((e) => { setStatus(`District KPI load failed: ${e.message}`); return null })
      if (!data) return []
      setStatus(`District KPI data loaded: ${(data || []).length} districts.`)
      return (data || []).map((row: any) => ({ ...row, kpis: normalizeKpis(row.kpis) }))
    }

    async function loadStorageDistrictGeojson() {
      setStatus('Loading African country and district boundaries from Supabase Storage...')
      const [adm0, adm2, kpiRows] = await Promise.all([
        fetchGeojsonWithFallback(SUPABASE_STORAGE_ADM0_OPTIMIZED_URL, SUPABASE_STORAGE_ADM0_URL),
        fetchGeojsonWithFallback(SUPABASE_STORAGE_ADM2_OPTIMIZED_URL, SUPABASE_STORAGE_ADM2_URL),
        loadSupabaseKpiRows(),
      ])
      if (cancelled) return []
      loadedKpiRowCount = kpiRows.length
      const kpisByDistrict = indexKpiRows(kpiRows)
      const rawCountryCtx = (adm0.features as any[]).filter((f) => AFRICA_ISO3_CODES.includes(f.properties.shapeGroup)).map(normalizeStorageFeature)
      const districts = (adm2.features as any[])
        .filter((f) => AFRICA_ISO3_CODES.includes(f.properties.shapeGroup))
        .filter((f) => { const c = ISO3_TO_COUNTRY[f.properties.shapeGroup]; return c && PRIORITY_COUNTRIES.includes(c.slug) })
        .map((f) => { const d = normalizeStorageFeature(f); return { ...d, ...getMergedKpiValues(d, kpisByDistrict) } })
      const countryKpis = aggregateDistrictsToCountries(districts)
      const countryCtx = rawCountryCtx.map((c) => ({ ...c, ...(countryKpis.get(c.country_slug) || {}) }))
      setStatus(`Loaded ${countryCtx.length} countries and ${districts.length} districts.`)
      return [...countryCtx, ...districts]
    }

    async function loadDistricts() {
      return loadStorageDistrictGeojson()
    }

    async function loadSchools() {
      setStatus('Loading school point data from Supabase...')
      const data = await portalRpc('get_school_point_data').catch((e) => { setStatus(`School data load failed: ${e.message}`); return null })
      if (!data) return []
      const schools = (data || []).map(normalizeSupabaseSchool).filter((s: any) =>
        isPriorityCountry(s) && Number.isFinite(s.latitude) && Number.isFinite(s.longitude) &&
        !(s.latitude === 0 && s.longitude === 0)
      )
      setStatus(`School data loaded: ${schools.length} schools.`)
      return schools
    }

    // ── Initialization ────────────────────────────────────────────────────────

    populateKpiOptions()
    // initializeYearRange() removed — year range slider no longer exists in the UI.
    // currentDataYear is set after data loads via computeLatestDataYear().
    initializePlaceholderSlicers()
    updateFilterVisibility()
    updateLayerAvailability()

    // ── Event listeners ───────────────────────────────────────────────────────

    countrySearch?.addEventListener('input', renderCountryList)
    districtSearch?.addEventListener('input', renderDistrictList)
    schoolSearch?.addEventListener('input', renderSchoolList)

    metricSelect?.addEventListener('change', () => {
      updateLayerAvailability()
      countryOptions = getCountryOptions()
      selectedCountries = new Set(countryOptions.map((c) => c.slug))
      districtSelectionMode = 'all'; schoolSelectionMode = 'all'
      refreshDistrictOptions(); refreshSchoolOptions()
      renderCountryList(); renderDistrictList(); renderSchoolList()
      updateSlicerCounts(); renderDistricts()
    })
    // yearStart and yearEnd event listeners removed — the year-range slider inputs no
    // longer exist in the JSX. The map re-renders only when the metric or layer changes.

    countryLayerToggle?.addEventListener('change', handleLayerChange)
    districtLayerToggle?.addEventListener('change', handleLayerChange)
    schoolLayerToggle?.addEventListener('change', handleLayerChange)

    document.querySelectorAll('.seg-opt').forEach((label) => {
      label.addEventListener('click', () => {
        const input = label.querySelector('input[type="radio"]') as HTMLInputElement | null
        if (input) input.checked = true
        handleLayerChange()
      })
    })

    countryToggle?.addEventListener('click', () => toggleMenu(countryMenu, districtMenu, schoolMenu))
    districtToggle?.addEventListener('click', () => toggleMenu(districtMenu, countryMenu, schoolMenu))
    schoolToggle?.addEventListener('click', () => toggleMenu(schoolMenu, countryMenu, districtMenu))

    const onDocClick = (e: MouseEvent) => { if (!(e.target as Element).closest('.slicer')) closeSlicerMenus() }
    document.addEventListener('click', onDocClick)

    countryAll?.addEventListener('click', () => {
      selectedCountries = new Set(countryOptions.map((c) => c.slug))
      districtSelectionMode = 'all'; schoolSelectionMode = 'all'
      refreshDistrictOptions(); refreshSchoolOptions()
      renderCountryList(); renderDistrictList(); renderSchoolList(); updateSlicerCounts(); renderDistricts()
    })
    countryNone?.addEventListener('click', () => {
      selectedCountries = new Set(); selectedDistricts = new Set(); selectedSchools = new Set()
      districtSelectionMode = 'none'; schoolSelectionMode = 'none'
      refreshDistrictOptions(); refreshSchoolOptions()
      renderCountryList(); renderDistrictList(); renderSchoolList(); updateSlicerCounts(); renderDistricts()
    })
    districtAll?.addEventListener('click', () => {
      districtSelectionMode = 'all'; schoolSelectionMode = 'all'
      selectedDistricts = new Set(districtOptions.map((d) => d.key))
      refreshSchoolOptions(); renderDistrictList(); renderSchoolList(); updateSlicerCounts(); renderDistricts()
    })
    districtNone?.addEventListener('click', () => {
      districtSelectionMode = 'none'; schoolSelectionMode = 'none'
      selectedDistricts = new Set(); selectedSchools = new Set()
      refreshSchoolOptions(); renderDistrictList(); renderSchoolList(); updateSlicerCounts(); renderDistricts()
    })
    schoolAll?.addEventListener('click', () => {
      schoolSelectionMode = 'all'; selectedSchools = new Set(schoolOptions.map((s) => s.id))
      renderSchoolList(); updateSlicerCounts(); renderDistricts()
    })
    schoolNone?.addEventListener('click', () => {
      schoolSelectionMode = 'none'; selectedSchools = new Set()
      renderSchoolList(); updateSlicerCounts(); renderDistricts()
    })

    countryList?.addEventListener('change', (e) => {
      const target = e.target as HTMLInputElement
      if (!target.matches('input[data-type="country"]')) return
      target.checked ? selectedCountries.add(target.value) : selectedCountries.delete(target.value)
      districtSelectionMode = 'all'; schoolSelectionMode = 'all'
      refreshDistrictOptions(); refreshSchoolOptions()
      renderCountryList(); renderDistrictList(); renderSchoolList(); updateSlicerCounts(); renderDistricts()
    })
    districtList?.addEventListener('change', (e) => {
      const target = e.target as HTMLInputElement
      if (!target.matches('input[data-type="district"]')) return
      target.checked ? selectedDistricts.add(target.value) : selectedDistricts.delete(target.value)
      districtSelectionMode = selectedDistricts.size === districtOptions.length ? 'all' : 'custom'
      schoolSelectionMode = 'all'; refreshSchoolOptions()
      renderDistrictList(); renderSchoolList(); updateSlicerCounts(); renderDistricts()
    })
    schoolList?.addEventListener('change', (e) => {
      const target = e.target as HTMLInputElement
      if (!target.matches('input[data-type="school"]')) return
      target.checked ? selectedSchools.add(target.value) : selectedSchools.delete(target.value)
      schoolSelectionMode = selectedSchools.size === schoolOptions.length ? 'all' : 'custom'
      renderSchoolList(); updateSlicerCounts(); renderDistricts()
    })

    // ── Load data ─────────────────────────────────────────────────────────────

    Promise.all([loadDistricts(), loadSchools()])
      .then(([districts, schools]) => {
        if (cancelled) return
        allDistricts = districts; allSchools = schools; loadedSchoolRowCount = schools.length
        // Determine the most recent year that has actual data and lock the map to it.
        // This replaces the year-range slider — the user no longer selects a year,
        // the map automatically shows the latest available reporting year.
        currentDataYear = computeLatestDataYear(districts, schools)
        initializeSlicers()
        filterKpiOptionsToAvailableData(districts, schools)
        renderDistricts()
      })
      .catch((err) => {
        if (cancelled) return
        console.error(err)
        allDistricts = sampleDistricts; allSchools = []; loadedSchoolRowCount = 0
        // Fall back to the last year in YEARS when using sample data (no real data to scan)
        currentDataYear = String(YEARS[YEARS.length - 1])
        initializeSlicers()
        filterKpiOptionsToAvailableData(sampleDistricts, [])
        setStatus('Boundary data could not load — sample data is shown.')
        renderDistricts()
      })

    // ── Cleanup ───────────────────────────────────────────────────────────────

    return () => {
      cancelled = true
      document.removeEventListener('click', onDocClick)
      mapInstance.remove()
    }
  }, [showHowTo])

  // ── JSX ────────────────────────────────────────────────────────────────────

  return (
    <div className="map-page-shell">

      {/* ── Filter bar ────────────────────────────────────────────────────── */}
      <FilterSection>

        {/* Layer */}
        <div className="filter-bar-item filter-bar-item--layer">
          <label className="filter-bar-label">
            <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true">
              <polygon points="8,2 14,5.5 8,9 2,5.5" />
              <polyline points="2,9.5 8,13 14,9.5" />
              <polyline points="2,7 8,10.5 14,7" />
            </svg>
            Layer
          </label>
          <div className="seg-control" role="radiogroup" aria-label="Map layer">
            <label className="seg-opt">
              <input type="radio" name="activeLayer" value="country" id="countryLayerToggle" defaultChecked onChange={() => setShowHowTo(false)} />
              <span>
                <svg viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true">
                  <circle cx="7" cy="7" r="5.5" />
                  <path d="M7 1.5c-1.2 1.6-2 3.4-2 5.5s.8 3.9 2 5.5M7 1.5c1.2 1.6 2 3.4 2 5.5s-.8 3.9-2 5.5M1.5 7h11" />
                </svg>
                Country
              </span>
            </label>
            <label className="seg-opt">
              <input type="radio" name="activeLayer" value="district" id="districtLayerToggle" onChange={() => setShowHowTo(false)} />
              <span>
                <svg viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true">
                  <path d="M7 12.5S2 8.5 2 5.5a5 5 0 0110 0c0 3-5 7-5 7z" />
                  <circle cx="7" cy="5.5" r="1.5" />
                </svg>
                District
              </span>
            </label>
            <label className="seg-opt" id="schoolLayerLabel">
              <input type="radio" name="activeLayer" value="school" id="schoolLayerToggle" onChange={() => setShowHowTo(false)} />
              <span>
                <svg viewBox="0 0 14 14" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true">
                  <rect x="1.5" y="6" width="11" height="6.5" rx="1" />
                  <path d="M0.5 6L7 2l6.5 4" />
                  <rect x="5" y="9" width="4" height="3.5" />
                </svg>
                School
              </span>
            </label>
          </div>
        </div>

        {/* Country */}
        <div className="filter-bar-item slicer" id="countryControl">
          <label className="filter-bar-label">
            <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true">
              <circle cx="8" cy="8" r="6.5" />
              <path d="M8 1.5c-1.5 2-2.5 4-2.5 6.5s1 4.5 2.5 6.5M8 1.5c1.5 2 2.5 4 2.5 6.5s-1 4.5-2.5 6.5M1.5 8h13" />
            </svg>
            Country
          </label>
          <button type="button" id="countryToggle" className="chip-btn" onClick={() => setShowHowTo(false)}>
            <span id="countryButtonText">All Countries</span>
            <svg className="chip-chevron" viewBox="0 0 10 6" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
              <path d="M1 1l4 4 4-4" />
            </svg>
          </button>
          <div id="countryMenu" className="slicer-menu" hidden>
            <input id="countrySearch" type="search" placeholder="Search countries…" />
            <div className="slicer-links">
              <button type="button" id="countryAll">All</button>
              <span />
              <button type="button" id="countryNone">None</button>
            </div>
            <div id="countryList" className="check-list" aria-label="Country options" />
          </div>
        </div>

        {/* District */}
        <div className="filter-bar-item slicer chip-hidden" id="districtControl">
          <label className="filter-bar-label">
            <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true">
              <path d="M8 14.5S2.5 10 2.5 6.5a5.5 5.5 0 0111 0c0 3.5-5.5 8-5.5 8z" />
              <circle cx="8" cy="6.5" r="2" />
            </svg>
            District
          </label>
          <button type="button" id="districtToggle" className="chip-btn">
            <span id="districtButtonText">All Districts</span>
            <svg className="chip-chevron" viewBox="0 0 10 6" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
              <path d="M1 1l4 4 4-4" />
            </svg>
          </button>
          <div id="districtMenu" className="slicer-menu district-menu" hidden>
            <input id="districtSearch" type="search" placeholder="Search districts…" />
            <div className="slicer-links">
              <button type="button" id="districtAll">All</button>
              <span />
              <button type="button" id="districtNone">None</button>
            </div>
            <div id="districtList" className="check-list" aria-label="District options" />
          </div>
        </div>

        {/* School */}
        <div className="filter-bar-item slicer chip-hidden" id="schoolControl">
          <label className="filter-bar-label">
            <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true">
              <rect x="2" y="7" width="12" height="7.5" rx="1" />
              <path d="M1 7l7-4.5L15 7" />
              <rect x="5.5" y="10.5" width="5" height="4" />
            </svg>
            School
          </label>
          <button type="button" id="schoolToggle" className="chip-btn">
            <span id="schoolButtonText">All Schools</span>
            <svg className="chip-chevron" viewBox="0 0 10 6" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
              <path d="M1 1l4 4 4-4" />
            </svg>
          </button>
          <div id="schoolMenu" className="slicer-menu school-menu" hidden>
            <input id="schoolSearch" type="search" placeholder="Search schools…" />
            <div className="slicer-links">
              <button type="button" id="schoolAll">All</button>
              <span />
              <button type="button" id="schoolNone">None</button>
            </div>
            <div id="schoolList" className="check-list" aria-label="School options" />
          </div>
        </div>

        {/* KPI */}
        <div className="filter-bar-item">
          <label className="filter-bar-label">
            <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="1.5" aria-hidden="true">
              <rect x="2" y="8" width="3" height="6" />
              <rect x="6.5" y="4" width="3" height="10" />
              <rect x="11" y="6" width="3" height="8" />
            </svg>
            KPI
          </label>
          <select id="metricSelect" className="indicator-dropdown map-kpi-select" onChange={() => setShowHowTo(false)} />
        </div>

      </FilterSection>

      {/* ── Dashboard content ──────────────────────────────────────────────── */}
      <div className="dashboard-content">

        {/* ── How to use (shown on first visit; dismissed with Got it) ────── */}
        {showHowTo && (
          <div className="landing-section landing-section--how-to map-how-to">
            <button
              type="button"
              className="map-how-to-close"
              aria-label="Dismiss"
              onClick={() => setShowHowTo(false)}
            >
              <svg width="14" height="14" viewBox="0 0 16 16" fill="none" stroke="currentColor" strokeWidth="2" aria-hidden="true">
                <path d="M4 4l8 8M12 4l-8 8" strokeLinecap="round" />
              </svg>
            </button>
            <div className="landing-title">How to Use the Data Map</div>
            <p className="landing-intro">
              Explore country, district, and school-level programme data by choosing a layer, selecting places, and choosing a KPI.
            </p>
            <div className="landing-steps">
              <div className="landing-step">
                <span className="landing-step-num">1</span>
                <div className="landing-step-text">
                  <strong>Select a Map Layer</strong>
                  <span>Choose Country, District, or School to change what is shown on the map.</span>
                </div>
              </div>
              <div className="landing-step">
                <span className="landing-step-num">2</span>
                <div className="landing-step-text">
                  <strong>Filter the Geography</strong>
                  <span>Use the Country, District, and School dropdowns to narrow the map to specific places.</span>
                </div>
              </div>
              <div className="landing-step">
                <span className="landing-step-num">3</span>
                <div className="landing-step-text">
                  <strong>Choose a KPI</strong>
                  <span>The map colours, legend, and summary update based on the selected KPI. Data shown is always the most recent available year.</span>
                </div>
              </div>
              <div className="landing-step">
                <span className="landing-step-num">4</span>
                <div className="landing-step-text">
                  <strong>Hover for Details</strong>
                  <span>Hover over any country, district, or school to see details in the Inspector panel.</span>
                </div>
              </div>
            </div>
            <div className="landing-tip">
              <span className="landing-tip-arrow">→</span>
              <span>Use <strong>Layer</strong> to switch between country totals, district boundaries, and school points.</span>
            </div>
          </div>
        )}
        {!showHowTo && (
          <>
            <div className="panel-grid">

              {/* Map panel */}
              <article className="panel panel-map">
                <div className="panel-heading">
                  <h2>SHF Agriculture Programme Map</h2>
                  <span>Leaflet + Supabase</span>
                </div>
                <div ref={mapContainerRef} id="map" aria-label="SHF Agriculture programme data map" />
                <div id="mapEmpty" className="map-empty" hidden>
                  <strong>No boundary data loaded</strong>
                  <span>The GeoJSON file could not be loaded or did not return African boundaries. Check the Supabase Storage URL and refresh the page.</span>
                </div>
                <div className="map-detail-grid">
                  <section className="map-detail-card chart-legend" aria-label="Map legend">
                    <div className="legend-titlebar">
                      <span>Legend</span>
                      <h2 id="legendTitle">Programme count</h2>
                      <p id="legendSubtitle" />
                    </div>
                    <div id="legendRows" className="legend-rows" />
                  </section>
                </div>
              </article>

              {/* Inspector + chart panel */}
              <article className="panel chart-panel inspector-panel" aria-label="Map feature details">
                <div className="inspector-card" aria-live="polite">
                  <div className="inspector-titlebar">
                    <span id="inspectorType">Inspector</span>
                    <h2 id="inspectorTitle">Hover over a country, district, or school</h2>
                  </div>
                  <dl id="inspectorDetails" className="inspector-details">
                    <dt>Selection</dt>
                    <dd>No map feature selected</dd>
                  </dl>
                </div>

                <section className="map-detail-card chart-summary-card" aria-label="Selected metric chart">
                  <div className="panel-heading">
                    <h2 id="chartTitle">Priority Countries</h2>
                    <span id="chartMetricLabel">Programme count</span>
                  </div>
                  <div id="countryChart" className="bar-chart" />
                </section>
              </article>

            </div>

            <section className="support-grid">
              <article className="panel status-panel" aria-live="polite">
                <h2>Status</h2>
                <p id="statusText">Loading map…</p>
              </article>
            </section>
          </>
        )}
      </div>

    </div>
  )
}
