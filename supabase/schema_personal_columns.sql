-- =============================================================================
-- Colonnes personnelles + métadonnées sur collection_items
-- À exécuter dans Supabase → SQL Editor (après la table collection_items)
-- =============================================================================

-- Métadonnées JSON (cartes, voitures, timbres, vinyles, lego…)
alter table public.collection_items
  add column if not exists metadata jsonb not null default '{}'::jsonb;

-- Sous-type (ex: manga / roman pour livres, pokemon pour cartes)
alter table public.collection_items
  add column if not exists subcategory text;

-- Champs perso (toutes catégories)
alter table public.collection_items
  add column if not exists rating double precision,
  add column if not exists review text,
  add column if not exists purchase_price numeric(10, 2),
  add column if not exists condition text,
  add column if not exists games_played integer,
  add column if not exists personal_rules text;

-- Contraintes optionnelles
alter table public.collection_items
  drop constraint if exists collection_items_condition_personal_check;

alter table public.collection_items
  add constraint collection_items_condition_personal_check
  check (
    condition is null
    or condition in ('neuf', 'tres_bon', 'bon', 'correct', 'use')
  );

alter table public.collection_items
  drop constraint if exists collection_items_rating_range_check;

alter table public.collection_items
  add constraint collection_items_rating_range_check
  check (rating is null or (rating >= 0 and rating <= 5));

-- Vérification : liste les colonnes de collection_items
-- select column_name, data_type
-- from information_schema.columns
-- where table_schema = 'public' and table_name = 'collection_items'
-- order by ordinal_position;
