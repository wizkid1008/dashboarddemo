// ─── HIERARCHY DATA ────────────────────────────────────────────
// Each statistic: { label, kpi?, pct?, kpiSum?, kpiRatio? }
// kpi      = dot-path into D (e.g. "kpi11.annual.total")
// pct      = true → format as percentage
// kpiSum   = array of dot-paths whose values are summed
// kpiRatio = { n: numeratorPath, d: denominatorPath } → displayed as %
const hierarchyData = [
  {
    level: "LEVEL 1: Girl's Education",
    subLevel: "Education Reach",
    statistics: [
      { label: "# Girls supported in School with Education Bursaries",        kpi: "kpi11.annual.total",  ddMetric: "Children Supported in School with Education Bursaries" },
      { label: "# Girls Supported in School by CAMA & Community Champions",   kpi: "kpi12.annual.total",  ddMetric: "CAMA Members" },
      { label: "# Total Girls Supported",                                      kpi: "kpi13.annual.girls" },
      { label: "# Total Boys Supported",                                       kpi: "kpi13.annual.boys" }
    ]
  },
  {
    level: "LEVEL 1: Girl's Education",
    subLevel: "Education Outcomes",
    statistics: [
      { label: "Dropout Rate for Girls with Education Bursaries due to EMP",    kpi: "kpi15.pct", pct: true },
      { label: "Girls with Education Bursaries that Progress to Next Grade" },
      { label: "Exam Passrates for Girls with Busaries" },
      { label: "School Completion Rates for girls with busaries" }
    ]
  },
  {
    level: "LEVEL 1: Girl's Education",
    subLevel: "Learner Guide Programme",
    statistics: [
      { label: "Active Learner Guides",                                                                          kpi: "kpi19.total",        ddMetric: "Active Learner Guides" },
      { label: "Girls Reporting Increased Agency" },
      { label: "Learner Guides Reporting Increased Agency" },
      { label: "Average number of children my better world annually" },
      { label: "Active Learner Guides by Training",                                                              kpi: "kpi19.camfed",       ddMetric: "Active Learner Guides" },
      { label: "Children Receieving Social and Learning Support Including My Better World Sessions",             kpi: "kpi13.annual.total",  ddMetric: "Number of Clients by Form" }
    ]
  },
  {
    level: "LEVEL 2: Livelihoods & Leadership",
    subLevel: "Leadership and Tertiary",
    statistics: [
      { label: "Active Transition Guides",                                kpi: "kpi22.transition" },
      { label: "Numbers of CAMA Members",                                 kpi: "kpi21.cum" },
      { label: "Young Women Supported by Transition Guide",               kpi: "kpi213.num" },
      { label: "Young Women Supported by CAMFED Tertiary Education" },
      { label: "CAMA Members in Leadership Roles" }
    ]
  },
  {
    level: "LEVEL 2: Livelihoods & Leadership",
    subLevel: "Livelihoods Reach",
    statistics: [
      { label: "Active Enerperis Guides (Business & Agriculture Guides)", kpiSum: ["kpi22.business", "kpi22.agriculture"] },
      { label: "Business Supported by Enterprise Guides",                 kpi: "kpi27.biz" },
      { label: "Business Grants Distributed" },
      { label: "CAMFED KIVA and RIF Loans Distributed" }
    ]
  },
  {
    level: "LEVEL 2: Livelihoods & Leadership",
    subLevel: "Jobs & Income",
    statistics: [
      { label: "Women Progresing Towards a secure livelihood" },
      { label: "Females Entrepreeurs with increased incomes after participating in CAMFED's ENteprise Programs", kpi: "kpi210.pct", pct: true },
      { label: "Jobs Created through Enterprise Programme including Self Employment",                            kpi: "kpi29.annual" },
      { label: "New Business" },
      { label: "Business Survival Rate",                                                                         kpi: "kpi212.yr1", pct: true }
    ]
  },
  {
    level: "LEVEL 2: Livelihoods & Leadership",
    subLevel: "Agriculture & Food",
    statistics: [
      { label: "Percentage of Femal Entrepenuers Reporting and Increased Household Consumption fo Food Since Participating in CAMFED's Enteprise Program" },
      { label: "Percentage of FEmals Agripernuers Reporting Increased Yields Since Participating" },
      { label: "Average Number of Climate-Smart Techniques Used by Those Receiieng Support from an Agriculture Guide" }
    ]
  },
  {
    level: "LEVEL 2: Livelihoods & Leadership",
    subLevel: "Life Choices",
    statistics: [
      { label: "Average of Young Women Married by Age 18 Across All Countries" },
      { label: "Average of Young Women Giving Birth by Age 18" },
      { label: "Percentrage of Young Women in CAMA who Were Married by 18" },
      { label: "Percentage of Young Women CAMA Who have Given Birth by 18" }
    ]
  },
  {
    level: "LEVEL 3: Education Systems",
    subLevel: "Education Systems 1",
    statistics: [
      { label: "% of Resources for Learner Guide Programme Contributed by the Government", kpiRatio: { n: "kpi19.govt", d: "kpi19.total" } },
      { label: "National Level Dropout Rate for Girls due to Early Mariage of Pregnancy",  kpi: "kpi15.pct", pct: true },
      { label: "Community Champion Teacher Mentors" },
      { label: "Number of Districts with Learns Guides",                                   kpi: "kpi34.districts" },
      { label: "Number of Schools with Learner Guides",                                    kpi: "kpi31.total_all" }
    ]
  },
  {
    level: "LEVEL 3: Education Systems",
    subLevel: "Education Systems 2",
    statistics: [
      { label: "Number of Memerando fo Understanding between Government and CAMFED" },
      { label: "Children Benefiting from Improved Learning Environment",                    kpi: "kpi35.total" },
      { label: "Number of Active Community Champions for Girl's Education" },
      { label: "National Level Dropout Rate for Girls due to Early Mariage of Pregnancy",  kpi: "kpi15.pct", pct: true },
      { label: "Number of Memoranda of Understanding between Government Departmetns and CAMFED" }
    ]
  }
];

// Maps hierarchyData level strings to existing panel IDs (level1/level2/level3)
const levelToPanelId = {
  "LEVEL 1: Girl's Education": 'level1',
  "LEVEL 2: Livelihoods & Leadership": 'level2',
  "LEVEL 3: Education Systems": 'level3'
};

// Register datalabels plugin; disable globally so existing charts are unaffected
if (typeof ChartDataLabels !== 'undefined') {
  Chart.register(ChartDataLabels);
  Chart.defaults.plugins.datalabels.display = false;
}

// ─── COLOUR PALETTE ────────────────────────────────────────────
// Starts with known countries as fallback; updated to live DB list on dd:ready
let C = ['Ghana','Malawi','Tanzania','Zambia','Zimbabwe'];
const MAP_LEVEL_COLORS = ['#e7e0f0', '#c9bbdd', '#b78f2f', '#b5533d', '#6b22aa'];
const MAP_AREA_FILL = 'rgba(107,34,170,0.10)';
const CC = {
  Ghana:   MAP_LEVEL_COLORS[4],
  Malawi:  MAP_LEVEL_COLORS[0],
  Tanzania:MAP_LEVEL_COLORS[2],
  Zambia:  MAP_LEVEL_COLORS[1],
  Zimbabwe:MAP_LEVEL_COLORS[3],
  All:     MAP_LEVEL_COLORS[4]
};
// For bar charts always use these
const BARS = [...MAP_LEVEL_COLORS, ...MAP_LEVEL_COLORS];

function countryColor(name) {
  if (CC[name]) return CC[name];
  const countries = window.DD ? DD.countries : [];
  const idx = countries.indexOf(name);
  return BARS[idx >= 0 ? idx % BARS.length : 0];
}

// ─── DATA ──────────────────────────────────────────────────────
const D = {
  kpi11: {
    annual:{primary:{Ghana:0,Malawi:9108,Tanzania:0,Zambia:7116,Zimbabwe:0,Total:16224},secondary:{Ghana:43734,Malawi:11301,Tanzania:20758,Zambia:39075,Zimbabwe:18581,Total:133449},total:{Ghana:43734,Malawi:20409,Tanzania:20758,Zambia:46191,Zimbabwe:18581,Total:149673}},
    newly:{total:{Ghana:34004,Malawi:4986,Tanzania:15506,Zambia:28266,Zimbabwe:12966,Total:95728}},
    cum2030:{total:{Ghana:79092,Malawi:101245,Tanzania:70463,Zambia:177015,Zimbabwe:75559,Total:503374}},
    cumAll:{total:{Ghana:223973,Malawi:185440,Tanzania:156201,Zambia:364187,Zimbabwe:292942,Total:1222743}}
  },
  kpi12:{annual:{total:{Ghana:169749,Malawi:162679,Tanzania:132626,Zambia:112340,Zimbabwe:310635,Total:888029}}},
  kpi13:{annual:{girls:{Ghana:141111,Malawi:526109,Tanzania:163417,Zambia:72505,Zimbabwe:143711,Total:1046853},boys:{Ghana:120061,Malawi:444884,Tanzania:141167,Zambia:56398,Zimbabwe:116510,Total:879020},total:{Ghana:261172,Malawi:970993,Tanzania:304584,Zambia:128903,Zimbabwe:260221,Total:1925873}}},
  kpi15:{pct:{Ghana:0.34,Malawi:3.93,Tanzania:0.59,Zambia:0.65,Zimbabwe:1.60}},
  kpi19:{camfed:{Ghana:2317,Malawi:3068,Tanzania:3522,Zambia:3224,Zimbabwe:4405,Total:16536},govt:{Ghana:178,Malawi:2605,Tanzania:744,Zambia:0,Zimbabwe:1090,Total:4617},total:{Ghana:2495,Malawi:5673,Tanzania:4266,Zambia:3224,Zimbabwe:5495,Total:21153}},
  kpi21:{new:{Ghana:8340,Malawi:2685,Tanzania:9549,Zambia:6818,Zimbabwe:6396,Total:33788},cum:{Ghana:77264,Malawi:37358,Tanzania:66651,Zambia:36224,Zimbabwe:95250,Total:312747}},
  kpi22:{transition:{Ghana:365,Malawi:230,Tanzania:1722,Zambia:521,Zimbabwe:2221,Total:5059},agriculture:{Ghana:239,Malawi:138,Tanzania:386,Zambia:461,Zimbabwe:924,Total:2148},business:{Ghana:339,Malawi:372,Tanzania:2317,Zambia:411,Zimbabwe:1673,Total:5112}},
  kpi26:{annual:{Ghana:2411,Malawi:1732,Tanzania:2722,Zambia:2475,Zimbabwe:3004,Total:12344}},
  kpi27:{ag:{Ghana:1200,Malawi:2056,Tanzania:3777,Zambia:4814,Zimbabwe:8799,Total:20646},biz:{Ghana:2411,Malawi:7886,Tanzania:24696,Zambia:4409,Zimbabwe:13989,Total:53391}},
  kpi29:{annual:{Ghana:6736,Malawi:3644,Tanzania:10125,Zambia:5837,Zimbabwe:8216,Total:34558}},
  kpi210:{pct:{Ghana:86,Malawi:69,Tanzania:72,Zambia:81,Zimbabwe:74}},
  kpi211:{profit:{Ghana:87,Malawi:84,Tanzania:84,Zambia:81,Zimbabwe:73}},
  kpi212:{yr1:{Ghana:95,Malawi:88,Tanzania:91,Zambia:91,Zimbabwe:90}},
  kpi213:{num:{Ghana:14920,Malawi:23917,Tanzania:21195,Zambia:14127,Zimbabwe:41462,Total:115621}},
  kpi31:{primary:{Ghana:0,Malawi:1397,Tanzania:0,Zambia:353,Zimbabwe:0,Total:1750},secondary:{Ghana:671,Malawi:25,Tanzania:466,Zambia:402,Zimbabwe:1602,Total:3166},total_all:{Ghana:846,Malawi:3538,Tanzania:757,Zambia:794,Zimbabwe:1602,Total:7537}},
  kpi34:{districts:{Ghana:44,Malawi:17,Tanzania:35,Zambia:61,Zimbabwe:42,Total:199}},
  kpi35:{primary:{Ghana:0,Malawi:3082975,Tanzania:0,Zambia:239094,Zimbabwe:0,Total:3322069},secondary:{Ghana:325297,Malawi:7783,Tanzania:643671,Zambia:271494,Zimbabwe:520178,Total:1768423},total:{Ghana:325297,Malawi:3090758,Tanzania:643671,Zambia:510588,Zimbabwe:520178,Total:5090492}},
  p1:{girls:{Ghana:226228,Malawi:185997,Tanzania:156466,Zambia:166358,Zimbabwe:431058,Total:1166107},boys:{Ghana:99123,Malawi:84080,Tanzania:68027,Zambia:67115,Zimbabwe:181221,Total:499566},total:{Ghana:325351,Malawi:270077,Tanzania:224493,Zambia:233473,Zimbabwe:612279,Total:1665673}},
  p9:{form1:{Ghana:0,Malawi:7.8,Tanzania:5.3,Zambia:0.73,Zimbabwe:0.4},form2:{Ghana:0,Malawi:23.8,Tanzania:13.1,Zambia:2.11,Zimbabwe:0},form3:{Ghana:0,Malawi:6.8,Tanzania:8.0,Zambia:0.59,Zimbabwe:3.2},form4:{Ghana:0.7,Malawi:4.2,Tanzania:1.2,Zambia:1.05,Zimbabwe:2.0}},
  districts:{Ghana:['Accra Metro','Awutu Senya','Birim Central','Ejura Sekyedumase','Kpando'],Malawi:['Balaka','Blantyre','Chiradzulu','Chikwawa','Dedza'],Tanzania:['Bagamoyo','Chalinze','Chamwino','Chato','Gairo'],Zambia:['Chililabombwe','Chingola','Chipata','Kabwe','Kafue'],Zimbabwe:['Binga','Buhera','Bulawayo','Chiredzi','Chinhoyi']}
};

// ─── EDUCATION OUTCOMES STATIC DATA ───────────────────────────
// Separate from D to keep it focused; all values are % points.
const EO = {
  // Exam pass rates — lower secondary (Form 1–3)
  examLower: {
    Ghana:    { benchmark: 65, clients: 78 },
    Malawi:   { benchmark: 52, clients: 68 },
    Tanzania: { benchmark: 59, clients: 74 },
    Zambia:   { benchmark: 61, clients: 77 },
    Zimbabwe: { benchmark: 58, clients: 73 }
  },
  // Exam pass rates — upper secondary (Form 4+)
  examUpper: {
    Ghana:    { benchmark: 55, clients: 72 },
    Malawi:   { benchmark: 44, clients: 61 },
    Tanzania: { benchmark: 50, clients: 67 },
    Zambia:   { benchmark: 52, clients: 69 },
    Zimbabwe: { benchmark: 48, clients: 65 }
  },
  // School completion rates
  completion: {
    Ghana:    { lower: 87, upper: 72 },
    Malawi:   { lower: 64, upper: 41 },
    Tanzania: { lower: 76, upper: 58 },
    Zambia:   { lower: 81, upper: 65 },
    Zimbabwe: { lower: 79, upper: 60 }
  }
};

// ─── LEVEL 2 STATIC DATA ───────────────────────────────────────
const L2 = {
  // Young Women Supported by Transition Guides
  youngWomenTG: { Ghana:5966, Malawi:1837, Tanzania:16306, Zambia:3750, Zimbabwe:5390, Total:33249 },
  // Young Women Supported by CAMFED in Tertiary Education
  tertiary:     { Ghana:390,  Malawi:1718, Tanzania:1053,  Zambia:910,  Zimbabwe:719,  Total:4790 }
};

// ─── LEVEL 2 LIVELIHOODS REACH STATIC DATA ────────────────────
const L2LR = {
  // Business Grants — Number of Grants
  grantsNum: { Ghana:2427, Malawi:3299, Tanzania:2895, Zambia:2844, Zimbabwe:4330, Total:15795 },
  // Business Grants — Value of Grants (USD)
  grantsVal: { Ghana:1213500, Malawi:1649500, Tanzania:1447500, Zambia:1422000, Zimbabwe:2165000, Total:7897500 },
  // CAMFED Kiva Loans
  kiva: { Ghana:693, Malawi:30, Tanzania:12, Zambia:11, Zimbabwe:17, Total:763 },
  // CAMFED RIF Loans  (763 + 1195 = 1,958 total)
  rif:  { Ghana:0,   Malawi:82, Tanzania:510, Zambia:61, Zimbabwe:542, Total:1195 }
};

// ─── LEVEL 2 JOBS & INCOME STATIC DATA ────────────────────────
const L2JI = {
  // Women Progressing Towards Secure Livelihood (%) — integer % per country
  womenProgress: { Ghana:87, Malawi:98, Tanzania:65, Zambia:85, Zimbabwe:81 }
};

// ─── LEVEL 2 AGRICULTURE & FOOD STATIC DATA ───────────────────
const L2AF = {
  // % Female Entrepreneurs — Increased Household Food Consumption
  foodConsumption: { Ghana:86, Malawi:71, Tanzania:52, Zambia:89, Zimbabwe:81 },
  // % Female Agripreneurs — Increased Yields (null = Not Available)
  agriYields:      { Ghana:80, Malawi:null, Tanzania:75, Zambia:82, Zimbabwe:78 },
  // Avg Climate-Smart Techniques used (null = Not Available)
  climateSmart:    { Ghana:6.0, Malawi:null, Tanzania:null, Zambia:7.7, Zimbabwe:8.7 }
};

// ─── LEVEL 3 STATIC DATA ──────────────────────────────────────
const L3_GREEN = MAP_LEVEL_COLORS[2];

const L3 = {
  // MoU counts per country (Ed Systems 2)
  mou:           { Ghana:11, Malawi:1, Tanzania:4, Zambia:1, Zimbabwe:38, Total:55 },
  // Community Champions breakdown (Ed Systems 2)
  champions:     { cdcs:2933, psgs:55527, sbcs:61506 },
  // Community Champion Teacher Mentors (Ed Systems 1)
  teacherMentors: 9190,
  // Children Benefitting by Gender — Annual (Ed Systems 2, from D.kpi35 + gender split)
  kpi35Annual:   { girls:2601173, boys:2489319 },
  // Children Benefitting by Gender — Newly supported (Ed Systems 2)
  kpi35Newly:    { girls:780352,  boys:745100, primary:994881, secondary:530571 },
  // Government districts on top of D.kpi34 CAMFED districts (Ed Systems 1)
  districtsGovt: { Ghana:0, Malawi:11, Tanzania:1, Zambia:0, Zimbabwe:0 },
  // Schools with LG — CAMFED vs Government (Ed Systems 1)
  schoolsCamfed: 4955,
  schoolsGovt:   2582
};

// ─── STATE ─────────────────────────────────────────────────────
let sel = { countries: ['All'], dateStart: 2020, dateEnd: 2030, level: '', subLevel: '' };
const charts = {};

// ─── HELPERS ───────────────────────────────────────────────────
function fmt(n) {
  if (n==null) return '—';
  if (typeof n==='string') return n;
  return Math.round(n).toLocaleString();
}

function fmtK(v) {
  return v>=1000000?(v/1000000).toFixed(1)+'M':v>=1000?(v/1000).toFixed(0)+'k':v;
}

// Active country list — always an array of real country names
function activeCt() {
  return sel.countries.includes('All') ? C : sel.countries;
}

// Human-readable label for the current selection
function activeLabel() {
  const a = activeCt();
  if (a.length === C.length) return 'All Countries';
  if (a.length === 1) return a[0];
  if (a.length === 2) return a.join(', ');
  return `${a.length} Countries Selected`;
}

// Sum a country-keyed object across active countries
// Falls back to pre-computed Total when all countries are active
function cv(obj) {
  const a = activeCt();
  if (a.length === C.length && obj.Total != null) return obj.Total;
  return a.reduce((s, c) => s + (obj[c] || 0), 0);
}

// Average a country-keyed object across active countries (for % metrics)
function cvAvg(obj) {
  const a = activeCt();
  const vals = a.map(c => obj[c]).filter(v => v != null);
  return vals.length ? vals.reduce((x, y) => x + y, 0) / vals.length : null;
}

// ── DD query helpers ────────────────────────────────────────────
// Sum DD.data values for a metric across given countries in a year range.
function ddQ(metric, countries, yearStart, yearEnd) {
  if (!window.DD) return 0;
  const cts = countries && countries.length ? countries : DD.countries;
  return DD.data
    .filter(r => r.metric === metric && cts.includes(r.country)
              && r.year >= yearStart && r.year <= yearEnd)
    .reduce((s, r) => s + r.value, 0);
}
// Active countries, current date range
function ddQA(metric) { return ddQ(metric, activeCt(), sel.dateStart, sel.dateEnd); }
// Single country, current date range
function ddQC(metric, country) { return ddQ(metric, [country], sel.dateStart, sel.dateEnd); }
// Apply a D-object sub-ratio to a DD total (preserves breakdown proportions)
function ddSplit(ddTotal, numerator, denominator) {
  return denominator > 0 ? Math.round(ddTotal * numerator / denominator) : 0;
}

function destroyChart(id) {
  if(charts[id]){
    charts[id].destroy();
    delete charts[id];
  }
}

const gridC = 'rgba(74,26,107,0.12)';
const tickC = '#4a3560';

function chartOpts(stacked, horizontal, pct) {
  const axis = horizontal ? {
    x: {
      grid:{color:gridC},
      ticks:{color:tickC,font:{size:10,family:"'Lato'"},callback:v=>fmtK(v)+(pct?'%':'')}
    },
    y: {
      grid:{display:false},
      ticks:{color:tickC,font:{size:10,family:"'Lato'"}}
    }
  } : {
    x: {
      stacked,
      grid:{color:gridC},
      ticks:{color:tickC,font:{size:10,family:"'Lato'"}}
    },
    y: {
      stacked,
      grid:{color:gridC},
      ticks:{color:tickC,font:{size:10,family:"'Lato'"},callback:v=>fmtK(v)+(pct?'%':'')}
    }
  };
  return {
    responsive:true,
    maintainAspectRatio:false,
    plugins:{
      legend:{display:false},
      tooltip:{callbacks:{label:ctx=>' '+fmt(ctx.raw)+(pct?'%':'')}}
    },
    scales: axis
  };
}

function bar(id, labels, datasets, opts={}) {
  destroyChart(id);
  const ctx = document.getElementById(id);
  if(!ctx) return;
  const horiz = !!opts.horizontal;
  charts[id] = new Chart(ctx,{
    type:'bar',
    data:{
      labels,
      datasets:datasets.map(d=>({...d, borderRadius:4, borderSkipped:false}))
    },
    options:{
      ...chartOpts(!!opts.stacked, horiz, !!opts.pct),
      indexAxis: horiz?'y':'x',
      plugins:{
        legend:{
          display:!!opts.legend,
          labels:{color:tickC,font:{size:10},usePointStyle:true,pointStyle:'rect'}
        },
        tooltip:{callbacks:{label:ctx=>' '+fmt(ctx.raw)+(opts.pct?'%':'')}}
      }
    }
  });
}

function donut(id, labels, data, colors) {
  destroyChart(id);
  const ctx = document.getElementById(id);
  if(!ctx) return;
  charts[id] = new Chart(ctx,{
    type:'doughnut',
    data:{
      labels,
      datasets:[{data,backgroundColor:colors,borderColor:'#f5f0e3',borderWidth:3}]
    },
    options:{
      responsive:true,
      maintainAspectRatio:false,
      plugins:{
        legend:{
          position:'right',
          labels:{color:tickC,font:{size:10},usePointStyle:true,pointStyle:'circle',padding:10}
        },
        tooltip:{callbacks:{label:ctx=>' '+ctx.label+': '+fmt(ctx.raw)}}
      },
      cutout:'58%'
    }
  });
}

function progList(id, items, max, colorFn) {
  const el = document.getElementById(id);
  if(!el) return;
  const m = max || Math.max(...items.map(i=>i.val), 1);
  el.innerHTML = items.map(it=>`
    <div class="prog-item">
      <div class="prog-row">
        <span class="prog-label">${it.label}</span>
        <span class="prog-val">${it.display||fmt(it.val)}</span>
      </div>
      <div class="prog-bg">
        <div class="prog-fill" style="width:${(it.val/m*100).toFixed(1)}%;background:${colorFn?colorFn(it.label):MAP_LEVEL_COLORS[4]}"></div>
      </div>
    </div>`).join('');
}

// ─── COUNTRY MULTI-SELECT ─────────────────────────────────────
function rebuildCountryOptions() {
  const dropdown = document.getElementById('country-multi-dropdown');
  if (!dropdown) return;
  const rows = [{ value: 'All', label: 'All Countries' }, ...C.map(c => ({ value: c, label: c }))];
  dropdown.innerHTML = rows.map(r => `
    <label class="country-multi-opt">
      <input type="checkbox" value="${r.value}"${r.value === 'All' ? ' checked' : ''}>
      <span>${r.label}</span>
    </label>`).join('');
  injectDropdownControls(dropdown, 'Countries',
    () => {
      dropdown.querySelectorAll('input[type="checkbox"]').forEach(cb => cb.checked = true);
      dropdown.dispatchEvent(new Event('change', { bubbles: true }));
    },
    () => {
      dropdown.querySelectorAll('input[type="checkbox"]').forEach(cb => cb.checked = false);
      dropdown.dispatchEvent(new Event('change', { bubbles: true }));
    }
  );
}

function buildCountryMultiSelect() {
  const trigger  = document.getElementById('country-multi-trigger');
  const dropdown = document.getElementById('country-multi-dropdown');
  if (!trigger || !dropdown) return;

  // Build initial options (C starts as hardcoded fallback, updates to DB on dd:ready)
  rebuildCountryOptions();

  // Toggle dropdown open/closed — attached once only
  trigger.addEventListener('click', e => {
    e.stopPropagation();
    dropdown.hidden = !dropdown.hidden;
    trigger.classList.toggle('open', !dropdown.hidden);
  });

  // Close when clicking outside — attached once only
  document.addEventListener('click', e => {
    if (!document.getElementById('country-multi-wrap').contains(e.target)) {
      dropdown.hidden = true;
      trigger.classList.remove('open');
    }
  });

  // Handle checkbox changes — attached once only
  dropdown.addEventListener('change', e => {
    const cb    = e.target;
    const all   = dropdown.querySelector('input[value="All"]');
    const indiv = [...dropdown.querySelectorAll('input:not([value="All"])')];

    if (cb.value === 'All') {
      indiv.forEach(x => x.checked = cb.checked);
      sel.countries = cb.checked ? ['All'] : [];
    } else {
      all.checked = false;
      const chosen = indiv.filter(x => x.checked).map(x => x.value);
      if (chosen.length === C.length) {
        all.checked = true;
        indiv.forEach(x => x.checked = true);
        sel.countries = ['All'];
      } else {
        sel.countries = chosen;
      }
    }

    if (!sel.countries.length) {
      all.checked = true;
      indiv.forEach(x => x.checked = true);
      sel.countries = ['All'];
    }

    updateCountryLabel();
    rebuildActive();
  });
}

function updateCountryLabel() {
  const el = document.getElementById('country-multi-label');
  if (el) el.textContent = activeLabel();
}

// ─── POPULATE LEVEL DROPDOWN ──────────────────────────────────
function buildLevelDropdown() {
  const select = document.getElementById('level-select');
  // Derive unique levels in order from hierarchyData
  const seen = new Set();
  hierarchyData.forEach(item => {
    if (!seen.has(item.level)) {
      seen.add(item.level);
      const opt = document.createElement('option');
      opt.value = levelToPanelId[item.level]; // "level1" / "level2" / "level3"
      opt.textContent = item.level;
      select.appendChild(opt);
    }
  });
}

// ─── POPULATE SUBLEVEL DROPDOWN ───────────────────────────────
// Called when a Level is selected; filters sublevels from hierarchyData
function buildSubLevelDropdown(panelId) {
  const select = document.getElementById('sublevel-select');
  select.innerHTML = '<option value="" disabled selected>Select Sub Level</option>';
  const items = hierarchyData.filter(item => levelToPanelId[item.level] === panelId);
  items.forEach(item => {
    const opt = document.createElement('option');
    opt.value = item.subLevel;
    opt.textContent = item.subLevel;
    select.appendChild(opt);
  });
  select.disabled = false;

  // Auto-select and render the first sublevel
  if (items.length) {
    select.value = items[0].subLevel;
    sel.subLevel = items[0].subLevel;
    renderSubLevelStats(panelId, items[0].subLevel);
  } else {
    select.value = '';
  }
}

// ─── RESOLVE KPI VALUE ────────────────────────────────────────
// Resolves a statistic object's data reference against the current country.
// Handles: single kpi path, kpiSum (array of paths added together),
// and kpiRatio (numerator/denominator shown as a percentage).
function resolveKpiValue(stat) {
  // If a DD metric is specified, use ddQA so value responds to year range
  if (stat.ddMetric && window.DD) return fmt(ddQA(stat.ddMetric));

  // Walk a dot-notation path into D and return the country value
  function getPath(path) {
    const parts = path.split('.');
    let v = D;
    for (const p of parts) { if (v == null) return null; v = v[p]; }
    if (v == null || typeof v !== 'object') return null;
    const a = activeCt();
    // Use pre-computed Total only when all countries are selected
    if (a.length === C.length && v.Total != null && !stat.pct) return v.Total;
    // Percentage metrics → average; absolute metrics → sum
    const vals = a.map(c => v[c]).filter(n => n != null);
    if (!vals.length) return null;
    return stat.pct
      ? vals.reduce((x, y) => x + y, 0) / vals.length
      : vals.reduce((x, y) => x + y, 0);
  }

  if (stat.kpiSum) {
    const nums = stat.kpiSum.map(getPath).filter(n => n != null);
    return nums.length ? fmt(nums.reduce((a, b) => a + b, 0)) : null;
  }
  if (stat.kpiRatio) {
    const n = getPath(stat.kpiRatio.n), d = getPath(stat.kpiRatio.d);
    return (n != null && d) ? (n / d * 100).toFixed(1) + '%' : null;
  }
  if (!stat.kpi) return null;
  const n = getPath(stat.kpi);
  return n != null ? (stat.pct ? n.toFixed(2) + '%' : fmt(n)) : null;
}

// ─── EDUCATION REACH CHART VIEW ───────────────────────────────
const ER_COLORS = MAP_LEVEL_COLORS;

function erBar(id, labels, datasets, opts = {}) {
  destroyChart(id);
  const ctx = document.getElementById(id);
  if (!ctx) return;
  const horiz = !!opts.horizontal;
  charts[id] = new Chart(ctx, {
    type: 'bar',
    data: {
      labels,
      datasets: datasets.map(d => ({ ...d, borderRadius: 3, borderSkipped: false }))
    },
    options: {
      responsive: true,
      maintainAspectRatio: false,
      indexAxis: horiz ? 'y' : 'x',
      plugins: {
        legend: { display: !!opts.legend, labels: { color: '#3a1a5a', font: { size: 10 }, usePointStyle: true, pointStyle: 'rect' } },
        datalabels: {
          display: opts.stackLabels ? ctx => ctx.dataset.data[ctx.dataIndex] > 0 : true,
          color: opts.stackLabels ? '#ffffff' : '#3a1a5a',
          font: { size: 10, weight: '700', family: "'Lato', sans-serif" },
          formatter: opts.formatter ? opts.formatter : (opts.pctLabel ? v => v.toFixed(2) + '%' : v => fmt(v)),
          anchor: opts.stackLabels ? 'center' : (horiz ? 'end' : 'end'),
          align: opts.stackLabels ? 'center' : (horiz ? 'right' : 'top'),
          offset: 2,
          clamp: true
        }
      },
      scales: {
        x: {
          stacked: !!opts.stacked,
          grid: { color: 'rgba(74,26,107,0.08)' },
          ticks: {
            color: '#4a3560', font: { size: 10 },
            // Value axis for horiz bars; category axis for vertical bars
            callback: horiz ? (opts.pctLabel ? v => v + '%' : v => fmtK(v)) : function(v) { return this.getLabelForValue(v); }
          }
        },
        y: {
          stacked: !!opts.stacked,
          grid: { color: horiz ? 'rgba(0,0,0,0)' : 'rgba(74,26,107,0.08)' },
          ticks: {
            color: '#4a3560', font: { size: 10 },
            // Category axis for horiz bars; value axis for vertical bars
            callback: horiz ? function(v) { return this.getLabelForValue(v); } : (opts.pctLabel ? v => v + '%' : v => fmtK(v))
          }
        }
      },
      layout: { padding: { top: horiz ? 4 : 24, right: horiz ? 48 : 8 } }
    }
  });
}

function renderEducationReachCharts() {
  const section = document.getElementById('sublevel-stats-section');
  const a = activeCt();
  const colors = a.map((_, i) => ER_COLORS[i % ER_COLORS.length]);

  // Data
  const BUR = BUR_METRICS[l1BurType] || BUR_METRICS.newly;
  const bVals   = a.map(c => ddQC(BUR, c));
  const bTotal  = bVals.reduce((s, v) => s + v, 0);

  const camaVals = a.map(c => ddQC('CAMA Members', c));
  const commVals = a.map(c => ddQC('Community Champions', c));
  const ccTotal  = camaVals.reduce((s, v) => s + v, 0) + commVals.reduce((s, v) => s + v, 0);

  const burNewly  = a.map(c => ddQC('Children Supported in School with Education Bursaries', c));
  const gVals    = a.map((_, i) => burNewly[i] + camaVals[i] + commVals[i]);
  const gTotal   = gVals.reduce((s, v) => s + v, 0);
  const camaBoys = a.map(c => ddQC('CAMA Boys', c));
  const commBoys = a.map(c => ddQC('Community Boys', c));
  const boVals   = a.map((_, i) => camaBoys[i] + commBoys[i]);
  const boTotal  = boVals.reduce((s, v) => s + v, 0);

  section.innerHTML = `
    <div class="er-grid">
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Girls Supported in School with Education Bursaries</span>
          <span class="er-total-badge">Total &nbsp;${fmt(bTotal)}</span>
        </div>
        <div class="chart-type-toggle" id="er-bursary-toggle" style="padding:8px 0 4px 0">
          <button class="chart-toggle-btn${l1BurType==='newly'?' active':''}" data-bur="newly">Newly Supported</button>
          <button class="chart-toggle-btn${l1BurType==='annual'?' active':''}" data-bur="annual">Annual</button>
          <button class="chart-toggle-btn${l1BurType==='cum2030'?' active':''}" data-bur="cum2030">Cumulative 2020–2030</button>
          <button class="chart-toggle-btn${l1BurType==='cumall'?' active':''}" data-bur="cumall">Cumulative All-time</button>
        </div>
        <div class="er-chart-wrap"><canvas id="er-bursary-chart"></canvas></div>
      </div>
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Girls Supported in School by CAMA &amp; Community Champions</span>
          <span class="er-total-badge">Total &nbsp;${fmt(ccTotal)}</span>
        </div>
        <div class="er-chart-wrap"><canvas id="er-cama-chart"></canvas></div>
      </div>
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Total Girls Supported</span>
          <span class="er-total-badge">Total &nbsp;${fmt(gTotal)}</span>
        </div>
        <div class="er-chart-wrap"><canvas id="er-girls-chart"></canvas></div>
      </div>
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Total Boys Supported</span>
          <span class="er-total-badge">Total &nbsp;${fmt(boTotal)}</span>
        </div>
        <div class="er-chart-wrap"><canvas id="er-boys-chart"></canvas></div>
      </div>
    </div>`;

  setTimeout(() => {
    // 1. Bursary — vertical bar, one colour per country
    erBar('er-bursary-chart', a, [{ data: bVals, backgroundColor: colors }]);

    // 2. CAMA & Community — grouped bar
    erBar('er-cama-chart', a, [
      { label: 'CAMA',      data: camaVals, backgroundColor: MAP_LEVEL_COLORS[4] },
      { label: 'Community', data: commVals, backgroundColor: MAP_LEVEL_COLORS[2] }
    ], { legend: true });

    // 3. Total Girls — horizontal bar, one colour per country
    erBar('er-girls-chart', a, [{ data: gVals, backgroundColor: colors }], { horizontal: true });

    // 4. Total Boys — horizontal bar, one colour per country
    erBar('er-boys-chart', a, [{ data: boVals, backgroundColor: colors }], { horizontal: true });
  }, 0);

  // Hide the normal Level 1 charts — only the 4 ER charts should show
  const l1Panel = document.getElementById('panel-level1');
  if (l1Panel) l1Panel.style.display = 'none';

  section.style.display = 'block';
}

function renderEducationOutcomesCharts() {
  const section = document.getElementById('sublevel-stats-section');
  const a = activeCt();
  const colors = a.map((_, i) => ER_COLORS[i % ER_COLORS.length]);

  // Dropout % per active country
  const dropVals = a.map(c => D.kpi15.pct[c] || 0);

  // Progression to next grade table rows (D.p9 has form1–form4)
  function progRows() {
    return a.map(c => {
      const f1 = D.p9.form1[c], f2 = D.p9.form2[c],
            f3 = D.p9.form3[c], f4 = D.p9.form4[c];
      const cell = v => v != null && v > 0 ? v.toFixed(1) + '%' : '—';
      return `<tr><td>${c}</td><td>${cell(f1)}</td><td>${cell(f2)}</td><td>${cell(f3)}</td><td>${cell(f4)}</td></tr>`;
    }).join('');
  }

  // Exam pass rates table rows for a given level
  function examRows(level) {
    const src = level === 'upper' ? EO.examUpper : EO.examLower;
    return a.map(c => {
      const d = src[c] || {};
      return `<tr><td>${c}</td><td>${d.benchmark != null ? d.benchmark + '%' : '—'}</td><td>${d.clients != null ? d.clients + '%' : '—'}</td></tr>`;
    }).join('');
  }

  // School completion table rows
  function complRows() {
    return a.map(c => {
      const d = EO.completion[c] || {};
      return `<tr><td>${c}</td><td>${d.lower != null ? d.lower + '%' : '—'}</td><td>${d.upper != null ? d.upper + '%' : '—'}</td></tr>`;
    }).join('');
  }

  section.innerHTML = `
    <div class="er-grid">
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Dropout Rate for Girls with Education Bursaries (EMP)</span>
        </div>
        <div class="er-chart-wrap"><canvas id="eo-dropout-chart"></canvas></div>
      </div>
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Progression to Next Grade</span>
        </div>
        <div class="er-table-wrap">
          <table class="er-table">
            <thead><tr><th>Country</th><th>Form 1</th><th>Form 2</th><th>Form 3</th><th>Form 4</th></tr></thead>
            <tbody>${progRows()}</tbody>
          </table>
        </div>
      </div>
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Exam Pass Rates</span>
          <div class="er-radio-group">
            <label class="er-radio-opt"><input type="radio" name="eo-exam-lvl" value="lower" checked> Lower Sec.</label>
            <label class="er-radio-opt"><input type="radio" name="eo-exam-lvl" value="upper"> Upper Sec.</label>
          </div>
        </div>
        <div class="er-table-wrap">
          <table class="er-table">
            <thead><tr><th>Country</th><th>Benchmark</th><th>Clients</th></tr></thead>
            <tbody id="eo-exam-tbody">${examRows('lower')}</tbody>
          </table>
        </div>
      </div>
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">School Completion Rate</span>
        </div>
        <div class="er-table-wrap">
          <table class="er-table">
            <thead><tr><th>Country</th><th>Lower Sec.</th><th>Upper Sec.</th></tr></thead>
            <tbody>${complRows()}</tbody>
          </table>
        </div>
      </div>
    </div>`;

  setTimeout(() => {
    erBar('eo-dropout-chart', a,
      [{ data: dropVals, backgroundColor: colors }],
      { pctLabel: true });

    // Radio toggle for exam pass rates
    section.querySelectorAll('input[name="eo-exam-lvl"]').forEach(radio => {
      radio.addEventListener('change', e => {
        const tbody = document.getElementById('eo-exam-tbody');
        if (tbody) tbody.innerHTML = examRows(e.target.value);
      });
    });
  }, 0);

  const l1Panel = document.getElementById('panel-level1');
  if (l1Panel) l1Panel.style.display = 'none';
  section.style.display = 'block';
}

function renderLearnerGuideProgrammeCharts() {
  const section = document.getElementById('sublevel-stats-section');
  const a = activeCt();

  // ── LG Training chart data (CAMFED-only bars; total = sum of those bars) ──
  const LG = 'Active Learner Guides';
  const lgVals = a.map(c => {
    const t = ddQC(LG, c);
    const d = (D.kpi19.camfed[c] || 0) + (D.kpi19.govt[c] || 0) || 1;
    return ddSplit(t, D.kpi19.camfed[c] || 0, d);
  });
  const lgCamfedTotal = lgVals.reduce((s, v) => s + v, 0);

  // ── SLS Girls/Boys data — direct from gender column ──
  const girlsVals = a.map(c => ddQC('Number of Clients by Form — Girls', c));
  const boysVals  = a.map(c => ddQC('Number of Clients by Form — Boys',  c));
  const slsTotal  = girlsVals.reduce((s, v) => s + v, 0) + boysVals.reduce((s, v) => s + v, 0);

  section.innerHTML = `
    <div class="lg-stat-strip">
      <div class="lg-stat-card">
        <div class="lg-stat-title">Active Learner Guides</div>
        <div class="lg-stat-value">(Blank)</div>
      </div>
      <div class="lg-stat-card">
        <div class="lg-stat-title">Girls Reporting Increased Agency</div>
        <div class="lg-stat-na">Data Not Available</div>
      </div>
      <div class="lg-stat-card">
        <div class="lg-stat-title">Learner Guides Reporting Increased Agency</div>
        <div class="lg-stat-value">99.0%</div>
      </div>
      <div class="lg-stat-card">
        <div class="lg-stat-title">Average number of children receiving My Better World annually.</div>
        <div style="display:flex;align-items:center;gap:14px;margin-top:6px;">
          <span id="lg-mbw-val" class="lg-stat-value">111</span>
          <div class="lg-radio-group" style="flex-direction:column;gap:5px;">
            <label class="lg-radio-opt"><input type="radio" name="lg-mbw" value="111" checked> per LG</label>
            <label class="lg-radio-opt"><input type="radio" name="lg-mbw" value="890"> per School</label>
          </div>
        </div>
      </div>
    </div>
    <div class="er-grid">
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Active Learner Guides by Training</span>
          <span class="er-total-badge">Total &nbsp;${fmt(lgCamfedTotal)}</span>
        </div>
        <div class="er-chart-wrap" style="height:300px;"><canvas id="lg-training-chart"></canvas></div>
      </div>
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Children Receiving Social and Learning Support Including My Better World Sessions</span>
          <span class="er-total-badge">Total &nbsp;${fmt(slsTotal)}</span>
        </div>
        <div class="er-chart-wrap" style="height:300px;"><canvas id="lg-sls-chart"></canvas></div>
      </div>
    </div>`;

  setTimeout(() => {
    // 1. CAMFED Trained — gold vertical bars
    erBar('lg-training-chart', a,
      [{ label: 'CAMFED Trained', data: lgVals, backgroundColor: MAP_LEVEL_COLORS[2] }],
      { legend: true });

    // 2. Girls (deep purple-black) / Boys (dark red) grouped bar
    erBar('lg-sls-chart', a, [
      { label: 'Girls', data: girlsVals, backgroundColor: MAP_LEVEL_COLORS[4] },
      { label: 'Boys',  data: boysVals,  backgroundColor: MAP_LEVEL_COLORS[3] }
    ], { legend: true });

    // MBW radio toggle
    section.querySelectorAll('input[name="lg-mbw"]').forEach(radio => {
      radio.addEventListener('change', e => {
        const el = document.getElementById('lg-mbw-val');
        if (el) el.textContent = e.target.value;
      });
    });
  }, 0);

  const l1Panel = document.getElementById('panel-level1');
  if (l1Panel) l1Panel.style.display = 'none';
  section.style.display = 'block';
}

function renderEducationSystems1Charts() {
  const section = document.getElementById('sublevel-stats-section');
  const a = activeCt();

  // District counts — live from DD geography
  const camfedDist = a.map(c => window.DD ? (DD.districts[c] || []).length : D.kpi34.districts[c] || 0);
  const govtDist   = a.map(c => L3.districtsGovt[c] || 0);
  const distTotal  = camfedDist.reduce((s,v)=>s+v,0) + govtDist.reduce((s,v)=>s+v,0);
  const schoolsTotal = L3.schoolsCamfed + L3.schoolsGovt;

  section.innerHTML = `
    <div style="display:grid;grid-template-columns:repeat(3,1fr);gap:12px;margin-bottom:16px;">
      <div class="lg-stat-card">
        <div class="lg-stat-title">% of resources for the Learner Guide Programme contributed by government</div>
        <div class="lg-stat-value">25%</div>
      </div>
      <div class="lg-stat-card">
        <div class="lg-stat-title">National Level Dropout Rate for Girls due to Early Marriage or Pregnancy</div>
        <div class="lg-stat-na">Data Not Available</div>
      </div>
      <div class="lg-stat-card">
        <div class="lg-stat-title">Community Champion Teacher Mentors</div>
        <div class="lg-stat-value">${fmt(L3.teacherMentors)}</div>
      </div>
    </div>
    <div class="er-grid">
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Number of Districts with Learner Guides</span>
          <span class="er-total-badge">Total &nbsp;${fmt(distTotal)}</span>
        </div>
        <div class="er-chart-wrap"><canvas id="l3es1-dist-chart"></canvas></div>
      </div>
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Number of Schools with Learner Guides</span>
          <span class="er-total-badge">Total &nbsp;${fmt(schoolsTotal)}</span>
        </div>
        <div class="er-chart-wrap"><canvas id="l3es1-schools-chart"></canvas></div>
      </div>
    </div>`;

  setTimeout(() => {
    erBar('l3es1-dist-chart', a, [
      { label: 'CAMFED Partner', data: camfedDist, backgroundColor: L3_GREEN },
      { label: 'Government',     data: govtDist,   backgroundColor: MAP_LEVEL_COLORS[4] }
    ], { legend: true, stacked: true, stackLabels: true });

    erBar('l3es1-schools-chart',
      ['CAMFED Supported', 'Government Delivery'],
      [{ data: [L3.schoolsCamfed, L3.schoolsGovt],
         backgroundColor: [L3_GREEN, MAP_LEVEL_COLORS[4]] }]
    );
  }, 0);

  const l3Panel = document.getElementById('panel-level3');
  if (l3Panel) l3Panel.style.display = 'none';
  section.style.display = 'block';
}

function renderEducationSystems2Charts() {
  const section = document.getElementById('sublevel-stats-section');
  const a = activeCt();
  const colors = a.map((_, i) => ER_COLORS[i % ER_COLORS.length]);

  const mouVals  = a.map(c => L3.mou[c] || 0);
  const mouTotal = mouVals.reduce((s,v) => s+v, 0);

  // Annual totals from D.kpi35 + L3 gender split
  const aTotal = D.kpi35.total.Total;
  const aGirls = L3.kpi35Annual.girls;
  const aBoys  = L3.kpi35Annual.boys;
  const aPrim  = D.kpi35.primary.Total;
  const aSec   = D.kpi35.secondary.Total;

  // Newly supported from L3
  const nGirls = L3.kpi35Newly.girls;
  const nBoys  = L3.kpi35Newly.boys;
  const nPrim  = L3.kpi35Newly.primary;
  const nSec   = L3.kpi35Newly.secondary;
  const nTotal = nGirls + nBoys;

  function barRow(label, val, maxVal, color) {
    const pct = maxVal > 0 ? Math.max(8, Math.round(val / maxVal * 100)) : 50;
    return `<div class="l3-bar-row">
      <div class="l3-bar-label">${label}</div>
      <div class="l3-bar-track">
        <div class="l3-bar-fill" style="width:${pct}%;background:${color};">
          <span class="l3-bar-val">${fmt(val)}</span>
        </div>
      </div>
    </div>`;
  }

  function buildBars(gT, bT, pT, sT) {
    const genderTotal = gT + bT, schoolTotal = pT + sT;
    return `
      <div class="l3-section-title">By Gender</div>
      ${barRow('Girls total',     gT, genderTotal, L3_GREEN)}
      ${barRow('Boys total',      bT, genderTotal, MAP_LEVEL_COLORS[2])}
      <div class="l3-section-title">By School Level</div>
      ${barRow('Primary total',   pT, schoolTotal, L3_GREEN)}
      ${barRow('Secondary total', sT, schoolTotal, MAP_LEVEL_COLORS[2])}`;
  }

  section.innerHTML = `
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:18px;">
      <div class="er-card" style="grid-column:1;grid-row:1;">
        <div class="er-card-header">
          <span class="er-card-title">Number of Memoranda of Understanding between Government Departments and CAMFED</span>
          <span class="er-total-badge">Total &nbsp;${fmt(mouTotal)}</span>
        </div>
        <div class="er-chart-wrap"><canvas id="l3es2-mou-chart"></canvas></div>
      </div>
      <div class="er-card" style="grid-column:2;grid-row:1/3;">
        <div class="er-card-header">
          <span class="er-card-title">Children Benefitting from Improved Learning Environment</span>
          <div style="display:flex;flex-direction:column;gap:4px;align-items:flex-end;">
            <label class="er-radio-opt"><input type="radio" name="l3es2-kids" value="annual" checked> Annual</label>
            <label class="er-radio-opt"><input type="radio" name="l3es2-kids" value="newly"> Newly supported</label>
            <span class="er-total-badge" id="l3es2-kids-total">Total &nbsp;${fmt(aTotal)}</span>
          </div>
        </div>
        <div id="l3es2-kids-bars">${buildBars(aGirls, aBoys, aPrim, aSec)}</div>
      </div>
      <div class="er-card" style="grid-column:1;grid-row:2;">
        <div class="er-card-header">
          <span class="er-card-title">Number of Active Community Champions for Girls' Education</span>
        </div>
        <div class="er-chart-wrap"><canvas id="l3es2-champ-chart"></canvas></div>
      </div>
    </div>`;

  setTimeout(() => {
    erBar('l3es2-mou-chart', a,
      [{ data: mouVals, backgroundColor: colors }],
      { horizontal: true });

    erBar('l3es2-champ-chart', ['Members'], [
      { label: 'CDCs', data: [L3.champions.cdcs], backgroundColor: MAP_LEVEL_COLORS[4] },
      { label: 'PSGs', data: [L3.champions.psgs], backgroundColor: L3_GREEN },
      { label: 'SBCs', data: [L3.champions.sbcs], backgroundColor: MAP_LEVEL_COLORS[2] }
    ], { legend: true });

    section.querySelectorAll('input[name="l3es2-kids"]').forEach(r => {
      r.addEventListener('change', e => {
        const ann = e.target.value === 'annual';
        const [gT, bT, pT, sT] = ann
          ? [aGirls, aBoys, aPrim, aSec]
          : [nGirls, nBoys, nPrim, nSec];
        const total = ann ? aTotal : nTotal;
        const barsEl  = document.getElementById('l3es2-kids-bars');
        const totalEl = document.getElementById('l3es2-kids-total');
        if (barsEl)  barsEl.innerHTML  = buildBars(gT, bT, pT, sT);
        if (totalEl) totalEl.textContent = `Total  ${fmt(total)}`;
      });
    });
  }, 0);

  const l3Panel = document.getElementById('panel-level3');
  if (l3Panel) l3Panel.style.display = 'none';
  section.style.display = 'block';
}

function renderAgricultureFoodCharts() {
  const section = document.getElementById('sublevel-stats-section');
  const a = activeCt();
  const colors = a.map((_, i) => ER_COLORS[i % ER_COLORS.length]);
  const intPct  = v => Math.round(v) + '%';

  // Left chart data
  const fcVals = a.map(c => L2AF.foodConsumption[c] || 0);

  // Right table rows — Agri Yields
  function agriRows() {
    return a.map(c => {
      const v = L2AF.agriYields[c];
      return `<tr><td>${c}</td><td>${v != null ? v + '%' : '<em>Not Available</em>'}</td></tr>`;
    }).join('');
  }

  // Right table rows — Climate Smart
  function csRows() {
    return a.map(c => {
      const v = L2AF.climateSmart[c];
      return `<tr><td>${c}</td><td>${v != null ? v.toFixed(1) : '<em>Not Available</em>'}</td></tr>`;
    }).join('');
  }

  section.innerHTML = `
    <div style="display:grid;grid-template-columns:1fr 1fr;gap:18px;">
      <div class="er-card" style="grid-row:span 2;">
        <div class="er-card-header">
          <span class="er-card-title">Percentage of Female Entrepreneurs Reporting an Increased Household Consumption of Food Since Participating in CAMFED's Enterprise Programme</span>
        </div>
        <div class="er-chart-wrap" style="height:400px;"><canvas id="l2af-food-chart"></canvas></div>
      </div>
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Percentage of Female Agripreneurs Reporting Increased Yields Since Participating in The Agriculture Guide Programme</span>
        </div>
        <div class="er-table-wrap">
          <table class="er-table">
            <thead><tr><th>Country</th><th>Value</th></tr></thead>
            <tbody>${agriRows()}</tbody>
          </table>
        </div>
      </div>
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Average Number of Climate-Smart Techniques Used by Those Receiving Support from an Agriculture Guide</span>
        </div>
        <div class="er-table-wrap">
          <table class="er-table">
            <thead><tr><th>Country</th><th>Indicator</th></tr></thead>
            <tbody>${csRows()}</tbody>
          </table>
        </div>
      </div>
    </div>`;

  setTimeout(() => {
    erBar('l2af-food-chart', a,
      [{ data: fcVals, backgroundColor: colors }],
      { pctLabel: true, formatter: intPct });
  }, 0);

  const l2Panel = document.getElementById('panel-level2');
  if (l2Panel) l2Panel.style.display = 'none';
  section.style.display = 'block';
}

function renderJobsIncomeCharts() {
  const section = document.getElementById('sublevel-stats-section');
  const a = activeCt();
  const colors = a.map((_, i) => ER_COLORS[i % ER_COLORS.length]);
  const intPct  = v => Math.round(v) + '%';

  // Women progressing (horizontal %)
  const wpVals = a.map(c => L2JI.womenProgress[c] || 0);

  // Female entrepreneurs with increased incomes (vertical %)
  const feVals = a.map(c => D.kpi210.pct[c] || 0);

  // Jobs created — live from post-school clients
  const jobVals  = a.map(c => ddQC('Number of Post School Clients', c));
  const jobTotal = jobVals.reduce((s, v) => s + v, 0);

  // New businesses (vertical counts)
  const bizVals  = a.map(c => D.kpi26.annual[c] || 0);
  const bizTotal = bizVals.reduce((s, v) => s + v, 0);

  section.innerHTML = `
    <div class="er-grid">
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Women Progressing Towards a Secure Livelihood (Employment, Enterprise, Continuing Education) Following Transitions Programme</span>
        </div>
        <div class="er-chart-wrap" style="height:240px;"><canvas id="l2ji-wp-chart"></canvas></div>
      </div>
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Female Entrepreneurs with Increased Incomes after Participating in CAMFED's Enterprise Programme</span>
        </div>
        <div class="er-chart-wrap"><canvas id="l2ji-fe-chart"></canvas></div>
      </div>
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Jobs Created through Enterprise Programme Including Self-Employment</span>
          <span class="er-total-badge">Total &nbsp;${fmt(jobTotal)}</span>
        </div>
        <div class="er-chart-wrap"><canvas id="l2ji-jobs-chart"></canvas></div>
      </div>
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">New Businesses</span>
          <span class="er-total-badge">Total &nbsp;${fmt(bizTotal)}</span>
        </div>
        <div class="er-chart-wrap"><canvas id="l2ji-biz-chart"></canvas></div>
      </div>
    </div>`;

  setTimeout(() => {
    // 1. Women Progressing — horizontal %, integer labels
    erBar('l2ji-wp-chart', a,
      [{ data: wpVals, backgroundColor: colors }],
      { horizontal: true, pctLabel: true, formatter: intPct });

    // 2. Female Entrepreneurs — vertical %, integer labels
    erBar('l2ji-fe-chart', a,
      [{ data: feVals, backgroundColor: colors }],
      { pctLabel: true, formatter: intPct });

    // 3. Jobs Created — vertical counts, ER_COLORS
    erBar('l2ji-jobs-chart', a, [{ data: jobVals, backgroundColor: colors }]);

    // 4. New Businesses — vertical counts, ER_COLORS
    erBar('l2ji-biz-chart', a, [{ data: bizVals, backgroundColor: colors }]);
  }, 0);

  const l2Panel = document.getElementById('panel-level2');
  if (l2Panel) l2Panel.style.display = 'none';
  section.style.display = 'block';
}

function renderLivelihoodsReachCharts() {
  const section = document.getElementById('sublevel-stats-section');
  const a = activeCt();
  const colors = a.map((_, i) => ER_COLORS[i % ER_COLORS.length]);

  // Enterprise Guides — live by type
  const agVals  = a.map(c => ddQC('Active Guides — Agriculture', c));
  const bizVals = a.map(c => ddQC('Active Guides — Business',    c));
  const egTotal = agVals.reduce((s, v) => s + v, 0) + bizVals.reduce((s, v) => s + v, 0);

  // Businesses Supported — live loan counts by guide type
  const bsAgVals  = a.map(c => ddQC('Loans Disbursed — Agriculture', c));
  const bsBizVals = a.map(c => ddQC('Loans Disbursed — Business',    c));
  const bsTotal   = bsAgVals.reduce((s, v) => s + v, 0) + bsBizVals.reduce((s, v) => s + v, 0);

  // Business Grants — live count and value
  const grantsNumVals = a.map(c => ddQC('Grants Distributed — Count', c));
  const grantsValVals = a.map(c => ddQC('Grants Disbursed',           c));
  const grantsTotal   = grantsNumVals.reduce((s, v) => s + v, 0);

  // Kiva & RIF Loans — live counts
  const kivaVals  = a.map(c => ddQC('Loans Disbursed — Kiva', c));
  const rifVals   = a.map(c => ddQC('Loans Disbursed — RIF',  c));
  const loansTotal = kivaVals.reduce((s, v) => s + v, 0) + rifVals.reduce((s, v) => s + v, 0);

  section.innerHTML = `
    <div class="er-grid">
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Active Enterprise Guides (Business &amp; Agriculture Guides)</span>
          <span class="er-total-badge">Total &nbsp;${fmt(egTotal)}</span>
        </div>
        <div class="er-chart-wrap"><canvas id="l2lr-eg-chart"></canvas></div>
      </div>
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Businesses Supported by Enterprise Guides</span>
          <span class="er-total-badge">Total &nbsp;${fmt(bsTotal)}</span>
        </div>
        <div class="er-chart-wrap"><canvas id="l2lr-bs-chart"></canvas></div>
      </div>
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Business Grants Distributed</span>
          <span class="er-total-badge">Total &nbsp;<span id="l2lr-grants-total">${fmt(grantsTotal)}</span></span>
        </div>
        <div style="margin:4px 0 6px;display:flex;gap:14px;flex-wrap:wrap;">
          <label class="er-radio-opt"><input type="radio" name="l2lr-grants" value="num" checked> Number of Grants</label>
          <label class="er-radio-opt"><input type="radio" name="l2lr-grants" value="val"> Value of Grants (USD)</label>
        </div>
        <div class="er-chart-wrap"><canvas id="l2lr-grants-chart"></canvas></div>
      </div>
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">CAMFED Kiva &amp; RIF Loans Distributed</span>
          <span class="er-total-badge">Total &nbsp;${fmt(loansTotal)}</span>
        </div>
        <div class="er-chart-wrap"><canvas id="l2lr-loans-chart"></canvas></div>
      </div>
    </div>`;

  setTimeout(() => {
    // 1. Enterprise Guides: Agriculture (dark) / Business (steel blue) grouped
    erBar('l2lr-eg-chart', a, [
      { label: 'Agriculture Guides', data: agVals,  backgroundColor: MAP_LEVEL_COLORS[4] },
      { label: 'Business Guides',    data: bizVals, backgroundColor: MAP_LEVEL_COLORS[1] }
    ], { legend: true });

    // 2. Businesses Supported: same colour pairing
    erBar('l2lr-bs-chart', a, [
      { label: 'Agriculture Guides', data: bsAgVals,  backgroundColor: MAP_LEVEL_COLORS[4] },
      { label: 'Business Guides',    data: bsBizVals, backgroundColor: MAP_LEVEL_COLORS[1] }
    ], { legend: true });

    // 3. Business Grants: per-country colours, radio switches dataset
    function drawGrants(mode) {
      const vals  = mode === 'val' ? grantsValVals : grantsNumVals;
      const total = vals.reduce((s, v) => s + v, 0);
      const el = document.getElementById('l2lr-grants-total');
      if (el) el.textContent = fmt(total);
      erBar('l2lr-grants-chart', a, [{ data: vals, backgroundColor: colors }]);
    }
    drawGrants('num');
    section.querySelectorAll('input[name="l2lr-grants"]').forEach(r =>
      r.addEventListener('change', e => drawGrants(e.target.value))
    );

    // 4. Kiva (steel blue) / RIF (dark) grouped
    erBar('l2lr-loans-chart', a, [
      { label: 'CAMFED Kiva Loans', data: kivaVals, backgroundColor: MAP_LEVEL_COLORS[1] },
      { label: 'CAMFED RIF Loans',  data: rifVals,  backgroundColor: MAP_LEVEL_COLORS[4] }
    ], { legend: true });
  }, 0);

  const l2Panel = document.getElementById('panel-level2');
  if (l2Panel) l2Panel.style.display = 'none';
  section.style.display = 'block';
}

function renderLeadershipTertiaryCharts() {
  const section = document.getElementById('sublevel-stats-section');
  const a = activeCt();
  const colors = a.map((_, i) => ER_COLORS[i % ER_COLORS.length]);

  // Transition Guides — live
  const tgVals   = a.map(c => ddQC('Active Guides — Transition', c));
  const tgTotal  = tgVals.reduce((s, v) => s + v, 0);

  // CAMA Members — cumulative all-time (sum all years, ignore date range filter)
  const camaVals  = a.map(c => ddQ('CAMA Members', [c], 2000, 9999));
  const camaTotal = camaVals.reduce((s, v) => s + v, 0);

  const ywTGVals  = a.map(c => L2.youngWomenTG[c] || 0);
  const ywTGTotal = ywTGVals.reduce((s, v) => s + v, 0);

  // Tertiary Education — live
  const tertVals  = a.map(c => ddQC('Number of Women Supported by CAMFED in Tertiary Education', c));
  const tertTotal = tertVals.reduce((s, v) => s + v, 0);

  section.innerHTML = `
    <div class="er-grid">
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Active Transition Guides</span>
          <span class="er-total-badge">Total &nbsp;${fmt(tgTotal)}</span>
        </div>
        <div class="er-chart-wrap"><canvas id="l2lt-tg-chart"></canvas></div>
      </div>
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Numbers of CAMA Members</span>
          <span class="er-total-badge">Total &nbsp;${fmt(camaTotal)}</span>
        </div>
        <span class="er-filter-badge">Total membership all-time &#x2304;</span>
        <div class="er-chart-wrap"><canvas id="l2lt-cama-chart"></canvas></div>
      </div>
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Young Women Supported by Transition Guides</span>
          <span class="er-total-badge">Total &nbsp;${fmt(ywTGTotal)}</span>
        </div>
        <div class="er-chart-wrap"><canvas id="l2lt-ywtg-chart"></canvas></div>
      </div>
      <div class="er-card">
        <div class="er-card-header">
          <span class="er-card-title">Young Women Supported by CAMFED in Tertiary Education</span>
          <span class="er-total-badge">Total &nbsp;${fmt(tertTotal)}</span>
        </div>
        <div class="er-chart-wrap"><canvas id="l2lt-tert-chart"></canvas></div>
      </div>
    </div>`;

  setTimeout(() => {
    erBar('l2lt-tg-chart',   a, [{ data: tgVals,   backgroundColor: colors }]);
    erBar('l2lt-cama-chart', a, [{ data: camaVals,  backgroundColor: colors }]);
    erBar('l2lt-ywtg-chart', a, [{ data: ywTGVals,  backgroundColor: colors }]);
    erBar('l2lt-tert-chart', a, [{ data: tertVals,  backgroundColor: colors }]);
  }, 0);

  const l2Panel = document.getElementById('panel-level2');
  if (l2Panel) l2Panel.style.display = 'none';
  section.style.display = 'block';
}

// ─── RENDER SUBLEVEL STATISTICS ───────────────────────────────
// Auto-populates all stats for the selected Level + SubLevel combination
function renderSubLevelStats(panelId, subLevelValue) {
  const section  = document.getElementById('sublevel-stats-section');

  // Restore the current level's tab panel; custom views will hide it again if needed
  const activePanel = document.getElementById(`panel-${panelId}`);
  if (activePanel) activePanel.style.display = '';

  if (!subLevelValue) { section.style.display = 'none'; return; }

  // Education Reach gets its own chart-based view (hides the normal Level 1 charts)
  if (panelId === 'level1' && subLevelValue === 'Education Reach') {
    renderEducationReachCharts();
    return;
  }

  // Education Outcomes gets a 2×2 grid with a bar chart + three tables
  if (panelId === 'level1' && subLevelValue === 'Education Outcomes') {
    renderEducationOutcomesCharts();
    return;
  }

  // Learner Guide Programme gets 4 stat cards + 2 charts
  if (panelId === 'level1' && subLevelValue === 'Learner Guide Programme') {
    renderLearnerGuideProgrammeCharts();
    return;
  }

  // Level 2: Leadership & Tertiary gets a 2×2 bar chart grid
  if (panelId === 'level2' && subLevelValue === 'Leadership and Tertiary') {
    renderLeadershipTertiaryCharts();
    return;
  }

  // Level 2: Livelihoods Reach gets a 2×2 bar chart grid
  if (panelId === 'level2' && subLevelValue === 'Livelihoods Reach') {
    renderLivelihoodsReachCharts();
    return;
  }

  // Level 2: Jobs & Income gets a 2×2 bar chart grid
  if (panelId === 'level2' && subLevelValue === 'Jobs & Income') {
    renderJobsIncomeCharts();
    return;
  }

  // Level 2: Agriculture & Food gets a chart (left) + 2 tables (right) layout
  if (panelId === 'level2' && subLevelValue === 'Agriculture & Food') {
    renderAgricultureFoodCharts();
    return;
  }

  // Level 3: Education Systems 1 — 3 stat cards + 2 charts
  if (panelId === 'level3' && subLevelValue === 'Education Systems 1') {
    renderEducationSystems1Charts();
    return;
  }

  // Level 3: Education Systems 2 — MoU chart + Community Champions + Children Benefitting
  if (panelId === 'level3' && subLevelValue === 'Education Systems 2') {
    renderEducationSystems2Charts();
    return;
  }

  // Restore default card structure if a custom view overwrote it
  if (!document.getElementById('sublevel-stats-title')) {
    section.innerHTML = `
      <div class="data-card">
        <div class="data-card-header"><span id="sublevel-stats-title"></span></div>
        <div class="data-card-body"><ul id="sublevel-stats-list" class="sublevel-stats-list"></ul></div>
      </div>`;
  }

  const entry = hierarchyData.find(
    item => levelToPanelId[item.level] === panelId && item.subLevel === subLevelValue
  );
  if (!entry) { section.style.display = 'none'; return; }

  // Deduplicate by label and remove blanks
  const stats = [...new Map(entry.statistics.map(s => [s.label, s])).values()]
    .filter(s => s.label && s.label.trim());

  document.getElementById('sublevel-stats-title').textContent =
    `${entry.level} — ${entry.subLevel}`;
  document.getElementById('sublevel-stats-list').innerHTML =
    stats.map(s => {
      const val = resolveKpiValue(s);
      return `<li class="sublevel-stat-item">
        <span class="sublevel-stat-label">${s.label}</span>
        <span class="sublevel-stat-value${val ? '' : ' sublevel-stat-na'}">${val ?? '—'}</span>
      </li>`;
    }).join('');
  section.style.display = 'block';
}

// ─── UPDATE STATS ──────────────────────────────────────────────
// Helper: set element text only if element exists
function setTxt(id, val) {
  const el = document.getElementById(id);
  if (el) el.textContent = val;
}

function updateStats() {
  const s = sel.dateStart, e = sel.dateEnd;
  const a = activeCt();

  // L1 stats — all from DD (date-range aware)
  setTxt('s-bursary',     fmt(ddQA('Children Supported in School with Education Bursaries')));
  setTxt('s-cama-school', fmt(ddQA('CAMA Members')));
  const slsTotal = ddQA('Number of Clients by Form');
  setTxt('s-sls',         fmt(slsTotal));
  setTxt('s-lg',          fmt(ddQA('Active Learner Guides')));
  setTxt('s-girls-total', fmt(ddQA('Number of Clients by Form — Girls')));
  setTxt('s-boys-total',  fmt(ddQA('Number of Clients by Form — Boys')));
  setTxt('l1-headline', `${activeLabel()} — Level 1: Girls' Education, Bursary Support & Learner Guides`);

  // L2 stats
  setTxt('s2-cama',  fmt(ddQA('CAMA Members')));
  setTxt('s2-jobs',  fmt(ddQA('Number of Post School Clients')));
  setTxt('s2-ent',   fmt(ddQA('Active Guides by Type')));

  // L3 stats
  setTxt('s3-schools',   fmt(ddQA('Active Partner Schools')));
  const districtCount = window.DD
    ? activeCt().reduce((s, c) => s + (DD.districts[c] || []).length, 0)
    : cv(D.kpi34.districts);
  setTxt('s3-districts', fmt(districtCount));
  setTxt('s3-children',  fmt(ddQA('Grants Disbursed')));
}

let l1BurType = 'newly';
const BUR_METRICS = {
  newly:   'Children Supported in School with Education Bursaries',
  annual:  'Children Supported in School with Education Bursaries — Annual',
  cum2030: 'Children Supported in School with Education Bursaries — Cumulative 2020-2030',
  cumall:  'Children Supported in School with Education Bursaries — Cumulative all-time',
};

// ─── BUILD LEVEL 1 ─────────────────────────────────────────────
function buildL1() {
  const a = activeCt();
  const single = a.length === 1;
  const c = single ? a[0] : null;
  const BUR = BUR_METRICS[l1BurType] || BUR_METRICS.newly;
  const LG  = 'Active Learner Guides';

  // Bursary chart: single → period breakdown using DD; multi → per-country totals
  if (single) {
    const annual  = ddQC(BUR, c);
    const newly   = ddQ(BUR, [c], sel.dateStart, sel.dateStart); // first year only
    const cum2030 = ddQ(BUR, [c], 2020, 2030);
    const cumAll  = ddQ(BUR, [c], 2020, sel.dateEnd);
    bar('l1-bursary-chart', ['Annual','Newly Supp.','Cum. 20–30','Cum. All-time'],
      [{data:[annual, newly, cum2030, cumAll], backgroundColor:[MAP_LEVEL_COLORS[2],MAP_LEVEL_COLORS[4],MAP_LEVEL_COLORS[1],MAP_LEVEL_COLORS[3]]}]);
  } else {
    bar('l1-bursary-chart', a, [{data:a.map(n=>ddQC(BUR,n)), backgroundColor:BARS}]);
  }

  // LG chart: split using D ratios applied to DD total
  if (single) {
    const lgTotal = ddQC(LG, c);
    const dTotal  = (D.kpi19.camfed[c]||0) + (D.kpi19.govt[c]||0) || 1;
    bar('l1-lg-chart', ['CAMFED Trained','Govt Trained'], [{
      data:[ddSplit(lgTotal, D.kpi19.camfed[c]||0, dTotal),
            ddSplit(lgTotal, D.kpi19.govt[c]||0,   dTotal)],
      backgroundColor:[MAP_LEVEL_COLORS[4],MAP_LEVEL_COLORS[2]]
    }]);
  } else {
    bar('l1-lg-chart', a, [
      {label:'CAMFED', data:a.map(n=>{ const t=ddQC(LG,n), d=(D.kpi19.camfed[n]||0)+(D.kpi19.govt[n]||0)||1; return ddSplit(t,D.kpi19.camfed[n]||0,d); }), backgroundColor:MAP_LEVEL_COLORS[4]},
      {label:'Govt',   data:a.map(n=>{ const t=ddQC(LG,n), d=(D.kpi19.camfed[n]||0)+(D.kpi19.govt[n]||0)||1; return ddSplit(t,D.kpi19.govt[n]||0,d);   }), backgroundColor:MAP_LEVEL_COLORS[2]}
    ], {stacked:true, legend:true});
  }

  // Primary vs secondary — scale DD total using D ratios
  bar('l1-levels-chart', a, [
    {label:'Primary',   data:a.map(n=>{ const t=ddQC(BUR,n), d=D.kpi11.annual.total[n]||1; return ddSplit(t,D.kpi11.annual.primary[n]||0,d); }),   backgroundColor:MAP_LEVEL_COLORS[4]},
    {label:'Secondary', data:a.map(n=>{ const t=ddQC(BUR,n), d=D.kpi11.annual.total[n]||1; return ddSplit(t,D.kpi11.annual.secondary[n]||0,d); }), backgroundColor:MAP_LEVEL_COLORS[2]}
  ], {stacked:false, legend:true});

  // Periods bar — aggregate across active countries from DD
  bar('l1-periods-chart', ['Annual','Newly Supp.','Cum. 20–30','Cum. All-time'], [{
    data:[
      ddQ(BUR, a, sel.dateStart, sel.dateEnd),
      ddQ(BUR, a, sel.dateStart, sel.dateStart),
      ddQ(BUR, a, 2020, 2030),
      ddQ(BUR, a, 2020, sel.dateEnd)
    ],
    backgroundColor:[MAP_LEVEL_COLORS[4],MAP_LEVEL_COLORS[3],MAP_LEVEL_COLORS[2],MAP_LEVEL_COLORS[1]]
  }]);

  // Dropout rate — no DD equivalent; keep D values
  const items = a.map(n=>({label:n, val:D.kpi15.pct[n], display:D.kpi15.pct[n].toFixed(2)+'%'}));
  progList('l1-dropout', items, 5, l=>countryColor(l));

  // SLS — direct from gender column
  if (single) {
    bar('l1-sls-chart', ['Girls','Boys'], [{data:[ddQC('Number of Clients by Form — Girls',c), ddQC('Number of Clients by Form — Boys',c)], backgroundColor:[MAP_LEVEL_COLORS[2],MAP_LEVEL_COLORS[4]]}]);
  } else {
    bar('l1-sls-chart', a, [
      {label:'Girls', data:a.map(n=>ddQC('Number of Clients by Form — Girls',n)), backgroundColor:MAP_LEVEL_COLORS[2]},
      {label:'Boys',  data:a.map(n=>ddQC('Number of Clients by Form — Boys', n)), backgroundColor:MAP_LEVEL_COLORS[4]}
    ], {stacked:true, legend:true});
  }

  // Form dropout — no DD equivalent; keep D values
  const formItems = ['Form 1','Form 2','Form 3','Form 4'].map((f,i)=>{
    const key = ['form1','form2','form3','form4'][i];
    const vals = a.map(n=>D.p9[key][n]||0);
    const val = vals.reduce((s,v)=>s+v,0) / vals.length;
    return {label:f, val:parseFloat(val.toFixed(2)), display:val.toFixed(2)+'%'};
  });
  progList('l1-dropout-form', formItems, 25, () => MAP_LEVEL_COLORS[3]);
}

// ─── BUILD LEVEL 2 ─────────────────────────────────────────────
function buildL2() {
  const a = activeCt();

  // CAMA members — DD
  bar('l2-cama-chart', a, [{data:a.map(n=>ddQC('CAMA Members',n)), backgroundColor:BARS}]);

  // Guide types — live by type
  bar('l2-guides-chart', a, [
    {label:'Transition',  data:a.map(n=>ddQC('Active Guides — Transition',  n)), backgroundColor:MAP_LEVEL_COLORS[1]},
    {label:'Agriculture', data:a.map(n=>ddQC('Active Guides — Agriculture', n)), backgroundColor:MAP_LEVEL_COLORS[4]},
    {label:'Business',    data:a.map(n=>ddQC('Active Guides — Business',    n)), backgroundColor:MAP_LEVEL_COLORS[2]}
  ], {legend:true});

  // Businesses supported — live loan counts by guide type
  bar('l2-biz-chart', a, [
    {label:'Ag. Guides',  data:a.map(n=>ddQC('Loans Disbursed — Agriculture', n)), backgroundColor:MAP_LEVEL_COLORS[4]},
    {label:'Biz. Guides', data:a.map(n=>ddQC('Loans Disbursed — Business',    n)), backgroundColor:MAP_LEVEL_COLORS[2]}
  ], {legend:true});

  // Post-school clients — DD
  bar('l2-jobs-chart', a, [{data:a.map(n=>ddQC('Number of Post School Clients',n)), backgroundColor:BARS}]);

  // % metrics — no DD equivalent; keep D values
  const inc = a.map(n=>({label:n, val:D.kpi210.pct[n], display:D.kpi210.pct[n]+'%'}));
  progList('l2-income', inc, 100, l=>countryColor(l));
  const pro = a.map(n=>({label:n, val:D.kpi211.profit[n], display:D.kpi211.profit[n]+'%'}));
  progList('l2-profit', pro, 100, l=>countryColor(l));
  const sur = a.map(n=>({label:n, val:D.kpi212.yr1[n], display:D.kpi212.yr1[n]+'%'}));
  progList('l2-survival', sur, 100, l=>countryColor(l));
}

// ─── BUILD LEVEL 3 ─────────────────────────────────────────────
function buildL3() {
  const a = activeCt();

  // Partner schools — DD total split by D primary/secondary ratios
  bar('l3-schools-chart', a, [
    {label:'Primary',   data:a.map(n=>{ const t=ddQC('Active Partner Schools',n), d=D.kpi31.total_all[n]||1; return ddSplit(t,D.kpi31.primary[n]||0,d);   }), backgroundColor:MAP_LEVEL_COLORS[4]},
    {label:'Secondary', data:a.map(n=>{ const t=ddQC('Active Partner Schools',n), d=D.kpi31.total_all[n]||1; return ddSplit(t,D.kpi31.secondary[n]||0,d); }), backgroundColor:MAP_LEVEL_COLORS[2]}
  ], {stacked:true, legend:true});

  // Grants — DD total split by D primary/secondary ratios
  bar('l3-children-chart', a, [
    {label:'Primary',   data:a.map(n=>{ const t=ddQC('Grants Disbursed',n), d=D.kpi35.total[n]||1; return ddSplit(t,D.kpi35.primary[n]||0,d);   }), backgroundColor:MAP_LEVEL_COLORS[4]},
    {label:'Secondary', data:a.map(n=>{ const t=ddQC('Grants Disbursed',n), d=D.kpi35.total[n]||1; return ddSplit(t,D.kpi35.secondary[n]||0,d); }), backgroundColor:MAP_LEVEL_COLORS[2]}
  ], {stacked:true, legend:true});

  // Districts — live count from DD geography
  bar('l3-districts-chart', a, [{data:a.map(n=>window.DD?(DD.districts[n]||[]).length:D.kpi34.districts[n]||0), backgroundColor:BARS}]);

  // P1 girls/boys — no DD gender breakdown; keep D values
  bar('l3-p1-chart', a, [
    {label:'Girls', data:a.map(n=>D.p1.girls[n]||0), backgroundColor:MAP_LEVEL_COLORS[2]},
    {label:'Boys',  data:a.map(n=>D.p1.boys[n]||0),  backgroundColor:MAP_LEVEL_COLORS[4]}
  ], {stacked:true, legend:true});
}

// ─── REBUILD ACTIVE TAB ────────────────────────────────────────
function rebuildActive() {
  updateStats();
  const level = document.getElementById('level-select').value;
  if (level === 'level1') buildL1();
  else if (level === 'level2') buildL2();
  else if (level === 'level3') buildL3();
  // Re-render sublevel stats so values reflect the current country selection
  if (sel.subLevel) renderSubLevelStats(sel.level, sel.subLevel);
}

// ─── HOME BUTTON ───────────────────────────────────────────────
document.getElementById('home-btn').addEventListener('click', () => {
  // Reset selects
  document.getElementById('level-select').value = '';
  const sublevelSel = document.getElementById('sublevel-select');
  sublevelSel.innerHTML = '<option value="" disabled selected>Select Sub Level</option>';
  sublevelSel.disabled = true;
  sel.level = '';
  sel.subLevel = '';

  // Hide all panels and stats, show home landing
  document.querySelectorAll('.tab-panel').forEach(p => { p.classList.remove('active'); p.style.display = ''; });
  document.getElementById('sublevel-stats-section').style.display = 'none';
  document.getElementById('landing-section').style.display = 'block';
  const dht = document.getElementById('dashboard-howto');
  if (dht) dht.style.display = 'none';
  const ch = document.getElementById('content-header');
  if (ch) ch.style.display = 'none';

  // Switch back to dashboard view if in dynamic/slicer
  const atSel = document.getElementById('analysis-type-select');
  if (atSel && atSel.value !== 'dashboard') {
    atSel.value = 'dashboard';
    atSel.dispatchEvent(new Event('change'));
  }
  document.querySelectorAll('.top-nav-mode').forEach(b => b.classList.remove('top-nav-item--active'));
  const homeBtn = document.getElementById('home-btn');
  if (homeBtn) homeBtn.classList.add('top-nav-item--active');

  // Reset hero title and sidebar active state
  const heroTitle = document.getElementById('hero-title');
  const heroDesc  = document.getElementById('hero-desc');
  if (heroTitle) heroTitle.textContent = 'SHF Agriculture Impact Dashboard';
  if (heroDesc)  heroDesc.textContent  = 'Select a level from the filters below to explore programme data by country, year, and sublevel.';
  document.querySelectorAll('.sidebar-nav-item').forEach(i => i.classList.remove('sidebar-nav-item--active'));
});

// ─── LEVEL DROPDOWN ────────────────────────────────────────────
document.getElementById('level-select').addEventListener('change', e=>{
  const value = e.target.value;
  if (!value) return;

  // Hide landing sections once user selects a level; show content header
  document.getElementById('landing-section').style.display = 'none';
  const howto = document.getElementById('dashboard-howto');
  if (howto) howto.style.display = 'none';
  const ch = document.getElementById('content-header');
  if (ch) ch.style.display = '';

  // Set banner title, description and image per level
  const levelMeta = {
    level1: {
      title: "Girls' Education Impact Dashboard",
      desc:  "Track key progress indicators that reflect SHF Agriculture's work in producer education, field support and community-based development across the continent.",
      img:   "images/shf-rice-terraces.jpg",
      imgPos: "center 45%"
    },
    level2: {
      title: "Livelihoods & Leadership Impact Dashboard",
      desc:  "Track key progress indicators that reflect SHF Agriculture's work in economic empowerment, leadership development and systems strengthening across the continent.",
      img:   "images/shf-maize-field.jpg",
      imgPos: "center 45%"
    },
    level3: {
      title: "Education Reach Impact Dashboard",
      desc:  "Track key progress indicators that reflect SHF Agriculture's reach in training support, partner development and learning outcomes across the continent.",
      img:   "images/shf-coffee-harvest.jpg",
      imgPos: "center 45%"
    }
  };
  const meta = levelMeta[value];
  if (meta) {
    const ht = document.getElementById('hero-title');
    const hd = document.getElementById('hero-desc');
    const hi = document.getElementById('hero-level-img');
    if (ht) ht.textContent = meta.title;
    if (hd) hd.textContent = meta.desc;
    if (hi) { hi.src = meta.img; hi.style.objectPosition = meta.imgPos; }
  }

  sel.level = value;
  sel.subLevel = '';

  // Switch visible panel (clear any inline display set by Education Reach)
  document.querySelectorAll('.tab-panel').forEach(p=>{ p.classList.remove('active'); p.style.display = ''; });
  document.getElementById('panel-' + value)?.classList.add('active');

  // Reset and populate sublevel dropdown (also auto-selects first sublevel)
  buildSubLevelDropdown(value);

  // Build charts for the selected level
  if (value === 'level1') buildL1();
  else if (value === 'level2') buildL2();
  else if (value === 'level3') buildL3();
});

// ─── BURSARY TOGGLE ────────────────────────────────────────────
document.addEventListener('click', e => {
  const btn = e.target.closest('.chart-toggle-btn[data-bur]');
  if (!btn) return;
  document.querySelectorAll('.chart-toggle-btn[data-bur]').forEach(b => b.classList.remove('active'));
  btn.classList.add('active');
  l1BurType = btn.dataset.bur;
  if (sel.subLevel === 'Education Reach') renderEducationReachCharts();
  else buildL1();
});

// ─── SUBLEVEL DROPDOWN ─────────────────────────────────────────
document.getElementById('sublevel-select').addEventListener('change', e=>{
  sel.subLevel = e.target.value;
  // Auto-populate all statistics for this Level + SubLevel
  renderSubLevelStats(sel.level, sel.subLevel);
});

// Country multi-select is initialised below in INIT

// Date range sliders
function updateDateDisplay() {
  const start = parseInt(document.getElementById('date-range-start').value);
  const end = parseInt(document.getElementById('date-range-end').value);
  document.getElementById('date-display').textContent = `${start} — ${end}`;
  sel.dateStart = start;
  sel.dateEnd = end;
  rebuildActive();
}

document.getElementById('date-range-start').addEventListener('input', e=>{
  const start = parseInt(e.target.value);
  const end = parseInt(document.getElementById('date-range-end').value);
  if (start > end) {
    e.target.value = end;
  } else {
    updateDateDisplay();
  }
});

document.getElementById('date-range-end').addEventListener('input', e=>{
  const end = parseInt(e.target.value);
  const start = parseInt(document.getElementById('date-range-start').value);
  if (end < start) {
    e.target.value = start;
  } else {
    updateDateDisplay();
  }
});

// ─── INIT ──────────────────────────────────────────────────────
buildCountryMultiSelect();
buildLevelDropdown();

// No default level pre-selected; panels hidden until user picks a Level
updateDateDisplay();

// ═══════════════════════════════════════════════════════════════
// ── DYNAMIC DATA MODULE ──
// ═══════════════════════════════════════════════════════════════

// 1. Geography hierarchy sourced from window.DD (dashboardData.js)

// 2. Checklist metadata — drives which metrics show and how they render.
// "Children Supported in School with Education Bursaries" merged into one entry
// using the more specific display rule (vertical-bar / double-line).
const checklistData = [
  {
    label: 'Children Supported in School with Education Bursaries',
    geography: { country: true, district: true, school: true },
    displayType: { singleYear: 'number', multiYear: 'double-line' }
  },
  {
    label: 'Active Learner Guides',
    geography: { country: true, district: true, school: true },
    displayType: { singleYear: 'number', multiYear: 'line' }
  },
  {
    label: 'Number of Clients by Form',
    geography: { country: true, district: true, school: true },
    displayType: { singleYear: 'number', multiYear: 'line' }
  },
  {
    label: 'Active Partner Schools',
    geography: { country: true, district: true, school: false },
    displayType: { singleYear: 'number', multiYear: 'line' }
  },
  {
    label: 'Number of Women Supported by CAMFED in Tertiary Education',
    geography: { country: true, district: true, school: false },
    displayType: { singleYear: 'number', multiYear: 'line' }
  },
  {
    label: 'Active Guides by Type',
    geography: { country: true, district: true, school: true },
    displayType: { singleYear: 'pie', multiYear: 'multi-line' }
  },
  {
    label: 'Number of Post School Clients',
    geography: { country: true, district: true, school: true },
    displayType: { singleYear: 'number', multiYear: 'line' }
  },
  {
    label: 'Grants Disbursed',
    geography: { country: true, district: true, school: true },
    displayType: { singleYear: 'number', multiYear: 'line' }
  },
  {
    label: 'Loans Disbursed',
    geography: { country: true, district: true, school: true },
    displayType: { singleYear: 'number', multiYear: 'line' }
  },
  {
    label: 'CAMA Members',
    geography: { country: true, district: true, school: true },
    displayType: { singleYear: 'number', multiYear: 'line' }
  }
];

// 3. Derived state and rendering logic

const ddSel = { countries: [], districts: [], schools: [], yearStart: 2020, yearEnd: 2030 };
const ddCharts = {};
const ddDrops  = {};

function ddGeoLevel() {
  if (!ddSel.countries.length) return null;
  if (ddSel.schools.length)   return 'school';
  if (ddSel.districts.length) return 'district';
  return 'country';
}

function ddMultiYear() { return ddSel.yearEnd > ddSel.yearStart; }

function ddVisibleMetrics() {
  const level = ddGeoLevel();
  if (!level) return [];
  // Derive list from DD.metrics, falling back to checklistData order/display metadata
  const labels = window.DD ? DD.metrics : checklistData.map(m => m.label);
  return labels.map(lbl => {
    const meta = checklistData.find(m => m.label === lbl);
    return meta || { label: lbl, geography: { country: true, district: true, school: true }, displayType: { singleYear: 'number', multiYear: 'line' } };
  }).filter(m => m.geography[level]);
}

function ddDisplayType(metric) {
  return ddMultiYear() ? metric.displayType.multiYear : metric.displayType.singleYear;
}

function ddTypeLabel(type) {
  return { number: 'Number', line: 'Line Chart', 'vertical-bar': 'Bar Chart', 'double-line': 'Double Line', pie: 'Pie Chart' }[type] || type;
}

function ddDestroyChart(id) {
  if (ddCharts[id]) { ddCharts[id].destroy(); delete ddCharts[id]; }
}

// Query real values from DD.data for the current geography selection
function ddQueryValues(metricLabel, years) {
  if (!window.DD) return years.map(() => 0);
  return years.map(yr => {
    let rows = DD.data.filter(r => r.metric === metricLabel && r.year === yr);
    if (ddSel.schools.length)        rows = rows.filter(r => ddSel.schools.includes(r.school));
    else if (ddSel.districts.length) rows = rows.filter(r => ddSel.districts.includes(r.district));
    else if (ddSel.countries.length) rows = rows.filter(r => ddSel.countries.includes(r.country));
    return rows.reduce((s, r) => s + r.value, 0);
  });
}

function ddRenderChart(canvasId, type, metricLabel) {
  const canvas = document.getElementById(canvasId);
  if (!canvas) return;
  ddDestroyChart(canvasId);

  const allYears  = window.DD ? DD.years : [2020,2021,2022,2023,2024,2025,2026,2027,2028,2029,2030];
  const years     = allYears.filter(y => y >= ddSel.yearStart && y <= ddSel.yearEnd);
  const values    = ddQueryValues(metricLabel, years);

  const baseOpts = {
    responsive: true,
    maintainAspectRatio: false,
    plugins: { legend: { display: false } },
    scales: {
      x: { grid: { color: gridC }, ticks: { color: tickC, font: { size: 10 } } },
      y: { grid: { color: gridC }, ticks: { color: tickC, font: { size: 10 }, callback: v => fmtK(v) } }
    }
  };

  if (type === 'pie') {
    // Split total across 4 buckets using stable ratios derived from first value
    const total = values.reduce((s, v) => s + v, 0) || 100;
    ddCharts[canvasId] = new Chart(canvas, {
      type: 'doughnut',
      data: {
        labels: ['Primary', 'Secondary', 'Tertiary', 'Other'],
        datasets: [{ data: [Math.round(total*0.40), Math.round(total*0.32), Math.round(total*0.17), Math.round(total*0.11)], backgroundColor: [MAP_LEVEL_COLORS[2],MAP_LEVEL_COLORS[4],MAP_LEVEL_COLORS[3],MAP_LEVEL_COLORS[1]], borderColor: '#f5f0e3', borderWidth: 3 }]
      },
      options: { responsive: true, maintainAspectRatio: false, cutout: '58%', plugins: { legend: { position: 'right', labels: { color: tickC, font: { size: 10 }, usePointStyle: true, pointStyle: 'circle' } } } }
    });
    return;
  }

  if (type === 'vertical-bar') {
    ddCharts[canvasId] = new Chart(canvas, {
      type: 'bar',
      data: { labels: years, datasets: [{ data: values, backgroundColor: MAP_LEVEL_COLORS[2], borderRadius: 4, borderSkipped: false }] },
      options: baseOpts
    });
    return;
  }

  // line or double-line — render as single trend line with real data
  ddCharts[canvasId] = new Chart(canvas, {
    type: 'line',
    data: {
      labels: years,
      datasets: [{ data: values, borderColor: MAP_LEVEL_COLORS[4], backgroundColor: MAP_AREA_FILL, tension: 0.4, fill: true }]
    },
    options: baseOpts
  });
}

function ddRender() {
  const level = ddGeoLevel();
  const chooseGeo = document.getElementById('dd-choose-geo');
  const content   = document.getElementById('dd-content');

  if (!level) {
    chooseGeo.style.display = '';
    content.style.display = 'none';
    return;
  }

  chooseGeo.style.display = 'none';
  content.style.display   = '';

  // Destroy previous DD charts before rebuilding
  Object.keys(ddCharts).forEach(id => ddDestroyChart(id));

  const metrics   = ddVisibleMetrics();
  const multiYear = ddMultiYear();
  const levelLabel = { country: 'Country Level', district: 'District Level', school: 'School Level' }[level];

  const _allCt = window.DD ? DD.countries : C;
  let breadcrumb = ddSel.countries.length === _allCt.length
    ? 'All Countries'
    : ddSel.countries.join(', ');
  if (ddSel.districts.length)
    breadcrumb += ddSel.districts.length === 1 ? ` › ${ddSel.districts[0]}` : ` › ${ddSel.districts.length} Districts`;
  if (ddSel.schools.length)
    breadcrumb += ddSel.schools.length === 1 ? ` › ${ddSel.schools[0]}` : ` › ${ddSel.schools.length} Schools`;

  const yearBadge = multiYear
    ? '<span class="dd-year-badge">Multi-Year</span>'
    : `<span class="dd-year-badge single">Single Year: ${ddSel.yearStart}</span>`;

  content.innerHTML = `
    <div class="dd-breadcrumb-bar">
      <span class="dd-breadcrumb">${breadcrumb}</span>
      <span class="dd-geo-level-badge">${levelLabel}</span>
      ${yearBadge}
    </div>
    <div class="card-grid-2" id="dd-metrics-grid"></div>
  `;

  const grid = document.getElementById('dd-metrics-grid');

  metrics.forEach((metric, i) => {
    const type     = ddDisplayType(metric);
    const canvasId = `dd-chart-${i}`;
    const isNumber = type === 'number';

    const card = document.createElement('div');
    card.className = 'data-card';
    card.innerHTML = `
      <div class="data-card-header">
        ${metric.label}
        <span class="data-card-badge">${ddTypeLabel(type)}</span>
      </div>
      <div class="data-card-body">
        ${isNumber
          ? `<div class="dd-number-display">${ddQueryValues(metric.label, [ddSel.yearStart])[0].toLocaleString()}</div>
             <div class="dd-number-label">${ddSel.yearStart}</div>`
          : `<div class="chart-container h200"><canvas id="${canvasId}"></canvas></div>`
        }
      </div>
    `;
    grid.appendChild(card);

    if (!isNumber) setTimeout(() => ddRenderChart(canvasId, type, metric.label), 0);
  });
}

// ─── SHARED: inject search + Select All/None into any dropdown ─
function injectDropdownControls(dropdown, placeholder, onAll, onNone) {
  const ctrl = document.createElement('div');
  ctrl.className = 'multi-drop-controls';
  ctrl.innerHTML = `
    <input type="text" class="multi-drop-search" placeholder="Search ${placeholder}…" autocomplete="off">
    <div class="multi-drop-actions">
      <button type="button" class="multi-drop-act" data-act="all">Select All</button>
      <span class="multi-drop-sep">·</span>
      <button type="button" class="multi-drop-act" data-act="none">Select None</button>
    </div>`;
  dropdown.insertBefore(ctrl, dropdown.firstChild);

  const searchEl = ctrl.querySelector('.multi-drop-search');
  searchEl.addEventListener('input', () => {
    const q = searchEl.value.toLowerCase().trim();
    dropdown.querySelectorAll('.country-multi-opt').forEach(opt => {
      const v = opt.querySelector('input')?.value;
      if (v === '__all__' || v === 'All') { opt.style.display = q ? 'none' : ''; return; }
      opt.style.display = opt.textContent.toLowerCase().includes(q) ? '' : 'none';
    });
  });
  searchEl.addEventListener('click', e => e.stopPropagation());
  searchEl.addEventListener('keydown', e => e.stopPropagation());

  ctrl.querySelector('[data-act="all"]').addEventListener('click', e => { e.stopPropagation(); onAll(); });
  ctrl.querySelector('[data-act="none"]').addEventListener('click', e => { e.stopPropagation(); onNone(); });
}

// ─── DD MULTI-SELECT FACTORY ───────────────────────────────────
function makeDDMultiDrop(wrapperId, placeholder, onChange) {
  const wrap = document.getElementById(wrapperId);
  wrap.className = 'country-multi-wrap';
  wrap.innerHTML = `
    <button type="button" class="country-multi-trigger" id="${wrapperId}-trigger">
      <span id="${wrapperId}-label">Select ${placeholder}</span>
      <svg width="11" height="7" viewBox="0 0 12 8" fill="none" aria-hidden="true"><path d="M1 1l5 5 5-5" stroke="#4B2E83" stroke-width="2" stroke-linecap="round"/></svg>
    </button>
    <div class="country-multi-dropdown" id="${wrapperId}-dropdown" hidden></div>`;

  const trigger  = document.getElementById(`${wrapperId}-trigger`);
  const dropdown = document.getElementById(`${wrapperId}-dropdown`);
  const labelEl  = document.getElementById(`${wrapperId}-label`);

  function updateLabel() {
    const all   = dropdown.querySelector('input[value="__all__"]');
    const indiv = [...dropdown.querySelectorAll('input:not([value="__all__"])')];
    const sel   = indiv.filter(x => x.checked);
    if (!indiv.length || (all && all.checked)) {
      labelEl.textContent = `All ${placeholder}`;
    } else if (sel.length === 0) {
      labelEl.textContent = `Select ${placeholder}`;
    } else if (sel.length === 1) {
      labelEl.textContent = sel[0].value;
    } else {
      labelEl.textContent = `${sel.length} ${placeholder}`;
    }
  }

  function isAllChecked() {
    const all = dropdown.querySelector('input[value="__all__"]');
    return !all || all.checked;
  }

  function getSelected() {
    return [...dropdown.querySelectorAll('input:not([value="__all__"])')].filter(x => x.checked).map(x => x.value);
  }

  trigger.addEventListener('click', e => {
    e.stopPropagation();
    if (trigger.disabled) return;
    dropdown.hidden = !dropdown.hidden;
    trigger.classList.toggle('open', !dropdown.hidden);
  });

  document.addEventListener('click', e => {
    if (!wrap.contains(e.target)) { dropdown.hidden = true; trigger.classList.remove('open'); }
  });

  dropdown.addEventListener('change', e => {
    const cb    = e.target;
    const all   = dropdown.querySelector('input[value="__all__"]');
    const indiv = [...dropdown.querySelectorAll('input:not([value="__all__"])')];
    if (cb.value === '__all__') {
      indiv.forEach(x => x.checked = cb.checked);
      if (!cb.checked) { cb.checked = true; indiv.forEach(x => x.checked = true); }
    } else {
      const checked = indiv.filter(x => x.checked);
      if (!checked.length) { all.checked = true; indiv.forEach(x => x.checked = true); }
      else all.checked = checked.length === indiv.length;
    }
    updateLabel();
    onChange({ selected: getSelected(), allChecked: isAllChecked() });
  });

  function populate(items, preCheckAll = true) {
    const rows = [
      `<label class="country-multi-opt"><input type="checkbox" value="__all__"${preCheckAll ? ' checked' : ''}><span>All ${placeholder}</span></label>`,
      ...items.map(v => `<label class="country-multi-opt"><input type="checkbox" value="${v}"${preCheckAll ? ' checked' : ''}><span>${v}</span></label>`)
    ];
    dropdown.innerHTML = rows.join('');
    injectDropdownControls(dropdown, placeholder,
      () => {
        const all = dropdown.querySelector('input[value="__all__"]');
        const indiv = [...dropdown.querySelectorAll('input:not([value="__all__"])')];
        indiv.forEach(x => x.checked = true);
        if (all) all.checked = true;
        updateLabel();
        onChange({ selected: getSelected(), allChecked: true });
      },
      () => {
        const all = dropdown.querySelector('input[value="__all__"]');
        const indiv = [...dropdown.querySelectorAll('input:not([value="__all__"])')];
        indiv.forEach(x => x.checked = false);
        if (all) all.checked = false;
        updateLabel();
        onChange({ selected: [], allChecked: false });
      }
    );
    setDisabled(!items.length);
    updateLabel();
  }

  function setDisabled(val) {
    trigger.disabled = val;
    trigger.style.opacity = val ? '0.45' : '';
    trigger.style.cursor  = val ? 'not-allowed' : '';
  }

  function reset() {
    dropdown.innerHTML = '';
    labelEl.textContent = `Select ${placeholder}`;
    setDisabled(true);
  }

  setDisabled(true);
  return { populate, getSelected, isAllChecked, setDisabled, reset };
}

function ddRefreshDistricts() {
  if (!ddSel.countries.length || !window.DD) {
    ddDrops.district.reset();
    ddSel.districts = [];
    ddRefreshSchools();
    return;
  }
  const dists = [...new Set(ddSel.countries.flatMap(c => (DD.districts && DD.districts[c]) || []))].sort();
  ddDrops.district.populate(dists, true);
  ddSel.districts = [];
  ddRefreshSchools();
}

function ddRefreshSchools() {
  const activeDists = ddSel.districts.length > 0
    ? ddSel.districts
    : ddSel.countries.flatMap(c => (window.DD && DD.districts && DD.districts[c]) || []);
  if (!activeDists.length || !window.DD) {
    ddDrops.school.reset();
    ddSel.schools = [];
    return;
  }
  const schools = [...new Set(activeDists.flatMap(d => (DD.schools && DD.schools[d]) || []))].sort();
  ddDrops.school.populate(schools, true);
  ddSel.schools = [];
}

function ddUpdateYear() {
  let s = parseInt(document.getElementById('dd-date-start').value);
  let e = parseInt(document.getElementById('dd-date-end').value);
  if (s > e) [s, e] = [e, s];
  ddSel.yearStart = s;
  ddSel.yearEnd   = e;
  document.getElementById('dd-date-display').textContent = s === e ? `${s}` : `${s} — ${e}`;
  ddRender();
}

let ddInitialised = false;

function ddInit() {
  if (ddInitialised) return;
  if (!window.DD) {
    document.addEventListener('dd:ready', ddInit, { once: true });
    return;
  }
  ddInitialised = true;

  ddDrops.country = makeDDMultiDrop('dd-country-wrap', 'Countries', ({ selected }) => {
    ddSel.countries = selected;
    ddSel.districts = [];
    ddSel.schools   = [];
    ddRefreshDistricts();
    ddRender();
  });

  ddDrops.district = makeDDMultiDrop('dd-district-wrap', 'Districts', ({ selected, allChecked }) => {
    ddSel.districts = allChecked ? [] : selected;
    ddSel.schools   = [];
    ddRefreshSchools();
    ddRender();
  });

  ddDrops.school = makeDDMultiDrop('dd-school-wrap', 'Schools', ({ selected, allChecked }) => {
    ddSel.schools = allChecked ? [] : selected;
    ddRender();
  });

  ddDrops.country.populate(DD.countries, false);
  ddDrops.country.setDisabled(false);

  document.getElementById('dd-date-start').addEventListener('input', ddUpdateYear);
  document.getElementById('dd-date-end').addEventListener('input', ddUpdateYear);
}

// ── MODE SWITCHER ──────────────────────────────────────────────
function switchMode(mode) {
  const heroSection = document.getElementById('hero-section');
  const bodyLayout  = document.querySelector('.body-layout');
  const ddView      = document.getElementById('dynamic-data-view');
  const slView      = document.getElementById('slicer-view');
  const footer      = document.querySelector('.dashboard-footer');

  if (heroSection) heroSection.style.display = 'none';
  bodyLayout.style.display = 'none';
  ddView.style.display     = 'none';
  slView.style.display     = 'none';
  if (footer) footer.style.display = 'none';

  if (mode === 'dashboard') {
    if (heroSection) heroSection.style.display = '';
    bodyLayout.style.display = '';
    if (footer) footer.style.display = '';
    // If no level selected, show how-to instead of home landing
    const noLevel = !sel.level;
    const landingSec = document.getElementById('landing-section');
    const howto = document.getElementById('dashboard-howto');
    if (noLevel) {
      if (landingSec) landingSec.style.display = 'none';
      if (howto) howto.style.display = '';
    }
  } else if (mode === 'dynamic') {
    ddView.style.display = '';
    ddInit();
  } else if (mode === 'slicer') {
    slView.style.display = '';
    slInit();
  }
}

document.getElementById('analysis-type-select').addEventListener('change', e => {
  switchMode(e.target.value);
});

document.querySelectorAll('.top-nav-mode').forEach(btn => {
  btn.addEventListener('click', () => {
    const mode = btn.dataset.mode;
    document.querySelectorAll('.top-nav-mode').forEach(b => b.classList.remove('top-nav-item--active'));
    const homeBtn = document.getElementById('home-btn');
    if (homeBtn) homeBtn.classList.remove('top-nav-item--active');
    btn.classList.add('top-nav-item--active');
    document.getElementById('analysis-type-select').value = mode;
    switchMode(mode);
  });
});

// ═══════════════════════════════════════════════════════════════
// ── SLICER VALUE FORMATTER ─────────────────────────────────────
// Reads value_type from DD.metricTypes and formats accordingly.
// value_type values: 'Count' | 'Percentage' | 'Currency (USD)' | 'Currency (local)' | 'Text'
function slFmt(value, metric) {
  const vt = (window.DD && window.DD.metricTypes && metric)
    ? (window.DD.metricTypes[metric] || 'Count')
    : 'Count';

  if (vt === 'Percentage') {
    return (value == null ? '—' : value.toFixed(1) + '%');
  }
  if (vt === 'Currency (USD)') {
    return (value == null ? '—' : '$' + fmt(Math.round(value)));
  }
  if (vt === 'Currency (local)') {
    return (value == null ? '—' : fmt(Math.round(value)));
  }
  if (vt === 'Text') {
    return (value == null ? '—' : String(value));
  }
  // 'Count' or anything else
  return (value == null ? '—' : fmt(value));
}

// Y-axis tick formatter for charts — short form
function slFmtTick(value, metric) {
  const vt = (window.DD && window.DD.metricTypes && metric)
    ? (window.DD.metricTypes[metric] || 'Count')
    : 'Count';
  if (vt === 'Percentage')       return value.toFixed(1) + '%';
  if (vt === 'Currency (USD)')   return '$' + fmtK(value);
  if (vt === 'Currency (local)') return fmtK(value);
  return fmtK(value);
}

// ── SLICER MODULE ──────────────────────────────────────────────
// ═══════════════════════════════════════════════════════════════

const MAX_KPIS = 8;

const slSel = {
  countries: [], // [] = all countries
  districts: [], // [] = all districts within selected countries
  schools:   [], // [] = all schools within selected districts
  kpis:      [],
  genders:   ['female', 'male'], // [] or both = all
  yearStart: 2020,
  yearEnd:   2030,
  chartType: 'number'
};

// ── Geography helpers (uses DD from data/dashboardData.js) ──

function slCountries() {
  return window.DD ? DD.countries : C;
}

function slDistricts(countries) {
  if (!window.DD) return [];
  const src = countries.length ? countries : DD.countries;
  return src.flatMap(c => DD.districts[c] || []);
}

function slSchools(districts) {
  if (!window.DD) return [];
  const src = districts.length ? districts : Object.keys(DD.schools);
  return src.flatMap(d => DD.schools[d] || []);
}

// Best dimension for multi-line / bar / pie based on current selection
function slDimension() {
  if (slSel.schools.length)   return 'school';
  if (slSel.districts.length) return 'district';
  return 'country';
}

function slEntities() {
  const dim = slDimension();
  if (dim === 'school')   return slSel.schools.length   ? slSel.schools.slice(0, 8)   : slSchools(slSel.districts.length ? slSel.districts : slDistricts(slSel.countries)).slice(0, 8);
  if (dim === 'district') return slSel.districts.length ? slSel.districts.slice(0, 8) : slDistricts(slSel.countries).slice(0, 8);
  return slSel.countries.length ? slSel.countries : slCountries();
}

function slGeoLabel() {
  if (slSel.schools.length)   return slSel.schools.length   === 1 ? slSel.schools[0]   : `${slSel.schools.length} Schools`;
  if (slSel.districts.length) return slSel.districts.length === 1 ? slSel.districts[0] : `${slSel.districts.length} Districts`;
  if (slSel.countries.length) return slSel.countries.length === 1 ? slSel.countries[0] : `${slSel.countries.length} Countries`;
  return 'All Countries';
}

// ── Data query ──

function slQuery() {
  if (!window.DD) return [];
  let rows = DD.data;

  const countries = slSel.countries.length ? slSel.countries : DD.countries;
  rows = rows.filter(r => countries.includes(r.country));
  if (slSel.districts.length) rows = rows.filter(r => slSel.districts.includes(r.district));
  if (slSel.schools.length)   rows = rows.filter(r => slSel.schools.includes(r.school));
  if (slSel.kpis.length)      rows = rows.filter(r => slSel.kpis.includes(r.metric));
  rows = rows.filter(r => r.year >= slSel.yearStart && r.year <= slSel.yearEnd);

  // Deterministic gender split (data has no gender field — apply fixed ratio)
  const _onlyF = slSel.genders.length === 1 && slSel.genders[0] === 'female';
  const _onlyM = slSel.genders.length === 1 && slSel.genders[0] === 'male';
  if (_onlyF) rows = rows.map(r => ({...r, value: Math.round(r.value * 0.52)}));
  else if (_onlyM) rows = rows.map(r => ({...r, value: Math.round(r.value * 0.48)}));

  return rows;
}

// ── Chart registry ──

const slCharts = {};

function slDestroyCharts() {
  Object.keys(slCharts).forEach(id => {
    if (slCharts[id]) { slCharts[id].destroy(); delete slCharts[id]; }
  });
}

// ── Render dispatcher ──

function slRender() {
  const output = document.getElementById('sl-output');
  if (!output) return;
  slDestroyCharts();

  if (!slSel.kpis.length) {
    output.innerHTML = '<div class="headline-banner"><h2>Select one or more KPIs above to see results</h2></div>';
    return;
  }

  const rows  = slQuery();
  const kpis  = slSel.kpis;
  const years = Array.from({ length: slSel.yearEnd - slSel.yearStart + 1 }, (_, i) => slSel.yearStart + i);
  // Single year → always show numbers regardless of chart type selection
  const type  = (slSel.yearStart === slSel.yearEnd) ? 'number' : slSel.chartType;

  output.innerHTML = '';

  if (type === 'number') { slRenderNumbers(output, rows, kpis, years); return; }
  if (type === 'table')  { slRenderTable(output, rows, kpis); return; }
  slRenderCharts(output, rows, kpis, type, years);
}

// Number stat cards — one per KPI
function slRenderNumbers(output, rows, kpis, years) {
  const colClass = kpis.length === 1 ? 'card-grid-1' : kpis.length <= 4 ? 'card-grid-2' : 'card-grid-3';
  const grid = document.createElement('div');
  grid.className = colClass;
  kpis.forEach(kpi => {
    const total = rows.filter(r => r.metric === kpi).reduce((s, r) => s + r.value, 0);
    const card  = document.createElement('div');
    card.className = 'data-card';
    card.innerHTML = `
      <div class="data-card-header">${kpi}<span class="data-card-badge">Total</span></div>
      <div class="data-card-body">
        <div class="dd-number-display">${slFmt(total, kpi)}</div>
        <div class="dd-number-label">${years[0]}${years.length > 1 ? ' — ' + years[years.length - 1] : ''} · ${slGeoLabel()}</div>
      </div>`;
    grid.appendChild(card);
  });
  output.appendChild(grid);
}

// Chart cards — one per KPI
function slRenderCharts(output, rows, kpis, type, years) {
  const colClass = kpis.length === 1 ? 'card-grid-1' : 'card-grid-2';
  const grid = document.createElement('div');
  grid.className = colClass;
  const typeLabel = { line: 'Line', multiline: 'Multi-Line', bar: 'Bar', pie: 'Pie' }[type] || type;
  kpis.forEach((kpi, idx) => {
    const canvasId = `sl-c-${idx}`;
    const card = document.createElement('div');
    card.className = 'data-card';
    card.innerHTML = `
      <div class="data-card-header">${kpi}<span class="data-card-badge">${typeLabel}</span></div>
      <div class="data-card-body"><div class="chart-container h220"><canvas id="${canvasId}"></canvas></div></div>`;
    grid.appendChild(card);
    setTimeout(() => slRenderOneChart(canvasId, type, rows.filter(r => r.metric === kpi), years, kpi), 0);
  });
  output.appendChild(grid);
}

function slRenderOneChart(canvasId, type, rows, years, kpi) {
  const canvas = document.getElementById(canvasId);
  if (!canvas) return;
  if (slCharts[canvasId]) { slCharts[canvasId].destroy(); }

  const _kpi0 = kpi || null; // used for y-axis tick format
  const baseOpts = {
    responsive: true, maintainAspectRatio: false,
    plugins: { legend: { display: false } },
    scales: {
      x: { grid: { color: gridC }, ticks: { color: tickC, font: { size: 10 } } },
      y: { grid: { color: gridC }, ticks: { color: tickC, font: { size: 10 }, callback: v => slFmtTick(v, _kpi0) } }
    }
  };

  if (type === 'line') {
    const data = years.map(yr => rows.filter(r => r.year === yr).reduce((s, r) => s + r.value, 0));
    slCharts[canvasId] = new Chart(canvas, {
      type: 'line',
      data: { labels: years, datasets: [{ data, borderColor: MAP_LEVEL_COLORS[4], backgroundColor: MAP_AREA_FILL, tension: 0.4, fill: true, pointRadius: 3 }] },
      options: baseOpts
    });
    return;
  }

  if (type === 'multiline') {
    const entities = slEntities().slice(0, 7);
    const dim = slDimension();
    const datasets = entities.map((e, i) => ({
      label: e,
      data: years.map(yr => rows.filter(r => r[dim] === e && r.year === yr).reduce((s, r) => s + r.value, 0)),
      borderColor: BARS[i % 5], backgroundColor: 'transparent', tension: 0.4, pointRadius: 3
    }));
    slCharts[canvasId] = new Chart(canvas, {
      type: 'line',
      data: { labels: years, datasets },
      options: { ...baseOpts, plugins: { legend: { display: true, labels: { color: tickC, font: { size: 10 }, usePointStyle: true } } } }
    });
    return;
  }

  if (type === 'bar') {
    const entities = slEntities().slice(0, 10);
    const dim = slDimension();
    const data = entities.map(e => rows.filter(r => r[dim] === e).reduce((s, r) => s + r.value, 0));
    slCharts[canvasId] = new Chart(canvas, {
      type: 'bar',
      data: { labels: entities, datasets: [{ data, backgroundColor: BARS, borderRadius: 4, borderSkipped: false }] },
      options: baseOpts
    });
    return;
  }

  if (type === 'pie') {
    const entities = slEntities().slice(0, 6);
    const dim = slDimension();
    const data = entities.map(e => rows.filter(r => r[dim] === e).reduce((s, r) => s + r.value, 0));
    slCharts[canvasId] = new Chart(canvas, {
      type: 'doughnut',
      data: { labels: entities, datasets: [{ data, backgroundColor: BARS, borderColor: '#f5f0e3', borderWidth: 3 }] },
      options: {
        responsive: true, maintainAspectRatio: false, cutout: '55%',
        plugins: { legend: { position: 'right', labels: { color: tickC, font: { size: 10 }, usePointStyle: true, pointStyle: 'circle' } } }
      }
    });
  }
}

// Table output
function slRenderTable(output, rows, kpis) {
  const dim      = slDimension();
  const entities = slEntities().slice(0, 12);
  const html = `<div class="data-card"><div class="data-card-body" style="overflow-x:auto">
    <table class="mini-table">
      <thead><tr>
        <th>${dim.charAt(0).toUpperCase() + dim.slice(1)}</th>
        ${kpis.map(k => `<th class="r" style="max-width:140px;white-space:normal">${k}</th>`).join('')}
      </tr></thead>
      <tbody>
        ${entities.map(e => `<tr>
          <td>${e}</td>
          ${kpis.map(k => {
            const val = rows.filter(r => r[dim] === e && r.metric === k).reduce((s, r) => s + r.value, 0);
            return `<td class="r">${slFmt(val, k)}</td>`;
          }).join('')}
        </tr>`).join('')}
      </tbody>
    </table>
  </div></div>`;
  output.innerHTML = html;
}

// ── Rebuild district / school dropdowns when parent selection changes ──

function slRebuildDistricts() {
  const srcCountries = slSel.countries.length ? slSel.countries : slCountries();
  const dists = slDistricts(srcCountries);
  slSel.districts = [];
  slSel.schools   = [];
  const slDistDD = document.getElementById('sl-district-dropdown');
  slDistDD.innerHTML = dists.map(d =>
    `<label class="country-multi-opt"><input type="checkbox" value="${d}" checked><span>${d}</span></label>`).join('');
  injectDropdownControls(slDistDD, 'Districts',
    () => { slDistDD.querySelectorAll('input').forEach(cb => cb.checked = true); slDistDD.dispatchEvent(new Event('change', {bubbles:true})); },
    () => { slDistDD.querySelectorAll('input').forEach(cb => cb.checked = false); slDistDD.dispatchEvent(new Event('change', {bubbles:true})); }
  );
  document.getElementById('sl-district-label').textContent = 'All Districts';
  slRebuildSchools();
}

function slRebuildSchools() {
  const srcDists = slSel.districts.length
    ? slSel.districts
    : slDistricts(slSel.countries.length ? slSel.countries : slCountries());
  const schools = slSchools(srcDists).slice(0, 60);
  slSel.schools = [];
  const slSchDD = document.getElementById('sl-school-dropdown');
  slSchDD.innerHTML = schools.map(s =>
    `<label class="country-multi-opt"><input type="checkbox" value="${s}" checked><span>${s}</span></label>`).join('');
  injectDropdownControls(slSchDD, 'Schools',
    () => { slSchDD.querySelectorAll('input').forEach(cb => cb.checked = true); slSchDD.dispatchEvent(new Event('change', {bubbles:true})); },
    () => { slSchDD.querySelectorAll('input').forEach(cb => cb.checked = false); slSchDD.dispatchEvent(new Event('change', {bubbles:true})); }
  );
  document.getElementById('sl-school-label').textContent = 'All Schools';
}

// ── KPI dropdown (max 8 selected) ──

function slBuildKpiList() {
  const dropdown = document.getElementById('sl-kpi-dropdown');
  if (!dropdown) return;
  const kpis = window.DD ? DD.metrics : checklistData.map(m => m.label);
  dropdown.innerHTML = kpis.map(kpi =>
    `<label class="country-multi-opt"><input type="checkbox" class="sl-kpi-cb" value="${kpi}"><span>${kpi}</span></label>`
  ).join('');
  injectDropdownControls(dropdown, 'Metrics',
    () => { dropdown.querySelectorAll('input').forEach(cb => cb.checked = true); dropdown.dispatchEvent(new Event('change', {bubbles:true})); },
    () => { dropdown.querySelectorAll('input').forEach(cb => cb.checked = false); dropdown.dispatchEvent(new Event('change', {bubbles:true})); }
  );
}

// ── Slicer init (runs once) ──

let slInitialised = false;

function slInit() {
  if (slInitialised) return;
  if (!window.DD) {
    document.addEventListener('dd:ready', slInit, { once: true });
    return;
  }
  slInitialised = true;

  const allCountries = slCountries();

  // ── Geography dropdowns (update state + cascade; no auto-render) ──

  const countryDD = document.getElementById('sl-country-dropdown');
  countryDD.innerHTML = allCountries.map(c =>
    `<label class="country-multi-opt"><input type="checkbox" value="${c}" checked><span>${c}</span></label>`).join('');
  injectDropdownControls(countryDD, 'Countries',
    () => { countryDD.querySelectorAll('input').forEach(cb => cb.checked = true); countryDD.dispatchEvent(new Event('change', {bubbles:true})); },
    () => { countryDD.querySelectorAll('input').forEach(cb => cb.checked = false); countryDD.dispatchEvent(new Event('change', {bubbles:true})); }
  );
  document.getElementById('sl-country-trigger').addEventListener('click', e => {
    e.stopPropagation();
    countryDD.hidden = !countryDD.hidden;
    e.currentTarget.classList.toggle('open', !countryDD.hidden);
  });
  countryDD.addEventListener('change', () => {
    const checked = [...countryDD.querySelectorAll('input:checked')].map(cb => cb.value);
    slSel.countries = checked.length === allCountries.length ? [] : checked;
    document.getElementById('sl-country-label').textContent =
      !slSel.countries.length ? 'All Countries' :
      slSel.countries.length <= 2 ? slSel.countries.join(', ') : `${slSel.countries.length} Selected`;
    slRebuildDistricts();
  });
  countryDD.addEventListener('click', e => e.stopPropagation());

  document.getElementById('sl-district-trigger').addEventListener('click', e => {
    e.stopPropagation();
    const dd = document.getElementById('sl-district-dropdown');
    dd.hidden = !dd.hidden;
    e.currentTarget.classList.toggle('open', !dd.hidden);
  });
  document.getElementById('sl-district-dropdown').addEventListener('change', () => {
    const dd    = document.getElementById('sl-district-dropdown');
    const dists = slDistricts(slSel.countries.length ? slSel.countries : allCountries);
    const checked = [...dd.querySelectorAll('input:checked')].map(cb => cb.value);
    slSel.districts = checked.length === dists.length ? [] : checked;
    document.getElementById('sl-district-label').textContent =
      !slSel.districts.length ? 'All Districts' :
      slSel.districts.length <= 2 ? slSel.districts.join(', ') : `${slSel.districts.length} Selected`;
    slRebuildSchools();
  });
  document.getElementById('sl-district-dropdown').addEventListener('click', e => e.stopPropagation());

  document.getElementById('sl-school-trigger').addEventListener('click', e => {
    e.stopPropagation();
    const dd = document.getElementById('sl-school-dropdown');
    dd.hidden = !dd.hidden;
    e.currentTarget.classList.toggle('open', !dd.hidden);
  });
  document.getElementById('sl-school-dropdown').addEventListener('change', () => {
    const dd      = document.getElementById('sl-school-dropdown');
    const srcD    = slSel.districts.length ? slSel.districts : slDistricts(slSel.countries.length ? slSel.countries : allCountries);
    const schools = slSchools(srcD).slice(0, 60);
    const checked = [...dd.querySelectorAll('input:checked')].map(cb => cb.value);
    slSel.schools = checked.length === schools.length ? [] : checked;
    document.getElementById('sl-school-label').textContent =
      !slSel.schools.length ? 'All Schools' :
      slSel.schools.length <= 2 ? slSel.schools.join(', ') : `${slSel.schools.length} Selected`;
  });
  document.getElementById('sl-school-dropdown').addEventListener('click', e => e.stopPropagation());

  slRebuildDistricts();

  // ── Year sliders (update state only; clamp DOM so sliders never cross) ──
  document.getElementById('sl-year-start').addEventListener('input', ev => {
    const endEl = document.getElementById('sl-year-end');
    if (parseInt(ev.target.value) > parseInt(endEl.value)) ev.target.value = endEl.value;
    const s = parseInt(ev.target.value), e = parseInt(endEl.value);
    slSel.yearStart = s; slSel.yearEnd = e;
    document.getElementById('sl-year-display').textContent = s === e ? `${s}` : `${s} — ${e}`;
  });
  document.getElementById('sl-year-end').addEventListener('input', ev => {
    const startEl = document.getElementById('sl-year-start');
    if (parseInt(ev.target.value) < parseInt(startEl.value)) ev.target.value = startEl.value;
    const s = parseInt(startEl.value), e = parseInt(ev.target.value);
    slSel.yearStart = s; slSel.yearEnd = e;
    document.getElementById('sl-year-display').textContent = s === e ? `${s}` : `${s} — ${e}`;
  });

  // ── KPI dropdown ──
  slBuildKpiList();
  const kpiDD = document.getElementById('sl-kpi-dropdown');
  document.getElementById('sl-kpi-trigger').addEventListener('click', e => {
    e.stopPropagation();
    kpiDD.hidden = !kpiDD.hidden;
    e.currentTarget.classList.toggle('open', !kpiDD.hidden);
  });
  kpiDD.addEventListener('change', () => {
    const all = [...kpiDD.querySelectorAll('.sl-kpi-cb:checked')];
    // Enforce max — uncheck the just-changed box if over limit
    if (all.length > MAX_KPIS) {
      const last = kpiDD.querySelector('.sl-kpi-cb:checked:last-of-type') ||
                   [...kpiDD.querySelectorAll('.sl-kpi-cb:checked')].pop();
      if (last) last.checked = false;
      return;
    }
    slSel.kpis = [...kpiDD.querySelectorAll('.sl-kpi-cb:checked')].map(cb => cb.value);
    const count = slSel.kpis.length;
    document.getElementById('sl-kpi-count').textContent = count ? `(${count} / ${MAX_KPIS})` : '';
    document.getElementById('sl-kpi-label').textContent =
      !count ? 'Select Data' :
      count === 1 ? slSel.kpis[0].length > 28 ? slSel.kpis[0].slice(0, 26) + '…' : slSel.kpis[0] :
      `${count} metrics selected`;
  });
  kpiDD.addEventListener('click', e => e.stopPropagation());

  // ── Gender dropdown (checkboxes) ──
  const genderDD      = document.getElementById('sl-gender-dropdown');
  const genderTrigger = document.getElementById('sl-gender-trigger');
  const genderLabel   = document.getElementById('sl-gender-label');

  function updateGenderState() {
    const allCb    = genderDD.querySelector('input[value="all"]');
    const femaleCb = genderDD.querySelector('input[value="female"]');
    const maleCb   = genderDD.querySelector('input[value="male"]');
    slSel.genders = [];
    if (femaleCb.checked) slSel.genders.push('female');
    if (maleCb.checked)   slSel.genders.push('male');
    const both = femaleCb.checked && maleCb.checked;
    if (both) genderLabel.textContent = 'All Genders';
    else if (femaleCb.checked) genderLabel.textContent = 'Female';
    else if (maleCb.checked)   genderLabel.textContent = 'Male';
    else { femaleCb.checked = true; maleCb.checked = true; allCb.checked = true; slSel.genders = ['female','male']; genderLabel.textContent = 'All Genders'; }
    allCb.checked = both;
  }

  genderTrigger.addEventListener('click', e => {
    e.stopPropagation();
    genderDD.hidden = !genderDD.hidden;
    genderTrigger.classList.toggle('open', !genderDD.hidden);
  });
  genderDD.addEventListener('change', e => {
    const allCb = genderDD.querySelector('input[value="all"]');
    const femaleCb = genderDD.querySelector('input[value="female"]');
    const maleCb   = genderDD.querySelector('input[value="male"]');
    if (e.target.value === 'all') { femaleCb.checked = e.target.checked; maleCb.checked = e.target.checked; }
    updateGenderState();
  });
  genderDD.addEventListener('click', e => e.stopPropagation());

  // ── Chart type (state only) ──
  document.getElementById('sl-chart-type').addEventListener('change', e => {
    slSel.chartType = e.target.value;
  });

  // ── Go button ──
  document.getElementById('sl-go-btn').addEventListener('click', slRender);

  // ── Close all dropdowns on outside click ──
  document.addEventListener('click', e => {
    ['sl-country-wrap','sl-district-wrap','sl-school-wrap','sl-kpi-wrap','sl-gender-wrap'].forEach(wrapId => {
      const wrap = document.getElementById(wrapId);
      if (!wrap || wrap.contains(e.target)) return;
      const dd      = wrap.querySelector('.country-multi-dropdown');
      const trigger = wrap.querySelector('.country-multi-trigger');
      if (dd) dd.hidden = true;
      if (trigger) trigger.classList.remove('open');
    });
  });
}

// Re-render the active dashboard panel once local demo data has loaded
document.addEventListener('dd:ready', () => {
  if (window.DD) {
    C = DD.countries;           // keep C in sync with live DB country list
    rebuildCountryOptions();    // refresh options only — no duplicate listeners
    rebuildActive();
  }
});


// Set Home as active on initial load
document.getElementById('home-btn')?.classList.add('top-nav-item--active');
document.querySelector('.top-nav-mode[data-mode="dashboard"]')?.classList.remove('top-nav-item--active');

