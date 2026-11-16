# Ananta Vastra — Supabase setup guide

This package is for the existing Supabase project `hctqowxkhdouclbqvejh` and the existing GitHub repository. It does not replace the current Cloudflare Pages deployment.

## 1. Run the database script

1. Open Supabase Dashboard → SQL Editor → New query.
2. Open `ANANTA-VASTRA-SUPABASE-SETUP.sql` from this package.
3. Copy the entire file into the query editor.
4. Click **Run** once and wait for `Success. No rows returned` (or the success state).
5. If the editor reports an error, stop and share the full error text. Do not keep running partial selections.

The script creates the app tables, row-level security, database RPCs, the nine product categories, expense categories, the private product-photo bucket, and Realtime publication membership. It is designed to be re-runnable for the objects it creates, but it is intended for this project before any real shop data is imported.

## 2. Create the single Owner Admin Auth user

The SQL Editor cannot safely create an Auth password. Create the user through Supabase's supported Auth UI:

1. Dashboard → Authentication → Users → **Add user** → choose **Create new user** (not Send invitation).
2. Email: `yogisharajan@gmail.com`.
3. Set the initial password privately in the Dashboard (do not put it in SQL, GitHub, or browser source).
4. Confirm the email address in the create-user dialog, if that option is shown.
5. Under Authentication → Sign In / Providers or General configuration, disable **Allow new users to sign up**. Project owners can still create users administratively from the Dashboard.

Then open `supabase/ADMIN-BOOTSTRAP-AFTER-AUTH-USER.sql`, copy it into SQL Editor and run it. It creates the sole Admin profile only when this is the only Auth user and no profile has yet been created. It sets the Admin profile username to `admin`; change that literal only if you intentionally want another Admin username.

The bootstrap SQL does not contain or reset the password. Sign in as the Admin with the owner email and the password entered in the Auth UI. Because the initial password was previously shared in chat, rotate it to a new private password after your first successful login.

## 3. Sales login convention and employee administration

Sales Auth users are created by the `manage-sales-employee` Edge Function. The function checks the caller's active `profiles.role='admin'` before it can create, edit, reset, deactivate, or reactivate a Sales account.

Sales username `staffname` maps to the internal Auth email `staffname@sales.anantavastra.in`. The app login screen must derive that internal email from the entered username before calling `supabase.auth.signInWithPassword({ email, password })`. Employees use their username and password; the synthetic email is internal and is not an email inbox.

Supported Edge Function actions:

- `create`: requires `username`, `fullName`, `password`.
- `update-profile`: requires `username`, `fullName`.
- `reset-password`: requires `username`, `password`.
- `deactivate`: requires `username`; profile RLS access is disabled immediately and Auth sign-in is banned.
- `reactivate`: requires `username`, `password`; Admin sets a new password when reactivating.

The function never manages or resets the Admin account. On deactivation, the profile is marked inactive, the JWT issue-time floor is advanced, and Supabase Auth bans new sign-ins. Existing JWTs may remain cryptographically valid until expiry, but all application RLS/RPC checks reject them immediately. Reactivation requires the Admin to set a new password.

## 4. Deploy the Edge Function

Using Supabase CLI from the repository root:

```bash
supabase login
supabase link --project-ref hctqowxkhdouclbqvejh
supabase functions deploy manage-sales-employee
```

Supabase injects the project URL and legacy Auth API keys into hosted Edge Functions as environment variables. The function reads those injected values. Do not try to create custom secrets whose names begin with `SUPABASE_`; that prefix is reserved by Supabase. Never commit a service-role/secret key or paste it into this chat. Keep any manually created provider credentials in the Supabase Edge Function Secrets page only. See the [Supabase secrets guide](https://supabase.com/docs/guides/functions/secrets) and [function deployment guide](https://supabase.com/docs/guides/functions/deploy).

The allowed CORS origins include the existing Cloudflare Pages domain and its preview subdomains. Add any final custom production domain to `isAllowedOrigin()` before deployment.

## 5. Verify the database

Run these checks in SQL Editor after setup and Admin bootstrap:

```sql
select table_name
from information_schema.tables
where table_schema='public' and table_type='BASE TABLE'
order by table_name;

select name, code_prefix from public.categories order by name;

select p.id, p.full_name, p.username, p.role, p.is_active, u.email
from public.profiles p join auth.users u on u.id=p.id
where p.role='admin';

select id, name, public, file_size_limit
from storage.buckets where id='ananta-product-photos';
```

Expected: the nine category rows, one Admin profile, and a private `ananta-product-photos` bucket.

## 6. Important: frontend integration is a separate step

The current `index.html` in the repository still has browser-local demo persistence and preview role switching. Applying this SQL does **not** automatically connect the existing screens to Supabase. Before entering actual shop inventory, the frontend must be updated to:

- load Supabase JS and the existing `supabase/client-config.js`;
- replace localStorage business persistence with Supabase reads and RPC writes;
- add Admin email/password and Sales username/password login;
- call `manage-sales-employee` for employee management;
- subscribe to the Realtime tables;
- show a blocking offline/backend-unavailable state for all writes.

Do not enter real customer, employee or stock data into the current preview app until that frontend integration is complete and tested. This package establishes the database/security layer, not a completed live application.

## 7. Initial release boundaries

- Email/SMS recovery is intentionally not enabled in this initial release; it can be added later.
- No public self-registration.
- One owner Admin only; Sales accounts are created only by Admin.
- Sales cannot read purchase costs, customer purchase history, cashbook, refunds, Admin reports or activity logs.
- No Supplier Management in this release.
- Supabase Free does not include managed database backups. Export/restore must be arranged and tested before relying on the shop database.