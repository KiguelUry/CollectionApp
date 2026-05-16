-- =============================================================================
-- Groupes, amis, localisations, quantités — à exécuter dans Supabase SQL Editor
-- =============================================================================

-- Localisations (Chez Papa, Chez les enfants…)
create table if not exists public.locations (
  id uuid primary key default gen_random_uuid(),
  label text not null,
  created_by uuid not null references public.profiles (id) on delete cascade,
  group_id uuid,
  created_at timestamptz not null default now(),
  constraint locations_label_not_empty check (char_length(trim(label)) > 0)
);

-- Groupes (Famille, Amis TCG…)
create table if not exists public.groups (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  created_by uuid not null references public.profiles (id) on delete cascade,
  created_at timestamptz not null default now(),
  constraint groups_name_not_empty check (char_length(trim(name)) > 0)
);

alter table public.locations
  drop constraint if exists locations_group_id_fkey;

alter table public.locations
  add constraint locations_group_id_fkey
  foreign key (group_id) references public.groups (id) on delete cascade;

-- Membres d'un groupe
create table if not exists public.group_members (
  group_id uuid not null references public.groups (id) on delete cascade,
  profile_id uuid not null references public.profiles (id) on delete cascade,
  joined_at timestamptz not null default now(),
  primary key (group_id, profile_id)
);

-- Amitiés (partage de collections)
create table if not exists public.friendships (
  id uuid primary key default gen_random_uuid(),
  requester_id uuid not null references public.profiles (id) on delete cascade,
  addressee_id uuid not null references public.profiles (id) on delete cascade,
  status text not null default 'accepted'
    check (status in ('pending', 'accepted', 'blocked')),
  share_collections boolean not null default true,
  created_at timestamptz not null default now(),
  constraint friendships_not_self check (requester_id <> addressee_id),
  constraint friendships_unique_pair unique (requester_id, addressee_id)
);

-- Colonnes sur les objets
alter table public.collection_items
  add column if not exists quantity integer not null default 1,
  add column if not exists location_id uuid references public.locations (id) on delete set null,
  add column if not exists group_id uuid references public.groups (id) on delete set null,
  add column if not exists added_by uuid references public.profiles (id) on delete set null;

alter table public.collection_items
  drop constraint if exists collection_items_quantity_positive;

alter table public.collection_items
  add constraint collection_items_quantity_positive check (quantity >= 1);

create index if not exists collection_items_group_id_idx on public.collection_items (group_id);
create index if not exists collection_items_location_id_idx on public.collection_items (location_id);

-- RLS (app famille : utilisateurs authentifiés)
alter table public.locations enable row level security;
alter table public.groups enable row level security;
alter table public.group_members enable row level security;
alter table public.friendships enable row level security;

create policy "locations_all_authenticated" on public.locations
  for all to authenticated using (true) with check (true);

create policy "groups_all_authenticated" on public.groups
  for all to authenticated using (true) with check (true);

create policy "group_members_all_authenticated" on public.group_members
  for all to authenticated using (true) with check (true);

create policy "friendships_all_authenticated" on public.friendships
  for all to authenticated using (true) with check (true);

grant all on public.locations to postgres, service_role;
grant all on public.groups to postgres, service_role;
grant all on public.group_members to postgres, service_role;
grant all on public.friendships to postgres, service_role;

grant select, insert, update, delete on public.locations to authenticated;
grant select, insert, update, delete on public.groups to authenticated;
grant select, insert, update, delete on public.group_members to authenticated;
grant select, insert, update, delete on public.friendships to authenticated;
