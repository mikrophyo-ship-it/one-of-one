-- Admin operations contract for the One of One V1 console.

create or replace function public.derive_admin_released_state(p_item_id uuid)
returns public.item_state
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.unique_items;
  v_has_transfer boolean;
begin
  select * into v_item
  from public.unique_items
  where id = p_item_id;

  if not found then
    raise exception 'Item not found';
  end if;

  if v_item.current_owner_user_id is null then
    if v_item.state in ('in_inventory', 'minted', 'drafted', 'archived') then
      return v_item.state;
    end if;
    return 'sold_unclaimed';
  end if;

  select exists (
    select 1
    from public.ownership_transfers ot
    where ot.unique_item_id = p_item_id
      and ot.transfer_status = 'completed'
  ) into v_has_transfer;

  if v_has_transfer then
    return 'transferred';
  end if;

  return 'claimed';
end;
$$;

create or replace function public.admin_update_platform_settings(
  p_platform_fee_bps int,
  p_default_royalty_bps int,
  p_marketplace_rules jsonb default null,
  p_brand_settings jsonb default null
)
returns public.platform_settings
language plpgsql
security definer
set search_path = public
as $$
declare
  v_settings public.platform_settings;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  if p_platform_fee_bps < 0 or p_platform_fee_bps > 5000 then
    raise exception 'Platform fee must be between 0 and 5000 bps';
  end if;

  if p_default_royalty_bps < 0 or p_default_royalty_bps > 5000 then
    raise exception 'Default royalty must be between 0 and 5000 bps';
  end if;

  update public.platform_settings
  set platform_fee_bps = p_platform_fee_bps,
      default_royalty_bps = p_default_royalty_bps,
      marketplace_rules = coalesce(p_marketplace_rules, marketplace_rules),
      brand_settings = coalesce(p_brand_settings, brand_settings)
  where id = true
  returning * into v_settings;

  perform public.log_audit_event(
    'platform_settings',
    null,
    'admin_update_platform_settings',
    jsonb_build_object(
      'platform_fee_bps', p_platform_fee_bps,
      'default_royalty_bps', p_default_royalty_bps
    )
  );

  return v_settings;
end;
$$;

create or replace function public.admin_moderate_listing(
  p_listing_id uuid,
  p_action text,
  p_note text default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_listing public.listings;
  v_item public.unique_items;
  v_note_id uuid;
  v_release_state public.item_state;
  v_normalized_action text;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  v_normalized_action := lower(trim(coalesce(p_action, '')));
  if v_normalized_action not in ('block', 'restore', 'cancel') then
    raise exception 'Unsupported listing moderation action';
  end if;

  select * into v_listing
  from public.listings
  where id = p_listing_id
  for update;

  if not found then
    raise exception 'Listing not found';
  end if;

  select * into v_item
  from public.unique_items
  where id = v_listing.unique_item_id
  for update;

  if v_item.id is null then
    raise exception 'Item not found';
  end if;

  if v_normalized_action = 'restore' then
    if v_listing.status <> 'blocked_by_admin' then
      raise exception 'Only admin-blocked listings can be restored';
    end if;
    if v_item.state in ('disputed', 'frozen', 'stolen_flagged', 'archived') then
      raise exception 'Restricted items cannot return to the resale market';
    end if;
    perform public.assert_current_owner(v_item, v_listing.seller_user_id);

    update public.listings
    set status = 'active'
    where id = v_listing.id;

    update public.unique_items
    set state = 'listed_for_resale',
        listed_price_cents = v_listing.asking_price_cents
    where id = v_item.id;
  else
    v_release_state := public.derive_admin_released_state(v_item.id);

    update public.listings
    set status = case
      when v_normalized_action = 'cancel' then 'cancelled_by_admin'
      else 'blocked_by_admin'
    end
    where id = v_listing.id;

    if v_item.state in ('listed_for_resale', 'sale_pending') then
      update public.unique_items
      set state = v_release_state,
          listed_price_cents = null
      where id = v_item.id;
    end if;
  end if;

  insert into public.admin_notes (entity_type, entity_id, note, admin_user_id)
  values (
    'listing',
    v_listing.id,
    coalesce(
      p_note,
      case
        when v_normalized_action = 'restore' then 'Listing restored by admin.'
        when v_normalized_action = 'cancel' then 'Listing cancelled by admin moderation.'
        else 'Listing blocked by admin moderation.'
      end
    ),
    auth.uid()
  )
  returning id into v_note_id;

  perform public.log_audit_event(
    'listing',
    v_listing.id,
    'admin_moderate_listing',
    jsonb_build_object(
      'action', v_normalized_action,
      'item_id', v_item.id,
      'admin_note_id', v_note_id
    )
  );

  return v_note_id;
end;
$$;

create or replace function public.admin_update_dispute_status(
  p_dispute_id uuid,
  p_status public.dispute_status,
  p_note text default null,
  p_release_item boolean default false,
  p_release_target_state public.item_state default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_dispute public.disputes;
  v_item public.unique_items;
  v_note_id uuid;
  v_target_state public.item_state;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  select * into v_dispute
  from public.disputes
  where id = p_dispute_id
  for update;

  if not found then
    raise exception 'Dispute not found';
  end if;

  select * into v_item
  from public.unique_items
  where id = v_dispute.unique_item_id
  for update;

  if v_item.id is null then
    raise exception 'Item not found';
  end if;

  update public.disputes
  set status = p_status
  where id = v_dispute.id;

  if p_release_item then
    if p_status not in ('resolved', 'rejected') then
      raise exception 'Only resolved or rejected disputes can release an item';
    end if;

    v_target_state := coalesce(
      p_release_target_state,
      public.derive_admin_released_state(v_item.id)
    );

    if v_target_state in ('disputed', 'frozen', 'stolen_flagged', 'listed_for_resale', 'sale_pending') then
      raise exception 'Unsafe release target state';
    end if;

    update public.unique_items
    set state = v_target_state,
        listed_price_cents = null
    where id = v_item.id;
  end if;

  insert into public.admin_notes (entity_type, entity_id, note, admin_user_id)
  values (
    'dispute',
    v_dispute.id,
    coalesce(
      p_note,
      case
        when p_release_item then 'Dispute updated and item released by admin.'
        else 'Dispute updated by admin.'
      end
    ),
    auth.uid()
  )
  returning id into v_note_id;

  perform public.log_audit_event(
    'dispute',
    v_dispute.id,
    'admin_update_dispute_status',
    jsonb_build_object(
      'status', p_status,
      'item_id', v_item.id,
      'release_item', p_release_item,
      'release_target_state', v_target_state,
      'admin_note_id', v_note_id
    )
  );

  return v_note_id;
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

  if p_target_state not in (
    'in_inventory',
    'sold_unclaimed',
    'claimed',
    'transferred',
    'disputed',
    'stolen_flagged',
    'frozen',
    'archived'
  ) then
    raise exception 'Unsupported admin target state';
  end if;

  if p_target_state in ('listed_for_resale', 'sale_pending', 'drafted', 'minted') then
    raise exception 'Unsafe admin target state';
  end if;

  update public.unique_items
  set state = p_target_state,
      listed_price_cents = case
        when p_target_state in ('stolen_flagged', 'frozen', 'disputed', 'claimed', 'transferred', 'sold_unclaimed', 'in_inventory', 'archived')
          then null
        else listed_price_cents
      end
  where id = p_item_id;

  if p_target_state in ('stolen_flagged', 'frozen', 'disputed', 'claimed', 'transferred', 'sold_unclaimed', 'in_inventory', 'archived') then
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

create or replace view public.admin_dashboard_overview
with (security_invoker = true) as
select
  (select count(*)::int from public.disputes d where d.status in ('open', 'under_review')) as open_disputes,
  (select count(*)::int from public.listings l where l.status = 'active') as active_listings,
  (select count(*)::int from public.orders o where o.order_status = 'payment_pending') as payment_pending_orders,
  (select coalesce(sum(o.total_cents), 0)::int from public.orders o where o.order_status in ('paid', 'fulfilled')) as gross_sales_cents,
  (select coalesce(sum(amount_cents), 0)::int from public.royalty_ledgers) as royalty_cents,
  (select coalesce(sum(amount_cents), 0)::int from public.platform_fee_ledgers) as platform_fee_cents,
  (select count(*)::int from public.unique_items ui where ui.state = 'frozen') as frozen_items,
  (select count(*)::int from public.unique_items ui where ui.state = 'stolen_flagged') as stolen_items;

create or replace view public.admin_customer_overview
with (security_invoker = true) as
select
  up.user_id,
  up.display_name,
  up.username,
  up.role,
  up.created_at,
  (
    select count(*)::int
    from public.ownership_records r
    where r.owner_user_id = up.user_id
      and r.relinquished_at is null
  ) as owned_item_count,
  (
    select count(*)::int
    from public.disputes d
    where d.reported_by_user_id = up.user_id
      and d.status in ('open', 'under_review')
  ) as open_dispute_count,
  (
    select count(*)::int
    from public.orders o
    where o.buyer_user_id = up.user_id
  ) as buy_order_count,
  (
    select count(*)::int
    from public.orders o
    where o.seller_user_id = up.user_id
  ) as sell_order_count,
  (
    select max(al.created_at)
    from public.audit_logs al
    where al.actor_user_id = up.user_id
  ) as last_activity_at
from public.user_profiles up;

create or replace view public.admin_listing_queue
with (security_invoker = true) as
select
  l.id as listing_id,
  l.unique_item_id as item_id,
  l.seller_user_id,
  l.status as listing_status,
  l.asking_price_cents,
  l.created_at,
  ui.serial_number,
  ui.state as item_state,
  gp.name as garment_name,
  a.title as artwork_title,
  ar.display_name as artist_name,
  seller.display_name as seller_display_name,
  seller.username as seller_username
from public.listings l
join public.unique_items ui on ui.id = l.unique_item_id
join public.garment_products gp on gp.id = ui.garment_product_id
join public.artworks a on a.id = ui.artwork_id
join public.artists ar on ar.id = ui.artist_id
left join public.user_profiles seller on seller.user_id = l.seller_user_id;

create or replace view public.admin_dispute_queue
with (security_invoker = true) as
select
  d.id as dispute_id,
  d.unique_item_id as item_id,
  d.order_id,
  d.status as dispute_status,
  d.reason,
  d.details,
  d.created_at,
  d.reported_by_user_id,
  reporter.display_name as reporter_display_name,
  reporter.username as reporter_username,
  ui.serial_number,
  ui.state as item_state,
  gp.name as garment_name,
  a.title as artwork_title,
  ar.display_name as artist_name,
  (
    select l.status
    from public.listings l
    where l.unique_item_id = ui.id
    order by l.created_at desc
    limit 1
  ) as latest_listing_status
from public.disputes d
join public.unique_items ui on ui.id = d.unique_item_id
join public.garment_products gp on gp.id = ui.garment_product_id
join public.artworks a on a.id = ui.artwork_id
join public.artists ar on ar.id = ui.artist_id
left join public.user_profiles reporter on reporter.user_id = d.reported_by_user_id;

create or replace view public.admin_order_queue
with (security_invoker = true) as
select
  o.id as order_id,
  o.listing_id,
  o.order_status,
  o.subtotal_cents,
  o.total_cents,
  o.created_at,
  oi.unique_item_id as item_id,
  ui.serial_number,
  ui.state as item_state,
  gp.name as garment_name,
  a.title as artwork_title,
  ar.display_name as artist_name,
  buyer.display_name as buyer_display_name,
  seller.display_name as seller_display_name,
  l.status as listing_status,
  (
    select p.status
    from public.payments p
    where p.order_id = o.id
    order by p.created_at desc
    limit 1
  ) as payment_status,
  (
    select p.provider
    from public.payments p
    where p.order_id = o.id
    order by p.created_at desc
    limit 1
  ) as payment_provider,
  (
    select pl.status
    from public.payout_ledgers pl
    where pl.order_id = o.id
    order by pl.created_at desc
    limit 1
  ) as seller_payout_status,
  (
    select rl.status
    from public.royalty_ledgers rl
    where rl.order_id = o.id
    order by rl.created_at desc
    limit 1
  ) as royalty_status,
  (
    select pfl.status
    from public.platform_fee_ledgers pfl
    where pfl.order_id = o.id
    order by pfl.created_at desc
    limit 1
  ) as platform_fee_status
from public.orders o
join public.order_items oi on oi.order_id = o.id
join public.unique_items ui on ui.id = oi.unique_item_id
join public.garment_products gp on gp.id = ui.garment_product_id
join public.artworks a on a.id = ui.artwork_id
join public.artists ar on ar.id = ui.artist_id
left join public.listings l on l.id = o.listing_id
left join public.user_profiles buyer on buyer.user_id = o.buyer_user_id
left join public.user_profiles seller on seller.user_id = o.seller_user_id;

create or replace view public.admin_audit_feed
with (security_invoker = true) as
select
  al.id as audit_id,
  al.created_at,
  al.entity_type,
  al.entity_id,
  al.action,
  al.payload,
  actor.display_name as actor_display_name,
  actor.username as actor_username
from public.audit_logs al
left join public.user_profiles actor on actor.user_id = al.actor_user_id;

grant execute on function public.admin_update_platform_settings(int, int, jsonb, jsonb) to authenticated;
grant execute on function public.admin_moderate_listing(uuid, text, text) to authenticated;
grant execute on function public.admin_update_dispute_status(uuid, public.dispute_status, text, boolean, public.item_state) to authenticated;
grant select on public.admin_dashboard_overview to authenticated;
grant select on public.admin_customer_overview to authenticated;
grant select on public.admin_listing_queue to authenticated;
grant select on public.admin_dispute_queue to authenticated;
grant select on public.admin_order_queue to authenticated;
grant select on public.admin_audit_feed to authenticated;
