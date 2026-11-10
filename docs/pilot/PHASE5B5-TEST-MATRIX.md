# Phase 5B-5: test and verification matrix

Date: 2026-11-10.

**Execution status of every test in this document: NOT EXECUTED.**

- Tests marked **W** write to a database: **NOT EXECUTED — REQUIRES SEPARATE STAGING APPROVAL**. They are never to be run on production, including inside a transaction that is rolled back.
- Tests marked **R** are read-only checks. They have not been run as a suite either. Where a fact was already observed during investigation, section 1 says so separately; that is an observation, not a passed test.
- "After guard" means after the draft in `remediation/PHASE5B5-payment-guard-DRAFT.sql` has been applied to staging. "After containment" means after the nine revokes and the unschedule.

Design references: `PHASE5B5-GUARD-ARCHITECTURE.md`, `PHASE5B5-CONTAINMENT-REVIEW.md`, `WHATSAPP-RECEIPT-CONFIRMATION-COPY-DRAFT.md`.

Fixture vocabulary: **O-paid** = route order with driver and marshal, verified evidence, delivered. **O-unpaid** = same without evidence. Roles: `buyer_a`, `buyer_b`, `seller_a`, `driver_a`, `marshal_a`, `admin_a`, `outsider`, `service` (service key), `writer` (`payment_writer`), `owner` (`postgres`).

"No money rows" means: no new row in `wallet_transactions`, `platform_revenue`, `driver_marshal_transactions`, `association_earnings`, `pay.allocation_legs`; no balance change.

---

## 1. Facts already observed (not tests)

| Observation                                                       | Where recorded                |
| ----------------------------------------------------------------- | ----------------------------- |
| Nine payout entry functions and their ACLs                        | Containment review, section 2 |
| `orders.escrow_status` default is `holding` on both environments  | Phase 5B-3 and 5B-4           |
| Cron job 2 active as `postgres` on production; no cron on staging | Phase 5B-4                    |
| Integrity view reports seller ledger 0 against 904                | Phase 5B-3                    |

---

## 2. Read-only checks (R)

| ID  | Check                                                                                                  | Expected                            | Environment |
| --- | ------------------------------------------------------------------------------------------------------ | ----------------------------------- | ----------- |
| R1  | EXECUTE for `anon`, `authenticated`, `service_role` on each of the nine payout entries                 | all false after containment         | both        |
| R2  | Recursive caller check (query V6 of the containment draft)                                             | zero rows                           | both        |
| R3  | `cron.job` contains `escrow-auto-release-72h`                                                          | absent after containment            | production  |
| R4  | Other cron jobs unchanged                                                                              | jobs 3 to 6 present, active         | production  |
| R5  | Orders, disputes, ledger counts and balances before and after containment                              | identical                           | production  |
| R6  | `orders.escrow_status` default                                                                         | `awaiting_payment` after guard      | staging     |
| R7  | Privileges of `anon`, `authenticated`, `service_role`, `payment_writer` on every `pay` table           | no INSERT, UPDATE, DELETE, TRUNCATE | staging     |
| R8  | RLS enabled and forced on every `pay` table                                                            | true                                | staging     |
| R9  | `authenticator` is not a member of `payment_writer`; `payment_writer` is a member of nothing           | true                                | staging     |
| R10 | Schema `pay` absent from the API's exposed schemas                                                     | true                                | staging     |
| R11 | Default privileges for `postgres` in schema `pay` grant nothing to app or service roles                | true                                | staging     |
| R12 | No function body contains the production project reference                                             | zero rows                           | staging     |
| R13 | `public.auto_release_escrow()` exists                                                                  | absent after guard                  | staging     |
| R14 | Trigger function `credit_wallet` attached to any table                                                 | none                                | both        |
| R15 | Integrity view seller ledger sum equals wallet-transaction sum for a wallet with credits and no debits | equal after monitor fix             | staging     |
| R16 | Unique index exists on canonical phone; no two profiles share a normalised number                      | true after phone design             | staging     |

---

## 3. Payout entry points (W)

| ID  | Setup                                 | Acting role                                                            | Expected result                                                                | Expected database changes               | Audit evidence                                                  |
| --- | ------------------------------------- | ---------------------------------------------------------------------- | ------------------------------------------------------------------------------ | --------------------------------------- | --------------------------------------------------------------- |
| E1  | O-unpaid                              | service calls `_apply_route_payout`                                    | permission denied                                                              | none                                    | none                                                            |
| E2  | O-unpaid                              | service calls `_apply_order_payout_legacy`                             | permission denied                                                              | none                                    | none                                                            |
| E3  | O-unpaid                              | service calls `_apply_order_payout`                                    | permission denied                                                              | none                                    | none                                                            |
| E4  | O-unpaid                              | service calls `public.auto_release_escrow()`                           | function does not exist (after guard) or permission denied (after containment) | none                                    | none                                                            |
| E5  | O-unpaid, buyer_a owns it             | buyer_a calls `confirm_delivery`                                       | permission denied                                                              | none                                    | none                                                            |
| E6  | O-unpaid                              | WhatsApp Confirm Receipt tap from buyer_a's number                     | neutral reply; no credit                                                       | none in money tables                    | webhook log entry without phone number                          |
| E7  | O-unpaid delivered 73 hours ago       | cron run of `private.auto_release_escrow` (staging job)                | zero released                                                                  | no money rows                           | `auto_release_failed` row naming "no verified payment evidence" |
| E8  | O-unpaid                              | service calls `complete_order`                                         | permission denied                                                              | none                                    | none                                                            |
| E9  | O-unpaid with open dispute            | service calls `resolve_dispute` release                                | permission denied                                                              | none                                    | none                                                            |
| E10 | O-unpaid with open dispute            | admin_a calls `admin_resolve_dispute` release                          | permission denied (containment)                                                | none                                    | none                                                            |
| E11 | O-unpaid                              | owner calls `_apply_route_payout` directly                             | raises "no verified payment evidence"                                          | none                                    | none                                                            |
| E12 | Non-route order with evidence fixture | owner calls `_apply_order_payout_legacy`                               | raises "Legacy payout is disabled"                                             | none                                    | none                                                            |
| E13 | O-unpaid                              | owner calls `_apply_order_payout`                                      | raises from the guard inside the leaf                                          | none                                    | none                                                            |
| E14 | O-unpaid                              | seller_a, driver_a, marshal_a, outsider, anon each attempt every entry | permission denied for all                                                      | none                                    | none                                                            |
| E15 | O-paid                                | owner calls `_apply_route_payout`                                      | succeeds once                                                                  | six legs; wallet rows; order `released` | `order_released_internal` with evidence id                      |

---

## 4. Payment evidence (W)

| ID  | Setup                                                           | Acting role                            | Expected result                                        | Expected database changes                                                            | Audit evidence                     |
| --- | --------------------------------------------------------------- | -------------------------------------- | ------------------------------------------------------ | ------------------------------------------------------------------------------------ | ---------------------------------- |
| P1  | Open intent; webhook with invalid signature                     | verifier stub, then writer logs event  | rejected before provider call                          | one `provider_events` row, outcome `rejected_signature`                              | that row                           |
| P2  | Valid signature; provider verify returns failed                 | writer                                 | no evidence                                            | event row `provider_verify_failed`                                                   | that row                           |
| P3  | Amount one cent below the intent                                | writer calls `record_verified_payment` | raises "Amount does not match"                         | none (transaction rolled back)                                                       | event row `mismatch`               |
| P4  | Currency USD                                                    | writer                                 | raises "Currency does not match"                       | none                                                                                 | event row `mismatch`               |
| P5  | Reference of order A, metadata names order B                    | writer                                 | raises "different order"                               | none                                                                                 | event row                          |
| P6  | Metadata buyer differs from the intent's buyer                  | writer                                 | raises "different buyer"                               | none                                                                                 | event row                          |
| P7  | Same provider event delivered twice                             | writer                                 | second call is a no-op                                 | one event row, one evidence row                                                      | single `payment_evidence_recorded` |
| P8  | Same transaction id submitted again with a new event id         | writer                                 | returns existing evidence id                           | no new evidence                                                                      | none new                           |
| P9  | Second reference for an order that already has a live intent    | buyer_a calls intent creation          | refused by unique index                                | none                                                                                 | none                               |
| P10 | Webhook from last month replayed                                | writer                                 | intent not open; refused                               | none                                                                                 | event row `duplicate`              |
| P11 | Direct INSERT into `pay.payment_evidence`                       | service                                | permission denied                                      | none                                                                                 | none                               |
| P12 | Call `pay.record_verified_payment`                              | service, authenticated, anon           | permission denied or schema not exposed                | none                                                                                 | none                               |
| P13 | EXECUTE mistakenly granted to service; service calls the writer | service                                | raises "Not the payment writer" (`session_user` check) | none                                                                                 | none                               |
| P14 | UPDATE or DELETE an evidence row                                | owner                                  | raises "append-only"                                   | none                                                                                 | none                               |
| P15 | Provider status `pending`                                       | writer                                 | raises "not success"                                   | none                                                                                 | event row                          |
| P16 | Intent in `reconciling`                                         | buyer_a requests a new intent          | refused; buyer told to wait                            | none                                                                                 | none                               |
| P17 | Evidence exists; event `refunded` recorded; release attempted   | owner                                  | release refused                                        | none                                                                                 | none                               |
| P18 | Evidence exists; event `charged_back`; release attempted        | owner                                  | release refused                                        | none                                                                                 | none                               |
| P19 | Valid success, all fields match                                 | writer                                 | evidence recorded                                      | evidence row; intent `verified`; order `awaiting_payment` → `holding`, status `paid` | `payment_evidence_recorded`        |
| P20 | Order total changed after the intent was created                | writer                                 | raises "Order total changed"                           | none                                                                                 | event row                          |
| P21 | Browser redirect to the success page with a forged status       | buyer_a                                | no state change                                        | none                                                                                 | none                               |
| P22 | `payments_live` true, no evidence, release attempted            | owner                                  | refused                                                | none                                                                                 | none                               |
| P23 | Evidence for a test order                                       | writer                                 | raises "Test orders cannot receive payment evidence"   | none                                                                                 | event row                          |

---

## 5. Allocation and settlement (W)

| ID  | Setup                                                      | Acting role                   | Expected result                                                            | Expected database changes                                                                                                                                                       | Audit evidence             |
| --- | ---------------------------------------------------------- | ----------------------------- | -------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------- |
| A1  | Paid, delivered, **no driver**                             | owner release                 | refused "has no driver"                                                    | none                                                                                                                                                                            | none                       |
| A2  | Paid, driver, **no marshal**                               | owner release                 | succeeds                                                                   | marshal leg `suspense`, event `pending_recipient`; suspense balance up by the marshal share; seller and platform legs equal the normal amounts; pooled marshal wallet unchanged | release audit row          |
| A3  | Paid, no driver, no marshal                                | owner release                 | refused                                                                    | none                                                                                                                                                                            | none                       |
| A4  | Paid; association share is zero; card fee zero             | owner release                 | succeeds                                                                   | association and card-fee legs written with amount 0, event `not_applicable`; no wallet row for them                                                                             | release audit row          |
| A5  | A2 result                                                  | read                          | suspense amount is not in `platform_revenue` and not in any seller balance | none                                                                                                                                                                            | none                       |
| A6  | Released order; release attempted again                    | owner                         | refused "already allocated"                                                | none                                                                                                                                                                            | none                       |
| A7  | Two sessions release the same order at once                | owner ×2                      | exactly one succeeds                                                       | one set of legs                                                                                                                                                                 | one audit row              |
| A8  | `platform_wallet` row missing (fixture)                    | owner release                 | whole transaction rolls back with "changed 0 rows"                         | none                                                                                                                                                                            | none                       |
| A9  | Legs sum differs from total (fixture with altered shares)  | owner release                 | refused "does not equal the buyer total"                                   | none                                                                                                                                                                            | none                       |
| A10 | Released internally, no settlement                         | read                          | no leg in `externally_paid`; no message says "paid"                        | none                                                                                                                                                                            | none                       |
| A11 | Settlement created; provider transfer fails                | settlement process            | settlement `failed`; legs back to `released_internal` via a new event      | new events only                                                                                                                                                                 | settlement events          |
| A12 | Retry after A11                                            | settlement process            | same idempotency key reused; one transfer at most                          | settlement `paid`; legs `externally_paid`                                                                                                                                       | events                     |
| A13 | Full refund after internal release                         | refund process                | one reversal leg per original leg, same cents negated                      | reversal legs; wallet debits; order `refunded`                                                                                                                                  | refund and reversal events |
| A14 | Partial refund of 1,000 cents on an order with uneven legs | refund process                | parts sum to exactly 1,000; proportional to recorded legs                  | reversal legs                                                                                                                                                                   | events                     |
| A15 | Refund after the split rule has changed                    | refund process                | still reverses the recorded amounts                                        | reversal legs equal originals                                                                                                                                                   | events                     |
| A16 | Refund after a leg is `externally_paid`                    | refund process                | recorded as `needs_recovery`; no wallet forced negative                    | refund row; recovery record                                                                                                                                                     | events                     |
| A17 | Same provider refund id delivered twice                    | refund process                | second is a no-op                                                          | none                                                                                                                                                                            | none                       |
| A18 | Refund when seller balance is lower than the seller leg    | refund process                | stops in `needs_recovery`                                                  | no partial debit                                                                                                                                                                | event                      |
| A19 | Suspense leg assigned to a marshal by admin approval       | admin_a via approved function | suspense down, marshal wallet up, new event `recipient_assigned`           | events; balances                                                                                                                                                                | audit with admin id        |
| A20 | Failed provider refund                                     | refund process                | no ledger reversal written                                                 | refund row `failed`                                                                                                                                                             | event                      |

---

## 6. State integrity (W)

| ID  | Setup                                                                  | Acting role                     | Expected result                                                         | Expected database changes | Audit evidence                    |
| --- | ---------------------------------------------------------------------- | ------------------------------- | ----------------------------------------------------------------------- | ------------------------- | --------------------------------- |
| S1  | New order via `create_order_v2`                                        | buyer_a                         | escrow `awaiting_payment`                                               | order row                 | none                              |
| S2  | UPDATE order to `holding` with no evidence                             | owner                           | trigger raises                                                          | none                      | none                              |
| S3  | INSERT order directly with `holding`                                   | owner                           | trigger raises                                                          | none                      | none                              |
| S4  | Driver marks an unpaid order delivered                                 | driver_a                        | delivery state changes only; no evidence created                        | delivery and order status | delivery audit                    |
| S5  | Buyer records receipt on an unpaid delivered order                     | buyer_a                         | receipt recorded; no release                                            | receipt record only       | receipt audit                     |
| S6  | Paid order with open dispute; every entry attempted (E1 to E15 routes) | each role                       | all refused                                                             | none                      | none                              |
| S7  | Paid order with **escalated** dispute; owner calls a leaf directly     | owner                           | refused (dispute check is inside the guard)                             | none                      | none                              |
| S8  | `payments_live` flipped to true with no evidence anywhere              | owner release on any order      | refused                                                                 | none                      | none                              |
| S9  | `payments_live` false, valid evidence                                  | owner release                   | refused                                                                 | none                      | none                              |
| S10 | Dispute inserted for an order by `outsider`                            | outsider                        | refused after policy fix                                                | none                      | none                              |
| S11 | `resolve_dispute` release branch on an open dispute, **current** code  | service (staging, before guard) | **record actual behaviour**; suspected to fail on its own dispute check | to be observed            | to be observed                    |
| S12 | Unpaid order older than 48 hours with no driver                        | cron auto-cancel                | cancelled (function updated to accept `awaiting_payment`)               | order and delivery        | cancel audit                      |
| S13 | Notification fails to send for a paid order                            | dispatcher                      | order and ledger unchanged                                              | notification status only  | failure row without personal data |

---

## 7. Phone identity and WhatsApp (W)

| ID  | Setup                                                                                   | Acting role                | Expected result                                       | Expected database changes | Audit evidence                       |
| --- | --------------------------------------------------------------------------------------- | -------------------------- | ----------------------------------------------------- | ------------------------- | ------------------------------------ |
| W1  | Profile with an unverified phone                                                        | buyer taps Confirm Receipt | refused: number not verified                          | none                      | row with profile id, no phone number |
| W2  | Second profile tries to verify a number already verified by another                     | buyer_b                    | refused by unique index on canonical number           | none                      | none                                 |
| W3  | Same number entered as `0821234567`, `27821234567`, `+27 82 123 4567` on three profiles | users                      | all normalise to one value; only one can verify       | one verified              | none                                 |
| W4  | Token for buyer_a's order delivered to a different person's phone (mistyped number)     | wrong recipient taps       | refused: sender not the verified buyer for that token | none                      | mismatch row without the number      |
| W5  | Token older than its expiry                                                             | buyer_a                    | refused: expired                                      | none                      | row                                  |
| W6  | Token used once, tapped again                                                           | buyer_a                    | "already recorded" reply; no second record            | none                      | none                                 |
| W7  | Token for buyer_b's order tapped from buyer_a's number                                  | buyer_a                    | refused                                               | none                      | row                                  |
| W8  | Two profiles normalise to the same number (legacy data fixture)                         | sender lookup              | refused as ambiguous; no first-match                  | none                      | row                                  |
| W9  | Same WhatsApp message id delivered twice by Meta                                        | webhook                    | one effect                                            | none on second            | none                                 |
| W10 | Webhook POST without a valid Meta signature                                             | anyone                     | 401; nothing processed                                | none                      | log line without body                |
| W11 | Any reply sent after a Confirm Receipt tap                                              | webhook                    | text contains none of: credited, paid, held, payment  | none                      | n/a                                  |
| W12 | Logs and audit rows produced by W1 to W10                                               | read                       | no full phone number, no message body                 | n/a                       | n/a                                  |

---

## 8. Monitoring (W unless marked)

| ID  | Setup                                                                                 | Acting role       | Expected result                                                 |
| --- | ------------------------------------------------------------------------------------- | ----------------- | --------------------------------------------------------------- |
| M1  | Wallet with credits and no debits                                                     | sweep             | ledger sum equals credits; no false variance                    |
| M2  | Wallet with debits and no credits (fixture)                                           | sweep             | variance reported correctly                                     |
| M3  | Unknown transaction type row                                                          | sweep             | flagged, not ignored                                            |
| M4  | Variance left unresolved for three days                                               | sweep             | alert repeated daily until acknowledged                         |
| M5  | A sweep function raises                                                               | background sweeps | `sweep_error` row written; other sweeps still run               |
| M6  | Email delivery failing                                                                | alerting          | second channel fires; "no alert delivered" alarm after 24 hours |
| M7  | Order in `holding` without evidence (fixture inserted by owner with trigger disabled) | reconciliation    | flagged                                                         |
| M8  | Evidence row whose `written_by` is not `payment_writer`                               | reconciliation    | flagged                                                         |
| M9  | Released order with fewer than six legs                                               | reconciliation    | flagged                                                         |

---

## 9. Pass criteria

1. No test in sections 3 to 7 may produce a money row or a balance change without a verified evidence row and a release audit row for that order.
2. Every refused action leaves row counts and balances identical to the pre-test snapshot.
3. All R checks hold on staging after the guard, and R1 to R5 hold on production after any approved containment.

Passing these tests would show that the tested paths behave as designed on staging. It would not prove production is secure, and it would say nothing about privileged SQL access.

## 10. Counts

Read-only checks: 16. Write tests: 15 entry point, 23 evidence, 20 allocation and settlement, 13 state, 12 phone and WhatsApp, 9 monitoring. Total 92 write tests. **Executed: 0.**
