-- Secure admin claim operations for one-time reveal and printable claim packets.

create table if not exists public.admin_item_claim_materials (
  item_id uuid primary key references public.unique_items(id) on delete cascade,
  hidden_claim_code_plaintext text not null,
  created_at timestamptz not null default timezone('utc', now()),
  created_by uuid references public.users(id)
);

create table if not exists public.admin_item_claim_ops (
  item_id uuid primary key references public.unique_items(id) on delete cascade,
  claim_code_revealed_at timestamptz,
  claim_code_revealed_by uuid references public.users(id),
  claim_code_reveal_reason text,
  claim_packet_generated_at timestamptz,
  claim_packet_generated_by uuid references public.users(id),
  claim_packet_reason text,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

alter table public.admin_item_claim_ops
  add column if not exists claim_code_reveal_reason text;

alter table public.admin_item_claim_ops
  add column if not exists claim_packet_reason text;

create or replace function public.touch_admin_item_claim_ops_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists set_admin_item_claim_ops_updated_at on public.admin_item_claim_ops;
create trigger set_admin_item_claim_ops_updated_at
before update on public.admin_item_claim_ops
for each row
execute function public.touch_admin_item_claim_ops_updated_at();

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
  v_public_qr_token text;
  v_hidden_claim_code text;
  v_hidden_claim_code_hash text;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  if p_item_id is null then
    v_public_qr_token := 'qr_' || replace(gen_random_uuid()::text, '-', '');
    v_hidden_claim_code := format(
      'CLAIM-%s-%s',
      upper(left(regexp_replace(p_serial_number, '[^A-Za-z0-9]', '', 'g'), 12)),
      upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 8))
    );
    v_hidden_claim_code_hash := encode(
      extensions.digest(v_hidden_claim_code, 'sha256'),
      'hex'
    );

    insert into public.unique_items (
      serial_number,
      artwork_id,
      artist_id,
      garment_product_id,
      public_qr_token,
      hidden_claim_code_hash,
      state
    ) values (
      p_serial_number,
      p_artwork_id,
      p_artist_id,
      p_garment_product_id,
      v_public_qr_token,
      v_hidden_claim_code_hash,
      p_item_state
    ) returning id into v_item_id;

    insert into public.admin_item_claim_materials (
      item_id,
      hidden_claim_code_plaintext,
      created_by
    ) values (
      v_item_id,
      v_hidden_claim_code,
      auth.uid()
    )
    on conflict (item_id) do nothing;
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
  end as claim_code_reveal_state
from public.unique_items ui
join public.artists ar on ar.id = ui.artist_id
join public.artworks aw on aw.id = ui.artwork_id
join public.garment_products gp on gp.id = ui.garment_product_id
left join public.user_profiles owner_profile on owner_profile.user_id = ui.current_owner_user_id
left join public.authenticity_records authrec on authrec.unique_item_id = ui.id
left join public.listings l on l.unique_item_id = ui.id
left join public.admin_item_claim_ops claim_ops on claim_ops.item_id = ui.id;

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

create or replace function public.admin_issue_claim_packet_payload(
  p_item_id uuid,
  p_reason text,
  p_action text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item public.unique_items;
  v_artist_name text;
  v_artwork_title text;
  v_garment_name text;
  v_authenticity_status text;
  v_claim_code text;
  v_action text;
  v_reason text;
  v_now timestamptz := timezone('utc', now());
  v_claim_packet_ready boolean;
  v_claim_code_reveal_state text;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  v_action := lower(trim(coalesce(p_action, 'reveal')));
  if v_action not in ('reveal', 'claim_packet') then
    raise exception 'Unsupported claim action';
  end if;

  v_reason := trim(coalesce(p_reason, ''));
  if v_reason = '' then
    raise exception 'Sensitive claim action reason is required';
  end if;

  insert into public.admin_item_claim_ops (item_id)
  values (p_item_id)
  on conflict (item_id) do nothing;

  select ui.*
  into v_item
  from public.unique_items ui
  where ui.id = p_item_id
  for update;

  if not found then
    raise exception 'Inventory item not found';
  end if;

  select
    ar.display_name,
    aw.title,
    gp.name,
    authrec.authenticity_status
  into
    v_artist_name,
    v_artwork_title,
    v_garment_name,
    v_authenticity_status
  from public.unique_items ui
  join public.artists ar on ar.id = ui.artist_id
  join public.artworks aw on aw.id = ui.artwork_id
  join public.garment_products gp on gp.id = ui.garment_product_id
  left join public.authenticity_records authrec on authrec.unique_item_id = ui.id
  where ui.id = p_item_id;

  select materials.hidden_claim_code_plaintext
  into v_claim_code
  from public.admin_item_claim_materials materials
  where materials.item_id = p_item_id
  for update;

  if v_claim_code is null then
    raise exception 'Secure claim material unavailable for this item';
  end if;

  if encode(extensions.digest(v_claim_code, 'sha256'), 'hex') <> v_item.hidden_claim_code_hash then
    raise exception 'Secure claim material is out of sync for this item';
  end if;

  if nullif(trim(v_item.public_qr_token), '') is null then
    raise exception 'QR token is not ready for this item';
  end if;

  if v_authenticity_status is null then
    raise exception 'Create authenticity record first';
  end if;

  if v_item.claim_code_consumed_at is not null then
    raise exception 'Claim code already consumed';
  end if;

  if v_item.state not in ('drafted', 'minted', 'in_inventory', 'sold_unclaimed') then
    raise exception 'Item is not eligible for secure claim operations';
  end if;

  if v_action = 'reveal' then
    if exists (
      select 1
      from public.admin_item_claim_ops claim_ops
      where claim_ops.item_id = p_item_id
        and claim_ops.claim_code_revealed_at is not null
      for update
    ) then
      raise exception 'Claim code already revealed';
    end if;

    update public.admin_item_claim_ops
    set claim_code_revealed_at = v_now,
        claim_code_revealed_by = auth.uid(),
        claim_code_reveal_reason = v_reason
    where item_id = p_item_id;
  else
    if exists (
      select 1
      from public.admin_item_claim_ops claim_ops
      where claim_ops.item_id = p_item_id
        and claim_ops.claim_packet_generated_at is not null
      for update
    ) then
      raise exception 'Claim packet already generated';
    end if;

    update public.admin_item_claim_ops
    set claim_packet_generated_at = v_now,
        claim_packet_generated_by = auth.uid(),
        claim_packet_reason = v_reason
    where item_id = p_item_id;
  end if;

  select
    (
      v_authenticity_status is not null
      and nullif(trim(v_item.public_qr_token), '') is not null
      and v_item.claim_code_consumed_at is null
      and exists (
        select 1
        from public.admin_item_claim_ops claim_ops
        where claim_ops.item_id = p_item_id
          and claim_ops.claim_packet_generated_at is null
      )
      and v_item.state in ('drafted', 'minted', 'in_inventory', 'sold_unclaimed')
    ),
    case
      when v_item.claim_code_consumed_at is not null then 'consumed'
      when exists (
        select 1
        from public.admin_item_claim_ops claim_ops
        where claim_ops.item_id = p_item_id
          and claim_ops.claim_code_revealed_at is not null
      ) then 'revealed_once'
      when v_authenticity_status is null then 'awaiting_authenticity'
      when nullif(trim(v_item.public_qr_token), '') is null then 'qr_missing'
      when v_item.state in ('disputed', 'frozen', 'stolen_flagged', 'archived', 'claimed', 'transferred', 'listed_for_resale', 'sale_pending') then 'unavailable'
      else 'ready'
    end
  into v_claim_packet_ready, v_claim_code_reveal_state;

  perform public.log_audit_event(
    'unique_item',
    p_item_id,
    case when v_action = 'claim_packet' then 'admin_generate_claim_packet' else 'admin_reveal_claim_code' end,
    jsonb_build_object(
      'serial_number', v_item.serial_number,
      'reason', v_reason,
      'claim_code_reveal_state', v_claim_code_reveal_state,
      'qr_ready', true,
      'claim_packet_ready', v_claim_packet_ready
    )
  );

  return jsonb_build_object(
    'item_id', p_item_id,
    'serial_number', v_item.serial_number,
    'artist_name', v_artist_name,
    'artwork_title', v_artwork_title,
    'garment_name', v_garment_name,
    'public_qr_token', v_item.public_qr_token,
    'verification_uri', 'oneofone://authenticity/' || v_item.public_qr_token,
    'hidden_claim_code', v_claim_code,
    'claim_code_reveal_state', v_claim_code_reveal_state,
    'reveal_action', v_action
  );
end;
$$;

create or replace function public.admin_reveal_item_claim_code(
  p_item_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.admin_issue_claim_packet_payload(p_item_id, p_reason, 'reveal');
end;
$$;

create or replace function public.admin_generate_claim_packet(
  p_item_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  return public.admin_issue_claim_packet_payload(p_item_id, p_reason, 'claim_packet');
end;
$$;

revoke all on public.admin_item_claim_ops from authenticated;
revoke all on public.admin_item_claim_materials from authenticated;

grant execute on function public.get_admin_inventory_directory() to authenticated;
grant execute on function public.admin_issue_claim_packet_payload(uuid, text, text) to authenticated;
grant execute on function public.admin_reveal_item_claim_code(uuid, text) to authenticated;
grant execute on function public.admin_generate_claim_packet(uuid, text) to authenticated;
