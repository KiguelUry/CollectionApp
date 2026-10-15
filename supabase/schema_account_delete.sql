-- Suppression de compte (RGPD) : nettoie les données utilisateur puis auth.users.
-- Exécuter dans Supabase → SQL Editor (rôle postgres) après les autres schémas.
-- La fonction est SECURITY DEFINER pour pouvoir supprimer la ligne auth.

create or replace function public.delete_my_account()
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  uid uuid := auth.uid();
begin
  if uid is null then
    raise exception 'Non connecté';
  end if;

  delete from public.app_notifications
    where recipient_id = uid or sender_id = uid;

  delete from public.friendships
    where requester_id = uid or addressee_id = uid;

  delete from public.group_members where profile_id = uid;

  delete from public.collection_items
    where added_by = uid or location_user_id = uid;

  delete from public.profiles where id = uid;

  delete from auth.users where id = uid;
end;
$$;

grant execute on function public.delete_my_account() to authenticated;
