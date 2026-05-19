-- Wishlist visible par les amis (défaut : oui)
alter table public.profiles
  add column if not exists share_wishlist boolean not null default true;
