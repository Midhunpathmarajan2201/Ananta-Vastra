# Ananta Vastra — mobile-first app prototype

**Version:** 1.0 UI demo  
**Operating model:** Physical bill pad + online sales register + inventory management  
**Demo status:** Interactive browser prototype; not yet connected to a live shared database.

## Open the demo

1. Download and extract `ananta-vastra-final.zip`.
2. Open the `ananta-vastra-app` folder.
3. Open `index.html` in Chrome or Edge on a computer. The layout is responsive; use a phone-sized browser window or open it on an Android phone for the mobile layout.
4. Use the role selector to switch between **Admin preview** and **Sales preview**. In Sales preview, choose an active sample employee.
5. Try the flows below using sample data.

The ChatGPT attachment preview may not support every HTML form control and date picker. Downloading/extracting the ZIP and opening `index.html` in a normal browser gives the intended interactive experience.

## Main demo flows

### Admin preview
- Browse category-first inventory and size/colour variants.
- Create and edit categories, products and variants.
- Set category-specific product-code prefixes.
- Set variant prices and stock thresholds.
- Review the physical bill register and correct/cancel a bill with a reason.
- Review customer groups and purchase history.
- Maintain suppliers and purchase invoices.
- Review Cashbook collections and expenses.
- View day, week, month and custom-date reports; export reports.
- Manage sample employee profiles and activity history.
- Review notifications and settings.

### Sales preview
- View active categories, products, variants and quantities.
- Add stock only to a variant already created by Admin.
- Enter each physical paper bill separately, including multiple product lines.
- Record customer name, optional phone, paper bill date and number, sold-by employee, payment split and actual amounts.
- View the employee's permitted sales information.

The demo is seeded with **illustrative sample data**. Do not mistake those bills, names, stock quantities or rupee amounts for your shop's actual records.

## Demo data and privacy

- Changes are stored in browser `localStorage` on the current device/browser only.
- The role selector is a preview control, **not authentication**.
- There is no real Admin login, Sales login, server-side permission enforcement, shared cloud database or cross-device synchronisation in this demo.
- Browser notification display is not the production phone-push service.
- Do not enter real customer information, employee credentials, supplier invoices or financial data into this prototype.
- Use **Settings → Download JSON backup** to export the current demo state. **Reset sample data** restores the initial examples.

## Online-only behaviour

The physical shop can continue to write customer bills in the paper bill pad when the internet is unavailable. The app is designed to require internet for saving digital sales/stock transactions. In this local prototype, transaction saves are blocked when the browser reports offline. This browser network check does not prove that a production database is reachable; the live app must also verify its backend connection and transaction response.

## PWA installation

The project includes `manifest.webmanifest`, `sw.js`, and 192/512px icons. To install it as a PWA, it must be hosted on an HTTPS origin (or localhost for development). Opening `index.html` as a local file is suitable for UI review but does not provide normal PWA installation. The service worker caches the app shell, but the app remains read-only for business transactions while offline.

## Reports

- PDF: use **PDF / Print** and choose “Save as PDF” in the browser print dialog.
- Excel: the demo attempts to load SheetJS when the export action is selected. If the library cannot be reached, it downloads an Excel-compatible CSV fallback. For production, bundle and test a maintained XLSX export library or generate XLSX on the server.

## Remaining brand asset

The homepage uses the Ananta Vastra brand mark in this prototype. The approved Namakkal Anjaneyar devotional photograph must be sourced and its reuse/licence confirmed before it is included in a public deployment.

## Backend foundation

`supabase/schema.sql` is a starter PostgreSQL/Supabase schema with Row Level Security policies and transactional RPC foundations for paper-bill entry, stock addition, Admin corrections/cancellation, stock adjustment and supplier invoice/payment recording.

`supabase/functions/deactivate-employee/index.ts` is an example Edge Function for Admin-only employee deactivation and global session revocation.

**The browser demo is not wired to this backend foundation.** Before real use, a Supabase project must be created, the schema reviewed and applied, missing catalogue/cashbook RPCs completed, the Edge Function deployed, authentication and realtime connected, storage policies configured for product photos, and security/backup/restore tests passed. Never put the Supabase `service_role` key in browser code.

## Project contents

- `index.html` — interactive mobile-first UI and demo logic
- `manifest.webmanifest` — PWA metadata
- `sw.js` — app-shell service worker
- `icon-192.png`, `icon-512.png` — PWA icons
- `supabase/schema.sql` — backend schema and RLS/RPC foundation
- `supabase/functions/deactivate-employee/index.ts` — example secure deactivation function
- `FINAL_SPECIFICATION.md` — consolidated approved requirements
- `PRODUCTION_CHECKLIST.md` — go-live security and deployment checklist
- `screenshots/` — mobile UI preview images
