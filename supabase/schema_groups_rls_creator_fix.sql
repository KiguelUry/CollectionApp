-- Permet au créateur de lire son groupe juste après l'INSERT (avant group_members).
-- Corrige la création de groupe invisible si RETURNING est bloqué par RLS.

drop policy if exists groups_select_creator on public.groups;

create policy groups_select_creator
  on public.groups
  for select
  to authenticated
  using (created_by = auth.uid());
