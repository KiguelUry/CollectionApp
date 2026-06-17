# API JSON BGG (Flutter Web)

Le navigateur appelle cette fonction au lieu de parser du XML. Réponses JSON stables pour recherche, hot, fiche jeu et extensions.

## Déploiement

Même secret que `bgg-proxy` : `BGG_APPLICATION_TOKEN`.

```bash
supabase login
supabase link --project-ref TON_PROJECT_REF
supabase secrets set BGG_APPLICATION_TOKEN=ton_token_bgg
supabase functions deploy bgg-api --no-verify-jwt
```

## Endpoints

| Action | Paramètres | Réponse |
|--------|------------|---------|
| `search` | `query`, `sort=smart\|recent` | `{ "games": [{ "id", "title", "year", "bgg_rank?", "image_url?" }] }` |
| `hot` | — | `{ "games": [...] }` |
| `game` | `id` | `{ "game": { "bgg_id", "image_url", ... } }` |
| `expansions` | `id` | `{ "expansions": [...] }` |

Exemple :

`https://TON_PROJECT.supabase.co/functions/v1/bgg-api?action=search&query=catan`
