# Pilot launch checklist

Status key: [ ] not started, [~] in progress, [x] done with evidence. Items marked LEGAL need counsel's review. Items marked OWNER need the owner.

## A. Technical (staging first)

- [ ] SEC-01 withdrawal revoke applied on staging and tested (LEGAL: no payment claim)
- [ ] SEC-02 driver and marshal views revoked on staging and tested
- [ ] SEC-03 `sa_id_is_youth` revoked on staging and tested
- [ ] SEC-04 `request_subscription` revoked on staging and tested
- [ ] SEC-06 policy migration on production (OWNER approval, then re-test)
- [ ] Role tests repeated on production after each change (read-only plus rolled-back transactions)
- [ ] `npm run check` passes on the release commit (typecheck, format, tests, build)
- [ ] Sign-in working on staging with email (blocked: Resend SMTP key)
- [ ] Quote path tested end to end on staging with a real signed-in buyer account
- [ ] Mobile widths 320, 360, 390 px checked on the release build
- [ ] Production build served without the staging banner (environment check)
- [ ] Rotated credentials confirmed (SEC-11) (OWNER)
- [ ] GitHub 2FA enabled (OWNER, by 8 December 2026)

## B. Commercial and legal

- [ ] Counsel's written advice on payments, escrow and the 80/10/5/5 split (LEGAL)
- [ ] Paystack written confirmation (LEGAL / OWNER)
- [ ] Taxi association engagement and any written agreement (OWNER). None exists.
- [ ] Seller agreement signed by each pilot seller (LEGAL). Template not yet drafted by counsel.
- [ ] Driver and marshal agreements (LEGAL)
- [ ] POPIA notice and consent wording for buyers, sellers, drivers and marshals (LEGAL)
- [ ] Route price list confirmed by the owner against the database (see ROUTE-PRICING-VERIFICATION.md)

## C. Operations

- [ ] Seller roster (OWNER): names, location, products, weights recorded
- [ ] Driver and marshal roster (OWNER)
- [ ] Operating procedures reviewed by owner (see OPERATING-PROCEDURES.md)
- [ ] Failed delivery and escalation contacts published to the team
- [ ] First supervised order run through the checklist with no real money
- [ ] Stock discrepancy procedure agreed (STOCK-DISCREPANCY-PROCEDURE.md)
- [ ] Complaint procedure agreed (CUSTOMER-COMPLAINT-PROCEDURE.md)
- [ ] Incident register opened (INCIDENT-REGISTER.md)

## D. Go / no-go

Go only when every item in A is done, every item in B that is marked LEGAL is done, and C has a named owner for each step. Payments stay off until B's payment items are complete. Record the decision and date here: **\_\_**.
