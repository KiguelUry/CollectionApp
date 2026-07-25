-- Lieux « Autre » partagés au sein d'un groupe (suggestions « Chez qui ? »)
-- À exécuter une fois dans Supabase → SQL Editor (après schema_rls_group_members_fix.sql).

create table if not exists public.group_holder_places (
  id uuid primary key default gen_random_uuid(),
  group_id uuid not null references public.groups (id) on delete cascade,
  label text not null,
  normalized_label text not null,
  created_by uuid references public.profiles (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint group_holder_places_label_not_empty check (char_length(trim(label)) > 0),
  constraint group_holder_places_normalized_not_empty check (char_length(trim(normalized_label)) > 0),
  constraint group_holder_places_group_label_unique unique (group_id, normalized_label)
);

create index if not exists group_holder_places_group_id_idx
  on public.group_holder_places (group_id);

alter table public.group_holder_places enable row level security;

drop policy if exists group_holder_places_select on public.group_holder_places;
drop policy if exists group_holder_places_insert on public.group_holder_places;
drop policy if exists group_holder_places_delete on public.group_holder_places;

create policy group_holder_places_select
  on public.group_holder_places
  for select
  to authenticated
  using (public.is_group_member(group_id));

create policy group_holder_places_insert
  on public.group_holder_places
  for insert
  to authenticated
  with check (public.is_group_member(group_id));

create policy group_holder_places_delete
  on public.group_holder_places
  for delete
  to authenticated
  using (public.is_group_member(group_id));

grant select, insert, delete on public.group_holder_places to authenticated;
grant all on public.group_holder_places to postgres, service_role;
