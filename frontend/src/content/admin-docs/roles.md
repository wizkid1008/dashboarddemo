# User Roles

Roles control which dashboards, charts, and WhatsApp report types a non-admin user can see. Admins always see everything and aren't affected by role permissions.

## How permissions work

A role is a named bundle of permissions — things like "can see the Education Reach dashlet" or "can see the Bursaries card on Dynamic Data." When you assign a role to a user, they get access to everything that role's permissions unlock, and nothing else.

Permissions are grouped by where they show up in the portal:

- **Dashboard cards** — the main dashboard's summary cards.
- **Dynamic Data + Map** — the metric cards on the Dynamic Data page and the KPI dropdown on the interactive map.
- **WhatsApp reports** — which report types a WhatsApp bot user can request.

## Creating and editing a role

Give the role a clear name (e.g. "Zambia Country Team"), then check the permissions it should include. You can edit a role's permissions at any time — changes take effect for every user holding that role as soon as they next load the portal.

## Assigning a role to a user

Roles are assigned from this page or from the Users page — a user can hold more than one role, in which case they get the union of all permissions across their roles.

## Deleting a role

A role can't be deleted while any user still holds it — reassign or remove it from those users first. This prevents users from silently losing access to everything if a role is deleted by mistake.

## If something isn't showing up

If a user reports a dashlet or metric is invisible to them despite having a role that should include it, this is usually a configuration gap on the backend (the permission isn't wired to that specific metric) rather than something fixable from this page — flag it to a developer with the exact metric name.
