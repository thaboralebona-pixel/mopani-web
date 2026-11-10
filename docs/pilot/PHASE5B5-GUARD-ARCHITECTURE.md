# Phase 5B-5: payment evidence and payout guard architecture

Date: 2026-11-10. **Design for review. Nothing here is implemented.** The companion SQL (`remediation/PHASE5B5-payment-guard-DRAFT.sql`) is a draft that has not been executed, parsed or tested on any database. Decision 44: authoring approved; applying it anywhere is not.

Supersedes `PHASE5B4-GUARD-ARCHITECTURE.md` and `remediation/PHASE5B-guard-v2-DRAFT.sql` (kept for history).

Objective: no wallet credit, allocation or release can exist for an order without verified, order-specific payment evidence, on any route.

---

## 1. What does not count as payment

None of these is evidence, alone or together: a browser redirect; a status sent by the client; a webhook payload, even with a valid signature, before the provider has been asked directly; `payments_live = true`; an order in `holding`; a wallet balance; a payment row inserted by hand or by a role other than the trusted writer.

---

## 2. Platform facts that constrain the design (**confirmed** 2026-11-10)

| Fact                                                                                  | Source                                                              | Consequence                                                                                                         |
| ------------------------------------------------------------------------------------- | ------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `service_role` bypasses RLS                                                           | `pg_roles`                                                          | RLS cannot protect evidence from Edge Functions. Table privileges still apply to `service_role` and must be revoked |
| Every Edge Function receives `SUPABASE_DB_URL`, a direct database URL, by default     | [Supabase docs](https://supabase.com/docs/guides/functions/secrets) | Any function's code could connect outside the API roles. In-database controls cannot stop this                      |
| Custom function secrets are set at project level                                      | Same page (per-function scoping is not documented there)            | A secret stored for one function should be assumed readable by all functions in the project                         |
| `service_role` can read `vault.decrypted_secrets`                                     | privilege query                                                     | A provider key kept in the database vault is readable by every Edge Function                                        |
| New `public` tables are granted to `anon`, `authenticated`, `service_role` by default | `pg_default_acl`                                                    | Every new table must revoke in the same migration                                                                   |
| `postgres` owns everything and bypasses RLS; `supabase_admin` is superuser            | `pg_roles`                                                          | Privileged SQL can always write. Detective controls are required                                                    |
| The `http` extension is available, not installed                                      | `pg_available_extensions`                                           | Database-side provider calls are possible if chosen                                                                 |

---

## 3. Trusted payment path (D1)

```
buyer app ──(1) create intent──▶ database: pay.create_payment_intent(order)
                                   returns reference + amount (from the order row)
buyer ──(2) pays at Paystack using that reference
Paystack ──(3) webhook──▶ payment verifier (trusted component)
   (4) verify HMAC signature over the RAW body with the provider signing secret
   (5) call Paystack's verify-transaction API for that reference (server to server)
   (6) call database: pay.record_verified_payment(...)  as role payment_writer
database (7) checks everything again against its own rows, then in ONE transaction:
            evidence row + intent verified + order awaiting_payment → holding + audit event
```

Step by step:

1. **Intent.** Only the database issues a payment reference, for one order, with the amount in integer cents taken from `orders.total_amount`. One open intent per order.
2. **Signature.** The verifier computes the HMAC over the raw request bytes and compares in constant time. A failure is logged as an event and stops there.
3. **Provider verification.** The verifier asks Paystack directly for the transaction. The webhook body is treated as a hint; the verify response is the fact. (Header name, HMAC algorithm and endpoint to be taken from Paystack's current documentation at build time; not asserted here.)
4. **Database re-check.** The database function does not trust the verifier's conclusion. It compares, against its own rows: reference equals the order's open intent; amount in cents equals the intent; currency is `ZAR`; provider status is success; the order and buyer named in the provider metadata equal the intent's order and that order's `buyer_id`; the provider transaction id and event id have not been seen.
5. **Atomic.** Evidence, intent status, escrow transition and audit event commit together or not at all.

### 3.1 What the evidence record holds

Provider name; provider transaction id; provider reference; provider event id; order id; buyer id; amount in cents; currency; provider status; provider paid-at time; **SHA-256 of the raw webhook body**; **SHA-256 of the verify response**; signing key identifier (not the key); verifier build identifier; verification time; outcome.

A flag such as "signature verified = true" is not the evidence. The evidence is the set of provider identifiers and hashes that lets anyone re-fetch the transaction from Paystack later and prove the row matches. A daily reconciliation job does exactly that (section 10). Raw bodies are not stored in the database; only hashes.

---

## 4. Dedicated evidence writer (D2)

### 4.1 The problem stated honestly

Inside one Supabase project there is no secret that only one Edge Function can read, and every function can reach the database directly. So "a custom role that only the payment function uses", **if its credential lives in the same project**, is separation by convention, not by enforcement.

### 4.2 Options

| Option                                         | How the writer authenticates                                                                                                                                                                                                                                                                                                  | Strength                                                                      | Cost                                                                                                                |
| ---------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------- |
| **A. Separate payments project (recommended)** | The verifier runs in its **own** Supabase project (or any small separate service). That project alone holds the provider keys and the password of a database role `payment_writer` in the main database. It connects to the main database with a normal Postgres connection over TLS (connection pooler), as `payment_writer` | Main-project functions never hold the credential. Real separation of identity | A second project to run; one more secret for the owner to manage                                                    |
| B. Database-side verification                  | The database function itself calls the provider (`http` extension) with a key from the vault                                                                                                                                                                                                                                  | Evidence does not depend on who called                                        | The provider secret key becomes readable by `service_role` (vault). Synchronous outbound calls inside a transaction |
| C. Custom JWT role in the same project         | A long-lived token with `role = payment_writer`, used through the API                                                                                                                                                                                                                                                         | Weak: the token is a project secret any function can read                     | Low                                                                                                                 |

**Recommendation: A**, with the reconciliation job as the detective control. C is not acceptable as the control. B may be added later as a second check if the key exposure is accepted.

### 4.3 How role `payment_writer` works (option A)

- `create role payment_writer login noinherit nobypassrls` with a low connection limit. **No password in any migration or file.** The owner sets it once, out of band, and stores it only in the payments project.
- Member of nothing. Nothing is a member of it. `authenticator` is **not** granted this role, so the API cannot switch to it.
- Privileges: `USAGE` on schema `pay`; `EXECUTE` on exactly two functions (`pay.record_provider_event`, `pay.record_verified_payment`). **No table privilege at all.**
- Both functions are SECURITY DEFINER, owned by `postgres`, with a pinned `search_path`. They check `session_user = 'payment_writer'` as well, so a call arriving through another role's session is refused even if someone grants EXECUTE by mistake.
- Schema `pay` is **not** exposed through the API (not in the exposed schemas list), so `service_role` cannot reach these functions over REST even if granted.

### 4.4 Ownership, RLS, privileges

| Object                                                     | Owner    | RLS                    | `anon` / `authenticated` | `service_role`              | `payment_writer` |
| ---------------------------------------------------------- | -------- | ---------------------- | ------------------------ | --------------------------- | ---------------- |
| Schema `pay`                                               | postgres | n/a                    | no usage                 | usage (read functions only) | usage            |
| Evidence, events, intents, legs, settlements, refunds      | postgres | enabled **and forced** | none                     | **SELECT only**             | none             |
| `pay.record_verified_payment`, `pay.record_provider_event` | postgres | n/a                    | none                     | **none**                    | execute          |
| `pay.create_payment_intent`                                | postgres | n/a                    | execute (own order only) | none                        | none             |
| Payout functions                                           | postgres | n/a                    | none                     | none                        | none             |

Default privileges are changed **in the same migration**, for objects `postgres` creates in schema `pay`: nothing to `anon`, `authenticated`, `service_role`, `PUBLIC`. Each table also carries an explicit `revoke all`, because defaults set by `supabase_admin` cannot be relied on.

### 4.5 Can evidence be forged or replayed?

| Attempt                                                    | Outcome                                                                                                                                                                                                                                              |
| ---------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Edge Function inserts an evidence row with the service key | No INSERT privilege; schema not exposed                                                                                                                                                                                                              |
| Edge Function calls the writer function                    | No EXECUTE; `session_user` check fails                                                                                                                                                                                                               |
| Replay of an old webhook                                   | Event id unique; transaction id unique; intent already closed                                                                                                                                                                                        |
| Evidence from order A presented for order B                | Reference belongs to A's intent; mismatch refused                                                                                                                                                                                                    |
| Correct reference, smaller amount                          | Cents compared with the intent; refused                                                                                                                                                                                                              |
| Verifier compromised                                       | It can only submit what the database then checks against its own intent. It cannot change the amount or order. It could submit a false "success": caught by daily reconciliation against the provider, and limited to orders with an open intent     |
| Someone with `postgres` access                             | Not preventable in the database. Mitigations: restrict dashboard access, rotate the database password, forbid `SUPABASE_DB_URL` in function code (checked in review), reconciliation, alerting on evidence rows whose writer is not `payment_writer` |

---

## 5. Separate order, payment and escrow state (D3)

| Stage                            | Order status                 | Escrow status                        | Payment intent | Who may cause the transition                                        |
| -------------------------------- | ---------------------------- | ------------------------------------ | -------------- | ------------------------------------------------------------------- |
| Order placed                     | `pending`                    | **`awaiting_payment`** (new default) | none or `open` | Buyer, through `create_order_v2`                                    |
| Payment verified                 | `paid`                       | `holding`                            | `verified`     | **Only** `pay.record_verified_payment`, in the evidence transaction |
| Collected, in transit, delivered | delivery states              | `holding`                            | `verified`     | Seller, marshal, driver functions. They cannot create evidence      |
| Receipt recorded                 | `delivered` + receipt record | `holding`                            | `verified`     | Buyer statement (app or WhatsApp token). **Not a payment event**    |
| Internal allocation              | `completed`                  | `released`                           | `verified`     | Guarded release only                                                |
| External settlement              | `completed`                  | `released`                           | `settled`      | Settlement record from bank or provider                             |
| Reconciled                       | unchanged                    | unchanged                            | `reconciled`   | Reconciliation job                                                  |

Rules:

- `holding` cannot be reached without an evidence row. The column default changes to `awaiting_payment` and a constraint trigger rejects `holding` unless evidence exists for the order.
- Delivery confirmation records a fact about goods. It moves no money and creates no evidence.
- `released` means the internal ledger was allocated. It is never shown as "paid".
- Functions that today test `escrow_status = 'holding'` for unpaid orders (`auto_cancel_undispatched`, `private._cancel_before_collection`, `admin_force_cancel`, `raise_dispute`) must be updated to accept `awaiting_payment`. Listed in the SQL draft as required follow-on changes.

---

## 6. Every payout route is guarded (D4)

One function, `pay.assert_release_allowed(order_id)`, is the **first statement** in each credit writer and in the parent:

| Function                                                    | Change                                                                                                                                          | EXECUTE after change                   |
| ----------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------- |
| `_apply_route_payout`                                       | Guard first; then allocation legs; then wallet writes with row-count checks                                                                     | postgres only                          |
| `_apply_order_payout_legacy`                                | **Disabled**: body raises. Non-route orders cannot be released. (Its split was never approved and gives unassigned legs to the seller)          | postgres only                          |
| `_apply_order_payout`                                       | Guard, dispute check, route orders only                                                                                                         | postgres only                          |
| `confirm_delivery`, `confirm_order_delivery_by_phone`       | Record receipt only. May request release, which the guard decides                                                                               | authenticated (own order) / token path |
| `complete_order`                                            | Retired (its only caller was the Stripe webhook)                                                                                                | none                                   |
| `resolve_dispute`, `admin_resolve_dispute`                  | Admin check in the body; accepts escalated disputes; release branch goes through the guard; refund branch goes through the provider refund flow | admins through the wrapper only        |
| `private.auto_release_escrow`, `public.auto_release_escrow` | Wrapper dropped. Job restored only after the guard is live; skips test orders                                                                   | postgres (cron)                        |

`pay.assert_release_allowed` raises unless all hold:

1. `payments_live` is true. (A switch. Never sufficient alone.)
2. Order locked; not a test order; escrow is `holding`.
3. Exactly one evidence row for the order, outcome verified, not refunded or charged back, amount in cents equal to the order total, currency `ZAR`.
4. No dispute in `open`, `under_review` or `escalated`.
5. A driver is assigned.
6. No allocation legs exist yet for the order (duplicate release).

A leaf called directly still runs the guard, because the guard is inside the leaf.

---

## 7. Allocation completeness and suspense (D5)

- One row in `pay.allocation_legs` **per intended leg, always**: `seller`, `platform`, `driver`, `marshal`, `association`, `card_fee`. Unique on (order, leg).
- Amounts are integer cents. The legs must sum to the order total or the transaction rolls back.
- **Missing driver:** release is refused. No legs are written.
- **Missing marshal:** the marshal leg is written with recipient kind `suspense` and state `pending_recipient`. Its amount goes to a named suspense balance. It is **not** added to the seller, the platform or the pooled marshal wallet, and it is **not** platform revenue. The seller, platform and driver legs proceed (owner rule to confirm: release with a pending marshal leg is allowed; release with no driver is not).
- **Zero-value leg:** the leg row is still written with amount 0 and state `not_applicable`, with a reason. No wallet transaction row is written for it, so existing ledger tables with positive-amount expectations are not violated. Completeness is checked on legs, not on wallet rows.
- Every wallet update must report exactly one row changed. Zero rows raises. (This is the check that would have prevented the R108 written nowhere in July.)
- Leg states, append-only in `pay.allocation_events`: `allocated`, `pending_recipient`, `not_applicable`, `released_internal`, `submitted_external`, `externally_paid`, `failed`, `reversed`, `reconciled`.
- A suspense leg is resolved only by an admin-approved assignment event naming the recipient. It never expires into revenue.

---

## 8. Refunds and chargebacks (D6)

Principle: a reversal copies the **recorded** legs with opposite sign. No percentage is recalculated. The current `refund_order` (fixed 80/10/5/5) is retired.

| Case                               | Behaviour                                                                                                                                                                                                                |
| ---------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| Full refund before release         | Evidence event `refunded`; order → `refunded`; no legs exist, nothing to reverse                                                                                                                                         |
| Full refund after internal release | One reversal row per original leg, same cents, linked by `reverses_leg_id`. Wallets debited with row-count checks. If a wallet lacks the balance, the refund stops in state `needs_recovery`; nothing is forced negative |
| Partial refund                     | Amount in cents allocated across legs in proportion to the **recorded** leg amounts, largest-remainder rounding so the parts sum exactly. Recorded per leg                                                               |
| Failed refund at provider          | Refund row stays `failed`; no ledger reversal is written until the provider confirms                                                                                                                                     |
| Repeated refund event              | Provider refund id unique. Second delivery is a no-op                                                                                                                                                                    |
| Chargeback                         | Evidence event `charged_back`; release blocked from that moment; if already released, legs are flagged and a recovery record opened. No automatic external payment afterwards                                            |
| Leg already externally paid        | Reversal is recorded against the recipient as a receivable in `needs_recovery`. The platform does not pretend the money returned                                                                                         |
| History                            | All of the above are new rows. No evidence, leg or event row is updated or deleted                                                                                                                                       |

---

## 9. Vocabulary (internal release is not payment)

| State                         | May be shown as               | Never shown as     |
| ----------------------------- | ----------------------------- | ------------------ |
| No evidence                   | "Awaiting payment"            | "Paid", "Held"     |
| Evidence verified             | "Payment received"            | "Paid out"         |
| Legs released internally      | "Earnings recorded"           | "Paid", "Credited" |
| External settlement confirmed | "Paid to you", with reference | n/a                |

---

## 10. One-charge and idempotency invariants (D7)

| Risk                                   | Control                                                                                                                                    |
| -------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------ |
| Duplicate successful provider event    | Unique provider event id                                                                                                                   |
| Duplicate payment reference            | Unique reference; references issued only by the database                                                                                   |
| Duplicate charge for one order         | One open intent per order (partial unique index). A new intent is refused while one is `open`, `verified` or `reconciling`                 |
| Payment in reconciliation              | Intent state `reconciling` blocks a new intent. The buyer is told to wait, never to pay again                                              |
| Duplicate internal payout              | Guard condition 6; unique (order, leg); escrow must be `holding` under row lock                                                            |
| Duplicate refund                       | Unique provider refund id; reversal unique per original leg and refund                                                                     |
| Duplicate external transfer            | Settlement row with a unique idempotency key created **before** the transfer request; the provider call carries the key; a retry reuses it |
| Evidence reused for another order      | Reference bound to one intent, one order                                                                                                   |
| Replay of an old WhatsApp confirmation | Single-use token and unique message id (see WhatsApp draft, section 4)                                                                     |

Daily reconciliation (detective): for every evidence row, re-fetch the transaction from the provider and compare amount, currency, status and reference; compare provider settlement reports with settlements; alert on any evidence row not written by `payment_writer`, any order in `holding` without evidence, any released order without a full set of legs, and any wallet balance that differs from its ledger.

---

## 11. Database ownership and privilege safety (D8)

- All new objects live in schema `pay`, owned by `postgres`, not exposed to the API.
- The migration begins by setting default privileges for that schema (no app or service role), and ends with read-only assertions that fail the migration if any app role holds a privilege on a `pay` object.
- RLS is enabled and forced on every `pay` table, as a second layer. Privileges are the first layer, because RLS does not bind `service_role` or `postgres`.
- Unused table privileges held by `authenticated` on existing financial tables are revoked (SEC-39).
- EXECUTE on every payout entry is limited to the owner, as in the containment draft.
- pgTAP is not installed in an exposed schema.
- Known limit, stated plainly: none of this restrains `postgres`, `supabase_admin` or code using `SUPABASE_DB_URL`. Those are organisational controls plus reconciliation.

---

## 12. Monitoring corrections (Workstream G, proposals only)

| Weakness                                                                              | Proposed correction                                                                                                             |
| ------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------- |
| NULL arithmetic in `private.v_wallet_integrity` (credits minus NULL debits becomes 0) | `COALESCE` each side separately                                                                                                 |
| Wallet with debits and no credits                                                     | Same fix covers it                                                                                                              |
| Compares `available_balance` only                                                     | Compare available + pending + reserve with the ledger, or ledger each bucket                                                    |
| Unknown transaction types ignored                                                     | Count and flag any `type` outside the known set                                                                                 |
| Each variance logged once, then silence                                               | Re-alert daily until acknowledged by a named admin                                                                              |
| Sweep errors swallowed (`EXCEPTION WHEN OTHERS THEN NULL`)                            | Write a `sweep_error` audit row and count it in the health score                                                                |
| Email alerts failing daily since August                                               | Fix the email key (owner action) and add a second channel; alert on "no alert delivered in 24 hours"                            |
| Order-level check excludes test orders                                                | Keep the exclusion for revenue reports, but run the balance check on all orders, and refuse test orders in payout on production |
| Platform check uses revenue rows only                                                 | Include suspense and processing reserve, each against its own ledger                                                            |

---

## 13. Open questions carried forward

1. Why the platform wallet row was missing before 21 July 2026.
2. The exact payout function body live on 20 July 2026.
3. Which route produced the seven July releases.
4. Why `v_ledger_imbalance_audit` differs between staging and production.
5. Whether the `resolve_dispute` release branch can succeed as written.
6. The external admin console.
7. Paystack specifics (signature header, verify endpoint, refund and chargeback events, test mode) to be confirmed from current documentation at build time.
8. Whether the connection pooler accepts a custom login role in the expected form; to confirm on staging.

Historical amounts stay untouched: R904 seller credits, R113 platform revenue, R5 platform wallet without a revenue row, R108 written nowhere. No balancing entry.
