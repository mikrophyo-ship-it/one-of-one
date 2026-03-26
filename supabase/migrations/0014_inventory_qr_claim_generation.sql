-- Generate required QR tokens and private claim-code hashes when admin-created
-- inventory items are inserted. This preserves the base schema contract without
-- exposing hidden claim data in the admin UI.

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
  v_hidden_claim_code_hash text;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  v_public_qr_token := 'qr_' || replace(gen_random_uuid()::text, '-', '');
  v_hidden_claim_code_hash := encode(
    digest(gen_random_uuid()::text, 'sha256'),
    'hex'
  );

  if p_item_id is null then
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

grant execute on function public.admin_upsert_inventory_item(uuid, uuid, uuid, text, public.item_state, uuid) to authenticated;
