-- Hardening and operational RPCs for One of One V1.

alter function public.log_audit_event(text, uuid, text, jsonb)
  set search_path = public;

alter function public.assert_item_is_actionable(uuid)
  set search_path = public;

alter function public.claim_item_ownership(uuid, text)
  set search_path = public;

alter function public.create_resale_listing(uuid, int)
  set search_path = public;

alter function public.complete_resale_order(uuid)
  set search_path = public;

create policy "authenticity public read" on public.authenticity_records
for select using (true);

alter table public.payments enable row level security;
alter table public.payout_ledgers enable row level security;
alter table public.royalty_ledgers enable row level security;
alter table public.platform_fee_ledgers enable row level security;
alter table public.ownership_transfers enable row level security;

create policy "payments participant read" on public.payments
for select using (
  exists (
    select 1
    from public.orders o
    where o.id = payments.order_id
      and (o.buyer_user_id = auth.uid() or o.seller_user_id = auth.uid() or public.is_admin_user())
  )
);

create policy "payout ledgers participant read" on public.payout_ledgers
for select using (seller_user_id = auth.uid() or public.is_admin_user());

create policy "royalty ledgers admin read" on public.royalty_ledgers
for select using (public.is_admin_user());

create policy "platform fee ledgers admin read" on public.platform_fee_ledgers
for select using (public.is_admin_user());

create policy "ownership transfers participant read" on public.ownership_transfers
for select using (from_owner_user_id = auth.uid() or to_owner_user_id = auth.uid() or public.is_admin_user());

create or replace view public.public_authenticity_items as
select
  ui.id,
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
    and status = 'active';

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

  if p_target_state not in ('stolen_flagged', 'frozen', 'claimed', 'archived') then
    raise exception 'Unsupported admin target state';
  end if;

  update public.unique_items
  set state = p_target_state,
      listed_price_cents = case when p_target_state in ('stolen_flagged', 'frozen') then null else listed_price_cents end
  where id = p_item_id;

  if p_target_state in ('stolen_flagged', 'frozen') then
    update public.listings
    set status = 'blocked_by_admin'
    where unique_item_id = p_item_id
      and status = 'active';
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
