# KPI Upload

KPI figures (unlike school, contact, and grant data) don't come from Salesforce automatically — they're uploaded here as spreadsheets. This page has four tabs.

## KPI Definitions

Reference list of every KPI the portal knows about — names, descriptions, and IDs. Useful for checking exact naming before you build an upload file, since the uploader matches KPI names against this list.

## Annual KPIs

Upload the `All_KPIs` sheet here. A few rules the uploader enforces:

- The workbook must contain a sheet named exactly **All_KPIs**.
- Required columns must be present and populated on every row: **Country**, **Year**, **KPI**.
- All KPI figures in the file must belong to a **single year** — mixed-year files are rejected outright (unlike the Level 1 tab, which does allow mixed years).
- If a row has a second-level disaggregation (**disagg2**), it must also have a first-level one (**disagg1**) — you can't skip a level.
- Every country in the file must already exist in the portal's geography data (populated by the nightly Salesforce ingest) — a brand-new country needs to be onboarded first, not just added via a KPI upload.

Uploading for a year **replaces** all existing Annual KPI data for that year — it's not additive. If you're correcting a mistake, re-upload the full corrected year rather than just the changed rows.

## Milestones

Cumulative/target-style KPI values, uploaded and validated the same way as Annual KPIs.

## Level 1 KPIs

Upload the `level_kpis` sheet here. Required columns must be present and populated, and — unlike Annual KPIs — mixed years in a single file are fine. Uploading here **updates existing rows that match the same year, country, school level, fund type, and gender** rather than replacing a whole year, so you can safely re-upload just the rows that changed.

## After uploading

Use the **KPI Data Coverage** tab to confirm the new figures appear where expected across years and countries before telling stakeholders the data is live.
