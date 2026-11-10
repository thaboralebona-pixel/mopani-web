-- SEC-03 REMEDIATION. DRAFT. STAGING ONLY. NOT APPLIED. Requires owner approval.
-- Purpose: stop anonymous and signed-in callers submitting ID numbers to sa_id_is_youth.
-- Dependency check still required before apply: catalogue search for sa_id_is_youth in functions, views, triggers, policies.

begin;

-- BEFORE (expected: true, true)
select has_function_privilege('anon','public.sa_id_is_youth(text)','EXECUTE') as anon_before,
       has_function_privilege('authenticated','public.sa_id_is_youth(text)','EXECUTE') as auth_before;

revoke execute on function public.sa_id_is_youth(text) from public, anon, authenticated;

-- AFTER (expected: false, false)
select has_function_privilege('anon','public.sa_id_is_youth(text)','EXECUTE') as anon_after,
       has_function_privilege('authenticated','public.sa_id_is_youth(text)','EXECUTE') as auth_after;

rollback; -- dry run only. Change to commit after owner approval.

-- ROLLBACK (after a committed apply):
-- grant execute on function public.sa_id_is_youth(text) to anon, authenticated;
