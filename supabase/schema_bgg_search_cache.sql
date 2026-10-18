-- Cache partagé des recherches BGG par texte (anti rate-limit).
-- Une ligne par requête normalisée ("smart:sea salt"), rafraîchie après 7 jours.
-- Exécuter dans Supabase → SQL Editor. Idempotent.

create table if not exists public.bgg_search_cache (
  query_key text primary key check (char_length(query_key) between 1 and 200),
  payload jsonb not null,
  fetched_at timestamptz not null default now()
);

create index if not exists bgg_search_cache_fetched_idx
  on public.bgg_search_cache (fetched_at);

alter table public.bgg_search_cache enable row level security;

drop policy if exists bgg_search_cache_select on public.bgg_search_cache;
drop policy if exists bgg_search_cache_insert on public.bgg_search_cache;
drop policy if exists bgg_search_cache_update on public.bgg_search_cache;

create policy bgg_search_cache_select
  on public.bgg_search_cache
  for select
  to anon, authenticated
  using (true);

create policy bgg_search_cache_insert
  on public.bgg_search_cache
  for insert
  to authenticated
  with check (true);

create policy bgg_search_cache_update
  on public.bgg_search_cache
  for update
  to authenticated
  using (true)
  with check (true);

grant select on public.bgg_search_cache to anon, authenticated;
grant insert, update on public.bgg_search_cache to authenticated;

-- Ménage : les entrées de plus de 60 jours ne servent plus.
-- delete from public.bgg_search_cache where fetched_at < now() - interval '60 days';
