# Supabase — scripts SQL

## Correctif sécurité (prod)

Si tu as exporté des policies `boardgames_*` avec `using: true` ou `friendships_all_authenticated`, exécute **une fois** :

**`schema_rls_fix_live.sql`** → Supabase Dashboard → SQL Editor → Run

Puis vérifie :

```sql
SELECT tablename, policyname FROM pg_policies
WHERE schemaname = 'public'
ORDER BY tablename, policyname;
```

Tu ne dois **plus** voir : `boardgames_*`, `*_all_authenticated`.

## Correctif menu home bloqué (récursion RLS)

Si l’app affiche un chargement infini sur l’accueil et les logs mentionnent  
`infinite recursion detected in policy for relation "group_members"` :

**`schema_rls_group_members_fix.sql`** → SQL Editor → Run (une fois)

## Trophées + fil d’activité

- `schema_profile_trophies.sql` — colonne `favorite_item_ids`
- `schema_activity_feed.sql` — table `activity_events`

## Ordre indicatif (nouvelle base)

1. `schema_profiles.sql`
2. `schema_profiles_backfill.sql` (comptes existants)
3. Tables collection / social (selon ton historique)
4. `schema_collection_items_rls.sql` — remplacé par `schema_rls_fix_live.sql` en prod
5. `schema_friend_requests.sql` — **ne pas** ré-exécuter après le fix (il affaiblit `share_collections`)
6. Fonctions : `schema_showcase.sql`, `schema_book_series.sql`, etc.
7. Edge Function `functions/bgg-proxy` + secret `BGG_APPLICATION_TOKEN`

## Edge Functions

- Secrets : **Edge Functions → Secrets** (pas Project Settings général)
- `bgg-proxy` : désactiver **Verify JWT** pour le web Vercel
