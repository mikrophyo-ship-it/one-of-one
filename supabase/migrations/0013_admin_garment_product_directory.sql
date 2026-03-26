-- Expose garment products to the admin catalog flow so inventory creation
-- can select a real foreign-key target instead of typing raw UUIDs.

create or replace view public.admin_garment_product_directory
with (security_invoker = true) as
select
  gp.id as garment_product_id,
  gp.sku,
  gp.name,
  gp.silhouette,
  gp.size_label,
  gp.colorway,
  gp.base_price_cents
from public.garment_products gp;

create or replace function public.get_admin_garment_product_directory()
returns setof public.admin_garment_product_directory
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  return query
  select * from public.admin_garment_product_directory
  order by name asc, sku asc;
end;
$$;

grant execute on function public.get_admin_garment_product_directory() to authenticated;
