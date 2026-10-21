-- =============================================================================
-- Paloma — synchronisation schéma ↔ app (idempotent)
-- À exécuter UNE FOIS dans Supabase → SQL Editor (projet prod).
-- Crée les tables/colonnes manquantes, RLS, index ; nettoie les policies
-- profiles en doublon. Ne détruit aucune donnée.
-- =============================================================================

-- ---------------------------------------------------------------------------
-- 1) Cache catalogue BGG (absente en prod → GET/POST 404 en boucle au scroll)
-- ---------------------------------------------------------------------------
create table if not exists public.bgg_catalog_cache (
  bgg_id text not null,
  kind text not null check (kind in ('details', 'expansions')),
  payload jsonb not null,
  fetched_at timestamptz not null default now(),
  primary key (bgg_id, kind),
  constraint bgg_catalog_cache_id_numeric check (bgg_id ~ '^[0-9]+$')
);

create index if not exists bgg_catalog_cache_fetched_idx
  on public.bgg_catalog_cache (fetched_at);

alter table public.bgg_catalog_cache enable row level security;

drop policy if exists bgg_catalog_cache_select on public.bgg_catalog_cache;
drop policy if exists bgg_catalog_cache_insert on public.bgg_catalog_cache;
drop policy if exists bgg_catalog_cache_update on public.bgg_catalog_cache;

create policy bgg_catalog_cache_select
  on public.bgg_catalog_cache
  for select
  to anon, authenticated
  using (true);

create policy bgg_catalog_cache_insert
  on public.bgg_catalog_cache
  for insert
  to authenticated
  with check (true);

create policy bgg_catalog_cache_update
  on public.bgg_catalog_cache
  for update
  to authenticated
  using (true)
  with check (true);

grant select on public.bgg_catalog_cache to anon, authenticated;
grant insert, update on public.bgg_catalog_cache to authenticated;

-- ---------------------------------------------------------------------------
-- 2) Profiles — colonnes attendues par l'app
-- ---------------------------------------------------------------------------
alter table public.profiles
  add column if not exists households jsonb not null default '[]'::jsonb;

alter table public.profiles
  add column if not exists household_aliases jsonb not null default '[]'::jsonb;

alter table public.profiles
  add column if not exists pantheon_item_ids jsonb not null default '[]'::jsonb;

alter table public.profiles
  add column if not exists favorite_item_ids uuid[] not null default '{}'::uuid[];

alter table public.profiles
  add column if not exists gender_identity text;

alter table public.profiles
  add column if not exists greeting_grammar text;

alter table public.profiles
  add column if not exists showcase_public boolean not null default false;

alter table public.profiles
  add column if not exists showcase_token text;

alter table public.profiles
  add column if not exists hide_collection_from_non_friends boolean not null default false;

alter table public.profiles
  add column if not exists hide_collection_from_friends boolean not null default false;

alter table public.profiles
  add column if not exists share_wishlist boolean not null default true;

alter table public.profiles
  add column if not exists bio text;

alter table public.profiles
  add column if not exists avatar_url text;

alter table public.profiles
  add column if not exists accent_color text;

comment on column public.profiles.households is
  'Foyers : [{id, place, people[], ...}] visibles par amis / groupe.';
comment on column public.profiles.household_aliases is
  'Pseudos / surnoms « chez qui » de l''utilisateur (liste de textes).';
comment on column public.profiles.pantheon_item_ids is
  'Top Panthéon (ids collection_items, ordre conservé, jsonb array).';

-- ---------------------------------------------------------------------------
-- 3) Marketplace (table absente → insert 404 si l'UI marketplace est utilisée)
-- ---------------------------------------------------------------------------
create table if not exists public.marketplace_inquiries (
  id uuid primary key default gen_random_uuid(),
  listing_item_id uuid not null references public.collection_items (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  owner_id uuid not null references public.profiles (id) on delete cascade,
  message text not null,
  proposed_item_id uuid references public.collection_items (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint marketplace_inquiries_message_not_empty
    check (char_length(trim(message)) > 0)
);

create index if not exists marketplace_inquiries_listing_idx
  on public.marketplace_inquiries (listing_item_id, created_at desc);

create index if not exists marketplace_inquiries_owner_idx
  on public.marketplace_inquiries (owner_id, created_at desc);

alter table public.marketplace_inquiries enable row level security;

drop policy if exists marketplace_inquiries_select on public.marketplace_inquiries;
drop policy if exists marketplace_inquiries_insert on public.marketplace_inquiries;

create policy marketplace_inquiries_select
  on public.marketplace_inquiries
  for select
  to authenticated
  using (sender_id = auth.uid() or owner_id = auth.uid());

create policy marketplace_inquiries_insert
  on public.marketplace_inquiries
  for insert
  to authenticated
  with check (sender_id = auth.uid());

grant select, insert on public.marketplace_inquiries to authenticated;

-- ---------------------------------------------------------------------------
-- 4) activity_reactions (déjà présente chez toi — CREATE IF NOT EXISTS safe)
-- ---------------------------------------------------------------------------
create table if not exists public.activity_reactions (
  event_id uuid not null references public.activity_events (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  emoji text not null,
  created_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

alter table public.activity_reactions enable row level security;

-- ---------------------------------------------------------------------------
-- 5) Nettoyage policies RLS profiles en doublon
--     (profiles_select_authenticated + profiles_select_self_friends_groups
--      et deux INSERT/UPDATE « Users … » / « profiles_* »)
-- ---------------------------------------------------------------------------
drop policy if exists "Users insert own profile row" on public.profiles;
drop policy if exists "Users update own profile row" on public.profiles;

-- On garde profiles_insert_own / profiles_update_own / profiles_select_* .
-- Recrée la policy SELECT élargie (soi + amis + groupe) si absente.
drop policy if exists profiles_select_self_friends_groups on public.profiles;
create policy profiles_select_self_friends_groups
  on public.profiles
  for select
  to authenticated
  using (
    id = auth.uid()
    or exists (
      select 1
      from public.friendships f
      where f.status = 'accepted'
        and (
          (f.requester_id = auth.uid() and f.addressee_id = profiles.id)
          or (f.addressee_id = auth.uid() and f.requester_id = profiles.id)
        )
    )
    or exists (
      select 1
      from public.group_members me
      join public.group_members them on them.group_id = me.group_id
      where me.profile_id = auth.uid()
        and them.profile_id = profiles.id
    )
  );

-- Assurer insert/update own (idempotent)
drop policy if exists profiles_insert_own on public.profiles;
create policy profiles_insert_own
  on public.profiles
  for insert
  to authenticated
  with check (id = auth.uid());

drop policy if exists profiles_update_own on public.profiles;
create policy profiles_update_own
  on public.profiles
  for update
  to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

-- ---------------------------------------------------------------------------
-- 6) Index utiles (idempotents)
-- ---------------------------------------------------------------------------
create index if not exists collection_items_added_by_idx
  on public.collection_items (added_by);

create index if not exists collection_items_category_idx
  on public.collection_items (category);

create index if not exists collection_items_location_user_idx
  on public.collection_items (location_user_id);

create index if not exists bgg_search_cache_fetched_idx
  on public.bgg_search_cache (fetched_at);

-- ---------------------------------------------------------------------------
-- Note : collection_items.location_label N'EST PAS créée volontairement.
-- Le lieu libre est stocké dans metadata.holder_label (app alignée).
-- =============================================================================
