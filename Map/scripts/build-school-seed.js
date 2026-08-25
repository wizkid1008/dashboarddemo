const fs = require("fs");
const path = require("path");

const root = path.resolve(__dirname, "..");
const inputFile = "C:\\Users\\Sisters\\Downloads\\schools_final.csv";
const chunksDir = path.join(root, "school-sql-chunks");
const importDir = path.join(root, "school-import");
const chunkSize = 100;

const countrySlugs = {
  Ghana: "ghana",
  Malawi: "malawi",
  Tanzania: "tanzania",
  Zambia: "zambia",
  Zimbabwe: "zimbabwe",
};

function parseCsv(text) {
  const rows = [];
  let row = [];
  let cell = "";
  let inQuotes = false;

  for (let index = 0; index < text.length; index += 1) {
    const char = text[index];
    const next = text[index + 1];

    if (char === '"' && inQuotes && next === '"') {
      cell += '"';
      index += 1;
    } else if (char === '"') {
      inQuotes = !inQuotes;
    } else if (char === "," && !inQuotes) {
      row.push(cell);
      cell = "";
    } else if ((char === "\n" || char === "\r") && !inQuotes) {
      if (char === "\r" && next === "\n") index += 1;
      row.push(cell);
      if (row.some((value) => value !== "")) rows.push(row);
      row = [];
      cell = "";
    } else {
      cell += char;
    }
  }

  if (cell || row.length > 0) {
    row.push(cell);
    rows.push(row);
  }

  const headers = rows.shift();
  return rows.map((values) =>
    Object.fromEntries(headers.map((header, index) => [header, values[index] || ""]))
  );
}

function sqlQuote(value) {
  return String(value || "").replace(/'/g, "''");
}

function csvQuote(value) {
  const text = String(value ?? "");
  return `"${text.replace(/"/g, '""')}"`;
}

function hashString(value) {
  let hash = 0;
  for (let index = 0; index < value.length; index += 1) {
    hash = (hash * 31 + value.charCodeAt(index)) >>> 0;
  }
  return hash;
}

function withGrowth(value, ratio) {
  return Math.round(value * ratio);
}

function createKpis(row) {
  const hash = hashString(`${row.country}:${row.district}:${row.school_name}:${row.id}`);
  const bursaries = 25 + (hash % 420);
  const guides = 2 + (hash % 28);
  const grants = bursaries * (80 + (hash % 110));
  const girls = Math.round(bursaries * (0.5 + ((hash >> 4) % 10) / 100));
  const boys = Math.max(0, bursaries - girls);

  return {
    years: {
      2020: {
        education_bursaries_children: withGrowth(bursaries, 0.6),
        active_learner_guides: withGrowth(guides, 0.6),
        grants_disbursed: withGrowth(grants, 0.6),
      },
      2021: {
        education_bursaries_children: withGrowth(bursaries, 0.68),
        active_learner_guides: withGrowth(guides, 0.68),
        grants_disbursed: withGrowth(grants, 0.68),
      },
      2022: {
        education_bursaries_children: withGrowth(bursaries, 0.76),
        active_learner_guides: withGrowth(guides, 0.76),
        grants_disbursed: withGrowth(grants, 0.76),
      },
      2023: {
        education_bursaries_children: withGrowth(bursaries, 0.84),
        active_learner_guides: withGrowth(guides, 0.84),
        grants_disbursed: withGrowth(grants, 0.84),
      },
      2024: {
        education_bursaries_children: withGrowth(bursaries, 0.92),
        active_learner_guides: withGrowth(guides, 0.92),
        grants_disbursed: withGrowth(grants, 0.92),
      },
      2025: {
        education_bursaries_children: bursaries,
        active_learner_guides: guides,
        grants_disbursed: grants,
      },
      2026: {
        education_bursaries_children: withGrowth(bursaries, 1.06),
        active_learner_guides: withGrowth(guides, 1.06),
        grants_disbursed: withGrowth(grants, 1.06),
      },
      2027: {
        education_bursaries_children: withGrowth(bursaries, 1.12),
        active_learner_guides: withGrowth(guides, 1.12),
        grants_disbursed: withGrowth(grants, 1.12),
      },
      2028: {
        education_bursaries_children: withGrowth(bursaries, 1.18),
        active_learner_guides: withGrowth(guides, 1.18),
        grants_disbursed: withGrowth(grants, 1.18),
      },
      2029: {
        education_bursaries_children: withGrowth(bursaries, 1.23),
        active_learner_guides: withGrowth(guides, 1.23),
        grants_disbursed: withGrowth(grants, 1.23),
      },
      2030: {
        education_bursaries_children: withGrowth(bursaries, 1.28),
        active_learner_guides: withGrowth(guides, 1.28),
        grants_disbursed: withGrowth(grants, 1.28),
      },
    },
    education_bursaries_children: bursaries,
    education_bursaries_children_annual: Math.round(bursaries * 0.18),
    education_bursaries_children_cumulative_2020_2030: Math.round(bursaries * 7.2),
    education_bursaries_children_cumulative_all_time: Math.round(bursaries * 8.8),
    active_learner_guides: guides,
    clients_by_form: bursaries + Math.round(bursaries * 0.25),
    clients_by_form_girls: girls,
    clients_by_form_boys: boys,
    active_partner_schools: 1,
    women_supported_tertiary: Math.round(girls * 0.08),
    active_guides_by_type: guides + Math.round(guides * 0.25),
    post_school_clients: Math.round(bursaries * 0.24),
    grants_disbursed: grants,
    loans_disbursed: Math.round(grants * 0.18),
    cama_members: Math.round(girls * 0.36),
    active_guides_transition: Math.round(guides * 0.25),
    active_guides_agriculture: Math.round(guides * 0.18),
    active_guides_business: Math.round(guides * 0.14),
    grants_distributed_count: Math.max(1, Math.round(grants / 2500)),
  };
}

function getSetupSql() {
  return `create table if not exists public.schools (
  school_id text primary key,
  school_name text not null,
  country_slug text not null,
  country_name text not null,
  district_name text not null,
  province text,
  latitude numeric not null,
  longitude numeric not null,
  geo_source text,
  kpis jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

truncate table public.schools;
`;
}

function getInsertSql(rows) {
  return `insert into public.schools (
  school_id,
  school_name,
  country_slug,
  country_name,
  district_name,
  province,
  latitude,
  longitude,
  geo_source,
  kpis
)
values
${rows.join(",\n")}
on conflict (school_id) do update set
  school_name = excluded.school_name,
  country_slug = excluded.country_slug,
  country_name = excluded.country_name,
  district_name = excluded.district_name,
  province = excluded.province,
  latitude = excluded.latitude,
  longitude = excluded.longitude,
  geo_source = excluded.geo_source,
  kpis = excluded.kpis,
  updated_at = now();
`;
}

function getFinalizeSql() {
  return `create index if not exists schools_country_district_idx
  on public.schools (country_slug, district_name);

drop view if exists public.school_points_geojson;

create view public.school_points_geojson
with (security_invoker = true) as
select
  school_id,
  school_name,
  country_slug,
  country_name,
  district_name,
  province,
  latitude,
  longitude,
  geo_source,
  kpis
from public.schools;

alter table public.schools enable row level security;

drop policy if exists "Public read schools"
  on public.schools;

create policy "Public read schools"
  on public.schools
  for select
  to anon
  using (true);

grant usage on schema public to anon, authenticated;
grant select on public.schools to anon, authenticated;
grant select on public.school_points_geojson to anon, authenticated;
`;
}

function buildRows() {
  const csv = fs.readFileSync(inputFile, "utf8");
  return parseCsv(csv)
    .filter((row) => countrySlugs[row.country])
    .filter((row) => row.latitude && row.longitude)
    .map((row) => {
      const kpis = JSON.stringify(createKpis(row)).replace(/'/g, "''");
      return `(
  '${sqlQuote(row.id)}',
  '${sqlQuote(row.school_name)}',
  '${countrySlugs[row.country]}',
  '${sqlQuote(row.country)}',
  '${sqlQuote(row.district)}',
  '${sqlQuote(row.province)}',
  ${Number(row.latitude)},
  ${Number(row.longitude)},
  '${sqlQuote(row.geo_source)}',
  '${kpis}'::jsonb
)`;
    });
}

function writeChunks() {
  const rows = buildRows();
  fs.rmSync(chunksDir, { recursive: true, force: true });
  fs.mkdirSync(chunksDir, { recursive: true });
  fs.writeFileSync(path.join(chunksDir, "01_setup.sql"), getSetupSql());

  for (let index = 0; index < rows.length; index += chunkSize) {
    const chunkNumber = String(index / chunkSize + 2).padStart(2, "0");
    fs.writeFileSync(
      path.join(chunksDir, `${chunkNumber}_insert_rows.sql`),
      getInsertSql(rows.slice(index, index + chunkSize))
    );
  }

  const finalNumber = String(Math.ceil(rows.length / chunkSize) + 2).padStart(2, "0");
  fs.writeFileSync(path.join(chunksDir, `${finalNumber}_finalize.sql`), getFinalizeSql());
  console.log(`Wrote ${rows.length} school rows to ${chunksDir}`);
}

function writeImportFiles() {
  const csv = fs.readFileSync(inputFile, "utf8");
  const rows = parseCsv(csv)
    .filter((row) => countrySlugs[row.country])
    .filter((row) => row.latitude && row.longitude);

  fs.rmSync(importDir, { recursive: true, force: true });
  fs.mkdirSync(importDir, { recursive: true });

  const headers = [
    "school_id",
    "school_name",
    "country_slug",
    "country_name",
    "district_name",
    "province",
    "latitude",
    "longitude",
    "geo_source",
    "kpis",
  ];

  const csvRows = rows.map((row) => {
    const values = [
      row.id,
      row.school_name,
      countrySlugs[row.country],
      row.country,
      row.district,
      row.province,
      Number(row.latitude),
      Number(row.longitude),
      row.geo_source,
      JSON.stringify(createKpis(row)),
    ];
    return values.map(csvQuote).join(",");
  });

  fs.writeFileSync(path.join(importDir, "schools_import.csv"), `${headers.join(",")}\n${csvRows.join("\n")}\n`);
  fs.writeFileSync(path.join(importDir, "01_create_schools_table.sql"), getSetupSql());
  fs.writeFileSync(path.join(importDir, "02_finalize_school_view.sql"), getFinalizeSql());
  console.log(`Wrote CSV import files to ${importDir}`);
}

writeChunks();
writeImportFiles();
