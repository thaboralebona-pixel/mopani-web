# Phase 5B-4: remaining functions, phone identity, leaf grants, staging comparison

Date: 2026-11-10. **Read-only.** Only `SELECT` queries were run, on production (`jpjjdzlhthvookllydai`, "ProjectX") and staging (`exohydsjywelbhhswswh`, "mopani-staging"). No write, grant, revoke, cron change, function change, deployment or test execution on either database.

Labels: **Confirmed** (read this pass), **Inferred**, **Unresolved**.

---

## 1. Owner decisions recorded (2026-11-10)

| Area                                       | Decision                                                                    |
| ------------------------------------------ | --------------------------------------------------------------------------- |
| Production order freeze (Decision 32)      | **Approved.** No real orders on production. Operational restriction, no SQL |
| Payments                                   | Stay disabled                                                               |
| Unschedule payout cron                     | Approved in principle. **Execution not authorised**                         |
| Guard v2                                   | Direction approved. Current SQL not approved                                |
| Suspense allocation for missing recipients | Approved in principle                                                       |
| Order 96 and dispute 9                     | Leave untouched                                                             |
| Historical wallet adjustments              | Not approved                                                                |
| Production or staging database changes     | Not authorised                                                              |

`holding`, `delivered`, `released` and wallet credits are **not** evidence that money was received.

---

## 2. Timestamp reconciliation

Query at the time of this pass (**Confirmed**):

| Item                                | Value                                |
| ----------------------------------- | ------------------------------------ |
| Database `now()`                    | 2026-11-10 13:25:28 UTC              |
| Database time zone setting          | UTC                                  |
| Same instant in Africa/Johannesburg | 2026-11-10 15:25:28 SAST             |
| Last `escrow-auto-release-72h` run  | 2026-11-10 13:00:00 UTC = 15:00 SAST |

The 13:00 UTC run was 25 minutes before the query, not in the future. The earlier report was written at about 15:16 SAST (13:16 UTC), after that run. The "approximately 10:00 SAST" figure in the review does not match the database clock or the session timestamps. All `cron.job_run_details` and audit times in these documents are UTC.

---

## 3. Leaf payout functions: grants and call paths (**Confirmed**)

| Function                             | Owner    | ACL                            | Called by                                                                                                              |
| ------------------------------------ | -------- | ------------------------------ | ---------------------------------------------------------------------------------------------------------------------- |
| `_apply_order_payout(bigint)`        | postgres | `postgres=X`, `service_role=X` | `confirm_delivery`, `complete_order`, `resolve_dispute`, `private.auto_release_escrow`, `private.run_regression_suite` |
| `_apply_order_payout_legacy(bigint)` | postgres | `postgres=X`, `service_role=X` | `_apply_order_payout` only                                                                                             |
| `_apply_route_payout(bigint)`        | postgres | `postgres=X`, `service_role=X` | `_apply_order_payout` only                                                                                             |

Additional entry found this pass:

- **R7: `public.auto_release_escrow()`**, a SECURITY DEFINER wrapper that runs `private.auto_release_escrow()`. ACL `postgres=X`, `service_role=X`. A service-role API call can trigger the whole automatic release without the cron. Unscheduling the job does not remove this route. Present on staging too.
- `private.run_regression_suite()` calls `_apply_order_payout`. Security invoker, postgres only. If run outside a rolled-back transaction it would write credits. Not a remote route.

Final route list: R1 WhatsApp, R2 buyer RPC, R3 cron, R4a `complete_order`, R4b `resolve_dispute`, R5a and R5b direct service-role calls, **R7 service-role wrapper**, R6 SQL as postgres. Every route except R6 depends on an EXECUTE grant or on the cron entry. That is the basis of the grants-only containment draft (`remediation/PHASE5B4-containment-package-DRAFT.sql`).

---

## 4. Remaining function bodies (**Confirmed**, all owner postgres, SECURITY DEFINER)

### 4.1 `_apply_route_payout(bigint)`

- Locks the order. Refuses unless escrow is `holding`.
- Refuses unless subtotal + delivery fee + card fee = total, and driver share + marshal share = delivery fee.
- **Refuses if no driver is assigned.**
- Platform = 10% of product subtotal; seller = subtotal minus platform. Ledger rows for seller, driver, marshal, association (from the platform's 10%), platform revenue; card fee to `processing_reserve`.
- No marshal assigned: the marshal share goes to the pooled `marshal_wallet` row id 1 and a `driver_marshal_transactions` row is written with a NULL recipient. This is an undeclared suspense balance.
- Final balance check: all legs must equal the total, or the transaction rolls back.
- **No payment check. No dispute check. No audit row. No check that `platform_wallet` or `marshal_wallet` id 1 was actually updated** (the same silent zero-row update that lost R108 in July).

### 4.2 `admin_force_cancel(bigint)`

- EXECUTE: authenticated and service_role. **Begins with `is_admin()`.**
- Only for `pending`, `paid` or `processing` orders with escrow `holding` and a delivery still `unassigned`.
- Restores stock, sets order and escrow to `cancelled`, delivery to `returned`, cancels queued notifications, writes audit `order_force_cancelled`.
- Returns `refund_owed` with the note that no automated payment rail exists. Writes no wallet.
- Not a payout route. Its own comments confirm the system records `holding` with no payment behind it.

### 4.3 `private._cancel_before_collection(bigint, uuid, text)`

- EXECUTE: postgres only. Same checks and effects as above for `pending` + `holding` orders with delivery `unassigned` or `assigned`. Audit row with actor and reason. No wallet write.

### 4.4 `private.invoke_whatsapp_dispatcher()`

- EXECUTE: postgres only. Reads the webhook secret from the vault and posts an empty body to the production `dispatch-whatsapp` URL. Errors become warnings. No table write. Not a payout route. (Secret value not read.)

### 4.5 `set_delivery_address(bigint, jsonb)`

- EXECUTE: authenticated. Updates only `delivery_address`, only on the caller's own `pending` order.

### 4.6 `guard_profile_privileged_fields()` (trigger on `profiles`)

- Lets users keep role within buyer/seller, pins `location_verified` and `referred_by`. **Does not restrict `phone`.**

---

## 5. Phone-based WhatsApp identification

### 5.1 Facts (**Confirmed**)

- `profiles.phone` is in the `authenticated` column UPDATE grant. A user can set any value on their own row. Nothing verifies they control the number (no one-time code).
- Unique index `uq_profiles_phone` is on the **raw text** (non-empty). Matching is done on the **normalised** number (`private.sanitize_za_phone`), which maps `0821234567`, `27821234567` and `+27 82 123 4567` to the same value. Two profiles can therefore hold the same real number in different spellings.
- Lookups by sender (`accept_route_cargo_by_phone`, `get_order_statuses_by_phone`) take the first matching profile with `LIMIT 1` and no ordering.
- `confirm_order_delivery_by_phone` compares the sender with the phone on the **order's buyer profile**.
- Audit rows for mismatches and unknown senders store the sender's phone number in plain text.
- **Production today: 3 profiles, none with a phone number.** The WhatsApp confirm route cannot match anyone at present.

### 5.2 Can users be confused or impersonated?

| Scenario                                                        | Result                                                                                                                                                                                                                                                         |
| --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Attacker confirms someone else's order                          | Not through this path: the sender must equal the phone on the buyer's own profile, which only the buyer (or an admin) can set                                                                                                                                  |
| Buyer mistypes their number, or enters a number they do not own | **The person who owns that number receives the confirmation template and can release the payout with one tap.** No ownership check exists. Real risk once phones are populated                                                                                 |
| Attacker registers a victim's number in a different spelling    | Sender lookups become ambiguous. The victim's WhatsApp status request may resolve to the attacker's profile (victim sees the wrong orders); a real driver's "accept cargo" may resolve to a non-driver profile and be refused. Confusion and denial, not theft |
| Attacker claims a number before its real owner signs up         | The real owner cannot register the same spelling; their WhatsApp messages act on the attacker's account                                                                                                                                                        |

### 5.3 Required before any phone-based action carries financial effect

1. Verify phone ownership with a one-time code before the number is trusted.
2. Store the normalised number and make **that** unique.
3. Remove `LIMIT 1` ambiguity: fail if more than one profile matches.
4. Do not let a messaging tap alone release money. Under the approved direction it cannot, because release will need payment evidence.
5. Hash or truncate phone numbers in audit rows.

---

## 6. Staging versus production

Same fingerprint query on both projects (function source hash, security mode, EXECUTE for anon, authenticated and service_role; table grants; policies; views; defaults).

### 6.1 Identical (**Confirmed**)

- **All 30 fingerprinted functions**: same source hash, same security mode, same grants. This includes all payout, confirmation, dispute, refund, withdrawal, order-creation, cancel, sweep and notification functions, and the `public.auto_release_escrow()` wrapper.
- `orders.escrow_status` default `'holding'`.
- Table grants for anon and authenticated on all 13 tables checked.
- Views `v_wallet_integrity` and `v_wallet_integrity_flagged` (same NULL-arithmetic bug).
- Both `post_notification` and `invoke_whatsapp_dispatcher` contain the **production** function URL.

### 6.2 Different (**Confirmed**)

| Item                           | Production                                                              | Staging                               | Consequence                                                                                                                                                                                                                                                                                                       |
| ------------------------------ | ----------------------------------------------------------------------- | ------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `pg_cron`                      | installed, 5 jobs                                                       | **not installed**                     | Staging has no automatic release, sweeps or auto-cancel. Cron behaviour cannot be rehearsed on staging as it stands                                                                                                                                                                                               |
| `pg_net`                       | installed                                                               | **not installed**                     | The staging notification functions cannot make an HTTP call as installed. The production URL is in the code but inert. **This corrects the earlier statement that staging notifications reach production: the coupling is in the definition, not currently live.** It becomes live the moment `pg_net` is enabled |
| `pgtap`                        | installed                                                               | not installed                         | Regression suite cannot run on staging                                                                                                                                                                                                                                                                            |
| `app_config.payments_live`     | `false`                                                                 | **row absent**                        | Code treats absent as false. Tests of the switch need the row                                                                                                                                                                                                                                                     |
| Orders policies                | `Seller can view their product orders`, `seller view own sales` present | absent                                | Production exposes order rows to sellers (SEC-06)                                                                                                                                                                                                                                                                 |
| Deliveries policies            | `deliveries_participant_read` present                                   | absent                                | As SEC-06                                                                                                                                                                                                                                                                                                         |
| `wallet_transactions` policies | seller read only                                                        | plus driver and marshal read policies | Staging is ahead                                                                                                                                                                                                                                                                                                  |
| `v_ledger_imbalance_audit`     | one definition                                                          | different definition                  | Not compared line by line (**Unresolved**)                                                                                                                                                                                                                                                                        |
| Active admins                  | 2                                                                       | 0                                     | Admin-gated functions cannot be exercised on staging without a fixture                                                                                                                                                                                                                                            |
| Data                           | 8 orders, 1 dispute, 3 profiles                                         | 7 orders, 0 disputes, 4 profiles      | Separate data sets                                                                                                                                                                                                                                                                                                |

### 6.3 What this means for testing

- Function-level tests of payout, confirmation, refund and dispute logic are valid on staging: the code is identical.
- Cron, HTTP dispatch and the regression suite cannot be tested on staging until the three extensions are added there (a staging change needing approval).
- Staging must get its own function URLs and secrets **before** `pg_net` is enabled, or enabling it creates the cross-environment call.

---

## 7. Remaining unknowns

1. External admin console (Decision 1).
2. Why the platform wallet row was absent before 21 July; the exact payout body live on 20 July.
3. Whether `resolve_dispute`'s release branch can succeed (needs a staging test).
4. `v_ledger_imbalance_audit` difference between environments.
5. Whether staging has a migration history table (not queried).
6. Production Edge Function sources are still not in the repository.
7. Storage policies.
8. Which route produced the seven July releases.

---

## 8. New register entries

SEC-47 to SEC-50 in `SECURITY-REGISTER.md`.

Nothing here authorises a database change, payment activation, merge or deployment.
