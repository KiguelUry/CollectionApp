# Proxy BGG (Flutter Web / Vercel)

Le navigateur ne peut pas appeler `boardgamegeek.com` directement (CORS). Cette fonction relaie les requêtes `/xmlapi2/*`.

## Déploiement (une fois)

### Via le dashboard Supabase (Editor)

1. **Edge Functions** → fonction `bgg-proxy` → coller le code de `index.ts` → **Deploy**
2. Désactiver **Verify JWT** sur la fonction (accès web avec clé `anon`)
3. **Important** — ajouter le secret BGG (sinon « Unauthorized » de BGG) :
   - **Project Settings** → **Edge Functions** → **Secrets** (ou **Manage secrets**)
   - Nom : `BGG_APPLICATION_TOKEN`
   - Valeur : **exactement** le même token que dans ton `.env` local (`BGG_APPLICATION_TOKEN=...`)
   - Le token vient de [boardgamegeek.com/applications](https://boardgamegeek.com/applications) → ton app → **Tokens**
4. Pas besoin de redéployer après avoir ajouté le secret (lu à chaque requête)

### Via CLI (optionnel)

```bash
supabase login
supabase link --project-ref TON_PROJECT_REF
supabase secrets set BGG_APPLICATION_TOKEN=ton_token_bgg
supabase functions deploy bgg-proxy --no-verify-jwt
```

`--no-verify-jwt` : la fonction est publique (lecture BGG uniquement).

## Vérification

`https://TON_PROJECT.supabase.co/functions/v1/bgg-proxy?path=/xmlapi2/hot&type=boardgame`

Doit renvoyer du XML BGG.
