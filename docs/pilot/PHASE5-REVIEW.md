# Phase 5 review: controlled staging remediation and operational readiness

Status: read-only investigation complete for production; staging unchanged; nothing applied to any Supabase project. Owner decisions 1 and 2 remain open.

## 1. Urgent finding: WhatsApp "Confirm Receipt" moves ledger money while payments are off

Production `whatsapp-webhook` accepts a buyer's "Confirm Receipt" tap and calls `confirm_order_delivery_by_phone`. That function:

1. Checks the sender number matches the buyer (sound).
2. Sets the buyer's identity in the transaction and calls `confirm_delivery(order_id, key)`.
3. `confirm_delivery` requires `status = 'delivered'` and `escrow_status = 'holding'`, then calls `_apply_order_payout`, which credits seller, driver and marshal wallets (route branch 90/10, or legacy 80/10/5/5 for non-route orders), then sets the order to `completed`.

Nothing in this path reads `app_config.payments_live`. The webhook reply tells the buyer "The seller and driver have been credited", which is a money claim.

Current production state (read-only query):

| status    | escrow   | test | route | orders | total |
| --------- | -------- | ---- | ----- | ------ | ----- |
| completed | released | yes  | no    | 7      | 1,130 |
| delivered | holding  | yes  | no    | 1      | 50    |

`payments_live` = `false`. Every production order is a test order on the legacy path. One order (total 50) is `delivered` and `holding`, so its buyer can confirm it through WhatsApp now and release a legacy split into wallets with no payment behind it.

Risk: low financial exposure today (test data, no card money), but it is a live path that contradicts "payments remain disabled" and would become serious the moment payments are switched on or a real order reaches `holding`.

Recommended (not done; production change needs written approval):

- Owner to decide how to handle the held test order (leave, or release manually after review).
- Gate `confirm_delivery` / `_apply_order_payout` on `payments_live` and on a non-test order, or disable the WhatsApp confirm path until payments are approved.
- Reword the webhook reply so it makes no credit claim while payments are off.

## 2. Admin console and `mark_payout_settled` (Decision 1, open)

- No admin console source exists in the repository.
- `mark_payout_settled` has no database callers.
- No production Edge Function calls it.
- The external admin URL referenced by the notification digest has not been inspected.

Decision 1 is still needed: owner to provide the admin console source or access, or confirm no console calls the function. Until then the lockdown SQL (`PHASE4-01`) must not be applied, because we cannot prove what would break.

## 3. Seller packing view (address-free)

Draft: `docs/pilot/remediation/PHASE5-seller-pack-lines-DRAFT.sql` (NOT APPLIED).

- Dry run on staging inside a rolled-back transaction passed.
- Expected result: 4 distinct orders for seller 1 (5 order lines). An earlier expectation of 5 orders was wrong; the query result is correct.
- Exposes order id, product id, product name, quantity, order status and order time. No buyer id, no delivery address, no phone number.

Still to test before any apply: seller A cannot see seller B's lines; no buyer address is reachable through alternative queries; anon has no access.

## 4. KYC storage and privacy (Decision 2, open)

- `seller_kyc` on staging and production has 0 rows; no document fields are populated.
- Policy `kyc_own_read` lets a seller read every column, including `id_number` and bank fields. This must be restricted before any real KYC collection.
- No KYC storage bucket exists on either project. That does not prove documents are not stored elsewhere; the owner needs an explicit answer about every location, including external services.
- Recommendation: keep sensitive KYC collection disabled for the pilot (ID numbers, bank details, identity documents). Pilot UI already has no KYC collection.

## 5. Allocation model

- Route orders: seller 90%, platform 10% of product subtotal (live path).
- Legacy trigger 80/10/5/5 is attached and enabled but not reachable from app roles; origin not traceable in repo history or migrations.
- Production ledger: the 7 released test orders show 80% to seller, 10% to platform, and 10% (driver/marshal share) with no destination in driver or marshal wallets. The unallocated 10% is a reconciliation gap, not yet resolved.
- Platform wallet balance 118.00 reconciles to platform fees of the released orders (113) plus one further order (5).
- Driver/marshal 2:1 split is a working assumption; not verified in code for route orders.

No allocation change until reconciled (owner rule).

## 6. Notification path: staging points at production

`dispatch_notification_webhook()` → `private.post_notification()` → HTTP POST to the production `dispatch-notification` URL. This runs on the staging database too, so staging test notifications reach production's function. Must be fixed under a separate approved change; it also means credential rotation must consider this consumer.

## 7. Production wording and personal-data risks (no change made)

- `dispatch-notification`: withdrawal fallback text says approved; SMS stub logs phone number and message body.
- `whatsapp-webhook`: `report_problem` text mentions "payment stays held", which is wrong while payments are off and becomes a money claim if `payments_live` flips without review.
- `lindi-chat`: model string hardcoded.
- `stripe-webhook`: retired, returns 410 (Paystack is the chosen provider).

## 8. Storage and proof-photo access

- Production bucket `delivery-proof`: participant read plus admin. Marshal collection photos are not covered by an explicit policy.
- Production `product-photos`: public.
- Staging: no storage policies.
- Needs a separate review before the SEC-06 migration is considered.

## 9. SEC-06 (production privacy migration)

Draft remains in `docs/pilot/remediation/PHASE4-PRODUCTION-SEC-06-migration.sql`. Not executed, not approved. Owner position: build and test the address-free packing view in staging first, then re-test before any production change.

## Decisions needed from owner

1. Decision 1: admin console source or access, or confirmation no console calls `mark_payout_settled`.
2. Decision 2: confirm sensitive KYC collection stays disabled for the pilot.
3. Held test order (total 50) on production: leave, or release after review.
4. Approval to gate the WhatsApp confirm path on `payments_live` (production change; needs written approval).
5. Owner actions: credential rotation, GitHub 2FA by 8 December 2026, taxi association, rosters, counsel's advice, Paystack confirmation.

Nothing in this document authorises a production or Supabase change, payment activation, merge or deployment.

## Phase 5B correction (2026-11-10)

Phase 5 named one payout route (WhatsApp). The complete list, from read-only production inspection, is in `PHASE5B-PAYOUT-CONTAINMENT.md` section 1:

- **R1** WhatsApp confirm (service role).
- **R2** Direct buyer RPC `confirm_delivery` (any signed-in buyer; authenticated EXECUTE). Not previously identified.
- **R3** Hourly cron `escrow-auto-release-72h` releases any `holding` order 72 hours after delivery with no open dispute. No human action needed. Not previously identified. This is the most dangerous route.
- **R4** `complete_order` and `resolve_dispute` (service role only).

All four end in `_apply_order_payout`. The draft containment guards that function and removes R2's buyer EXECUTE. Reconciliation of the eight production orders is in `PHASE5B-RECONCILIATION.md`. The draft `remediation/PHASE5-seller-pack-lines-DRAFT.sql` was not changed in this pass.
