-- SEC-01 REMEDIATION. DRAFT. STAGING ONLY. NOT APPLIED. Requires owner approval.
-- Purpose: stop signed-in sellers creating withdrawal liabilities while payments are off.
-- Scope is deliberately narrow. Wider wallet grants (seller_wallets INSERT/DELETE) are NOT changed here:
-- the trigger create_wallet_for_seller runs as the invoking user and must be checked first.

begin;

-- BEFORE (expected): authenticated can execute; authenticated can UPDATE seller_withdrawals.
-- select has_function_privilege('authenticated','public.request_withdrawal_v2(numeric)','EXECUTE');  -- true
-- select has_table_privilege('authenticated','public.seller_withdrawals','UPDATE');                  -- true

revoke execute on function public.request_withdrawal_v2(numeric) from public, anon, authenticated;
revoke insert, update, delete on public.seller_withdrawals from authenticated;

-- AFTER (expected): both false.
select
  has_function_privilege('authenticated','public.request_withdrawal_v2(numeric)','EXECUTE') as auth_can_withdraw,
  has_table_privilege('authenticated','public.seller_withdrawals','UPDATE') as auth_update_withdrawals;

commit;

-- ROLLBACK (only if the owner reverses the decision):
-- begin;
-- grant execute on function public.request_withdrawal_v2(numeric) to authenticated;
-- grant insert, update, delete on public.seller_withdrawals to authenticated;
-- commit;

-- VERIFICATION QUERIES (run after apply, staging):
-- 1. anon and authenticated cannot execute the function:
--    select has_function_privilege('anon','public.request_withdrawal_v2(numeric)','EXECUTE') = false
--       and has_function_privilege('authenticated','public.request_withdrawal_v2(numeric)','EXECUTE') = false;
-- 2. Row count is unchanged and no new pending withdrawals appear:
--    select count(*) from public.seller_withdrawals;
-- 3. A test seller calling the RPC receives a permission error (run as that user in the API, not in SQL).

-- NOT INCLUDED (open decisions):
-- a. Double-settlement path between approve_withdrawal and mark_payout_settled (see WITHDRAWAL-CALL-CHAIN.md, point 8).
-- b. The misleading comment in approve_withdrawal ("funds actually leave the wallet now").
-- c. Wider grants on seller_wallets and seller_kyc (DELETE/INSERT for authenticated), pending dependency check.
