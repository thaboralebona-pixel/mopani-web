-- PHASE 4 / STEP 01 TESTS. Staging only. Runs the change, tests it, then ends with an exception so NOTHING persists.
-- Result is returned in the exception message. A passing run shows only "OK" and "denied" results.
DO $$
DECLARE
  s uuid := '11111111-1111-4111-8111-111111111111';
  wid uuid;
  r text := '';
  n int;
BEGIN
  SELECT id INTO wid FROM seller_wallets WHERE seller_id = s;
  r := r || format('BEFORE req=%s settle=%s approve=%s youth_anon=%s subs=%s drv_view=%s mar_view=%s; ',
    has_function_privilege('authenticated','public.request_withdrawal_v2(numeric)','EXECUTE'),
    has_function_privilege('authenticated','public.mark_payout_settled(uuid,numeric,text)','EXECUTE'),
    has_function_privilege('authenticated','public.approve_withdrawal(bigint)','EXECUTE'),
    has_function_privilege('anon','public.sa_id_is_youth(text)','EXECUTE'),
    has_function_privilege('authenticated','public.request_subscription(text)','EXECUTE'),
    has_table_privilege('authenticated','public.public_driver_profiles','SELECT'),
    has_table_privilege('authenticated','public.public_marshal_profiles','SELECT'));

  -- apply (same statements as PHASE4-01-staging-lockdown.sql, minus begin/commit)
  REVOKE EXECUTE ON FUNCTION public.request_withdrawal_v2(numeric) FROM public, anon, authenticated;
  REVOKE EXECUTE ON FUNCTION public.request_withdrawal(uuid, numeric) FROM public, anon, authenticated;
  REVOKE EXECUTE ON FUNCTION public.mark_payout_settled(uuid, numeric, text) FROM public, anon, authenticated;
  REVOKE EXECUTE ON FUNCTION public.approve_withdrawal(bigint) FROM public, anon, authenticated;
  REVOKE INSERT, UPDATE, DELETE ON public.seller_withdrawals FROM authenticated;
  REVOKE DELETE ON public.seller_wallets FROM authenticated;
  REVOKE SELECT ON public.public_driver_profiles, public.public_marshal_profiles FROM anon, authenticated;
  REVOKE EXECUTE ON FUNCTION public.sa_id_is_youth(text) FROM public, anon, authenticated;
  REVOKE EXECUTE ON FUNCTION public.request_subscription(text) FROM public, anon, authenticated;

  r := r || format('AFTER req=%s settle=%s approve=%s youth_anon=%s subs=%s drv_view=%s mar_view=%s; ',
    has_function_privilege('authenticated','public.request_withdrawal_v2(numeric)','EXECUTE'),
    has_function_privilege('authenticated','public.mark_payout_settled(uuid,numeric,text)','EXECUTE'),
    has_function_privilege('authenticated','public.approve_withdrawal(bigint)','EXECUTE'),
    has_function_privilege('anon','public.sa_id_is_youth(text)','EXECUTE'),
    has_function_privilege('authenticated','public.request_subscription(text)','EXECUTE'),
    has_table_privilege('authenticated','public.public_driver_profiles','SELECT'),
    has_table_privilege('authenticated','public.public_marshal_profiles','SELECT'));

  PERFORM set_config('request.jwt.claims', json_build_object('sub', s, 'role', 'authenticated')::text, true);
  SET LOCAL ROLE authenticated;
  BEGIN PERFORM public.request_withdrawal_v2(10); r := r || 'N1 FAIL; ';
  EXCEPTION WHEN insufficient_privilege THEN r := r || 'N1 request denied OK; '; END;
  BEGIN PERFORM public.mark_payout_settled(wid, 10, 'x'); r := r || 'N2 FAIL; ';
  EXCEPTION WHEN insufficient_privilege THEN r := r || 'N2 settle denied OK; '; END;
  BEGIN UPDATE public.seller_withdrawals SET status = 'paid' WHERE seller_id = s; r := r || 'N3 FAIL; ';
  EXCEPTION WHEN insufficient_privilege THEN r := r || 'N3 direct update denied OK; '; END;
  BEGIN PERFORM 1 FROM public.public_driver_profiles LIMIT 1; r := r || 'N4 FAIL; ';
  EXCEPTION WHEN insufficient_privilege THEN r := r || 'N4 driver view denied OK; '; END;
  BEGIN PERFORM public.request_subscription('plan'); r := r || 'N5 FAIL; ';
  EXCEPTION WHEN insufficient_privilege THEN r := r || 'N5 subscription denied OK; '; END;
  -- positive control: owner can still read history and own wallet
  SELECT count(*) INTO n FROM public.seller_withdrawals WHERE seller_id = s;
  r := r || format('P1 history readable rows=%s; ', n);
  SELECT count(*) INTO n FROM public.seller_wallets WHERE seller_id = s;
  r := r || format('P2 own wallet readable rows=%s; ', n);
  RESET ROLE;

  RAISE EXCEPTION 'PHASE4-01 TEST RESULT (rolled back, nothing persisted): %', r;
END $$;
