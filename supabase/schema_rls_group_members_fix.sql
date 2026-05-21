-- Correctif prod : « infinite recursion detected in policy for relation group_members »
-- Exécuter dans Supabase → SQL Editor (une fois).

create or replace function public.is_group_member(
  p_group_id uuid,
  p_profile_id uuid default auth.uid()
)
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select exists (
    select 1
    from public.group_members gm
    where gm.group_id = p_group_id
      and gm.profile_id = p_profile_id
  );
$$;

revoke all on function public.is_group_member(uuid, uuid) from public;
grant execute on function public.is_group_member(uuid, uuid) to authenticated;

drop policy if exists group_members_select_member on public.group_members;

create policy group_members_select_member
  on public.group_members
  for select
  to authenticated
  using (public.is_group_member(group_id));
