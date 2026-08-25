const DISTRICT_GEOJSON_FILE = "./geoBoundariesCGAZ_ADM2.geojson";
const BOUNDARY_SOURCE = "sample";
const USE_LOCAL_GEOJSON = false;
const PRIORITY_COUNTRIES = ["tanzania", "ghana", "malawi", "zambia", "zimbabwe"];
const YEARS = Array.from({ length: 11 }, (_, index) => 2020 + index);
const KPI_DEFINITIONS = [
  {
    key: "education_bursaries_children",
    label: "Children Supported in School with Education Bursaries",
  },
  {
    key: "education_bursaries_children_annual",
    label: "Children Supported in School with Education Bursaries - Annual",
  },
  {
    key: "education_bursaries_children_cumulative_2020_2030",
    label:
      "Children Supported in School with Education Bursaries - Cumulative 2020-2030",
  },
  {
    key: "education_bursaries_children_cumulative_all_time",
    label: "Children Supported in School with Education Bursaries - Cumulative all-time",
  },
  { key: "active_learner_guides", label: "Active Learner Guides" },
  { key: "clients_by_form", label: "Number of Clients by Form" },
  { key: "clients_by_form_girls", label: "Number of Clients by Form - Girls" },
  { key: "clients_by_form_boys", label: "Number of Clients by Form - Boys" },
  { key: "active_partner_schools", label: "Active Partner Schools" },
  {
    key: "women_supported_tertiary",
    label: "Number of Women Supported by CAMFED in Tertiary Education",
  },
  { key: "active_guides_by_type", label: "Active Guides by Type" },
  { key: "post_school_clients", label: "Number of Post School Clients" },
  { key: "grants_disbursed", label: "Grants Disbursed" },
  { key: "loans_disbursed", label: "Loans Disbursed" },
  { key: "cama_members", label: "CAMA Members" },
  { key: "active_guides_transition", label: "Active Guides - Transition" },
  { key: "active_guides_agriculture", label: "Active Guides - Agriculture" },
  { key: "active_guides_business", label: "Active Guides - Business" },
  { key: "grants_distributed_count", label: "Grants Distributed - Count" },
];
const AFRICA_ISO3_CODES = [
  "DZA",
  "AGO",
  "BEN",
  "BWA",
  "BFA",
  "BDI",
  "CPV",
  "CMR",
  "CAF",
  "TCD",
  "COM",
  "COG",
  "COD",
  "CIV",
  "DJI",
  "EGY",
  "GNQ",
  "ERI",
  "SWZ",
  "ETH",
  "GAB",
  "GMB",
  "GHA",
  "GIN",
  "GNB",
  "KEN",
  "LSO",
  "LBR",
  "LBY",
  "MDG",
  "MWI",
  "MLI",
  "MRT",
  "MUS",
  "MAR",
  "MOZ",
  "NAM",
  "NER",
  "NGA",
  "RWA",
  "STP",
  "SEN",
  "SYC",
  "SLE",
  "SOM",
  "ZAF",
  "SSD",
  "SDN",
  "TZA",
  "TGO",
  "TUN",
  "UGA",
  "ZMB",
  "ZWE",
];
const ISO3_TO_COUNTRY = {
  DZA: { slug: "algeria", name: "Algeria" },
  AGO: { slug: "angola", name: "Angola" },
  BEN: { slug: "benin", name: "Benin" },
  BWA: { slug: "botswana", name: "Botswana" },
  BFA: { slug: "burkina-faso", name: "Burkina Faso" },
  BDI: { slug: "burundi", name: "Burundi" },
  CPV: { slug: "cabo-verde", name: "Cabo Verde" },
  CMR: { slug: "cameroon", name: "Cameroon" },
  CAF: { slug: "central-african-republic", name: "Central African Republic" },
  TCD: { slug: "chad", name: "Chad" },
  COM: { slug: "comoros", name: "Comoros" },
  COG: { slug: "congo", name: "Republic of the Congo" },
  COD: { slug: "dr-congo", name: "Democratic Republic of the Congo" },
  CIV: { slug: "cote-divoire", name: "Cote d'Ivoire" },
  DJI: { slug: "djibouti", name: "Djibouti" },
  EGY: { slug: "egypt", name: "Egypt" },
  GNQ: { slug: "equatorial-guinea", name: "Equatorial Guinea" },
  ERI: { slug: "eritrea", name: "Eritrea" },
  SWZ: { slug: "eswatini", name: "Eswatini" },
  ETH: { slug: "ethiopia", name: "Ethiopia" },
  GAB: { slug: "gabon", name: "Gabon" },
  GMB: { slug: "gambia", name: "The Gambia" },
  TZA: { slug: "tanzania", name: "Tanzania" },
  GHA: { slug: "ghana", name: "Ghana" },
  GIN: { slug: "guinea", name: "Guinea" },
  GNB: { slug: "guinea-bissau", name: "Guinea-Bissau" },
  KEN: { slug: "kenya", name: "Kenya" },
  LSO: { slug: "lesotho", name: "Lesotho" },
  LBR: { slug: "liberia", name: "Liberia" },
  LBY: { slug: "libya", name: "Libya" },
  MDG: { slug: "madagascar", name: "Madagascar" },
  MWI: { slug: "malawi", name: "Malawi" },
  MLI: { slug: "mali", name: "Mali" },
  MRT: { slug: "mauritania", name: "Mauritania" },
  MUS: { slug: "mauritius", name: "Mauritius" },
  MAR: { slug: "morocco", name: "Morocco" },
  MOZ: { slug: "mozambique", name: "Mozambique" },
  NAM: { slug: "namibia", name: "Namibia" },
  NER: { slug: "niger", name: "Niger" },
  NGA: { slug: "nigeria", name: "Nigeria" },
  RWA: { slug: "rwanda", name: "Rwanda" },
  STP: { slug: "sao-tome-and-principe", name: "Sao Tome and Principe" },
  SEN: { slug: "senegal", name: "Senegal" },
  SYC: { slug: "seychelles", name: "Seychelles" },
  SLE: { slug: "sierra-leone", name: "Sierra Leone" },
  SOM: { slug: "somalia", name: "Somalia" },
  ZAF: { slug: "south-africa", name: "South Africa" },
  SSD: { slug: "south-sudan", name: "South Sudan" },
  SDN: { slug: "sudan", name: "Sudan" },
  TGO: { slug: "togo", name: "Togo" },
  TUN: { slug: "tunisia", name: "Tunisia" },
  UGA: { slug: "uganda", name: "Uganda" },
  ZMB: { slug: "zambia", name: "Zambia" },
  ZWE: { slug: "zimbabwe", name: "Zimbabwe" },
};

const sampleDistricts = [
  {
    id: "tz-arusha",
    country_slug: "tanzania",
    country_name: "Tanzania",
    district_name: "Arusha",
    program_count: 18,
    beneficiary_count: 12400,
    risk_score: 34,
    kpis: {
      education_bursaries_children: 34004,
      education_bursaries_children_annual: 2800,
      education_bursaries_children_cumulative_2020_2030: 15720,
      education_bursaries_children_cumulative_all_time: 34004,
      active_learner_guides: 260,
      clients_by_form: 39735,
      clients_by_form_girls: 21500,
      clients_by_form_boys: 18235,
      active_partner_schools: 210,
      women_supported_tertiary: 480,
      active_guides_by_type: 760,
      post_school_clients: 9300,
      grants_disbursed: 142000,
      loans_disbursed: 46000,
      cama_members: 11800,
      active_guides_transition: 120,
      active_guides_agriculture: 88,
      active_guides_business: 74,
      grants_distributed_count: 340,
    },
    geometry: {
      type: "Polygon",
      coordinates: [
        [
          [36.25, -3.05],
          [37.35, -3.05],
          [37.35, -3.85],
          [36.25, -3.85],
          [36.25, -3.05],
        ],
      ],
    },
  },
  {
    id: "gh-tamale",
    country_slug: "ghana",
    country_name: "Ghana",
    district_name: "Tamale",
    program_count: 12,
    beneficiary_count: 8100,
    risk_score: 28,
    kpis: {
      education_bursaries_children: 4986,
      education_bursaries_children_annual: 640,
      education_bursaries_children_cumulative_2020_2030: 3200,
      education_bursaries_children_cumulative_all_time: 4986,
      active_learner_guides: 75,
      clients_by_form: 12460,
      clients_by_form_girls: 7600,
      clients_by_form_boys: 4860,
      active_partner_schools: 62,
      women_supported_tertiary: 110,
      active_guides_by_type: 210,
      post_school_clients: 2400,
      grants_disbursed: 42000,
      loans_disbursed: 9000,
      cama_members: 4200,
      active_guides_transition: 32,
      active_guides_agriculture: 18,
      active_guides_business: 24,
      grants_distributed_count: 88,
    },
    geometry: {
      type: "Polygon",
      coordinates: [
        [
          [-1.25, 9.75],
          [-0.45, 9.75],
          [-0.45, 9.15],
          [-1.25, 9.15],
          [-1.25, 9.75],
        ],
      ],
    },
  },
  {
    id: "mw-lilongwe",
    country_slug: "malawi",
    country_name: "Malawi",
    district_name: "Lilongwe",
    program_count: 21,
    beneficiary_count: 16300,
    risk_score: 42,
    kpis: {
      education_bursaries_children: 15506,
      education_bursaries_children_annual: 1300,
      education_bursaries_children_cumulative_2020_2030: 8600,
      education_bursaries_children_cumulative_all_time: 15506,
      active_learner_guides: 180,
      clients_by_form: 34049,
      clients_by_form_girls: 18600,
      clients_by_form_boys: 15449,
      active_partner_schools: 140,
      women_supported_tertiary: 320,
      active_guides_by_type: 540,
      post_school_clients: 6800,
      grants_disbursed: 98000,
      loans_disbursed: 22000,
      cama_members: 9200,
      active_guides_transition: 76,
      active_guides_agriculture: 58,
      active_guides_business: 48,
      grants_distributed_count: 210,
    },
    geometry: {
      type: "Polygon",
      coordinates: [
        [
          [33.35, -13.55],
          [34.2, -13.55],
          [34.2, -14.25],
          [33.35, -14.25],
          [33.35, -13.55],
        ],
      ],
    },
  },
  {
    id: "zm-lusaka",
    country_slug: "zambia",
    country_name: "Zambia",
    district_name: "Lusaka",
    program_count: 15,
    beneficiary_count: 9800,
    risk_score: 38,
    kpis: {
      education_bursaries_children: 28266,
      education_bursaries_children_annual: 2100,
      education_bursaries_children_cumulative_2020_2030: 14100,
      education_bursaries_children_cumulative_all_time: 28266,
      active_learner_guides: 230,
      clients_by_form: 18792,
      clients_by_form_girls: 9900,
      clients_by_form_boys: 8892,
      active_partner_schools: 175,
      women_supported_tertiary: 260,
      active_guides_by_type: 470,
      post_school_clients: 5400,
      grants_disbursed: 79000,
      loans_disbursed: 17000,
      cama_members: 7600,
      active_guides_transition: 62,
      active_guides_agriculture: 42,
      active_guides_business: 36,
      grants_distributed_count: 170,
    },
    geometry: {
      type: "Polygon",
      coordinates: [
        [
          [28.0, -15.15],
          [28.75, -15.15],
          [28.75, -15.8],
          [28.0, -15.8],
          [28.0, -15.15],
        ],
      ],
    },
  },
  {
    id: "zw-harare",
    country_slug: "zimbabwe",
    country_name: "Zimbabwe",
    district_name: "Harare",
    program_count: 9,
    beneficiary_count: 6900,
    risk_score: 47,
    kpis: {
      education_bursaries_children: 12966,
      education_bursaries_children_annual: 980,
      education_bursaries_children_cumulative_2020_2030: 7400,
      education_bursaries_children_cumulative_all_time: 12966,
      active_learner_guides: 135,
      clients_by_form: 31754,
      clients_by_form_girls: 16800,
      clients_by_form_boys: 14954,
      active_partner_schools: 115,
      women_supported_tertiary: 210,
      active_guides_by_type: 360,
      post_school_clients: 3900,
      grants_disbursed: 64000,
      loans_disbursed: 14000,
      cama_members: 6900,
      active_guides_transition: 48,
      active_guides_agriculture: 36,
      active_guides_business: 30,
      grants_distributed_count: 130,
    },
    geometry: {
      type: "Polygon",
      coordinates: [
        [
          [30.65, -17.55],
          [31.45, -17.55],
          [31.45, -18.1],
          [30.65, -18.1],
          [30.65, -17.55],
        ],
      ],
    },
  },
];

const map = L.map("map", {
  zoomControl: true,
  minZoom: 4,
  attributionControl: false,
}).setView([-8, 24], 4);

const countrySearch = document.querySelector("#countrySearch");
const countryToggle = document.querySelector("#countryToggle");
const countryMenu = document.querySelector("#countryMenu");
const countryButtonText = document.querySelector("#countryButtonText");
const countryList = document.querySelector("#countryList");
const countryAll = document.querySelector("#countryAll");
const countryNone = document.querySelector("#countryNone");
const districtSearch = document.querySelector("#districtSearch");
const districtToggle = document.querySelector("#districtToggle");
const districtMenu = document.querySelector("#districtMenu");
const districtButtonText = document.querySelector("#districtButtonText");
const districtList = document.querySelector("#districtList");
const districtAll = document.querySelector("#districtAll");
const districtNone = document.querySelector("#districtNone");
const schoolSearch = document.querySelector("#schoolSearch");
const schoolToggle = document.querySelector("#schoolToggle");
const schoolMenu = document.querySelector("#schoolMenu");
const schoolButtonText = document.querySelector("#schoolButtonText");
const schoolList = document.querySelector("#schoolList");
const schoolAll = document.querySelector("#schoolAll");
const schoolNone = document.querySelector("#schoolNone");
const metricSelect = document.querySelector("#metricSelect");
const yearStart = document.querySelector("#yearStart");
const yearEnd = document.querySelector("#yearEnd");
const yearRangeText = document.querySelector("#yearRangeText");
const countryLayerToggle = document.querySelector("#countryLayerToggle");
const districtLayerToggle = document.querySelector("#districtLayerToggle");
const schoolLayerToggle = document.querySelector("#schoolLayerToggle");
const statusText = document.querySelector("#statusText");
const chartTitle = document.querySelector("#chartTitle");
const chartMetricLabel = document.querySelector("#chartMetricLabel");
const countryChart = document.querySelector("#countryChart");
const mapEmpty = document.querySelector("#mapEmpty");
const legendTitle = document.querySelector("#legendTitle");
const legendSubtitle = document.querySelector("#legendSubtitle");
const legendRows = document.querySelector("#legendRows");
const inspectorType = document.querySelector("#inspectorType");
const inspectorTitle = document.querySelector("#inspectorTitle");
const inspectorDetails = document.querySelector("#inspectorDetails");
const mapIntroOverlay = document.querySelector("#mapIntroOverlay");
const mapIntroClose = document.querySelector("#mapIntroClose");
const mapIntroExplore = document.querySelector("#mapIntroExplore");

const LEVEL_ZERO_COLOR = "#ffffff";
const LEVEL_COLORS = ["#e7e0f0", "#c9bbdd", "#b78f2f", "#b5533d", "#6b22aa"];

let allDistricts = [];
let allSchools = [];
let boundaryLayer;
let schoolLayer;
let countryOptions = [];
let districtOptions = [];
let schoolOptions = [];
let selectedCountries = new Set();
let selectedDistricts = new Set();
let selectedSchools = new Set();
let districtSelectionMode = "all";
let schoolSelectionMode = "all";
let loadedKpiRowCount = 0;
let loadedSchoolRowCount = 0;

populateKpiOptions();
initializeYearRange();
initializePlaceholderSlicers();
updateFilterVisibility();

async function loadDistricts() {
  setStatus('Using local sample district and country data from this repository.');
  const districts = sampleDistricts.map((district) => ({
    ...district,
    boundary_level: 'ADM2',
    kpis: normalizeKpis(district.kpis),
  }));
  const countries = aggregateDistrictsToCountries(districts);
  return [...countries.values(), ...districts];
}

async function loadSchools() {
  loadedSchoolRowCount = sampleDistricts.length * 2;
  return sampleDistricts.flatMap((district) => {
    const [lng, lat] = getPolygonCenter(district.geometry);
    return [0, 1].map((offset) => ({
      school_id: district.id + '-school-' + (offset + 1),
      school_name: district.district_name + (offset === 0 ? ' Demonstration School' : ' Partner Secondary'),
      country_slug: district.country_slug,
      country_name: district.country_name,
      district_name: district.district_name,
      province: 'Demo Province',
      geo_source: 'local_sample',
      latitude: lat + (offset === 0 ? 0.08 : -0.08),
      longitude: lng + (offset === 0 ? 0.08 : -0.08),
      kpis: scaleKpis(district.kpis, offset === 0 ? 0.56 : 0.44),
    }));
  });
}

function getPolygonCenter(geometry) {
  const ring = geometry && geometry.coordinates && geometry.coordinates[0];
  if (!ring || !ring.length) return [0, 0];
  const total = ring.reduce(
    (acc, coord) => ({ lng: acc.lng + coord[0], lat: acc.lat + coord[1] }),
    { lng: 0, lat: 0 }
  );
  return [total.lng / ring.length, total.lat / ring.length];
}

function scaleKpis(kpis, multiplier) {
  return Object.fromEntries(
    Object.entries(normalizeKpis(kpis)).map(([key, value]) => [key, Math.round(Number(value || 0) * multiplier)])
  );
}

function indexKpiRows(rows) {
  const index = new Map();

  rows.forEach((row) => {
    index.set(getDistrictKey(row), row);
  });

  return index;
}

function getMergedKpiValues(district, kpisByDistrict) {
  const row = kpisByDistrict.get(getDistrictKey(district));

  if (!row) {
    return {
      program_count: 0,
      beneficiary_count: 0,
      risk_score: 0,
      kpis: {},
    };
  }

  return {
    program_count: Number(row.program_count || 0),
    beneficiary_count: Number(row.beneficiary_count || 0),
    risk_score: Number(row.risk_score || 0),
    kpis: row.kpis || {},
  };
}

function aggregateDistrictsToCountries(districts) {
  const countries = new Map();

  districts.filter(isPriorityCountry).forEach((district) => {
    const current = countries.get(district.country_slug) || {
      country_slug: district.country_slug,
      country_name: district.country_name,
      district_name: district.country_name,
      boundary_level: "ADM0",
      program_count: 0,
      beneficiary_count: 0,
      risk_score_total: 0,
      risk_score_count: 0,
      kpis: { years: {} },
    };

    current.program_count += Number(district.program_count || 0);
    current.beneficiary_count += Number(district.beneficiary_count || 0);
    current.risk_score_total += Number(district.risk_score || 0);
    current.risk_score_count += 1;

    KPI_DEFINITIONS.forEach((kpi) => {
      const flatValue = district.kpis?.[kpi.key];
      if (flatValue !== undefined) {
        current.kpis[kpi.key] = Number(current.kpis[kpi.key] || 0) + Number(flatValue || 0);
      }

      YEARS.forEach((year) => {
        const yearKey = String(year);
        const value = getRawDistrictMetric(district, kpi.key, yearKey, { yearlyOnly: true });
        if (value === undefined || value === null) return;

        current.kpis.years[yearKey] ||= {};
        current.kpis.years[yearKey][kpi.key] =
          Number(current.kpis.years[yearKey][kpi.key] || 0) + Number(value || 0);
      });
    });

    countries.set(district.country_slug, current);
  });

  return new Map(
    Array.from(countries.entries()).map(([slug, country]) => [
      slug,
      {
        ...country,
        risk_score:
          country.risk_score_count > 0 ? country.risk_score_total / country.risk_score_count : 0,
      },
    ])
  );
}

function getDistrictKey(district) {
  return `${district.country_slug}::${district.district_name}`.toLowerCase();
}

function getNormalizedDistrictName(name) {
  return String(name || "")
    .toLowerCase()
    .replace(/&/g, " and ")
    .replace(/[^a-z0-9]+/g, " ")
    .replace(
      /\b(district|municipal|municipality|metropolitan|metro|city|town|council|province|region)\b/g,
      " "
    )
    .replace(/\s+/g, " ")
    .trim();
}

function isDistrictNameMatch(leftName, rightName) {
  const left = getNormalizedDistrictName(leftName);
  const right = getNormalizedDistrictName(rightName);

  if (!left || !right) return false;
  return left === right || left.includes(right) || right.includes(left);
}

function isSchoolInSelectedDistricts(school) {
  // When no manual district filtering is active, all schools in
  // selected countries are visible — country check already done upstream.
  if (districtSelectionMode === "all") return true;

  // Direct key match (country_slug::district_name)
  if (selectedDistricts.has(getDistrictKey(school))) return true;

  // Fuzzy name match then point-in-polygon fallback
  return districtOptions.some((district) => {
    if (!selectedDistricts.has(district.key) || district.countrySlug !== school.country_slug) {
      return false;
    }

    if (isDistrictNameMatch(district.name, school.district_name)) {
      return true;
    }

    const boundary = allDistricts.find(
      (item) => item.boundary_level !== "ADM0" && getDistrictKey(item) === district.key
    );

    return (
      boundary?.geometry &&
      Number.isFinite(school.latitude) &&
      Number.isFinite(school.longitude) &&
      !(school.latitude === 0 && school.longitude === 0) &&
      school.geo_source !== "invalid_nulled" &&
      school.geo_source !== "regeocode_failed_manual_needed" &&
      isPointInGeometry([school.longitude, school.latitude], boundary.geometry)
    );
  });
}

function isPointInGeometry(point, geometry) {
  if (!geometry) return false;

  if (geometry.type === "Polygon") {
    return isPointInPolygon(point, geometry.coordinates);
  }

  if (geometry.type === "MultiPolygon") {
    return geometry.coordinates.some((polygon) => isPointInPolygon(point, polygon));
  }

  return false;
}

function isPointInPolygon(point, rings) {
  if (!rings?.length || !isPointInRing(point, rings[0])) {
    return false;
  }

  return !rings.slice(1).some((ring) => isPointInRing(point, ring));
}

function isPointInRing([x, y], ring) {
  let inside = false;

  for (let index = 0, previousIndex = ring.length - 1; index < ring.length; previousIndex = index++) {
    const [xi, yi] = ring[index];
    const [xj, yj] = ring[previousIndex];
    const intersects = yi > y !== yj > y && x < ((xj - xi) * (y - yi)) / (yj - yi) + xi;

    if (intersects) {
      inside = !inside;
    }
  }

  return inside;
}

function initializeSlicers() {
  countryOptions = getCountryOptions();
  selectedCountries = new Set(countryOptions.map((country) => country.slug));
  districtSelectionMode = "all";
  schoolSelectionMode = "all";
  refreshDistrictOptions();
  refreshSchoolOptions();
  renderCountryList();
  renderDistrictList();
  renderSchoolList();
  updateSlicerCounts();
}

function initializePlaceholderSlicers() {
  countryOptions = PRIORITY_COUNTRIES.map((slug) => ({
    slug,
    name: getCountryNameFromSlug(slug),
  }));
  selectedCountries = new Set(countryOptions.map((country) => country.slug));
  districtOptions = [];
  selectedDistricts = new Set();
  schoolOptions = [];
  selectedSchools = new Set();
  districtSelectionMode = "all";
  schoolSelectionMode = "all";
  renderCountryList();
  renderDistrictList();
  renderSchoolList();
  updateSlicerCounts();
}

function getCountryOptions() {
  const countries = new Map();

  allDistricts
    .filter((district) => district.boundary_level !== "ADM0")
    .filter(isPriorityCountry)
    .forEach((district) => {
      countries.set(district.country_slug, {
        slug: district.country_slug,
        name: district.country_name,
      });
    });

  return Array.from(countries.values()).sort((a, b) => a.name.localeCompare(b.name));
}

function getCountryNameFromSlug(slug) {
  return Object.values(ISO3_TO_COUNTRY).find((country) => country.slug === slug)?.name || slug;
}

function refreshDistrictOptions() {
  const previousSelectedDistricts = new Set(selectedDistricts);
  const districts = new Map();

  allDistricts
    .filter((district) => district.boundary_level !== "ADM0")
    .filter(isPriorityCountry)
    .filter((district) => selectedCountries.has(district.country_slug))
    .forEach((district) => {
      districts.set(getDistrictKey(district), {
        key: getDistrictKey(district),
        name: district.district_name,
        countrySlug: district.country_slug,
        countryName: district.country_name,
      });
    });

  districtOptions = Array.from(districts.values()).sort((a, b) => {
    const countryCompare = a.countryName.localeCompare(b.countryName);
    return countryCompare || a.name.localeCompare(b.name);
  });

  if (districtSelectionMode === "all") {
    selectedDistricts = new Set(districtOptions.map((district) => district.key));
  } else {
    selectedDistricts = new Set(
      districtOptions
        .filter((district) => previousSelectedDistricts.has(district.key))
        .map((district) => district.key)
    );
  }

  refreshSchoolOptions();
}

function refreshSchoolOptions() {
  const previousSelectedSchools = new Set(selectedSchools);
  const schools = new Map();

  allSchools
    .filter((school) => selectedCountries.has(school.country_slug))
    .filter(isSchoolInSelectedDistricts)
    .forEach((school) => {
      schools.set(school.school_id, {
        id: school.school_id,
        name: school.school_name,
        districtName: school.district_name,
        countryName: school.country_name,
      });
    });

  schoolOptions = Array.from(schools.values()).sort((a, b) => {
    const countryCompare = a.countryName.localeCompare(b.countryName);
    const districtCompare = countryCompare || a.districtName.localeCompare(b.districtName);
    return districtCompare || a.name.localeCompare(b.name);
  });

  if (schoolSelectionMode === "all") {
    selectedSchools = new Set(schoolOptions.map((school) => school.id));
    return;
  }

  selectedSchools = new Set(
    schoolOptions.filter((school) => previousSelectedSchools.has(school.id)).map((school) => school.id)
  );
}

function renderCountryList() {
  const searchTerm = countrySearch.value.trim().toLowerCase();
  const visibleCountries = countryOptions.filter((country) =>
    country.name.toLowerCase().includes(searchTerm)
  );

  countryList.innerHTML = visibleCountries
    .map((country) =>
      renderCheckboxRow({
        type: "country",
        value: country.slug,
        label: country.name,
        checked: selectedCountries.has(country.slug),
      })
    )
    .join("");
}

function renderDistrictList() {
  const searchTerm = districtSearch.value.trim().toLowerCase();
  const visibleDistricts = districtOptions.filter((district) =>
    `${district.name} ${district.countryName}`.toLowerCase().includes(searchTerm)
  );

  districtList.innerHTML = visibleDistricts
    .map((district) =>
      renderCheckboxRow({
        type: "district",
        value: district.key,
        label: district.name,
        meta: district.countryName,
        checked: selectedDistricts.has(district.key),
      })
    )
    .join("");
}

function renderSchoolList() {
  const searchTerm = schoolSearch.value.trim().toLowerCase();
  const visibleSchools = schoolOptions.filter((school) =>
    `${school.name} ${school.districtName} ${school.countryName}`.toLowerCase().includes(searchTerm)
  );

  schoolList.innerHTML = visibleSchools
    .map((school) =>
      renderCheckboxRow({
        type: "school",
        value: school.id,
        label: school.name,
        meta: `${school.districtName}, ${school.countryName}`,
        checked: selectedSchools.has(school.id),
      })
    )
    .join("");
}

function renderCheckboxRow({ type, value, label, meta = "", checked }) {
  return `
    <label class="check-row">
      <input type="checkbox" data-type="${type}" value="${escapeHtml(value)}" ${
        checked ? "checked" : ""
      } />
      <span>
        ${escapeHtml(label)}
        ${meta ? `<small>${escapeHtml(meta)}</small>` : ""}
      </span>
    </label>
  `;
}

function updateSlicerCounts() {
  countryButtonText.textContent = formatButtonText(
    selectedCountries.size,
    countryOptions.length,
    "Countries"
  );
  districtButtonText.textContent = formatButtonText(
    selectedDistricts.size,
    districtOptions.length,
    "Districts"
  );
  schoolButtonText.textContent = formatButtonText(
    selectedSchools.size,
    schoolOptions.length,
    "Schools"
  );
}

// Show/hide District and School filter chips based on active layer
function updateFilterVisibility() {
  const layer = getActiveLayer();
  const districtControl = document.getElementById("districtControl");
  const schoolControl = document.getElementById("schoolControl");
  // Country → hide both District and School chips
  // District → hide School chip only
  // School   → show both
  // Use .chip-hidden class (display:none !important) so flex on .filter-chip cannot override it
  districtControl?.classList.toggle("chip-hidden", layer === "country");
  schoolControl?.classList.toggle("chip-hidden", layer === "country" || layer === "district");
}

function getActiveLayer() {
  if (schoolLayerToggle.checked) return "school";
  if (districtLayerToggle.checked) return "district";
  return "country";
}

function getActiveLayerLabel() {
  const labels = {
    country: "Country",
    district: "District",
    school: "School",
  };

  return labels[getActiveLayer()];
}

function formatButtonText(selectedCount, totalCount, label) {
  if (totalCount === 0) return `No ${label}`;
  if (selectedCount === 0) return `No ${label}`;
  if (selectedCount === totalCount) return `All ${label}`;
  if (selectedCount === 1) return `1 ${label.slice(0, -1)}`;
  return `${selectedCount} of ${totalCount}`;
}

async function loadLocalDistrictGeojson() {
  setStatus("Loading local ADM2 district GeoJSON...");

  const response = await fetch(DISTRICT_GEOJSON_FILE);
  if (!response.ok) {
    throw new Error(`Could not load ${DISTRICT_GEOJSON_FILE}`);
  }

  const geojson = await response.json();
  const districts = geojson.features
    .filter((feature) => AFRICA_ISO3_CODES.includes(feature.properties.shapeGroup))
    .map(normalizeGeoBoundaryFeature);

  setStatus(`Loaded ${districts.length} local district boundaries.`);
  return districts;
}

function normalizeGeoBoundaryFeature(feature) {
  return normalizeStorageFeature(feature);
}

function normalizeStorageFeature(feature) {
  const country = ISO3_TO_COUNTRY[feature.properties.shapeGroup];
  const shapeType = feature.properties.shapeType || "ADM";

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
  };
}

function normalizeExternalDistrict(row) {
  return {
    ...row,
    program_count: Number(row.program_count || 0),
    beneficiary_count: Number(row.beneficiary_count || 0),
    risk_score: Number(row.risk_score || 0),
    kpis: normalizeKpis(row.kpis),
    geometry:
      typeof row.geometry === "string" ? JSON.parse(row.geometry) : row.geometry,
  };
}

function normalizeExternalSchool(row) {
  return {
    ...row,
    school_id: String(row.school_id),
    latitude: Number(row.latitude),
    longitude: Number(row.longitude),
    kpis: normalizeKpis(row.kpis),
  };
}

function normalizeKpis(kpis) {
  if (!kpis) return {};
  return typeof kpis === "string" ? JSON.parse(kpis) : kpis;
}

function renderDistricts() {
  const filtered = getVisibleBoundaryContext();
  const visibleSchools = getVisibleSchools();

  if (boundaryLayer) {
    boundaryLayer.remove();
  }

  const featureCollection = {
    type: "FeatureCollection",
    features: filtered.map((district) => ({
      type: "Feature",
      geometry: district.geometry,
      properties: district,
    })),
  };

  boundaryLayer = L.geoJSON(featureCollection, {
    style: districtStyle,
    onEachFeature: bindDistrictPopup,
  }).addTo(map);

  updateMapEmptyState(
    filtered.length + (schoolLayerToggle.checked ? visibleSchools.length : 0)
  );
  map.invalidateSize();
  renderSchools(visibleSchools);
  fitMapToActiveLayer(filtered, visibleSchools);
  renderLayerChart(filtered, visibleSchools);
  renderLegend(getLegendMetricSource(filtered, visibleSchools));
  setStatus(
    allDistricts.length === 0
      ? "Local demo data returned no boundary rows."
      : `Showing ${filtered.length} boundary context layer${
          filtered.length === 1 ? "" : "s"
        } and ${schoolLayerToggle.checked ? visibleSchools.length : 0} school point${
          visibleSchools.length === 1 ? "" : "s"
        }. KPI rows loaded: ${loadedKpiRowCount}. School rows loaded: ${loadedSchoolRowCount}. ${getKpiAvailabilityMessage(getLegendMetricSource(filtered, visibleSchools))}`
  );
}

function getVisibleBoundaryContext() {
  return allDistricts.filter((district) => {
    const isContextCountry = district.boundary_level === "ADM0";
    const districtKey = getDistrictKey(district);

    if (isContextCountry) {
      return true;
    }

    return (
      isPriorityCountry(district) &&
      selectedCountries.has(district.country_slug) &&
      selectedDistricts.has(districtKey)
    );
  });
}

function getLegendMetricSource(boundaries, schools) {
  const activeLayer = getActiveLayer();

  if (activeLayer === "school") {
    return schools;
  }

  return boundaries.filter((boundary) =>
    activeLayer === "country" ? boundary.boundary_level === "ADM0" : boundary.boundary_level !== "ADM0"
  );
}

function updateMapEmptyState(featureCount) {
  mapEmpty.hidden = featureCount > 0;
}

function getVisibleSchools() {
  return allSchools.filter((school) => {
    return (
      selectedCountries.has(school.country_slug) &&
      isSchoolInSelectedDistricts(school) &&
      selectedSchools.has(school.school_id)
    );
  });
}

function renderSchools(visibleSchools = getVisibleSchools()) {
  if (schoolLayer) {
    schoolLayer.remove();
  }

  if (!schoolLayerToggle.checked) {
    return;
  }

  const maxValue = Math.max(
    ...visibleSchools
      .filter((school) => hasMetricData(school, metricSelect.value))
      .map((school) => getDistrictMetric(school, metricSelect.value)),
    0
  );

  const featureCollection = {
    type: "FeatureCollection",
    features: visibleSchools.map((school) => ({
      type: "Feature",
      geometry: {
        type: "Point",
        coordinates: [school.longitude, school.latitude],
      },
      properties: school,
    })),
  };

  schoolLayer = L.geoJSON(featureCollection, {
    pointToLayer: (feature, latlng) =>
      L.circleMarker(latlng, getSchoolMarkerStyle(feature.properties, maxValue)),
    onEachFeature: bindSchoolPopup,
  }).addTo(map);
}

function fitMapToActiveLayer(boundaries, schools) {
  const activeLayer = getActiveLayer();
  let bounds = null;

  if (activeLayer === "school" && schools.length > 0) {
    bounds = L.latLngBounds(schools.map((school) => [school.latitude, school.longitude]));
  } else {
    const activeBoundaries = boundaries.filter((boundary) => {
      if (activeLayer === "country") {
        return (
          boundary.boundary_level === "ADM0" &&
          isPriorityCountry(boundary) &&
          selectedCountries.has(boundary.country_slug)
        );
      }

      return boundary.boundary_level !== "ADM0" && selectedDistricts.has(getDistrictKey(boundary));
    });

    if (activeBoundaries.length > 0) {
      bounds = L.geoJSON({
        type: "FeatureCollection",
        features: activeBoundaries.map((boundary) => ({
          type: "Feature",
          geometry: boundary.geometry,
          properties: boundary,
        })),
      }).getBounds();
    }
  }

  if (bounds?.isValid()) {
    map.fitBounds(bounds, { padding: [34, 34], maxZoom: activeLayer === "school" ? 9 : 8 });
  } else if (boundaryLayer?.getBounds().isValid()) {
    map.fitBounds(boundaryLayer.getBounds(), { padding: [28, 28] });
  }
}

function renderLayerChart(boundaries, schools) {
  const metric = metricSelect.value;
  const activeLayer = getActiveLayer();
  const rows = getLayerChartRows(boundaries, schools, metric, activeLayer);
  const maxValue = Math.max(...rows.map((row) => row.value), 0);

  chartTitle.textContent = getLayerChartTitle(activeLayer);
  chartMetricLabel.textContent = getMetricLabel(metric);
  countryChart.innerHTML = "";

  if (rows.length === 0) {
    countryChart.innerHTML = `<p class="empty-chart">No matching ${escapeHtml(activeLayer)} data.</p>`;
    return;
  }

  rows.forEach((row) => {
    const barWidth = maxValue > 0 ? Math.max((row.value / maxValue) * 100, 4) : 4;
    const item = document.createElement("div");
    item.className = "bar-row";
    item.innerHTML = `
      <div class="bar-meta">
        <span>${escapeHtml(row.label)}</span>
        <strong>${formatMetric(row.value, metric)}</strong>
      </div>
      <div class="bar-track" aria-hidden="true">
        <span class="bar-fill" style="width: ${barWidth}%"></span>
      </div>
    `;
    countryChart.appendChild(item);
  });
}

function getLayerChartRows(boundaries, schools, metric, activeLayer) {
  const source =
    activeLayer === "school"
      ? schools
      : boundaries.filter((boundary) =>
          activeLayer === "country"
            ? boundary.boundary_level === "ADM0" &&
              isPriorityCountry(boundary) &&
              selectedCountries.has(boundary.country_slug)
            : boundary.boundary_level !== "ADM0" && isPriorityCountry(boundary)
        );

  return source
    .filter((item) => hasMetricData(item, metric))
    .map((item) => ({
      label: getFeatureLabel(item, activeLayer),
      value: getDistrictMetric(item, metric),
    }))
    .sort((a, b) => b.value - a.value);
}

function getLayerChartTitle(activeLayer) {
  const titles = {
    country: selectedCountries.size === countryOptions.length ? "Selected Countries" : "Filtered Countries",
    district: "Selected Districts",
    school: "Selected Schools",
  };

  return titles[activeLayer];
}

function getFeatureLabel(feature, activeLayer) {
  if (activeLayer === "school") return feature.school_name;
  if (activeLayer === "country") return feature.country_name;
  return feature.district_name;
}

function districtStyle(feature) {
  const metric = metricSelect.value;
  const isPriority = isPriorityCountry(feature.properties);
  const isCountryContext = feature.properties.boundary_level === "ADM0";
  const hasData = hasMetricData(feature.properties, metric);
  const isSelectedPriorityCountry =
    isPriority && selectedCountries.has(feature.properties.country_slug);
  const isLayerColored = isCountryContext
    ? countryLayerToggle.checked
    : districtLayerToggle.checked;
  const isDataLayer =
    isLayerColored &&
    hasData &&
    (isCountryContext
      ? isSelectedPriorityCountry
      : isPriority && selectedDistricts.has(getDistrictKey(feature.properties)));
  const value = getDistrictMetric(feature.properties, metric);
  const isInteractiveLayer =
    (countryLayerToggle.checked && isCountryContext) ||
    (districtLayerToggle.checked && !isCountryContext);

  return {
    interactive: isInteractiveLayer,
    bubblingMouseEvents: false,
    color: isDataLayer ? "#3f2875" : "#a49da8",
    weight: isCountryContext ? (isDataLayer ? 1.2 : 1) : isDataLayer ? 1.4 : 0.7,
    opacity: isCountryContext ? (isDataLayer ? 0.8 : 0.5) : isDataLayer ? 0.92 : 0.45,
    fillColor: isDataLayer
      ? colorForValue(value, metric, feature.properties.boundary_level)
      : LEVEL_ZERO_COLOR,
    fillOpacity: isCountryContext ? (isDataLayer ? 0.66 : 0.12) : isDataLayer ? 0.72 : 0.28,
  };
}

function getSchoolMarkerStyle(school, maxValue) {
  const metric = metricSelect.value;
  const value = getDistrictMetric(school, metric);
  const hasData = hasMetricData(school, metric);
  const ratio = maxValue > 0 ? value / maxValue : 0;

  return {
    interactive: true,
    bubblingMouseEvents: false,
    radius: 1 + ratio * 4,
    color: hasData ? "#25123c" : "#918895",
    weight: hasData ? 1.4 : 1,
    opacity: hasData ? 0.92 : 0.65,
    fillColor: hasData && maxValue > 0 ? LEVEL_COLORS[getMetricLevel(value, maxValue) - 1] : LEVEL_ZERO_COLOR,
    fillOpacity: hasData ? 0.88 : 0.45,
    className: "school-marker",
  };
}

function isPriorityCountry(district) {
  return PRIORITY_COUNTRIES.includes(district.country_slug);
}

function colorForValue(value, metric, boundaryLevel = null) {
  const max = getMaxMetricValue(metric, allDistricts, boundaryLevel);
  if (max <= 0) return LEVEL_ZERO_COLOR;

  return LEVEL_COLORS[getMetricLevel(value, max) - 1];
}

function getMetricLevel(value, max) {
  if (max <= 0) return 1;

  const ratio = value / max;
  if (ratio < 0.2) return 1;
  if (ratio < 0.4) return 2;
  if (ratio < 0.6) return 3;
  if (ratio < 0.8) return 4;
  return 5;
}

function getMaxMetricValue(metric, districts, boundaryLevel = null) {
  const comparableBoundaries = getComparableMetricBoundaries(districts, metric, boundaryLevel);
  return Math.max(
    ...comparableBoundaries
      .map((district) => getDistrictMetric(district, metric))
      .filter((metricValue) => Number.isFinite(metricValue)),
    0
  );
}

function getComparableMetricBoundaries(boundaries, metric, boundaryLevel = null) {
  const priorityBoundaries = boundaries.filter(
    (boundary) =>
      isPriorityCountry(boundary) &&
      selectedCountries.has(boundary.country_slug) &&
      hasMetricData(boundary, metric)
  );

  if (boundaryLevel) {
    return priorityBoundaries.filter((boundary) => boundary.boundary_level === boundaryLevel);
  }

  const districtBoundaries = priorityBoundaries.filter(
    (boundary) => boundary.boundary_level !== "ADM0"
  );

  return districtBoundaries.length > 0
    ? districtBoundaries
    : priorityBoundaries.filter((boundary) => boundary.boundary_level === "ADM0");
}

function renderLegend(districts) {
  const metric = metricSelect.value;
  const label = getMetricLabel(metric);
  const yearLabel = getYearRangeLabel();
  const max = getMaxMetricValue(metric, districts);
  legendTitle.textContent = label;
  legendSubtitle.textContent = yearLabel;

  if (max <= 0) {
    legendRows.innerHTML = `
      <div class="legend-row legend-row-zero">
        <span class="swatch" style="background: ${LEVEL_ZERO_COLOR}"></span>
        <span class="legend-level">Level 0</span>
        <span class="legend-range">No data or not selected</span>
      </div>
    `;
    return;
  }

  const levelZeroRow = `
    <div class="legend-row legend-row-zero" style="grid-column: 1; grid-row: 1;">
      <span class="swatch" style="background: ${LEVEL_ZERO_COLOR}"></span>
      <span class="legend-level">Level 0</span>
      <span class="legend-range">No data or not selected</span>
    </div>
  `;

  const dataRows = LEVEL_COLORS.map((color, index) => {
    const level = index + 1;
    const start = (max * index) / 5;
    const end = (max * level) / 5;
    const rangeLabel = getLegendRangeLabel(start, end, level);
    const legendIndex = index + 1;
    const gridColumn = legendIndex < 3 ? 1 : 2;
    const gridRow = legendIndex < 3 ? legendIndex + 1 : legendIndex - 2;
    return `
      <div class="legend-row" style="grid-column: ${gridColumn}; grid-row: ${gridRow};">
        <span class="swatch" style="background: ${color}"></span>
        <span class="legend-level">Level ${level}</span>
        <span class="legend-range">${rangeLabel}</span>
      </div>
    `;
  }).join("");

  legendRows.innerHTML = levelZeroRow + dataRows;
}

function getLegendRangeLabel(start, end, level) {
  const roundedStart = formatRoundedLegendNumber(start);
  const roundedEnd = formatRoundedLegendNumber(end);

  if (level === 1) {
    return `0 - <=${roundedEnd}`;
  }

  return `>${roundedStart} - <=${roundedEnd}`;
}

function formatRoundedLegendNumber(value) {
  const rounded = Math.round(Number(value || 0) / 100) * 100;
  return formatNumber(rounded);
}

// ── Hover tooltip ────────────────────────────────────────────────────────────
// Positioning: native window mousemove — guaranteed pageX/pageY, no Leaflet.
// Show/hide: native addEventListener on each SVG element via getElement(),
// called after addTo(map) so the SVG node definitely exists.


function bindDistrictPopup(feature, layer) {
  const district = feature.properties;
  const metric = metricSelect.value;
  const value = getDistrictMetric(district, metric);
  layer.bindPopup(`
    <div class="district-popup">
      <strong>${escapeHtml(district.district_name)}, ${escapeHtml(district.country_name)}</strong>
      <dl>
        <dt>${escapeHtml(getMetricLabel(metric))}</dt><dd>${formatMetric(value, metric)}</dd>
        <dt>Programs</dt><dd>${formatNumber(district.program_count)}</dd>
        <dt>Beneficiaries</dt><dd>${formatNumber(district.beneficiary_count)}</dd>
      </dl>
    </div>
  `, { autoPan: false });
  const isCountryBoundary = district.boundary_level === "ADM0";
  const tooltipName = isCountryBoundary ? district.country_name : district.district_name;
  layer.bindTooltip(tooltipName, {
    sticky: true,
    direction: "top",
    className: "map-feature-tooltip",
  });

  layer.on({
    mouseover: (event) => {
      if (!isDistrictHoverActive(district)) {
        layer.closeTooltip();
        return;
      }
      updateInspectorForDistrict(district);
      layer.openTooltip(event.latlng);
      if (layer.bringToFront) layer.bringToFront();
    },
    mousemove: (event) => {
      if (isDistrictHoverActive(district)) layer.openTooltip(event.latlng);
    },
    mouseout: () => layer.closeTooltip(),
  });
}

function bindSchoolPopup(feature, layer) {
  const school = feature.properties;
  const metric = metricSelect.value;
  const value = getDistrictMetric(school, metric);

  layer.bindPopup(`
    <div class="district-popup">
      <strong>${escapeHtml(school.school_name)}</strong>
      <dl>
        <dt>District</dt><dd>${escapeHtml(school.district_name)}</dd>
        <dt>Country</dt><dd>${escapeHtml(school.country_name)}</dd>
        <dt>${escapeHtml(getMetricLabel(metric))}</dt><dd>${formatMetric(value, metric)}</dd>
        <dt>Location</dt><dd>${escapeHtml(school.geo_source || "GPS")}</dd>
      </dl>
    </div>
  `, { autoPan: false });
  const schoolName = school.school_name || school.name || school.item_name || "Unknown";
  layer.bindTooltip(schoolName, {
    sticky: true,
    direction: "top",
    className: "map-feature-tooltip",
  });

  layer.on({
    mouseover: (event) => {
      if (!schoolLayerToggle.checked) {
        layer.closeTooltip();
        return;
      }
      updateInspectorForSchool(school);
      layer.openTooltip(event.latlng);
      if (layer.bringToFront) layer.bringToFront();
    },
    mousemove: (event) => {
      if (schoolLayerToggle.checked) layer.openTooltip(event.latlng);
    },
    mouseout: () => layer.closeTooltip(),
  });
}

function isDistrictHoverActive(district) {
  const activeLayer = getActiveLayer();
  const isCountryBoundary = district.boundary_level === "ADM0";

  if (activeLayer === "country") {
    return (
      isCountryBoundary &&
      isPriorityCountry(district) &&
      selectedCountries.has(district.country_slug)
    );
  }

  if (activeLayer === "district") {
    return (
      !isCountryBoundary &&
      isPriorityCountry(district) &&
      selectedCountries.has(district.country_slug) &&
      selectedDistricts.has(getDistrictKey(district))
    );
  }

  return false;
}

function updateInspectorForDistrict(district) {
  const metric = metricSelect.value;
  const value = getDistrictMetric(district, metric);

  inspectorType.textContent = district.boundary_level === "ADM0" ? "Country" : "District";
  inspectorTitle.textContent =
    district.boundary_level === "ADM0"
      ? district.country_name
      : `${district.district_name}, ${district.country_name}`;

  const rows =
    district.boundary_level === "ADM0"
      ? [
          ["Country", district.country_name],
          [getYearRangeLabel(), formatMetric(value, metric)],
          ["Programs", formatNumber(district.program_count)],
          ["Beneficiaries", formatNumber(district.beneficiary_count)],
        ]
      : [
          ["Country", district.country_name],
          ["District", district.district_name],
          [getYearRangeLabel(), formatMetric(value, metric)],
          ["Programs", formatNumber(district.program_count)],
          ["Beneficiaries", formatNumber(district.beneficiary_count)],
        ];

  inspectorDetails.innerHTML = renderInspectorRows(rows);
}

function updateInspectorForSchool(school) {
  const metric = metricSelect.value;
  const value = getDistrictMetric(school, metric);

  inspectorType.textContent = "School";
  inspectorTitle.textContent = school.school_name;
  inspectorDetails.innerHTML = renderInspectorRows([
    ["Country", school.country_name],
    ["District", school.district_name],
    ["Province", school.province || "Not listed"],
    [getYearRangeLabel(), formatMetric(value, metric)],
    ["GPS Source", school.geo_source || "GPS"],
  ]);
}

function renderInspectorRows(rows) {
  return rows
    .map(
      ([label, value]) => `
        <dt>${escapeHtml(label)}</dt>
        <dd>${escapeHtml(value)}</dd>
      `
    )
    .join("");
}

function setStatus(message) {
  statusText.textContent = message;
}

function formatNumber(value) {
  return new Intl.NumberFormat().format(Number(value || 0));
}

function formatMetric(value, metric) {
  if (metric === "risk_score") {
    return Number(value || 0).toFixed(1);
  }

  return formatNumber(value);
}

function getMetricLabel(metric) {
  return metricSelect.querySelector(`option[value="${metric}"]`).textContent;
}

function getDistrictMetric(district, metric) {
  const selectedYears = getSelectedYears();
  const yearlyValues = selectedYears
    .map((year) => getRawDistrictMetric(district, metric, year, { yearlyOnly: true }))
    .filter((value) => value !== undefined && value !== null);

  if (yearlyValues.length > 0) {
    return yearlyValues.reduce((total, value) => total + Number(value || 0), 0);
  }

  const value = getRawDistrictMetric(district, metric, selectedYears[0], { yearlyOnly: false });
  return Number(value || 0);
}

function hasMetricData(district, metric) {
  if (!district) return false;

  const hasSelectedYearValue = getSelectedYears().some((year) => {
    const value = getRawDistrictMetric(district, metric, year, { yearlyOnly: true });
    return value !== undefined && value !== null && value !== "";
  });

  if (hasSelectedYearValue) {
    return true;
  }

  if (district.kpis && Object.hasOwn(district.kpis, metric)) {
    return true;
  }

  return Object.hasOwn(district, metric);
}

function getRawDistrictMetric(district, metric, year, options = {}) {
  if (!district.kpis) {
    return district[metric];
  }

  if (district.kpis.years && district.kpis.years[year]?.[metric] !== undefined) {
    return district.kpis.years[year][metric];
  }

  if (district.kpis[year] && district.kpis[year][metric] !== undefined) {
    return district.kpis[year][metric];
  }

  if (options.yearlyOnly) {
    return undefined;
  }

  if (Object.hasOwn(district.kpis, metric)) {
    return district.kpis[metric];
  }

  return district[metric];
}

function populateKpiOptions() {
  metricSelect.innerHTML = KPI_DEFINITIONS.map(
    (kpi) => `<option value="${kpi.key}">${escapeHtml(kpi.label)}</option>`
  ).join("");
}

function initializeYearRange() {
  yearStart.min = YEARS[0];
  yearStart.max = YEARS[YEARS.length - 1];
  yearEnd.min = YEARS[0];
  yearEnd.max = YEARS[YEARS.length - 1];
  yearStart.value = YEARS[0];
  yearEnd.value = YEARS[YEARS.length - 1];
  updateYearRangeText();
}

function getSelectedYearBounds() {
  const start = Number(yearStart.value);
  const end = Number(yearEnd.value);
  return {
    start: Math.min(start, end),
    end: Math.max(start, end),
  };
}

function getSelectedYears() {
  const { start, end } = getSelectedYearBounds();
  return YEARS.filter((year) => year >= start && year <= end).map(String);
}

function getYearRangeLabel() {
  const { start, end } = getSelectedYearBounds();
  return start === end ? String(start) : `${start} - ${end}`;
}

function updateYearRangeText() {
  yearRangeText.textContent = getYearRangeLabel();
}

function getKpiAvailabilityMessage(districts) {
  const metric = metricSelect.value;
  const yearLabel = getYearRangeLabel();
  const matchingValues = getComparableMetricBoundaries(districts, metric)
    .map((district) => getDistrictMetric(district, metric))
    .filter((value) => value !== undefined && value !== null);

  if (matchingValues.length === 0) {
    return `No KPI values found for ${getMetricLabel(metric)} in ${yearLabel}.`;
  }

  return `${matchingValues.length} KPI value${
    matchingValues.length === 1 ? "" : "s"
  } found for ${yearLabel}.`;
}

function escapeHtml(value) {
  return String(value).replace(/[&<>"']/g, (character) => {
    const entities = {
      "&": "&amp;",
      "<": "&lt;",
      ">": "&gt;",
      '"': "&quot;",
      "'": "&#039;",
    };
    return entities[character];
  });
}

function closeMapIntro() {
  if (!mapIntroOverlay) return;
  mapIntroOverlay.hidden = true;
  map.invalidateSize();
}

countrySearch.addEventListener("input", renderCountryList);
districtSearch.addEventListener("input", renderDistrictList);
schoolSearch.addEventListener("input", renderSchoolList);
metricSelect.addEventListener("change", renderDistricts);
yearStart.addEventListener("input", () => {
  updateYearRangeText();
  renderDistricts();
});
yearEnd.addEventListener("input", () => {
  updateYearRangeText();
  renderDistricts();
});
// Listen for layer change via both change event and label click
// (pointer-events:none on hidden radio inputs can suppress change in some browsers)
countryLayerToggle.addEventListener("change", handleLayerChange);
districtLayerToggle.addEventListener("change", handleLayerChange);
schoolLayerToggle.addEventListener("change", handleLayerChange);
document.querySelectorAll(".seg-opt").forEach((label) => {
  label.addEventListener("click", () => {
    const input = label.querySelector("input[type='radio']");
    if (input) input.checked = true;
    handleLayerChange();
  });
});
mapIntroClose?.addEventListener("click", closeMapIntro);
mapIntroExplore?.addEventListener("click", closeMapIntro);
mapIntroOverlay?.addEventListener("click", (event) => {
  if (event.target === mapIntroOverlay) {
    closeMapIntro();
  }
});
document.addEventListener("keydown", (event) => {
  if (event.key === "Escape" && mapIntroOverlay && !mapIntroOverlay.hidden) {
    closeMapIntro();
  }
});
countryToggle.addEventListener("click", () =>
  toggleMenu(countryMenu, districtMenu, schoolMenu)
);
districtToggle.addEventListener("click", () =>
  toggleMenu(districtMenu, countryMenu, schoolMenu)
);
schoolToggle.addEventListener("click", () =>
  toggleMenu(schoolMenu, countryMenu, districtMenu)
);
document.addEventListener("click", (event) => {
  if (!event.target.closest(".slicer")) {
    closeSlicerMenus();
  }
});
countryAll.addEventListener("click", () => {
  selectedCountries = new Set(countryOptions.map((country) => country.slug));
  districtSelectionMode = "all";
  schoolSelectionMode = "all";
  refreshDistrictOptions();
  refreshSchoolOptions();
  renderCountryList();
  renderDistrictList();
  renderSchoolList();
  updateSlicerCounts();
  renderDistricts();
});
countryNone.addEventListener("click", () => {
  selectedCountries = new Set();
  selectedDistricts = new Set();
  selectedSchools = new Set();
  districtSelectionMode = "none";
  schoolSelectionMode = "none";
  refreshDistrictOptions();
  refreshSchoolOptions();
  renderCountryList();
  renderDistrictList();
  renderSchoolList();
  updateSlicerCounts();
  renderDistricts();
});
districtAll.addEventListener("click", () => {
  districtSelectionMode = "all";
  schoolSelectionMode = "all";
  selectedDistricts = new Set(districtOptions.map((district) => district.key));
  refreshSchoolOptions();
  renderDistrictList();
  renderSchoolList();
  updateSlicerCounts();
  renderDistricts();
});
districtNone.addEventListener("click", () => {
  districtSelectionMode = "none";
  schoolSelectionMode = "none";
  selectedDistricts = new Set();
  selectedSchools = new Set();
  refreshSchoolOptions();
  renderDistrictList();
  renderSchoolList();
  updateSlicerCounts();
  renderDistricts();
});
schoolAll.addEventListener("click", () => {
  schoolSelectionMode = "all";
  selectedSchools = new Set(schoolOptions.map((school) => school.id));
  renderSchoolList();
  updateSlicerCounts();
  renderDistricts();
});
schoolNone.addEventListener("click", () => {
  schoolSelectionMode = "none";
  selectedSchools = new Set();
  renderSchoolList();
  updateSlicerCounts();
  renderDistricts();
});
countryList.addEventListener("change", (event) => {
  if (!event.target.matches('input[data-type="country"]')) return;

  if (event.target.checked) {
    selectedCountries.add(event.target.value);
  } else {
    selectedCountries.delete(event.target.value);
  }

  districtSelectionMode = "all";
  schoolSelectionMode = "all";
  refreshDistrictOptions();
  refreshSchoolOptions();
  renderCountryList();
  renderDistrictList();
  renderSchoolList();
  updateSlicerCounts();
  renderDistricts();
});
districtList.addEventListener("change", (event) => {
  if (!event.target.matches('input[data-type="district"]')) return;

  if (event.target.checked) {
    selectedDistricts.add(event.target.value);
  } else {
    selectedDistricts.delete(event.target.value);
  }
  districtSelectionMode =
    selectedDistricts.size === districtOptions.length ? "all" : "custom";
  schoolSelectionMode = "all";
  refreshSchoolOptions();

  renderDistrictList();
  renderSchoolList();
  updateSlicerCounts();
  renderDistricts();
});
schoolList.addEventListener("change", (event) => {
  if (!event.target.matches('input[data-type="school"]')) return;

  if (event.target.checked) {
    selectedSchools.add(event.target.value);
  } else {
    selectedSchools.delete(event.target.value);
  }
  schoolSelectionMode = selectedSchools.size === schoolOptions.length ? "all" : "custom";

  renderSchoolList();
  updateSlicerCounts();
  renderDistricts();
});

function toggleMenu(menuToToggle, ...menusToClose) {
  menusToClose.forEach((menu) => {
    menu.hidden = true;
  });
  const willOpen = menuToToggle.hidden;
  menuToToggle.hidden = !willOpen;
  if (willOpen) {
    // Position fixed relative to the toggle button
    const btn = menuToToggle.previousElementSibling;
    if (btn) {
      const rect = btn.getBoundingClientRect();
      menuToToggle.style.top = (rect.bottom + 6) + "px";
      menuToToggle.style.left = rect.left + "px";
    }
  }
}

function closeSlicerMenus() {
  countryMenu.hidden = true;
  districtMenu.hidden = true;
  schoolMenu.hidden = true;
}

function handleLayerChange() {
  // Show/hide District and School chips based on the active layer.
  // District selection data is preserved as-is underneath.
  updateFilterVisibility();
  renderDistricts();
}

Promise.all([loadDistricts(), loadSchools()])
  .then(([districts, schools]) => {
    allDistricts = districts;
    allSchools = schools;
    loadedSchoolRowCount = schools.length;
    initializeSlicers();
    renderDistricts();
  })
  .catch((error) => {
    console.error(error);
    allDistricts = sampleDistricts;
    allSchools = [];
    loadedSchoolRowCount = 0;
    initializeSlicers();
    setStatus("Boundary data could not load, so sample data is shown.");
    renderDistricts();
  });


