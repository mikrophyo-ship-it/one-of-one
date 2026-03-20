create extension if not exists "pgcrypto";

create type public.app_role as enum ('customer', 'admin', 'owner', 'artist_manager', 'support');
create type public.item_state as enum (
  'drafted',
  'minted',
  'in_inventory',
  'sold_unclaimed',
  'claimed',
  'listed_for_resale',
  'sale_pending',
  'transferred',
  'disputed',
  'stolen_flagged',
  'frozen',
  'archived'
);
create type public.order_status as enum ('draft', 'payment_pending', 'paid', 'failed', 'cancelled', 'fulfilled');
create type public.payment_status as enum ('pending', 'captured', 'failed', 'refunded');
create type public.dispute_status as enum ('open', 'under_review', 'resolved', 'rejected');

create table public.users (
  id uuid primary key references auth.users(id) on delete cascade,
  created_at timestamptz not null default timezone('utc', now())
);

create table public.user_profiles (
  user_id uuid primary key references public.users(id) on delete cascade,
  display_name text not null,
  username text unique,
  role public.app_role not null default 'customer',
  avatar_url text,
  created_at timestamptz not null default timezone('utc', now())
);

create table public.artists (
  id uuid primary key default gen_random_uuid(),
  slug text not null unique,
  display_name text not null,
  bio text,
  payout_config jsonb not null default '{}'::jsonb,
  royalty_bps int not null check (royalty_bps between 0 and 5000),
  authenticity_statement text not null,
  is_active boolean not null default true,
  created_at timestamptz not null default timezone('utc', now())
);

create table public.artworks (
  id uuid primary key default gen_random_uuid(),
  artist_id uuid not null references public.artists(id),
  title text not null,
  collection_name text,
  concept_note text not null,
  story text not null,
  creation_date date,
  provenance_proof jsonb not null default '[]'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create table public.garment_products (
  id uuid primary key default gen_random_uuid(),
  sku text not null unique,
  name text not null,
  silhouette text,
  size_label text,
  colorway text,
  base_price_cents int not null check (base_price_cents >= 0),
  created_at timestamptz not null default timezone('utc', now())
);

create table public.unique_items (
  id uuid primary key default gen_random_uuid(),
  garment_product_id uuid not null references public.garment_products(id),
  artwork_id uuid not null references public.artworks(id),
  artist_id uuid not null references public.artists(id),
  serial_number text not null unique,
  public_qr_token text not null unique,
  hidden_claim_code_hash text not null,
  state public.item_state not null default 'drafted',
  current_owner_user_id uuid references public.users(id),
  minted_at timestamptz,
  listed_price_cents int,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create table public.authenticity_records (
  id uuid primary key default gen_random_uuid(),
  unique_item_id uuid not null unique references public.unique_items(id) on delete cascade,
  authenticity_status text not null,
  public_story text not null,
  visibility_label text not null default 'platform-verified',
  created_at timestamptz not null default timezone('utc', now())
);

create table public.ownership_records (
  id uuid primary key default gen_random_uuid(),
  unique_item_id uuid not null references public.unique_items(id) on delete cascade,
  owner_user_id uuid not null references public.users(id),
  acquired_at timestamptz not null default timezone('utc', now()),
  relinquished_at timestamptz,
  acquisition_type text not null,
  visibility_label text not null default 'private_owner'
);

create unique index ownership_records_open_unique
  on public.ownership_records(unique_item_id)
  where relinquished_at is null;

create table public.ownership_transfers (
  id uuid primary key default gen_random_uuid(),
  unique_item_id uuid not null references public.unique_items(id) on delete cascade,
  from_owner_user_id uuid references public.users(id),
  to_owner_user_id uuid references public.users(id),
  order_id uuid,
  transfer_source text not null default 'marketplace_checkout',
  transfer_status text not null,
  v2_transfer_channel text,
  created_at timestamptz not null default timezone('utc', now())
);

create table public.listings (
  id uuid primary key default gen_random_uuid(),
  unique_item_id uuid not null unique references public.unique_items(id) on delete cascade,
  seller_user_id uuid not null references public.users(id),
  asking_price_cents int not null check (asking_price_cents > 0),
  status text not null default 'active',
  created_at timestamptz not null default timezone('utc', now())
);

create table public.orders (
  id uuid primary key default gen_random_uuid(),
  buyer_user_id uuid not null references public.users(id),
  seller_user_id uuid references public.users(id),
  listing_id uuid references public.listings(id),
  order_status public.order_status not null default 'draft',
  subtotal_cents int not null check (subtotal_cents >= 0),
  total_cents int not null check (total_cents >= 0),
  created_at timestamptz not null default timezone('utc', now())
);

create table public.order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  unique_item_id uuid not null references public.unique_items(id),
  unit_price_cents int not null
);

create table public.payments (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  provider text not null,
  provider_reference text,
  status public.payment_status not null default 'pending',
  amount_cents int not null,
  created_at timestamptz not null default timezone('utc', now())
);

create table public.payout_ledgers (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  seller_user_id uuid not null references public.users(id),
  amount_cents int not null,
  status text not null default 'pending',
  created_at timestamptz not null default timezone('utc', now())
);

create table public.royalty_ledgers (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  artist_id uuid not null references public.artists(id),
  amount_cents int not null,
  status text not null default 'pending',
  created_at timestamptz not null default timezone('utc', now())
);

create table public.platform_fee_ledgers (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.orders(id) on delete cascade,
  amount_cents int not null,
  status text not null default 'captured',
  created_at timestamptz not null default timezone('utc', now())
);

create table public.disputes (
  id uuid primary key default gen_random_uuid(),
  unique_item_id uuid not null references public.unique_items(id),
  order_id uuid references public.orders(id),
  reported_by_user_id uuid not null references public.users(id),
  reason text not null,
  details text,
  status public.dispute_status not null default 'open',
  created_at timestamptz not null default timezone('utc', now())
);

create table public.audit_logs (
  id uuid primary key default gen_random_uuid(),
  actor_user_id uuid references public.users(id),
  entity_type text not null,
  entity_id uuid,
  action text not null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default timezone('utc', now())
);

create table public.notifications (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.users(id) on delete cascade,
  title text not null,
  body text not null,
  read_at timestamptz,
  created_at timestamptz not null default timezone('utc', now())
);

create table public.admin_notes (
  id uuid primary key default gen_random_uuid(),
  entity_type text not null,
  entity_id uuid not null,
  note text not null,
  admin_user_id uuid not null references public.users(id),
  created_at timestamptz not null default timezone('utc', now())
);

create table public.media_assets (
  id uuid primary key default gen_random_uuid(),
  storage_bucket text not null,
  storage_path text not null,
  media_type text not null,
  visibility text not null default 'private',
  linked_entity_type text not null,
  linked_entity_id uuid not null,
  created_at timestamptz not null default timezone('utc', now())
);

create table public.platform_settings (
  id boolean primary key default true,
  platform_fee_bps int not null default 1000,
  default_royalty_bps int not null default 1200,
  marketplace_rules jsonb not null default '{}'::jsonb,
  brand_settings jsonb not null default '{}'::jsonb
);

insert into public.platform_settings (id) values (true)
on conflict (id) do nothing;

create or replace function public.current_app_role()
returns public.app_role
language sql
stable
as $$
  select coalesce((select role from public.user_profiles where user_id = auth.uid()), 'customer'::public.app_role)
$$;

create or replace function public.is_admin_user()
returns boolean
language sql
stable
as $$
  select public.current_app_role() in ('admin', 'owner', 'artist_manager', 'support')
$$;

create or replace function public.log_audit_event(p_entity_type text, p_entity_id uuid, p_action text, p_payload jsonb default '{}'::jsonb)
returns void
language plpgsql
security definer
as $$
begin
  insert into public.audit_logs (actor_user_id, entity_type, entity_id, action, payload)
  values (auth.uid(), p_entity_type, p_entity_id, p_action, p_payload);
end;
$$;

create or replace function public.assert_item_is_actionable(p_item_id uuid)
returns public.unique_items
language plpgsql
security definer
as $$
declare
  v_item public.unique_items;
begin
  select * into v_item from public.unique_items where id = p_item_id for update;
  if not found then
    raise exception 'Item not found';
  end if;
  if v_item.state in ('disputed', 'stolen_flagged', 'frozen') then
    raise exception 'Restricted items cannot be claimed, listed, sold, or transferred';
  end if;
  return v_item;
end;
$$;

create or replace function public.claim_item_ownership(p_item_id uuid, p_claim_code text)
returns uuid
language plpgsql
security definer
as $$
declare
  v_item public.unique_items;
  v_profile public.user_profiles;
  v_ownership_id uuid;
begin
  select * into v_profile from public.user_profiles where user_id = auth.uid();
  if v_profile.user_id is null then
    raise exception 'Profile required before claim';
  end if;

  v_item := public.assert_item_is_actionable(p_item_id);
  if v_item.state <> 'sold_unclaimed' then
    raise exception 'Item is not claimable';
  end if;
  if v_item.hidden_claim_code_hash <> encode(digest(p_claim_code, 'sha256'), 'hex') then
    raise exception 'Claim code invalid';
  end if;
  if exists (
    select 1 from public.ownership_records
    where unique_item_id = p_item_id and relinquished_at is null
  ) then
    raise exception 'Ownership already claimed';
  end if;

  update public.unique_items
  set current_owner_user_id = auth.uid(),
      state = 'claimed'
  where id = p_item_id;

  insert into public.ownership_records (unique_item_id, owner_user_id, acquisition_type)
  values (p_item_id, auth.uid(), 'claim')
  returning id into v_ownership_id;

  perform public.log_audit_event('unique_item', p_item_id, 'claim_item', jsonb_build_object('ownership_record_id', v_ownership_id));
  return v_ownership_id;
end;
$$;

create or replace function public.create_resale_listing(p_item_id uuid, p_price_cents int)
returns uuid
language plpgsql
security definer
as $$
declare
  v_item public.unique_items;
  v_listing_id uuid;
begin
  v_item := public.assert_item_is_actionable(p_item_id);
  if v_item.current_owner_user_id <> auth.uid() then
    raise exception 'Only the current owner can list this item';
  end if;
  if v_item.state not in ('claimed', 'transferred') then
    raise exception 'Item is not eligible for resale';
  end if;

  insert into public.listings (unique_item_id, seller_user_id, asking_price_cents)
  values (p_item_id, auth.uid(), p_price_cents)
  returning id into v_listing_id;

  update public.unique_items
  set state = 'listed_for_resale', listed_price_cents = p_price_cents
  where id = p_item_id;

  perform public.log_audit_event('listing', v_listing_id, 'create_listing', jsonb_build_object('item_id', p_item_id, 'price_cents', p_price_cents));
  return v_listing_id;
end;
$$;

create or replace function public.complete_resale_order(p_order_id uuid)
returns uuid
language plpgsql
security definer
as $$
declare
  v_order public.orders;
  v_listing public.listings;
  v_item public.unique_items;
  v_platform_fee_bps int;
  v_royalty_bps int;
  v_platform_fee int;
  v_royalty_fee int;
  v_seller_payout int;
  v_transfer_id uuid;
begin
  select * into v_order from public.orders where id = p_order_id for update;
  if v_order.order_status <> 'paid' then
    raise exception 'Order must be paid before ownership transfer';
  end if;

  select * into v_listing from public.listings where id = v_order.listing_id for update;
  v_item := public.assert_item_is_actionable(v_listing.unique_item_id);

  select platform_fee_bps, default_royalty_bps into v_platform_fee_bps, v_royalty_bps from public.platform_settings where id = true;
  select coalesce(royalty_bps, v_royalty_bps) into v_royalty_bps from public.artists where id = v_item.artist_id;

  v_platform_fee := round(v_order.total_cents * v_platform_fee_bps / 10000.0);
  v_royalty_fee := round(v_order.total_cents * v_royalty_bps / 10000.0);
  v_seller_payout := v_order.total_cents - v_platform_fee - v_royalty_fee;

  update public.ownership_records
  set relinquished_at = timezone('utc', now())
  where unique_item_id = v_item.id and relinquished_at is null;

  insert into public.ownership_records (unique_item_id, owner_user_id, acquisition_type)
  values (v_item.id, v_order.buyer_user_id, 'resale_checkout');

  update public.unique_items
  set current_owner_user_id = v_order.buyer_user_id,
      state = 'transferred',
      listed_price_cents = null
  where id = v_item.id;

  update public.listings
  set status = 'sold'
  where id = v_listing.id;

  insert into public.payout_ledgers (order_id, seller_user_id, amount_cents)
  values (v_order.id, v_order.seller_user_id, v_seller_payout);

  insert into public.royalty_ledgers (order_id, artist_id, amount_cents)
  values (v_order.id, v_item.artist_id, v_royalty_fee);

  insert into public.platform_fee_ledgers (order_id, amount_cents)
  values (v_order.id, v_platform_fee);

  insert into public.ownership_transfers (
    unique_item_id,
    from_owner_user_id,
    to_owner_user_id,
    order_id,
    transfer_status,
    transfer_source
  ) values (
    v_item.id,
    v_order.seller_user_id,
    v_order.buyer_user_id,
    v_order.id,
    'completed',
    'marketplace_checkout'
  ) returning id into v_transfer_id;

  perform public.log_audit_event('order', v_order.id, 'complete_resale_order', jsonb_build_object('transfer_id', v_transfer_id));
  return v_transfer_id;
end;
$$;

alter table public.user_profiles enable row level security;
alter table public.artists enable row level security;
alter table public.artworks enable row level security;
alter table public.unique_items enable row level security;
alter table public.authenticity_records enable row level security;
alter table public.ownership_records enable row level security;
alter table public.listings enable row level security;
alter table public.orders enable row level security;
alter table public.notifications enable row level security;
alter table public.disputes enable row level security;
alter table public.audit_logs enable row level security;
alter table public.admin_notes enable row level security;
alter table public.media_assets enable row level security;
alter table public.platform_settings enable row level security;

create policy "profiles self read" on public.user_profiles
for select using (user_id = auth.uid() or public.is_admin_user());

create policy "profiles self upsert" on public.user_profiles
for all using (user_id = auth.uid() or public.is_admin_user())
with check (user_id = auth.uid() or public.is_admin_user());

create policy "artists public read" on public.artists
for select using (true);

create policy "artists admin write" on public.artists
for all using (public.is_admin_user())
with check (public.is_admin_user());

create policy "artworks public read" on public.artworks
for select using (true);

create policy "artworks admin write" on public.artworks
for all using (public.is_admin_user())
with check (public.is_admin_user());

create policy "unique items public authenticity read" on public.unique_items
for select using (true);

create policy "unique items admin write" on public.unique_items
for all using (public.is_admin_user())
with check (public.is_admin_user());

create policy "ownership owner read" on public.ownership_records
for select using (owner_user_id = auth.uid() or public.is_admin_user());

create policy "listings public read" on public.listings
for select using (true);

create policy "listings owner write" on public.listings
for all using (seller_user_id = auth.uid() or public.is_admin_user())
with check (seller_user_id = auth.uid() or public.is_admin_user());

create policy "orders participant read" on public.orders
for select using (buyer_user_id = auth.uid() or seller_user_id = auth.uid() or public.is_admin_user());

create policy "orders buyer create" on public.orders
for insert with check (buyer_user_id = auth.uid() or public.is_admin_user());

create policy "notifications owner read" on public.notifications
for select using (user_id = auth.uid() or public.is_admin_user());

create policy "disputes actor read" on public.disputes
for select using (reported_by_user_id = auth.uid() or public.is_admin_user());

create policy "disputes reporter create" on public.disputes
for insert with check (reported_by_user_id = auth.uid() or public.is_admin_user());

create policy "audit admin read" on public.audit_logs
for select using (public.is_admin_user());

create policy "admin notes admin only" on public.admin_notes
for all using (public.is_admin_user()) with check (public.is_admin_user());

create policy "media assets public read if public" on public.media_assets
for select using (visibility = 'public' or public.is_admin_user());

create policy "platform settings public read" on public.platform_settings
for select using (true);

comment on table public.media_assets is 'Suggested buckets: public-authenticity, artist-proof-private, garment-editorial, claim-code-packaging-private';
