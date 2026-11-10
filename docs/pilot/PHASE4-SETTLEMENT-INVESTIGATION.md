# Withdrawal and settlement investigation (Phase 4, P1)

Environment: staging (`mopani-staging`). Production (`ProjectX`) checked by definition hash: the three withdrawal functions have identical definitions on both (md5 match), so the findings apply to both.
Pilot rule (owner, provisional): **no seller withdrawals during the pilot. Payments remain disabled.**

## 1. Every route that creates, approves, cancels or settles a withdrawal

| Route                                      | Who can execute (staging and production)                                                                                                         | What it does                                                                                                                                                                                                                                                  | Money effect on the wallet                                                      |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------------------- |
| `request_withdrawal_v2(numeric)`           | authenticated (SEC-01)                                                                                                                           | Checks KYC `verified`, then `available_balance -= amount`, `pending_balance += amount`, inserts `seller_withdrawals` (status `pending`), inserts a `wallet_transactions` debit labelled "Withdrawal request"                                                  | Creates a liability: funds move from available to pending                       |
| `request_withdrawal(uuid, numeric)` (v1)   | nobody (no anon, no authenticated grant)                                                                                                         | Same shape as v2 without the KYC check                                                                                                                                                                                                                        | Not reachable by app roles. Service role or owner only                          |
| `approve_withdrawal(bigint)`               | nobody by app roles (no authenticated grant). Callable by postgres/service role only                                                             | Requires status `pending`; row-locks; `pending_balance -= amount`; sets status `paid`; inserts a debit "Withdrawal approved". **No admin check inside the body.** Comment in the function says funds leave the wallet; that is inaccurate. No payment is made | Releases pending. Does not touch available. Records "paid" without money moving |
| `mark_payout_settled(uuid, numeric, text)` | authenticated (SEC-01); body checks `is_admin()`                                                                                                 | Requires positive amount and reference; **debits `available_balance`** directly; inserts debit and audit row. Not linked to any `seller_withdrawals` row                                                                                                      | A second debit from available, unrelated to the withdrawal row                  |
| `admin_force_cancel(bigint)`               | authenticated; body checks `is_admin()`                                                                                                          | Orders only: voids escrow hold and restores stock. Does not touch withdrawals                                                                                                                                                                                 | None on withdrawals                                                             |
| Triggers on `seller_withdrawals`           | `trigger_kyc_withdrawal_gate` (BEFORE INSERT: KYC must be verified), `trg_audit_withdrawal` (AFTER INSERT/UPDATE: writes audit rows)             | Gate and audit only                                                                                                                                                                                                                                           | None                                                                            |
| `fraud_check_withdrawal()`                 | not attached to any table (earlier finding, unchanged)                                                                                           | Would flag amounts above 10,000. Not active                                                                                                                                                                                                                   | None                                                                            |
| Direct table writes                        | `authenticated` holds INSERT, UPDATE, DELETE on `seller_withdrawals`; **RLS allows only SELECT**, so writes are refused today. Grants are excess | None while RLS holds                                                                                                                                                                                                                                          | None while RLS holds                                                            |
| Cancel path                                | **none exists** for seller withdrawals                                                                                                           | No function changes a pending withdrawal to cancelled                                                                                                                                                                                                         | A pending withdrawal cannot be reversed by any function                         |

Other functions that touch the same balances (read for completeness, not withdrawal routes): `credit_seller_wallet` / `_apply_route_payout` (credits seller on completion), `refund_order` (requires idempotency key; execute revoked from app roles), `credit_wallet` and `create_wallet_for_seller` (trigger functions, invoker, not callable as normal RPCs in a useful way).

## 2. Can one withdrawal be approved and settled by two paths?

**Yes. Confirmed by simulation.**

Simulation (staging, seller test account, KYC set to verified inside a transaction, all changes rolled back, nothing persisted):

| Step                                          | available  | pending | Withdrawal rows        |
| --------------------------------------------- | ---------- | ------- | ---------------------- |
| Start                                         | 958.50     | 0.00    | 0                      |
| `request_withdrawal_v2(100)` twice            | 758.50     | 200.00  | #5 pending, #6 pending |
| `approve_withdrawal(#5)`                      | 758.50     | 100.00  | #5 paid, #6 pending    |
| `mark_payout_settled(wallet, 100, 'SIM EFT')` | **658.50** | 100.00  | #5 paid, #6 pending    |

For one R100 payout (#5), the seller's wallet has been debited **R200**: once by the request, once by the settlement. The approval step only released pending and did not touch available. The result is an overstatement of seller debits, and a seller dispute waiting to happen. If payment is later made against both records, the platform pays out money that the ledger has already debited twice, and reconciliation cannot match the two debits to one bank transfer.

Post-simulation check: staging available 958.50, KYC unverified, 0 withdrawals, 0 admins. Rollback confirmed.

## 3. Shared transaction or idempotency mechanism?

- **Idempotency:** none. `request_withdrawal_v2` has no key. Repeated calls create repeated pending rows and repeated debits (simulated: two calls, two rows). `approve_withdrawal` is safe to call twice only because its status check rejects a non-pending row (`FOR UPDATE` plus status filter). `mark_payout_settled` has no status check and no withdrawal link, so it is not safe to repeat.
- **Shared transaction:** each function is its own transaction. There is no shared state between the three functions except the balances, and no link from a settlement to a withdrawal row.
- **Linkage:** `mark_payout_settled` takes a wallet id and a free-text reference. It cannot know whether the money is a withdrawal, an order payout, or something else.

## 4. Admin settlement routes

- `mark_payout_settled`: admin-guarded by `is_admin()` in the body; reachable by any authenticated user who calls it (the guard rejects non-admins). The guard relies on `admins` (staging: 0 rows; production: not checked in this pass, UV-02).
- `approve_withdrawal`: no admin guard, but no app grant. Anyone with service-role access can approve. Must be restricted or documented.
- `admin_pending_payouts`, `admin_payout_summary`, `admin_overview`: read-only admin views (guarded).

## 5. Can another function bypass the intended restrictions?

- `request_withdrawal` (v1): no grant to app roles; no KYC check in body. If granted, it would bypass KYC. Keep revoked.
- `mark_payout_settled`: bypasses the withdrawal lifecycle entirely (no withdrawal row). Any admin can debit any wallet with a free-text reason.
- Excess table grants on `seller_withdrawals` (INSERT, UPDATE, DELETE): blocked only by RLS. If a future policy is added carelessly, sellers could write their own withdrawal rows directly. Revoke removes this dependency.
- KYC self-verification: **not a bypass.** The `guard_seller_privileged_fields` trigger on `seller_kyc` resets `kyc_status`, `verified_at`, `verified_by`, `rejection_note` and `verified_youth` for non-admin, non-owner roles. Confirmed in the trigger body and the policy list.

## 6. Frontend

The frontend (`src/`) calls only `quote_order`, `products` and `delivery_routes`. No withdrawal, settlement or wallet call exists. The payments section says withdrawals are unavailable. Confirmed by grep on the branch.

## 7. Recommended pilot restriction (smallest safe change)

Implemented as step 01 in `docs/pilot/remediation/PHASE4-01-staging-lockdown.sql` (not applied):

1. Revoke EXECUTE on `request_withdrawal_v2` from public, anon, authenticated. Stops new requests.
2. Revoke EXECUTE on `mark_payout_settled` from public, anon, authenticated. Stops settlement by signed-in users. **Dependency:** if an admin console calls this function as an authenticated admin, it stops working. Owner to confirm.
3. Revoke EXECUTE on `approve_withdrawal` and `request_withdrawal` from public, anon, authenticated (already absent; stated for the record).
4. Revoke INSERT, UPDATE, DELETE on `seller_withdrawals` from authenticated. Preserves SELECT for history.
5. Revoke DELETE on `seller_wallets` from authenticated. **Not** INSERT: `create_wallet_for_seller` runs as the signing-up role and needs it.

What this does **not** do: it does not delete history, does not change any balance, and does not fix the double-debit. The double-debit path is removed only by the revoke of `mark_payout_settled` from app roles. The _definitions_ of `approve_withdrawal` (misleading comment, no admin check) and `mark_payout_settled` (no link to withdrawals) need a separate reviewed change before any settlement process is approved.

Tests: `docs/pilot/remediation/PHASE4-01-tests.sql`. Dry run on staging, all assertions passed (see section 8).

## 8. Dry-run evidence (staging, rolled back)

- BEFORE: request_v2 authenticated true; settle authenticated true; approve authenticated false; sa_id_is_youth anon true; request_subscription authenticated true; driver view authenticated SELECT true; marshal view authenticated SELECT true.
- AFTER: all false.
- N1 request as seller: denied (insufficient_privilege). N2 settle: denied. N3 direct update of withdrawal: denied. N4 driver view: denied. N5 subscription: denied.
- P1 owner reads own withdrawal history: allowed (0 rows, no withdrawals existed). P2 owner reads own wallet: allowed.
- Post-run privileges re-checked: unchanged (true, true, true, true, true, true).

## 9. Open items for the owner

- Confirm whether an admin console calls `mark_payout_settled` as an authenticated user. If yes, the revoke must wait until a service-role admin path exists.
- Decide whether the `approve_withdrawal` comment and the settlement design are corrected before any payment is enabled.
- Confirm there is no other admin tool using the withdrawal tables.
