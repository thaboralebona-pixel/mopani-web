# Phase 5B: payout containment, reconciliation and environment separation

Status: investigation complete (read-only on staging and production). **No production or staging change was made.** Every change below is a proposal awaiting written owner approval.

Evidence labels: **Confirmed** = read from the live database or source this pass. **Assumption** = inferred. **Unverified** = not checked.

---

## 1. Critical finding: three routes move ledger money while payments are off

Production payouts all run through `public._apply_order_payout(bigint)`. That function checks only for open disputes and never checks `app_config.payments_live` (value `'false'`, confirmed). It has no check that a payment was received. Three routes reach it:

| #   | Route                                                                                                                          | Who can trigger it                                                                                                                                     | Confirmed evidence                                                                                                | Status of control                                                                                                                                      |
| --- | ------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------ | ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------ |
| R1  | WhatsApp "Confirm Receipt" → `confirm_order_delivery_by_phone(phone, order, key)` → `confirm_delivery` → `_apply_order_payout` | Anyone sending from the buyer's verified number (HMAC-signed webhook)                                                                                  | Function grants: anon false, authenticated false (service role only). Sender must match buyer phone.              | Identity check present. **No payment or payments_live check.** Reply text claims "seller and driver have been credited".                               |
| R2  | Direct RPC `confirm_delivery(order, key)`                                                                                      | **Any signed-in buyer**, via the Supabase API, outside WhatsApp                                                                                        | Grant: authenticated **true**. Buyer check is `buyer_id = auth.uid()` and status `delivered`/`holding`.           | **No payment or payments_live check.** Not visible in the frontend (`src/` calls none of it), so it is reachable by anyone who calls the API directly. |
| R3  | Hourly cron `escrow-auto-release-72h` (`0 * * * *`, active) → `private.auto_release_escrow()` → `_apply_order_payout`          | No one (scheduled). Releases any `delivered` + `holding` order 72 hours after delivery, when no dispute is open. Sets `buyer_confirmed = true` itself. | Cron job active; function body read. Audit rule text: "72h after delivery, no open dispute".                      | **No payment or payments_live check.** Runs without any human action.                                                                                  |
| R4  | `complete_order` and `resolve_dispute` (service role only)                                                                     | Service role / admin tooling                                                                                                                           | Grants: service role only. `resolve_dispute` has **no admin check in its body**; it relies entirely on the grant. | Depends on grant discipline. Note only.                                                                                                                |

Also confirmed: `private.run_background_sweeps` and `auto_cancel_undispatched` do not reference the payout functions by name in their bodies. Not fully read; **unverified** whether they call payouts indirectly.

**Confirmed financial exposure today:** 7 orders released to wallets (R904 seller credit, R113 platform revenue, R113 driver and marshal share not credited anywhere). Full breakdown in `PHASE5B-RECONCILIATION.md`. The R50 held order (96) is protected **only** by dispute 9, which is `escalated`. That protection is a side effect of a dispute row, not a payment control. If dispute 9 were closed without a resolution, R3 would release order 96 automatically within the next hour.

**Corrections to `PHASE5-REVIEW.md`:** that document named one route (WhatsApp). There are three buyer- or schedule-reachable routes plus two service-role routes, and the scheduled route (R3) is the most dangerous because it needs no one to act.

---

## 2. Why the containment is not the permanent control

`payments_live` is a switch. The owner's rule is correct: a switch alone must not authorise a payout. The permanent design must establish, for **each order**, before any state change:

1. A verified payment record exists, from the payment provider, linked to the order (`orders` currently has `stripe_session_id` and `stripe_payment_intent` columns but no provider reference column for Paystack; both are empty on all 8 production orders).
2. The amount received equals `orders.total_amount` (exact, to the cent).
3. The payment is not already used by another order (idempotency key on the payment reference).
4. The payout write is atomic with the order state change (one transaction, `FOR UPDATE`).
5. Only a signed provider callback can write verified payment evidence. A buyer, a webhook message or a browser redirect cannot.

This design is **not** included in this phase. It needs its own reviewed change.

---

## 3. Proposed containment (draft: `docs/pilot/remediation/PHASE5B-containment-DRAFT.sql`)

| Step | Change                                                                                                       | Closes                                     | Reversible                 |
| ---- | ------------------------------------------------------------------------------------------------------------ | ------------------------------------------ | -------------------------- |
| 1    | Guard at the top of `_apply_order_payout`: raise unless `payments_live = 'true'`. Everything else unchanged. | R1, R2, R3, R4 (all end here)              | Yes: restore original body |
| 2    | `revoke execute on confirm_delivery from public, anon, authenticated`                                        | R2 (direct buyer call)                     | Yes: re-grant              |
| 3    | `cron.unschedule('escrow-auto-release-72h')` (**separate approval**)                                         | R3 (stops hourly attempts and audit noise) | Yes: `cron.schedule`       |

Behaviour after step 1 and 2, with payments off:

- WhatsApp confirm: the order stays `delivered` / `holding`. `confirm_delivery` rolls back. The webhook returns `confirm_failed` and writes `whatsapp_confirm_failed` with the error text. **No wallet or ledger row changes.**
- Direct buyer RPC: permission denied.
- Cron: each run fails inside `_apply_order_payout`, writes `auto_release_failed`, moves nothing.
- Dispute resolution (`resolve_dispute` with `release_to_seller`): fails. Admin must resolve through a reviewed path once payments are live.

**Required companion change (edge function, separate approval):** the `whatsapp-webhook` reply on confirm failure must not say "credited". Proposed reply when payments are off: "Thank you. We have recorded your confirmation. Payment processing is not yet live, so no payment has been made." Also remove `detail: SQLERRM` from the buyer-visible response. The error text must stay in the audit log only.

### Original body of `_apply_order_payout` (rollback source, read 2026-11-10)

```sql
CREATE OR REPLACE FUNCTION public._apply_order_payout(p_order_id bigint)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  IF EXISTS (SELECT 1 FROM disputes
              WHERE order_id = p_order_id
                AND status IN ('open','under_review','escalated')) THEN
    RAISE EXCEPTION 'Order % has an open dispute. Payment stays frozen until admin resolves it.', p_order_id;
  END IF;
  IF EXISTS (SELECT 1 FROM orders WHERE id = p_order_id AND route_id IS NOT NULL) THEN
    PERFORM public._apply_route_payout(p_order_id);
  ELSE
    PERFORM public._apply_order_payout_legacy(p_order_id);
  END IF;
END $function$
```

---

## 4. Test plan (staging only, before any production approval)

| Test                                       | Expected                                                                                                            | Roles                    |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------- | ------------------------ |
| T1 Payout refused while payments off       | `_apply_order_payout` raises "Payouts are disabled"; all wallet totals and `wallet_transactions` count unchanged    | service role             |
| T2 WhatsApp confirm with payments off      | `ok=false`, `confirm_failed`; order stays `delivered`/`holding`; no ledger row                                      | service role via webhook |
| T3 Buyer direct RPC                        | permission denied on `confirm_delivery`                                                                             | authenticated buyer      |
| T4 Anonymous RPC                           | permission denied                                                                                                   | anon                     |
| T5 Cron run                                | returns 0 released; only `auto_release_failed` audit rows                                                           | scheduled                |
| T6 Seller, driver, marshal, admin attempts | all refused (no EXECUTE on payout functions)                                                                        | each role                |
| T7 Escalated dispute                       | payout refused (existing rule still holds)                                                                          | service role             |
| T8 Notification failure                    | a failed notification does not change order or ledger state (verify no trigger writes money on notification insert) | service role             |

Test T6 in the draft (payments on, no payment evidence) is expected to **pass** under containment. That is why containment is not the permanent control.

Note: T1 to T8 must run on a staging project, never on production. Production verification is read-only (`select` on settings, grants and definitions).

---

## 5. Staging and production separation

**Confirmed:** the staging database's `private.post_notification()` posts to the production `dispatch-notification` URL. A staging notification therefore runs production code with production secrets. (The URL is hardcoded; the secret is read from the staging vault. The vault value was not printed or recorded.)

Proposed remediation (separate approval, not executed):

1. Disable staging notification delivery now: set the staging URL to a null or staging-only value, or disable the `dispatch_notification_webhook` trigger on staging.
2. Deploy a staging `dispatch-notification` with its own project URL and secret.
3. Confirm production secrets are not present in the staging vault (store and compare by name only).
4. Confirm the production function rejects a staging-signed request.
5. Test: a staging notification reaches only staging recipients.
6. Failure rule: a notification error must not change orders, wallets or ledger rows. Verified for the trigger path (`dispatch_notification_webhook` does not write to financial tables); repeat after the change.

**Unverified:** whether the staging `dispatch-notification` function exists. Not checked in this pass.

---

## 6. Notification privacy and wording (from Phase 5 source reading; not re-run this pass)

| Item                                       | Finding                                         | Proposed change                                                                                                                      |
| ------------------------------------------ | ----------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------ |
| `dispatch-notification` withdrawal message | Fallback text says a withdrawal was approved    | Neutral wording: "Your withdrawal request has been received. No money has been moved." Withdrawals are disabled in the pilot anyway. |
| Seller and driver payout messages          | Can state funds were credited                   | Only after verified settlement. While payments are off: "Your order is complete. Payment settlement is not yet live."                |
| SMS stub                                   | Logs phone number and message body to logs      | Log only a hashed recipient and message type. Check log retention and who can read function logs.                                    |
| WhatsApp `report_problem`                  | Says "payment stays held"                       | Neutral wording until payments are live.                                                                                             |
| WhatsApp confirm reply                     | Says sellers and drivers "have been credited"   | See section 3.                                                                                                                       |
| Error logging                              | `SQLERRM` returned to buyer in webhook response | Return a generic reason; keep detail in `admin_audit_log` only.                                                                      |

---

## 7. Admin console dependency (Decision 1, still open)

**Known:** no admin console source is in this repository. No database function or Edge Function calls `mark_payout_settled`. The admin digest references an external admin URL.

**Not proven:** that no external console calls `mark_payout_settled`, `approve_withdrawal` or `resolve_dispute`. A console that calls `resolve_dispute` would need service role; a console using an authenticated admin session would not reach `resolve_dispute` (no EXECUTE for authenticated), so the console would already be failing if it relies on that.

**Needed to close:** the console source or repository, its database role (service role or user session), a list of RPCs it calls, and the admin audit trail for the last 90 days.

**If the Phase 4 withdrawal lockdown were applied now, what would break:** any console action that calls `mark_payout_settled` or `approve_withdrawal` as an authenticated admin. Those functions are the only settlement tools. Do not apply Phase 4 step 01 until this is answered.

---

## 8. Environment and credentials (owner actions; no values recorded here)

- Credential rotation is the owner's action. Claude does not handle secret values.
- Rotate the webhook secret used by `whatsapp-webhook` and `dispatch-whatsapp` together, since both sides must change in one window.
- The staging-to-production coupling in section 5 means the production `dispatch-notification` secret is in the staging vault. Rotate the production value after the separation work, not before.

---

## 9. Decisions and approvals requested

| #   | Decision                                                                         | Recommendation                                                                                                                            |
| --- | -------------------------------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| A   | Approve the production containment (step 1 and 2) after staging rehearsal        | Approve after T1 to T8 pass on staging                                                                                                    |
| B   | Approve unscheduling the auto-release cron (step 3)                              | Approve. The job can only pay out, and it must not run without verified payment                                                           |
| C   | Approve the edge-function wording and error-leak change                          | Approve                                                                                                                                   |
| D   | Owner decision on the 7 released test orders and the R113 driver and marshal gap | Owner choice: (a) leave as test records and document, or (b) correct through a reviewed adjustment. No correction without a reviewed plan |
| E   | Owner decision on held order 96 (R50)                                            | Keep held. Dispute 9 stays open until owner decides                                                                                       |
| F   | Decision 1 (admin console source)                                                | Still required                                                                                                                            |
| G   | Decision 2 (KYC collection stays disabled)                                       | Keep disabled                                                                                                                             |

Nothing in this document authorises a production change, payment activation, a merge or a deployment.

## Phase 5B-2 update (2026-11-10)

- The payments_live-only guard in step 1 is **containment only**. It does not check payment evidence, amount, currency, recipient legs or audit basis. See `PHASE5B-GUARD-AND-TESTS.md` section 3.
- Guard v2 (`remediation/PHASE5B-guard-v2-DRAFT.sql`) requires a `payment_evidence` table that does not exist yet. It fails closed until it does.
- The cron unschedule SQL, verification and restoration are in `remediation/PHASE5B-cron-containment.sql`. Restore only after guard v2.
- Full call graph (R1 to R4b), bypass list B1 to B8, order 96 and dispute 9 analysis, and staging tests T1 to T16 with the safe/fixture split are in `PHASE5B-GUARD-AND-TESTS.md`.
- No test was executed.

## Phase 5B-3 update (2026-11-10)

Read-only production evidence in `PHASE5B-PRIVILEGE-AND-FUNCTION-REVIEW.md` changes the containment picture:

- Routes R5a and R5b exist: `service_role` can call `_apply_order_payout` and both leaf functions directly. The leaf functions do not check disputes. **Step 1 of the containment draft (guard in `_apply_order_payout` only) does not stop R5b.** The guard must be in both leaf functions, or `service_role` EXECUTE on them must be revoked.
- `orders.escrow_status` defaults to `holding`. The normal order flow reaches payout with no payment. Containment is therefore needed for ordinary use, not only for misuse.
- The cron runs as `postgres` and has run 3,072 times, all succeeded, last at 13:00 UTC today.
- Direct-write bypasses by app roles (B1 to B4) are closed.
- `auto_cancel_undispatched` cancels unassigned orders after 48 hours only while payments are off. It is not a payout route.
- No change was applied.
