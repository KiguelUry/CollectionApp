-- Listes utilisateur thématiques (lectures, tops, sélections…)
-- À exécuter dans Supabase → SQL Editor

create table if not exists public.user_lists (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  description text,
  cover_url text,
  icon_key text not null default 'playlist_play',
  color_hex text not null default '#00A896',
  metadata jsonb not null default '{}',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (owner_id, name)
);

create table if not exists public.user_list_items (
  id uuid primary key default gen_random_uuid(),
  list_id uuid not null references public.user_lists (id) on delete cascade,
  item_id uuid not null references public.collection_items (id) on delete cascade,
  sort_index int not null default 0,
  added_at timestamptz not null default now(),
  unique (list_id, item_id)
);

create index if not exists user_lists_owner_idx on public.user_lists (owner_id);
create index if not exists user_list_items_list_idx on public.user_list_items (list_id);
create index if not exists user_list_items_item_idx on public.user_list_items (item_id);

alter table public.user_lists enable row level security;
alter table public.user_list_items enable row level security;

drop policy if exists user_lists_own on public.user_lists;
create policy user_lists_own
  on public.user_lists
  for all
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists user_list_items_own on public.user_list_items;
create policy user_list_items_own
  on public.user_list_items
  for all
  to authenticated
  using (
    exists (
      select 1 from public.user_lists ul
      where ul.id = list_id and ul.owner_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.user_lists ul
      where ul.id = list_id and ul.owner_id = auth.uid()
    )
  );
