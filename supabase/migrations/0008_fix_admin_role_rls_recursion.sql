-- Fix admin role helper recursion under RLS.
-- current_app_role()/is_admin_user() are referenced by user_profiles policies,
-- so they must be able to read role state without re-entering the same RLS check.

create or replace function public.current_app_role()
returns public.app_role
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role from public.user_profiles where user_id = auth.uid()),
    'customer'::public.app_role
  )
$$;

create or replace function public.is_admin_user()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select public.current_app_role() in ('admin', 'owner', 'artist_manager', 'support')
$$;
