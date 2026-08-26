/**
 * gadm_geocode.js
 * Two-pass geocoder:
 *   1st pass – Photon (free, no API key, better Africa coverage than Nominatim)
 *   2nd pass – District centroid from GADM (fallback for unresolved schools)
 * Progress is saved every 100 schools so the script can be resumed.
 */

const https   = require('https');
const http    = require('http');
const fs      = require('fs');
const urlLib  = require('url');

const INPUT    = 'C:/Users/Sisters/Downloads/dim_school.csv';
const OUT_GJ   = 'C:/Users/Sisters/Downloads/schools.geojson';
const OUT_CSV  = 'C:/Users/Sisters/Downloads/schools_geocoded.csv';
const PROGRESS = 'C:/Users/Sisters/Downloads/geocode_progress2.json';

const COUNTRIES = { Ghana: 'GHA', Tanzania: 'TZA', Zambia: 'ZMB', Zimbabwe: 'ZWE', Malawi: 'MWI', Ethiopia: 'ETH', Kenya: 'KEN' };

// ── helpers ──────────────────────────────────────────────────────────────────

function parseCSV(text) {
  const lines = text.trim().split(/\r?\n/);
  const headers = lines[0].split(',');
  return lines.slice(1).map(line => {
    const vals = [];
    let cur = '', inQ = false;
    for (const ch of line) {
      if (ch === '"') { inQ = !inQ; }
      else if (ch === ',' && !inQ) { vals.push(cur); cur = ''; }
      else cur += ch;
    }
    vals.push(cur);
    const obj = {};
    headers.forEach((h, i) => obj[h.trim()] = (vals[i] || '').trim());
    return obj;
  });
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function fetchText(rawUrl) {
  return new Promise((resolve, reject) => {
    const parsed = urlLib.parse(rawUrl);
    const lib = parsed.protocol === 'https:' ? https : http;
    lib.get({ ...parsed, headers: { 'User-Agent': 'CAMFED-Dashboard-Geocoder/1.0 (nonprofit school data)' } }, res => {
      if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
        return fetchText(res.headers.location).then(resolve).catch(reject);
      }
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => resolve(d));
    }).on('error', reject);
  });
}

function norm(s) {
  return (s || '').toLowerCase()
    .replace(/\b(district|county|region|province|council|municipality|ward|division)\b/g, '')
    .replace(/[^a-z0-9]+/g, ' ')
    .trim();
}

// ── GADM district centroids ───────────────────────────────────────────────────

function geoCentroid(geom) {
  let coords = [];
  if (geom.type === 'Polygon') {
    coords = geom.coordinates[0];
  } else if (geom.type === 'MultiPolygon') {
    let best = [];
    for (const poly of geom.coordinates) {
      if (poly[0].length > best.length) best = poly[0];
    }
    coords = best;
  }
  if (!coords.length) return null;
  const lon = coords.reduce((s, c) => s + c[0], 0) / coords.length;
  const lat = coords.reduce((s, c) => s + c[1], 0) / coords.length;
  return { lon, lat };
}

async function loadDistrictCentroids(country, iso3) {
  console.log(`\n[${country}] Loading district centroids…`);
  try {
    const meta = JSON.parse(await fetchText(`https://www.geoboundaries.org/api/current/gbOpen/${iso3}/ADM2/`));
    const gj   = JSON.parse(await fetchText(meta.gjDownloadURL));
    const map  = {};
    for (const feat of (gj.features || [])) {
      const name = feat.properties.shapeName || feat.properties.NAME_2 || '';
      const c = geoCentroid(feat.geometry);
      if (c && name) map[norm(name)] = { lon: c.lon, lat: c.lat, original: name };
    }
    console.log(`  ✓ ${Object.keys(map).length} districts`);
    return map;
  } catch (e) {
    console.log(`  ✗ Failed: ${e.message}`);
    return {};
  }
}

function findCentroid(districtName, centroids) {
  const key = norm(districtName);
  if (centroids[key]) return centroids[key];
  for (const [k, v] of Object.entries(centroids)) {
    if (k.startsWith(key) || key.startsWith(k)) return v;
  }
  for (const [k, v] of Object.entries(centroids)) {
    const words = key.split(' ').filter(w => w.length > 3);
    if (words.length && words.some(w => k.includes(w))) return v;
  }
  return null;
}

// ── Photon geocoder ───────────────────────────────────────────────────────────

async function photon(query) {
  try {
    const q    = encodeURIComponent(query);
    const text = await fetchText(`https://photon.komoot.io/api/?q=${q}&limit=1`);
    const gj   = JSON.parse(text);
    const feat = gj.features && gj.features[0];
    if (!feat) return null;
    const [lon, lat] = feat.geometry.coordinates;
    return { lon, lat };
  } catch { return null; }
}

async function geocodeSchool(row) {
  const name    = row.school_name.trim();
  const district= row.district.trim();
  const country = row.country.trim();

  // Try: full name + district + country
  let r = await photon(`${name}, ${district}, ${country}`);
  await sleep(200); // Photon allows ~5 req/sec
  if (r) return { ...r, source: 'photon_school' };

  // Try: school + country
  r = await photon(`${name}, ${country}`);
  await sleep(200);
  if (r) return { ...r, source: 'photon_school_country' };

  return null;
}

// ── main ─────────────────────────────────────────────────────────────────────

async function run() {
  const schools = parseCSV(fs.readFileSync(INPUT, 'utf8'));
  console.log(`Loaded ${schools.length} schools`);

  // Resume from checkpoint
  let progress = {};
  if (fs.existsSync(PROGRESS)) {
    progress = JSON.parse(fs.readFileSync(PROGRESS, 'utf8'));
    console.log(`Resuming: ${Object.keys(progress).length} already done`);
  }

  // Load district centroids for all countries upfront
  const districtMaps = {};
  for (const [country, iso3] of Object.entries(COUNTRIES)) {
    districtMaps[country] = await loadDistrictCentroids(country, iso3);
  }
  console.log('\n── Pass 1: Photon geocoding ────────────────────────────────');

  let i = 0;
  for (const row of schools) {
    i++;
    const key = row.id;
    if (progress[key]) continue;  // already done

    const geo = await geocodeSchool(row);
    if (geo) {
      progress[key] = geo;
    } else {
      // Immediate fallback to district centroid
      const c = findCentroid(row.district, districtMaps[row.country] || {});
      progress[key] = c
        ? { lon: c.lon, lat: c.lat, source: 'district_centroid' }
        : { lon: null, lat: null, source: 'not_found' };
    }

    if (i % 100 === 0) {
      fs.writeFileSync(PROGRESS, JSON.stringify(progress), 'utf8');
      const photonHits   = Object.values(progress).filter(v => v.source && v.source.startsWith('photon')).length;
      const districtHits = Object.values(progress).filter(v => v.source === 'district_centroid').length;
      const missing      = Object.values(progress).filter(v => v.source === 'not_found').length;
      console.log(`${i}/${schools.length} — photon: ${photonHits} | district: ${districtHits} | missing: ${missing}`);
    }
  }

  fs.writeFileSync(PROGRESS, JSON.stringify(progress), 'utf8');

  // ── Assemble results ──
  const results = schools.map(row => ({
    ...row,
    longitude: progress[row.id]?.lon ?? null,
    latitude:  progress[row.id]?.lat ?? null,
    geo_source: progress[row.id]?.source ?? 'not_found'
  }));

  // ── Write CSV ──
  const csvH = ['id','school_name','district','province','country','longitude','latitude','geo_source'];
  const csvLines = results.map(r =>
    csvH.map(h => {
      const v = r[h] == null ? '' : String(r[h]);
      return v.includes(',') || v.includes('"') ? `"${v.replace(/"/g,'""')}"` : v;
    }).join(',')
  );
  fs.writeFileSync(OUT_CSV, [csvH.join(','), ...csvLines].join('\r\n'), 'utf8');

  // ── Write GeoJSON ──
  const features = results
    .filter(r => r.longitude != null)
    .map(r => ({
      type: 'Feature',
      geometry: { type: 'Point', coordinates: [+r.longitude, +r.latitude] },
      properties: {
        id: r.id, name: r.school_name,
        district: r.district, province: r.province, country: r.country,
        geo_source: r.geo_source
      }
    }));
  fs.writeFileSync(OUT_GJ, JSON.stringify({ type: 'FeatureCollection', features }, null, 2), 'utf8');

  const photonHits   = results.filter(r => r.geo_source && r.geo_source.startsWith('photon')).length;
  const districtHits = results.filter(r => r.geo_source === 'district_centroid').length;
  const missing      = results.filter(r => r.geo_source === 'not_found').length;
  console.log(`\n── Done ────────────────────────────────────────────────────`);
  console.log(`Photon (exact):    ${photonHits} schools`);
  console.log(`District centroid: ${districtHits} schools`);
  console.log(`Not found:         ${missing} schools`);
  console.log(`Total geocoded:    ${photonHits + districtHits}/${results.length} (${Math.round(100*(photonHits+districtHits)/results.length)}%)`);
  console.log(`CSV:     ${OUT_CSV}`);
  console.log(`GeoJSON: ${OUT_GJ}`);
}

run().catch(console.error);
