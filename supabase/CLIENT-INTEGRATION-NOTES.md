# Supabase client configuration

`client-config.js` stores the project's Supabase URL and browser publishable key.
The publishable key is intended to be visible in a browser application. It does not
replace authentication, Row Level Security (RLS), or server-side authorization.

## Database setup

The consolidated SQL Editor script is now available at [SQL-EDITOR-SETUP.md](./SQL-EDITOR-SETUP.md),
with the canonical schema in [schema.sql](./schema.sql). Follow the setup guide and
run the script in a fresh/test Supabase project first. Create the owner in Supabase
Auth and then attach its Auth UUID to the single Admin profile using the bootstrap
insert documented at the bottom of the SQL file.

## Still required before the browser client is enabled

1. Review the SQL execution result and inspect the created tables, functions, grants,
   RLS policies and private storage bucket.
2. Complete and test the employee invitation/password reset and global session
   revocation Edge Functions.
3. Verify RLS with separate Admin and Sales accounts, including direct API attempts.
4. Configure Auth redirect URLs and any required email/OTP providers.
5. Initialize `supabase-js` in the app and replace local demo persistence with
   authenticated reads and transactional RPC calls.
6. Add Realtime subscriptions and test multi-device updates and failure states.

The current `index.html` remains a localStorage-based prototype. Publishing the SQL
does not connect the frontend or make the app production-ready.

Never add a `service_role` key, database password, or OTP provider secret to browser
code, source control, or a client-side environment variable.
