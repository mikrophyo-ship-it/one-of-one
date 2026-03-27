-- Customer-facing item media and comments, plus admin media attachment helpers.

insert into storage.buckets (id, name, public)
values ('garment-editorial', 'garment-editorial', true)
on conflict (id) do update
set public = excluded.public;

drop policy if exists "garment editorial public read" on storage.objects;
create policy "garment editorial public read" on storage.objects
for select using (bucket_id = 'garment-editorial');

drop policy if exists "garment editorial admin write" on storage.objects;
create policy "garment editorial admin write" on storage.objects
for insert to authenticated with check (
  bucket_id = 'garment-editorial'
  and public.is_admin_user()
);

drop policy if exists "garment editorial admin update" on storage.objects;
create policy "garment editorial admin update" on storage.objects
for update to authenticated using (
  bucket_id = 'garment-editorial'
  and public.is_admin_user()
)
with check (
  bucket_id = 'garment-editorial'
  and public.is_admin_user()
);

create table if not exists public.item_comments (
  id uuid primary key default gen_random_uuid(),
  unique_item_id uuid not null references public.unique_items(id) on delete cascade,
  user_id uuid not null,
  body text not null,
  created_at timestamptz not null default timezone('utc', now())
);

alter table public.item_comments enable row level security;

drop policy if exists "item comments public read" on public.item_comments;
create policy "item comments public read" on public.item_comments
for select using (true);

drop policy if exists "item comments owner create" on public.item_comments;
create policy "item comments owner create" on public.item_comments
for insert with check (user_id = auth.uid());

create or replace function public.get_public_item_comments()
returns table (
  comment_id uuid,
  item_id uuid,
  user_display_name text,
  body text,
  created_at timestamptz
)
language sql
security invoker
set search_path = public
as $$
  select
    ic.id as comment_id,
    ic.unique_item_id as item_id,
    coalesce(up.display_name, up.username, 'Collector') as user_display_name,
    ic.body,
    ic.created_at
  from public.item_comments ic
  left join public.user_profiles up on up.user_id = ic.user_id
  order by ic.created_at desc
$$;

create or replace function public.add_item_comment(
  p_item_id uuid,
  p_body text
)
returns table (
  comment_id uuid,
  item_id uuid,
  user_display_name text,
  body text,
  created_at timestamptz
)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile public.user_profiles;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  select * into v_profile
  from public.user_profiles
  where user_id = auth.uid();

  if v_profile.user_id is null then
    raise exception 'Profile not found for authenticated user';
  end if;

  if not exists (select 1 from public.unique_items where id = p_item_id) then
    raise exception 'Collectible not found';
  end if;

  if nullif(trim(p_body), '') is null then
    raise exception 'Comment body is required';
  end if;

  insert into public.item_comments (unique_item_id, user_id, body)
  values (p_item_id, auth.uid(), trim(p_body));

  return query
  select
    ic.id as comment_id,
    ic.unique_item_id as item_id,
    coalesce(v_profile.display_name, v_profile.username, 'Collector') as user_display_name,
    ic.body,
    ic.created_at
  from public.item_comments ic
  where ic.user_id = auth.uid()
    and ic.unique_item_id = p_item_id
  order by ic.created_at desc
  limit 1;
end;
$$;

create or replace function public.admin_attach_item_media_asset(
  p_item_id uuid,
  p_storage_bucket text,
  p_storage_path text,
  p_media_type text,
  p_visibility text default 'public'
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_asset_id uuid;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  if not exists (select 1 from public.unique_items where id = p_item_id) then
    raise exception 'Inventory item not found';
  end if;

  insert into public.media_assets (
    storage_bucket,
    storage_path,
    media_type,
    visibility,
    linked_entity_type,
    linked_entity_id
  ) values (
    p_storage_bucket,
    p_storage_path,
    p_media_type,
    coalesce(nullif(trim(p_visibility), ''), 'public'),
    'unique_item',
    p_item_id
  )
  returning id into v_asset_id;

  perform public.log_audit_event(
    'media_asset',
    v_asset_id,
    'admin_attach_item_media_asset',
    jsonb_build_object(
      'item_id', p_item_id,
      'storage_bucket', p_storage_bucket,
      'storage_path', p_storage_path,
      'media_type', p_media_type
    )
  );

  return v_asset_id;
end;
$$;

grant execute on function public.get_public_item_comments() to anon, authenticated;
grant execute on function public.add_item_comment(uuid, text) to authenticated;
grant execute on function public.admin_attach_item_media_asset(uuid, text, text, text, text) to authenticated;
