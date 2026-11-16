# Ananta Vastra — mobile-first shop management app

**Current application status:** interactive UI prototype; Supabase backend setup is provided but the browser UI is not yet connected to it.

## Review the app

1. Open `index.html` in Chrome or Edge, or host it on HTTPS for PWA installation.
2. The current Admin/Sales role selector is preview-only.
3. Sample inventory, bills and employee records are stored in browser `localStorage`; they are not shared between devices.

Do not enter real customer, employee, inventory or financial data in the current prototype.

## Existing Supabase backend setup

The repository now contains the initial V1 database and authentication setup for project `hctqowxkhdouclbqvejh`:

- `supabase/schema.sql` — tables, indexes, RLS, functions/RPCs, nine agreed categories, expense categories, private product-photo bucket and Realtime publication membership.
- `supabase/ADMIN-BOOTSTRAP-AFTER-AUTH-USER.sql` — one-time Admin profile creation after the owner Auth user is created in the Dashboard.
- `supabase/VERIFY-AFTER-SETUP.sql` — post-install checks.
- `supabase/functions/manage-sales-employee/` — Admin-only Sales account creation, profile updates, password reset, deactivation and reactivation.
- `SUPABASE-SETUP-GUIDE.md` — step-by-step instructions for the existing Supabase project.

Read `SUPABASE-SETUP-GUIDE.md` before running the SQL. The SQL does not create an Auth password: create the owner user in Supabase Authentication → Users, then run the Admin bootstrap script. Public sign-ups must be disabled.

## Important release boundary

The SQL and Edge Function establish the backend layer; they do not wire the existing `index.html` to Supabase. Real shop use remains blocked until frontend authentication, database reads/RPC writes, realtime subscriptions, online-only enforcement and Admin/Sales permission tests are completed. Keep the currently deployed review site unchanged until those checks pass.

Email and SMS password recovery are intentionally deferred from this initial setup. Supplier Management is excluded from this V1 release.

## Security rules

- Exactly one owner Admin profile.
- No public self-registration.
- Admin creates and manages Sales accounts.
- Sales cannot read purchase costs, customer purchase history, Cashbook, refunds or Admin activity logs.
- Direct table writes are revoked; business writes use audited server-side RPCs.
- Never commit a Supabase secret/service-role key or database password.