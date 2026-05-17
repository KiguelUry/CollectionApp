-- =============================================================================
-- Prêts entre amis / hors app sur collection_items
-- À exécuter dans Supabase → SQL Editor
-- =============================================================================

alter table public.collection_items
  add column if not exists loaned_to_id uuid references public.profiles (id) on delete set null,
  add column if not exists loaned_to_name text,
  add column if not exists loaned_at timestamptz;

create index if not exists collection_items_loaned_to_id_idx
  on public.collection_items (loaned_to_id)
  where loaned_to_id is not null;
