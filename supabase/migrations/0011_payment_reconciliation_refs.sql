-- Persist Stripe object references used for later webhook reconciliation.

create or replace function public.record_payment_provider_object_refs(
  p_order_id uuid,
  p_checkout_session_id text default null,
  p_payment_intent_id text default null,
  p_latest_charge_id text default null,
  p_webhook_event_id text default null,
  p_webhook_event_type text default null,
  p_event_created_at timestamptz default null
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
  set checkout_session_id = coalesce(nullif(trim(p_checkout_session_id), ''), checkout_session_id),
      payment_intent_id = coalesce(nullif(trim(p_payment_intent_id), ''), payment_intent_id),
      latest_charge_id = coalesce(nullif(trim(p_latest_charge_id), ''), latest_charge_id),
      last_webhook_event_id = coalesce(nullif(trim(p_webhook_event_id), ''), last_webhook_event_id),
      last_webhook_event_type = coalesce(nullif(trim(p_webhook_event_type), ''), last_webhook_event_type),
      last_event_created_at = coalesce(p_event_created_at, last_event_created_at)
  where id = v_payment.id;

  return jsonb_build_object(
    'payment_id', v_payment.id,
    'order_id', p_order_id,
    'checkout_session_id', coalesce(nullif(trim(p_checkout_session_id), ''), v_payment.checkout_session_id),
    'payment_intent_id', coalesce(nullif(trim(p_payment_intent_id), ''), v_payment.payment_intent_id),
    'latest_charge_id', coalesce(nullif(trim(p_latest_charge_id), ''), v_payment.latest_charge_id)
  );
end;
$$;

grant execute on function public.record_payment_provider_object_refs(uuid, text, text, text, text, text, timestamptz) to authenticated;
