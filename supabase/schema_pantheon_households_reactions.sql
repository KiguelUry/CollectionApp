-- Panthéon, foyers et réactions du fil.
-- À exécuter dans Supabase → SQL Editor.

alter table public.profiles
  add column if not exists pantheon_item_ids jsonb not null default '[]'::jsonb,
  add column if not exists households jsonb not null default '[]'::jsonb;

comment on column public.profiles.pantheon_item_ids is
  'Top 10 choisi par le joueur (ids collection_items, ordre conservé).';
comment on column public.profiles.households is
  'Foyers : [{id, place, people[]}] visibles par les amis et le groupe.';

-- Lecture des profils entre soi, amis et membres d'un même groupe
-- (les policies SELECT se cumulent).
drop policy if exists profiles_select_self_friends_groups on public.profiles;
create policy profiles_select_self_friends_groups
  on public.profiles
  for select
  to authenticated
  using (
    id = auth.uid()
    or exists (
      select 1
      from public.friendships f
      where f.status = 'accepted'
        and (
          (f.requester_id = auth.uid() and f.addressee_id = profiles.id)
          or (f.addressee_id = auth.uid() and f.requester_id = profiles.id)
        )
    )
    or exists (
      select 1
      from public.group_members me
      join public.group_members them on them.group_id = me.group_id
      where me.profile_id = auth.uid()
        and them.profile_id = profiles.id
    )
  );

create table if not exists public.activity_reactions (
  event_id uuid not null references public.activity_events (id) on delete cascade,
  user_id uuid not null references public.profiles (id) on delete cascade,
  emoji text not null check (emoji in ('🔥', '👏', '❤️', '🎲')),
  created_at timestamptz not null default now(),
  primary key (event_id, user_id)
);

alter table public.activity_reactions enable row level security;

drop policy if exists activity_reactions_select on public.activity_reactions;
create policy activity_reactions_select
  on public.activity_reactions
  for select
  to authenticated
  using (
    exists (
      select 1
      from public.activity_events e
      where e.id = activity_reactions.event_id
        and (
          e.actor_id = auth.uid()
          or exists (
            select 1
            from public.friendships f
            where f.status = 'accepted'
              and f.share_collections = true
              and (
                (f.requester_id = auth.uid() and f.addressee_id = e.actor_id)
                or (f.addressee_id = auth.uid() and f.requester_id = e.actor_id)
              )
          )
        )
    )
  );

drop policy if exists activity_reactions_write_own on public.activity_reactions;
create policy activity_reactions_write_own
  on public.activity_reactions
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

grant select, insert, update, delete on public.activity_reactions to authenticated;
