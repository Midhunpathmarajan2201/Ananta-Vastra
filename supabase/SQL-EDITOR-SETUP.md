# Supabase SQL Editor setup — Ananta Vastra

The canonical database setup is [schema.sql](./schema.sql). It includes the initial tables, role-aware RLS, transaction RPCs, Admin catalogue and financial functions, Sales account profile linking, cashbook expense entry, reporting helpers, private product-photo bucket policies, default categories and optional Realtime publication membership.

## Before you run it

- Use the existing Supabase project for Ananta Vastra; do not create a replacement project.
- Take a database backup first if the project contains data.
- Prefer a fresh/test Supabase project for the first run. The SQL is designed to be rerunnable for the included objects, but it is not a substitute for a tested migration/rollback process.
- Never paste a database password, service-role key, employee password or other secret into SQL source or GitHub.

## Run the script

1. Open the Supabase Dashboard for the Ananta Vastra project.
2. Select **SQL Editor** → **New query**.
3. Open `supabase/schema.sql` from this repository and copy its complete contents.
4. Paste the entire file into the SQL Editor and click **Run**.
5. Confirm the query completes without an error. If it fails, stop and share the exact error; do not repeatedly run partial fragments.
6. In **Table Editor**, verify that `profiles`, `categories`, `products`, `product_variants`, `paper_bills`, `paper_bill_items`, `stock_movements`, supplier, cashbook, notification and audit tables exist.

## Create the owner/Admin login

SQL does not create an Auth login or password. Create the owner identity first:

1. Go to **Authentication → Users → Add user**.
2. Enter the owner's email and a strong password; confirm the user if the dashboard offers that option.
3. Copy the Auth user's UUID.
4. In SQL Editor, replace the placeholders in the commented **FIRST-OWNER BOOTSTRAP** insert at the bottom of `schema.sql`, uncomment it, and run that INSERT exactly once.

The database enforces one Admin profile for this single-shop deployment. Do not create a second Admin profile.

## Create Sales logins

For each employee:

1. Create an individual user in **Authentication → Users** (or use a trusted server-side invitation flow when implemented).
2. Sign in to the app as Admin once the app is connected.
3. Call `admin_add_sales_profile(auth_user_uuid, full_name, username)` with that Auth user's UUID. The function attaches an existing Auth user; it does not create or store a password.

To deactivate/reactivate a Sales profile, call `admin_set_sales_active(profile_uuid, false)` or `admin_set_sales_active(profile_uuid, true)`. This blocks database access through RLS immediately. Global refresh-token revocation still requires the trusted server-side employee lifecycle Edge Function.

## Important application status

This database script does **not** connect the current browser prototype to Supabase. The current `index.html` still uses browser localStorage and does not initialize `supabase-js`. The app must still be integrated with Supabase Auth, RPCs, reads, Realtime and Storage; then tested with separate Admin and Sales accounts before real shop data is entered.

Do not use this as a production release sign-off. Complete the RLS test matrix, concurrent stock/billing tests, employee deactivation/session revocation, backups and restore rehearsal, and the remaining acceptance checklist in [PRODUCTION_CHECKLIST.md](../PRODUCTION_CHECKLIST.md).
