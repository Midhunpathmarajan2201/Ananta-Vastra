# Supabase client configuration

`client-config.js` contains the existing project's URL and public publishable key. The key is intended for browser use, but it does not replace authentication or Row Level Security.

## Database and Admin setup

1. Follow the root `SUPABASE-SETUP-GUIDE.md`.
2. Run `supabase/schema.sql` in the existing project's SQL Editor.
3. Create the one owner Auth user in Authentication → Users. Public sign-ups must be disabled.
4. Run `supabase/ADMIN-BOOTSTRAP-AFTER-AUTH-USER.sql` to create the sole Admin profile.
5. Run `supabase/VERIFY-AFTER-SETUP.sql` and confirm tables, the nine categories, one Admin profile, RLS and the private product-photo bucket.

## Sales account management

Deploy `supabase/functions/manage-sales-employee` using the CLI instructions in the setup guide. The function checks the caller's active Admin profile before creating, editing, resetting, deactivating or reactivating Sales accounts. Sales login uses the username-to-internal-email convention in the setup guide.

## Frontend integration still required

The current `index.html` still uses browser `localStorage` and Admin/Sales preview selectors. Applying the SQL and deploying the function does **not** automatically connect the current UI. Before real inventory is entered, the frontend must be changed to:

- initialize `supabase-js` using `client-config.js`;
- replace localStorage business-data reads/writes with authenticated queries and transactional RPCs;
- use Supabase Auth for Admin email/password and Sales username/password;
- call `manage-sales-employee` for employee administration;
- subscribe to the configured Realtime tables;
- block writes whenever the backend is unavailable or the browser is offline.

Do not enter real shop data until this frontend integration and the Admin/Sales RLS test matrix have passed.

Never put a Supabase secret/service-role key, database password, or OTP provider credential in browser code or GitHub.