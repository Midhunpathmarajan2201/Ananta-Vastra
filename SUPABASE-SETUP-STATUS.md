# Supabase V1 setup status

## Prepared in this branch

- Database schema with 17 application tables, 22 database functions/RPCs, 24 RLS policies, indexes and uniqueness constraints.
- Admin-only purchase-cost and bill-cost snapshot tables.
- Sales product creation under existing Admin-defined categories, with generated category-prefixed codes.
- Atomic bill recording with stock validation/deduction and payment split checks.
- Admin corrections/cancellation, stock correction, Admin cashbook expenses/refunds.
- One-time owner Admin bootstrap and Admin-only Sales account Edge Function.
- Nine category seeds, expense-category seeds, private product-photo Storage bucket and Realtime table membership.

## Not yet done

- The SQL has not been run against the live Supabase project; no migration has been applied by this package.
- The Admin Auth user/profile has not yet been created.
- The Edge Function has not yet been deployed.
- The existing frontend still uses `localStorage`; Supabase Auth/data/RPC/Realtime integration remains outstanding.
- Live RLS tests, multi-device tests, transaction concurrency tests, backup/restore and production deployment remain outstanding.

## Safety

Run the main SQL in the existing project's SQL Editor. Stop and share the full error if any statement fails. Do not import real inventory until the frontend is integrated and the verification matrix passes.