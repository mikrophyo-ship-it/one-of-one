-- Manual payment proof workflow for customer checkout and admin verification.

do $$
begin
  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'payment_status'
      and e.enumlabel = 'under_review'
  ) then
    alter type public.payment_status add value 'under_review' after 'pending';
  end if;
end
$$;

do $$
begin
  if not exists (
    select 1
    from pg_enum e
    join pg_type t on t.oid = e.enumtypid
    where t.typname = 'payment_status'
      and e.enumlabel = 'rejected'
  ) then
    alter type public.payment_status add value 'rejected' after 'under_review';
  end if;
end
$$;

insert into storage.buckets (id, name, public)
values ('payment-proofs', 'payment-proofs', false)
on conflict (id) do update
set public = excluded.public;

drop policy if exists "payment proofs owner upload" on storage.objects;
create policy "payment proofs owner upload" on storage.objects
for insert to authenticated with check (
  bucket_id = 'payment-proofs'
  and (storage.foldername(name))[1] = auth.uid()::text
);

drop policy if exists "payment proofs owner or admin read" on storage.objects;
create policy "payment proofs owner or admin read" on storage.objects
for select to authenticated using (
  bucket_id = 'payment-proofs'
  and (
    (storage.foldername(name))[1] = auth.uid()::text
    or public.is_admin_user()
  )
);

create table if not exists public.manual_payment_submissions (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  buyer_user_id uuid not null references public.users(id) on delete cascade,
  payment_method text not null,
  payer_name text not null,
  payer_phone text not null,
  paid_amount_cents int not null check (paid_amount_cents > 0),
  paid_at timestamptz not null,
  transaction_reference text,
  proof_bucket text not null default 'payment-proofs',
  proof_path text not null,
  review_status text not null default 'submitted',
  review_note text,
  reviewed_by uuid references public.users(id),
  reviewed_at timestamptz,
  created_at timestamptz not null default timezone('utc', now()),
  updated_at timestamptz not null default timezone('utc', now())
);

create index if not exists manual_payment_submissions_order_created_idx
  on public.manual_payment_submissions(order_id, created_at desc);

alter table public.manual_payment_submissions enable row level security;

drop policy if exists "manual payment submissions buyer read" on public.manual_payment_submissions;
create policy "manual payment submissions buyer read" on public.manual_payment_submissions
for select using (buyer_user_id = auth.uid() or public.is_admin_user());

drop policy if exists "manual payment submissions buyer create" on public.manual_payment_submissions;
create policy "manual payment submissions buyer create" on public.manual_payment_submissions
for insert with check (buyer_user_id = auth.uid());

create or replace function public.touch_manual_payment_submission_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at := timezone('utc', now());
  return new;
end;
$$;

drop trigger if exists set_manual_payment_submission_updated_at on public.manual_payment_submissions;
create trigger set_manual_payment_submission_updated_at
before update on public.manual_payment_submissions
for each row
execute function public.touch_manual_payment_submission_updated_at();

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
  p.status as payment_status,
  p.provider as payment_provider,
  p.provider_reference as payment_reference,
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
join lateral (
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

create or replace function public.get_my_order_payment_statuses()
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
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

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
  where status.buyer_user_id = auth.uid()
  order by status.created_at desc;
end;
$$;

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
  v_submission public.manual_payment_submissions;
  v_payment public.payments;
  v_authorization jsonb;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  if v_action not in ('approve', 'reject', 'request_resubmission') then
    raise exception 'Unsupported payment review action';
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
      review_note = coalesce(v_note, review_note),
      reviewed_by = auth.uid(),
      reviewed_at = timezone('utc', now())
  where id = v_submission.id;

  if v_action = 'request_resubmission' then
    update public.payments
    set status = 'rejected'
    where id = v_payment.id;

    insert into public.notifications (user_id, title, body)
    values (
      v_submission.buyer_user_id,
      'Payment proof needs resubmission',
      coalesce(v_note, 'Update your payment proof and resubmit it for review.')
    );
  else
    update public.payments
    set status = 'failed'
    where id = v_payment.id;

    perform public.release_resale_order_back_to_market(
      p_order_id,
      coalesce(v_note, 'Manual payment proof rejected by admin review.')
    );

    insert into public.notifications (user_id, title, body)
    values (
      v_submission.buyer_user_id,
      'Payment proof rejected',
      coalesce(v_note, 'Your payment proof was rejected. Contact support if you need assistance.')
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
  status.review_status as manual_payment_review_status,
  status.payment_method as manual_payment_method,
  status.payer_name,
  status.payer_phone,
  status.paid_amount_cents as submitted_amount_cents,
  status.paid_at,
  status.transaction_reference,
  status.proof_bucket as payment_proof_bucket,
  status.proof_path as payment_proof_path,
  status.review_note as payment_review_note,
  status.reviewed_at,
  reviewer.display_name as reviewed_by_display_name
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
left join public.user_profiles reviewer on reviewer.user_id = status.reviewed_by;

grant select on public.manual_payment_order_statuses to authenticated;
grant execute on function public.get_my_order_payment_statuses() to authenticated;
grant execute on function public.submit_manual_payment_proof(uuid, text, text, text, int, timestamptz, text, text, text) to authenticated;
grant execute on function public.admin_review_manual_payment(uuid, text, text) to authenticated;
