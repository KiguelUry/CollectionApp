-- Extensions jeux de société : lien parent enfant sur collection_items
-- À exécuter dans Supabase → SQL Editor

alter table public.collection_items
  add column if not exists is_expansion boolean not null default false;

alter table public.collection_items
  add column if not exists parent_game_id uuid
    references public.collection_items (id) on delete cascade;

create index if not exists collection_items_parent_game_id_idx
  on public.collection_items (parent_game_id)
  where parent_game_id is not null;

create index if not exists collection_items_is_expansion_idx
  on public.collection_items (is_expansion)
  where is_expansion = true;
