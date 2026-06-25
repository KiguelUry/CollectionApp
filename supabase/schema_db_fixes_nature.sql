-- =============================================================================
-- Correctifs BDD : FK location_user_id (PGRST200) + catégories animal/restaurant
-- À exécuter dans Supabase → SQL Editor (une fois)
-- =============================================================================

-- Colonne propriétaire / détenteur physique de l'objet
alter table public.collection_items
  add column if not exists location_user_id uuid;

-- FK explicite pour PostgREST : profiles!collection_items_location_user_id_fkey
alter table public.collection_items
  drop constraint if exists collection_items_location_user_id_fkey;

alter table public.collection_items
  add constraint collection_items_location_user_id_fkey
  foreign key (location_user_id) references public.profiles (id) on delete set null;

comment on constraint collection_items_location_user_id_fkey
  on public.collection_items is
  'Détenteur — embed PostgREST : profiles!collection_items_location_user_id_fkey';

-- FK added_by (hint stable si absente ou mal nommée)
alter table public.collection_items
  drop constraint if exists collection_items_added_by_fkey;

alter table public.collection_items
  add constraint collection_items_added_by_fkey
  foreign key (added_by) references public.profiles (id) on delete set null;

-- Étend la contrainte de catégorie (23514) : animal + restaurant (+ wildlife legacy)
alter table public.collection_items
  drop constraint if exists collection_items_category_check;

alter table public.collection_items
  add constraint collection_items_category_check check (
    category in (
      'boardgame',
      'book',
      'card',
      'car',
      'stamp',
      'coin',
      'media',
      'lego',
      'watch',
      'videogame',
      'movie',
      'custom',
      'animal',
      'restaurant',
      'wildlife'
    )
  );

-- Harmonise les anciennes lignes wildlife → animal
update public.collection_items
set category = 'animal'
where category = 'wildlife';

-- Recharge le cache schéma PostgREST
notify pgrst, 'reload schema';
