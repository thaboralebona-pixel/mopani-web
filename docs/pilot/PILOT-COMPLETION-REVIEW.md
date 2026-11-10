# Pilot completion review (Phase 4, P7)

Purpose: check the Phase 3 pilot documents for contradictions, missing responsibilities and operational gaps. Each question is answered as **designated**, **proposed (needs owner)** or **not defined**. Answers marked proposed are not decisions.

## 1. Responsibilities

| Question                                             | Status                                      | Answer / gap                                                                                                                                                                                                                                                                              |
| ---------------------------------------------------- | ------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Who confirms seller readiness?                       | Not defined                                 | Proposed: the team lead confirms the seller's product list, weights and stock; the owner approves the seller onto the pilot roster. Application has no approval step beyond KYC                                                                                                           |
| Who assigns drivers?                                 | Not defined                                 | The application has no assignment screen in this pilot. Proposed: team lead assigns by phone and records the assignment; `deliveries.driver_id` is set by the back end. Confirm how assignment is written today (not verified in this pass)                                               |
| Who assigns marshals?                                | Not defined                                 | Same as drivers. `deliveries.marshal_id` is set by the back end. Proposed: origin rank marshal assigned per route per day                                                                                                                                                                 |
| Who handles a missing marshal?                       | Not defined                                 | Decision 8 (48 hours) is open. Proposed: team lead finds a standby marshal within 2 hours; owner escalated after 48 hours                                                                                                                                                                 |
| Who contacts buyers when delivery is delayed?        | Not defined                                 | Proposed: team lead, same day, via the buyer's registered contact. No automatic message is confirmed (notifications queue exists; delay messages not verified)                                                                                                                            |
| Who resolves stock discrepancies?                    | Defined in `STOCK-DISCREPANCY-PROCEDURE.md` | Marshal records, team lead resolves, owner decides money matters                                                                                                                                                                                                                          |
| Who approves refunds or cancellations?               | Partly defined                              | Application: `admin_force_cancel` (admin only). It voids the escrow hold and restores stock, and states that the refund must be returned manually. **Owner must name the admin who may execute it.** No payment rail exists, so refunds are manual and must not be recorded as `refunded` |
| Who handles disputes?                                | Partly defined                              | Application: `disputes` table exists with statuses open, under_review, escalated, and an open dispute freezes payout (verified in `_apply_order_payout`). **Owner must name the dispute handler and the response time.** Not in the Phase 3 documents                                     |
| What happens when a buyer does not confirm delivery? | Not defined                                 | `orders.buyer_confirmed` exists. No timeout is defined in the application. Proposed: team lead contacts the buyer after 24 hours of proof of delivery; no auto-confirmation without owner decision                                                                                        |
| What happens when a driver becomes unavailable?      | Not defined                                 | Proposed: standby driver (in PILOT-DESIGN.md). Reassignment is manual and must be recorded. The application's reassignment path was not verified                                                                                                                                          |

## 2. Contradictions and corrections found in Phase 3 documents

1. **`BUYER-GUIDE.md` said orders are placed by the app.** The app has no order placement screen in this pilot. Corrected in Phase 3 to supervised ordering. Re-checked here: still accurate.
2. **`ROUTE-PRICING-VERIFICATION.md` lists product prices with conflicting notes.** Owner must confirm one figure per product. Still open.
3. **`PILOT-DESIGN.md` says "Payment collection is not available" and "orders placed by the team".** Consistent with owner decisions. But `CUSTOMER-COMPLAINT-PROCEDURE.md` mentions compensation. Compensation must be owner-approved, not team-approved. Wording to be tightened: no compensation promised.
4. **`SECURITY-REGISTER.md` (Phase 3) describes SEC-06 as "Fixed (staging)".** Accurate only for staging. Production remains exposed. Stated explicitly in the register.
5. **The 48-hour marshal rule appears in `PILOT-DESIGN.md` as an escalation trigger** but is still an open owner decision. It should be shown as proposed.
6. **`INCIDENT-REGISTER.md` requires counsel for POPIA reporting.** Consistent with KYC review.
7. **`OWNER-DECISIONS.md` (Phase 3) listed SEC-02 and SEC-03 as recommended.** Owner has now approved both in direction (Phase 4 provisional decisions). Updated.

## 3. Operational gaps

- No defined cut-off time for orders each day (PILOT-DESIGN proposes one; no owner value).
- No defined operating hours for support.
- No defined route vehicle capacity limit (`max_load_kg` is in a view that is being restricted; the limit must come from the roster, not the view).
- Seller packing needs an address-free view of their orders (see PRODUCTION-STAGING-DIFFERENCES.md section 4).
- Proof-of-delivery photos cannot be opened on staging (no storage policy). Staging journey test blocked until fixed.

## 4. Manual processes versus application functionality

| Process                    | Application functionality                                           | Manual procedure                                       |
| -------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------ |
| Browse products and routes | Yes (catalogue, routes)                                             | None                                                   |
| Quote a total              | Yes, server-side, only when signed in (sign-in not live on staging) | None                                                   |
| Place an order             | **No** in this pilot                                                | Supervised order entered by team                       |
| Confirm seller readiness   | No                                                                  | Team lead and owner                                    |
| Assign driver and marshal  | Partly (back end writes IDs; no screen)                             | Team lead by phone, recorded                           |
| Collect and count goods    | Recording is manual; app status only                                | Marshal count, STOCK-DISCREPANCY-PROCEDURE             |
| Track delivery             | Status via `buyer_delivery()` (staging only)                        | Team lead updates by phone where status is missing     |
| Confirm receipt            | `buyer_confirmed` field exists; no UI verified                      | Buyer confirms to team, recorded                       |
| Cancel an order            | `admin_force_cancel` (admin only)                                   | Owner or named admin decides, manual refund            |
| Refund                     | **No payment rail**                                                 | Manual, owner-approved, not recorded as paid           |
| Withdraw seller balance    | **Disabled by SEC-01 (staging)**                                    | None during pilot                                      |
| Dispute                    | `disputes` table; freezes payout                                    | Named handler, manual                                  |
| Payouts                    | Ledger entries only; not money                                      | None during pilot. Ledger entries do not prove payment |

## 5. Remaining decisions (see OWNER-DECISIONS.md)

Refund authority, dispute handler, buyer confirmation timeout, marshal wait limit, roster owners, cut-off time, support hours.
