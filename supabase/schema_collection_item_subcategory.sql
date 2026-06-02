-- Étend les sous-catégories autorisées sur collection_items (cartes TCG, médias…).
-- À exécuter dans Supabase → SQL Editor si l'ajout de cartes échoue avec
-- collection_items_subcategory_check (nom réel côté Supabase)

alter table public.collection_items
  drop constraint if exists collection_items_subcategory_check;

alter table public.collection_items
  drop constraint if exists collection_item_subcategory_check;

alter table public.collection_items
  add constraint collection_items_subcategory_check check (
    subcategory is null
    or (
      category = 'book'
      and subcategory in ('manga', 'comic', 'novel', 'other')
    )
    or (
      category = 'card'
      and subcategory in (
        'pokemon',
        'magic',
        'yugioh',
        'onepiece',
        'lorcana',
        'topps',
        'panini',
        'other'
      )
    )
    or (
      category = 'media'
      and subcategory in ('vinyl', 'cd', 'cassette')
    )
    or category not in ('book', 'card', 'media')
  );
