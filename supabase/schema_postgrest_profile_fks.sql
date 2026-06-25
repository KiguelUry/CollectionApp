-- FK profils manquantes pour embeds PostgREST (PGRST200)
-- À exécuter si erreur loaned_to_id ou location_user_id persiste après schema_db_fixes_nature.sql

alter table public.collection_items
  add column if not exists location_user_id uuid,
  add column if not exists loaned_to_id uuid;

alter table public.collection_items
  drop constraint if exists collection_items_location_user_id_fkey;

alter table public.collection_items
  add constraint collection_items_location_user_id_fkey
  foreign key (location_user_id) references public.profiles (id) on delete set null;

alter table public.collection_items
  drop constraint if exists collection_items_loaned_to_id_fkey;

alter table public.collection_items
  add constraint collection_items_loaned_to_id_fkey
  foreign key (loaned_to_id) references public.profiles (id) on delete set null;

alter table public.collection_items
  drop constraint if exists collection_items_added_by_fkey;

alter table public.collection_items
  add constraint collection_items_added_by_fkey
  foreign key (added_by) references public.profiles (id) on delete set null;

notify pgrst, 'reload schema';
