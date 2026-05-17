-- =============================================================================
-- Personnalisation des groupes : couleur, icône, photo
-- À exécuter dans Supabase → SQL Editor
-- =============================================================================

alter table public.groups
  add column if not exists accent_color text default '#673AB7',
  add column if not exists icon_key text default 'groups',
  add column if not exists avatar_url text;

alter table public.groups
  drop constraint if exists groups_icon_key_check;

alter table public.groups
  add constraint groups_icon_key_check
  check (
    icon_key is null
    or icon_key in (
      'groups', 'family_restroom', 'home', 'favorite', 'casino',
      'sports_esports', 'pets', 'celebration', 'school', 'travel_explore',
      'restaurant', 'music_note'
    )
  );

-- Bucket photos de groupe
insert into storage.buckets (id, name, public)
values ('group-avatars', 'group-avatars', true)
on conflict (id) do update set public = true;

drop policy if exists "Group avatars public read" on storage.objects;
create policy "Group avatars public read"
  on storage.objects for select
  using (bucket_id = 'group-avatars');

drop policy if exists "Group creator upload avatar" on storage.objects;
create policy "Group creator upload avatar"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'group-avatars'
    and exists (
      select 1 from public.groups g
      where g.id::text = (storage.foldername(name))[1]
        and g.created_by = auth.uid()
    )
  );

drop policy if exists "Group creator update avatar" on storage.objects;
create policy "Group creator update avatar"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'group-avatars'
    and exists (
      select 1 from public.groups g
      where g.id::text = (storage.foldername(name))[1]
        and g.created_by = auth.uid()
    )
  );

drop policy if exists "Group creator delete avatar" on storage.objects;
create policy "Group creator delete avatar"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'group-avatars'
    and exists (
      select 1 from public.groups g
      where g.id::text = (storage.foldername(name))[1]
        and g.created_by = auth.uid()
    )
  );

-- Mise à jour du groupe par son créateur
drop policy if exists "Group creator can update" on public.groups;
create policy "Group creator can update"
  on public.groups for update
  to authenticated
  using (created_by = auth.uid())
  with check (created_by = auth.uid());
