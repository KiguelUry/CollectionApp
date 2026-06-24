-- Pokédex sauvage : observations multiples par espèce
create table if not exists public.wildlife_observations (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.collection_items (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  observed_at timestamptz not null default now(),
  note text,
  photo_url text,
  latitude double precision,
  longitude double precision,
  place_label text,
  created_at timestamptz not null default now()
);

create index if not exists wildlife_observations_item_idx
  on public.wildlife_observations (item_id);

create index if not exists wildlife_observations_user_idx
  on public.wildlife_observations (user_id);

alter table public.wildlife_observations enable row level security;

create policy wildlife_observations_own
  on public.wildlife_observations
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- Journal culinaire : visites restaurant
create table if not exists public.restaurant_visits (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references public.collection_items (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  visited_at timestamptz not null default now(),
  rating int check (rating is null or (rating >= 1 and rating <= 5)),
  review text,
  dishes jsonb not null default '[]'::jsonb,
  with_friend_id uuid references public.profiles (id) on delete set null,
  with_friend_name text,
  latitude double precision,
  longitude double precision,
  created_at timestamptz not null default now()
);

create index if not exists restaurant_visits_item_idx
  on public.restaurant_visits (item_id);

create index if not exists restaurant_visits_user_idx
  on public.restaurant_visits (user_id);

alter table public.restaurant_visits enable row level security;

create policy restaurant_visits_own
  on public.restaurant_visits
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

create policy restaurant_visits_group_read
  on public.restaurant_visits
  for select
  to authenticated
  using (
    exists (
      select 1 from public.collection_items ci
      join public.collection_item_groups cig on cig.item_id = ci.id
      join public.group_members gm on gm.group_id = cig.group_id
      where ci.id = restaurant_visits.item_id
        and gm.profile_id = auth.uid()
    )
    or exists (
      select 1 from public.collection_items ci
      join public.group_members gm on gm.group_id = ci.group_id
      where ci.id = restaurant_visits.item_id
        and gm.profile_id = auth.uid()
    )
  );
