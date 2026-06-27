-- =============================================================================
-- Autoriser quantity = 0 sur collection_items
-- À exécuter dans Supabase → SQL Editor
-- =============================================================================

-- 1) Identifier la contrainte CHECK sur quantity (nom + définition)
select
  con.conname as constraint_name,
  pg_get_constraintdef(con.oid) as constraint_definition
from pg_constraint con
inner join pg_class rel on rel.oid = con.conrelid
inner join pg_namespace nsp on nsp.oid = rel.relnamespace
where nsp.nspname = 'public'
  and rel.relname = 'collection_items'
  and con.contype = 'c'
  and pg_get_constraintdef(con.oid) ilike '%quantity%';

-- 2) Supprimer la contrainte qui impose quantity >= 1
alter table public.collection_items
  drop constraint if exists collection_items_quantity_positive;

-- 3) (Optionnel) Nouvelle contrainte : quantity ne peut pas être négative
alter table public.collection_items
  drop constraint if exists collection_items_quantity_non_negative;

alter table public.collection_items
  add constraint collection_items_quantity_non_negative
  check (quantity >= 0);

-- 4) Vérification
select conname, pg_get_constraintdef(oid)
from pg_constraint
where conrelid = 'public.collection_items'::regclass
  and contype = 'c'
  and pg_get_constraintdef(oid) ilike '%quantity%';
