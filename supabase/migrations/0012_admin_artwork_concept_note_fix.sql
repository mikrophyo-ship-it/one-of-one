-- Keep the V2 admin artwork upsert contract compatible with the base schema.
-- The current admin UI sends a single narrative field, while artworks still
-- require both concept_note and story.

create or replace function public.admin_upsert_artwork(
  p_artist_id uuid,
  p_title text,
  p_story text,
  p_provenance_proof text[] default '{}',
  p_creation_date timestamptz default null,
  p_artwork_id uuid default null
)
returns uuid
language plpgsql
security definer
set search_path = public
as $$
declare
  v_artwork_id uuid;
begin
  if not public.is_admin_user() then
    raise exception 'Admin access required';
  end if;

  if p_artwork_id is null then
    insert into public.artworks (
      artist_id,
      title,
      concept_note,
      story,
      provenance_proof,
      creation_date
    ) values (
      p_artist_id,
      p_title,
      p_story,
      p_story,
      to_jsonb(p_provenance_proof),
      p_creation_date::date
    ) returning id into v_artwork_id;
  else
    update public.artworks
    set artist_id = p_artist_id,
        title = p_title,
        concept_note = p_story,
        story = p_story,
        provenance_proof = to_jsonb(p_provenance_proof),
        creation_date = p_creation_date::date
    where id = p_artwork_id
    returning id into v_artwork_id;
  end if;

  perform public.log_audit_event(
    'artwork',
    v_artwork_id,
    'admin_upsert_artwork',
    jsonb_build_object('artist_id', p_artist_id, 'title', p_title)
  );

  return v_artwork_id;
end;
$$;

grant execute on function public.admin_upsert_artwork(uuid, text, text, text[], timestamptz, uuid) to authenticated;
