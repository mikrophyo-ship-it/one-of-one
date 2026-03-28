-- Repair manual payment lifecycle: seed/recover payment rows and keep review queue proof-driven.

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
  v_provider text := lower(coalesce(nullif(trim(p_provider), ''), 'stripe'));
  v_provider_reference text;
  v_item public.unique_items;
  v_listing public.listings;
begin
  v_order_id := public.create_resale_order(p_listing_id);
  v_provider_reference := v_provider || '_' || replace(v_order_id::text, '-', '');

  update public.payments p
  set provider = v_provider,
      provider_reference = v_provider_reference,
      provider_session_reference = 'session_' || replace(v_order_id::text, '-', ''),
      status = 'pending'
  where p.order_id = v_order_id;

  if not found then
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
      v_provider,
      v_provider_reference,
      'session_' || replace(o.id::text, '-', ''),
      'pending',
      o.total_cents
    from public.orders o
    where o.id = v_order_id;
  end if;

  select l.* into v_listing
  from public.listings l
  where l.id = p_listing_id;

  select ui.* into v_item
  from public.unique_items ui
  where ui.id = v_listing.unique_item_id;

  perform public.log_audit_event(
    'order',
    v_order_id,
    'create_resale_checkout_session',
    jsonb_build_object(
      'provider', v_provider,
      'success_url', p_success_url,
      'cancel_url', p_cancel_url
    )
  );

  return jsonb_build_object(
    'order_id', v_order_id,
    'provider', v_provider,
    'status', 'requires_action',
    'provider_reference', v_provider_reference,
    'checkout_url', null,
    'client_secret', null,
    'expires_at', timezone('utc', now()) + interval '30 minutes',
    'amount_cents', v_listing.asking_price_cents,
    'currency', 'usd',
    'item_label', v_item.serial_number
  );
end;
$$;

create or replace view public.manual_payment_order_statuses
with (security_invoker = true) as
select
  o.id as order_id,
  o.buyer_user_id,
  o.seller_user_id,
  o.order_status,
  o.total_cents,
  o.created_at,
  oi.unique_item_id as item_id,
  p.id as payment_id,
  coalesce(p.status, 'pending'::public.payment_status) as payment_status,
  coalesce(p.provider, 'manual_transfer') as payment_provider,
  coalesce(
    p.provider_reference,
    'manual_' || replace(o.id::text, '-', '')
  ) as payment_reference,
  submission.review_status,
  submission.payment_method,
  submission.payer_name,
  submission.payer_phone,
  submission.paid_amount_cents,
  submission.paid_at,
  submission.transaction_reference,
  submission.review_note,
  submission.proof_bucket,
  submission.proof_path,
  submission.created_at as proof_submitted_at,
  submission.reviewed_at,
  submission.reviewed_by
from public.orders o
join public.order_items oi on oi.order_id = o.id
left join lateral (
  select p.*
  from public.payments p
  where p.order_id = o.id
  order by p.created_at desc
  limit 1
) p on true
left join lateral (
  select s.*
  from public.manual_payment_submissions s
  where s.order_id = o.id
  order by s.created_at desc
  limit 1
) submission on true;

create or replace function public.submit_manual_payment_proof(
  p_order_id uuid,
  p_payment_method text,
  p_payer_name text,
  p_payer_phone text,
  p_paid_amount_cents int,
  p_paid_at timestamptz,
  p_transaction_reference text default null,
  p_proof_bucket text default 'payment-proofs',
  p_proof_path text default null
)
returns table (
  order_id uuid,
  item_id uuid,
  order_status public.order_status,
  total_cents int,
  created_at timestamptz,
  payment_status public.payment_status,
  payment_provider text,
  payment_reference text,
  review_status text,
  payment_method text,
  payer_name text,
  payer_phone text,
  paid_amount_cents int,
  paid_at timestamptz,
  transaction_reference text,
  review_note text,
  proof_submitted_at timestamptz,
  reviewed_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
  v_payment public.payments;
  v_latest_submission public.manual_payment_submissions;
  v_provider_reference text;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  if nullif(trim(coalesce(p_payment_method, '')), '') is null then
    raise exception 'Payment method is required';
  end if;

  if nullif(trim(coalesce(p_payer_name, '')), '') is null then
    raise exception 'Payer name is required';
  end if;

  if nullif(trim(coalesce(p_payer_phone, '')), '') is null then
    raise exception 'Payer phone is required';
  end if;

  if p_paid_amount_cents is null or p_paid_amount_cents <= 0 then
    raise exception 'Paid amount must be greater than zero';
  end if;

  if p_paid_at is null then
    raise exception 'Paid time is required';
  end if;

  if nullif(trim(coalesce(p_proof_path, '')), '') is null then
    raise exception 'Payment proof upload is required';
  end if;

  select o.* into v_order
  from public.orders o
  where o.id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.buyer_user_id <> auth.uid() then
    raise exception 'Order access denied';
  end if;

  if v_order.order_status <> 'payment_pending' then
    raise exception 'Order is not awaiting payment review';
  end if;

  select p.* into v_payment
  from public.payments p
  where p.order_id = p_order_id
  order by p.created_at desc
  limit 1
  for update;

  if not found then
    v_provider_reference := 'manual_' || replace(p_order_id::text, '-', '');

    insert into public.payments (
      order_id,
      provider,
      provider_reference,
      provider_session_reference,
      status,
      amount_cents
    ) values (
      p_order_id,
      'manual_transfer',
      v_provider_reference,
      'session_' || replace(p_order_id::text, '-', ''),
      'pending',
      v_order.total_cents
    )
    returning * into v_payment;
  end if;

  select s.* into v_latest_submission
  from public.manual_payment_submissions s
  where s.order_id = p_order_id
  order by s.created_at desc
  limit 1
  for update;

  if v_latest_submission.id is not null
     and v_latest_submission.review_status in ('submitted', 'under_review') then
    raise exception 'A payment proof is already awaiting review for this order';
  end if;

  insert into public.manual_payment_submissions (
    order_id,
    buyer_user_id,
    payment_method,
    payer_name,
    payer_phone,
    paid_amount_cents,
    paid_at,
    transaction_reference,
    proof_bucket,
    proof_path,
    review_status
  ) values (
    p_order_id,
    auth.uid(),
    trim(p_payment_method),
    trim(p_payer_name),
    trim(p_payer_phone),
    p_paid_amount_cents,
    p_paid_at,
    nullif(trim(coalesce(p_transaction_reference, '')), ''),
    coalesce(nullif(trim(coalesce(p_proof_bucket, '')), ''), 'payment-proofs'),
    trim(p_proof_path),
    'submitted'
  );

  update public.payments
  set provider = case
        when lower(trim(coalesce(provider, ''))) in ('', 'stripe') then 'manual_transfer'
        else provider
      end,
      status = 'under_review'
  where id = v_payment.id;

  insert into public.notifications (user_id, title, body)
  values (
    auth.uid(),
    'Payment proof submitted',
    'Your payment proof is now queued for admin review.'
  );

  perform public.log_audit_event(
    'order',
    p_order_id,
    'submit_manual_payment_proof',
    jsonb_build_object(
      'payment_method', trim(p_payment_method),
      'paid_amount_cents', p_paid_amount_cents,
      'proof_path', trim(p_proof_path)
    )
  );

  return query
  select
    status.order_id,
    status.item_id,
    status.order_status,
    status.total_cents,
    status.created_at,
    status.payment_status,
    status.payment_provider,
    status.payment_reference,
    status.review_status,
    status.payment_method,
    status.payer_name,
    status.payer_phone,
    status.paid_amount_cents,
    status.paid_at,
    status.transaction_reference,
    status.review_note,
    status.proof_submitted_at,
    status.reviewed_at
  from public.manual_payment_order_statuses status
  where status.order_id = p_order_id;
end;
$$;

grant execute on function public.create_resale_checkout_session(uuid, text, text, text) to authenticated;
grant select on public.manual_payment_order_statuses to authenticated;
grant execute on function public.submit_manual_payment_proof(uuid, text, text, text, int, timestamptz, text, text, text) to authenticated;
