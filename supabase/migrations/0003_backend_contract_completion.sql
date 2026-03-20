-- Contract completion for One of One V1 backend.

create or replace function public.handle_auth_user_created()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.users (id)
  values (new.id)
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_auth_user_created();

create or replace function public.upsert_my_profile(
  p_display_name text,
  p_username text,
  p_avatar_url text default null
)
returns public.user_profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if length(trim(coalesce(p_display_name, ''))) = 0 then
    raise exception 'Display name is required';
  end if;

  if length(trim(coalesce(p_username, ''))) = 0 then
    raise exception 'Username is required';
  end if;

  insert into public.users (id)
  values (auth.uid())
  on conflict (id) do nothing;

  insert into public.user_profiles (user_id, display_name, username, avatar_url)
  values (auth.uid(), trim(p_display_name), lower(trim(p_username)), p_avatar_url)
  on conflict (user_id) do update set
    display_name = excluded.display_name,
    username = excluded.username,
    avatar_url = excluded.avatar_url
  returning * into v_profile;

  perform public.log_audit_event('user_profile', auth.uid(), 'upsert_my_profile', '{}'::jsonb);
  return v_profile;
end;
$$;

create or replace function public.admin_set_user_role(
  p_user_id uuid,
  p_role public.app_role
)
returns public.user_profiles
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  update public.user_profiles
  set role = p_role
  where user_id = p_user_id
  returning * into v_profile;

  if v_profile.user_id is null then
    raise exception 'Profile not found';
  end if;

  perform public.log_audit_event('user_profile', p_user_id, 'admin_set_user_role', jsonb_build_object('role', p_role));
  return v_profile;
end;
$$;

alter table public.unique_items
  add column if not exists claim_code_consumed_at timestamptz,
  add column if not exists claim_code_consumed_by uuid references public.users(id),
  add column if not exists claimed_at timestamptz;

create or replace function public.assert_current_owner(
  p_item public.unique_items,
  p_owner_id uuid
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if p_item.current_owner_user_id is distinct from p_owner_id then
    raise exception 'Current owner mismatch';
  end if;

  if not exists (
    select 1
    from public.ownership_records r
    where r.unique_item_id = p_item.id
      and r.owner_user_id = p_owner_id
      and r.relinquished_at is null
  ) then
    raise exception 'Open ownership record not found for current owner';
  end if;
end;
$$;

create or replace function public.claim_item_ownership(p_item_id uuid, p_claim_code text)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.unique_items;
  v_profile public.user_profiles;
  v_ownership_id uuid;
begin
  select * into v_profile from public.user_profiles where user_id = auth.uid();
  if v_profile.user_id is null then
    raise exception 'Profile required before claim';
  end if;

  v_item := public.assert_item_is_actionable(p_item_id);
  if v_item.state <> 'sold_unclaimed' then
    raise exception 'Item is not claimable';
  end if;
  if v_item.claim_code_consumed_at is not null then
    raise exception 'Claim code already used';
  end if;
  if v_item.hidden_claim_code_hash <> encode(digest(p_claim_code, 'sha256'), 'hex') then
    raise exception 'Claim code invalid';
  end if;
  if exists (
    select 1 from public.ownership_records
    where unique_item_id = p_item_id and relinquished_at is null
  ) then
    raise exception 'Ownership already claimed';
  end if;

  update public.unique_items
  set current_owner_user_id = auth.uid(),
      state = 'claimed',
      claim_code_consumed_at = timezone('utc', now()),
      claim_code_consumed_by = auth.uid(),
      claimed_at = timezone('utc', now())
  where id = p_item_id;

  insert into public.ownership_records (unique_item_id, owner_user_id, acquisition_type)
  values (p_item_id, auth.uid(), 'claim')
  returning id into v_ownership_id;

  perform public.log_audit_event(
    'unique_item',
    p_item_id,
    'claim_item',
    jsonb_build_object('ownership_record_id', v_ownership_id, 'claim_code_consumed', true)
  );
  return v_ownership_id;
end;
$$;

create or replace function public.create_resale_listing(p_item_id uuid, p_price_cents int)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.unique_items;
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

  if exists (
    select 1 from public.listings
    where unique_item_id = p_item_id
      and status in ('active', 'sale_pending')
  ) then
    raise exception 'Listing already exists for this item';
  end if;

  insert into public.listings (unique_item_id, seller_user_id, asking_price_cents, status)
  values (p_item_id, auth.uid(), p_price_cents, 'active')
  returning id into v_listing_id;

  update public.unique_items
  set state = 'listed_for_resale', listed_price_cents = p_price_cents
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

create or replace function public.create_resale_order(p_listing_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_listing public.listings;
  v_item public.unique_items;
  v_order_id uuid;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_listing
  from public.listings
  where id = p_listing_id
  for update;

  if not found then
    raise exception 'Listing not found';
  end if;

  if v_listing.status <> 'active' then
    raise exception 'Listing is not available for checkout';
  end if;

  if v_listing.seller_user_id = auth.uid() then
    raise exception 'Seller cannot buy their own listing';
  end if;

  v_item := public.assert_item_is_actionable(v_listing.unique_item_id);
  perform public.assert_current_owner(v_item, v_listing.seller_user_id);

  if v_item.state <> 'listed_for_resale' then
    raise exception 'Item is not currently listed for resale';
  end if;

  insert into public.orders (
    buyer_user_id,
    seller_user_id,
    listing_id,
    order_status,
    subtotal_cents,
    total_cents
  ) values (
    auth.uid(),
    v_listing.seller_user_id,
    v_listing.id,
    'payment_pending',
    v_listing.asking_price_cents,
    v_listing.asking_price_cents
  ) returning id into v_order_id;

  insert into public.order_items (order_id, unique_item_id, unit_price_cents)
  values (v_order_id, v_listing.unique_item_id, v_listing.asking_price_cents);

  update public.listings
  set status = 'sale_pending'
  where id = v_listing.id;

  update public.unique_items
  set state = 'sale_pending'
  where id = v_listing.unique_item_id;

  perform public.log_audit_event('order', v_order_id, 'create_resale_order', jsonb_build_object('listing_id', p_listing_id));
  return v_order_id;
end;
$$;

create or replace function public.complete_resale_order(p_order_id uuid)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
  v_listing public.listings;
  v_item public.unique_items;
  v_platform_fee_bps int;
  v_royalty_bps int;
  v_platform_fee int;
  v_royalty_fee int;
  v_seller_payout int;
  v_transfer_id uuid;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.order_status <> 'paid' then
    raise exception 'Order must be paid before ownership transfer';
  end if;

  if not exists (
    select 1 from public.payments p
    where p.order_id = v_order.id
      and p.status = 'captured'
  ) then
    raise exception 'Captured payment record required before transfer';
  end if;

  select * into v_listing from public.listings where id = v_order.listing_id for update;
  if v_listing.status not in ('sale_pending', 'active') then
    raise exception 'Listing is not in a transferable state';
  end if;

  v_item := public.assert_item_is_actionable(v_listing.unique_item_id);
  perform public.assert_current_owner(v_item, v_order.seller_user_id);

  if v_item.state not in ('sale_pending', 'listed_for_resale') then
    raise exception 'Item is not in a transferable resale state';
  end if;

  select platform_fee_bps, default_royalty_bps into v_platform_fee_bps, v_royalty_bps from public.platform_settings where id = true;
  select coalesce(royalty_bps, v_royalty_bps) into v_royalty_bps from public.artists where id = v_item.artist_id;

  v_platform_fee := round(v_order.total_cents * v_platform_fee_bps / 10000.0);
  v_royalty_fee := round(v_order.total_cents * v_royalty_bps / 10000.0);
  v_seller_payout := v_order.total_cents - v_platform_fee - v_royalty_fee;

  if v_seller_payout < 0 then
    raise exception 'Invalid payout calculation';
  end if;

  update public.ownership_records
  set relinquished_at = timezone('utc', now())
  where unique_item_id = v_item.id and relinquished_at is null;

  insert into public.ownership_records (unique_item_id, owner_user_id, acquisition_type)
  values (v_item.id, v_order.buyer_user_id, 'resale_checkout');

  update public.unique_items
  set current_owner_user_id = v_order.buyer_user_id,
      state = 'transferred',
      listed_price_cents = null
  where id = v_item.id;

  update public.listings
  set status = 'sold'
  where id = v_listing.id;

  update public.orders
  set order_status = 'fulfilled'
  where id = v_order.id;

  insert into public.payout_ledgers (order_id, seller_user_id, amount_cents)
  values (v_order.id, v_order.seller_user_id, v_seller_payout);

  insert into public.royalty_ledgers (order_id, artist_id, amount_cents)
  values (v_order.id, v_item.artist_id, v_royalty_fee);

  insert into public.platform_fee_ledgers (order_id, amount_cents)
  values (v_order.id, v_platform_fee);

  insert into public.ownership_transfers (
    unique_item_id,
    from_owner_user_id,
    to_owner_user_id,
    order_id,
    transfer_status,
    transfer_source
  ) values (
    v_item.id,
    v_order.seller_user_id,
    v_order.buyer_user_id,
    v_order.id,
    'completed',
    'marketplace_checkout'
  ) returning id into v_transfer_id;

  perform public.log_audit_event(
    'order',
    v_order.id,
    'complete_resale_order',
    jsonb_build_object(
      'transfer_id', v_transfer_id,
      'platform_fee_cents', v_platform_fee,
      'artist_royalty_cents', v_royalty_fee,
      'seller_payout_cents', v_seller_payout
    )
  );
  return v_transfer_id;
end;
$$;

create or replace function public.record_resale_payment_and_transfer(
  p_order_id uuid,
  p_provider text,
  p_provider_reference text,
  p_amount_cents int
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
  v_payment_id uuid;
  v_transfer_id uuid;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.order_status <> 'payment_pending' then
    raise exception 'Order is not awaiting payment';
  end if;

  if v_order.total_cents <> p_amount_cents then
    raise exception 'Payment amount does not match order total';
  end if;

  insert into public.payments (order_id, provider, provider_reference, status, amount_cents)
  values (p_order_id, p_provider, p_provider_reference, 'captured', p_amount_cents)
  returning id into v_payment_id;

  update public.orders
  set order_status = 'paid'
  where id = p_order_id;

  v_transfer_id := public.complete_resale_order(p_order_id);

  perform public.log_audit_event(
    'payment',
    v_payment_id,
    'record_resale_payment_and_transfer',
    jsonb_build_object('order_id', p_order_id, 'transfer_id', v_transfer_id)
  );
  return v_transfer_id;
end;
$$;

create or replace function public.open_dispute(
  p_item_id uuid,
  p_reason text,
  p_details text default null,
  p_freeze_item boolean default false
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.unique_items;
  v_dispute_id uuid;
  v_new_state public.item_state;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_item
  from public.unique_items
  where id = p_item_id
  for update;

  if not found then
    raise exception 'Item not found';
  end if;

  if v_item.current_owner_user_id is distinct from auth.uid()
     and not exists (
       select 1 from public.orders o
       join public.order_items oi on oi.order_id = o.id
       where oi.unique_item_id = p_item_id
         and o.buyer_user_id = auth.uid()
     )
     and not public.is_admin_user() then
    raise exception 'Only the recorded owner, buyer, or admin can open a dispute';
  end if;

  v_new_state := case when p_freeze_item then 'frozen'::public.item_state else 'disputed'::public.item_state end;

  insert into public.disputes (unique_item_id, reported_by_user_id, reason, details, status)
  values (p_item_id, auth.uid(), p_reason, p_details, 'open')
  returning id into v_dispute_id;

  update public.unique_items
  set state = v_new_state,
      listed_price_cents = null
  where id = p_item_id;

  update public.listings
  set status = 'blocked_by_dispute'
  where unique_item_id = p_item_id
    and status in ('active', 'sale_pending');

  perform public.log_audit_event(
    'dispute',
    v_dispute_id,
    'open_dispute',
    jsonb_build_object('item_id', p_item_id, 'new_state', v_new_state, 'freeze_item', p_freeze_item)
  );

  return v_dispute_id;
end;
$$;

create or replace function public.admin_flag_item_status(
  p_item_id uuid,
  p_target_state public.item_state,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_note_id uuid;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  if p_target_state not in ('stolen_flagged', 'frozen', 'claimed', 'archived', 'disputed') then
    raise exception 'Unsupported admin target state';
  end if;

  update public.unique_items
  set state = p_target_state,
      listed_price_cents = case when p_target_state in ('stolen_flagged', 'frozen', 'disputed') then null else listed_price_cents end
  where id = p_item_id;

  if p_target_state in ('stolen_flagged', 'frozen', 'disputed') then
    update public.listings
    set status = 'blocked_by_admin'
    where unique_item_id = p_item_id
      and status in ('active', 'sale_pending');
  end if;

  insert into public.admin_notes (entity_type, entity_id, note, admin_user_id)
  values ('unique_item', p_item_id, coalesce(p_note, 'Status updated by admin control.'), auth.uid())
  returning id into v_note_id;

  perform public.log_audit_event(
    'unique_item',
    p_item_id,
    'admin_flag_item_status',
    jsonb_build_object('target_state', p_target_state, 'admin_note_id', v_note_id)
  );

  return v_note_id;
end;
$$;

drop view if exists public.public_authenticity_items;
create view public.public_authenticity_items as
select
  ui.public_qr_token,
  ui.serial_number,
  ui.state,
  gp.name as garment_name,
  a.title as artwork_title,
  a.story,
  ar.display_name as artist_name,
  authrec.authenticity_status,
  authrec.public_story,
  case
    when ui.state in ('stolen_flagged', 'frozen') then 'restricted ownership status'
    when ui.state = 'disputed' then 'under dispute review'
    when ui.state = 'listed_for_resale' then 'listed for verified resale'
    when ui.state = 'sold_unclaimed' then 'awaiting claim'
    else 'platform verified'
  end as ownership_visibility,
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
join public.authenticity_records authrec on authrec.unique_item_id = ui.id;

create or replace function public.get_public_authenticity_by_qr_token(p_public_qr_token text)
returns public.public_authenticity_items
language sql
security definer
set search_path = public
stable
as $$
  select *
  from public.public_authenticity_items
  where public_qr_token = p_public_qr_token
$$;

create or replace view public.public_marketplace_listings as
select
  l.id as listing_id,
  ui.id as item_id,
  ui.serial_number,
  ui.state,
  gp.name as garment_name,
  a.title as artwork_title,
  ar.display_name as artist_name,
  l.asking_price_cents,
  (
    select count(*)::int
    from public.ownership_transfers ot
    where ot.unique_item_id = ui.id
      and ot.transfer_status = 'completed'
  ) as verified_transfer_count
from public.listings l
join public.unique_items ui on ui.id = l.unique_item_id
join public.garment_products gp on gp.id = ui.garment_product_id
join public.artworks a on a.id = ui.artwork_id
join public.artists ar on ar.id = ui.artist_id
where l.status = 'active'
  and ui.state = 'listed_for_resale';

drop policy if exists "unique items public authenticity read" on public.unique_items;
drop policy if exists "listings public read" on public.listings;
drop policy if exists "authenticity public read" on public.authenticity_records;

create policy "unique items owner or admin read" on public.unique_items
for select using (current_owner_user_id = auth.uid() or public.is_admin_user());

create policy "listings seller or admin read" on public.listings
for select using (seller_user_id = auth.uid() or public.is_admin_user());

create policy "authenticity owner or admin read" on public.authenticity_records
for select using (
  exists (
    select 1
    from public.unique_items ui
    where ui.id = authenticity_records.unique_item_id
      and (ui.current_owner_user_id = auth.uid() or public.is_admin_user())
  )
);

grant select on public.public_authenticity_items to anon, authenticated;
grant select on public.public_marketplace_listings to anon, authenticated;
grant execute on function public.get_public_authenticity_by_qr_token(text) to anon, authenticated;
grant execute on function public.upsert_my_profile(text, text, text) to authenticated;
grant execute on function public.claim_item_ownership(uuid, text) to authenticated;
grant execute on function public.create_resale_listing(uuid, int) to authenticated;
grant execute on function public.create_resale_order(uuid) to authenticated;
grant execute on function public.record_resale_payment_and_transfer(uuid, text, text, int) to authenticated;
grant execute on function public.open_dispute(uuid, text, text, boolean) to authenticated;
grant execute on function public.admin_flag_item_status(uuid, public.item_state, text) to authenticated;
grant execute on function public.admin_set_user_role(uuid, public.app_role) to authenticated;
