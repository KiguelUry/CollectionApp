-- Fil d'activité amis (ajouts, notes, trophées)
-- Exécuter après schema_rls_fix_live.sql

create table if not exists public.activity_events (
  id uuid primary key default gen_random_uuid(),
  actor_id uuid not null references public.profiles (id) on delete cascade,
  event_type text not null check (
    event_type in (
      'item_added',
      'wishlist_added',
      'item_rated',
      'trophies_updated'
    )
  ),
  item_id uuid references public.collection_items (id) on delete set null,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create index if not exists activity_events_created_at_idx
  on public.activity_events (created_at desc);

create index if not exists activity_events_actor_id_idx
  on public.activity_events (actor_id);

alter table public.activity_events enable row level security;

drop policy if exists activity_events_select on public.activity_events;
drop policy if exists activity_events_insert_own on public.activity_events;

create policy activity_events_select
  on public.activity_events
  for select
  to authenticated
  using (
    actor_id = auth.uid()
    or exists (
      select 1
      from public.friendships f
      where f.status = 'accepted'
        and f.share_collections = true
        and (
          (f.requester_id = auth.uid() and f.addressee_id = activity_events.actor_id)
          or (f.addressee_id = auth.uid() and f.requester_id = activity_events.actor_id)
        )
    )
  );

create policy activity_events_insert_own
  on public.activity_events
  for insert
  to authenticated
  with check (actor_id = auth.uid());

grant select, insert on public.activity_events to authenticated;

-- Journalisation automatique des ajouts / notes
create or replace function public.log_collection_item_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.activity_events (actor_id, event_type, item_id)
    values (
      auth.uid(),
      case when new.is_wishlist then 'wishlist_added' else 'item_added' end,
      new.id
    );
  elsif tg_op = 'UPDATE'
      and new.rating is distinct from old.rating
      and new.rating is not null then
    insert into public.activity_events (actor_id, event_type, item_id, payload)
    values (
      auth.uid(),
      'item_rated',
      new.id,
      jsonb_build_object('rating', new.rating)
    );
  end if;
  return new;
end;
$$;

drop trigger if exists collection_items_activity_log on public.collection_items;

create trigger collection_items_activity_log
  after insert or update of rating on public.collection_items
  for each row
  execute function public.log_collection_item_activity();
