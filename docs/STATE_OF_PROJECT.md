# Collectingo — State of Project (handoff tour → portable)

> **Pour Cursor sur le portable :** lis ce fichier en premier, puis `docs/NOV10_CHECKLIST.md`.  
> Dernière MAJ : **2026-11-08** · HEAD attendu : `bbb09d2` (+ commit de ce fichier) · branche `main`.

---

## 1. C’est quoi

App Flutter **multi-collections** (jeux, livres/manga, TCG, vinyles, JV, films, Lego, etc.)  
+ social (amis, groupes, prêts) · backend **Supabase** · front web **GitHub Pages**.

Repo : `https://github.com/KiguelUry/CollectionApp.git`  
Projet Supabase : `jfudrneoblsiingjqsio` (eu-west-1) · Org free, **EXCEEDING USAGE LIMITS** jusqu’au reset **~10 nov 2026**.

---

## 2. Stack & URLs critiques

| Élément | Valeur |
|--------|--------|
| Supabase URL | `https://jfudrneoblsiingjqsio.supabase.co` |
| Anon key (publique, aussi dans `lib/config/supabase_public_config.dart`) | `sb_publishable_…` |
| Cloudflare Worker catalog-proxy | `https://paloma-catalog-proxy.kilian-ury.workers.dev` |
| Constante Dart | `lib/config/catalog_proxy_config.dart` → `kCloudflareCatalogProxyUrl` |
| Source Worker | `cloudflare/paloma-catalog-proxy.js` (à coller dans CF Edit code si MAJ) |
| Edge encore sur Supabase | `bgg-api` (XML BGG + secret `BGG_APPLICATION_TOKEN`) — **pas** migré CF |
| Deploy web | `.github/workflows/deploy.yml` → GitHub Pages |

---

## 3. Blocage actuel (contexte)

- Auth / API app : **402 `exceed_egress_quota`** → **pas de login** jusqu’au reset quota (~10 nov) ou upgrade Pro.
- Dashboard SQL Supabase : encore accessible.
- Cloudflare Worker : **indépendant** du 402 (images MangaDex / proxy JSON CORS).
- « Invalid url » sur l’URL nue du Worker **sans** `?url=` = **normal** (garde-fou). Health : `/?health=1`.

---

## 4. Correctifs Egress / perf (déjà sur `main`)

Ordre chronologique récent (résumé) :

1. **Slim metadata** + batch `book_volumes` + kill realtime streams home.
2. **Images** : wsrv.nl (Apple/Google/BGG…) · MangaDex **uniquement** via proxy (jamais wsrv).
3. **FailSafeNetworkImage** : coupe-circuit anti-boucle ; soft TTL 45s sur échecs.
4. Kill **MetadataPurge** au login · kill prefetch prix BGG en masse.
5. **SupabaseReadCache** TTL 10 min + inFlight (`collection_items`, volumes, friendships…).
6. **InventoryService** = **1 seul GET** hub/drawer/social (fini `select=metadata` séparé SocialDirectory).
7. Fiche série : `PopScope` + `_hasMutatedData` → pas de re-fetch 42 kB au pop propre.
8. Grille tomes : **SliverGrid lazy** (plus One Piece = 100 covers d’un coup).
9. MangaDex : append officiel `.jpg.256.jpg` (pas replace) · `.512` lightbox seul.
10. **Cloudflare Worker** `paloma-catalog-proxy` branché → egress images **hors** Supabase.
11. Login : message humain 402 (`lib/utils/supabase_error_messages.dart`).
12. Cartes TCG : cache `card_meta:` · discovery genres via InventoryService · stats sans faux enrich BGG.

Scripts / docs utiles :
- `scripts/vacuum-full.ps1` — VACUUM FULL via **psql local** (pas SQL Editor). Cosmétique disque, **≠** Egress.
- `docs/NOV10_CHECKLIST.md` — smoke test le jour du reset.

---

## 5. Architecture images (ne pas casser)

```
MangaDex uploads.*  →  Cloudflare Worker (?url=)  →  .256.jpg
Apple / Google / BGG / Discogs  →  wsrv.nl
AniList / TMDB / OpenLibrary…  →  HTTPS direct si CORS OK
```

Proxy CF : **pas** d’`apikey` dans l’URL (évite preflight).  
Fallback si `kCloudflareCatalogProxyUrl` vide : Edge Supabase `catalog-proxy` + apikey.

---

## 6. Capacités produit (bilan court)

**Fort :** boardgames (BGG, parties, discover), livres/séries, TCG, amis/groupes/prêts, wishlist, stats, caches.  
**Moyen :** JV, films, Lego, media Discogs, tech/montres.  
**Lab / masqué :** wildlife, restos · car/stamp/coin dans l’enum peu exposés.  
**Dette :** écrans orphelins (`user_lists_*`, ancien hub BG…), marketplace mince.

**Direction produit (après stabilité Egress) :** features **local/cache-first**  
(ex. « Ce soir on joue », listes perso, rappels prêts) — voir chat du 6 nov.

---

## 7. Secrets — ce qui NE passe PAS par Git

Fichier **local uniquement** (gitignore) à recopier sur le portable :

| Fichier | Rôle |
|---------|------|
| `.env` (racine) | Clés locales Flutter |

Clés présentes sur la tour (noms) :
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `BGG_APPLICATION_TOKEN`, `GOOGLE_BOOKS_API_KEY`,  
`DISCOGS_TOKEN`, `TMDB_API_KEY`, `RAWG_API_KEY`, `REBRICKABLE_API_KEY`,  
+ optionnel `DEV_TEST_EMAIL` / `DEV_TEST_PASSWORD` / `DEV_LOGIN_LABEL`.

**Ne jamais committer `.env`.**  
Modèle : `.env.example`.  
Note : `CATALOG_PROXY_URL` peut manquer dans `.env` — OK car URL CF est **hardcodée** dans `catalog_proxy_config.dart`.

GitHub Actions secrets (deploy Pages) : mêmes clés côté repo Settings → Secrets.

---

## 8. Setup portable Croatie (checklist exacte)

### Avant de quitter la tour
1. `git status` clean + `git push origin main` (fait avec ce fichier).
2. Copier **`.env`** vers Drive / clé USB / gestionnaire de mots de passe (fichier chiffré).
3. Noter logins : GitHub, Supabase, Cloudflare, Google (Books key).
4. (Optionnel) `flutter upgrade` + `flutter pub get` sur la tour pour connaître la version cible.

### Sur le portable (fibre avant vacances si possible)
```powershell
# 1. Outils
winget install Git.Git
winget install Flutter.Flutter   # ou installer depuis flutter.dev
# Android Studio / VS Code / Cursor selon ton flow

# 2. Clone
git clone https://github.com/KiguelUry/CollectionApp.git
cd CollectionApp
git checkout main
git pull

# 3. Secrets
# Coller le .env de la tour à la racine (même contenu)

# 4. Dépendances
flutter pub get
flutter analyze
flutter test

# 5. Lire le contexte
# Ouvrir Cursor → @docs/STATE_OF_PROJECT.md + @docs/NOV10_CHECKLIST.md

# 6. CLI si tu dois déployer proxy / edge
npx supabase login
npx supabase link --project-ref jfudrneoblsiingjqsio
# Cloudflare Worker : dash.cloudflare.com (Edit code) OU wrangler login
```

### Limite jusqu’au ~10 nov
- Tu peux **coder + tester unitaires**.
- Tu **ne pourras pas** te connecter à l’app live (402 Auth) tant que le quota n’est pas reset.
- Worker CF testable à la main :  
  `https://paloma-catalog-proxy.kilian-ury.workers.dev/?health=1`

### Prompt Cursor portable (copier-coller)
```
Lis docs/STATE_OF_PROJECT.md et docs/NOV10_CHECKLIST.md.
On reprend Collectingo sur portable. Ne committe jamais .env.
État : quota Supabase Egress bloqué jusqu’au ~10 nov 2026 ; Worker CF déjà en place.
Propose la prochaine tâche utile offline (tests, UI, dette écrans orphelins) ou smoke post-reset.
```

---

## 9. Prochaines priorités suggérées

**Dès accès Auth (post-10) :**
1. Suivre `NOV10_CHECKLIST.md` (login + Network CF vs Supabase).
2. Confirmer hub = 1× `collection_items`, MangaDex sur `workers.dev`.

**Ensuite (features, egress-safe) :**
1. « Ce soir on joue » / listes perso / rappels prêts.
2. Nettoyer écrans orphelins.
3. (Optionnel) VACUUM via `scripts/vacuum-full.ps1` si jauge DB dérange.

---

## 10. Fichiers « mémoire » pour l’agent

| Fichier | Quand le lire |
|---------|----------------|
| `docs/STATE_OF_PROJECT.md` | Toujours (ce handoff) |
| `docs/NOV10_CHECKLIST.md` | Jour du reset quota |
| `cloudflare/paloma-catalog-proxy.js` | MAJ Worker |
| `lib/config/catalog_proxy_config.dart` | URL proxy |
| `lib/services/inventory_service.dart` | Lecture collection unifiée |
| `lib/utils/web_image_proxy.dart` | Routage images |

Les transcripts Cursor de la tour **ne se synchronisent pas** : ce doc + git remplacent l’historique chat.
