-- =============================================================================
-- Profils manquants : comptes Auth sans ligne dans public.profiles
-- → erreur FK collection_items_added_by_fkey à l'ajout d'un jeu/livre
--
-- À exécuter dans Supabase → SQL Editor (une fois, en tant qu'admin).
-- Ne remplace pas schema_profiles.sql (RLS insert) : les deux sont utiles.
-- =============================================================================

-- 1) Créer les profils pour tous les utilisateurs Auth existants
insert into public.profiles (id, username)
select
  u.id,
  coalesce(
    nullif(trim(u.raw_user_meta_data ->> 'username'), ''),
    nullif(trim(split_part(coalesce(u.email, ''), '@', 1)), ''),
    'user_' || left(u.id::text, 8)
  ) as username
from auth.users u
where not exists (
  select 1 from public.profiles p where p.id = u.id
);

-- 2) Trigger : chaque nouvel inscrit obtient automatiquement un profil
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, username)
  values (
    new.id,
    coalesce(
      nullif(trim(new.raw_user_meta_data ->> 'username'), ''),
      nullif(trim(split_part(coalesce(new.email, ''), '@', 1)), ''),
      'user_' || left(new.id::text, 8)
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 3) Vérification (doit retourner 0 ligne)
-- select u.id, u.email
-- from auth.users u
-- left join public.profiles p on p.id = u.id
-- where p.id is null;
