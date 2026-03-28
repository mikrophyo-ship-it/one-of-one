-- Ensure public comment reads can resolve commenter display names safely
-- through the trusted SQL function path.

create or replace function public.get_public_item_comments(p_item_id uuid)
returns table (
  comment_id uuid,
  item_id uuid,
  user_display_name text,
  body text,
  created_at timestamptz
)
language sql
security definer
set search_path = public
as $$
  select
    ic.id as comment_id,
    ic.unique_item_id as item_id,
    coalesce(
      nullif(trim(up.display_name), ''),
      nullif(trim(up.username), ''),
      'Collector'
    ) as user_display_name,
    ic.body,
    ic.created_at
  from public.item_comments ic
  join public.public_collectible_catalog catalog
    on catalog.item_id = ic.unique_item_id
  left join public.user_profiles up on up.user_id = ic.user_id
  where ic.unique_item_id = p_item_id
  order by ic.created_at desc
$$;

grant execute on function public.get_public_item_comments(uuid) to anon, authenticated;
