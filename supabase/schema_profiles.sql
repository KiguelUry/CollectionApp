-- =============================================================================
-- Profils personnalisés : avatar, couleur, bio + bucket Storage
-- À exécuter dans Supabase → SQL Editor
-- =============================================================================

alter table public.profiles
  add column if not exists avatar_url text,
  add column if not exists accent_color text default '#673AB7',
  add column if not exists bio text;

alter table public.profiles
  drop constraint if exists profiles_bio_length_check;

alter table public.profiles
  add constraint profiles_bio_length_check
  check (bio is null or char_length(bio) <= 280);

-- Bucket public pour les avatars (lecture publique, écriture par le propriétaire)
insert into storage.buckets (id, name, public)
values ('avatars', 'avatars', true)
on conflict (id) do update set public = true;

-- Policies storage (idempotent)
drop policy if exists "Avatars public read" on storage.objects;
create policy "Avatars public read"
  on storage.objects for select
  using (bucket_id = 'avatars');

drop policy if exists "Users upload own avatar" on storage.objects;
create policy "Users upload own avatar"
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users update own avatar" on storage.objects;
create policy "Users update own avatar"
  on storage.objects for update
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

drop policy if exists "Users delete own avatar" on storage.objects;
create policy "Users delete own avatar"
  on storage.objects for delete
  to authenticated
  using (
    bucket_id = 'avatars'
    and (storage.foldername(name))[1] = auth.uid()::text
  );

-- Création du profil par l'utilisateur connecté (comptes sans ligne profiles)
drop policy if exists "Users insert own profile row" on public.profiles;
create policy "Users insert own profile row"
  on public.profiles for insert
  to authenticated
  with check (auth.uid() = id);

-- Mise à jour du profil par l'utilisateur connecté
drop policy if exists "Users update own profile row" on public.profiles;
create policy "Users update own profile row"
  on public.profiles for update
  to authenticated
  using (auth.uid() = id)
  with check (auth.uid() = id);
