# Pilot operating procedures (draft for owner review)

Status: draft. Items marked **LEGAL REVIEW** need counsel before they are relied on. Items marked **MANUAL** are done by people, not by the app. Items marked **APP** are supported by the app today. Nothing here is a signed agreement.

Application support today (verified on staging): produce listing, delivery routes, basket, product weight display, read-only payment status, and the total breakdown (only once sign-in works). Not yet in the app: sign-in, placing orders from the app, seller, driver, marshal and admin screens, notifications on staging (email ready, not sent), SMS and WhatsApp.

---

## 1. Seller onboarding (MANUAL, with APP later)

Purpose: a producer can sell safely and be paid through the approved process.

1. Visit the producer in person or by phone. Confirm the town, the products and an honest average weight for each product.
2. Record: name, town, phone, products, units, prices, stock. Record the average weight per unit in kg, or leave it blank. A blank weight counts as 5 kg per product line for delivery.
3. Agree the collection arrangement: which day, which time, and who hands over the goods.
4. Explain in plain language: the buyer pays through the platform; money is not paid out until the payment process is live; the producer will see "payment pending" until it settles.
5. Record consent to terms. **LEGAL REVIEW**: the terms are not approved.
6. Create the seller account only after the above is recorded. Do not share the anon key or any credential.
7. Evidence to keep: the onboarding form (no ID numbers unless POPIA review approves), the collection arrangement, the consent record.

## 2. Driver onboarding (MANUAL, with admin approval in the app)

1. Confirm the driver holds a valid operator and driver permit for the route. **LEGAL REVIEW** and taxi association confirmation required.
2. Record name, phone, taxi association member, vehicle type and load limit. Do not store licence or ID numbers in the app.
3. The app creates the driver record inactive and unverified. Only an admin can verify and activate it.
4. Brief the driver: accept by text, record collection with a photo, record delivery with a photo, never accept cash.
5. Evidence: permit copy kept by the association, the admin's approval, the briefing sign-off.

## 3. Marshal onboarding (MANUAL)

1. Confirm the marshal is trusted by the origin town's taxi rank. Record the rank and the association contact.
2. The marshal receives the parcel at the rank, records collection, and hands over to the driver.
3. Marshal payments: **EFT only, no cash** (owner decision). Until the payout process is live, the marshal sees "payment pending".
4. A marshal must be named on the delivery for their share to be paid. See the waiting-payout rule in section 4.
5. Evidence: rank confirmation, the briefing sign-off.

## 4. Delivery operating procedure (APP + MANUAL)

Steps, with the owner of each step:

| Step                  | Who                  | Action                                       | App support                       | Evidence               |
| --------------------- | -------------------- | -------------------------------------------- | --------------------------------- | ---------------------- |
| 1. Order placed       | Buyer                | Places order (once sign-in works)            | Not yet                           | Order number           |
| 2. Seller told        | Seller               | Prepares goods for collection                | Notification (not yet sent)       | Confirmation text      |
| 3. Driver accepts     | Driver               | Replies to accept by text, or accepts in app | Partly (accept by phone function) | Assigned status        |
| 4. Collection         | Driver, with marshal | Collects at the origin rank, takes a photo   | APP (photo, mark collected)       | Collection photo, time |
| 5. Transport          | Driver               | Travels by taxi; keeps the parcel with them  | MANUAL                            | Taxi reference         |
| 6. Delivery           | Driver               | Hands over, takes a delivery photo           | APP (proof of delivery)           | Proof photo, time      |
| 7. Buyer confirmation | Buyer                | Confirms receipt                             | APP once sign-in works            | Confirmation time      |
| 8. Payout             | Platform             | Pays the ledger entries                      | Ledger only; not a bank transfer  | Ledger reconciliation  |

Rule: a ledger entry is not proof that a person was paid. Payment is confirmed only when the payment provider and a bank record confirm it.

Waiting payouts: if a delivery has no marshal named, the buyer can still confirm, but the marshal's share waits. An admin releases it once a marshal is named (draft migration, not applied).

## 5. Failed delivery and escalation (MANUAL, with app flags where noted)

| Situation                           | First action                                            | Who              | Escalate to                  | Deadline                            |
| ----------------------------------- | ------------------------------------------------------- | ---------------- | ---------------------------- | ----------------------------------- |
| Seller cannot fulfil                | Cancel the item and tell the buyer what happened        | Seller and admin | Owner, if the order was paid | Same day                            |
| No driver available                 | Find a replacement driver on the route                  | Admin            | Owner                        | 2 hours before collection           |
| Taxi departs late                   | Tell the buyer the new time                             | Driver           | Admin                        | Immediately                         |
| Driver accepts but does not collect | Reassign                                                | Admin            | Owner                        | Before the collection window closes |
| Collected but not delivered         | Driver reports location and status; admin tracks        | Driver and admin | Owner                        | Same day                            |
| Buyer unavailable                   | Hold the parcel at the agreed point and call twice      | Driver           | Admin                        | Next business day                   |
| Dispute raised                      | Freeze payouts on the order; gather photos and messages | Admin            | Owner and counsel            | Within 48 hours (draft target)      |
| Proof photo missing                 | Do not confirm delivery; ask the driver                 | Admin            | Owner                        | Same day                            |
| Buyer does not confirm              | Follow up once after 24 hours                           | Admin            | Owner                        | 48 hours                            |
| Order cancelled                     | Record reason; no payout until the reason is recorded   | Admin            | Owner                        | Same day                            |
| Driver or marshal replaced          | Record the change on the delivery                       | Admin            | Owner                        | Same day                            |

Escalation rule: anything involving money, a dispute, or a person's safety goes to the owner the same day.

**LEGAL REVIEW**: the 48-hour dispute target, cancellation rules and liability for lost goods.

## 6. First supervised pilot order checklist (MANUAL)

Before the order:

- [ ] Owner has approved the production changes in writing.
- [ ] Security items SEC-01, SEC-02, SEC-06, SEC-07 are fixed or formally accepted.
- [ ] Credentials are rotated (SEC-12).
- [ ] Payments are off, and the app says so.
- [ ] One seller, one product, one route, one driver, one marshal are confirmed.
- [ ] Test order run on staging from start to finish with the same people.

During the order:

- [ ] Order number recorded.
- [ ] Seller confirms preparation.
- [ ] Driver accepts; time recorded.
- [ ] Collection photo taken; marshal recorded.
- [ ] Delivery photo taken; buyer confirms receipt.
- [ ] Owner is told the same day.

After the order:

- [ ] Ledger reconciles (audit view shows zero variance).
- [ ] Payout status is "pending" everywhere it is shown.
- [ ] Notes on anything that went wrong, in the incident register.

## 7. Daily pilot operations report (template)

Date: \_**\_ Prepared by: \_\_**

| Measure              | Today | Running total | Notes |
| -------------------- | ----- | ------------- | ----- |
| Orders placed        |       |               |       |
| Orders collected     |       |               |       |
| Orders delivered     |       |               |       |
| Buyers who confirmed |       |               |       |
| Failed collections   |       |               |       |
| Failed deliveries    |       |               |       |
| Stock discrepancies  |       |               |       |
| Complaints           |       |               |       |
| Payouts pending      |       |               |       |
| Incidents open       |       |               |       |

Blockers:
Decisions needed from the owner:

Note: targets are proposals for owner approval and are not agreed.
