# Ananta Vastra UI Demo — QA results

**Test date:** 15 November 2026  
**Browser engine:** Chromium (automated local browser session)  
**Viewport checks:** 390 × 844 mobile; 1440 × 960 desktop

## Passed in the interactive UI prototype

- Initial dashboard renders in mobile and desktop layouts.
- All nine initial categories render in category-first inventory.
- Product hierarchy is category → product/design → separate optional colour and size → variant stock.
- A bill line's separate colour and size selectors resolve to the correct Admin-created variant.
- Sales can add stock to an existing variant in the demo.
- Sales can enter an individual physical paper bill with multiple product lines, customer, paper date/number, sold-by/entered-by, Cash/UPI/split payment and editable amount.
- Saving a paper bill deducts stock from the exact selected variant.
- Sales preview does not show saved-bill correction controls.
- Admin preview can correct a bill and return quantity to inventory with a reason.
- Bill register shows Category and supports sort selection by category/sold-by.
- Reports, Cashbook, Suppliers and Employee screens render.
- Digital save is blocked when browser connectivity is set to offline.
- English/Tamil switch updates navigation and page-title labels; broader Tamil localisation remains a release task.
- No browser JavaScript page errors were observed during the automated test flow.

## Not verified / not live

- Supabase SQL has not been applied to a live PostgreSQL/Supabase project or tested with real authenticated users.
- RLS, password handling, server-side role enforcement, employee session revocation, realtime subscriptions, phone push, cloud photo storage, scheduled backups and restore have not been deployed.
- The frontend is still local browser demo state, not a shared multi-user database.
- Real-device PWA installation and Android printer integration are not part of this test.

This test validates the prototype interaction paths only. It is not a security audit or production-readiness certification.
