# Ananta Vastra — development run log

Date: 2026-11-15

## Environment checks
- Supabase project URL and browser publishable key are present in `supabase/client-config.js`.
- Inline application JavaScript extracted from `index.html` and checked with Node.js v22.16.0: PASS.
- Local static HTTP smoke test: `GET /` returned HTTP 200.
- Supabase API connectivity probe could not resolve `hctqowxkhdouclbqvejh.supabase.co` from this execution environment (curl exit 6, DNS resolution failure). This is an environment/network limitation; it does not establish whether the Supabase project or key is valid.
- `psql` and `deno` are not installed in this execution environment, so PostgreSQL migrations and the Supabase Edge Function have not been executed.

## Findings requiring remediation before backend deployment
1. The current browser app still uses `localStorage`; it is not connected to Supabase Auth, Postgres, RPCs, Realtime, or Storage.
2. The starter SQL creates several RLS policies without preceding `DROP POLICY IF EXISTS`, so rerunning the schema is not reliably idempotent.
3. The schema has transaction RPCs for bills, stock additions, corrections, cancellations, supplier receiving and payments, but the production checklist still calls out missing Admin CRUD RPCs, cashbook recording, employee provisioning/password reset, storage policies, and tests.
4. OTP provider configuration, first-owner bootstrap, and server-side employee lifecycle flows remain unimplemented/unverified.
5. No Admin/Sales RLS integration tests, concurrency tests, backup/restore rehearsal, or production deployment have been run.

## Safety decision
No schema was applied to the live Supabase project and no deployment was made. The existing published prototype remains untouched. Do not enter real shop data until backend integration and role-isolation tests pass.
