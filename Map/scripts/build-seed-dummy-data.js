const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const inputFile = path.join(root, "optimized", "priority_adm2_simplified.geojson");
const outputFile = path.join(root, "seed-dummy-data.sql");
const chunksDir = path.join(root, "seed-sql-chunks");
const chunkSize = 80;

const ISO_TO_COUNTRY = {
  GHA: { slug: "ghana", name: "Ghana" },
  MWI: { slug: "malawi", name: "Malawi" },
  TZA: { slug: "tanzania", name: "Tanzania" },
  ZMB: { slug: "zambia", name: "Zambia" },
  ZWE: { slug: "zimbabwe", name: "Zimbabwe" },
};

const countrySeeds = {
  ghana: 17000,
  malawi: 9000,
  tanzania: 14000,
  zambia: 12000,
  zimbabwe: 10000,
};

function sqlQuote(value) {
  return String(value).replace(/'/g, "''");
}

function hashString(value) {
  let hash = 0;
  for (let index = 0; index < value.length; index += 1) {
    hash = (hash * 31 + value.charCodeAt(index)) >>> 0;
  }
  return hash;
}

function createKpis(countrySlug, districtName) {
  const hash = hashString(`${countrySlug}:${districtName}`);
  const base = countrySeeds[countrySlug] + (hash % 18000);
  const multiplier = 0.55 + ((hash % 100) / 100) * 0.9;
  const bursaries = Math.round(base * multiplier);
  const girls = Math.round(bursaries * (0.52 + ((hash >> 4) % 8) / 100));
  const boys = Math.max(0, bursaries - girls);
  const schools = 18 + (hash % 150);
  const guides = 35 + (hash % 420);
  const grants = bursaries * (5 + (hash % 7));
  const loans = Math.round(grants * (0.18 + ((hash >> 6) % 20) / 100));

  return {
    years: {
      2020: withGrowth(bursaries, guides, grants, 0.62),
      2021: withGrowth(bursaries, guides, grants, 0.7),
      2022: withGrowth(bursaries, guides, grants, 0.78),
      2023: withGrowth(bursaries, guides, grants, 0.86),
      2024: withGrowth(bursaries, guides, grants, 0.93),
      2025: withGrowth(bursaries, guides, grants, 1),
      2026: withGrowth(bursaries, guides, grants, 1.06),
      2027: withGrowth(bursaries, guides, grants, 1.11),
      2028: withGrowth(bursaries, guides, grants, 1.16),
      2029: withGrowth(bursaries, guides, grants, 1.2),
      2030: withGrowth(bursaries, guides, grants, 1.24),
    },
    education_bursaries_children: bursaries,
    education_bursaries_children_annual: Math.round(bursaries * 0.12),
    education_bursaries_children_cumulative_2020_2030: Math.round(bursaries * 4.9),
    education_bursaries_children_cumulative_all_time: Math.round(bursaries * 6.2),
    active_learner_guides: guides,
    clients_by_form: bursaries + Math.round(bursaries * 0.18),
    clients_by_form_girls: girls,
    clients_by_form_boys: boys,
    active_partner_schools: schools,
    women_supported_tertiary: Math.round(girls * 0.035),
    active_guides_by_type: guides + Math.round(guides * 0.35),
    post_school_clients: Math.round(bursaries * 0.28),
    grants_disbursed: grants,
    loans_disbursed: loans,
    cama_members: Math.round(girls * 0.42),
    active_guides_transition: Math.round(guides * 0.22),
    active_guides_agriculture: Math.round(guides * 0.17),
    active_guides_business: Math.round(guides * 0.14),
    grants_distributed_count: Math.round(grants / 650),
  };
}

function withGrowth(bursaries, guides, grants, ratio) {
  return {
    education_bursaries_children: Math.round(bursaries * ratio),
    active_learner_guides: Math.round(guides * ratio),
    grants_disbursed: Math.round(grants * ratio),
  };
}

function getEnvelope(feature) {
  const points = [];
  collectPoints(feature.geometry.coordinates, points);

  const lngs = points.map((point) => point[0]);
  const lats = points.map((point) => point[1]);
  return {
    minLng: Math.min(...lngs),
    minLat: Math.min(...lats),
    maxLng: Math.max(...lngs),
    maxLat: Math.max(...lats),
  };
}

function collectPoints(value, points) {
  if (typeof value[0] === "number" && typeof value[1] === "number") {
    points.push(value);
    return;
  }

  value.forEach((item) => collectPoints(item, points));
}

function createSeedRows() {
  const geojson = JSON.parse(fs.readFileSync(inputFile, "utf8"));
  return geojson.features.map((feature) => {
      const country = ISO_TO_COUNTRY[feature.properties.shapeGroup];
      const districtName = feature.properties.shapeName;
      const envelope = getEnvelope(feature);
      const kpis = createKpis(country.slug, districtName);
      const programCount = 4 + (hashString(districtName) % 24);
      const beneficiaryCount = kpis.education_bursaries_children;
      const riskScore = 10 + (hashString(`${districtName}:risk`) % 70);

      return `(
  '${country.slug}',
  '${country.name}',
  '${sqlQuote(districtName)}',
  ${programCount},
  ${beneficiaryCount},
  ${riskScore},
  '${JSON.stringify(kpis).replace(/'/g, "''")}'::jsonb,
  st_multi(st_makeenvelope(${envelope.minLng}, ${envelope.minLat}, ${envelope.maxLng}, ${envelope.maxLat}, 4326))
)`;
    });
}

function getSetupSql() {
  return `create extension if not exists postgis;

create table if not exists public.district_boundaries (
  id uuid primary key default gen_random_uuid(),
  country_slug text not null,
  country_name text not null,
  district_name text not null,
  program_count integer not null default 0,
  beneficiary_count integer not null default 0,
  risk_score numeric not null default 0,
  kpis jsonb not null default '{}'::jsonb,
  geom geometry(MultiPolygon, 4326) not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table public.district_boundaries
  add column if not exists kpis jsonb not null default '{}'::jsonb;

truncate table public.district_boundaries;
`;
}

function getInsertSql(rows) {
  return `
insert into public.district_boundaries (
  country_slug,
  country_name,
  district_name,
  program_count,
  beneficiary_count,
  risk_score,
  kpis,
  geom
)
values
${rows.join(",\n")};
`;
}

function getFinalizeSql() {
  return `
create index if not exists district_boundaries_country_idx
  on public.district_boundaries (country_slug);

create index if not exists district_boundaries_geom_idx
  on public.district_boundaries
  using gist (geom);

drop view if exists public.district_boundaries_geojson;

create view public.district_boundaries_geojson
with (security_invoker = true) as
select
  id,
  country_slug,
  country_name,
  district_name,
  program_count,
  beneficiary_count,
  risk_score,
  kpis,
  st_asgeojson(geom)::json as geometry
from public.district_boundaries;

alter table public.district_boundaries enable row level security;

drop policy if exists "Public read district boundaries"
  on public.district_boundaries;

create policy "Public read district boundaries"
  on public.district_boundaries
  for select
  to anon
  using (true);

grant usage on schema public to anon, authenticated;
grant select on public.district_boundaries to anon, authenticated;
grant select on public.district_boundaries_geojson to anon, authenticated;
`;
}

function buildSql() {
  const rows = createSeedRows();
  return `${getSetupSql()}${getInsertSql(rows)}${getFinalizeSql()}`;
}

function writeChunkedSql() {
  const rows = createSeedRows();
  fs.rmSync(chunksDir, { recursive: true, force: true });
  fs.mkdirSync(chunksDir, { recursive: true });
  fs.writeFileSync(path.join(chunksDir, "01_setup.sql"), getSetupSql());

  for (let index = 0; index < rows.length; index += chunkSize) {
    const chunkNumber = String(index / chunkSize + 2).padStart(2, "0");
    const chunkRows = rows.slice(index, index + chunkSize);
    fs.writeFileSync(path.join(chunksDir, `${chunkNumber}_insert_rows.sql`), getInsertSql(chunkRows));
  }

  const finalNumber = String(Math.ceil(rows.length / chunkSize) + 2).padStart(2, "0");
  fs.writeFileSync(path.join(chunksDir, `${finalNumber}_finalize.sql`), getFinalizeSql());
}

fs.writeFileSync(outputFile, buildSql());
writeChunkedSql();
console.log(`Wrote ${outputFile}`);
console.log(`Wrote chunked SQL files to ${chunksDir}`);
