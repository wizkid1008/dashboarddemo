const https = require('https');
const fs = require('fs');

const INPUT  = 'C:/Users/Sisters/Downloads/dim_school.csv';
const OUTPUT = 'C:/Users/Sisters/Downloads/schools_geocoded.csv';
const PROGRESS = 'C:/Users/Sisters/Downloads/geocode_progress.json';

// Load progress checkpoint
let done = {};
if (fs.existsSync(PROGRESS)) {
  done = JSON.parse(fs.readFileSync(PROGRESS, 'utf8'));
  console.log(`Resuming — ${Object.keys(done).length} already geocoded`);
}

// Parse CSV
function parseCSV(text) {
  const lines = text.trim().split(/\r?\n/);
  const headers = lines[0].split(',');
  return lines.slice(1).map(line => {
    const vals = [];
    let cur = '', inQ = false;
    for (const ch of line) {
      if (ch === '"') inQ = !inQ;
      else if (ch === ',' && !inQ) { vals.push(cur); cur = ''; }
      else cur += ch;
    }
    vals.push(cur);
    const obj = {};
    headers.forEach((h, i) => obj[h] = vals[i] || '');
    return obj;
  });
}

function sleep(ms) { return new Promise(r => setTimeout(r, ms)); }

function nominatim(query) {
  return new Promise((resolve) => {
    const q = encodeURIComponent(query);
    const opts = {
      hostname: 'nominatim.openstreetmap.org',
      path: `/search?q=${q}&format=json&limit=1`,
      method: 'GET',
      headers: { 'User-Agent': 'CAMFED-Dashboard-Geocoder/1.0 (educational nonprofit)' }
    };
    const req = https.request(opts, res => {
      let d = '';
      res.on('data', c => d += c);
      res.on('end', () => {
        try {
          const j = JSON.parse(d);
          if (j.length) resolve({ lon: parseFloat(j[0].lon), lat: parseFloat(j[0].lat), source: 'school' });
          else resolve(null);
        } catch { resolve(null); }
      });
    });
    req.on('error', () => resolve(null));
    req.end();
  });
}

async function geocode(row) {
  const key = row.id;
  if (done[key]) return done[key];

  const school = row.school_name.trim();
  const district = row.district.trim();
  const country = row.country.trim();

  // Try 1: school + district + country
  let result = await nominatim(`${school}, ${district}, ${country}`);
  await sleep(1100);
  if (!result) {
    // Try 2: school + country only
    result = await nominatim(`${school}, ${country}`);
    await sleep(1100);
  }
  if (!result) {
    // Fallback: district + country centroid
    result = await nominatim(`${district}, ${country}`);
    if (result) result.source = 'district';
    await sleep(1100);
  }

  const out = result
    ? { lon: result.lon, lat: result.lat, source: result.source }
    : { lon: null, lat: null, source: 'not_found' };

  done[key] = out;
  return out;
}

async function run() {
  const rows = parseCSV(fs.readFileSync(INPUT, 'utf8'));
  console.log(`Total schools: ${rows.length}`);

  const results = [];
  let i = 0;
  for (const row of rows) {
    i++;
    const geo = await geocode(row);
    results.push({ ...row, longitude: geo.lon, latitude: geo.lat, geo_source: geo.source });

    if (i % 50 === 0) {
      fs.writeFileSync(PROGRESS, JSON.stringify(done), 'utf8');
      const found = Object.values(done).filter(v => v.lon !== null).length;
      console.log(`${i}/${rows.length} — ${found} found so far`);
    }
  }

  // Save progress + final CSV
  fs.writeFileSync(PROGRESS, JSON.stringify(done), 'utf8');

  const headers = ['id','school_name','district','province','country','longitude','latitude','geo_source'];
  const csv = [
    headers.join(','),
    ...results.map(r => headers.map(h => {
      const v = r[h] == null ? '' : String(r[h]);
      return v.includes(',') || v.includes('"') ? `"${v.replace(/"/g,'""')}"` : v;
    }).join(','))
  ].join('\r\n');
  fs.writeFileSync(OUTPUT, csv, 'utf8');

  // GeoJSON
  const features = results
    .filter(r => r.longitude && r.latitude)
    .map(r => ({
      type: 'Feature',
      geometry: { type: 'Point', coordinates: [r.longitude, r.latitude] },
      properties: { id: r.id, name: r.school_name, district: r.district, province: r.province, country: r.country, geo_source: r.geo_source }
    }));
  const geojson = { type: 'FeatureCollection', features };
  fs.writeFileSync('C:/Users/Sisters/Downloads/schools.geojson', JSON.stringify(geojson), 'utf8');

  const found = results.filter(r => r.longitude).length;
  console.log(`\nDone! ${found}/${rows.length} geocoded`);
  console.log(`CSV: ${OUTPUT}`);
  console.log(`GeoJSON: C:/Users/Sisters/Downloads/schools.geojson`);
}

run().catch(console.error);
