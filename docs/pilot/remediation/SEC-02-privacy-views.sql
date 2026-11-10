-- SEC-02 REMEDIATION. DRAFT. STAGING ONLY. NOT APPLIED. Requires owner approval.
-- Purpose: stop signed-in users reading driver and marshal rows through owner-rights views.
-- Dependency check (10 Nov 2026): no function or view references either view; the web app does not query them.

begin;

-- BEFORE (expected): true for authenticated.
-- select has_table_privilege('authenticated','public.public_driver_profiles','SELECT');
-- select has_table_privilege('authenticated','public.public_marshal_profiles','SELECT');

revoke select on public.public_driver_profiles, public.public_marshal_profiles from authenticated, anon;

-- AFTER (expected): false.
select
  has_table_privilege('authenticated','public.public_driver_profiles','SELECT') as auth_driver,
  has_table_privilege('authenticated','public.public_marshal_profiles','SELECT') as auth_marshal,
  has_table_privilege('anon','public.public_driver_profiles','SELECT') as anon_driver;

commit;

-- ROLLBACK:
-- grant select on public.public_driver_profiles, public.public_marshal_profiles to authenticated;

-- VERIFICATION (staging, after apply):
-- 1. As a signed-in buyer, select from public_driver_profiles returns a permission error.
-- 2. Catalogue and quote still load in the web app.
