-- Stripe hosted checkout hardening, webhook reconciliation, and idempotent settlement controls.

alter table public.payments
  add column if not exists checkout_session_id text,
  add column if not exists checkout_url text,
  add column if not exists payment_intent_id text,
  add column if not exists latest_charge_id text,
  add column if not exists currency text not null default 'usd',
  add column if not exists refund_total_cents int not null default 0,
  add column if not exists last_webhook_event_id text,
  add column if not exists last_webhook_event_type text,
  add column if not exists last_event_created_at timestamptz;

alter table public.refunds
  add column if not exists provider text not null default 'stripe',
  add column if not exists provider_payload jsonb not null default '{}'::jsonb;

create unique index if not exists payments_checkout_session_id_key
  on public.payments (checkout_session_id)
  where checkout_session_id is not null;

create unique index if not exists refunds_provider_reference_key
  on public.refunds (provider, provider_reference)
  where provider_reference is not null;

create table if not exists public.payment_provider_webhook_events (
  id uuid primary key default gen_random_uuid(),
  provider text not null,
  provider_event_id text not null,
  event_type text not null,
  api_version text,
  livemode boolean not null default false,
  payload jsonb not null default '{}'::jsonb,
  processing_state text not null default 'received',
  processing_attempts int not null default 0,
  order_id uuid references public.orders(id),
  payment_id uuid references public.payments(id),
  refund_id uuid references public.refunds(id),
  error_message text,
  received_at timestamptz not null default timezone('utc', now()),
  processed_at timestamptz
);

create unique index if not exists payment_provider_webhook_events_provider_event_key
  on public.payment_provider_webhook_events (provider, provider_event_id);

alter table public.payment_provider_webhook_events enable row level security;

drop policy if exists payment_provider_webhook_events_admin_only on public.payment_provider_webhook_events;
create policy payment_provider_webhook_events_admin_only
on public.payment_provider_webhook_events
for select using (public.is_admin_user());

create or replace function public.get_order_item_id(p_order_id uuid)
returns uuid
language sql
security definer
set search_path = public
as $$
  select oi.unique_item_id
  from public.order_items oi
  where oi.order_id = p_order_id
  limit 1;
$$;

create or replace function public.get_latest_payment_id(p_order_id uuid)
returns uuid
language sql
security definer
set search_path = public
as $$
  select p.id
  from public.payments p
  where p.order_id = p_order_id
  order by p.created_at desc
  limit 1;
$$;

create or replace function public.can_release_order_payouts(p_order_id uuid)
returns boolean
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
  v_item_id uuid;
  v_has_delivery_shipment boolean;
  v_has_open_dispute boolean;
  v_refund_total int;
begin
  select * into v_order
  from public.orders
  where id = p_order_id;

  if not found then
    return false;
  end if;

  if v_order.order_status <> 'fulfilled' then
    return false;
  end if;

  if v_order.delivery_confirmed_at is null then
    return false;
  end if;

  v_item_id := public.get_order_item_id(p_order_id);

  select exists (
    select 1
    from public.shipment_events se
    where se.order_id = p_order_id
      and se.status in ('delivered', 'delivery_confirmed', 'received')
  ) into v_has_delivery_shipment;

  if not v_has_delivery_shipment then
    return false;
  end if;

  select exists (
    select 1
    from public.disputes d
    where (d.order_id = p_order_id or d.unique_item_id = v_item_id)
      and d.status in ('open', 'under_review')
  ) into v_has_open_dispute;

  if v_has_open_dispute then
    return false;
  end if;

  select coalesce(sum(r.amount_cents), 0)::int
  into v_refund_total
  from public.refunds r
  where r.order_id = p_order_id
    and lower(r.status) not in ('failed', 'canceled', 'cancelled');

  if coalesce(v_refund_total, 0) > 0 then
    return false;
  end if;

  return true;
end;
$$;

create or replace function public.try_release_order_payouts(
  p_order_id uuid,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
  v_ready boolean;
begin
  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.payout_released_at is not null then
    return jsonb_build_object(
      'order_id', p_order_id,
      'released', true,
      'payout_released_at', v_order.payout_released_at,
      'message', 'Payouts were already released.'
    );
  end if;

  v_ready := public.can_release_order_payouts(p_order_id);
  if not v_ready then
    return jsonb_build_object(
      'order_id', p_order_id,
      'released', false,
      'message', 'Payout release conditions are not yet satisfied.'
    );
  end if;

  update public.orders
  set payout_released_at = timezone('utc', now())
  where id = p_order_id;

  update public.payout_ledgers
  set status = 'released'
  where order_id = p_order_id
    and status <> 'released';

  update public.royalty_ledgers
  set status = 'released'
  where order_id = p_order_id
    and status <> 'released';

  update public.platform_fee_ledgers
  set status = 'captured'
  where order_id = p_order_id
    and status <> 'captured';

  perform public.log_audit_event(
    'order',
    p_order_id,
    'try_release_order_payouts',
    jsonb_build_object('note', p_note, 'released_at', timezone('utc', now()))
  );

  return jsonb_build_object(
    'order_id', p_order_id,
    'released', true,
    'payout_released_at', timezone('utc', now()),
    'message', 'Payout release completed.'
  );
end;
$$;

create or replace function public.attach_checkout_provider_session(
  p_order_id uuid,
  p_provider text,
  p_provider_reference text,
  p_provider_session_reference text,
  p_checkout_session_id text,
  p_checkout_url text,
  p_currency text default 'usd',
  p_provider_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.payments;
begin
  select * into v_payment
  from public.payments
  where order_id = p_order_id
  order by created_at desc
  limit 1
  for update;

  if not found then
    raise exception 'Payment record not found for order';
  end if;

  update public.payments
  set provider = lower(trim(p_provider)),
      provider_reference = p_provider_reference,
      provider_session_reference = p_provider_session_reference,
      checkout_session_id = p_checkout_session_id,
      checkout_url = p_checkout_url,
      currency = lower(coalesce(nullif(trim(p_currency), ''), 'usd')),
      provider_payload = coalesce(provider_payload, '{}'::jsonb) || coalesce(p_provider_payload, '{}'::jsonb)
  where id = v_payment.id;

  perform public.log_audit_event(
    'payment',
    v_payment.id,
    'attach_checkout_provider_session',
    jsonb_build_object(
      'order_id', p_order_id,
      'provider', lower(trim(p_provider)),
      'checkout_session_id', p_checkout_session_id
    )
  );

  return jsonb_build_object(
    'order_id', p_order_id,
    'payment_id', v_payment.id,
    'checkout_session_id', p_checkout_session_id,
    'checkout_url', p_checkout_url
  );
end;
$$;

create or replace function public.record_payment_provider_webhook_event(
  p_provider text,
  p_provider_event_id text,
  p_event_type text,
  p_payload jsonb,
  p_api_version text default null,
  p_livemode boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.payment_provider_webhook_events;
begin
  insert into public.payment_provider_webhook_events (
    provider,
    provider_event_id,
    event_type,
    api_version,
    livemode,
    payload,
    processing_state,
    processing_attempts
  ) values (
    lower(trim(p_provider)),
    p_provider_event_id,
    p_event_type,
    p_api_version,
    p_livemode,
    coalesce(p_payload, '{}'::jsonb),
    'received',
    1
  )
  on conflict (provider, provider_event_id)
  do update
    set processing_attempts = public.payment_provider_webhook_events.processing_attempts + 1,
        payload = excluded.payload,
        event_type = excluded.event_type,
        api_version = excluded.api_version,
        livemode = excluded.livemode
  returning * into v_event;

  return jsonb_build_object(
    'webhook_event_id', v_event.id,
    'already_processed', v_event.processed_at is not null and v_event.processing_state = 'processed',
    'processing_state', v_event.processing_state
  );
end;
$$;

create or replace function public.mark_payment_provider_webhook_event_state(
  p_provider text,
  p_provider_event_id text,
  p_processing_state text,
  p_order_id uuid default null,
  p_payment_id uuid default null,
  p_refund_id uuid default null,
  p_error_message text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_event public.payment_provider_webhook_events;
begin
  update public.payment_provider_webhook_events
  set processing_state = lower(trim(p_processing_state)),
      processed_at = case
        when lower(trim(p_processing_state)) in ('processed', 'ignored') then timezone('utc', now())
        else processed_at
      end,
      order_id = coalesce(p_order_id, order_id),
      payment_id = coalesce(p_payment_id, payment_id),
      refund_id = coalesce(p_refund_id, refund_id),
      error_message = p_error_message
  where provider = lower(trim(p_provider))
    and provider_event_id = p_provider_event_id
  returning * into v_event;

  if not found then
    raise exception 'Webhook event not found';
  end if;

  return jsonb_build_object(
    'webhook_event_id', v_event.id,
    'processing_state', v_event.processing_state,
    'processed_at', v_event.processed_at
  );
end;
$$;

create or replace function public.release_resale_order_back_to_market(
  p_order_id uuid,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
  v_listing public.listings;
  v_item public.unique_items;
begin
  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if v_order.order_status = 'fulfilled' or v_order.delivery_confirmed_at is not null then
    return jsonb_build_object(
      'order_id', p_order_id,
      'released', false,
      'message', 'Order already finalized; listing was not reopened.'
    );
  end if;

  select * into v_listing
  from public.listings
  where id = v_order.listing_id
  for update;

  select * into v_item
  from public.unique_items
  where id = public.get_order_item_id(p_order_id)
  for update;

  update public.orders
  set order_status = 'failed'
  where id = p_order_id
    and order_status in ('payment_pending', 'paid');

  if v_listing.id is not null
     and v_item.state not in ('disputed', 'frozen', 'stolen_flagged', 'archived')
     and v_item.current_owner_user_id = v_order.seller_user_id then
    update public.listings
    set status = 'active'
    where id = v_listing.id;

    update public.unique_items
    set state = 'listed_for_resale',
        listed_price_cents = v_listing.asking_price_cents
    where id = v_item.id;
  end if;

  perform public.log_audit_event(
    'order',
    p_order_id,
    'release_resale_order_back_to_market',
    jsonb_build_object('reason', p_reason)
  );

  return jsonb_build_object(
    'order_id', p_order_id,
    'released', true,
    'message', p_reason
  );
end;
$$;

create or replace function public.mark_resale_payment_failed_or_expired(
  p_order_id uuid,
  p_provider text,
  p_provider_reference text,
  p_reason text
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_payment public.payments;
  v_release jsonb;
begin
  select * into v_payment
  from public.payments
  where order_id = p_order_id
  order by created_at desc
  limit 1
  for update;

  if not found then
    raise exception 'Payment record not found for order';
  end if;

  if v_payment.status = 'captured' then
    return jsonb_build_object(
      'order_id', p_order_id,
      'status', 'ignored',
      'message', 'Payment is already captured; failure event ignored.'
    );
  end if;

  update public.payments
  set provider = lower(trim(p_provider)),
      provider_reference = coalesce(p_provider_reference, provider_reference),
      status = 'failed'
  where id = v_payment.id;

  v_release := public.release_resale_order_back_to_market(p_order_id, p_reason);

  perform public.log_audit_event(
    'payment',
    v_payment.id,
    'mark_resale_payment_failed_or_expired',
    jsonb_build_object('order_id', p_order_id, 'reason', p_reason)
  );

  return jsonb_build_object(
    'order_id', p_order_id,
    'payment_id', v_payment.id,
    'status', 'failed',
    'release', v_release
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
  v_payment public.payments;
  v_item_id uuid;
begin
  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  select * into v_payment
  from public.payments
  where order_id = p_order_id
  order by created_at desc
  limit 1
  for update;

  if not found then
    raise exception 'Payment record not found for order';
  end if;

  select oi.unique_item_id into v_item_id
  from public.order_items oi
  where oi.order_id = p_order_id
  limit 1;

  if v_payment.status = 'captured'
     and v_order.order_status in ('paid', 'fulfilled')
     and coalesce(v_payment.provider_reference, '') = coalesce(p_provider_reference, coalesce(v_payment.provider_reference, '')) then
    return jsonb_build_object(
      'order_id', p_order_id,
      'item_id', v_item_id,
      'status', 'captured',
      'message', 'Payment was already authorized.'
    );
  end if;

  if v_order.order_status not in ('payment_pending', 'paid', 'fulfilled') then
    return jsonb_build_object(
      'order_id', p_order_id,
      'item_id', v_item_id,
      'status', 'ignored',
      'message', 'Late payment authorization ignored because the order is no longer pending.'
    );
  end if;

  if v_order.total_cents <> p_amount_cents then
    raise exception 'Payment amount does not match order total';
  end if;

  update public.payments
  set provider = lower(trim(p_provider)),
      provider_reference = p_provider_reference,
      payment_intent_id = coalesce(payment_intent_id, p_provider_reference),
      status = 'captured',
      amount_cents = p_amount_cents
  where id = v_payment.id;

  if v_order.order_status = 'payment_pending' then
    update public.orders
    set order_status = 'paid',
        review_window_closes_at = coalesce(review_window_closes_at, timezone('utc', now()) + interval '48 hours')
    where id = p_order_id;

    insert into public.notifications (user_id, title, body)
    values
      (v_order.buyer_user_id, 'Payment authorized', 'Your order is now awaiting shipment and delivery review.'),
      (v_order.seller_user_id, 'Ship collectible', 'Payment is authorized. Record shipment events before delivery confirmation.');
  end if;

  perform public.log_audit_event(
    'payment',
    v_payment.id,
    'mark_resale_payment_authorized',
    jsonb_build_object(
      'order_id', p_order_id,
      'provider', lower(trim(p_provider)),
      'provider_reference', p_provider_reference,
      'amount_cents', p_amount_cents
    )
  );

  return jsonb_build_object(
    'order_id', p_order_id,
    'item_id', v_item_id,
    'payment_id', v_payment.id,
    'status', 'captured'
  );
end;
$$;

create or replace function public.reconcile_order_refund(
  p_order_id uuid,
  p_provider text,
  p_provider_reference text,
  p_amount_cents int,
  p_reason text,
  p_status text,
  p_note text default null,
  p_provider_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_order public.orders;
  v_payment public.payments;
  v_refund public.refunds;
  v_existing_amount int;
  v_total_refunded int;
  v_refund_id uuid;
begin
  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  select * into v_payment
  from public.payments
  where order_id = p_order_id
  order by created_at desc
  limit 1
  for update;

  if not found then
    raise exception 'Payment record not found for order';
  end if;

  select * into v_refund
  from public.refunds
  where provider = lower(trim(p_provider))
    and provider_reference = p_provider_reference
  limit 1
  for update;

  v_existing_amount := coalesce(v_refund.amount_cents, 0);

  if v_refund.id is null then
    insert into public.refunds (
      order_id,
      amount_cents,
      reason,
      note,
      provider,
      provider_reference,
      status,
      provider_payload,
      created_by_user_id
    ) values (
      p_order_id,
      p_amount_cents,
      p_reason,
      p_note,
      lower(trim(p_provider)),
      p_provider_reference,
      lower(trim(p_status)),
      coalesce(p_provider_payload, '{}'::jsonb),
      auth.uid()
    ) returning * into v_refund;
  else
    update public.refunds
    set amount_cents = p_amount_cents,
        reason = p_reason,
        note = coalesce(p_note, note),
        status = lower(trim(p_status)),
        provider_payload = coalesce(provider_payload, '{}'::jsonb) || coalesce(p_provider_payload, '{}'::jsonb)
    where id = v_refund.id
    returning * into v_refund;
  end if;

  select coalesce(sum(r.amount_cents), 0)::int
  into v_total_refunded
  from public.refunds r
  where r.order_id = p_order_id
    and lower(r.status) not in ('failed', 'canceled', 'cancelled')
    and r.id <> v_refund.id;

  v_total_refunded := v_total_refunded + coalesce(v_refund.amount_cents, 0);

  if v_total_refunded > v_payment.amount_cents then
    raise exception 'Refund total exceeds captured amount';
  end if;

  update public.payments
  set refund_total_cents = v_total_refunded,
      status = case
        when v_total_refunded >= amount_cents then 'refunded'
        else status
      end
  where id = v_payment.id;

  if v_total_refunded > 0 and v_order.payout_released_at is not null then
    update public.payout_ledgers
    set status = 'reversal_review'
    where order_id = p_order_id;

    update public.royalty_ledgers
    set status = 'reversal_review'
    where order_id = p_order_id;

    update public.platform_fee_ledgers
    set status = 'reversal_review'
    where order_id = p_order_id;
  end if;

  if v_total_refunded >= v_payment.amount_cents
     and v_order.delivery_confirmed_at is null then
    perform public.release_resale_order_back_to_market(
      p_order_id,
      'Order released back to market after full refund before delivery finalization.'
    );
  end if;

  perform public.log_audit_event(
    'refund',
    v_refund.id,
    'reconcile_order_refund',
    jsonb_build_object(
      'order_id', p_order_id,
      'amount_cents', p_amount_cents,
      'status', lower(trim(p_status)),
      'provider_reference', p_provider_reference
    )
  );

  return jsonb_build_object(
    'refund_id', v_refund.id,
    'order_id', p_order_id,
    'status', v_refund.status,
    'amount_cents', v_refund.amount_cents,
    'provider_reference', v_refund.provider_reference,
    'refund_total_cents', v_total_refunded
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
  v_release_result jsonb := jsonb_build_object('released', false);
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

  if v_order.order_status = 'fulfilled' and v_order.delivery_confirmed_at is not null then
    if p_release_payouts then
      v_release_result := public.try_release_order_payouts(
        p_order_id,
        'Repeated delivery confirmation checked payout release readiness.'
      );
    end if;

    return jsonb_build_object(
      'order_id', p_order_id,
      'item_id', public.get_order_item_id(p_order_id),
      'transfer_id', null,
      'delivery_confirmed_at', v_order.delivery_confirmed_at,
      'payout_release', v_release_result
    );
  end if;

  if v_order.order_status <> 'paid' then
    raise exception 'Order must be paid before delivery confirmation';
  end if;

  update public.orders
  set delivery_confirmed_at = coalesce(delivery_confirmed_at, timezone('utc', now()))
  where id = p_order_id;

  v_transfer_id := public.complete_resale_order(p_order_id);
  v_item_id := public.get_order_item_id(p_order_id);

  if p_release_payouts then
    v_release_result := public.try_release_order_payouts(
      p_order_id,
      'Delivery confirmation triggered payout release evaluation.'
    );
  end if;

  insert into public.notifications (user_id, title, body)
  values
    (v_order.buyer_user_id, 'Delivery confirmed', 'Ownership is now finalized on-platform.'),
    (v_order.seller_user_id, 'Settlement review advanced', 'Delivery is confirmed and payout release conditions were re-evaluated.');

  perform public.log_audit_event(
    'order',
    p_order_id,
    'confirm_resale_delivery',
    jsonb_build_object(
      'transfer_id', v_transfer_id,
      'release_payouts', p_release_payouts,
      'note', p_note,
      'payout_release', v_release_result
    )
  );

  return jsonb_build_object(
    'order_id', p_order_id,
    'item_id', v_item_id,
    'transfer_id', v_transfer_id,
    'delivery_confirmed_at', timezone('utc', now()),
    'payout_release', v_release_result
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
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  return public.reconcile_order_refund(
    p_order_id,
    'stripe',
    'admin_refund_' || replace(p_order_id::text, '-', '') || '_' || p_amount_cents::text,
    p_amount_cents,
    p_reason,
    case when p_amount_cents > 0 then 'pending' else 'failed' end,
    p_note,
    jsonb_build_object('source', 'admin_manual_refund')
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
  v_release_result jsonb := jsonb_build_object('released', false);
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

  if lower(trim(p_status)) in ('delivered', 'delivery_confirmed', 'received') then
    v_release_result := public.try_release_order_payouts(
      p_order_id,
      'Shipment event triggered payout release evaluation.'
    );
  end if;

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
      'tracking_number', p_tracking_number,
      'payout_release', v_release_result
    )
  );

  return jsonb_build_object(
    'order_id', p_order_id,
    'status', lower(trim(p_status)),
    'carrier', p_carrier,
    'tracking_number', p_tracking_number,
    'note', p_note,
    'occurred_at', v_occurred_at,
    'payout_release', v_release_result
  );
end;
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
  v_item public.unique_items;
  v_listing public.listings;
begin
  v_order_id := public.create_resale_order(p_listing_id);
  v_provider_reference := lower(coalesce(nullif(trim(p_provider), ''), 'stripe')) || '_' || replace(v_order_id::text, '-', '');

  update public.payments
  set provider = lower(coalesce(nullif(trim(p_provider), ''), 'stripe')),
      provider_reference = v_provider_reference,
      provider_session_reference = 'session_' || replace(v_order_id::text, '-', ''),
      status = 'pending'
  where order_id = v_order_id;

  select * into v_listing
  from public.listings
  where id = p_listing_id;

  select * into v_item
  from public.unique_items
  where id = v_listing.unique_item_id;

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
    'checkout_url', null,
    'client_secret', null,
    'expires_at', timezone('utc', now()) + interval '30 minutes',
    'amount_cents', v_listing.asking_price_cents,
    'currency', 'usd',
    'item_label', v_item.serial_number
  );
end;
$$;

grant execute on function public.get_order_item_id(uuid) to authenticated;
grant execute on function public.get_latest_payment_id(uuid) to authenticated;
grant execute on function public.can_release_order_payouts(uuid) to authenticated;
grant execute on function public.try_release_order_payouts(uuid, text) to authenticated;
grant execute on function public.attach_checkout_provider_session(uuid, text, text, text, text, text, text, jsonb) to authenticated;
grant execute on function public.record_payment_provider_webhook_event(text, text, text, jsonb, text, boolean) to authenticated;
grant execute on function public.mark_payment_provider_webhook_event_state(text, text, text, uuid, uuid, uuid, text) to authenticated;
grant execute on function public.release_resale_order_back_to_market(uuid, text) to authenticated;
grant execute on function public.mark_resale_payment_failed_or_expired(uuid, text, text, text) to authenticated;
grant execute on function public.reconcile_order_refund(uuid, text, text, int, text, text, text, jsonb) to authenticated;
