-- Admin read gateways that enforce admin-only access before returning operational views.

revoke select on public.admin_dashboard_overview from authenticated;
revoke select on public.admin_customer_overview from authenticated;
revoke select on public.admin_listing_queue from authenticated;
revoke select on public.admin_dispute_queue from authenticated;
revoke select on public.admin_order_queue from authenticated;
revoke select on public.admin_audit_feed from authenticated;

create or replace function public.get_admin_dashboard_overview()
returns setof public.admin_dashboard_overview
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  return query
  select *
  from public.admin_dashboard_overview;
end;
$$;

create or replace function public.get_admin_customer_overview()
returns setof public.admin_customer_overview
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  return query
  select *
  from public.admin_customer_overview
  order by created_at desc;
end;
$$;

create or replace function public.get_admin_listing_queue()
returns setof public.admin_listing_queue
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  return query
  select *
  from public.admin_listing_queue
  order by created_at desc;
end;
$$;

create or replace function public.get_admin_dispute_queue()
returns setof public.admin_dispute_queue
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  return query
  select *
  from public.admin_dispute_queue
  order by created_at desc;
end;
$$;

create or replace function public.get_admin_order_queue()
returns setof public.admin_order_queue
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  return query
  select *
  from public.admin_order_queue
  order by created_at desc;
end;
$$;

create or replace function public.get_admin_audit_feed()
returns setof public.admin_audit_feed
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  return query
  select *
  from public.admin_audit_feed
  order by created_at desc
  limit 150;
end;
$$;

grant execute on function public.get_admin_dashboard_overview() to authenticated;
grant execute on function public.get_admin_customer_overview() to authenticated;
grant execute on function public.get_admin_listing_queue() to authenticated;
grant execute on function public.get_admin_dispute_queue() to authenticated;
grant execute on function public.get_admin_order_queue() to authenticated;
grant execute on function public.get_admin_audit_feed() to authenticated;
