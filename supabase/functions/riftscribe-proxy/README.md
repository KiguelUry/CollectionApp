# riftscribe-proxy

Le navigateur ne peut pas appeler `riftscribe.gg` directement (CORS). Cette fonction relaie les requêtes `/api/cards*`.

**Aucune clé API** — RiftScribe est public.

```bash
supabase functions deploy riftscribe-proxy --no-verify-jwt
```
