# CAMFED District Boundary Map

Map of sample CAMFED district data for Tanzania, Ghana, Malawi, Zambia, and Zimbabwe, with the rest of Africa represented only by the demo UI context.

This GitHub demo uses local dummy data bundled in `app.js`. It does not connect to Supabase, Salesforce, or any live data warehouse.

## Open the Map

Serve this folder locally, then open the local URL in a browser:

```powershell
node server.js
```

Then visit `http://localhost:8080`.

## Data Shape

Each local sample district includes:

- `country_slug`: `tanzania`, `ghana`, `malawi`, `zambia`, or `zimbabwe`
- `country_name`
- `district_name`
- `program_count`
- `beneficiary_count`
- `risk_score`
- `kpis`: JSON object keyed by KPI code
- `geometry`: GeoJSON Polygon

School markers are generated locally from those sample districts at runtime.
