# API RAWG + Steam (Flutter Web)

Proxy CORS pour la recherche jeux vidéo (RAWG + Steam en parallèle, cache 15 min).

## Déploiement (CLI)

Projet : `jfudrneoblsiingjqsio`

```bash
supabase login
supabase link --project-ref jfudrneoblsiingjqsio
supabase secrets set RAWG_API_KEY=ta_vraie_cle_rawg
supabase functions deploy rawg-api --no-verify-jwt
```

Installer le CLI : https://supabase.com/docs/guides/cli/getting-started

## Déploiement (Dashboard, sans CLI)

1. [Dashboard → Edge Functions](https://supabase.com/dashboard/project/jfudrneoblsiingjqsio/functions)
2. Créer une fonction `rawg-api`, coller le contenu de `index.ts`
3. [Project Settings → Secrets](https://supabase.com/dashboard/project/jfudrneoblsiingjqsio/settings/functions) : ajouter `RAWG_API_KEY`
4. Déployer avec **Verify JWT** désactivé (`--no-verify-jwt`)

## Test

`https://jfudrneoblsiingjqsio.supabase.co/functions/v1/rawg-api?action=search&query=zelda`
