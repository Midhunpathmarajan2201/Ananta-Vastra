# Ananta Vastra — owner handoff and next steps

**Purpose:** prepare the existing project for a controlled Supabase backend integration and production test. This is not a production release package.

## Current verified state

- The UI source is an interactive browser prototype.
- Business data is stored in browser `localStorage`.
- Admin/Sales role selectors are preview controls, not authenticated accounts.
- `supabase/schema.sql` now contains the consolidated SQL Editor setup: database tables, RLS, transactional bill/stock RPCs, Admin catalogue and financial operations, Sales profile linking, cashbook expenses, reporting helpers, private product-photo bucket policies, default categories and optional Realtime publication membership.
- `supabase/SQL-EDITOR-SETUP.md` explains how to run the script and create the owner/Admin and Sales identities.
- `supabase/client-config.js` contains the project URL and browser publishable key, but `index.html` does not load a Supabase client or use that configuration.
- Supabase Auth, database RPC integration, realtime, storage, employee provisioning and production notification flows are not connected end-to-end.
- The current Cloudflare Pages deployment must remain unchanged until the replacement passes acceptance testing.

## Supabase setup

The owner may now use the documented SQL Editor procedure in `supabase/SQL-EDITOR-SETUP.md`. Start in a fresh/test project or take a verified backup first. Do not treat successful SQL execution as production approval.

Create the owner through Supabase **Authentication → Users**, then add its Auth UUID to `public.profiles` using the single-owner bootstrap insert documented in `schema.sql`. Create each Sales identity in Auth and link it through the Admin-only `admin_add_sales_profile` RPC. Passwords are managed only by Supabase Auth.

Never put the service-role key, database password, employee password, SMTP credentials, SMS provider secret, Cloudflare API token or GitHub token in chat, browser code or source control.

## Cloudflare Pages — no deployment action yet

- Keep `anantavastra-test.pages.dev` as it is.
- Do not upload this prototype over the live project and do not change its production branch/build settings yet.
- After backend integration and QA, configure only the public Supabase URL and publishable key in the browser client.
- Server-only secrets belong only in trusted Edge Function secret storage.

## Remaining work

1. Run the SQL in a fresh/test Supabase project and review all execution results.
2. Test Admin/Sales RLS isolation, cost-field privacy, bill posting/correction/cancellation, stock locking and duplicate bill prevention.
3. Complete employee invitations/password reset and global refresh-token revocation in trusted Edge Functions.
4. Integrate the browser app with Supabase Auth, reads, RPCs, Realtime and private Storage; replace localStorage business persistence.
5. Finish cashbook/reporting/export and notification workflows; verify dashboard drill-down behavior.
6. Run backup/restore, Android/desktop acceptance and production security review.
7. Deploy only after the owner accepts QA results; then verify the production URL.

## Release rule

Do not enter real shop transactions or customer information until authentication, RLS, atomic bill/stock updates, multi-device sync, reconciliation, export, and recovery tests have passed. A successful page load or SQL execution is not production acceptance.
