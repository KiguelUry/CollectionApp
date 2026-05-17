-- =============================================================================
-- Tags personnalisés + date d'ajout sur collection_items
-- À exécuter dans Supabase → SQL Editor
-- =============================================================================

alter table public.collection_items
  add column if not exists created_at timestamptz not null default now();

create index if not exists collection_items_created_at_idx
  on public.collection_items (created_at desc);

-- Tags par utilisateur
create table if not exists public.item_tags (
  id uuid primary key default gen_random_uuid(),
  profile_id uuid not null references public.profiles (id) on delete cascade,
  label text not null,
  color text not null default '#9E9E9E',
  created_at timestamptz not null default now(),
  constraint item_tags_label_not_empty check (char_length(trim(label)) > 0),
  constraint item_tags_unique_label unique (profile_id, label)
);

create table if not exists public.collection_item_tags (
  item_id uuid not null references public.collection_items (id) on delete cascade,
  tag_id uuid not null references public.item_tags (id) on delete cascade,
  primary key (item_id, tag_id)
);

create index if not exists collection_item_tags_tag_id_idx
  on public.collection_item_tags (tag_id);

alter table public.item_tags enable row level security;
alter table public.collection_item_tags enable row level security;

drop policy if exists "item_tags_own" on public.item_tags;
create policy "item_tags_own"
  on public.item_tags for all to authenticated
  using (profile_id = auth.uid())
  with check (profile_id = auth.uid());

drop policy if exists "collection_item_tags_select" on public.collection_item_tags;
create policy "collection_item_tags_select"
  on public.collection_item_tags for select to authenticated
  using (
    exists (
      select 1 from public.collection_items ci
      where ci.id = collection_item_tags.item_id
    )
  );

drop policy if exists "collection_item_tags_modify" on public.collection_item_tags;
create policy "collection_item_tags_modify"
  on public.collection_item_tags for all to authenticated
  using (
    exists (
      select 1 from public.collection_items ci
      where ci.id = collection_item_tags.item_id
        and (
          ci.added_by = auth.uid()
          or ci.location_user_id = auth.uid()
        )
    )
  )
  with check (
    exists (
      select 1 from public.item_tags t
      where t.id = collection_item_tags.tag_id
        and t.profile_id = auth.uid()
    )
    and exists (
      select 1 from public.collection_items ci
      where ci.id = collection_item_tags.item_id
        and (
          ci.added_by = auth.uid()
          or ci.location_user_id = auth.uid()
        )
    )
  );

grant select, insert, update, delete on public.item_tags to authenticated;
grant select, insert, update, delete on public.collection_item_tags to authenticated;
