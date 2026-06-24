-- Édition collaborative des objets de groupe + wiki / mur des souhaits
-- Exécuter après schema_rls_fix_live.sql et schema_groups_rls_creator_fix.sql

-- -----------------------------------------------------------------------------
-- collection_items : les membres du groupe peuvent modifier les fiches communes
-- -----------------------------------------------------------------------------
drop policy if exists "collection_items_update" on public.collection_items;

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

-- -----------------------------------------------------------------------------
-- Règles collectives par jeu (wiki de groupe)
-- -----------------------------------------------------------------------------
create table if not exists public.group_rule_entries (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  item_id uuid not null references public.collection_items (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  title text not null default 'Variante',
  body text not null,
  vote_count int not null default 0,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.group_rule_votes (
  rule_id uuid not null references public.group_rule_entries (id) on delete cascade,
  voter_id uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (rule_id, voter_id)
);

create index if not exists group_rule_entries_group_item_idx
  on public.group_rule_entries (group_id, item_id);

alter table public.group_rule_entries enable row level security;
alter table public.group_rule_votes enable row level security;

create policy group_rule_entries_member
  on public.group_rule_entries
  for all
  to authenticated
  using (
    exists (
      select 1 from public.group_members gm
      where gm.group_id = group_rule_entries.group_id
        and gm.profile_id = auth.uid()
    )
  )
  with check (
    author_id = auth.uid()
    and exists (
      select 1 from public.group_members gm
      where gm.group_id = group_rule_entries.group_id
        and gm.profile_id = auth.uid()
    )
  );

create policy group_rule_votes_member
  on public.group_rule_votes
  for all
  to authenticated
  using (
    exists (
      select 1
      from public.group_rule_entries r
      join public.group_members gm on gm.group_id = r.group_id
      where r.id = group_rule_votes.rule_id
        and gm.profile_id = auth.uid()
    )
  )
  with check (voter_id = auth.uid());

-- -----------------------------------------------------------------------------
-- Mur des souhaits (wanted board)
-- -----------------------------------------------------------------------------
create table if not exists public.group_wanted_posts (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  author_id uuid not null references public.profiles (id) on delete cascade,
  message text not null,
  item_id uuid references public.collection_items (id) on delete set null,
  catalog_payload jsonb not null default '{}'::jsonb,
  claimed_by uuid references public.profiles (id) on delete set null,
  claimed_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists group_wanted_posts_group_idx
  on public.group_wanted_posts (group_id, created_at desc);

alter table public.group_wanted_posts enable row level security;

create policy group_wanted_posts_member
  on public.group_wanted_posts
  for all
  to authenticated
  using (
    exists (
      select 1 from public.group_members gm
      where gm.group_id = group_wanted_posts.group_id
        and gm.profile_id = auth.uid()
    )
  )
  with check (
    author_id = auth.uid()
    and exists (
      select 1 from public.group_members gm
      where gm.group_id = group_wanted_posts.group_id
        and gm.profile_id = auth.uid()
    )
  );
