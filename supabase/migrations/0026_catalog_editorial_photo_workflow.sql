drop policy if exists "garment editorial admin delete" on storage.objects;
create policy "garment editorial admin delete" on storage.objects
for delete to authenticated using (
  bucket_id = 'garment-editorial'
  and public.is_admin_user()
);

create or replace function public.admin_attach_item_media_asset(
  p_item_id uuid,
  p_storage_bucket text,
  p_storage_path text,
  p_media_type text,
  p_visibility text default 'public'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_asset_id uuid;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  if not exists (select 1 from public.unique_items ui where ui.id = p_item_id) then
    raise exception 'Inventory item not found';
  end if;

  if exists (
    select 1
    from public.media_assets ma
    where ma.linked_entity_type = 'unique_item'
      and ma.linked_entity_id = p_item_id
      and ma.storage_bucket = 'garment-editorial'
  ) then
    raise exception 'Editorial image already attached for this item';
  end if;

  insert into public.media_assets (
    storage_bucket,
    storage_path,
    media_type,
    visibility,
    linked_entity_type,
    linked_entity_id
  ) values (
    p_storage_bucket,
    p_storage_path,
    p_media_type,
    coalesce(nullif(trim(p_visibility), ''), 'public'),
    'unique_item',
    p_item_id
  )
  returning id into v_asset_id;

  perform public.log_audit_event(
    'media_asset',
    v_asset_id,
    'admin_attach_item_media_asset',
    jsonb_build_object(
      'item_id', p_item_id,
      'storage_bucket', p_storage_bucket,
      'storage_path', p_storage_path,
      'media_type', p_media_type
    )
  );

  return v_asset_id;
end;
$$;

create or replace function public.admin_remove_item_media_assets(
  p_item_id uuid
)
returns table (
  storage_bucket text,
  storage_path text
)
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  if not exists (select 1 from public.unique_items ui where ui.id = p_item_id) then
    raise exception 'Inventory item not found';
  end if;

  if not exists (
    select 1
    from public.media_assets ma
    where ma.linked_entity_type = 'unique_item'
      and ma.linked_entity_id = p_item_id
      and ma.storage_bucket = 'garment-editorial'
  ) then
    raise exception 'Editorial image not found for this item';
  end if;

  return query
  with deleted_assets as (
    delete from public.media_assets ma
    where ma.linked_entity_type = 'unique_item'
      and ma.linked_entity_id = p_item_id
      and ma.storage_bucket = 'garment-editorial'
    returning ma.id, ma.storage_bucket, ma.storage_path
  )
  select da.storage_bucket, da.storage_path
  from deleted_assets da;

  perform public.log_audit_event(
    'unique_item',
    p_item_id,
    'admin_remove_item_media_assets',
    jsonb_build_object('item_id', p_item_id, 'storage_bucket', 'garment-editorial')
  );
end;
$$;

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
  ) as buyable,
  (authrec.id is not null and nullif(trim(ui.public_qr_token), '') is not null) as qr_ready,
  (
    authrec.id is not null
    and nullif(trim(ui.public_qr_token), '') is not null
    and ui.claim_code_consumed_at is null
    and claim_ops.claim_packet_generated_at is null
    and ui.state in ('drafted', 'minted', 'in_inventory', 'sold_unclaimed')
  ) as claim_packet_ready,
  case
    when ui.claim_code_consumed_at is not null then 'consumed'
    when claim_ops.claim_code_revealed_at is not null then 'revealed_once'
    when authrec.id is null then 'awaiting_authenticity'
    when nullif(trim(ui.public_qr_token), '') is null then 'qr_missing'
    when ui.state in ('disputed', 'frozen', 'stolen_flagged', 'archived', 'claimed', 'transferred', 'listed_for_resale', 'sale_pending') then 'unavailable'
    else 'ready'
  end as claim_code_reveal_state,
  editorial_media.asset_id is not null as has_editorial_image
from public.unique_items ui
join public.artists ar on ar.id = ui.artist_id
join public.artworks aw on aw.id = ui.artwork_id
join public.garment_products gp on gp.id = ui.garment_product_id
left join public.user_profiles owner_profile on owner_profile.user_id = ui.current_owner_user_id
left join public.authenticity_records authrec on authrec.unique_item_id = ui.id
left join public.listings l on l.unique_item_id = ui.id
left join public.admin_item_claim_ops claim_ops on claim_ops.item_id = ui.id
left join lateral (
  select
    ma.id as asset_id,
    ma.storage_bucket,
    ma.storage_path,
    ma.created_at
  from public.media_assets ma
  where ma.linked_entity_type = 'unique_item'
    and ma.linked_entity_id = ui.id
    and ma.storage_bucket = 'garment-editorial'
  order by ma.created_at desc
  limit 1
) editorial_media on true;

grant execute on function public.admin_attach_item_media_asset(uuid, text, text, text, text) to authenticated;
grant execute on function public.admin_remove_item_media_assets(uuid) to authenticated;
