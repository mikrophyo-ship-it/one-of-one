-- Admin workflow helpers for making inventory visible and buyable.

drop function if exists public.get_admin_inventory_directory();
drop view if exists public.admin_inventory_directory;

create or replace view public.admin_inventory_directory
with (security_invoker = true) as
select
  ui.id as item_id,
  ui.serial_number,
  ar.display_name as artist_name,
  aw.title as artwork_title,
  gp.name as garment_name,
  ui.state as item_state,
  coalesce(owner_profile.display_name, 'Unassigned') as owner_display_label,
  authrec.id is not null as has_authenticity_record,
  authrec.authenticity_status,
  l.id as listing_id,
  l.status as listing_status,
  coalesce(l.asking_price_cents, ui.listed_price_cents) as asking_price_cents,
  authrec.id is not null as customer_visible,
  (
    authrec.id is not null
    and l.status = 'active'
    and coalesce(l.asking_price_cents, ui.listed_price_cents) is not null
    and ui.state not in ('disputed', 'frozen', 'stolen_flagged', 'archived')
  ) as buyable
from public.unique_items ui
join public.artists ar on ar.id = ui.artist_id
join public.artworks aw on aw.id = ui.artwork_id
join public.garment_products gp on gp.id = ui.garment_product_id
left join public.user_profiles owner_profile on owner_profile.user_id = ui.current_owner_user_id
left join public.authenticity_records authrec on authrec.unique_item_id = ui.id
left join public.listings l on l.unique_item_id = ui.id;

create or replace function public.get_admin_inventory_directory()
returns setof public.admin_inventory_directory
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  return query
  select * from public.admin_inventory_directory
  order by serial_number asc;
end;
$$;

create or replace function public.admin_create_item_authenticity_record(
  p_item_id uuid,
  p_authenticity_status text default 'verified_human_made',
  p_public_story text default null,
  p_visibility_label text default 'platform-verified'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.unique_items;
  v_authenticity_id uuid;
  v_story text;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  select * into v_item
  from public.unique_items
  where id = p_item_id
  for update;

  if not found then
    raise exception 'Inventory item not found';
  end if;

  select id into v_authenticity_id
  from public.authenticity_records
  where unique_item_id = p_item_id;

  if v_authenticity_id is not null then
    raise exception 'Authenticity record already exists';
  end if;

  select coalesce(nullif(trim(p_public_story), ''), aw.story)
    into v_story
  from public.artworks aw
  where aw.id = v_item.artwork_id;

  insert into public.authenticity_records (
    unique_item_id,
    authenticity_status,
    public_story,
    visibility_label
  ) values (
    p_item_id,
    coalesce(nullif(trim(p_authenticity_status), ''), 'verified_human_made'),
    coalesce(v_story, 'Authenticity record published by platform operations.'),
    coalesce(nullif(trim(p_visibility_label), ''), 'platform-verified')
  )
  returning id into v_authenticity_id;

  perform public.log_audit_event(
    'authenticity_record',
    v_authenticity_id,
    'admin_create_item_authenticity_record',
    jsonb_build_object('item_id', p_item_id)
  );

  return v_authenticity_id;
end;
$$;

create or replace function public.admin_upsert_item_listing(
  p_item_id uuid,
  p_asking_price_cents int,
  p_status text default 'active'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.unique_items;
  v_listing_id uuid;
  v_status text;
  v_seller_user_id uuid;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  if p_asking_price_cents is null or p_asking_price_cents <= 0 then
    raise exception 'Listing price must be greater than zero';
  end if;

  v_status := lower(trim(coalesce(p_status, 'active')));
  if v_status not in ('draft', 'active') then
    raise exception 'Unsupported listing status';
  end if;

  select * into v_item
  from public.unique_items
  where id = p_item_id
  for update;

  if not found then
    raise exception 'Inventory item not found';
  end if;

  if v_item.state in ('disputed', 'frozen', 'stolen_flagged', 'archived') then
    raise exception 'Restricted items cannot be listed';
  end if;

  if not exists (
    select 1
    from public.authenticity_records
    where unique_item_id = p_item_id
  ) then
    raise exception 'Create authenticity record first';
  end if;

  v_seller_user_id := v_item.current_owner_user_id;
  if v_seller_user_id is null then
    v_seller_user_id := auth.uid();

    update public.unique_items
    set current_owner_user_id = v_seller_user_id
    where id = p_item_id
      and current_owner_user_id is null;

    if not exists (
      select 1
      from public.ownership_records
      where unique_item_id = p_item_id
        and relinquished_at is null
    ) then
      insert into public.ownership_records (
        unique_item_id,
        owner_user_id,
        acquisition_type,
        visibility_label
      ) values (
        p_item_id,
        v_seller_user_id,
        'admin_inventory_publish',
        'platform_custody'
      );
    end if;
  end if;

  select id into v_listing_id
  from public.listings
  where unique_item_id = p_item_id
  for update;

  if v_listing_id is null then
    insert into public.listings (
      unique_item_id,
      seller_user_id,
      asking_price_cents,
      status
    ) values (
      p_item_id,
      v_seller_user_id,
      p_asking_price_cents,
      v_status
    )
    returning id into v_listing_id;
  else
    update public.listings
    set seller_user_id = v_seller_user_id,
        asking_price_cents = p_asking_price_cents,
        status = v_status
    where id = v_listing_id;
  end if;

  update public.unique_items
  set listed_price_cents = p_asking_price_cents,
      state = case
        when v_status = 'active' then 'listed_for_resale'
        else state
      end
  where id = p_item_id;

  perform public.log_audit_event(
    'listing',
    v_listing_id,
    'admin_upsert_item_listing',
    jsonb_build_object(
      'item_id', p_item_id,
      'asking_price_cents', p_asking_price_cents,
      'status', v_status
    )
  );

  return v_listing_id;
end;
$$;

grant execute on function public.get_admin_inventory_directory() to authenticated;
grant execute on function public.admin_create_item_authenticity_record(uuid, text, text, text) to authenticated;
grant execute on function public.admin_upsert_item_listing(uuid, int, text) to authenticated;
