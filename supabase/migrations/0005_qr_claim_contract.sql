create or replace function public.claim_item_ownership_by_qr_token(
  p_public_qr_token text,
  p_claim_code text
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_item_id uuid;
begin
  select id
  into v_item_id
  from public.unique_items
  where public_qr_token = trim(p_public_qr_token);

  if v_item_id is null then
    raise exception 'Authenticity token not found';
  end if;

  return public.claim_item_ownership(v_item_id, p_claim_code);
end;
$$;

grant execute on function public.claim_item_ownership_by_qr_token(text, text) to authenticated;
