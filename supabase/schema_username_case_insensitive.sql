-- Pseudo unique sans tenir compte de la casse (kiki = KIKI).
-- À exécuter une fois sur Supabase.

create unique index if not exists profiles_username_lower_unique
  on public.profiles (lower(username));
