-- V2 commercial maturity contract:
-- payments and payout automation, shipment logging, refunds,
-- customer saved items and notifications, and expanded admin CRUD/reporting.

alter table public.orders
  add column if not exists delivery_confirmed_at timestamptz,
  add column if not exists review_window_closes_at timestamptz,
  add column if not exists payout_released_at timestamptz;

alter table public.payments
  add column if not exists provider_session_reference text,
  add column if not exists provider_payload jsonb not null default '{}'::jsonb;

create table if not exists public.saved_collectibles (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  unique_item_id uuid not null references public.unique_items(id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now()),
  unique (user_id, unique_item_id)
);

create table if not exists public.shipment_events (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  status text not null,
  carrier text,
  tracking_number text,
  note text,
  provider_payload jsonb not null default '{}'::jsonb,
  occurred_at timestamptz not null default timezone('utc', now()),
  created_by_user_id uuid references public.users(id)
);

create table if not exists public.refunds (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  amount_cents int not null check (amount_cents > 0),
  reason text not null,
  note text,
  provider_reference text,
  status text not null default 'pending',
  created_at timestamptz not null default timezone('utc', now()),
  created_by_user_id uuid references public.users(id)
);

alter table public.saved_collectibles enable row level security;
alter table public.shipment_events enable row level security;
alter table public.refunds enable row level security;

drop policy if exists saved_collectibles_select_own on public.saved_collectibles;
create policy saved_collectibles_select_own on public.saved_collectibles
for select using (user_id = auth.uid() or public.is_admin_user());

drop policy if exists saved_collectibles_insert_own on public.saved_collectibles;
create policy saved_collectibles_insert_own on public.saved_collectibles
for insert with check (user_id = auth.uid() or public.is_admin_user());

drop policy if exists saved_collectibles_delete_own on public.saved_collectibles;
create policy saved_collectibles_delete_own on public.saved_collectibles
for delete using (user_id = auth.uid() or public.is_admin_user());

drop policy if exists shipment_events_select_order_participants on public.shipment_events;
create policy shipment_events_select_order_participants on public.shipment_events
for select using (
  exists (
    select 1
    from public.orders o
    where o.id = order_id
      and (o.buyer_user_id = auth.uid() or o.seller_user_id = auth.uid() or public.is_admin_user())
  )
);

drop policy if exists shipment_events_insert_admin_only on public.shipment_events;
create policy shipment_events_insert_admin_only on public.shipment_events
for insert with check (public.is_admin_user());

drop policy if exists refunds_select_order_participants on public.refunds;
create policy refunds_select_order_participants on public.refunds
for select using (
  exists (
    select 1
    from public.orders o
    where o.id = order_id
      and (o.buyer_user_id = auth.uid() or o.seller_user_id = auth.uid() or public.is_admin_user())
  )
);

drop policy if exists refunds_insert_admin_only on public.refunds;
create policy refunds_insert_admin_only on public.refunds
for insert with check (public.is_admin_user());

create or replace function public.get_my_saved_collectibles()
returns table (
  item_id uuid,
  saved_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select sc.unique_item_id as item_id, sc.created_at as saved_at
  from public.saved_collectibles sc
  where sc.user_id = auth.uid()
  order by sc.created_at desc;
$$;

create or replace function public.save_collectible(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  insert into public.saved_collectibles (user_id, unique_item_id)
  values (auth.uid(), p_item_id)
  on conflict (user_id, unique_item_id) do nothing;

  perform public.log_audit_event(
    'saved_collectible',
    p_item_id,
    'save_collectible',
    jsonb_build_object('user_id', auth.uid())
  );
end;
$$;

create or replace function public.remove_saved_collectible(p_item_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  delete from public.saved_collectibles
  where user_id = auth.uid()
    and unique_item_id = p_item_id;

  perform public.log_audit_event(
    'saved_collectible',
    p_item_id,
    'remove_saved_collectible',
    jsonb_build_object('user_id', auth.uid())
  );
end;
$$;

create or replace function public.get_my_notifications()
returns table (
  notification_id uuid,
  title text,
  body text,
  is_read boolean,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select n.id as notification_id,
         n.title,
         n.body,
         n.read_at is not null as is_read,
         n.created_at
  from public.notifications n
  where n.user_id = auth.uid()
  order by n.created_at desc
  limit 100;
$$;

create or replace function public.create_resale_checkout_session(
  p_listing_id uuid,
  p_provider text default 'stripe',
  p_success_url text default null,
  p_cancel_url text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order_id uuid;
  v_provider_reference text;
begin
  v_order_id := public.create_resale_order(p_listing_id);
  v_provider_reference := lower(coalesce(nullif(trim(p_provider), ''), 'stripe')) || '_' || replace(v_order_id::text, '-', '');

  insert into public.payments (
    order_id,
    provider,
    provider_reference,
    provider_session_reference,
    status,
    amount_cents
  )
  select
    o.id,
    lower(coalesce(nullif(trim(p_provider), ''), 'stripe')),
    v_provider_reference,
    'session_' || replace(o.id::text, '-', ''),
    'pending',
    o.total_cents
  from public.orders o
  where o.id = v_order_id;

  perform public.log_audit_event(
    'order',
    v_order_id,
    'create_resale_checkout_session',
    jsonb_build_object(
      'provider', lower(coalesce(nullif(trim(p_provider), ''), 'stripe')),
      'success_url', p_success_url,
      'cancel_url', p_cancel_url
    )
  );

  return jsonb_build_object(
    'order_id', v_order_id,
    'provider', lower(coalesce(nullif(trim(p_provider), ''), 'stripe')),
    'status', 'requires_action',
    'provider_reference', v_provider_reference,
    'checkout_url', case
      when p_success_url is null then null
      else p_success_url || case when strpos(p_success_url, '?') > 0 then '&' else '?' end || 'order_id=' || v_order_id::text
    end,
    'client_secret', 'cs_' || replace(v_order_id::text, '-', ''),
    'expires_at', timezone('utc', now()) + interval '30 minutes'
  );
end;
$$;

create or replace function public.mark_resale_payment_authorized(
  p_order_id uuid,
  p_provider text,
  p_provider_reference text,
  p_amount_cents int
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
  v_item_id uuid;
begin
  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.order_status <> 'payment_pending' then
    raise exception 'Order is not awaiting payment';
  end if;

  if v_order.total_cents <> p_amount_cents then
    raise exception 'Payment amount does not match order total';
  end if;

  update public.payments
  set provider = lower(trim(p_provider)),
      provider_reference = p_provider_reference,
      status = 'captured',
      amount_cents = p_amount_cents
  where order_id = p_order_id;

  update public.orders
  set order_status = 'paid',
      review_window_closes_at = timezone('utc', now()) + interval '48 hours'
  where id = p_order_id;

  select oi.unique_item_id into v_item_id
  from public.order_items oi
  where oi.order_id = p_order_id
  limit 1;

  insert into public.notifications (user_id, title, body)
  values
    (v_order.buyer_user_id, 'Payment authorized', 'Your order is now awaiting shipment and delivery review.'),
    (v_order.seller_user_id, 'Ship collectible', 'Payment is authorized. Record shipment events before delivery confirmation.');

  perform public.log_audit_event(
    'payment',
    p_order_id,
    'mark_resale_payment_authorized',
    jsonb_build_object(
      'provider', lower(trim(p_provider)),
      'provider_reference', p_provider_reference,
      'amount_cents', p_amount_cents
    )
  );

  return jsonb_build_object(
    'order_id', p_order_id,
    'item_id', v_item_id,
    'status', 'captured'
  );
end;
$$;

create or replace function public.record_order_shipment_event(
  p_order_id uuid,
  p_status text,
  p_carrier text default null,
  p_tracking_number text default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
  v_occurred_at timestamptz := timezone('utc', now());
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  insert into public.shipment_events (
    order_id,
    status,
    carrier,
    tracking_number,
    note,
    occurred_at,
    created_by_user_id
  ) values (
    p_order_id,
    lower(trim(p_status)),
    nullif(trim(p_carrier), ''),
    nullif(trim(p_tracking_number), ''),
    nullif(trim(p_note), ''),
    v_occurred_at,
    auth.uid()
  );

  insert into public.notifications (user_id, title, body)
  values (
    v_order.buyer_user_id,
    'Shipment update',
    'Order shipment status changed to ' || lower(trim(p_status)) || '.'
  );

  perform public.log_audit_event(
    'shipment',
    p_order_id,
    'record_order_shipment_event',
    jsonb_build_object(
      'status', lower(trim(p_status)),
      'carrier', p_carrier,
      'tracking_number', p_tracking_number
    )
  );

  return jsonb_build_object(
    'order_id', p_order_id,
    'status', lower(trim(p_status)),
    'carrier', p_carrier,
    'tracking_number', p_tracking_number,
    'note', p_note,
    'occurred_at', v_occurred_at
  );
end;
$$;

create or replace function public.confirm_resale_delivery(
  p_order_id uuid,
  p_release_payouts boolean default true,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
  v_item_id uuid;
  v_transfer_id uuid;
begin
  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if auth.uid() <> v_order.buyer_user_id and not public.is_admin_user() then
    raise exception 'Only the buyer or admin can confirm delivery';
  end if;

  if v_order.order_status <> 'paid' then
    raise exception 'Order must be paid before delivery confirmation';
  end if;

  update public.orders
  set delivery_confirmed_at = timezone('utc', now())
  where id = p_order_id;

  v_transfer_id := public.complete_resale_order(p_order_id);

  select oi.unique_item_id into v_item_id
  from public.order_items oi
  where oi.order_id = p_order_id
  limit 1;

  if p_release_payouts then
    update public.orders
    set payout_released_at = timezone('utc', now())
    where id = p_order_id;

    update public.payout_ledgers
    set status = 'released'
    where order_id = p_order_id;

    update public.royalty_ledgers
    set status = 'released'
    where order_id = p_order_id;

    update public.platform_fee_ledgers
    set status = 'captured'
    where order_id = p_order_id;
  end if;

  insert into public.notifications (user_id, title, body)
  values
    (v_order.buyer_user_id, 'Delivery confirmed', 'Ownership is now finalized on-platform.'),
    (v_order.seller_user_id, 'Payout release queued', 'Delivery is confirmed and the payout workflow has advanced.');

  perform public.log_audit_event(
    'order',
    p_order_id,
    'confirm_resale_delivery',
    jsonb_build_object(
      'transfer_id', v_transfer_id,
      'release_payouts', p_release_payouts,
      'note', p_note
    )
  );

  return jsonb_build_object(
    'order_id', p_order_id,
    'item_id', v_item_id,
    'transfer_id', v_transfer_id,
    'delivery_confirmed_at', timezone('utc', now())
  );
end;
$$;

create or replace function public.issue_order_refund(
  p_order_id uuid,
  p_amount_cents int,
  p_reason text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
  v_refund_id uuid;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if p_amount_cents <= 0 or p_amount_cents > v_order.total_cents then
    raise exception 'Refund amount is invalid';
  end if;

  insert into public.refunds (
    order_id,
    amount_cents,
    reason,
    note,
    provider_reference,
    status,
    created_by_user_id
  ) values (
    p_order_id,
    p_amount_cents,
    p_reason,
    p_note,
    'refund_' || replace(p_order_id::text, '-', ''),
    case when p_amount_cents = v_order.total_cents then 'refunded' else 'partially_refunded' end,
    auth.uid()
  ) returning id into v_refund_id;

  update public.payments
  set status = case when p_amount_cents = v_order.total_cents then 'refunded' else status end
  where order_id = p_order_id;

  insert into public.notifications (user_id, title, body)
  values (
    v_order.buyer_user_id,
    'Refund issued',
    'A refund of ' || p_amount_cents::text || ' cents has been recorded for your order.'
  );

  perform public.log_audit_event(
    'refund',
    v_refund_id,
    'issue_order_refund',
    jsonb_build_object('order_id', p_order_id, 'amount_cents', p_amount_cents, 'reason', p_reason)
  );

  return jsonb_build_object(
    'refund_id', v_refund_id,
    'order_id', p_order_id,
    'status', case when p_amount_cents = v_order.total_cents then 'refunded' else 'partially_refunded' end,
    'amount_cents', p_amount_cents,
    'reason', p_reason,
    'provider_reference', 'refund_' || replace(p_order_id::text, '-', ''),
    'created_at', timezone('utc', now())
  );
end;
$$;

create or replace view public.admin_artist_directory
with (security_invoker = true) as
select
  ar.id as artist_id,
  ar.display_name,
  ar.slug,
  ar.royalty_bps,
  ar.is_active,
  (select count(*)::int from public.artworks aw where aw.artist_id = ar.id) as artwork_count,
  (select count(*)::int from public.unique_items ui where ui.artist_id = ar.id) as inventory_count
from public.artists ar;

create or replace view public.admin_artwork_directory
with (security_invoker = true) as
select
  aw.id as artwork_id,
  aw.artist_id,
  ar.display_name as artist_name,
  aw.title,
  aw.creation_date,
  (select count(*)::int from public.unique_items ui where ui.artwork_id = aw.id) as inventory_count
from public.artworks aw
join public.artists ar on ar.id = aw.artist_id;

create or replace view public.admin_inventory_directory
with (security_invoker = true) as
select
  ui.id as item_id,
  ui.serial_number,
  ar.display_name as artist_name,
  aw.title as artwork_title,
  gp.name as garment_name,
  ui.state as item_state,
  coalesce(owner_profile.display_name, 'Unassigned') as owner_display_label
from public.unique_items ui
join public.artists ar on ar.id = ui.artist_id
join public.artworks aw on aw.id = ui.artwork_id
join public.garment_products gp on gp.id = ui.garment_product_id
left join public.user_profiles owner_profile on owner_profile.user_id = ui.current_owner_user_id;

create or replace view public.admin_finance_report
with (security_invoker = true) as
select
  o.id as order_id,
  coalesce((
    select p.status::text
    from public.payments p
    where p.order_id = o.id
    order by p.created_at desc
    limit 1
  ), 'none') as payment_status,
  coalesce((
    select se.status
    from public.shipment_events se
    where se.order_id = o.id
    order by se.occurred_at desc
    limit 1
  ), 'pending') as shipment_status,
  coalesce((
    select pl.status
    from public.payout_ledgers pl
    where pl.order_id = o.id
    order by pl.created_at desc
    limit 1
  ), 'pending') as seller_payout_status,
  coalesce((
    select rl.status
    from public.royalty_ledgers rl
    where rl.order_id = o.id
    order by rl.created_at desc
    limit 1
  ), 'pending') as royalty_status,
  coalesce((
    select pfl.status
    from public.platform_fee_ledgers pfl
    where pfl.order_id = o.id
    order by pfl.created_at desc
    limit 1
  ), 'pending') as platform_fee_status,
  o.total_cents
from public.orders o;

create or replace function public.get_admin_artist_directory()
returns setof public.admin_artist_directory
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  return query
  select * from public.admin_artist_directory
  order by display_name asc;
end;
$$;

create or replace function public.get_admin_artwork_directory()
returns setof public.admin_artwork_directory
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  return query
  select * from public.admin_artwork_directory
  order by title asc;
end;
$$;

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

create or replace function public.get_admin_finance_report()
returns setof public.admin_finance_report
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  return query
  select * from public.admin_finance_report
  order by order_id desc;
end;
$$;

create or replace function public.admin_upsert_artist(
  p_display_name text,
  p_slug text,
  p_royalty_bps int,
  p_authenticity_statement text,
  p_is_active boolean default true,
  p_artist_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_artist_id uuid;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  if p_artist_id is null then
    insert into public.artists (
      display_name,
      slug,
      royalty_bps,
      authenticity_statement,
      is_active
    ) values (
      p_display_name,
      p_slug,
      p_royalty_bps,
      p_authenticity_statement,
      p_is_active
    ) returning id into v_artist_id;
  else
    update public.artists
    set display_name = p_display_name,
        slug = p_slug,
        royalty_bps = p_royalty_bps,
        authenticity_statement = p_authenticity_statement,
        is_active = p_is_active
    where id = p_artist_id
    returning id into v_artist_id;
  end if;

  perform public.log_audit_event(
    'artist',
    v_artist_id,
    'admin_upsert_artist',
    jsonb_build_object('slug', p_slug, 'royalty_bps', p_royalty_bps)
  );

  return v_artist_id;
end;
$$;

create or replace function public.admin_upsert_artwork(
  p_artist_id uuid,
  p_title text,
  p_story text,
  p_provenance_proof text[] default '{}',
  p_creation_date timestamptz default null,
  p_artwork_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_artwork_id uuid;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  if p_artwork_id is null then
    insert into public.artworks (
      artist_id,
      title,
      story,
      provenance_proof,
      creation_date
    ) values (
      p_artist_id,
      p_title,
      p_story,
      to_jsonb(p_provenance_proof),
      p_creation_date::date
    ) returning id into v_artwork_id;
  else
    update public.artworks
    set artist_id = p_artist_id,
        title = p_title,
        story = p_story,
        provenance_proof = to_jsonb(p_provenance_proof),
        creation_date = p_creation_date::date
    where id = p_artwork_id
    returning id into v_artwork_id;
  end if;

  perform public.log_audit_event(
    'artwork',
    v_artwork_id,
    'admin_upsert_artwork',
    jsonb_build_object('artist_id', p_artist_id, 'title', p_title)
  );

  return v_artwork_id;
end;
$$;

create or replace function public.admin_upsert_inventory_item(
  p_artist_id uuid,
  p_artwork_id uuid,
  p_garment_product_id uuid,
  p_serial_number text,
  p_item_state public.item_state,
  p_item_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item_id uuid;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  if p_item_id is null then
    insert into public.unique_items (
      serial_number,
      artwork_id,
      artist_id,
      garment_product_id,
      state
    ) values (
      p_serial_number,
      p_artwork_id,
      p_artist_id,
      p_garment_product_id,
      p_item_state
    ) returning id into v_item_id;
  else
    update public.unique_items
    set serial_number = p_serial_number,
        artwork_id = p_artwork_id,
        artist_id = p_artist_id,
        garment_product_id = p_garment_product_id,
        state = p_item_state
    where id = p_item_id
    returning id into v_item_id;
  end if;

  perform public.log_audit_event(
    'unique_item',
    v_item_id,
    'admin_upsert_inventory_item',
    jsonb_build_object('serial_number', p_serial_number, 'state', p_item_state)
  );

  return v_item_id;
end;
$$;

create or replace view public.admin_dashboard_overview
with (security_invoker = true) as
select
  (select count(*)::int from public.disputes d where d.status in ('open', 'under_review')) as open_disputes,
  (select count(*)::int from public.listings l where l.status = 'active') as active_listings,
  (select count(*)::int from public.orders o where o.order_status = 'payment_pending') as payment_pending_orders,
  (select count(*)::int from public.orders o where o.order_status = 'paid' and o.delivery_confirmed_at is null) as delivery_pending_orders,
  (select count(*)::int from public.orders o where o.order_status = 'fulfilled' and o.payout_released_at is null) as payout_pending_orders,
  (select count(*)::int from public.refunds r where r.status in ('pending', 'partially_refunded')) as refund_pending_orders,
  (select coalesce(sum(o.total_cents), 0)::int from public.orders o where o.order_status in ('paid', 'fulfilled')) as gross_sales_cents,
  (select coalesce(sum(amount_cents), 0)::int from public.royalty_ledgers) as royalty_cents,
  (select coalesce(sum(amount_cents), 0)::int from public.platform_fee_ledgers) as platform_fee_cents,
  (select count(*)::int from public.unique_items ui where ui.state = 'frozen') as frozen_items,
  (select count(*)::int from public.unique_items ui where ui.state = 'stolen_flagged') as stolen_items;

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
    select se.status
    from public.shipment_events se
    where se.order_id = o.id
    order by se.occurred_at desc
    limit 1
  ) as shipment_status,
  (
    select se.carrier
    from public.shipment_events se
    where se.order_id = o.id
    order by se.occurred_at desc
    limit 1
  ) as shipment_carrier,
  (
    select se.tracking_number
    from public.shipment_events se
    where se.order_id = o.id
    order by se.occurred_at desc
    limit 1
  ) as tracking_number,
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

grant execute on function public.get_my_saved_collectibles() to authenticated;
grant execute on function public.save_collectible(uuid) to authenticated;
grant execute on function public.remove_saved_collectible(uuid) to authenticated;
grant execute on function public.get_my_notifications() to authenticated;
grant execute on function public.create_resale_checkout_session(uuid, text, text, text) to authenticated;
grant execute on function public.mark_resale_payment_authorized(uuid, text, text, int) to authenticated;
grant execute on function public.confirm_resale_delivery(uuid, boolean, text) to authenticated;
grant execute on function public.record_order_shipment_event(uuid, text, text, text, text) to authenticated;
grant execute on function public.issue_order_refund(uuid, int, text, text) to authenticated;
grant execute on function public.get_admin_artist_directory() to authenticated;
grant execute on function public.get_admin_artwork_directory() to authenticated;
grant execute on function public.get_admin_inventory_directory() to authenticated;
grant execute on function public.get_admin_finance_report() to authenticated;
grant execute on function public.admin_upsert_artist(text, text, int, text, boolean, uuid) to authenticated;
grant execute on function public.admin_upsert_artwork(uuid, text, text, text[], timestamptz, uuid) to authenticated;
grant execute on function public.admin_upsert_inventory_item(uuid, uuid, uuid, text, public.item_state, uuid) to authenticated;
