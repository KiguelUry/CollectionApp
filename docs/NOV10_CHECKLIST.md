# Checklist — après le reset Supabase (10 novembre 2026)

## Avant de te connecter
1. Hard-refresh navigateur (`Ctrl+Shift+R`) sur l’app déployée (GitHub Pages).
2. Vérifier que `lib/config/catalog_proxy_config.dart` pointe encore vers  
   `https://paloma-catalog-proxy.kilian-ury.workers.dev`.
3. Optionnel : coller à jour le Worker Cloudflare avec `cloudflare/paloma-catalog-proxy.js`  
   (Edit code → Deploy) si tu n’as pas encore la version avec `?health=1`.

## Smoke tests (2 minutes)
1. Login OK (plus de 402 `exceed_egress_quota`).
2. Console navigateur : 0 erreur rouge Auth.
3. Network, filtre `supabase.co` :
   - Auth + PostgREST OK
   - **Pas** de rafale `functions/v1/catalog-proxy` (doit être sur `workers.dev`)
4. Network, filtre `workers.dev` :
   - covers MangaDex en `200` (~20–80 Ko), souvent `(disk cache)` au 2ᵉ passage
5. Ouvre One Piece / Monster : scroll lazy → pas 100+ images d’un coup.
6. Coller le radar console (optionnel) :

```js
(() => {
  const stats = {};
  performance.getEntriesByType('resource').forEach(r => {
    const url = new URL(r.name);
    let key = url.hostname;
    if (key.includes('supabase.co')) {
      key = url.pathname.includes('catalog-proxy') ? 'Supabase: catalog-proxy'
          : url.pathname.includes('bgg-api') ? 'Supabase: bgg-api'
          : 'Supabase DB: ' + (url.pathname.split('/').pop() || 'root');
    }
    if (key.includes('workers.dev')) key = 'Cloudflare Worker';
    stats[key] = stats[key] || { appels: 0, ko: 0 };
    stats[key].appels++;
    stats[key].ko += Math.round((r.transferSize || 0) / 1024);
  });
  console.table(stats);
})();
```

## Cibles réalistes (session 5 min, F5 pas Ctrl+Shift+R)
- Accueil hub : ~1 requête `collection_items`, &lt; ~500 Ko transferés supabase
- MangaDex : trafic sur `workers.dev`, pas sur Functions Supabase
- Pas de `bgg-api?action=prices` en rafale

## VACUUM (cosmétique disque, pas Egress)
Voir `scripts/vacuum-full.ps1` — **jamais** coller `psql …` dans le SQL Editor.
