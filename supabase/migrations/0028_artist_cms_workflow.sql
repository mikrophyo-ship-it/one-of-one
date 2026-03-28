alter table public.artists
  add column if not exists short_bio text,
  add column if not exists full_bio text,
  add column if not exists artist_statement text,
  add column if not exists instagram_url text,
  add column if not exists website_url text,
  add column if not exists is_featured boolean not null default false,
  add column if not exists sort_order int not null default 0,
  add column if not exists profile_status text not null default 'draft',
  add column if not exists portrait_media_asset_id uuid references public.media_assets(id) on delete set null,
  add column if not exists hero_media_asset_id uuid references public.media_assets(id) on delete set null,
  add column if not exists created_by uuid references auth.users(id) on delete set null,
  add column if not exists updated_by uuid references auth.users(id) on delete set null,
  add column if not exists approved_by uuid references auth.users(id) on delete set null,
  add column if not exists updated_at timestamptz not null default timezone('utc', now()),
  add column if not exists approved_at timestamptz;

update public.artists
set profile_status = case when is_active then 'published' else 'archived' end
where profile_status not in ('draft', 'published', 'archived');

alter table public.artists
  drop constraint if exists artists_profile_status_check;

alter table public.artists
  add constraint artists_profile_status_check
  check (profile_status in ('draft', 'published', 'archived'));

insert into storage.buckets (id, name, public)
values ('artist-editorial', 'artist-editorial', true)
on conflict (id) do nothing;

do $$
begin
  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'artist editorial public read'
  ) then
    create policy "artist editorial public read"
    on storage.objects
    for select
    to public
    using (bucket_id = 'artist-editorial');
  end if;

  if not exists (
    select 1
    from pg_policies
    where schemaname = 'storage'
      and tablename = 'objects'
      and policyname = 'artist editorial admin manage'
  ) then
    create policy "artist editorial admin manage"
    on storage.objects
    for all
    to authenticated
    using (
      bucket_id = 'artist-editorial'
      and public.current_app_role() in ('admin', 'owner', 'artist_manager', 'support')
    )
    with check (
      bucket_id = 'artist-editorial'
      and public.current_app_role() in ('admin', 'owner', 'artist_manager', 'support')
    );
  end if;
end
$$;

drop function if exists public.get_admin_artist_directory();
drop view if exists public.admin_artist_directory;

create view public.admin_artist_directory
with (security_invoker = true) as
select
  ar.id as artist_id,
  ar.display_name,
  ar.slug,
  ar.royalty_bps,
  ar.authenticity_statement,
  ar.short_bio,
  ar.full_bio,
  ar.artist_statement,
  ar.instagram_url,
  ar.website_url,
  ar.is_featured,
  ar.sort_order,
  ar.profile_status,
  ar.updated_at,
  portrait.storage_bucket as portrait_storage_bucket,
  portrait.storage_path as portrait_storage_path,
  hero.storage_bucket as hero_storage_bucket,
  hero.storage_path as hero_storage_path,
  (select count(*)::int from public.artworks aw where aw.artist_id = ar.id) as artwork_count,
  (select count(*)::int from public.unique_items ui where ui.artist_id = ar.id) as inventory_count
from public.artists ar
left join public.media_assets portrait on portrait.id = ar.portrait_media_asset_id
left join public.media_assets hero on hero.id = ar.hero_media_asset_id;

create or replace function public.get_admin_artist_directory()
returns setof public.admin_artist_directory
language plpgsql
security definer
set search_path = public
as $$
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  return query
  select *
  from public.admin_artist_directory
  order by sort_order asc, display_name asc;
end;
$$;

create or replace function public.admin_upsert_artist(
  p_display_name text,
  p_slug text,
  p_royalty_bps int,
  p_authenticity_statement text,
  p_short_bio text default null,
  p_full_bio text default null,
  p_artist_statement text default null,
  p_instagram_url text default null,
  p_website_url text default null,
  p_is_featured boolean default false,
  p_sort_order int default 0,
  p_profile_status text default 'draft',
  p_artist_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_artist_id uuid;
  v_user_id uuid := auth.uid();
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  if p_profile_status not in ('draft', 'published', 'archived') then
    raise exception 'Invalid profile status';
  end if;

  if p_artist_id is null then
    insert into public.artists (
      display_name,
      slug,
      royalty_bps,
      authenticity_statement,
      short_bio,
      full_bio,
      artist_statement,
      instagram_url,
      website_url,
      is_featured,
      sort_order,
      profile_status,
      is_active,
      created_by,
      updated_by,
      approved_by,
      approved_at
    ) values (
      p_display_name,
      p_slug,
      p_royalty_bps,
      p_authenticity_statement,
      nullif(trim(p_short_bio), ''),
      nullif(trim(p_full_bio), ''),
      nullif(trim(p_artist_statement), ''),
      nullif(trim(p_instagram_url), ''),
      nullif(trim(p_website_url), ''),
      p_is_featured,
      p_sort_order,
      p_profile_status,
      p_profile_status = 'published',
      v_user_id,
      v_user_id,
      case when p_profile_status = 'published' then v_user_id else null end,
      case when p_profile_status = 'published' then timezone('utc', now()) else null end
    ) returning id into v_artist_id;
  else
    update public.artists
    set display_name = p_display_name,
        slug = p_slug,
        royalty_bps = p_royalty_bps,
        authenticity_statement = p_authenticity_statement,
        short_bio = nullif(trim(p_short_bio), ''),
        full_bio = nullif(trim(p_full_bio), ''),
        artist_statement = nullif(trim(p_artist_statement), ''),
        instagram_url = nullif(trim(p_instagram_url), ''),
        website_url = nullif(trim(p_website_url), ''),
        is_featured = p_is_featured,
        sort_order = p_sort_order,
        profile_status = p_profile_status,
        is_active = p_profile_status = 'published',
        updated_by = v_user_id,
        updated_at = timezone('utc', now()),
        approved_by = case when p_profile_status = 'published' then v_user_id else approved_by end,
        approved_at = case when p_profile_status = 'published' then timezone('utc', now()) else approved_at end
    where id = p_artist_id
    returning id into v_artist_id;
  end if;

  perform public.log_audit_event(
    'artist',
    v_artist_id,
    'admin_upsert_artist',
    jsonb_build_object(
      'slug', p_slug,
      'royalty_bps', p_royalty_bps,
      'profile_status', p_profile_status,
      'is_featured', p_is_featured,
      'sort_order', p_sort_order
    )
  );

  return v_artist_id;
end;
$$;

create or replace function public.admin_attach_artist_media_asset(
  p_artist_id uuid,
  p_slot text,
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
  v_media_id uuid;
  v_existing_media_id uuid;
  v_entity_type text;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  if p_slot not in ('portrait', 'hero') then
    raise exception 'Invalid artist media slot';
  end if;

  select case
    when p_slot = 'portrait' then ar.portrait_media_asset_id
    else ar.hero_media_asset_id
  end
  into v_existing_media_id
  from public.artists ar
  where ar.id = p_artist_id
  for update;

  if v_existing_media_id is not null then
    raise exception 'This artist already has media attached for that slot';
  end if;

  v_entity_type := case when p_slot = 'portrait' then 'artist_portrait' else 'artist_hero' end;

  insert into public.media_assets (
    linked_entity_type,
    linked_entity_id,
    storage_bucket,
    storage_path,
    media_type,
    visibility
  ) values (
    v_entity_type,
    p_artist_id,
    p_storage_bucket,
    p_storage_path,
    p_media_type,
    p_visibility
  ) returning id into v_media_id;

  update public.artists
  set portrait_media_asset_id = case when p_slot = 'portrait' then v_media_id else portrait_media_asset_id end,
      hero_media_asset_id = case when p_slot = 'hero' then v_media_id else hero_media_asset_id end,
      updated_by = auth.uid(),
      updated_at = timezone('utc', now())
  where id = p_artist_id;

  perform public.log_audit_event(
    'artist',
    p_artist_id,
    'admin_attach_artist_media_asset',
    jsonb_build_object('slot', p_slot, 'media_asset_id', v_media_id)
  );

  return v_media_id;
end;
$$;

create or replace function public.admin_remove_artist_media_asset(
  p_artist_id uuid,
  p_slot text
)
returns table (storage_bucket text, storage_path text)
language plpgsql
security definer
set search_path = public
as $$
declare
  v_media_id uuid;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  if p_slot not in ('portrait', 'hero') then
    raise exception 'Invalid artist media slot';
  end if;

  select case
    when p_slot = 'portrait' then ar.portrait_media_asset_id
    else ar.hero_media_asset_id
  end
  into v_media_id
  from public.artists ar
  where ar.id = p_artist_id
  for update;

  if v_media_id is null then
    return;
  end if;

  update public.artists
  set portrait_media_asset_id = case when p_slot = 'portrait' then null else portrait_media_asset_id end,
      hero_media_asset_id = case when p_slot = 'hero' then null else hero_media_asset_id end,
      updated_by = auth.uid(),
      updated_at = timezone('utc', now())
  where id = p_artist_id;

  return query
  delete from public.media_assets ma
  where ma.id = v_media_id
  returning ma.storage_bucket, ma.storage_path;

  perform public.log_audit_event(
    'artist',
    p_artist_id,
    'admin_remove_artist_media_asset',
    jsonb_build_object('slot', p_slot)
  );
end;
$$;

grant execute on function public.get_admin_artist_directory() to authenticated;
grant execute on function public.admin_upsert_artist(text, text, int, text, text, text, text, text, text, boolean, int, text, uuid) to authenticated;
grant execute on function public.admin_attach_artist_media_asset(uuid, text, text, text, text, text) to authenticated;
grant execute on function public.admin_remove_artist_media_asset(uuid, text) to authenticated;
