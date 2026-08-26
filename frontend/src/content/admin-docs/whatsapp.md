# WhatsApp

Analytics on how people move through the WhatsApp bot's conversation flows — registration, district access requests, report delivery — showing how far they get and where they drop off or hit errors.

## What's on this page

- **Totals (last 30 days)** — total events, completions, errors, and the most-used flow.
- **Daily activity** — a 60-day chart of events vs. completions.
- **Flow summary** — per-flow breakdown: unique users, started, completed, abandoned, errors, and completion rate.
- **Step funnel** — pick a flow to see exactly which step users drop off at.
- **Recent errors** — the latest errors the bot raised, for debugging failed conversations.

## Where to find registrations and district access

Individual user registrations and district access requests aren't listed on this page — see the **Users** page for those. This page is aggregate analytics on bot usage, not a place to look up or action a specific user's request.

## Identity model

WhatsApp users are identified by their **Portal ID**, not their phone number — this means a shared or work phone can be used by more than one person without their activity getting mixed together. Phone numbers themselves are never stored in plain text in the analytics tables, only as a one-way hash, so this page can show usage patterns without exposing personal phone numbers.
