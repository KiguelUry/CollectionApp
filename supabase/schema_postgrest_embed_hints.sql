-- Note PostgREST : après `collection_item_groups`, qualifier les embeds côté client :
--   groups!collection_items_group_id_fkey(name)
--   profiles!collection_items_added_by_fkey(username)
-- La colonne `group_id` reste le groupe principal ; la table junction gère le multi-groupe.

-- Renomme explicitement la FK principale pour des hints PostgREST stables.
alter table public.collection_items
  drop constraint if exists collection_items_group_id_fkey;

alter table public.collection_items
  add constraint collection_items_group_id_fkey
  foreign key (group_id) references public.groups (id) on delete set null;

alter table public.collection_item_groups
  drop constraint if exists collection_item_groups_group_id_fkey;

alter table public.collection_item_groups
  add constraint collection_item_groups_group_id_fkey
  foreign key (group_id) references public.groups (id) on delete cascade;

comment on constraint collection_items_group_id_fkey on public.collection_items is
  'Groupe principal — utiliser groups!collection_items_group_id_fkey dans PostgREST';

comment on constraint collection_item_groups_group_id_fkey on public.collection_item_groups is
  'Appartenance multi-groupe — ne pas embedder via collection_items.groups sans hint';
