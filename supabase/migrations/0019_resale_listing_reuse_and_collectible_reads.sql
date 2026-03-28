-- Reuse historical listing rows for repeat resale and hide stale asking prices
-- outside active resale states.

create or replace function public.create_resale_listing(p_item_id uuid, p_price_cents int)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.unique_items;
  v_listing public.listings;
  v_listing_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if p_price_cents <= 0 then
    raise exception 'Listing price must be greater than zero';
  end if;

  v_item := public.assert_item_is_actionable(p_item_id);
  perform public.assert_current_owner(v_item, auth.uid());

  if v_item.state not in ('claimed', 'transferred') then
    raise exception 'Item is not eligible for resale';
  end if;

  select *
  into v_listing
  from public.listings
  where unique_item_id = p_item_id
  for update;

  if v_listing.id is not null and v_listing.status in ('active', 'sale_pending') then
    raise exception 'Listing already exists for this item';
  end if;

  if v_listing.id is null then
    insert into public.listings (
      unique_item_id,
      seller_user_id,
      asking_price_cents,
      status
    ) values (
      p_item_id,
      auth.uid(),
      p_price_cents,
      'active'
    )
    returning id into v_listing_id;
  else
    update public.listings
    set seller_user_id = auth.uid(),
        asking_price_cents = p_price_cents,
        status = 'active'
    where id = v_listing.id
    returning id into v_listing_id;
  end if;

  update public.unique_items
  set state = 'listed_for_resale',
      listed_price_cents = p_price_cents
  where id = p_item_id;

  perform public.log_audit_event(
    'listing',
    v_listing_id,
    'create_listing',
    jsonb_build_object('item_id', p_item_id, 'price_cents', p_price_cents)
  );
  return v_listing_id;
end;
$$;

create or replace view public.public_collectible_catalog as
select
  ui.id as item_id,
  ui.serial_number,
  ui.public_qr_token,
  ui.state,
  gp.name as garment_name,
  a.id as artwork_id,
  a.title as artwork_title,
  a.story,
  a.provenance_proof,
  ar.id as artist_id,
  ar.display_name as artist_name,
  ar.authenticity_statement,
  authrec.authenticity_status,
  authrec.public_story,
  coalesce(l.id, null) as listing_id,
  case
    when ui.state = 'listed_for_resale'
      then coalesce(l.asking_price_cents, ui.listed_price_cents)
    else null
  end as asking_price_cents,
  (
    select count(*)::int
    from public.ownership_transfers ot
    where ot.unique_item_id = ui.id
      and ot.transfer_status = 'completed'
  ) as verified_transfer_count
from public.unique_items ui
join public.garment_products gp on gp.id = ui.garment_product_id
join public.artworks a on a.id = ui.artwork_id
join public.artists ar on ar.id = ui.artist_id
join public.authenticity_records authrec on authrec.unique_item_id = ui.id
left join public.listings l on l.unique_item_id = ui.id and l.status = 'active';

create or replace function public.get_my_collectibles()
returns table (
  item_id uuid,
  serial_number text,
  state public.item_state,
  garment_name text,
  artwork_id uuid,
  artwork_title text,
  story text,
  artist_id uuid,
  artist_name text,
  authenticity_status text,
  asking_price_cents int,
  verified_transfer_count int,
  acquired_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select
    ui.id as item_id,
    ui.serial_number,
    ui.state,
    gp.name as garment_name,
    a.id as artwork_id,
    a.title as artwork_title,
    a.story,
    ar.id as artist_id,
    ar.display_name as artist_name,
    authrec.authenticity_status,
    case
      when ui.state in ('listed_for_resale', 'sale_pending') then ui.listed_price_cents
      else null
    end as asking_price_cents,
    (
      select count(*)::int
      from public.ownership_transfers ot
      where ot.unique_item_id = ui.id
        and ot.transfer_status = 'completed'
    ) as verified_transfer_count,
    own.acquired_at
  from public.unique_items ui
  join public.garment_products gp on gp.id = ui.garment_product_id
  join public.artworks a on a.id = ui.artwork_id
  join public.artists ar on ar.id = ui.artist_id
  join public.authenticity_records authrec on authrec.unique_item_id = ui.id
  join public.ownership_records own on own.unique_item_id = ui.id and own.relinquished_at is null
  where own.owner_user_id = auth.uid()
  order by own.acquired_at desc
$$;
