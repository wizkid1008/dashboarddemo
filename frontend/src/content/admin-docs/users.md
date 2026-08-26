# Users

Manage who can sign in to the portal and what level of access they have.

## Inviting a user

Use **Invite** and enter the person's email address. They'll receive an email with a link to set their own password — you don't set a password on their behalf. Until they complete that step, they'll show as pending in the user list.

Google sign-in users don't need an invite — anyone signing in with a SHF Agriculture Google account for the first time is automatically created with the standard **SHF Agriculture Staff** role.

## Setting the admin role

Toggle a user's role between standard user and **Admin** from the user list. Admins get full access to every page in this section; everyone else's access is controlled instead through **User Roles** (see that tab).

Note: an admin cannot change their own role — this is intentional, so that removing admin access always requires a second admin. If you need your own access changed, ask another admin.

## Removing a user

Removing a user revokes their portal access immediately. This doesn't affect any data they've uploaded (KPI files, etc.) — only their ability to sign in.

## Country Admins

A subset of users may be **Country Admins** rather than full Admins. They can manage users for their own country from this page but don't see the rest of the admin section (ingest, KPI upload, roles, etc.).

## Country access

Every user — not just Country Admins — can be given a list of countries from this page. That list controls which countries' data they see across the whole portal: the main Dashboard, Dynamic Data, Map, and all three KPI pages (Milestones, Trends, Report).

**A user with no countries assigned sees no data at all on those pages**, even if their role otherwise gives them access to the page itself. When you invite or edit a user, make sure to tick at least one country — Admins are the only exception, since Admins always see every country automatically.

If someone reports an empty dashboard or a blank map, this is the first thing to check.

## Assigning roles

A user can hold more than one role — assign or remove roles for them directly from this page. See the **User Roles** tab for what each role actually unlocks.

## WhatsApp users and district access

This page also manages the WhatsApp side of user access, separately from portal sign-in:

- **WhatsApp users** — invite or remove a WhatsApp user, and correct their registered phone number if it changes.
- **District access requests** — approve or reject a field user's request to see data for a specific district.
- **Approvers** — mark a user as the approver for a district, so their future access requests for that district route to them for a decision.
