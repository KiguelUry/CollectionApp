-- =============================================================================
-- Couvertures personnalisées (hors-série) — bucket Storage `book-custom-covers`
-- Chemins applicatifs : {user_id}/{series_id}/{volume_id|new}-{timestamp}.jpg
-- À exécuter dans Supabase → SQL Editor
-- =============================================================================

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'book-custom-covers',
  'book-custom-covers',
  true,
  5242880, -- 5 Mo
  array['image/jpeg', 'image/jpg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = true,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

-- Lecture publique (couvertures affichées sur le web / GitHub Pages)
drop policy if exists "Book custom covers public read" on storage.objects;
create policy "Book custom covers public read"
  on storage.objects for select
  using (bucket_id = 'book-custom-covers');

-- Upload : utilisateur connecté, dossier racine = son UUID, série qu'il possède
drop policy if exists "Users upload own book custom cover" on storage.objects;
create policy "Users upload own book custom cover"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'book-custom-covers'
    and (storage.foldername(name))[1] = auth.uid()::text
    and exists (
      select 1
      from public.book_series bs
      where bs.id::text = (storage.foldername(name))[2]
        and bs.owner_id = auth.uid()
    )
  );

-- Mise à jour (upsert côté app)
drop policy if exists "Users update own book custom cover" on storage.objects;
create policy "Users update own book custom cover"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'book-custom-covers'
    and (storage.foldername(name))[1] = auth.uid()::text
    and exists (
      select 1
      from public.book_series bs
      where bs.id::text = (storage.foldername(name))[2]
        and bs.owner_id = auth.uid()
    )
  )
  with check (
    bucket_id = 'book-custom-covers'
    and (storage.foldername(name))[1] = auth.uid()::text
    and exists (
      select 1
      from public.book_series bs
      where bs.id::text = (storage.foldername(name))[2]
        and bs.owner_id = auth.uid()
    )
  );

-- Suppression : même périmètre que l'upload
drop policy if exists "Users delete own book custom cover" on storage.objects;
create policy "Users delete own book custom cover"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'book-custom-covers'
    and (storage.foldername(name))[1] = auth.uid()::text
    and exists (
      select 1
      from public.book_series bs
      where bs.id::text = (storage.foldername(name))[2]
        and bs.owner_id = auth.uid()
    )
  );
