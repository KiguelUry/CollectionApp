-- Étend les sous-catégories livres : comics / bd / roman (en plus de comic / novel).
-- Corrige book_series_subcategory_check 23514 sur « Walking Dead » (Dart envoie 'comics').

alter table public.book_series
  drop constraint if exists book_series_subcategory_check;

alter table public.book_series
  add constraint book_series_subcategory_check check (
    subcategory in ('manga', 'bd', 'comics', 'comic', 'novel', 'roman', 'other')
  );

alter table public.collection_items
  drop constraint if exists collection_items_subcategory_check;

alter table public.collection_items
  drop constraint if exists collection_item_subcategory_check;

alter table public.collection_items
  add constraint collection_items_subcategory_check check (
    subcategory is null
    or (
      category = 'book'
      and subcategory in ('manga', 'bd', 'comics', 'comic', 'novel', 'roman', 'other')
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
