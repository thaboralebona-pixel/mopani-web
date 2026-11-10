# Phase 5B-3: privileges, scheduled jobs, function review, R5, monitor and payment evidence

Date: 2026-11-10. Production project `jpjjdzlhthvookllydai`. **Read-only pass.** Every query was a `SELECT` against catalogs, tables, views and the migration history. No write, migration, grant, revoke, cron change, function change, deployment, order, dispute, wallet or ledger change was made on production or staging.

Evidence labels: **Confirmed** (read this pass), **Inferred** (reasoned from confirmed facts), **Unresolved** (could not be answered read-only or not read).

This document corrects earlier Phase 5B statements where the new evidence contradicts them. Corrections are listed in section 9.

---

## 1. Effective privilege matrix

### 1.1 Roles (**Confirmed**)

| Role            | Superuser | Bypasses RLS | Notes                                                                                                                     |
| --------------- | --------- | ------------ | ------------------------------------------------------------------------------------------------------------------------- |
| `anon`          | no        | no           | Unauthenticated API calls                                                                                                 |
| `authenticated` | no        | no           | Every signed-in user: buyer, seller, driver, marshal, admin                                                               |
| `service_role`  | no        | **yes**      | Edge Functions and server tooling                                                                                         |
| `postgres`      | no        | **yes**      | Owner of every table and function reviewed; role used by all cron jobs; member of `anon`, `authenticated`, `service_role` |
| `authenticator` | no        | no           | API gateway role; can switch to `anon`, `authenticated`, `service_role`                                                   |

RLS is **enabled** and **not forced** on every table below. Table owner (`postgres`) and `service_role` are not subject to RLS. Every SECURITY DEFINER function reviewed is owned by `postgres`, so it runs with RLS bypassed.

### 1.2 Tables (**Confirmed**)

"Grant" is the table-level privilege. "Effective" is what the role can do once RLS policies are applied. No policy for a command means that command is denied for non-bypass roles.

| Table                                                                                                                                   | `anon` grant | `authenticated` grant                                       | Policies                                                             | `anon` effective | `authenticated` effective                                                                    |
| --------------------------------------------------------------------------------------------------------------------------------------- | ------------ | ----------------------------------------------------------- | -------------------------------------------------------------------- | ---------------- | -------------------------------------------------------------------------------------------- |
| `orders`                                                                                                                                | none         | SELECT, INSERT, DELETE (**no UPDATE**)                      | INSERT `with check (false)`; SELECT for own buyer, own seller, admin | nothing          | Read own rows only. **No insert, update or delete.**                                         |
| `order_items`                                                                                                                           | none         | all four                                                    | SELECT only (buyer of order, seller of product)                      | nothing          | Read only                                                                                    |
| `disputes`                                                                                                                              | none         | all four, all columns                                       | INSERT `raised_by = auth.uid()`; SELECT own                          | nothing          | Read own; **insert a dispute for any order id, with any status value**; no update, no delete |
| `app_config`                                                                                                                            | SELECT       | all four                                                    | **none**                                                             | nothing          | nothing                                                                                      |
| `admins`                                                                                                                                | SELECT       | all four                                                    | **none**                                                             | nothing          | nothing                                                                                      |
| `seller_wallets`                                                                                                                        | none         | SELECT, INSERT, DELETE                                      | SELECT own                                                           | nothing          | Read own only                                                                                |
| `wallet_transactions`                                                                                                                   | none         | all four                                                    | SELECT own                                                           | nothing          | Read own only                                                                                |
| `seller_withdrawals`                                                                                                                    | none         | all four                                                    | SELECT own                                                           | nothing          | Read own only                                                                                |
| `driver_wallets`                                                                                                                        | none         | all four                                                    | SELECT own                                                           | nothing          | Read own only                                                                                |
| `driver_marshal_transactions`                                                                                                           | SELECT       | all four                                                    | SELECT own                                                           | nothing          | Read own only                                                                                |
| `deliveries`                                                                                                                            | none         | all four, all columns                                       | SELECT for driver, marshal, buyer, seller, admin                     | nothing          | Read only                                                                                    |
| `listing_fee_payments`                                                                                                                  | none         | all four                                                    | SELECT own                                                           | nothing          | Read own only                                                                                |
| `profiles`                                                                                                                              | SELECT       | SELECT, DELETE; column INSERT and UPDATE (includes `phone`) | own insert, own read, own update                                     | nothing          | Read and update own row, including `phone`; no delete                                        |
| `platform_wallet`, `platform_revenue`, `marshal_wallet`, `association_earnings`, `idempotency_keys`, `admin_audit_log`, `impact_ledger` | none         | none                                                        | none                                                                 | nothing          | nothing                                                                                      |

No table named `payments` exists. The only payment-named table is `listing_fee_payments`. `orders` carries `stripe_session_id` and `stripe_payment_intent`, NULL on all eight rows.

**Hygiene finding (SEC-39):** `authenticated` holds table-level INSERT, UPDATE and DELETE on nine financial or operational tables where RLS is the only barrier. One permissive policy added by mistake would open them. RLS is not forced. Recommend revoking the unused table privileges (separate approved change).

### 1.3 Default privileges (**Confirmed**)

- New tables in `public` created by `postgres` or `supabase_admin` are granted ALL to `anon`, `authenticated` and `service_role` by default.
- New functions in `public` created by `postgres` are granted to `postgres` and `service_role` only. Functions created by `supabase_admin` are granted to `anon` and `authenticated` too.

Consequence: any new table, including the proposed `payment_evidence`, is exposed to app roles at table level the moment it is created, unless the same migration revokes and enables RLS.

### 1.4 Can a buyer alter these? (**Confirmed** unless marked)

| Target                        | Direct write         | Through a function they can call                                                                                                                                                                                         | Conclusion                                                                                                                         |
| ----------------------------- | -------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ | ---------------------------------------------------------------------------------------------------------------------------------- |
| Order status                  | No (no UPDATE grant) | `confirm_delivery` → `completed` (own order, `delivered` + `holding`, pays out). `raise_dispute` → `disputed` (own order). `admin_force_cancel` is callable but its admin check was **not fully read** (**Unresolved**). | Yes, only along those paths                                                                                                        |
| Escrow status                 | No                   | `confirm_delivery` → `released`; `raise_dispute` → `disputed`                                                                                                                                                            | Yes, only along those paths. A buyer cannot set `holding`, but **does not need to: `holding` is the column default** (section 4.1) |
| Buyer identity (`buyer_id`)   | No                   | None found. `create_order_v2` sets it from `auth.uid()`                                                                                                                                                                  | No                                                                                                                                 |
| Order total                   | No                   | None found. `create_order_v2` takes the total from `quote_order`                                                                                                                                                         | No                                                                                                                                 |
| Dispute status                | No update, no delete | Can **insert** a new dispute row with any status. Cannot change an existing one. `resolve_dispute` is service role only                                                                                                  | Cannot close or alter a dispute. Can open one on any order                                                                         |
| Payment switch (`app_config`) | No (no policy)       | `admin_approve`, `admin_nominate`, `admin_revoke` write `admins`, each checks `is_admin()` (**Confirmed** for approve and nominate). No app-callable function found that writes `app_config`                             | No                                                                                                                                 |

Bypasses B1 to B4 from `PHASE5B-GUARD-AND-TESTS.md` are **closed for app roles**. They remain open for `service_role` and `postgres` by design.

---

## 2. Complete payout call graph (replaces earlier versions)

Wallet credits are written by exactly two leaf functions: `_apply_route_payout` and `_apply_order_payout_legacy`. Both are called by `_apply_order_payout`. No trigger function writes `platform_wallet`. The only other non-trigger writer of `platform_wallet` is `refund_order`.

| Route   | Entry                                                                                                                           | Execution role at entry                                                       | Can reach payout?                                                                  |
| ------- | ------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| R1      | `whatsapp-webhook` → `confirm_order_delivery_by_phone` → `confirm_delivery` → `_apply_order_payout`                             | `service_role` (function not executable by anon or authenticated)             | Yes                                                                                |
| R2      | RPC `confirm_delivery`                                                                                                          | `authenticated` (EXECUTE **true**)                                            | Yes                                                                                |
| R3      | cron `escrow-auto-release-72h` → `private.auto_release_escrow` → `_apply_order_payout`                                          | `postgres`                                                                    | Yes                                                                                |
| R4a     | `complete_order`                                                                                                                | `service_role`                                                                | Yes                                                                                |
| R4b     | `resolve_dispute` (release branch)                                                                                              | `service_role`; no body admin check; **only for disputes with status `open`** | Yes                                                                                |
| **R5a** | `_apply_order_payout` called directly                                                                                           | `service_role` (EXECUTE **true**)                                             | Yes                                                                                |
| **R5b** | `_apply_route_payout` or `_apply_order_payout_legacy` called **directly**                                                       | `service_role` (EXECUTE **true** on both)                                     | Yes, and it **skips the dispute check**, which lives only in `_apply_order_payout` |
| R6      | Any SQL run as `postgres` (dashboard SQL editor, direct connection with the database password, a new cron job, a new migration) | `postgres`                                                                    | Yes                                                                                |

R1, R2 and R3 are **not** the only routes. R5a, R5b and R6 exist for privileged roles. No other buyer-, seller-, driver- or marshal-reachable route was found.

**Guard placement consequence:** a guard placed only in `_apply_order_payout` is bypassed by R5b. The guard must live in both leaf functions, or `service_role` EXECUTE on the leaves must be revoked.

### 2.1 How the preconditions for payout arise

Payout needs: order `delivered` (or `paid` for `complete_order`), escrow `holding`, no open dispute.

- `holding`: set **by default at order creation**. No payment involved.
- `delivered`: set by `mark_delivered`, callable by `authenticated`, restricted in the body to the assigned driver, delivery `in_transit`, proof photo present. Also set at creation by the legacy `create_order` test path (`p_is_test`), which is service role only.
- No open dispute: the normal case.

**Therefore the ordinary pilot flow reaches payout without any payment.** A signed-in buyer places an order with `create_order_v2` (EXECUTE true), a verified driver delivers it, and then either the buyer confirms (R1 or R2) or the cron releases it after 72 hours (R3). Nothing in this flow involves misuse. It is how the system is built. This is the central finding of this pass (SEC-40).

---

## 3. Scheduled job inventory (**Confirmed**)

All jobs: database `postgres`, user `postgres`, node `localhost`, active.

| Job id | Name                       | Schedule      | Command                                        | Runs recorded                                                     | Payout or dispute effect                                                                                               |
| ------ | -------------------------- | ------------- | ---------------------------------------------- | ----------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------- |
| 2      | `escrow-auto-release-72h`  | `0 * * * *`   | `SELECT private.auto_release_escrow();`        | 3,072, all succeeded; first 2026-07-05; last 2026-11-10 13:00 UTC | **Pays out** eligible orders                                                                                           |
| 3      | `background-sweeps`        | `5 * * * *`   | `SELECT private.run_background_sweeps();`      | 2,586, all succeeded                                              | Escalates overdue disputes (`open`/`under_review` → `escalated`). Never closes one. Flags anomalies. No payout.        |
| 4      | `whatsapp-dispatch`        | `*/5 * * * *` | `SELECT private.invoke_whatsapp_dispatcher();` | 30,903, all succeeded                                             | None found (body not read this pass)                                                                                   |
| 5      | `founder-digest-1800-sast` | `0 16 * * *`  | `SELECT private.queue_founder_digest();`       | 107, all succeeded                                                | None                                                                                                                   |
| 6      | `auto-cancel-undispatched` | `15 * * * *`  | `SELECT private.auto_cancel_undispatched();`   | 698, all succeeded                                                | Cancels `pending` + `holding` orders older than 48h with no driver, **only while payments are off**. Writes no wallet. |

Job 2 details:

- **Owner and execution role:** `postgres`.
- **Function:** `private.auto_release_escrow()`, owner `postgres`, SECURITY DEFINER.
- **Other invocation routes:** not executable by `anon`, `authenticated` or `service_role`. Only `postgres` can call it: the cron, the dashboard SQL editor, or a direct database connection. The production database password is therefore a payout credential.
- **Other jobs calling payout or dispute functions:** job 3 changes dispute status upward only. No other job calls a payout function.

---

## 4. Function-by-function security review

All functions below: owner `postgres`, SECURITY DEFINER, `search_path = public` (**Confirmed**).

### 4.1 `_apply_order_payout(bigint)`

- **EXECUTE:** anon no, authenticated no, service_role **yes**.
- **Reads:** `disputes`, `orders`. **Writes:** none itself; dispatches.
- **Payment check:** none. **Dispute check:** yes (open, under_review, escalated). **Idempotency:** none here; leaf checks `escrow_status = 'holding'`.
- **Audit:** none.
- **Bypass:** leaf functions callable directly by service role (R5b).

### 4.2 `_apply_order_payout_legacy(bigint)` (current body)

- **EXECUTE:** service_role yes.
- **Reads:** `orders` (FOR UPDATE), `deliveries`, `driver_profiles`, `taxi_ranks`, `taxi_partners`. **Writes:** `seller_wallets`, `wallet_transactions`, `marshal_wallet`, `marshal_profiles`, `driver_wallets`, `driver_profiles`, `driver_marshal_transactions`, `association_earnings`, `platform_revenue`, `platform_wallet`, `orders`.
- **Current allocation with no driver and no marshal:** marshal fee 0, driver fee 0, platform 10%, **seller 90%** (from `private.compute_*` helpers, read this pass). Unassigned legs are **given to the seller**, not dropped.
- **Payment check:** none. **Dispute check:** none (relies on caller). **Duplicate release:** refuses unless escrow is `holding`.
- **Audit:** ledger rows only. No record of the basis for release.
- **Defect:** `marshal_wallet` is updated at `id = 1` regardless of which marshal earned it. `platform_wallet` is updated at `id = 1` with no check that a row was matched.

### 4.3 `_apply_route_payout(bigint)`

Not re-read this pass. From Phase 5: requires escrow `holding`, 90/10 on product subtotal, association share from the platform's 10%, credits driver and marshal shares, adds card fee to `processing_reserve`. EXECUTE: service_role yes (**Confirmed**). Payment check: none (**Confirmed** in Phase 5). Body details **Unresolved** for this pass.

### 4.4 `confirm_delivery(bigint, text)`

- **EXECUTE:** authenticated **yes**.
- **Checks:** `auth.uid()` not null; idempotency key unique (duplicate raises); order is the caller's, `delivered`, `holding`, row-locked.
- **Writes:** `idempotency_keys`, `orders`; calls payout.
- **Payment check:** none. **Audit:** none of its own.

### 4.5 `complete_order(bigint, text)`

- **EXECUTE:** service_role only.
- **Checks:** idempotency key; status `paid` or `delivered`, escrow `holding`. **No caller identity check.**
- **Payment check:** none, although `paid` is an accepted status. **Audit:** none.

### 4.6 `resolve_dispute(bigint, text, text, text)`

- **EXECUTE:** service_role only. **No admin check in the body.**
- **Checks:** outcome is one of two values; idempotency key; dispute row has status **`open`** (row-locked).
- **Release branch:** sets order to `holding` + `delivered`, calls payout, sets `completed`. Note the payout would then **fail its own dispute check**, because the dispute row is still `open` at that point and is only marked `resolved` afterwards. **Inferred: the release branch cannot succeed as written.** Not tested.
- **Refund branch:** marks order `refunded`. No wallet change. Comment says cash refund happens at the payment provider.
- **Consequence for escalated disputes:** a dispute that has been escalated by the sweep **cannot be resolved by this function**. There is no function path out of `escalated`.

### 4.7 `refund_order(bigint, text)`

- **EXECUTE:** service_role only.
- **Checks:** idempotency key; order `completed` + `released`; seller available balance covers the reversal.
- **Writes:** `seller_wallets`, `wallet_transactions`, `platform_wallet`, `platform_revenue` (negative row), `marshal_wallet`, `driver_wallets`, `orders`.
- **Defect (SEC-41):** it reverses a fixed 80/10/5/5 split of `total_amount`, and takes unassigned driver and marshal legs back **from the platform wallet**. The current payout gives unassigned legs to the **seller** (90%). A refund of an order paid out under current rules would debit the seller 80% and the platform 20%, while the seller received 90% and the platform 10%. The route payout uses a different basis again (product subtotal). Refund and payout do not mirror each other.
- **Audit:** ledger rows only.

### 4.8 `private.auto_release_escrow()`

- **EXECUTE:** postgres only.
- **Selects:** `delivered`, `holding`, not buyer-confirmed, `delivered_at` older than 72h 30min, no dispute in open, under_review or escalated. Row lock with SKIP LOCKED.
- **Per order:** payout, set `completed` and `buyer_confirmed = true`, audit `auto_release`. On error: audit `auto_release_failed`, continue.
- **Payment check:** none. **Test-order filter:** none.

### 4.9 `private.run_background_sweeps()` and children

- Calls six sweeps, each wrapped so that **any error is swallowed silently** (`EXCEPTION WHEN OTHERS THEN NULL`). A broken monitor produces no signal (SEC-42).
- `sweep_overdue_disputes`: `open` or `under_review` past SLA → `escalated`, audit `dispute_sla_breached`. Never resolves or closes.
- `detect_escrow_anomalies`: flags four inconsistent states, including `auto_release_overdue` at 96h. Writes audit rows only.
- `sweep_ledger_imbalance`: reads `v_ledger_imbalance_audit`, which **excludes test orders** and only looks at `completed` orders. Queues an email to active admins.
- `sweep_wallet_integrity`: section 6.
- No payout. No dispute closure.

### 4.10 `private.auto_cancel_undispatched()`

- Returns immediately when `payments_live` is true. Otherwise cancels `pending` + `holding` orders older than 48h with an unassigned delivery, through `private._cancel_before_collection` (updates `orders` and `deliveries`; writes no wallet; body not fully read, **Unresolved**).
- Not a payout route. It is the only reviewed function that reads `payments_live`, and it uses it to cancel, not to protect money.

### 4.11 Supporting functions

- `raise_dispute`: authenticated; caller must be buyer or seller of the order; order must be `holding`; inserts dispute `open`, sets order `disputed` / `disputed`; audit `dispute_raised`.
- `mark_delivered`: authenticated; assigned driver only; needs `in_transit` and a proof photo; sets `delivered`.
- `create_order_v2`: authenticated; inserts with status `pending`, `is_test_order = false`, escrow left to the default (`holding`).
- `create_order` (legacy): service role only; with `p_is_test` it creates the order already `delivered` and marks the delivery delivered. This is how delivered orders with no driver exist.
- `admin_generate_test_order`, `admin_approve`, `admin_nominate`: authenticated, each begins with `is_admin()`. `is_admin()` reads `admins` for an active row. Two admins are active.

### 4.12 Routes that create, alter or remove payout preconditions

| Precondition       | Created by                                                             | Removed by                                                                                              |
| ------------------ | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------- |
| Escrow `holding`   | Column default at every order insert; `resolve_dispute` release branch | Payout (→ `released`); `raise_dispute` (→ `disputed`); cancel paths                                     |
| Status `delivered` | `mark_delivered` (driver); legacy test `create_order`                  | Payout callers (→ `completed`); `raise_dispute`                                                         |
| No open dispute    | Default                                                                | **Any signed-in user inserting a dispute row for any order** (direct insert policy, no ownership check) |

The last row is a denial-of-payout route, not a route to credits (SEC-43).

---

## 5. R5 platform variance: identified

**Result: the R5.00 is the unassigned driver and marshal legs of order 81, credited to the platform wallet without a `platform_revenue` row, by the payout function version that was live on 21 July 2026.**

Evidence chain:

1. Migration `20260721145717 seed_and_backfill_platform_wallet` (**Confirmed**, statement read): inserts `platform_wallet` id 1 with balance = sum of `platform_revenue`, `ON CONFLICT DO NOTHING`.
2. `platform_wallet.created_at` is `2026-07-21 14:57:17` (**Confirmed**), the same second. The insert took effect, so no row with id 1 existed just before it.
3. Six orders had been released on 20 July. Their platform revenue rows (ids 18 to 23) sum to 108.00. Seed balance = **108.00** (**Inferred** from 1 to 3; the six rows are the only ones dated before the seed).
4. Migration `20260721162233 wire_ledger_into_payout_function` (**Confirmed**, body read) was the live payout at 18:58 that day. It writes `platform_revenue` and `platform_wallet` for the platform fee, and has two `ELSE` branches: with no marshal, `platform_wallet += marshal_fee`; with no driver, `platform_wallet += driver_fee`. Neither branch writes `platform_revenue`.
5. Order 81 (total 50.00, no driver, no marshal) was released 2026-07-21 18:58 (**Confirmed**). Platform fee 5.00 to both ledgers. Marshal leg 2.50 and driver leg 2.50 to the wallet only.
6. 108.00 + 5.00 + 2.50 + 2.50 = **118.00**, the stored balance. `platform_revenue` total = 113.00. Variance 5.00. Exact match.
7. Migration `20260726131542 fix_platform_revenue_reconciliation_gap` (**Confirmed**, comment read) describes this defect in its own words: the wallet "was ALSO credited the driver fee when no driver was assigned".

Confidence: high. The one inferred step is the seed amount.

### 5.1 What this means for the R113

The earlier explanation (legs "dropped" by the function) described the wrong code version. Corrected account:

| Portion                                | Amount | What happened                                                                                                                                                                                                             | Status                                                                                                                                                                                                                             |
| -------------------------------------- | -----: | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Order 81 unassigned legs               |   5.00 | Credited to `platform_wallet`, no revenue row. This **is** the R5 variance.                                                                                                                                               | Confirmed (above)                                                                                                                                                                                                                  |
| Six orders of 20 July, unassigned legs | 108.00 | The payout of that date sent unassigned legs to `platform_wallet` id 1. That row did not exist on 20 July (step 2), so the `UPDATE ... WHERE id = 1` matched nothing and raised no error. The amount was written nowhere. | **Inferred.** The 20 July function version was read only in part (the 3 July version contains the comment "Marshal leg (or platform if unassigned"). Why the wallet row seeded on 3 July was missing by 20 July is **Unresolved**. |
| Total                                  | 113.00 |                                                                                                                                                                                                                           |                                                                                                                                                                                                                                    |

So: 1,130.00 = 904.00 seller + 113.00 platform revenue + 5.00 platform wallet without a revenue row + 108.00 written nowhere.

No balancing entry has been made. None should be made until the owner decides how test-era records are treated.

---

## 6. Integrity monitor review

Objects (**Confirmed**, definitions read): view `private.v_wallet_integrity`, view `public.v_wallet_integrity_flagged`, function `private.sweep_wallet_integrity()`, created by migration `20260726181433`.

### 6.1 Why it reports seller ledger 0 against 904

The seller branch computes:

```sql
COALESCE(
  (SELECT sum(amount) FILTER (WHERE type = 'credit')
        - sum(amount) FILTER (WHERE type = 'debit')
     FROM wallet_transactions wt WHERE wt.seller_id = sw.seller_id), 0)
```

When a wallet has credits and **no debit rows**, the second `sum` is NULL. `904 − NULL` is NULL, and the outer `COALESCE` turns it into 0. **This is a NULL-arithmetic bug.** The view still returns seller ledger 0, variance 904.00, today (**Confirmed** by reading the view's current output).

My earlier inference (a `wallet_type` filter) was wrong.

| Question                                    | Answer                                                                                                                                                                                                                                                                                                                                                                                                                                   |
| ------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Filters on `wallet_type`?                   | No                                                                                                                                                                                                                                                                                                                                                                                                                                       |
| Excludes NULL values?                       | Not by filter. NULL arithmetic zeroes the whole result when either side has no rows                                                                                                                                                                                                                                                                                                                                                      |
| Reads the correct ledger table?             | Yes for seller (`wallet_transactions`), driver and marshal (`driver_marshal_transactions`), platform (`platform_revenue`)                                                                                                                                                                                                                                                                                                                |
| Includes all transaction types?             | Only `credit` and `debit`. Any other `type` value is ignored                                                                                                                                                                                                                                                                                                                                                                             |
| Excludes test orders correctly?             | It does not exclude them, which is right for a balance check. The separate order-level check (`v_ledger_imbalance_audit`) excludes test orders, so the R113 gap on seven test orders was never flagged                                                                                                                                                                                                                                   |
| Reconciles balances against actual history? | Partly. Seller: compares `available_balance` only, ignoring `pending_balance` and `reserve_balance`. `approve_withdrawal` writes a second debit row while reducing `pending_balance`, so an approved withdrawal would create a false variance. Platform: ignores `processing_reserve` and any wallet change without a revenue row (which is how it correctly caught the R5). Marshal: compares the single pooled row to all marshal rows |

### 6.2 Other weaknesses

- The sweep logs a variance once per distinct value, then stays silent. A persistent mismatch produces one row in total (2026-07-26) and no reminder.
- Alerts go by email. Email has failed every day since at least 2026-08-19 (`RESEND_API_KEY is not set`, 167 failures recorded; 55 earlier give-ups). **The monitors are alerting no one.**
- Sweep errors are swallowed (section 4.9).

### 6.3 Proposed corrections (not applied)

1. `COALESCE` each sum separately: `COALESCE(sum(...) FILTER (credit), 0) − COALESCE(sum(...) FILTER (debit), 0)`.
2. Compare against `available_balance + pending_balance` for sellers, or model withdrawals in the ledger consistently.
3. Reject or count unknown `type` values.
4. Re-alert on unresolved variances on a fixed cadence, and require an acknowledgement.
5. Replace `EXCEPTION WHEN OTHERS THEN NULL` with an audit row.
6. Fix email delivery, or route alerts to a channel that works.

---

## 7. Payment evidence architecture review

Reviewed: `remediation/PHASE5B-guard-v2-DRAFT.sql`. Nothing was created or changed.

| Area                          | Draft v2                                  | Finding                                                                                                                       | Required change                                                                                                                                                                                   |
| ----------------------------- | ----------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Ownership and write path      | "Service role only" by RLS                | `service_role` bypasses RLS and is held by every Edge Function. Any function with the key could write evidence                | Single SECURITY DEFINER writer `record_payment_evidence(...)`, EXECUTE granted to one dedicated role used only by the payment webhook. No direct table privilege for `service_role` beyond SELECT |
| Default privileges            | Explicit revoke included                  | New `public` tables are granted to `anon` and `authenticated` by default (section 1.3). The revoke is essential, not optional | Keep revoke and RLS in the same migration; verify with `has_table_privilege`                                                                                                                      |
| Foreign keys                  | `order_id → orders(id)`                   | Sufficient for the link                                                                                                       | Add `ON DELETE RESTRICT` so a paid order cannot be deleted                                                                                                                                        |
| Buyer and order consistency   | Not checked                               | A payment for order A by a different payer could be attached                                                                  | Store payer reference and the order id the provider echoed in metadata; writer rejects a mismatch with `orders.buyer_id`                                                                          |
| Unique payment reference      | `provider_ref` unique                     | Good                                                                                                                          | Also store the provider event id, unique, for webhook replay                                                                                                                                      |
| Amount and currency           | cents vs `round(total_amount*100)`, `ZAR` | Good                                                                                                                          | Store the provider's amount as received; never derive it from a request body field the client can set                                                                                             |
| Idempotency                   | one row per order                         | Blocks a legitimate retry after a failed attempt                                                                              | Keep failed attempts in a separate attempts table; one **verified** row per order via partial unique index                                                                                        |
| Webhook verification evidence | `event_hash`                              | Hash alone does not show the signature was checked                                                                            | Store signature-verified flag, verification time, and key identifier (not the key)                                                                                                                |
| Reconciliation status         | Absent                                    | No settlement or bank tie-out                                                                                                 | Add lifecycle: `verified` → `settled` → `reconciled`, plus `refunded`, `charged_back`                                                                                                             |
| RLS and grants                | RLS on, no policies                       | Good                                                                                                                          | Force RLS on this table                                                                                                                                                                           |
| Service-role bypass           | Not addressed                             | R5b: service role can call leaf payout functions directly, skipping any guard in `_apply_order_payout`                        | Put the guard in both leaf functions, and revoke `service_role` EXECUTE on the leaves                                                                                                             |
| Refund and dispute            | Dispute check kept                        | Guard accepts a row whose payment was later refunded, because status is constrained to `verified` only                        | Guard requires status in (`verified`, `settled`, `reconciled`) and no refund or chargeback; `refund_order` must mirror the actual payout rows, not recompute a fixed split                        |
| Immutability                  | Absent                                    | Evidence could be edited                                                                                                      | Append-only: no UPDATE or DELETE except through the writer; status changes recorded as events                                                                                                     |
| Escrow default                | Absent                                    | `holding` is the default at order creation, so "holding" means nothing                                                        | New initial state (for example `awaiting_payment`); escrow becomes `holding` only when the evidence writer records a verified payment in the same transaction. Requires a check-constraint change |
| Test orders                   | Absent                                    | Test orders flow through the same payout                                                                                      | Guard refuses `is_test_order = true` on production                                                                                                                                                |

### 7.1 Missing-recipient design: resolved position

Facts: current code gives unassigned driver and marshal legs to the **seller** (90%). The July code sent them to the platform wallet. `refund_order` assumes they went to the platform. `orders.seller_earnings` (set at insert by `calculate_commission`) records 80%. Four parts of the system hold three different answers, and none was approved.

Resolution proposed (decision needed, nothing changed):

1. Every payout writes one allocation row **per leg**, always, including zero-value and unassigned legs. States as defined in `PHASE5B-GUARD-AND-TESTS.md` section 5.
2. A delivered order with **no driver** cannot be released at all. `mark_delivered` requires a driver, so such an order can only come from a test path. The guard refuses it.
3. A leg with no marshal is recorded as `pending recipient` in a named suspense balance, never added to the seller or the platform silently. Release of the seller and platform legs may proceed only if the owner approves that rule; otherwise the order waits.
4. `refund_order` reverses the recorded allocation rows.
5. `calculate_commission`, the payout and the refund read the split from one place.

---

## 8. Order 96 and dispute 9 (updated)

- Order 96 is `delivered` / `holding`. `raise_dispute` would have set it to `disputed` / `disputed`. It did not, so dispute 9 was **inserted directly** (the insert policy allows it), not raised through the function (**Inferred**).
- Dispute 9 is `escalated`. `resolve_dispute` accepts only `open`. The sweep only escalates. **No function can close or resolve dispute 9.** Only SQL run as `postgres` or `service_role` can change it (**Confirmed** from the definitions read).
- While dispute 9 stays in `escalated`, R1, R2, R3, R4a and R5a refuse order 96. **R5b does not check disputes**: a service-role call to `_apply_order_payout_legacy(96)` would pay it out today.
- If released under current code, order 96 would credit the seller **45.00** and the platform **5.00** (not 40 / 5 / 5 as stated earlier).
- Neither record was changed.

---

## 9. Corrections to earlier Phase 5B documents

| Earlier statement                                                   | Correction                                                                                                                                                                                                         |
| ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| "R113 is dropped because the legacy function has no else branch"    | True of today's code path only in form; today the legs go to the seller. The July code sent them to the platform wallet. 108.00 was lost because the wallet row did not exist; 5.00 is the R5 variance. Section 5. |
| "R5 is unexplained"                                                 | Identified. Section 5.                                                                                                                                                                                             |
| "Monitor probably filters on `wallet_type`"                         | Wrong. NULL-arithmetic bug. Section 6.                                                                                                                                                                             |
| "Order 96 would credit seller 40, platform 5, driver and marshal 5" | Under current code: seller 45, platform 5. Section 8.                                                                                                                                                              |
| "If dispute 9 is closed by any route, the cron releases order 96"   | Still true, but no function route can close it. Only privileged SQL. Section 8.                                                                                                                                    |
| "Bypasses B1 to B4 unverified"                                      | Closed for app roles. Section 1.4.                                                                                                                                                                                 |
| "R1 to R4b are the routes"                                          | Add R5a, R5b, R6. Section 2.                                                                                                                                                                                       |
| "`resolve_dispute` release branch pays out"                         | It appears unable to succeed, because its own payout call hits the open-dispute check. Inferred, untested. Section 4.6.                                                                                            |
| "Cron owner not recorded"                                           | `postgres`. Section 3.                                                                                                                                                                                             |

---

## 10. Remaining unknowns

1. External admin console: source, role and calls. Still required (Decision 1).
2. Why the `platform_wallet` row seeded on 3 July was absent by 20 July.
3. Full bodies not read: `_apply_route_payout` (this pass), `admin_force_cancel`, `private._cancel_before_collection`, `set_delivery_address`, `guard_profile_privileged_fields`, `private.invoke_whatsapp_dispatcher`, `calculate_commission` (this pass).
4. Whether `resolve_dispute`'s release branch really fails. Needs a staging test.
5. Which path produced the seven July releases. The API log tool covers 24 hours per query; July is out of practical reach.
6. Whether staging matches production on every item here. Staging was not read this pass.
7. Whether `profiles.phone` is unique. R1 and the driver WhatsApp path identify people by phone, and users can edit their own phone.
8. Production Edge Function sources are not in the repository, so their behaviour cannot be diffed or reviewed in version control.
9. Storage policies: not part of this pass.

---

## 11. New register entries

SEC-39 to SEC-46 are recorded in `SECURITY-REGISTER.md`.

Nothing in this document authorises a production change, payment activation, merge or deployment.
