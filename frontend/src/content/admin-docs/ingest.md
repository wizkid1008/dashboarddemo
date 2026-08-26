# Salesforce Log

This page shows the history of data loads from Salesforce into the portal — when they ran, whether they succeeded, and how far each step got.

## What "ingest" means here

Every night at 2 AM UTC, the portal automatically pulls fresh data from Salesforce (schools, contacts, academic records, grants, loans, and more) and processes it into the figures you see on the dashboards. This is a two-step process:

1. **Ingest** — fetch the raw records from Salesforce.
2. **Transform** — turn those raw records into the reporting tables the dashboards read from.

Both steps are captured in this log.

## Reading the run table

Each row is one ingest run, with a status:

- **Completed** — finished successfully; dashboards reflect this run's data.
- **In progress / Leased** — currently running, or resuming after being paused.
- **Failed** — something went wrong; data from the previous successful run is still what's shown on dashboards.

Expand a run to see its per-object breakdown (schools, contacts, districts, etc.) and how many rows were fetched for each.

## Triggering a run manually

Use the **Trigger** button if you need fresh data sooner than the next scheduled run — for example, after a Salesforce data fix that needs to show up in the portal today. Manual runs go through the same pipeline as the scheduled one, so they're safe to run at any time.

A run typically takes several minutes depending on how much data changed since the last run. You can leave the page and check back later — the run continues in the background.

## If a run fails

Check the error message on the failed run first. Most failures are transient (a Salesforce API hiccup) and resolve themselves on the next scheduled run or a manual retry. If failures persist, this needs developer attention — the underlying cause won't be visible from this page alone.
