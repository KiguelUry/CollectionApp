-- Cache BGG partagé entre tous les utilisateurs (anti rate-limit).
-- Une ligne par (jeu, type de ressource) : fiche détaillée, extensions…
-- Les entrées de plus de 14 jours sont rafraîchies côté app.
-- Exécuter dans Supabase → SQL Editor. Idempotent.

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

-- Données publiques BGG : lecture pour tous (anon inclus, web non connecté).
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
