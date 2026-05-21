-- =============================================================================
-- Correctif RLS PROD (à exécuter UNE FOIS dans Supabase → SQL Editor)
-- Basé sur l'export pg_policies du projet Collectingo.
-- =============================================================================

-- -----------------------------------------------------------------------------
-- P0 : supprimer les policies « true » (faille majeure)
-- -----------------------------------------------------------------------------
drop policy if exists boardgames_select_authenticated on public.collection_items;
drop policy if exists boardgames_insert_authenticated on public.collection_items;
drop policy if exists boardgames_update_authenticated on public.collection_items;
drop policy if exists boardgames_delete_authenticated on public.collection_items;

drop policy if exists friendships_all_authenticated on public.friendships;
drop policy if exists groups_all_authenticated on public.groups;
drop policy if exists "Group creator can update" on public.groups;
drop policy if exists group_members_all_authenticated on public.group_members;
drop policy if exists locations_all_authenticated on public.locations;

-- -----------------------------------------------------------------------------
-- collection_items : lecture amis (share_collections + hide profil)
-- -----------------------------------------------------------------------------
drop policy if exists collection_items_select on public.collection_items;

create policy collection_items_select
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
      and exists (
        select 1
        from public.profiles p
        where p.id = coalesce(
          collection_items.added_by,
          collection_items.location_user_id
        )
          and not p.hide_collection_from_friends
      )
    )
  );

-- -----------------------------------------------------------------------------
-- collection_item_tags : lecture alignée (plus de « item existe » seul)
-- -----------------------------------------------------------------------------
drop policy if exists collection_item_tags_select on public.collection_item_tags;

create policy collection_item_tags_select
  on public.collection_item_tags
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.collection_items ci
      where ci.id = collection_item_tags.item_id
        and (
          (
            ci.group_id is null
            and (
              ci.added_by = auth.uid()
              or ci.location_user_id = auth.uid()
            )
          )
          or (
            ci.group_id is not null
            and exists (
              select 1
              from public.group_members gm
              where gm.group_id = ci.group_id
                and gm.profile_id = auth.uid()
            )
          )
          or (
            ci.group_id is null
            and exists (
              select 1
              from public.friendships f
              where f.status = 'accepted'
                and f.share_collections = true
                and (
                  (
                    f.requester_id = auth.uid()
                    and f.addressee_id in (ci.added_by, ci.location_user_id)
                  )
                  or (
                    f.addressee_id = auth.uid()
                    and f.requester_id in (ci.added_by, ci.location_user_id)
                  )
                )
            )
            and exists (
              select 1
              from public.profiles p
              where p.id = coalesce(ci.added_by, ci.location_user_id)
                and not p.hide_collection_from_friends
            )
          )
        )
    )
  );

-- -----------------------------------------------------------------------------
-- friendships
-- -----------------------------------------------------------------------------
create policy friendships_select_own
  on public.friendships
  for select
  to authenticated
  using (
    requester_id = auth.uid()
    or addressee_id = auth.uid()
  );

create policy friendships_insert_requester
  on public.friendships
  for insert
  to authenticated
  with check (
    requester_id = auth.uid()
    and requester_id <> addressee_id
  );

create policy friendships_accept_pending
  on public.friendships
  for update
  to authenticated
  using (
    addressee_id = auth.uid()
    and status = 'pending'
  )
  with check (
    addressee_id = auth.uid()
    and status = 'accepted'
  );

create policy friendships_update_share
  on public.friendships
  for update
  to authenticated
  using (
    status = 'accepted'
    and (
      requester_id = auth.uid()
      or addressee_id = auth.uid()
    )
  )
  with check (
    status = 'accepted'
    and (
      requester_id = auth.uid()
      or addressee_id = auth.uid()
    )
  );

create policy friendships_delete_own
  on public.friendships
  for delete
  to authenticated
  using (
    requester_id = auth.uid()
    or addressee_id = auth.uid()
  );

-- -----------------------------------------------------------------------------
-- groups
-- -----------------------------------------------------------------------------
create policy groups_select_member
  on public.groups
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.group_members gm
      where gm.group_id = groups.id
        and gm.profile_id = auth.uid()
    )
  );

create policy groups_insert_creator
  on public.groups
  for insert
  to authenticated
  with check (created_by = auth.uid());

create policy groups_update_creator
  on public.groups
  for update
  to authenticated
  using (created_by = auth.uid())
  with check (created_by = auth.uid());

create policy groups_delete_creator
  on public.groups
  for delete
  to authenticated
  using (created_by = auth.uid());

-- -----------------------------------------------------------------------------
-- group_members (is_group_member évite la récursion RLS)
-- -----------------------------------------------------------------------------
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

create policy group_members_select_member
  on public.group_members
  for select
  to authenticated
  using (public.is_group_member(group_id));

create policy group_members_insert_creator_or_self
  on public.group_members
  for insert
  to authenticated
  with check (
    profile_id = auth.uid()
    or exists (
      select 1
      from public.groups g
      where g.id = group_members.group_id
        and g.created_by = auth.uid()
    )
  );

create policy group_members_delete_creator_or_self
  on public.group_members
  for delete
  to authenticated
  using (
    profile_id = auth.uid()
    or exists (
      select 1
      from public.groups g
      where g.id = group_members.group_id
        and g.created_by = auth.uid()
    )
  );

-- -----------------------------------------------------------------------------
-- locations
-- -----------------------------------------------------------------------------
create policy locations_select_scope
  on public.locations
  for select
  to authenticated
  using (
    created_by = auth.uid()
    or (
      group_id is not null
      and exists (
        select 1
        from public.group_members gm
        where gm.group_id = locations.group_id
          and gm.profile_id = auth.uid()
      )
    )
  );

create policy locations_insert_scope
  on public.locations
  for insert
  to authenticated
  with check (
    created_by = auth.uid()
    and (
      group_id is null
      or exists (
        select 1
        from public.group_members gm
        where gm.group_id = locations.group_id
          and gm.profile_id = auth.uid()
      )
      or exists (
        select 1
        from public.groups g
        where g.id = locations.group_id
          and g.created_by = auth.uid()
      )
    )
  );

create policy locations_update_scope
  on public.locations
  for update
  to authenticated
  using (
    created_by = auth.uid()
    or (
      group_id is not null
      and exists (
        select 1
        from public.groups g
        where g.id = locations.group_id
          and g.created_by = auth.uid()
      )
    )
  )
  with check (created_by = auth.uid());

create policy locations_delete_scope
  on public.locations
  for delete
  to authenticated
  using (
    created_by = auth.uid()
    or (
      group_id is not null
      and exists (
        select 1
        from public.groups g
        where g.id = locations.group_id
          and g.created_by = auth.uid()
      )
    )
  );
