-- Marketplace : messages d'intérêt et propositions de troc
-- À exécuter dans Supabase → SQL Editor

create table if not exists public.marketplace_inquiries (
  id uuid primary key default gen_random_uuid(),
  listing_item_id uuid not null references public.collection_items (id) on delete cascade,
  sender_id uuid not null references public.profiles (id) on delete cascade,
  owner_id uuid not null references public.profiles (id) on delete cascade,
  message text not null,
  proposed_item_id uuid references public.collection_items (id) on delete set null,
  created_at timestamptz not null default now(),
  constraint marketplace_inquiries_message_not_empty
    check (char_length(trim(message)) > 0)
);

create index if not exists marketplace_inquiries_listing_idx
  on public.marketplace_inquiries (listing_item_id, created_at desc);

create index if not exists marketplace_inquiries_owner_idx
  on public.marketplace_inquiries (owner_id, created_at desc);

alter table public.marketplace_inquiries enable row level security;

drop policy if exists marketplace_inquiries_select on public.marketplace_inquiries;
drop policy if exists marketplace_inquiries_insert on public.marketplace_inquiries;

create policy marketplace_inquiries_select
  on public.marketplace_inquiries
  for select
  to authenticated
  using (sender_id = auth.uid() or owner_id = auth.uid());

create policy marketplace_inquiries_insert
  on public.marketplace_inquiries
  for insert
  to authenticated
  with check (sender_id = auth.uid());

grant select, insert on public.marketplace_inquiries to authenticated;
