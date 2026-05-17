-- =============================================================================
-- Vitrine publique : lien lisible sans installer l'app
-- À exécuter dans Supabase → SQL Editor
-- =============================================================================

alter table public.profiles
  add column if not exists showcase_public boolean not null default false,
  add column if not exists showcase_token text;

create unique index if not exists profiles_showcase_token_idx
  on public.profiles (showcase_token)
  where showcase_token is not null;

-- Données publiques via token (pas d'auth requise)
create or replace function public.get_public_showcase(p_token text)
returns json
language plpgsql
security definer
set search_path = public
as $$
declare
  v_profile_id uuid;
  v_username text;
  v_avatar text;
  v_accent text;
  v_bio text;
  v_items json;
begin
  if p_token is null or length(trim(p_token)) < 8 then
    return json_build_object('error', 'invalid_token');
  end if;

  select id, username, avatar_url, accent_color, bio
  into v_profile_id, v_username, v_avatar, v_accent, v_bio
  from public.profiles
  where showcase_token = trim(p_token)
    and showcase_public = true;

  if v_profile_id is null then
    return json_build_object('error', 'not_found');
  end if;

  select coalesce(
    json_agg(
      json_build_object(
        'title', title,
        'category', category,
        'quantity', quantity,
        'rating', rating,
        'is_wishlist', coalesce(is_wishlist, false),
        'is_for_sale', coalesce(is_for_sale, false),
        'is_sold', coalesce(is_sold, false)
      )
      order by category, title
    ),
    '[]'::json
  )
  into v_items
  from public.collection_items
  where group_id is null
    and (
      added_by = v_profile_id
      or location_user_id = v_profile_id
    );

  return json_build_object(
    'username', v_username,
    'avatar_url', v_avatar,
    'accent_color', coalesce(v_accent, '#673AB7'),
    'bio', v_bio,
    'items', v_items
  );
end;
$$;

revoke all on function public.get_public_showcase(text) from public;
grant execute on function public.get_public_showcase(text) to anon, authenticated;
