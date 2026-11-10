# Phase 5B-4: payout guard architecture (v3 design) and test plan

Date: 2026-11-10. **Design document only.** No table, function, role, grant or test has been created or run. It replaces the direction in `remediation/PHASE5B-guard-v2-DRAFT.sql`, whose SQL is not approved.

Objective: it must be impossible for the system to create a wallet credit from an order without verified payment evidence for that order.

---

## 1. Principles

1. **A wallet credit is an internal ledger entry.** It is never described as money received or money paid to a person.
2. **Money received** is proven only by order-specific evidence from the payment provider, written by one trusted path.
3. **Money paid out** to a seller, driver or marshal is proven only by an external settlement record.
4. Every state change is append-only and attributable.
5. Controls sit where the write happens (the leaf functions), not only at the front door.

---

## 2. Owner requirements mapped to design

| #   | Requirement                                     | Design element                                                                                                                                                                                                                      |
| --- | ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| 1   | Guard in both leaf functions                    | One shared check `private.assert_payout_allowed(order_id)` called as the **first statement** of `_apply_route_payout` and `_apply_order_payout_legacy`, and again in `_apply_order_payout`. A leaf called directly is still guarded |
| 2   | Order-specific, authenticated provider evidence | Table `payment_evidence`, one verified row per order, written only by `private.record_payment_evidence(...)` after the webhook has verified the provider signature                                                                  |
| 3   | Amount and currency match trusted values        | Writer and guard both compare provider amount in cents with `round(orders.total_amount * 100)` and currency with `ZAR`. The order total comes from the database, never from the request                                             |
| 4   | Idempotency                                     | Unique provider event id; unique provider reference; one verified row per order (partial unique index); payout allowed only from escrow `holding` under row lock; allocation rows unique per (order, leg)                           |
| 5   | New orders do not start in `holding`            | New initial escrow state `awaiting_payment`, set as the column default and by `create_order_v2`. Only the evidence writer moves an order to `holding`, in the same transaction as the evidence row                                  |
| 6   | Refunds reverse recorded entries                | `refund_order` reads the order's allocation rows and writes equal and opposite rows. No percentage is recalculated                                                                                                                  |
| 7   | Missing recipients go to explicit suspense      | Every leg is a row. A leg with no recipient is `pending_recipient` against a named suspense balance. Nothing is added to the seller or platform silently. An order with no driver cannot be released                                |
| 8   | Internal release is not money received or paid  | Separate states and separate tables for payment received, internal allocation and external settlement (section 4). Message templates use the state names in section 4                                                               |
| 9   | Direct function access restricted               | EXECUTE on leaf functions, parent, wrappers and callers limited to the owner. Evidence written under a dedicated role, not `service_role`. `service_role` has SELECT only on evidence                                               |
| 10  | Append-only audit                               | No UPDATE or DELETE on evidence, allocation or settlement rows; status changes are new event rows. Enforced by privileges and a trigger that rejects updates and deletes                                                            |

Changing the initial state (5) does not close the hole by itself. Requirements 1, 2 and 9 are what stop a credit.

---

## 3. Components (to be specified in SQL in a later, separately approved step)

### 3.1 `payment_evidence`

| Column                                    | Purpose                                                         |
| ----------------------------------------- | --------------------------------------------------------------- |
| `id`                                      | Key                                                             |
| `order_id`                                | FK to `orders`, `ON DELETE RESTRICT`                            |
| `provider`                                | `paystack`                                                      |
| `provider_reference`                      | Unique                                                          |
| `provider_event_id`                       | Unique; replay protection                                       |
| `amount_cents`, `currency`                | As received from the provider                                   |
| `payer_reference`                         | Provider's customer identifier, for buyer consistency           |
| `signature_verified_at`, `signing_key_id` | Proof the signature was checked; never the key itself           |
| `event_hash`                              | Hash of the signed body; the body is not stored                 |
| `status`                                  | `verified`, `settled`, `reconciled`, `refunded`, `charged_back` |
| `created_at`                              | Insert time                                                     |

Rules: RLS enabled **and forced**; no policy for anon or authenticated; table privileges revoked from anon and authenticated in the creating migration (defaults would otherwise grant them); partial unique index on `order_id` where status is not `refunded` or `charged_back`.

### 3.2 `private.record_payment_evidence(...)`

- The only writer. SECURITY DEFINER. EXECUTE granted to one dedicated role (`payment_writer`), used only by the payment webhook function.
- Checks: order exists and is `awaiting_payment`; not a test order; amount and currency match the order; the provider metadata names this order and this buyer; event id not seen before.
- In one transaction: insert evidence, set escrow to `holding`, write an audit event.
- A failed attempt writes to a separate attempts log, not to `payment_evidence`.

### 3.3 `private.assert_payout_allowed(order_id)`

Raises unless **all** hold:

1. `payments_live` is true (a switch, not proof).
2. Order row locked; escrow is `holding`; not a test order.
3. Exactly one evidence row for the order with status `verified`, `settled` or `reconciled`; amount and currency equal the order total.
4. No dispute in `open`, `under_review` or `escalated`.
5. A driver is assigned (delivered orders with no driver are refused).
6. Every expected leg resolves to a recipient or to the named suspense balance.

Writes one audit event naming the evidence id.

### 3.4 `allocation_legs`

One row per order and leg (`seller`, `platform`, `driver`, `marshal`, `association`, `card_fee`), written by the payout in the same transaction as the wallet updates. States: `allocated`, `pending_recipient`, `approved`, `released_internal`, `externally_paid`, `failed`, `reconciled`. The sum of legs must equal the order total or the transaction rolls back. Each wallet update must report one row changed, or the transaction rolls back (this is the check that would have prevented the R108 loss).

### 3.5 `settlements`

External payments to sellers, drivers and marshals: provider or bank reference, amount, the allocation rows it settles, status. A leg becomes `externally_paid` only through a settlement row. Withdrawals are redesigned on top of this before they are ever enabled.

### 3.6 Disputes and refunds

- Dispute insert requires the caller to be buyer or seller of the order (closes SEC-43). Escalated disputes get a resolution path with an admin check in the body.
- A refund or chargeback from the provider updates evidence status through the same writer and blocks any further release.
- `refund_order` reverses recorded legs only, and refuses if any leg is already `externally_paid` without a recovery record.

### 3.7 Access

- Revoke EXECUTE on payout functions, wrappers and their callers from `service_role` (as in the containment draft); re-grant only what a reviewed flow needs.
- Buyer confirmation becomes a statement of receipt. It may trigger release only when the guard passes.
- The automatic release job is restored only after the guard is live, and skips test orders.
- The production database password and service-role key are payout credentials; rotation is an owner action.

---

## 4. Vocabulary for messages and screens

| State                         | May be shown as              | Must not be shown as      |
| ----------------------------- | ---------------------------- | ------------------------- |
| Order placed, no evidence     | "Awaiting payment"           | "Paid", "Held"            |
| Evidence verified             | "Payment received"           | "Paid out"                |
| Legs allocated internally     | "Earnings recorded"          | "Paid", "Credited to you" |
| External settlement confirmed | "Paid to you" with reference | none                      |

---

## 5. Test plan

**Status: no test has been executed.** Tests that write need separate written staging approval. Staging currently lacks `pg_cron`, `pg_net`, `pgtap` and the `payments_live` row (see `PHASE5B4-READONLY-FINDINGS.md` section 6).

### 5.1 Read-only checks (safe on either environment)

| ID  | Check                                                              | Expected after controls    |
| --- | ------------------------------------------------------------------ | -------------------------- |
| S1  | EXECUTE on each payout entry for anon, authenticated, service_role | all false                  |
| S2  | `cron.job` release entry                                           | absent until guard is live |
| S3  | `orders.escrow_status` default                                     | `awaiting_payment`         |
| S4  | `payment_evidence`: RLS enabled and forced, no app-role privileges | true                       |
| S5  | `authenticated` table privileges on financial tables               | SELECT only                |
| S6  | Dispute insert policy includes order ownership                     | true                       |
| S7  | Integrity view returns a correct seller ledger sum                 | equals stored balance      |

### 5.2 Fixture tests (staging only, writes; not authorised yet)

Access and routes

| ID  | Test                                                       | Expected                            |
| --- | ---------------------------------------------------------- | ----------------------------------- |
| T1  | Buyer calls `confirm_delivery` directly                    | refused                             |
| T2  | Service role calls `_apply_order_payout`                   | refused                             |
| T3  | Service role calls `_apply_route_payout` directly          | refused                             |
| T4  | Service role calls `_apply_order_payout_legacy` directly   | refused                             |
| T5  | Service role calls `public.auto_release_escrow()`          | refused                             |
| T6  | WhatsApp confirm on an order with no evidence              | no credit; neutral reply; audit row |
| T7  | Automatic release run with eligible orders and no evidence | zero released; no ledger change     |
| T8  | Seller, driver, marshal, admin attempt each payout entry   | refused                             |
| T9  | Anonymous attempt on each entry                            | refused                             |

Payment evidence

| ID  | Test                                                  | Expected                                 |
| --- | ----------------------------------------------------- | ---------------------------------------- |
| T10 | Payout with payments off and valid evidence           | refused                                  |
| T11 | Payout with payments on and **no** evidence           | refused                                  |
| T12 | Evidence amount one cent short                        | writer refuses; payout refused           |
| T13 | Evidence in another currency                          | refused                                  |
| T14 | Evidence for order A presented for order B            | refused                                  |
| T15 | Evidence whose payer does not match the buyer         | refused                                  |
| T16 | Same provider event delivered twice                   | one row; second is a no-op               |
| T17 | Second verified evidence for the same order           | refused                                  |
| T18 | Evidence written by `service_role` directly           | refused                                  |
| T19 | Browser redirect or WhatsApp message claiming payment | no evidence row created                  |
| T20 | New order from `create_order_v2`                      | starts `awaiting_payment`, not `holding` |

Release, duplicates and recipients

| ID  | Test                                                     | Expected                                                                           |
| --- | -------------------------------------------------------- | ---------------------------------------------------------------------------------- |
| T21 | Valid evidence, driver and marshal assigned              | released once; legs sum to total; audit names evidence id                          |
| T22 | Second release attempt on the same order                 | refused; no new rows                                                               |
| T23 | Two concurrent release attempts                          | exactly one succeeds                                                               |
| T24 | Delivered order with no driver                           | refused                                                                            |
| T25 | No marshal assigned                                      | marshal leg is `pending_recipient` in suspense; seller and platform legs unchanged |
| T26 | Zero-value leg                                           | row written with zero                                                              |
| T27 | Wallet row missing for a leg                             | whole transaction rolls back                                                       |
| T28 | Open dispute with valid evidence                         | refused                                                                            |
| T29 | Escalated dispute with valid evidence                    | refused                                                                            |
| T30 | Dispute raised by a user who is neither buyer nor seller | refused                                                                            |

Refunds, chargebacks, audit

| ID  | Test                                                                                 | Expected                                                    |
| --- | ------------------------------------------------------------------------------------ | ----------------------------------------------------------- |
| T31 | Refund of a released order                                                           | legs reversed exactly; totals return to zero for that order |
| T32 | Refund after a split rule change                                                     | still reverses the recorded amounts                         |
| T33 | Chargeback recorded before release                                                   | release refused                                             |
| T34 | Chargeback recorded after internal release                                           | legs flagged; no automatic external payment                 |
| T35 | Refund when a leg is already externally paid                                         | refused without a recovery record                           |
| T36 | UPDATE or DELETE on evidence, legs or settlements by any role except owner migration | refused                                                     |
| T37 | Every release has one audit event with evidence id                                   | true                                                        |
| T38 | Test order with valid evidence on production configuration                           | refused                                                     |
| T39 | `resolve_dispute` release branch on an open dispute                                  | record actual behaviour (suspected to fail today)           |
| T40 | Phone confirmation from a number that matches two profiles                           | refused as ambiguous                                        |

### 5.3 Pass criterion

No test in 5.2 may produce a row in `wallet_transactions`, `platform_revenue`, `driver_marshal_transactions`, or a balance change, unless a matching verified evidence row and audit event exist for that order.

Passing these tests proves the tested paths. It does not prove the database is secure; the read-only checks in 5.1 must also hold on production after any approved change.
