-- Customer app read contract additions.

create or replace view public.public_collectible_catalog as
select
  ui.id as item_id,
  ui.serial_number,
  ui.public_qr_token,
  ui.state,
  gp.name as garment_name,
  a.id as artwork_id,
  a.title as artwork_title,
  a.story,
  a.provenance_proof,
  ar.id as artist_id,
  ar.display_name as artist_name,
  ar.authenticity_statement,
  authrec.authenticity_status,
  authrec.public_story,
  coalesce(l.id, null) as listing_id,
  coalesce(l.asking_price_cents, ui.listed_price_cents) as asking_price_cents,
  (
    select count(*)::int
    from public.ownership_transfers ot
    where ot.unique_item_id = ui.id
      and ot.transfer_status = 'completed'
  ) as verified_transfer_count
from public.unique_items ui
join public.garment_products gp on gp.id = ui.garment_product_id
join public.artworks a on a.id = ui.artwork_id
join public.artists ar on ar.id = ui.artist_id
join public.authenticity_records authrec on authrec.unique_item_id = ui.id
left join public.listings l on l.unique_item_id = ui.id and l.status = 'active';

create or replace function public.get_my_collectibles()
returns table (
  item_id uuid,
  serial_number text,
  state public.item_state,
  garment_name text,
  artwork_id uuid,
  artwork_title text,
  story text,
  artist_id uuid,
  artist_name text,
  authenticity_status text,
  asking_price_cents int,
  verified_transfer_count int,
  acquired_at timestamptz
)
language sql
security definer
set search_path = public
stable
as $$
  select
    ui.id as item_id,
    ui.serial_number,
    ui.state,
    gp.name as garment_name,
    a.id as artwork_id,
    a.title as artwork_title,
    a.story,
    ar.id as artist_id,
    ar.display_name as artist_name,
    authrec.authenticity_status,
    ui.listed_price_cents as asking_price_cents,
    (
      select count(*)::int
      from public.ownership_transfers ot
      where ot.unique_item_id = ui.id
        and ot.transfer_status = 'completed'
    ) as verified_transfer_count,
    own.acquired_at
  from public.unique_items ui
  join public.garment_products gp on gp.id = ui.garment_product_id
  join public.artworks a on a.id = ui.artwork_id
  join public.artists ar on ar.id = ui.artist_id
  join public.authenticity_records authrec on authrec.unique_item_id = ui.id
  join public.ownership_records own on own.unique_item_id = ui.id and own.relinquished_at is null
  where own.owner_user_id = auth.uid()
  order by own.acquired_at desc
$$;

create or replace function public.get_my_item_history(p_item_id uuid)
returns table (
  owner_label text,
  acquired_at timestamptz,
  relinquished_at timestamptz,
  is_current boolean
)
language sql
security definer
set search_path = public
stable
as $$
  select
    case
      when own.relinquished_at is null then 'Current verified owner'
      else 'Previous verified owner'
    end as owner_label,
    own.acquired_at,
    own.relinquished_at,
    own.relinquished_at is null as is_current
  from public.ownership_records own
  where own.unique_item_id = p_item_id
    and (
      exists (
        select 1
        from public.ownership_records mine
        where mine.unique_item_id = p_item_id
          and mine.owner_user_id = auth.uid()
      )
      or public.is_admin_user()
    )
  order by own.acquired_at asc
$$;

grant select on public.public_collectible_catalog to anon, authenticated;
grant execute on function public.get_my_collectibles() to authenticated;
grant execute on function public.get_my_item_history(uuid) to authenticated;
