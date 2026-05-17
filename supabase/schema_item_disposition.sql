-- =============================================================================
-- Statut de disposition : à vendre / vendu
-- À exécuter dans Supabase → SQL Editor
-- =============================================================================

alter table public.collection_items
  add column if not exists is_for_sale boolean not null default false,
  add column if not exists is_sold boolean not null default false;

alter table public.collection_items
  drop constraint if exists collection_items_disposition_check;

alter table public.collection_items
  add constraint collection_items_disposition_check
  check (not (is_for_sale and is_sold));
