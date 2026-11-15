# Supabase client configuration

`client-config.js` stores the project's Supabase URL and browser publishable key.
The publishable key is intended to be visible in a browser application. It does not
replace authentication, Row Level Security (RLS), or server-side authorization.

Before loading a Supabase client in the app:

1. Review and apply the database migrations in a fresh/test environment.
2. Complete and test the missing RPCs and employee bootstrap/authentication flows.
3. Verify RLS with separate Admin and Sales accounts, including direct API attempts.
4. Configure OTP providers and redirect URLs in Supabase Auth.
5. Only then initialize `supabase-js` in the app and replace local demo persistence.

Never add a `service_role` key, database password, or OTP provider secret to browser
code, source control, or a client-side environment variable.
