-- Liaison N-N objet ↔ groupes (multi-appartenance)
create table if not exists public.collection_item_groups (
  item_id uuid not null references public.collection_items (id) on delete cascade,
  group_id uuid not null references public.groups (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (item_id, group_id)
);

create index if not exists collection_item_groups_group_idx
  on public.collection_item_groups (group_id);

alter table public.collection_item_groups enable row level security;

drop policy if exists collection_item_groups_member on public.collection_item_groups;

create policy collection_item_groups_member
  on public.collection_item_groups
  for all
  to authenticated
  using (
    exists (
      select 1 from public.group_members gm
      where gm.group_id = collection_item_groups.group_id
        and gm.profile_id = auth.uid()
    )
    or exists (
      select 1 from public.collection_items ci
      where ci.id = collection_item_groups.item_id
        and (ci.added_by = auth.uid() or ci.location_user_id = auth.uid())
    )
  )
  with check (
    exists (
      select 1 from public.group_members gm
      where gm.group_id = collection_item_groups.group_id
        and gm.profile_id = auth.uid()
    )
  );
