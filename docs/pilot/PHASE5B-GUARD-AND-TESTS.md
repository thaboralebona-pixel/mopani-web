# Phase 5B-2: payout call graph, guard review, missing-recipient design, order 96 and tests

Date: 2026-11-10. Branch: `feature/readiness-pass-1`.

**Constraint for this pass:** no production SQL was run. Facts below come from read-only queries and reads made earlier today (recorded in `PHASE5B-PAYOUT-CONTAINMENT.md` and `PHASE5B-RECONCILIATION.md`), plus repository searches run in this pass. Anything not read is marked **Unverified**. No staging SQL was run. No test has been executed.

Evidence labels: **Confirmed** (read from a live definition or row), **Repo** (read from this repository), **Inferred**, **Unverified**.

---

## 1. Payout call graph

### 1.1 What the repository contains

- `src/` contains no call to any payout, settlement, confirmation or refund function (**Repo**, confirmed by search).
- The repository has no `supabase/functions` directory (**Repo**). Production Edge Function sources were read through the Supabase tooling earlier and are not in version control. That is a finding in its own right (SEC-31 below).

### 1.2 Callers of `public._apply_order_payout(bigint)` (**Confirmed** from definitions read earlier)

| Caller                                      | Type                                    | Role that can execute the caller                         | Path to payout                            | Writes audit row?                           |
| ------------------------------------------- | --------------------------------------- | -------------------------------------------------------- | ----------------------------------------- | ------------------------------------------- |
| `confirm_delivery(bigint, text)`            | function, SECURITY DEFINER              | `authenticated` EXECUTE (confirmed `true`); `anon` false | direct                                    | **No**                                      |
| `complete_order(bigint, text)`              | function, SECURITY DEFINER              | service role only (anon false, authenticated false)      | direct                                    | No                                          |
| `resolve_dispute(bigint, text, text, text)` | function, SECURITY DEFINER              | service role only; **body has no admin check**           | `release_to_seller` branch                | No                                          |
| `private.auto_release_escrow()`             | function, SECURITY DEFINER, run by cron | cron job owner (not recorded)                            | loop per order, sub-transaction per order | Yes: `auto_release` / `auto_release_failed` |

### 1.3 Routes into those callers

| Route   | Entry point                                                                                                                                                                           | Who can trigger                                                                                                                    | Notes                                                                                                                              |
| ------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------- |
| **R1**  | `whatsapp-webhook` (Edge Function, production) → `confirm_order_delivery_by_phone(p_phone, p_order_id, p_idempotency_key)` (SECURITY DEFINER, service role only) → `confirm_delivery` | Any message from the buyer's verified WhatsApp number. Signature checked by webhook (HMAC `X-Hub-Signature-256`).                  | Writes `delivery_confirmed_via_whatsapp` or `whatsapp_confirm_failed` / `whatsapp_identity_mismatch` audit rows.                   |
| **R2**  | Direct PostgREST RPC `confirm_delivery(p_order_id, p_idempotency_key)`                                                                                                                | Any **signed-in** user (`authenticated` EXECUTE). Body requires `buyer_id = auth.uid()` and status `delivered` + escrow `holding`. | No audit row. Frontend does not call it (**Repo**). Reachable by anyone who calls the API.                                         |
| **R3**  | pg_cron job `escrow-auto-release-72h` (jobid 2, `0 * * * *`, active) → `private.auto_release_escrow()`                                                                                | No human. Runs hourly.                                                                                                             | Releases orders delivered more than 72h 30min ago, buyer not confirmed, no open dispute. Sets `buyer_confirmed = true` itself.     |
| **R4a** | `complete_order`                                                                                                                                                                      | Service role only (grant)                                                                                                          | Called by retired Stripe webhook per prior notes. Stripe webhook returns 410. Route is dormant but still callable by service role. |
| **R4b** | `resolve_dispute(..., 'release_to_seller', ...)`                                                                                                                                      | Service role only (grant); no body check                                                                                           | Admin tooling, if any, would use this. The external admin console is **not inspected** (Decision 1).                               |

**Confirmed answer to "are R1, R2 and R3 the only routes?": no.** R4a and R4b exist and are service-role routes. They are not buyer- or schedule-reachable, so R1 to R3 remain the exposed set, but the list is R1, R2, R3 **plus** R4a and R4b.

### 1.4 Other possible indirect routes (**Unverified**)

- `private.run_background_sweeps()` (cron jobid 3, hourly): body not read in this pass or earlier. Its name suggests dispute or SLA handling. If it changes dispute status, see section 6.
- `private.auto_cancel_undispatched()` (cron jobid 6): body not read. Could change order status.
- Direct table writes: if `authenticated` holds UPDATE on `orders.escrow_status` or `disputes.status`, or INSERT on `orders` with `escrow_status = 'holding'`, a buyer could create the preconditions for R2 without any payment. **Table grants and RLS for `orders`, `disputes` and `deliveries` were not read.** This is the highest-priority unverified item for the guard, because it is a bypass that containment step 2 would not close.
- Edge Functions other than `whatsapp-webhook` (for example `dispatch-whatsapp`, `lindi-chat`) were read earlier. None calls a payout function (**Confirmed** from source read in Phase 5). Their service-role keys still reach the database, so a leaked key reaches every R4 route.

---

## 2. Cron containment (summary; full SQL in `remediation/PHASE5B-cron-containment.sql`)

| Item                   | Value (**Confirmed**)                                                                                                                        |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------- |
| Job identifier         | jobid `2`, name `escrow-auto-release-72h`                                                                                                    |
| Current schedule       | `0 * * * *`                                                                                                                                  |
| Command                | `SELECT private.auto_release_escrow();`                                                                                                      |
| Function               | `private.auto_release_escrow()`, SECURITY DEFINER, `search_path = public`                                                                    |
| Execution role         | The cron job owner, which was **not recorded**. The function runs with its owner's rights. **Unverified** until `cron.job.username` is read. |
| Unschedule SQL         | `select cron.unschedule('escrow-auto-release-72h');`                                                                                         |
| Read-only verification | `select jobid, jobname, schedule, command, active from cron.job where jobname = 'escrow-auto-release-72h';` expect zero rows                 |
| Restore SQL            | `select cron.schedule('escrow-auto-release-72h', '0 * * * *', 'SELECT private.auto_release_escrow();');`                                     |

**Effect on existing orders and ledger:** unscheduling changes **no** order, wallet, ledger row, platform revenue row, dispute or audit row. It only removes the job entry. Orders that would have been released stay `delivered` / `holding`. The 72-hour test uses `delivered_at`, so eligibility is not lost. Restoring the job later would release any eligible order on the next run, so **restore only after the payout guard is in place**.

---

## 3. Central payout guard review

Reviewed artefacts: (a) the payments_live-only draft in `remediation/PHASE5B-containment-DRAFT.sql` step 1, and (b) the design draft `remediation/PHASE5B-guard-v2-DRAFT.sql`.

| Criterion                                                       | (a) payments_live-only draft                                       | (b) guard v2 draft                                                              | Notes                                                                                                                                                      |
| --------------------------------------------------------------- | ------------------------------------------------------------------ | ------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Rejects payout while payments disabled                          | **Yes**                                                            | Yes                                                                             | Only a switch. Anyone who can write `app_config` can flip it (see bypasses).                                                                               |
| Rejects orders without order-specific verified payment evidence | **No**                                                             | **Yes**, if `payment_evidence` is populated only by the signed provider webhook | `payment_evidence` **does not exist yet**. v2 cannot be applied until it does.                                                                             |
| Checks amount and currency against trusted DB values            | **No**                                                             | Yes: `round(total_amount*100)` vs `amount_cents`, currency `ZAR`                | Relies on `orders.total_amount` being correct. Confirmed: test orders have total set and `product_subtotal` NULL, so the total is the only trusted figure. |
| Prevents duplicate release                                      | Partial: escrow_status `holding` is checked by the legacy function | Yes: explicit check plus one verified row per order (`unique`)                  | Escrow state itself is mutable (see bypasses).                                                                                                             |
| Preserves open-dispute protection                               | **Yes** (unchanged)                                                | Yes (unchanged)                                                                 | Dispute protection applies to statuses open, under_review, escalated. A dispute in any other status is **not** a barrier.                                  |
| Requires valid recipient allocation                             | **No**                                                             | **No** (flagged, not fixed)                                                     | The legacy function credits a driver or marshal leg **only if** an ID exists. Nothing requires the ID.                                                     |
| Zero or missing recipient allocations cannot disappear          | **No** (confirmed: R113 dropped on the 7 released orders)          | **No** (flagged)                                                                | Requires a change to `_apply_order_payout_legacy` and `_apply_route_payout`, see section 5.                                                                |
| Atomic                                                          | Yes, within the caller's transaction                               | Yes, same                                                                       | Per-order isolation in the cron loop uses a sub-transaction. R1 and R2 roll back as a unit.                                                                |
| Auditable result                                                | **No** (no row written by the guard)                               | Yes: `payout_guard_passed` row in the same transaction                          | v2 must also record the evidence id and the recipient legs. Callers' audit rows differ (R2 writes none).                                                   |

### 3.1 Known bypasses

| #   | Bypass                                                                                        | Status                                                                             | Mitigation                                                                                  |
| --- | --------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------- |
| B1  | Flip `app_config.payments_live` to `true`                                                     | Possible for any role with write on `app_config` (grant **unverified**)            | Restrict `app_config` writes to service role; guard v2 does not depend on this switch alone |
| B2  | Buyer inserts an order with `escrow_status = 'holding'` and status `delivered`, then calls R2 | **Unverified** (depends on `orders` INSERT grant and RLS)                          | Check grants; containment step 2 removes R2 entirely, so B2 needs R2                        |
| B3  | Buyer updates own order's `escrow_status` directly                                            | **Unverified** (depends on `orders` UPDATE grant)                                  | Same as B2; restrict column writes                                                          |
| B4  | Dispute row closed by a direct UPDATE from an app role                                        | **Unverified** (`disputes` grant)                                                  | Restrict; guard v2 also rejects open-status only, so the protection depends on the row      |
| B5  | Service-role key leaked from any Edge Function or repository                                  | Key rotation is pending owner action                                               | Rotate after separation (section 5 of containment doc)                                      |
| B6  | Cron job restored or a new job added                                                          | Requires `cron` access                                                             | Job list is part of the Phase 5B verification                                               |
| B7  | Replay of a WhatsApp message                                                                  | Mitigated by `idempotency_key` in R1 (buyer-side check); R1 uses the webhook's key | Verify the key is per message, not per order                                                |
| B8  | A payment record written by a non-webhook source                                              | Guard v2 relies on who writes `payment_evidence`; no writer exists yet             | Table restricted to service role; writer must verify provider signature                     |

**Conclusion:** the proposed guard v2 would stop every route that lacks a verified payment row, **once the table exists and only the signed webhook writes it**. Until then, the strongest containment is steps 1 and 2 of the payments-off draft, plus the cron unschedule. Bypasses B2 to B4 must be verified before containment can be called complete.

---

## 4. Reconciliation: explanations of R904, R113, R5 and the monitor discrepancy

Facts are from the 2026-11-10 reconciliation (see `PHASE5B-RECONCILIATION.md`). The explanations below are reasoning from the verified legacy function body.

| Item                                       |          Amount | Explanation                                                                                                                                                                                                                                                                                                                                                | Status                                                                                                                                                              |
| ------------------------------------------ | --------------: | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Seller credits                             |         R904.00 | `_apply_order_payout_legacy` credits `seller_share = total − platform_fee − marshal_fee − driver_fee`, which equals 80% when no driver or marshal is present. Seven `wallet_transactions` rows, `type = credit`, `transaction_category = seller`, reference "Order #n payout". Sum matches `seller_wallets.available_balance` and `total_earned`.          | **Confirmed** (code and rows agree)                                                                                                                                 |
| Platform revenue                           |         R113.00 | `platform_fee` is 10% of total. Written to `platform_revenue` and added to `platform_wallet`. Association cut is zero (no `association_earnings` rows).                                                                                                                                                                                                    | **Confirmed**                                                                                                                                                       |
| Driver and marshal share                   | R113.00 missing | The legacy function computes `driver_fee` and `marshal_fee` (5% each), but inserts the marshal credit only inside `IF v_has_marshal` and the driver credit only inside `IF v_has_driver`. With no IDs, nothing is written. No `else` branch exists. The fee is calculated and then lost. No `driver_marshal_transactions` rows exist for the seven orders. | **Confirmed** (function body; NULL `driver_id` and `marshal_id` on all eight deliveries)                                                                            |
| Platform wallet variance                   |           R5.00 | `platform_wallet` balance and total_earned are 118.00. Platform revenue for the seven orders is 113.00. No `platform_revenue` row exists for order 96 (held, not released). The legacy function adds only `platform_revenue` amount to the wallet, so the 5.00 was added by some other writer.                                                             | **Unexplained.** Candidate writers: `refund_order` (updates `platform_wallet`), manual SQL, or a function not inspected. No audit row before 1 October explains it. |
| Monitor: seller ledger sum 0 vs stored 904 |            R904 | `wallet_transactions.wallet_type` is NULL on all seven seller rows. The platform check in the same monitor run returned 113, which matches `platform_revenue` and not a `wallet_transactions` sum. This pattern is consistent with the seller check filtering on a column that is NULL for every row.                                                      | **Inferred**, not proven. The monitor body was not read.                                                                                                            |

**Why no balancing entries:** the R113 gap and the R5 variance have no verified cause. A balancing entry would hide the cause. The owner's rule stands.

---

## 5. Missing-recipient design

### 5.1 Problem

A fee calculated for a driver or marshal that has not been assigned is currently dropped. The order is then released, and the money has no destination in the ledger. This is the R113 defect.

### 5.2 States

Each allocation leg is one row in a new table `allocation_legs` (design only; not created):

| State                   | Meaning                                                  | Ledger effect                                                              | Allowed next states                                 |
| ----------------------- | -------------------------------------------------------- | -------------------------------------------------------------------------- | --------------------------------------------------- |
| **Allocated**           | Amount calculated for a named role and order             | Internal ledger entry is created                                           | Pending recipient, Approved                         |
| **Pending recipient**   | Amount calculated, no driver or marshal assigned yet     | Held in a suspense bucket (not a beneficiary wallet); must not be released | Allocated (when assigned), Failed (cancelled order) |
| **Approved**            | Owner or policy approves the leg for release             | No money moves                                                             | Released internally, Failed                         |
| **Released internally** | Internal ledger credit written to the recipient's wallet | Wallet balance increases; **this is not payment to a person**              | Externally paid, Reconciled                         |
| **Externally paid**     | Provider or bank confirms money left the platform        | Provider reference stored                                                  | Reconciled                                          |
| **Failed**              | Could not be credited or paid; reason recorded           | No net change; retry or reversal recorded as a new row                     | Allocated (retry), Reconciled                       |
| **Reconciled**          | Ledger, provider and bank agree for this leg             | Closed                                                                     | none                                                |

Rules:

- An order cannot be released while any leg is **Pending recipient**, unless the owner approves a named policy (for example, assign to platform revenue with a stated reason).
- A zero-value leg is still a row. It cannot disappear.
- Internal allocation is not beneficiary payment. The UI and messages must not say "paid" or "credited" for **Allocated** or **Released internally** states while payments are not live.

### 5.3 Decision for the owner

Option A: keep driver and marshal shares in a suspense account until a recipient is assigned. Option B: cap the platform's take at 10% and reject release when the 5% legs cannot be assigned. Option A matches the working model (driver and marshal are paid per delivery). Option B is simpler but needs a rule change. **Recommended: A**, with the 2:1 split still unverified (see allocation doc).

---

## 6. Order 96 and dispute 9

### 6.1 State (Confirmed, read 2026-11-10)

- Order 96: `status = delivered`, `escrow_status = holding`, `buyer_confirmed = false`, total 50.00, delivery 82.
- Dispute 9: `order_id = 96`, `status = escalated`, reason "damaged", created 2026-07-23 16:12 UTC, SLA due 2026-07-25 16:12 UTC, SLA breach recorded 2026-07-25 20:05 UTC (audit), `resolved_at` NULL, `refund_issued = false`.

### 6.2 Functions that can change dispute 9 or order 96

| Function                                                           | Changes dispute 9?                                                                                                                             | Changes order 96?                                              | Triggers payout?                 | Callable by               |
| ------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------------------------- | -------------------------------- | ------------------------- |
| `resolve_dispute` (release branch)                                 | Yes: sets `resolved`                                                                                                                           | Yes: `holding`, `delivered`, then `completed`                  | **Yes**                          | service role              |
| `resolve_dispute` (refund branch)                                  | Yes                                                                                                                                            | Yes: `refunded`                                                | No                               | service role              |
| `private.auto_release_escrow()` (cron)                             | **No** (excluded while dispute open)                                                                                                           | Yes if dispute is no longer open                               | **Yes**                          | cron                      |
| `_apply_order_payout`                                              | No                                                                                                                                             | Escrow change only on success                                  | Yes (refuses while dispute open) | nobody (no app grant)     |
| `confirm_delivery` (R2) and `confirm_order_delivery_by_phone` (R1) | No                                                                                                                                             | Completes if escrow holding and no open dispute (it refuses)   | Yes                              | buyer (R2), WhatsApp (R1) |
| `complete_order`                                                   | No                                                                                                                                             | Completes                                                      | Yes                              | service role              |
| `refund_order`                                                     | No                                                                                                                                             | Requires `completed` + `released`, so **not applicable** to 96 | No                               | service role              |
| `run_background_sweeps` (cron)                                     | **Unknown.** Body not read. SLA breach was recorded but status is still `escalated`, which suggests no automatic close, but this is not proven | Unknown                                                        | Unknown                          | cron                      |
| Direct UPDATE on `disputes` or `orders` by app roles               | **Unverified** (grants not read)                                                                                                               | **Unverified**                                                 | Indirect                         | authenticated, if granted |

### 6.3 Routes that could release order 96

1. **Dispute row changes to any non-open status** (for example, by `resolve_dispute` with a refund outcome, a background sweep, or a direct write) **followed by the cron running**. The cron would release order 96 within the hour, because the order meets the other conditions (delivered, holding, not buyer-confirmed, delivered more than 72h 30min ago). **This is the most important risk for order 96.**
2. `resolve_dispute` with `release_to_seller` by a service-role caller. This pays out directly, with no evidence check.
3. R2 by the buyer **only if** the dispute is closed first (route 1) and buyer-confirm is then called. Buyer-confirm also requires `status = delivered` and no open dispute, so route 1 is a precondition.
4. Direct table writes (B3), unverified.

### 6.4 Assessment

- **Current risk:** dispute 9 is escalated, so both the payout function and the cron refuse to release order 96. The protection depends entirely on the status of one row.
- **Likelihood:** unknown. No route found in this pass closes dispute 9 automatically, but the background sweep body is unread.
- **Impact:** R50 test order. The same mechanism would apply to any real order, so the consequence is the pattern, not the amount.
- **Mitigation before any further change:** unschedule the cron (section 2). Confirm `run_background_sweeps` does not change disputes (read its body under approval). Keep dispute 9 unchanged.

We do **not** change order 96 or dispute 9 in this pass.

---

## 7. Staging tests

Status of every test: **NOT EXECUTED.** Execution needs written staging approval.

### 7.1 Safe to run on staging without fixtures (read-only checks)

| ID  | Test                                                                                                                                      | Expected                                                          |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------- |
| S1  | `has_function_privilege('authenticated', 'public.confirm_delivery(bigint,text)', 'EXECUTE')` after containment                            | false                                                             |
| S2  | Same for `anon` on every payout function (`_apply_order_payout`, `confirm_delivery`, `complete_order`, `resolve_dispute`, `refund_order`) | false                                                             |
| S3  | `cron.job` has no `escrow-auto-release-72h` row after containment                                                                         | zero rows                                                         |
| S4  | `has_table_privilege('authenticated', 'public.orders', 'UPDATE')` and column-level `escrow_status` privilege                              | false for escrow_status and status                                |
| S5  | `has_table_privilege('authenticated', 'public.disputes', 'UPDATE')`                                                                       | false                                                             |
| S6  | `has_table_privilege('authenticated', 'public.orders', 'INSERT')`                                                                         | false (or, if true, RLS must block escrow_status / status values) |
| S7  | `payment_evidence` exists with RLS enabled and zero policies for app roles (after v2 rehearsal)                                           | true                                                              |

### 7.2 Requires controlled fixtures on staging (not on production)

| ID  | Test                                                          | Route                                       | Expected                                                                                                                                                                               |
| --- | ------------------------------------------------------------- | ------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| T1  | Payout attempt with payments off on a delivered holding order | `_apply_order_payout` as service role       | raises "payments not live"; no wallet, ledger, platform or audit change                                                                                                                |
| T2  | Direct RPC by buyer, payments off                             | R2                                          | permission denied after containment step 2                                                                                                                                             |
| T3  | WhatsApp confirm, payments off                                | R1                                          | `ok=false`, order stays holding, `whatsapp_confirm_failed` audit only                                                                                                                  |
| T4  | Automatic release, payments off                               | R3                                          | 0 released; `auto_release_failed` rows only; after unschedule, no rows                                                                                                                 |
| T5  | Missing payment evidence (payments on)                        | guard v2                                    | raises "no verified payment evidence"                                                                                                                                                  |
| T6  | Incorrect amount (evidence present, amount ≠ total in cents)  | guard v2                                    | raises "does not match"                                                                                                                                                                |
| T7  | Wrong currency (USD evidence)                                 | guard v2                                    | raises                                                                                                                                                                                 |
| T8  | Duplicate payout attempt on a released order                  | guard v2                                    | raises "escrow is completed"                                                                                                                                                           |
| T9  | Duplicate evidence row for the same order                     | table constraint                            | unique violation                                                                                                                                                                       |
| T10 | Open dispute with valid evidence                              | guard v2                                    | raises "open dispute"                                                                                                                                                                  |
| T11 | Escalated dispute with valid evidence                         | guard v2                                    | raises "open dispute"                                                                                                                                                                  |
| T12 | Missing driver or marshal, valid evidence                     | legacy dispatch                             | **must not** drop the leg: expected result after the required change is a pending-recipient row; **current behaviour drops it (test will fail today, as designed to show the defect)** |
| T13 | Zero-value leg                                                | legacy dispatch                             | row written with 0 and a reason, not omitted                                                                                                                                           |
| T14 | Valid evidence, all legs assigned                             | guard v2                                    | payout succeeds once; `payout_guard_passed` audit row present; ledger sums equal total                                                                                                 |
| T15 | Failed payout rolls back                                      | guard v2 with forced error after the credit | no partial credit persists                                                                                                                                                             |
| T16 | Audit trail integrity                                         | all of the above                            | every payout has exactly one `payout_guard_passed` row with the evidence id                                                                                                            |

### 7.3 Required fixture design (for T1 to T16)

- A staging-only seller, buyer, driver, marshal and taxi rank, with `is_test_order = true`.
- Orders created through `create_order_v2` then driven to `delivered` by a staging-only helper, never by production data.
- Evidence rows written by a staging-only script under the service role, with a staging-only provider reference. No production provider data.
- Staging must have its own notification path (see containment doc section 5). Otherwise tests fire production messages.

---

## 8. Security-by-design observations

- A passing test suite is not proof of database security. The checks in 7.1 are the database-level proof, and only after they run on staging and then on production (read-only).
- `resolve_dispute` has no internal admin check. Its safety depends on the service-role grant alone. Add a check that the caller is an admin role, or document the grant as the only control.
- Edge Function sources are not in version control. Add them, so the call graph in section 1 can be checked against code.

---

## 9. New findings for the register

- **SEC-31:** Production Edge Function sources are not in the repository. The call graph cannot be verified from code.
- **SEC-32:** `resolve_dispute` has no body-level admin check (service-role grant only).
- **SEC-33:** Dispute 9 is the sole protection for held order 96. Closing it through any route allows auto-release within an hour.
- **SEC-34:** Legacy payout drops driver and marshal legs when IDs are absent (R113). Confirmed by definition.
- **SEC-35:** Platform wallet holds R5.00 more than platform revenue. No explanation. Unexplained.
- **SEC-36:** Integrity monitor seller check reports 0 against 904. Probable cause (wallet_type NULL) not confirmed.
- **SEC-37:** Unverified grants on `orders`, `disputes`, `app_config` and `payment_evidence` (not created). Bypasses B1 to B4 cannot be ruled out until read.
- **SEC-38:** Cron job owner not recorded (`cron.job.username`). Execution rights of the auto-release unverified.

---

## 10. Owner decisions arising

See `OWNER-DECISIONS.md` rows 25 to 31.

Nothing in this document authorises a production change, payment activation, merge or deployment.

## Phase 5B-3 corrections (2026-11-10)

Superseded by `PHASE5B-PRIVILEGE-AND-FUNCTION-REVIEW.md` where they differ:

- Section 1: add routes R5a, R5b (service role calling payout functions directly) and R6 (SQL as `postgres`). The background sweep and the auto-cancel job were read: neither pays out, neither closes disputes.
- Section 2: the cron job owner is `postgres`.
- Section 3: bypasses B1 to B4 are closed for app roles. New bypass B9: service role calling the leaf payout functions, which skips the dispute check and any guard in `_apply_order_payout`.
- Section 4: R5 is identified; the monitor discrepancy is a NULL-arithmetic bug.
- Section 6: no function can resolve or close an escalated dispute. Only privileged SQL can change dispute 9. Route R5b ignores the dispute.
- Section 7: add tests T17 (service role calls each leaf function directly; must be refused), T18 (order created by `create_order_v2` starts in a non-`holding` state once the new initial state exists), T19 (dispute insert by a user who is neither buyer nor seller is refused), T20 (monitor reports a correct seller ledger sum for a wallet with credits and no debits), T21 (`resolve_dispute` release branch on an open dispute: record whether it succeeds). All tests remain **not executed**.
