# Ananta Vastra — Final Functional Specification

**Specification version:** 1.0  
**Product:** Ananta Vastra  
**Business type:** Single-location textile/clothing retail shop  
**Primary purpose:** Digitally record individual physical paper bills, maintain accurate inventory, and give the owner real-time visibility of sales and stock.  
**User experience:** Mobile-first installable PWA and browser app  
**Currency / timezone:** INR (₹), India Standard Time (Asia/Kolkata)  
**Languages:** English and Tamil

## 1. Operating model — authoritative rule

Ananta Vastra is **not a point-of-sale checkout system**. Customers are billed using the shop's existing physical paper bill pad. Sales employees enter each physical bill as an individual digital sales record in Ananta Vastra, normally during the daily sales update process.

- Each paper bill receives one separate digital record; do not replace the register with a single consolidated daily total.
- One digital record can contain multiple product lines.
- The paper bill number and original paper bill date are retained.
- The app records the separate date/time at which the employee entered the record.
- Saving a valid digital bill deducts the corresponding quantities from the exact inventory variants.
- Admin can immediately see entered sales, products/quantities sold, employee activity, collections and remaining inventory through the shared online system.
- The physical bill pad remains the customer receipt. The app does not generate the customer's statutory/tax invoice or replace the paper bill pad.
- Excel and PDF management reports remain available. WhatsApp sharing may share an approved bill record/summary, not represent it as a GST invoice.

## 2. Users, roles and access control

### 2.1 Owner/Admin

- Exactly one owner/Admin account for this single-shop deployment.
- Admin can create, activate, deactivate and reactivate Sales employee accounts and reset employee passwords.
- Admin can create/manage categories, products and variants; set all prices and low-stock thresholds; correct stock; archive/restore products; manage suppliers; access customer purchase history, Cashbook, financial valuation, profit reports, employee reports, notifications and settings.
- Admin alone can apply discounts, correct/cancel saved paper-bill records, and approve saleable returned stock.

### 2.2 Sales employees

- Each employee has an individual username/password account; no shared Sales account.
- Sales can view active inventory and selling prices, add stock only to already existing Admin-created product variants, enter individual physical paper bills, and view their own basic sales summary.
- Sales cannot create products/categories/variants, change catalogue data, change procurement prices, adjust stock corrections, archive products, view investment/margin/profit data, view customer purchase history, access Cashbook/Suppliers/Admin reports, or edit/cancel saved bills.
- Sales can change the unit selling price while recording a physical bill and can override the final bill amount; the override must be recorded in the audit trail. Sales cannot apply a discount field; discounts are Admin-only.

### 2.3 Employee deactivation

- Admin deactivation marks the employee inactive; the employee must be immediately logged out and blocked from future sign-in.
- Production implementation must revoke all active authentication sessions/tokens at the server and reject every request from an inactive profile through database RLS.
- Preserve the employee profile, historical paper bills, sold-by/entered-by attribution, stock movements and reports. Do not delete employee history.
- Admin can still view all historical sales, bills, quantities and activity for former employees.

## 3. Product categories and product codes

Initial categories:

1. 2-piece chudi
2. 3-piece chudi
3. Tops
4. Dupatta
5. Legging
6. Shawl
7. Blouse
8. Saree
9. Petticoat

- Admin can create, rename and archive categories.
- Category deletion/archive is blocked while active products remain assigned; products must first be moved or archived. Historical bill snapshots remain intact.
- Product-code prefix is configured inside each category (example defaults: `2PC-`, `3PC-`, `TOP-`, `DUP-`, `LEG-`, `SHW-`, `BLO-`, `SAR-`, `PET-`).
- Admin controls the prefix; the code is prefix + numeric suffix, such as `2PC-00105`.
- Codes must be unique (case-insensitive). Changing a category prefix affects new products only; existing product codes never change.
- No barcode feature is required in version 1.0.

## 4. Product and variant hierarchy

Inventory navigation is:

**Category / product type → product/design → size → colour → available quantity.**

- A product belongs to one Admin-defined category.
- A product/design can have multiple variants.
- Colour is optional and stored as a true empty/null value when not applicable.
- Size is optional and stored as null when not applicable.
- Supported cases include colour + size, colour only, size only, or neither.
- Admin alone creates products and every colour/size combination. Sales cannot add a missing product or variant.
- Product photos are supported; production storage must use a private/authenticated storage bucket and safe file validation.

## 5. Inventory and stock control

- Stock is tracked separately for every variant.
- Maintain separate saleable/on-hand, damaged and pending-inspection quantities.
- Admin defines a minimum stock threshold per variant.
- Low-stock alert occurs when saleable stock reaches or falls below the threshold.
- Sales can add a positive quantity to an existing variant only; Sales must enter quantity and reason. Supplier and procurement details can be completed by Admin later.
- Admin can add stock, make stock corrections with mandatory reason, manage variants, and enter purchase prices.
- Sales cannot manually correct stock differences.
- Every movement records the exact variant, quantity delta, movement type, reason, actor and timestamp. Bill deductions are automatic after the digital paper-bill record is saved successfully.
- The app blocks a digital sales entry if its requested variant quantity exceeds available saleable stock. When the physical shop has already completed a paper sale but the app stock is wrong, Admin must reconcile the stock record before entering the paper bill; the prototype does not silently permit negative stock.
- Products are archived rather than permanently deleted. Archived products are unavailable for new sales and stock additions unless restored by Admin. Historical bills and movements remain available.

## 6. Procurement prices and inventory valuation

- Procurement price and selling price are stored per variant.
- Admin maintains the current procurement price per variant.
- Preserve every previous procurement price and supplier/invoice context in historical cost records.
- Supplier invoice receipts update the current procurement price and add stock through one atomic transaction.
- Each paper-bill item stores a cost snapshot at the time of sale. Historical gross profit uses the snapshot, not the current price.
- If procurement cost is unknown, the relevant cost/investment/profit calculation is excluded or explicitly marked pending; never assume unknown cost is zero.
- Admin-only inventory summary shows total pieces, category/product/variant detail, invested current-stock value (quantity × current purchase price), and potential sales value (quantity × current selling price).
- Sales cannot see purchase prices, invested value, margins or profit.

## 7. Physical paper-bill sales register

Each paper bill is entered individually, with multiple product lines allowed.

Required/optional fields:

| Field | Rule |
|---|---|
| Physical bill number | Required and unique; case-insensitive duplicate detection |
| Original bill date | Required, editable; India date convention |
| Customer name | Required; save exact name as written on that bill |
| Customer mobile | Optional |
| Sold by | Required; Sales defaults to own employee; Admin may attribute historical sale to an employee |
| Entered by | Automatically captured from authenticated account |
| App entry timestamp | Automatically generated separately from paper bill date |
| Product category/type | Required and visible in register/detail/reports |
| Product/design | Required; selected from Admin-created catalogue |
| Colour | Optional; separate field |
| Size | Optional; separate field |
| Quantity | Positive integer required |
| Unit selling price | Editable by Sales without preset cap; changes audited |
| Final bill amount | Editable by Sales; amount override audited |
| Discount | Admin-only |
| Payment | Cash, UPI, or split Cash + UPI |

- Payment components must add up exactly to the final amount.
- Customer receipt remains the original paper bill; no in-app A4/thermal customer invoice is required.
- The register shows physical bill no., date, customer, optional contact, category/product detail, quantity, amount, payment, sold-by, entered-by and status.
- Any displayed bill-register column can be sorted ascending/descending. Search and date/status filters are available.
- Clicking a bill opens full details, underlying products and its history.

## 8. Saved bill correction and cancellation

- Sales cannot edit or cancel saved records.
- Admin alone can correct a saved record or cancel it.
- Correction requires a reason and preserves before/after values, original entries, actor, timestamp and stock movements.
- Reducing a sold quantity because of a return restores the corresponding variant quantity to the selected bucket: saleable, damaged or pending inspection.
- Increasing corrected quantity deducts additional available stock; if insufficient, correction is blocked.
- Admin records any cash/UPI/store-credit refund separately in Cashbook as an expense/adjustment; the bill correction itself does not silently create a cash refund.
- Cancelling a bill restores the recorded saleable quantities and leaves the cancelled bill and its history in the register.
- No permanent deletion of saved bills.

## 9. Customer directory

- Customer directory is grouped by normalized mobile number when supplied.
- The same phone number may be associated with several different names; retain all aliases and exact per-bill name snapshots rather than overwriting a name.
- Name + phone only are stored as customer directory fields. Address/email are out of scope.
- Customer name is mandatory on every paper-bill entry; phone is optional.
- Customer purchase history and purchase-value totals are Admin-only. Sales may see limited customer name/contact information needed to record a bill, but not purchase history.
- Bills without a phone number remain valid and are not automatically grouped across bills.

## 10. Supplier management

Admin-only full supplier module:
- Supplier name, phone, email/address/notes.
- Supplier purchase history and invoice register.
- Invoice lines linked to existing product variants, with quantities and purchase unit prices.
- Invoice total, paid amount and outstanding balance.
- Supplier payments and payment references.
- Receiving a supplier invoice adds stock, updates current variant procurement price, preserves price history and logs stock movements atomically.
- Supplier invoice/payment balances are maintained in Supplier Management, not mixed into the approved Cashbook scope.

## 11. Cashbook

Admin-only; Day, Week, Month and Custom date range filters.
- Cash and UPI bill collections flow into Cashbook from posted paper-bill records.
- Split payments are shown as separate Cash and UPI collection components.
- Admin manually records shop expenses using predefined categories plus custom Admin-created categories.
- Admin chooses the refund method and records any return refund separately as a Cashbook expense/adjustment.
- Cashbook scope is bill collections and general shop expenses. Supplier invoices and outstanding supplier payments are kept in Supplier Management.
- Display transactions and totals. Automatic expected/actual closing-cash reconciliation is not included in version 1.0.

## 12. Reports and dashboard drill-down

Period selectors: Day, Week, Month and Custom From/To dates.

Admin reports:
- Bill count, sales value, pieces sold and payment split.
- Category-wise and product-wise quantities sold.
- Category-wise size and variant stock availability.
- Low-stock variants.
- Current invested inventory value and potential sales value.
- Product-wise top sellers, ranked by pieces sold.
- Employee-wise bill/sales/quantity summary, including former employees.
- Gross profit using historical line cost snapshots, expenses and estimated net operating result. Unknown costs are excluded/flagged.
- Supplier invoices/outstanding report in Supplier Management.

Sales reports:
- Own basic sales/bill/quantity summary only. No shop-wide finance, procurement or profit information.

Exports:
- Excel `.xlsx` and PDF for filtered reports; bill-register and Cashbook exports as appropriate.
- PDF may use the browser/server PDF generation path; production export must be tested on Android and desktop.

Drill-down:
- Dashboard metrics, report values, category totals, product quantities, low-stock indicators and bill rows are interactive.
- Clicking opens the relevant filtered bill list, category/product/variant details or transaction records. Avoid decorative metrics that do nothing.

## 13. Notifications

Admin receives in-app and phone-push notifications for:
- Sales bill entered (include physical bill number, amount, customer, sold-by, entered-by and timestamp).
- Sales stock addition (employee, variant, quantity, reason and timestamp).
- Low-stock threshold reached.
- Important failed online save/synchronisation/backend operations.
- Employee deactivation and other sensitive account activity.
- Admin corrections and cancellation may appear in the activity/audit log.

Push notifications require production HTTPS/PWA configuration and a push delivery service; the local demo notification list is illustrative only.

## 14. Online-only operation and real-time data

- Internet and authenticated backend access are required for all app business writes.
- When app internet/backend is unavailable, the app is read-only and shows a clear warning. Staff continue using the physical bill pad and enter those bills after the online app is available.
- No offline bill queue, offline stock posting or eventual conflict workflow.
- Bill save, stock deduction and movement history must be one atomic database transaction.
- Stock must be locked/checked in the database during bill posting to prevent overselling across concurrent devices.
- Admin/Sales changes appear immediately on other authenticated devices using realtime subscriptions or equivalent refresh.
- The client network flag alone is not proof of backend availability; production saves must wait for database confirmation and display a failure state if the server rejects a transaction.

## 15. UI, PWA and accessibility

- Mobile-first responsive layout for Android phones, with bottom navigation and touch-friendly forms; desktop browser layout also supported.
- PWA manifest, icons and service worker; install through HTTPS.
- Premium maroon, antique-gold and cream visual identity.
- English/Tamil language switch. Production release requires a complete translation review of all page titles, labels, validation messages, report headers and notifications; partial demo translation must not be represented as full Tamil localisation.
- Date/time use Asia/Kolkata and Indian display format (DD MMM YYYY, 12-hour time).
- Daily bilingual devotional reflection on Home, refreshed for each authenticated login. Keep reflections original and do not falsely attribute them to scripture.
- Homepage devotional artwork should use a genuine, high-resolution Namakkal Anjaneyar image; verify the source and reuse/licensing permission before bundling it. Do not use an unlicensed or watermarked image. The current prototype brand mark is a placeholder, not the approved devotional photograph.
- Product photos supported with private storage and authenticated access.
- Forms must be keyboard/screen-reader accessible, labels associated with controls, required fields validated, sufficient contrast, and destructive operations confirmed.

## 16. Data and application security

Production requirements:
- Supabase Auth or equivalent identity provider; one Admin profile and individually provisioned Sales users.
- Password hashes managed only by the authentication provider. Never store plaintext passwords or expose a service-role key in the client.
- Database Row Level Security for every business table; role checks must be enforced server-side, not by hiding UI elements.
- Atomic RPCs for bill posting, stock receiving, Admin correction/cancel, and stock adjustment.
- Employee deactivation: mark inactive in DB first, revoke all sessions globally, and reject every subsequent database request through an active-profile check.
- Least-privilege access to customers, supplier details, purchase prices, Cashbook, reports, photos and activity records.
- HTTPS only; secure storage, secrets and CORS configuration; input validation and rate limits on privileged Edge Functions.
- Daily automatic backup, weekly archive, Admin business-data export, and tested restore process.
- Audit trail for all important changes. Bills and stock movements must not be silently deleted or overwritten.
- Before go-live, carry out an independent security review, RLS test matrix, account-deactivation test, concurrent stock test and backup restore drill.

## 17. Final version 1.0 exclusions

- No in-app customer checkout/POS invoice; physical bill pad remains primary.
- No GST or statutory tax invoice module.
- No offline app transaction queue.
- No barcode scanning in core version 1.0.
- No cash opening/closing reconciliation.
- No customer address/email fields.
- No permanent deletion of bills, stock movement history or employee history.

## 18. Current implementation status

The delivered bundle is a **functional UI/demo prototype** with sample data and local browser persistence. The licensed Namakkal Anjaneyar homepage photograph is also still a pending asset. It is not yet a live shared application. The included Supabase SQL and Edge Function are backend starter materials, not a deployed or fully security-audited service. Do not enter actual shop/customer/employee/financial data until the production checklist is completed and the app is connected to a real backend.
