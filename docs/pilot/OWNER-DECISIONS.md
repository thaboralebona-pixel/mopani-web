# Owner decisions (ranked by urgency)

Only decisions that need the owner are listed. Items the team can decide alone are not here.
Status key: **Open** = no decision yet. **Recommended** = team recommendation, not a confirmed decision. **Confirmed** = owner has decided (none recorded yet in this document).

| Rank | Decision                                                                                                                | Why it needs you                                                              | Recommendation                                                                           | Deadline                      | Status                                                                  |
| ---- | ----------------------------------------------------------------------------------------------------------------------- | ----------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------- | ----------------------------- | ----------------------------------------------------------------------- |
| 1    | Rotate production database password and staging webhook secret                                                          | Exposed in chat. Only the owner can rotate.                                   | Rotate today; confirm in writing.                                                        | Immediate                     | Open                                                                    |
| 2    | Approve staging revoke of `request_withdrawal_v2` (SEC-01) and withdrawal settlement path                               | Financial function callable while payments are off                            | Approve staging revoke; decide who may settle withdrawals (admin only, or none in pilot) | Before any staging test cycle | Recommended                                                             |
| 3    | Approve staging privacy fix for driver and marshal views (SEC-02)                                                       | Personal data exposure                                                        | Approve; accept that drivers and marshals will not show names to buyers in the pilot     | Before pilot                  | Recommended                                                             |
| 4    | Approve revoking `sa_id_is_youth` from public (SEC-03)                                                                  | ID number accepted from anonymous callers                                     | Approve; remove only after dependency check, and only with your sign-off                 | Before pilot                  | Recommended                                                             |
| 5    | Approve production policy migration for products, orders and deliveries (SEC-06)                                        | Production still shows buyer addresses to sellers and driver IDs to buyers    | Approve after staging re-test; schedule                                                  | Before any real order         | Recommended                                                             |
| 6    | Driver and marshal roster and onboarding (names, phone, vehicle, association)                                           | Needed to run any order                                                       | Start with 2 drivers and 1 marshal per route, see pilot design                           | Before pilot                  | Owner action                                                            |
| 7    | Taxi association engagement: whether to approach, and what to offer                                                     | No agreement exists. Revenue split (30% of the platform's 10%) is not agreed. | Engage before any delivery; do not assume agreement                                      | High                          | Open                                                                    |
| 8    | Time limit for orders waiting for a marshal, then escalation                                                            | Affects customer promise and seller expectation                               | Recommend 48 hours, then manual escalation to owner                                      | Before pilot                  | Open                                                                    |
| 9    | Whether buyers may see the driver identity and vehicle                                                                  | Privacy. Owner has said no to driver ID.                                      | Keep "no" for pilot; show only a delivery status                                         | Before pilot                  | Confirmed (owner said no to driver ID; no decision recorded on vehicle) |
| 10   | Whether `approve_withdrawal` comment and the second settlement path (`mark_payout_settled`) are fixed before production | Double-settlement risk                                                        | Fix or block settlement until reconciled                                                 | Before production payments    | Open                                                                    |
| 11   | Whether legacy subscriptions, referrals and youth verification are removed or retained                                  | Unapproved features                                                           | Revoke grants for the pilot; decide removal later                                        | Before pilot                  | Recommended                                                             |
| 12   | Payment provider: confirm Paystack account and written terms                                                            | Payments cannot go live without it                                            | Keep payments off until written confirmation                                             | Critical before payments      | Open (external)                                                         |
| 13   | Legal opinion on payments and escrow (counsel's written advice)                                                         | Regulatory exposure. Counsel must advise.                                     | Engage counsel before any money moves                                                    | Critical before payments      | Open (external)                                                         |
| 14   | Resend SMTP key for email sign-in on staging                                                                            | Needed for sign-in testing                                                    | Provide key via secure channel, not chat                                                 | Before sign-in testing        | Open (external)                                                         |
| 15   | GitHub 2FA                                                                                                              | Repository takeover risk                                                      | Enable                                                                                   | 8 December 2026               | Owner action                                                            |

## Legal review required (not decided by the team)

Items 12 and 13, any payment flow, any statement that funds are "held", "protected" or "released", any youth-owned claim, and the taxi association revenue share. None of these may be published to buyers or sellers before counsel's written view.

## Not decisions the owner needs to make

Button styling, copy tone, internal file layout, test structure.

---

## Phase 4 update (10 Nov 2026)

### Provisional owner decisions in force

1. No seller withdrawals during the pilot. **Recorded.**
2. No anonymous youth verification during the pilot. **Recorded.**
3. Public driver and marshal profile views not required by the current application. **Recorded.**
4. Legacy subscriptions not approved pilot functionality. **Recorded.**
5. Payments remain disabled. **Recorded.**
6. No production change without separate written approval. **Recorded.**

### Owner approvals given in direction (exact migration still needs approval)

- SEC-02 staging lockdown: approved in direction.
- SEC-03 staging revocation: approved in direction.
- SEC-01 withdrawal lockdown: approved in direction, with settlement investigation first (done).
- SEC-04: investigate first (done; `request_subscription` has no dependent function or trigger found; revoke included in step 01).
- SEC-06 production migration: **not approved**.
- SEC-11 credentials: rotate, owner action. Not started.

### Decisions now required, ranked by urgency

| Rank | Decision                                                                                                                                               | Why                                                                           |
| ---- | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------- |
| 1    | Approve the exact file `docs/pilot/remediation/PHASE4-01-staging-lockdown.sql` for staging                                                             | Blocks all staging remediation. Dry run already passed                        |
| 2    | Confirm whether any admin console calls `mark_payout_settled` as an authenticated admin                                                                | If yes, step 01 breaks it. Decides whether the revoke can go ahead as written |
| 3    | Rotate credentials, and identify the caller of `dispatch-notification`                                                                                 | Plan in `CREDENTIAL-ROTATION-PLAN.md`. Owner action                           |
| 4    | Confirm where KYC documents are uploaded and who can read them                                                                                         | Possibly critical privacy exposure (SEC-17)                                   |
| 5    | Confirm allocation model A (90/10 on product subtotal; 2:1 delivery) as the working assumption, and whether the legacy 80/10/5/5 branch may be retired | SEC-15. Affects seller statements                                             |
| 6    | Accept or reject the production SEC-06 migration after a staging re-test, including the loss of seller access to buyer address                         | SEC-06 is production-blocking                                                 |
| 7    | Defer collection of bank account numbers until payments are enabled                                                                                    | SEC-16 minimisation                                                           |
| 8    | Name the refund and cancellation authority (`admin_force_cancel`)                                                                                      | Refunds are manual                                                            |
| 9    | Name the dispute handler and response time                                                                                                             | Disputes freeze payout                                                        |
| 10   | Buyer confirmation timeout (no auto-confirmation proposed)                                                                                             | Open                                                                          |
| 11   | Marshal wait limit (48 hours proposed)                                                                                                                 | Open                                                                          |
| 12   | Route price figures for each product (conflicting notes)                                                                                               | Needed before listing                                                         |
| 13   | Seller packing view without buyer address (proposed contract)                                                                                          | Needed once SEC-06 is applied                                                 |
| 14   | Counsel: payments, escrow, POPIA for KYC data, the allocation model                                                                                    | Critical before payments                                                      |
| 15   | Taxi association engagement                                                                                                                            | No agreement exists                                                           |
| 16   | Paystack written confirmation                                                                                                                          | Critical before payments                                                      |

### External

- Resend SMTP key for email sign-in on staging: not provided. Owner to provide via secure channel (not chat).
- GitHub 2FA: before 8 December 2026.

## Phase 5B owner decisions (2026-11-10)

| #   | Decision                                                                                                                         | Recommendation                                                           | Status             |
| --- | -------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ | ------------------ |
| 17  | Approve production payout containment (`PHASE5B-containment-DRAFT.sql` steps 1 and 2) after staging rehearsal T1 to T8           | Approve after staging passes                                             | Open               |
| 18  | Approve unscheduling `escrow-auto-release-72h` (step 3)                                                                          | Approve. It can only pay out, and must not run without verified payment  | Open               |
| 19  | Approve edge-function wording change for WhatsApp confirm and report_problem, and removal of SQLERRM from buyer responses        | Approve                                                                  | Open               |
| 20  | Correction method for the 7 released test orders (R113 driver and marshal gap; platform +5.00 variance; monitor seller variance) | Document as test records first. Correct only through a reviewed plan     | Open               |
| 21  | Held order 96 (R50) and dispute 9                                                                                                | Keep held. Owner to decide dispute 9 outcome; do not close it by default | Open               |
| 22  | Decision 1: admin console source or access                                                                                       | Still required before Phase 4 step 01                                    | Open               |
| 23  | Decision 2: sensitive KYC collection stays disabled                                                                              | Keep disabled                                                            | Open (recommended) |
| 24  | Staging-to-production notification separation                                                                                    | Approve staging-only dispatch function and secrets                       | Open               |

## Phase 5B-2 owner decisions (2026-11-10)

| #   | Decision                                                                                                                                                                                                                           | Recommendation                             | Status |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------ | ------ |
| 25  | Approve payout guard v2 design direction (`remediation/PHASE5B-guard-v2-DRAFT.sql`), including the new `payment_evidence` table, written only by the signed provider webhook                                                       | Approve direction; staging rehearsal first | Open   |
| 26  | Confirm item 18 (unschedule `escrow-auto-release-72h`) and its restoration condition: restore only after guard v2 is live                                                                                                          | Approve unschedule now; restoration gated  | Open   |
| 27  | Approve further read-only production queries needed to close Unverified items: grants on `orders`, `disputes`, `app_config`; `cron.job.username`; bodies of `run_background_sweeps` and `auto_cancel_undispatched`. No SQL changes | Approve (read only)                        | Open   |
| 28  | Missing-recipient policy: Option A (suspense account, release blocked while any leg is pending) or Option B (reject release, change the split)                                                                                     | Option A                                   | Open   |
| 29  | Approve capturing production Edge Function sources into the repository (SEC-31)                                                                                                                                                    | Approve                                    | Open   |
| 30  | Approve adding an admin-role check inside `resolve_dispute` (SEC-32), reviewed on staging                                                                                                                                          | Approve direction                          | Open   |
| 31  | Ownership of dispute 9 and held order 96: owner decides the outcome; dispute is not closed by default or by any automated route                                                                                                    | Keep held                                  | Open   |

## Phase 5B-3 owner decisions (2026-11-10)

| #   | Decision                                                                                                                                                         | Recommendation                                                           | Status |
| --- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------ | ------ |
| 32  | Treat SEC-40 as the governing finding: no real order may be created on production until the payout guard and a non-`holding` initial escrow state exist          | Approve as a pilot gate                                                  | Open   |
| 33  | Guard placement: guard inside both leaf payout functions and revoke `service_role` EXECUTE on them (SEC-44)                                                      | Approve direction; staging rehearsal first                               | Open   |
| 34  | Payment evidence writer: one dedicated function and role, not general service-role table access                                                                  | Approve direction                                                        | Open   |
| 35  | Unassigned legs policy. Today they go to the seller (90%); July code sent them to the platform; refund assumes platform. Choose one rule                         | Suspense balance, never silent; block release of an order with no driver | Open   |
| 36  | Test-era records (seven released orders, R108 written nowhere, R5 unrecorded platform credit): keep as labelled test history, or correct through a reviewed plan | Keep and label; no balancing entries                                     | Open   |
| 37  | Dispute 9: no function can resolve an escalated dispute. Owner to decide outcome and the method (reviewed, privileged change)                                    | Keep unchanged for now                                                   | Open   |
| 38  | Approve fixes to the integrity monitor and alert delivery (SEC-42, SEC-45) as a reviewed staging change                                                          | Approve direction                                                        | Open   |
| 39  | Approve removing unused table privileges from `authenticated` (SEC-39) and adding an ownership check on dispute inserts (SEC-43)                                 | Approve direction                                                        | Open   |
| 40  | Rotate the production database password as a payout credential (cron functions are callable by `postgres` only)                                                  | Owner action                                                             | Open   |

## Owner decisions received 2026-11-10 (Phase 5B-3 review)

| Area                                       | Decision                                            |
| ------------------------------------------ | --------------------------------------------------- |
| Decision 32: production order freeze       | **Approved** (operational; no SQL)                  |
| Keep payments disabled                     | **Approved**                                        |
| Unschedule payout cron                     | Approved in principle; **execution not authorised** |
| Guard v2 architecture                      | Direction approved; current SQL not approved        |
| Suspense allocation for missing recipients | Approved in principle                               |
| Order 96 and dispute 9                     | Leave untouched                                     |
| Historical wallet adjustments              | Not approved                                        |
| Production or staging database changes     | Not authorised                                      |

## Phase 5B-4 decisions requested

| #   | Decision                                                                                                                                              | Recommendation                               | Status |
| --- | ----------------------------------------------------------------------------------------------------------------------------------------------------- | -------------------------------------------- | ------ |
| 41  | Written approval to execute `remediation/PHASE5B4-containment-package-DRAFT.sql` on production (grants and schedule only; no function or data change) | Approve after owner review of the exact file | Open   |
| 42  | Before 41: approve the WhatsApp reply wording change, or accept that "Confirm Receipt" will fail with a generic reply                                 | Change wording first                         | Open   |
| 43  | Approve adding `pg_cron`, `pg_net`, `pgtap` and a `payments_live` row to staging, **after** staging has its own function URLs and secrets             | Approve in that order                        | Open   |
| 44  | Approve authoring guard v3 SQL from `PHASE5B4-GUARD-ARCHITECTURE.md` for staging rehearsal                                                            | Approve                                      | Open   |
| 45  | Phone ownership verification before any phone-based action has financial effect                                                                       | Approve as a pilot requirement               | Open   |
| 46  | Staging write-test execution (T1 to T40)                                                                                                              | Separate authorisation after 43 and 44       | Open   |

## Decision status as instructed for Phase 5B-5 (2026-11-10)

| Decision                                            | Status                                                                             |
| --------------------------------------------------- | ---------------------------------------------------------------------------------- |
| 32: production order freeze                         | **Approved.** In force until the owner changes it in writing                       |
| Cron unscheduling (18, 26)                          | Approved in principle. **Execution not authorised**                                |
| 41: execute containment SQL                         | **Not approved**                                                                   |
| 42: WhatsApp wording change                         | Approved in principle. **Production deployment not authorised**                    |
| 43, 44: staging preparation and guard SQL authoring | **Approved** as preparation. Staging changes and test execution **not authorised** |

## Phase 5B-5 recommendations (not decisions until the owner approves)

| #   | Recommendation                                                                                                                                                                                | Why                                                                         | Status         |
| --- | --------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | --------------------------------------------------------------------------- | -------------- |
| 47  | Review `remediation/PHASE5B5-containment-package-DRAFT.sql` (one unschedule, nine revokes) in place of the eight-revoke draft                                                                 | The earlier draft left `admin_resolve_dispute` open                         | Recommendation |
| 48  | During containment, stop queueing the `order_delivered` WhatsApp template, or replace it with one that has no Confirm Receipt button                                                          | The button invites an action that will be refused                           | Recommendation |
| 49  | Run the payment verifier in a separate project that alone holds the provider keys and the `payment_writer` credential (architecture option A)                                                 | Secrets and the database URL are shared by all functions within one project | Recommendation |
| 50  | Remove pgTAP from the exposed schema on production                                                                                                                                            | SEC-51                                                                      | Recommendation |
| 51  | Confirm the release rule: no release without a driver; release may proceed with the marshal share held in suspense                                                                            | Needed to finalise the guard                                                | Recommendation |
| 52  | Treat dashboard access, the database password and `SUPABASE_DB_URL` as payout credentials: limit who holds them, rotate the password, and forbid direct database connections in function code | Containment cannot bind privileged access                                   | Recommendation |
| 53  | Export the Meta template texts and commit the deployed Edge Function sources to the repository                                                                                                | Wording cannot be reviewed otherwise                                        | Recommendation |
| 54  | Approve staging actions S1 to S13 in the order given in `PHASE5B5-STAGING-PREPARATION.md`                                                                                                     | Staging cannot rehearse the guard as it stands                              | Recommendation |
| 55  | Decide separately on `refund_order` and the withdrawal functions (containment draft, section E)                                                                                               | They write wallets and are outside the package                              | Recommendation |
