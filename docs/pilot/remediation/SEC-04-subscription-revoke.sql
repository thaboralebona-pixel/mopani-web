-- SEC-04 REMEDIATION. DRAFT. STAGING ONLY. NOT APPLIED. Requires owner approval.
-- Purpose: stop signed-in sellers creating subscription payment rows while payments are disabled.
-- Unverified before apply: full side effects of request_subscription beyond its insert (read the complete body first).

begin;

-- BEFORE (expected: true)
select has_function_privilege('authenticated','public.request_subscription(text)','EXECUTE') as auth_before;

revoke execute on function public.request_subscription(text) from public, anon, authenticated;

-- AFTER (expected: false)
select has_function_privilege('authenticated','public.request_subscription(text)','EXECUTE') as auth_after;

rollback; -- dry run only. Change to commit after owner approval.

-- ROLLBACK (after a committed apply):
-- grant execute on function public.request_subscription(text) to authenticated;
