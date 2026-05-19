-- =============================================================================
-- Livres / manga / BD : séries, tomes, progression (phases 1–5)
-- À exécuter dans Supabase → SQL Editor (après collection_items + profiles)
-- =============================================================================

-- Séries (Naruto, DBZ, saga roman…)
create table if not exists public.book_series (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references public.profiles (id) on delete cascade,
  name text not null,
  subcategory text not null check (subcategory in ('manga', 'comic', 'novel', 'other')),
  cover_url text,
  parent_series_id uuid references public.book_series (id) on delete cascade,
  description text,
  user_rating numeric check (user_rating is null or (user_rating >= 0 and user_rating <= 5)),
  user_review text,
  expected_volume_count int check (expected_volume_count is null or expected_volume_count >= 0),
  wishlist_entire_series boolean not null default false,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index if not exists book_series_owner_idx on public.book_series (owner_id);
create index if not exists book_series_parent_idx on public.book_series (parent_series_id);
create index if not exists book_series_subcategory_idx
  on public.book_series (owner_id, subcategory);

-- Emplacements de tomes / chapitres dans une série
create table if not exists public.book_volumes (
  id uuid primary key default gen_random_uuid(),
  series_id uuid not null references public.book_series (id) on delete cascade,
  volume_number numeric not null,
  label text,
  sort_index numeric not null,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  unique (series_id, volume_number)
);

create index if not exists book_volumes_series_idx on public.book_volumes (series_id);

-- Lien items ↔ série / tome + lu
alter table public.collection_items
  add column if not exists series_id uuid references public.book_series (id) on delete set null;

alter table public.collection_items
  add column if not exists volume_id uuid references public.book_volumes (id) on delete set null;

alter table public.collection_items
  add column if not exists is_read boolean not null default false;

create index if not exists collection_items_series_idx on public.collection_items (series_id);
create index if not exists collection_items_volume_idx on public.collection_items (volume_id);

-- updated_at auto
create or replace function public.set_book_series_updated_at()
returns trigger
language plpgsql
as $$
begin
  new.updated_at = now();
  return new;
end;
$$;

drop trigger if exists book_series_updated_at on public.book_series;
create trigger book_series_updated_at
  before update on public.book_series
  for each row execute function public.set_book_series_updated_at();

-- RLS
alter table public.book_series enable row level security;
alter table public.book_volumes enable row level security;

drop policy if exists "book_series_select_own" on public.book_series;
create policy "book_series_select_own"
  on public.book_series for select
  to authenticated
  using (owner_id = auth.uid());

drop policy if exists "book_series_insert_own" on public.book_series;
create policy "book_series_insert_own"
  on public.book_series for insert
  to authenticated
  with check (owner_id = auth.uid());

drop policy if exists "book_series_update_own" on public.book_series;
create policy "book_series_update_own"
  on public.book_series for update
  to authenticated
  using (owner_id = auth.uid())
  with check (owner_id = auth.uid());

drop policy if exists "book_series_delete_own" on public.book_series;
create policy "book_series_delete_own"
  on public.book_series for delete
  to authenticated
  using (owner_id = auth.uid());

drop policy if exists "book_volumes_select_via_series" on public.book_volumes;
create policy "book_volumes_select_via_series"
  on public.book_volumes for select
  to authenticated
  using (
    exists (
      select 1 from public.book_series s
      where s.id = book_volumes.series_id and s.owner_id = auth.uid()
    )
  );

drop policy if exists "book_volumes_insert_via_series" on public.book_volumes;
create policy "book_volumes_insert_via_series"
  on public.book_volumes for insert
  to authenticated
  with check (
    exists (
      select 1 from public.book_series s
      where s.id = book_volumes.series_id and s.owner_id = auth.uid()
    )
  );

drop policy if exists "book_volumes_update_via_series" on public.book_volumes;
create policy "book_volumes_update_via_series"
  on public.book_volumes for update
  to authenticated
  using (
    exists (
      select 1 from public.book_series s
      where s.id = book_volumes.series_id and s.owner_id = auth.uid()
    )
  );

drop policy if exists "book_volumes_delete_via_series" on public.book_volumes;
create policy "book_volumes_delete_via_series"
  on public.book_volumes for delete
  to authenticated
  using (
    exists (
      select 1 from public.book_series s
      where s.id = book_volumes.series_id and s.owner_id = auth.uid()
    )
  );
