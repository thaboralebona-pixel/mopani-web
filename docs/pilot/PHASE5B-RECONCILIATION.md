# Phase 5B: production order reconciliation (read-only)

Read on 2026-11-10 from production (`jpjjdzlhthvookllydai`). **No financial record was modified.** Amounts are in rand. "Unallocated" means calculated but not credited to any wallet.

## 1. Order-by-order

Legacy split (non-route orders): seller 80%, platform 10%, marshal 5%, driver 5%. Seller and platform credits below are read from `wallet_transactions`, `platform_revenue` and the order columns. Every order has `driver_id` and `marshal_id` NULL on its delivery, so the marshal and driver legs have no destination.

| Order                  | Status / escrow         | Test |        Total |             Seller (credited) |          Platform (credited) | Driver + marshal (unallocated) | Released             | Legacy trigger | Notes                          |
| ---------------------- | ----------------------- | ---- | -----------: | ----------------------------: | ---------------------------: | -----------------------------: | -------------------- | -------------- | ------------------------------ |
| 49                     | completed / released    | yes  |        90.00 |                         72.00 |                         9.00 |                           9.00 | 2026-07-20 15:06 UTC | yes            | Buyer-confirmed flag set       |
| 50                     | completed / released    | yes  |        50.00 |                         40.00 |                         5.00 |                           5.00 | 2026-07-20 15:06 UTC | yes            |                                |
| 51                     | completed / released    | yes  |        75.00 |                         60.00 |                         7.50 |                           7.50 | 2026-07-20 15:06 UTC | yes            |                                |
| 52                     | completed / released    | yes  |        90.00 |                         72.00 |                         9.00 |                           9.00 | 2026-07-20 19:37 UTC | yes            |                                |
| 53                     | completed / released    | yes  |       700.00 |                        560.00 |                        70.00 |                          70.00 | 2026-07-20 19:37 UTC | yes            | Largest test order             |
| 54                     | completed / released    | yes  |        75.00 |                         60.00 |                         7.50 |                           7.50 | 2026-07-20 19:37 UTC | yes            |                                |
| 81                     | completed / released    | yes  |        50.00 |                         40.00 |                         5.00 |                           5.00 | 2026-07-21 18:58 UTC | yes            |                                |
| 96                     | delivered / **holding** | yes  |        50.00 | not credited (would be 40.00) | not credited (would be 5.00) |   not credited (would be 5.00) | not released         | not run        | Dispute 9 `escalated`, damaged |
| **Total released (7)** |                         |      | **1,130.00** |                    **904.00** |                   **113.00** |                     **113.00** |                      |                |                                |

Check: 904 + 113 + 113 = 1,130. Reconciles to the total.

## 2. Ledger and wallet tie-out

| Source                                                           |  Amount | Compared to                                                    | Result                                                                                                       |
| ---------------------------------------------------------------- | ------: | -------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `wallet_transactions` seller credits (7 rows, "Order #n payout") |  904.00 | `seller_wallets` available and total_earned for the one seller | Ties (904.00)                                                                                                |
| `platform_revenue` rows (7)                                      |  113.00 | Platform fee per order (10%)                                   | Ties                                                                                                         |
| `platform_wallet.balance`                                        |  118.00 | Platform revenue 113.00                                        | **Variance +5.00. No `platform_revenue` row exists for order 96 and order 96 is not released. Unexplained.** |
| `platform_wallet.total_earned`                                   |  118.00 | Same as above                                                  | Same variance                                                                                                |
| `driver_wallets`                                                 | no rows | 56.50 expected had a driver existed                            | No driver credit ever written                                                                                |
| `marshal_wallet`                                                 |    0.00 | 56.50 expected had a marshal existed                           | No marshal credit ever written                                                                               |
| Driver and marshal `driver_marshal_transactions`                 |    none |                                                                | No rows written for any of the 7 orders                                                                      |

The 113.00 driver and marshal share is calculated in `_apply_order_payout_legacy` and then dropped, because the function credits a leg only when a driver or marshal ID is present. This is a **functional defect in the legacy path**, not a missing number.

## 3. Existing integrity monitor (already flagged, not acted on)

`admin_audit_log` contains a `wallet_integrity_mismatch` run from 2026-07-26 18:15 UTC:

| Target         | Variance | Ledger sum | Stored | Reading                                                                                                                                                                                                                                      |
| -------------- | -------: | ---------: | -----: | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| platform:1     |    +5.00 |     113.00 | 118.00 | Matches the table above                                                                                                                                                                                                                      |
| seller:03c6... |  +904.00 |       0.00 | 904.00 | **The monitor's ledger sum is 0 while `wallet_transactions` shows 904.00 for this seller.** Either the monitor filters on a column that is NULL on every row (`wallet_type` is NULL on all 7), or the ledger link is broken. **Unverified.** |

No later audit row shows anyone responding to this run.

## 4. How the 7 releases happened (inference)

**Confirmed:** no audit row with action `delivery_confirmed_via_whatsapp`, `auto_release` or `whatsapp_confirm_failed` exists before 2026-10-01. Each of the 7 releases has only `order_state_change` rows (written by a trigger on `orders`), with no `admin_id`.

**Assumption:** the releases came through a path that writes no audit row of its own, which fits a direct authenticated `confirm_delivery` call (route R2 in `PHASE5B-PAYOUT-CONTAINMENT.md`). Routes R1 and R3 both write their own audit rows. This should be checked against the API request log for 2026-07-20 and 2026-07-21 before anyone relies on it.

## 5. Held order 96 (R50)

- Status `delivered`, escrow `holding`, `buyer_confirmed = false`.
- Dispute 9 is `escalated`, opened 2026-07-23 for "damaged", SLA due 2026-07-25, **SLA breached** (audit row 2026-07-25), no resolution.
- While dispute 9 is open, `_apply_order_payout` refuses. R1 and R2 fail on this order, and R3 excludes it.
- If dispute 9 is set to closed or resolved without a payout decision, R3 (hourly cron) releases order 96 within the hour, and R2 becomes possible for the buyer.
- Can order 96 still pay out through another channel? **Yes, if the dispute row changes.** Only `resolve_dispute` (service role) can resolve it by design. No other route checked.

## 6. Missing allocations and differences (summary)

| Item                                          | Amount | Status                                                                                                           |
| --------------------------------------------- | -----: | ---------------------------------------------------------------------------------------------------------------- |
| Driver and marshal share on 7 released orders | 113.00 | Unallocated. No destination.                                                                                     |
| Platform wallet above platform revenue        |   5.00 | Unexplained. Possibly related to order 96; not proven.                                                           |
| Seller wallet vs monitor ledger sum           | 904.00 | Monitor disagrees with `wallet_transactions`. Unverified.                                                        |
| Seller payment evidence for the 904.00        |   none | No payment reference exists on these orders (`stripe_session_id` and `stripe_payment_intent` are NULL on all 8). |

## 7. Why the seller balance cannot be withdrawn today

`request_withdrawal_v2` requires `seller_kyc.kyc_status = 'verified'`. Production `seller_kyc` has 0 rows, so no seller can request a withdrawal. The 904.00 is therefore a **liability on paper**, not cash that can leave the platform through the app. This is a control that depends on KYC being empty. It is not a payout control.

## 8. What not to do

- Do not release or re-run order 96.
- Do not reverse, redistribute or edit any row listed above.
- Do not write a balancing entry until the owner has decided the correction method (see `PHASE5B-PAYOUT-CONTAINMENT.md`, decision D).

## Phase 5B-2 explanations (2026-11-10)

Full reasoning in `PHASE5B-GUARD-AND-TESTS.md` section 4.

- **R904 seller credits: confirmed.** Legacy code credits 80% of total when no driver or marshal is present. Seven credit rows sum to 904, matching the seller wallet.
- **R113 platform revenue: confirmed.** 10% of total, written to `platform_revenue` and added to the platform wallet. No association cut applies.
- **R113 driver and marshal share: confirmed missing by design defect.** The legacy function calculates 5% + 5% and writes a leg only when an ID exists. No `else` branch, so the amount is dropped. No `driver_marshal_transactions` rows exist for these orders.
- **R5 platform variance: unexplained.** Platform wallet 118 vs platform revenue 113. Order 96 has no revenue row. The wallet was changed by a writer other than the legacy release. Candidate writers include `refund_order` and any unread function. No balancing entry is made.
- **Monitor seller 0 vs 904: inferred.** `wallet_type` is NULL on all seller rows; the monitor's seller check probably filters on it. Monitor body not read.
- **Release channel for the seven orders: inferred.** No audit row of the R1 or R3 type exists before 1 October, consistent with R2 (direct RPC, no audit row). Log window not checked: the log tool covers 24 hours per query and the events are about four months old.
- **Payment references:** `stripe_session_id` and `stripe_payment_intent` are NULL on all eight orders. No payments table was read in this pass.
- No historical record, balance or ledger entry was changed.
