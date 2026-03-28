-- Fix ambiguous order_id references in manual payment workflow functions.

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
    raise exception 'Payment record not found for order';
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

  select o.* into v_order
  from public.orders o
  where o.id = p_order_id
  for update;

  if not found then
    raise exception 'Order not found';
  end if;

  if v_action = 'cancel' then
    if v_order.order_status in ('cancelled', 'fulfilled')
       or v_order.delivery_confirmed_at is not null then
      raise exception 'Order cannot be cancelled from its current state';
    end if;

    if v_order.order_status = 'paid' then
      raise exception 'Paid orders cannot be cancelled from this review flow';
    end if;

    select p.* into v_payment
    from public.payments p
    where p.order_id = p_order_id
    order by p.created_at desc
    limit 1
    for update;

    select s.* into v_submission
    from public.manual_payment_submissions s
    where s.order_id = p_order_id
    order by s.created_at desc
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

  select s.* into v_submission
  from public.manual_payment_submissions s
  where s.order_id = p_order_id
  order by s.created_at desc
  limit 1
  for update;

  if not found then
    raise exception 'Payment proof not found for order';
  end if;

  select p.* into v_payment
  from public.payments p
  where p.order_id = p_order_id
  order by p.created_at desc
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

grant execute on function public.submit_manual_payment_proof(uuid, text, text, text, int, timestamptz, text, text, text) to authenticated;
grant execute on function public.admin_review_manual_payment(uuid, text, text) to authenticated;
