# Ananta Vastra — production go-live checklist

The included browser demo must not be used for real shop operations until each mandatory item below is complete and tested.

## Backend and hosting
- [ ] Create a Supabase production project in an appropriate region.
- [ ] Review, apply and test `supabase/schema.sql` in a staging project first.
- [ ] Complete Admin-only RPCs for category/product/variant creation, catalogue editing/archive, cashbook expense recording, supplier management and product-photo metadata.
- [ ] Complete employee provisioning and password reset through trusted server-side Edge Functions.
- [ ] Deploy and test `supabase/functions/deactivate-employee`; confirm inactive user is denied by RLS and global session revocation works.
- [ ] Add a private product-photo storage bucket and policies: authenticated read; Admin upload/update/delete; MIME/size validation.
- [ ] Wire the browser app to Supabase Auth, Postgres, RPCs, realtime and Storage. The current `index.html` is not connected.
- [ ] Deploy the PWA to HTTPS (Vercel or equivalent); configure domain, CSP, security headers and service worker updates.

## Identity and authorisation
- [ ] Provision exactly one owner/Admin profile using a trusted process.
- [ ] Provision individual Sales users without shared credentials.
- [ ] Verify password reset; do not log or export passwords.
- [ ] Verify session timeout, logout, employee deactivation and global session revocation.
- [ ] Test Admin and Sales RLS policies with separate accounts, including direct API requests (not just UI hiding).
- [ ] Confirm Sales cannot read customer purchase history, procurement costs, Cashbook, suppliers, financial reports, or activity logs.

## Transaction correctness
- [ ] Paper bill number uniqueness is enforced case-insensitively in the database.
- [ ] Paper-bill date and app-entry timestamp are stored separately.
- [ ] Bill posting and variant stock deduction are atomic; no partial save.
- [ ] Concurrent bill attempts cannot oversell stock.
- [ ] Sale price/final amount overrides and Admin-only discounts are audited.
- [ ] Split Cash/UPI values always reconcile to final recorded amount.
- [ ] Admin correction restores stock to the correct saleable/damaged/pending bucket.
- [ ] Bill cancellation retains history and restores the correct stock.
- [ ] Employee sold-by/entered-by and former-employee history remain available.
- [ ] Sales stock additions only target existing variants; Admin-only stock corrections are audited.
- [ ] Supplier invoice receiving atomically updates stock, procurement-price history, invoice records and movements.
- [ ] Unknown procurement cost is never treated as zero in profit/value reports.

## Reporting and realtime
- [ ] Day/week/month/custom periods use Asia/Kolkata consistently.
- [ ] Dashboard drill-down opens the correct filtered records.
- [ ] Excel `.xlsx` and PDF reports are tested with larger production data sets.
- [ ] Realtime changes appear on multiple devices with role filtering.
- [ ] Backend save failures display a clear error and never falsely claim success.
- [ ] Notifications and phone push are configured, permissioned and tested.

## Privacy, recovery and operations
- [ ] Privacy notice and data-retention policy approved by the shop owner.
- [ ] Daily backups are configured; weekly archives retained.
- [ ] Admin data export excludes credentials and secret fields.
- [ ] Restore from backup is rehearsed and documented.
- [ ] Audit logs cannot be edited/deleted by Sales or ordinary Admin UI flows.
- [ ] Rate limits, HTTPS, CORS, CSP and storage validation tested.
- [ ] All demo/sample records removed before first real data import.
- [ ] Owner acceptance test completed on Android phone and desktop browser.

## Important
A completed UI is not equivalent to a production-safe multi-user app. Do not use real business data until the above security, backend, transaction, backup and restore checks have passed.
