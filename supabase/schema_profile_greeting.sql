-- Genre et accord des salutations (ne jamais écraser avec null côté app).
alter table public.profiles
  add column if not exists gender_identity text,
  add column if not exists greeting_grammar text;
