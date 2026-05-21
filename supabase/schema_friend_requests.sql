-- Demandes d'amitié + visibilité collections entre amis
-- NE PAS ré-exécuter en prod si schema_rls_fix_live.sql a déjà été appliqué
-- (cette version enlève share_collections sur collection_items_select).
-- Exécuter dans Supabase → SQL Editor (nouvelle base uniquement)

-- Nouvelles amitiés en attente (les existantes « accepted » restent inchangées)
alter table public.friendships
  alter column status set default 'pending';

-- Profils : confidentialité (sync app à venir ; colonnes prêtes côté serveur)
alter table public.profiles
  add column if not exists hide_collection_from_non_friends boolean not null default true,
  add column if not exists hide_collection_from_friends boolean not null default false;

-- Lecture collection_items : amis acceptés voient sans exiger share_collections
drop policy if exists "collection_items_select" on public.collection_items;

create policy "collection_items_select"
  on public.collection_items
  for select
  to authenticated
  using (
    (
      group_id is null
      and (
        added_by = auth.uid()
        or location_user_id = auth.uid()
      )
    )
    or (
      group_id is not null
      and exists (
        select 1
        from public.group_members gm
        where gm.group_id = collection_items.group_id
          and gm.profile_id = auth.uid()
      )
    )
    or (
      group_id is null
      and exists (
        select 1
        from public.friendships f
        where f.status = 'accepted'
          and (
            (
              f.requester_id = auth.uid()
              and f.addressee_id in (
                collection_items.added_by,
                collection_items.location_user_id
              )
            )
            or (
              f.addressee_id = auth.uid()
              and f.requester_id in (
                collection_items.added_by,
                collection_items.location_user_id
              )
            )
          )
      )
    )
  );
