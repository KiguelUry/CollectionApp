-- Journal Quick Log (sessions de lecture, parties, etc.)
create table if not exists public.user_quick_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  item_id uuid references public.collection_items (id) on delete set null,
  note text not null,
  logged_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create index if not exists user_quick_logs_user_idx
  on public.user_quick_logs (user_id, logged_at desc);

alter table public.user_quick_logs enable row level security;

create policy user_quick_logs_own
  on public.user_quick_logs
  for all
  to authenticated
  using (user_id = auth.uid())
  with check (user_id = auth.uid());
