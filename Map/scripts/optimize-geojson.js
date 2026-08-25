const fs = require("fs");
const path = require("path");
const readline = require("readline");

const root = path.resolve(__dirname, "..");
const outputDir = path.join(root, "optimized");

const AFRICA_ISO3_CODES = new Set([
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
]);

const PRIORITY_ISO3_CODES = new Set(["TZA", "GHA", "MWI", "ZMB", "ZWE"]);

const jobs = [
  {
    input: "geoBoundariesCGAZ_ADM0.geojson",
    output: "africa_adm0_simplified.geojson",
    keep: AFRICA_ISO3_CODES,
    tolerance: 0.035,
  },
  {
    input: "geoBoundariesCGAZ_ADM1.geojson",
    output: "priority_adm1_simplified.geojson",
    keep: PRIORITY_ISO3_CODES,
    tolerance: 0.025,
  },
  {
    input: "geoBoundariesCGAZ_ADM2.geojson",
    output: "priority_adm2_simplified.geojson",
    keep: PRIORITY_ISO3_CODES,
    tolerance: 0.018,
  },
];

fs.mkdirSync(outputDir, { recursive: true });

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});

async function main() {
  for (const job of jobs) {
    await optimize(job);
  }
}

async function optimize(job) {
  const inputPath = path.join(root, job.input);
  const outputPath = path.join(outputDir, job.output);
  const input = fs.createReadStream(inputPath, { encoding: "utf8" });
  const output = fs.createWriteStream(outputPath, { encoding: "utf8" });
  const rl = readline.createInterface({ input, crlfDelay: Infinity });
  let count = 0;
  let first = true;

  output.write('{"type":"FeatureCollection","features":[\n');

  for await (const line of rl) {
    const trimmed = line.trim();
    if (!trimmed.startsWith('{ "type": "Feature"')) continue;

    const feature = JSON.parse(trimmed.replace(/,$/, ""));
    if (!job.keep.has(feature.properties.shapeGroup)) continue;

    const optimized = {
      type: "Feature",
      properties: {
        shapeName: feature.properties.shapeName,
        shapeID: feature.properties.shapeID,
        shapeGroup: feature.properties.shapeGroup,
        shapeType: feature.properties.shapeType,
      },
      geometry: simplifyGeometry(feature.geometry, job.tolerance),
    };

    if (!first) output.write(",\n");
    output.write(JSON.stringify(optimized));
    first = false;
    count += 1;
  }

  output.write("\n]}\n");
  await new Promise((resolve) => output.end(resolve));

  const sizeMb = fs.statSync(outputPath).size / 1024 / 1024;
  console.log(`${job.output}: ${count} features, ${sizeMb.toFixed(2)} MB`);
}

function simplifyGeometry(geometry, tolerance) {
  if (!geometry) return geometry;

  if (geometry.type === "Polygon") {
    return {
      type: "Polygon",
      coordinates: geometry.coordinates.map((ring) => simplifyRing(ring, tolerance)),
    };
  }

  if (geometry.type === "MultiPolygon") {
    return {
      type: "MultiPolygon",
      coordinates: geometry.coordinates.map((polygon) =>
        polygon.map((ring) => simplifyRing(ring, tolerance))
      ),
    };
  }

  return geometry;
}

function simplifyRing(ring, tolerance) {
  if (!Array.isArray(ring) || ring.length <= 4) return roundRing(ring || []);

  const closed = pointsEqual(ring[0], ring[ring.length - 1]);
  const body = closed ? ring.slice(0, -1) : ring.slice();
  const simplified = douglasPeucker(body, tolerance);
  const rounded = roundRing(simplified.length >= 3 ? simplified : body);

  if (!pointsEqual(rounded[0], rounded[rounded.length - 1])) {
    rounded.push([...rounded[0]]);
  }

  return rounded;
}

function roundRing(ring) {
  return ring.map(([lon, lat]) => [roundCoord(lon), roundCoord(lat)]);
}

function roundCoord(value) {
  return Number(value.toFixed(5));
}

function pointsEqual(a, b) {
  return a && b && a[0] === b[0] && a[1] === b[1];
}

function douglasPeucker(points, tolerance) {
  if (points.length <= 2) return points;

  let maxDistance = 0;
  let index = 0;
  const first = points[0];
  const last = points[points.length - 1];

  for (let i = 1; i < points.length - 1; i += 1) {
    const distance = perpendicularDistance(points[i], first, last);
    if (distance > maxDistance) {
      index = i;
      maxDistance = distance;
    }
  }

  if (maxDistance <= tolerance) {
    return [first, last];
  }

  const left = douglasPeucker(points.slice(0, index + 1), tolerance);
  const right = douglasPeucker(points.slice(index), tolerance);
  return left.slice(0, -1).concat(right);
}

function perpendicularDistance(point, lineStart, lineEnd) {
  const [x, y] = point;
  const [x1, y1] = lineStart;
  const [x2, y2] = lineEnd;
  const dx = x2 - x1;
  const dy = y2 - y1;

  if (dx === 0 && dy === 0) {
    return Math.hypot(x - x1, y - y1);
  }

  return Math.abs(dy * x - dx * y + x2 * y1 - y2 * x1) / Math.hypot(dx, dy);
}
