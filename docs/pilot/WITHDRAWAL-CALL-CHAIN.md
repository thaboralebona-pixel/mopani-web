# Withdrawal call-chain analysis (SEC-01)

Scope: staging, read-only. Definitions read on 10 Nov 2026. Nothing applied.

## Answers to the ten questions

1. **What happens when it is called.** `request_withdrawal_v2(p_amount)` (SECURITY DEFINER, owner postgres) checks `auth.uid()` is not null and the amount is positive. It reads `seller_kyc.kyc_status`, which must be `verified`. It locks the seller's wallet row and checks `available_balance >= amount`. It then moves the amount from `available_balance` to `pending_balance`, inserts a `pending` row in `seller_withdrawals`, and inserts a debit row in `wallet_transactions` with reference "Withdrawal request".

2. **Records created or changed.** `seller_wallets` (balances changed), `seller_withdrawals` (one new row), `wallet_transactions` (one new debit row), and `admin_audit_log` (via trigger `trg_audit_withdrawal`: "withdrawal_requested").

3. **Does it create a financial liability?** Yes, in the ledger. It creates a pending obligation to the seller and reduces what the seller can request again. No bank transfer happens in the database. Whether that obligation is ever paid depends on an admin action outside the app. Treat it as a real liability for the pilot.

4. **Available or reserved balances.** It changes `available_balance` (down) and `pending_balance` (up). There is no separate reserve field in this function.

5. **Repeated calls.** Yes. There is no idempotency key. Each call debits `available_balance` again until it runs out. A seller with R1,000 available can create ten R100 requests. Each one is a separate pending row.

6. **Idempotency.** None. The function does not take `p_idempotency_key`, and nothing deduplicates `seller_withdrawals`. (Compare `create_order_v2` and `confirm_delivery`, which do have idempotency keys.)

7. **Payment switch checked.** No. The function never reads `app_config.payments_live`. Neither the trigger `trigger_kyc_withdrawal_gate` (KYC only) nor `trg_audit_withdrawal` checks it.

8. **Can an administrator settle it?** Two paths, and they do not agree:
   - `approve_withdrawal(p_withdrawal_id)` (no caller check in the function; EXECUTE is revoked from anon and authenticated). It debits `pending_balance`, sets the row to `paid`, and writes a debit row. Its code comment says "funds actually leave the wallet now". That is false: it is a ledger event, not a transfer. Under owner Rule 3 this wording must not stand.
   - `mark_payout_settled(p_wallet_id, p_amount, p_reference)` (checks `is_admin()`; EXECUTE granted to authenticated, guarded inside). It debits `available_balance`, not `pending_balance`, and is not linked to any `seller_withdrawals` row. An admin can therefore settle the same money twice: once through the withdrawal row and once as a manual payout.
   - There is no cancel function. A pending withdrawal can only be approved. Money stays in `pending_balance` if nobody approves it.

9. **Can another function bypass the restrictions?** Not for writes to these tables from a signed-in user. RLS on `seller_withdrawals` allows only SELECT of own rows; there is no INSERT, UPDATE or DELETE policy. `seller_wallets` has only a SELECT policy. However, the table grants are wider than needed: `authenticated` holds INSERT, UPDATE and DELETE on `seller_withdrawals`, and INSERT and DELETE on `seller_wallets`. RLS currently blocks them, but one mistaken policy would open them. The bypass to watch is `mark_payout_settled` (point 8).

10. **Frontend exposure.** None. The only RPC the web app calls is `quote_order` (grep of `src/`). No withdrawal screen exists. The function is reachable directly through the API by any KYC-verified seller, because the anon key and a seller's session can call `/rpc/request_withdrawal_v2`.

## Current data on staging

- `seller_withdrawals`: 0 rows. `seller_kyc`: 2 rows. Nothing has been withdrawn.
- `fraud_check_withdrawal` exists but is **not attached** to any table. Its code also inserts the withdrawal ID into `fraud_flags.order_id`, which is the wrong column. Do not rely on it.

## Call chain

```
seller (signed in, KYC verified)
  └─ POST /rpc/request_withdrawal_v2(p_amount)            [EXECUTE: authenticated]
       ├─ reads seller_kyc.kyc_status                     must be 'verified'
       ├─ locks seller_wallets row (FOR UPDATE)
       ├─ UPDATE seller_wallets: available -= x, pending += x
       ├─ INSERT seller_withdrawals (status 'pending')
       │     ├─ trigger_kyc_withdrawal_gate  → enforce_kyc_on_withdrawal (KYC check again)
       │     └─ trg_audit_withdrawal         → admin_audit_log 'withdrawal_requested'
       └─ INSERT wallet_transactions (debit, 'Withdrawal request')

administrator (is_admin)
  ├─ approve_withdrawal(id)        [EXECUTE: postgres only]
  │     ├─ UPDATE seller_wallets: pending -= x
  │     ├─ UPDATE seller_withdrawals: status 'paid'      ← ledger only, NOT a transfer
  │     └─ INSERT wallet_transactions (debit)
  └─ mark_payout_settled(wallet, amount, ref)   [EXECUTE: authenticated, is_admin() inside]
        ├─ UPDATE seller_wallets: available -= x          ← different bucket, not linked
        └─ INSERT wallet_transactions (debit)
```

## Recommended pilot restriction

1. Revoke EXECUTE on `request_withdrawal_v2` from `public`, `anon` and `authenticated`. Keep the function so the owner can review it later.
2. Revoke INSERT, UPDATE and DELETE on `seller_withdrawals` from `authenticated`, so no route can write it directly.
3. Keep `approve_withdrawal` and `mark_payout_settled` for now, but record in the register that they can double-count. Before production, one of them must be removed or linked to the withdrawal row.
4. Correct the comment in `approve_withdrawal` in the next reviewed migration. Do not change it on production without approval.

Both steps are in `docs/pilot/remediation/SEC-01-withdrawal-lockdown.sql` (draft).

## Verification done

- Dry-run inside a transaction on staging, then rolled back. Inside the transaction: `authenticated` cannot execute `request_withdrawal_v2`, and cannot UPDATE `seller_withdrawals`. After rollback: both are back to the original state (`request_withdrawal_v2` is callable; `authenticated` can UPDATE).
- No database object depends on the two driver and marshal views (see SEC-02), so revoking their SELECT did not break any dependent object in the dry run.
