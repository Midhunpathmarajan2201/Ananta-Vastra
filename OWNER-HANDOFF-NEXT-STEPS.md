# Ananta Vastra — owner handoff and next steps

**Purpose:** prepare the existing project for a controlled backend integration and production test. This is not a production release package.

## Current verified state

- The UI source is an interactive browser prototype.
- Business data is stored in browser `localStorage`.
- Admin/Sales role selectors are preview controls, not authenticated accounts.
- `supabase/schema.sql` is a starter schema. It has not been executed against the owner's Supabase project in this workspace.
- `supabase/client-config.js` contains the project's URL and browser publishable key, but `index.html` does not load a Supabase client or use that configuration.
- Supabase Auth, database RPC integration, realtime, storage, OTP, and production notification flows are not connected.
- The Edge Function is an example foundation and has not been deployed or end-to-end tested.
- The current Cloudflare Pages deployment must remain unchanged until the replacement passes acceptance testing.

## Owner action — source handoff

1. Create a **private** GitHub repository named `ananta-vastra` (or use the existing private repository).
2. Extract the supplied project ZIP on your computer.
3. Upload the **contents** of the `ananta-vastra-app` folder to the repository root. The root should contain `index.html`, `manifest.webmanifest`, `sw.js`, `supabase/`, `FINAL_SPECIFICATION.md`, and `PRODUCTION_CHECKLIST.md`.
4. Do not upload any service-role key, database password, SMTP password, SMS provider secret, or other secret.
5. Send the repository URL in this chat. If it is private and cannot be accessed here, attach the updated ZIP in this chat instead. Do not make the repository public just to provide access.

## Supabase — do not run SQL yet

**Do not paste `supabase/schema.sql` into the production SQL Editor yet.** It is a starter schema, not a reviewed release migration. Applying it now could create an incomplete backend and make later migrations harder to manage.

Keep the existing Supabase project. Do not create a Firebase project or replace the current Supabase project. No service-role key or database password is needed in chat.

Once the source is available for the next review, the migration pack will be checked and prepared. Then the owner will be given the exact SQL file(s) and the exact Supabase Dashboard location to run them in a safe test/staging context first. We will verify results before any production migration.

## Cloudflare Pages — no deployment action yet

- Keep `anantavastra-test.pages.dev` as it is.
- Do not upload this prototype over the live project and do not change its production branch/build settings yet.
- After backend integration and QA, the release instructions will identify the exact files and environment variables to configure in Cloudflare Pages.
- Never add a Supabase service-role key to Cloudflare Pages browser-exposed variables or frontend source. Server-only secrets belong only in server-side/Edge Function secret storage.

## Safe information to share for testing

Safe to share in chat:
- Private/public GitHub repository URL (private access must be established through an available connector or by attaching the ZIP).
- Supabase project reference and project URL.
- Supabase publishable key (browser key; still apply RLS).
- Screenshots of Supabase Auth settings, database migration results, and Cloudflare Pages settings with all secrets masked.
- Non-sensitive test account usernames and synthetic test data, once the auth flow is ready.

Never share in chat or commit to GitHub:
- Supabase `service_role` / secret key.
- Database password or connection string containing a password.
- Email SMTP credentials, SMS provider API secret, Cloudflare API token, GitHub personal access token, or real customer/employee passwords/OTP codes.

## What happens after the source handoff

1. Review source against `FINAL_SPECIFICATION.md` and `PRODUCTION_CHECKLIST.md`.
2. Correct and complete the Supabase migration set, RLS policies, RPCs, auth/bootstrap and Edge Functions.
3. Add a browser Supabase client and replace local-only persistence with authenticated server calls.
4. Implement realtime, storage, Tamil/English, exports, notifications and approved remaining workflows.
5. Run static checks and functional tests; run database/RLS/concurrency tests in a test project.
6. Provide exact owner copy/paste steps for Supabase and Cloudflare.
7. Deploy only after the owner accepts the QA results; then verify the production URL.

## Release rule

Do not enter real shop transactions or customer information until authentication, RLS, atomic bill/stock updates, multi-device sync, reconciliation, export, and recovery tests have passed. A successful page load or JavaScript syntax check is not production acceptance.
