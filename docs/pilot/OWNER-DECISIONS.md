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
