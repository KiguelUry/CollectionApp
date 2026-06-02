-- Collections personnalisées (types créés par l'utilisateur)
-- À exécuter dans Supabase → SQL Editor

create table if not exists public.user_collection_types (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  icon_key text not null default 'category',
  color_hex text not null default '#607D8B',
  created_at timestamptz not null default now(),
  unique (owner_id, name)
);

create index if not exists user_collection_types_owner_idx
  on public.user_collection_types (owner_id);

alter table public.user_collection_types enable row level security;

drop policy if exists user_collection_types_own on public.user_collection_types;

create policy user_collection_types_own
  on public.user_collection_types
  for all
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

-- Les items custom utilisent category = 'custom' et subcategory = id du type.
