-- Complete admin order resolution controls for manual payment review.

create or replace function public.admin_review_manual_payment(
  p_order_id uuid,
  p_action text,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_action text := lower(trim(coalesce(p_action, '')));
  v_note text := nullif(trim(coalesce(p_note, '')), '');
  v_order public.orders;
  v_submission public.manual_payment_submissions;
  v_payment public.payments;
  v_authorization jsonb;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  if v_action not in ('approve', 'reject', 'request_resubmission', 'cancel') then
    raise exception 'Unsupported payment review action';
  end if;

  if v_action in ('reject', 'request_resubmission', 'cancel') and v_note is null then
    raise exception 'Reason is required for this order action';
  end if;

  select * into v_order
  from public.orders
  where id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if v_action = 'cancel' then
    if v_order.order_status in ('cancelled', 'fulfilled') or v_order.delivery_confirmed_at is not null then
      raise exception 'Order cannot be cancelled from its current state';
    end if;

    if v_order.order_status = 'paid' then
      raise exception 'Paid orders cannot be cancelled from this review flow';
    end if;

    select * into v_payment
    from public.payments
    where order_id = p_order_id
    order by created_at desc
    limit 1
    for update;

    select * into v_submission
    from public.manual_payment_submissions
    where order_id = p_order_id
    order by created_at desc
    limit 1
    for update;

    if v_submission.id is not null then
      update public.manual_payment_submissions
      set review_status = 'cancelled',
          review_note = v_note,
          reviewed_by = auth.uid(),
          reviewed_at = timezone('utc', now())
      where id = v_submission.id;
    end if;

    if v_payment.id is not null then
      update public.payments
      set status = 'failed'
      where id = v_payment.id
        and status <> 'captured';
    end if;

    if v_order.order_status in ('payment_pending', 'failed') then
      perform public.release_resale_order_back_to_market(
        p_order_id,
        v_note
      );
    end if;

    update public.orders
    set order_status = 'cancelled'
    where id = p_order_id
      and order_status in ('draft', 'payment_pending', 'failed');

    insert into public.notifications (user_id, title, body)
    values (
      v_order.buyer_user_id,
      'Order cancelled',
      'Your order was cancelled after admin review.'
    );

    perform public.log_audit_event(
      'order',
      p_order_id,
      'admin_cancel_order',
      jsonb_build_object('action', 'cancel', 'note', v_note)
    );

    return jsonb_build_object('order_id', p_order_id, 'action', v_action);
  end if;

  select * into v_submission
  from public.manual_payment_submissions
  where order_id = p_order_id
  order by created_at desc
  limit 1
  for update;

  if not found then
    raise exception 'Payment proof not found for order';
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

  if v_action = 'approve' then
    v_authorization := public.mark_resale_payment_authorized(
      p_order_id,
      coalesce(v_payment.provider, 'manual_transfer'),
      coalesce(
        nullif(trim(coalesce(v_submission.transaction_reference, '')), ''),
        nullif(trim(coalesce(v_payment.provider_reference, '')), ''),
        'manual_' || replace(p_order_id::text, '-', '')
      ),
      v_submission.paid_amount_cents
    );

    update public.manual_payment_submissions
    set review_status = 'approved',
        review_note = coalesce(v_note, review_note),
        reviewed_by = auth.uid(),
        reviewed_at = timezone('utc', now())
    where id = v_submission.id;

    perform public.log_audit_event(
      'order',
      p_order_id,
      'admin_review_manual_payment',
      jsonb_build_object('action', v_action, 'note', v_note, 'authorization', v_authorization)
    );

    return jsonb_build_object('order_id', p_order_id, 'action', v_action);
  end if;

  update public.manual_payment_submissions
  set review_status = case
        when v_action = 'request_resubmission' then 'resubmission_requested'
        else 'rejected'
      end,
      review_note = v_note,
      reviewed_by = auth.uid(),
      reviewed_at = timezone('utc', now())
  where id = v_submission.id;

  if v_action = 'request_resubmission' then
    update public.payments
    set status = 'rejected'
    where id = v_payment.id;

    update public.orders
    set order_status = 'payment_pending'
    where id = p_order_id
      and order_status <> 'cancelled';

    insert into public.notifications (user_id, title, body)
    values (
      v_submission.buyer_user_id,
      'Payment proof needs resubmission',
      v_note
    );
  else
    update public.payments
    set status = 'failed'
    where id = v_payment.id;

    perform public.release_resale_order_back_to_market(
      p_order_id,
      v_note
    );

    insert into public.notifications (user_id, title, body)
    values (
      v_submission.buyer_user_id,
      'Payment proof rejected',
      v_note
    );
  end if;

  perform public.log_audit_event(
    'order',
    p_order_id,
    'admin_review_manual_payment',
    jsonb_build_object('action', v_action, 'note', v_note)
  );

  return jsonb_build_object('order_id', p_order_id, 'action', v_action);
end;
$$;

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
  status.payment_status,
  status.payment_provider,
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
  ) as platform_fee_status,
  case
    when status.review_status is not null then status.review_status
    when o.order_status = 'cancelled' then 'cancelled'
    when resolution.action = 'admin_cancel_order' then 'cancelled'
    else null
  end as manual_payment_review_status,
  status.payment_method as manual_payment_method,
  status.payer_name,
  status.payer_phone,
  status.paid_amount_cents as submitted_amount_cents,
  status.paid_at,
  status.transaction_reference,
  status.proof_bucket as payment_proof_bucket,
  status.proof_path as payment_proof_path,
  coalesce(status.review_note, resolution.note) as payment_review_note,
  coalesce(status.reviewed_at, resolution.created_at) as reviewed_at,
  coalesce(reviewer.display_name, resolution_actor.display_name) as reviewed_by_display_name
from public.orders o
join public.order_items oi on oi.order_id = o.id
join public.unique_items ui on ui.id = oi.unique_item_id
join public.garment_products gp on gp.id = ui.garment_product_id
join public.artworks a on a.id = ui.artwork_id
join public.artists ar on ar.id = ui.artist_id
left join public.listings l on l.id = o.listing_id
left join public.user_profiles buyer on buyer.user_id = o.buyer_user_id
left join public.user_profiles seller on seller.user_id = o.seller_user_id
left join public.manual_payment_order_statuses status on status.order_id = o.id
left join public.user_profiles reviewer on reviewer.user_id = status.reviewed_by
left join lateral (
  select
    al.created_at,
    al.action,
    al.payload ->> 'note' as note,
    al.actor_user_id
  from public.audit_logs al
  where al.entity_type = 'order'
    and al.entity_id = o.id
    and al.action in ('admin_review_manual_payment', 'admin_cancel_order')
  order by al.created_at desc
  limit 1
) resolution on true
left join public.user_profiles resolution_actor
  on resolution_actor.user_id = resolution.actor_user_id;

grant execute on function public.admin_review_manual_payment(uuid, text, text) to authenticated;
