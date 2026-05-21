-- Armoire à trophées (6 objets max) sur profiles
-- Exécuter dans Supabase → SQL Editor

alter table public.profiles
  add column if not exists favorite_item_ids uuid[] not null default '{}';

alter table public.profiles
  drop constraint if exists profiles_favorite_items_max_6;

alter table public.profiles
  add constraint profiles_favorite_items_max_6
  check (coalesce(array_length(favorite_item_ids, 1), 0) <= 6);
