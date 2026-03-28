-- Customer notification read-state support.

create or replace function public.mark_my_notifications_read(
  p_notification_ids uuid[] default null
)
returns int
language plpgsql
security definer
set search_path = public
as $$
declare
  v_updated int := 0;
begin
  if auth.uid() is null then
    raise exception 'Authentication required';
  end if;

  update public.notifications n
  set read_at = coalesce(n.read_at, timezone('utc', now()))
  where n.user_id = auth.uid()
    and n.read_at is null
    and (
      p_notification_ids is null
      or n.id = any(p_notification_ids)
    );

  get diagnostics v_updated = row_count;
  return v_updated;
end;
$$;

grant execute on function public.mark_my_notifications_read(uuid[]) to authenticated;
