-- =============================================================================
-- Isolation des collections par utilisateur (RLS)
-- À exécuter dans Supabase → SQL Editor
--
-- Sans cela, tous les comptes connectés voient et modifient les mêmes objets.
-- =============================================================================

-- Rattacher les anciennes lignes orphelines (ajoutées avant added_by)
update public.collection_items
set added_by = location_user_id
where added_by is null
  and location_user_id is not null;

alter table public.collection_items enable row level security;

drop policy if exists "collection_items_select" on public.collection_items;
drop policy if exists "collection_items_insert" on public.collection_items;
drop policy if exists "collection_items_update" on public.collection_items;
drop policy if exists "collection_items_delete" on public.collection_items;

-- Lecture : ma collection, mes groupes, amis qui partagent
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
          and f.share_collections = true
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

-- Création : uniquement en mon nom (ou dans un groupe dont je suis membre)
create policy "collection_items_insert"
  on public.collection_items
  for insert
  to authenticated
  with check (
    added_by = auth.uid()
    and (
      group_id is null
      or exists (
        select 1
        from public.group_members gm
        where gm.group_id = collection_items.group_id
          and gm.profile_id = auth.uid()
      )
    )
  );

-- Modification : mes objets ou objets d'un groupe dont je suis membre
create policy "collection_items_update"
  on public.collection_items
  for update
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
  )
  with check (
    added_by = auth.uid()
    and (
      group_id is null
      or exists (
        select 1
        from public.group_members gm
        where gm.group_id = collection_items.group_id
          and gm.profile_id = auth.uid()
      )
    )
  );

-- Suppression : mêmes règles que la modification
create policy "collection_items_delete"
  on public.collection_items
  for delete
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
  );
