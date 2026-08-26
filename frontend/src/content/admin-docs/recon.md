# Salesforce Recon

Shows how many rows are currently in the portal's warehouse, broken down by source object (schools, contacts, grants, and so on), country, and year.

## What it's for

- Sanity-check that an ingest run actually populated data across all the countries and years you'd expect, not just some.
- Spot an object that's unexpectedly empty or unusually small for a given year.
- Export a CSV snapshot for a point-in-time record.

## Reading the table

- The summary at the top totals each source object across all countries and years.
- The detail table below can be filtered by object, country, and year — a **"—"** means that row's geography or date couldn't be resolved during processing.
- Expand **How values are calculated** for a plain-language note on exactly what each table counts — for example, children supported counts active School-type academic records, while guide assignment counts active guide roles.

## What this page doesn't do

This is a warehouse-only view — it doesn't compare against live Salesforce record counts. If you need to confirm the warehouse total matches what's actually in Salesforce right now, that's a separate check a developer runs outside the portal. If the numbers here look off, start with the **Salesforce Log** tab to check whether the most recent ingest run actually completed successfully.
