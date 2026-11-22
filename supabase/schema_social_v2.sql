-- Social v2 : demandes d'emprunt, « ami accepté », réactions notifiées,
-- fil d'activité sans doublons.
-- Exécuter dans Supabase → SQL Editor (après schema_notifications.sql,
-- schema_activity_feed.sql et schema_pantheon_households_reactions.sql).
-- Idempotent. L'app fonctionne aussi sans (repli côté client).

-- 1. Nouveaux types de notification --------------------------------------
alter table public.app_notifications
  drop constraint if exists app_notifications_type_check;

alter table public.app_notifications
  add constraint app_notifications_type_check
  check (
    type in (
      'friend_request',
      'group_invite',
      'item_recommendation',
      'play_shared',
      'borrow_request',
      'friend_accepted',
      'activity_reaction'
    )
  );

drop policy if exists app_notifications_insert on public.app_notifications;
create policy app_notifications_insert
  on public.app_notifications
  for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and type in (
      'group_invite', 'item_recommendation', 'play_shared', 'borrow_request'
    )
    and exists (
      select 1
      from public.friendships f
      where f.status = 'accepted'
        and (
          (f.requester_id = auth.uid() and f.addressee_id = recipient_id)
          or (f.addressee_id = auth.uid() and f.requester_id = recipient_id)
        )
    )
    and (
      type <> 'group_invite'
      or exists (
        select 1
        from public.group_members gm
        where gm.group_id = nullif(payload ->> 'group_id', '')::uuid
          and gm.profile_id = auth.uid()
      )
    )
    -- Une demande d'emprunt vise forcément un objet du destinataire.
    and (
      type <> 'borrow_request'
      or exists (
        select 1
        from public.collection_items ci
        where ci.id = nullif(payload ->> 'item_id', '')::uuid
          and ci.added_by = recipient_id
      )
    )
  );

-- 2. Demande d'ami : notif « accepté » renvoyée au demandeur ---------------
create or replace function public.notify_friend_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  sender_name text;
  accepter_name text;
begin
  if tg_op = 'INSERT' and new.status = 'pending' then
    select username into sender_name from public.profiles where id = new.requester_id;
    insert into public.app_notifications (
      recipient_id, sender_id, type, payload, dedupe_key
    )
    values (
      new.addressee_id,
      new.requester_id,
      'friend_request',
      jsonb_build_object(
        'friendship_id', new.id,
        'sender_username', coalesce(sender_name, 'Quelqu''un')
      ),
      'friend:' || new.id::text
    )
    on conflict do nothing;
  elsif tg_op = 'UPDATE' and new.status = 'accepted' and old.status <> 'accepted' then
    update public.app_notifications
      set status = 'accepted', read_at = coalesce(read_at, now())
      where dedupe_key = 'friend:' || new.id::text;
    select username into accepter_name from public.profiles where id = new.addressee_id;
    insert into public.app_notifications (
      recipient_id, sender_id, type, payload, dedupe_key
    )
    values (
      new.requester_id,
      new.addressee_id,
      'friend_accepted',
      jsonb_build_object(
        'friendship_id', new.id,
        'sender_username', coalesce(accepter_name, 'Quelqu''un')
      ),
      'friend_accepted:' || new.id::text
    )
    on conflict do nothing;
  elsif tg_op = 'DELETE' and old.status = 'pending' then
    update public.app_notifications
      set status = 'declined', read_at = coalesce(read_at, now())
      where dedupe_key = 'friend:' || old.id::text
        and status in ('unread', 'read');
  end if;
  return coalesce(new, old);
end;
$$;

-- 3. Réaction sur mon activité → notification (une par personne et par event)
create or replace function public.notify_activity_reaction()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  ev public.activity_events;
  reactor_name text;
  item_title text;
begin
  select * into ev from public.activity_events where id = new.event_id;
  if not found or ev.actor_id = new.user_id then
    return new;
  end if;
  select username into reactor_name from public.profiles where id = new.user_id;
  select title into item_title from public.collection_items where id = ev.item_id;
  insert into public.app_notifications (
    recipient_id, sender_id, type, payload, dedupe_key
  )
  values (
    ev.actor_id,
    new.user_id,
    'activity_reaction',
    jsonb_build_object(
      'event_id', ev.id,
      'emoji', new.emoji,
      'item_id', ev.item_id,
      'item_title', item_title,
      'sender_username', coalesce(reactor_name, 'Quelqu''un')
    ),
    'reaction:' || ev.id::text || ':' || new.user_id::text
  )
  on conflict (recipient_id, dedupe_key) where dedupe_key is not null
  do update set
    payload = excluded.payload,
    status = 'unread',
    read_at = null,
    created_at = now();
  return new;
end;
$$;

drop trigger if exists activity_reactions_notify on public.activity_reactions;
create trigger activity_reactions_notify
  after insert or update of emoji on public.activity_reactions
  for each row
  execute function public.notify_activity_reaction();

-- 4. Fil d'activité : titre figé + pas de doublon (même jeu en < 10 min) ---
create or replace function public.log_collection_item_activity()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  kind text;
  bgg text;
begin
  if tg_op = 'INSERT' then
    kind := case when new.is_wishlist then 'wishlist_added' else 'item_added' end;
    bgg := nullif(new.metadata ->> 'bgg_id', '');
    if exists (
      select 1
      from public.activity_events e
      left join public.collection_items ci on ci.id = e.item_id
      where e.actor_id = auth.uid()
        and e.event_type = kind
        and e.created_at > now() - interval '10 minutes'
        and (
          (bgg is not null and coalesce(e.payload ->> 'bgg_id', ci.metadata ->> 'bgg_id') = bgg)
          or lower(coalesce(e.payload ->> 'title', ci.title, '')) = lower(new.title)
        )
    ) then
      return new;
    end if;
    insert into public.activity_events (actor_id, event_type, item_id, payload)
    values (
      auth.uid(),
      kind,
      new.id,
      jsonb_strip_nulls(jsonb_build_object('title', new.title, 'bgg_id', bgg))
    );
  elsif tg_op = 'UPDATE'
      and new.rating is distinct from old.rating
      and new.rating is not null then
    insert into public.activity_events (actor_id, event_type, item_id, payload)
    values (
      auth.uid(),
      'item_rated',
      new.id,
      jsonb_build_object('rating', new.rating, 'title', new.title)
    );
  end if;
  return new;
end;
$$;

-- 5. Nettoyage des doublons déjà présents (même acteur, type, objet titre,
--    à moins de 10 minutes d'intervalle) : on garde le plus ancien.
delete from public.activity_events e
using public.activity_events older, public.collection_items ci_e, public.collection_items ci_o
where e.item_id = ci_e.id
  and older.item_id = ci_o.id
  and e.actor_id = older.actor_id
  and e.event_type = older.event_type
  and e.event_type in ('item_added', 'wishlist_added')
  and lower(ci_e.title) = lower(ci_o.title)
  and older.created_at < e.created_at
  and e.created_at - older.created_at < interval '10 minutes';
