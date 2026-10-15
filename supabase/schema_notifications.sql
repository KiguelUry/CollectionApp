-- Centre de notifications (demandes d'ami, invitations groupe,
-- recommandations d'objets, parties partagées).
-- Exécuter dans Supabase → SQL Editor (après schema_social.sql et
-- schema_friend_requests.sql). Idempotent.

create table if not exists public.app_notifications (
  id uuid primary key default gen_random_uuid(),
  recipient_id uuid not null references public.profiles (id) on delete cascade,
  sender_id uuid references public.profiles (id) on delete cascade,
  type text not null check (
    type in (
      'friend_request',
      'group_invite',
      'item_recommendation',
      'play_shared'
    )
  ),
  payload jsonb not null default '{}'::jsonb,
  status text not null default 'unread'
    check (status in ('unread', 'read', 'accepted', 'declined')),
  -- Empêche les doublons (même partie partagée, même demande d'ami…).
  dedupe_key text,
  read_at timestamptz,
  created_at timestamptz not null default now(),
  constraint app_notifications_not_self check (sender_id is null or sender_id <> recipient_id)
);

create unique index if not exists app_notifications_dedupe_idx
  on public.app_notifications (recipient_id, dedupe_key)
  where dedupe_key is not null;

create index if not exists app_notifications_recipient_idx
  on public.app_notifications (recipient_id, created_at desc);

alter table public.app_notifications enable row level security;

drop policy if exists app_notifications_select on public.app_notifications;
drop policy if exists app_notifications_insert on public.app_notifications;
drop policy if exists app_notifications_update on public.app_notifications;
drop policy if exists app_notifications_delete on public.app_notifications;

create policy app_notifications_select
  on public.app_notifications
  for select
  to authenticated
  using (recipient_id = auth.uid() or sender_id = auth.uid());

-- Envoi client : uniquement à un ami accepté ; invitation groupe = membre du groupe.
-- Les demandes d'ami sont créées par trigger (security definer).
create policy app_notifications_insert
  on public.app_notifications
  for insert
  to authenticated
  with check (
    sender_id = auth.uid()
    and type in ('group_invite', 'item_recommendation', 'play_shared')
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
  );

create policy app_notifications_update
  on public.app_notifications
  for update
  to authenticated
  using (recipient_id = auth.uid())
  with check (recipient_id = auth.uid());

create policy app_notifications_delete
  on public.app_notifications
  for delete
  to authenticated
  using (recipient_id = auth.uid() or sender_id = auth.uid());

grant select, insert, update, delete on public.app_notifications to authenticated;

-- Demande d'ami → notification ; acceptation / refus → statut synchronisé.
create or replace function public.notify_friend_request()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  sender_name text;
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
  elsif tg_op = 'DELETE' and old.status = 'pending' then
    update public.app_notifications
      set status = 'declined', read_at = coalesce(read_at, now())
      where dedupe_key = 'friend:' || old.id::text
        and status in ('unread', 'read');
  end if;
  return coalesce(new, old);
end;
$$;

drop trigger if exists friendships_notify on public.friendships;

create trigger friendships_notify
  after insert or update of status or delete on public.friendships
  for each row
  execute function public.notify_friend_request();

-- Rejoindre un groupe depuis une invitation (le destinataire n'a pas le droit
-- d'insérer directement dans group_members).
create or replace function public.accept_group_invite(p_notification_id uuid)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  n public.app_notifications;
  gid uuid;
begin
  select * into n
  from public.app_notifications
  where id = p_notification_id
    and recipient_id = auth.uid()
    and type = 'group_invite';
  if not found then
    raise exception 'Invitation introuvable';
  end if;
  gid := nullif(n.payload ->> 'group_id', '')::uuid;
  if gid is null or not exists (
    select 1 from public.group_members
    where group_id = gid and profile_id = n.sender_id
  ) then
    raise exception 'Invitation expirée';
  end if;
  insert into public.group_members (group_id, profile_id)
  values (gid, auth.uid())
  on conflict do nothing;
  update public.app_notifications
    set status = 'accepted', read_at = coalesce(read_at, now())
    where id = n.id;
end;
$$;

grant execute on function public.accept_group_invite(uuid) to authenticated;
