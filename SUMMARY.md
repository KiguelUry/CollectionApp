# Collectingo — Inventaire complet du projet

> Document généré pour recenser l’ensemble des fonctionnalités, collections, APIs et infrastructure de **Collectingo** (`collection_app` v1.1.0+2).  
> Stack : **Flutter** (SDK ^3.10.7) + **Supabase** (auth, Postgres, storage, edge functions) + catalogues externes.

---

## Table des matières

1. [Vue d’ensemble](#1-vue-densemble)
2. [Collections et catégories](#2-collections-et-catégories)
3. [Micro-fonctionnalités par catégorie](#3-micro-fonctionnalités-par-catégorie)
4. [Fonctionnalités globales et transverses](#4-fonctionnalités-globales-et-transverses)
5. [Infrastructure Supabase](#5-infrastructure-supabase)
6. [APIs et catalogues externes](#6-apis-et-catalogues-externes)
7. [Architecture Flutter](#7-architecture-flutter)
8. [Déploiement et configuration](#8-déploiement-et-configuration)
9. [Annexes — fichiers clés](#9-annexes--fichiers-clés)

---

## 1. Vue d’ensemble

**Collectingo** est une application de gestion de collections personnelles (et partagées) avec :

- **12 catégories** d’objets (8 visibles au menu principal, 4 masquées ou personnalisées)
- **Catalogues externes** pour enrichir les ajouts (BGG, Open Library, TCGdex, Discogs, TMDB, RAWG, Rebrickable…)
- **Social** : amis, groupes, flux d’activité, prêts, wishlist partagée
- **Multi-plateforme** : mobile/desktop natif + **web** déployé sur GitHub Pages (`/CollectionApp/`)

### Navigation principale

```
SplashScreen
  → LoginScreen (si non connecté)
  → CategorySelectionScreen (hub principal)
       ├── Hub par catégorie (Boardgames, Books, Cards, Media, Lego, Watch, Videogame, Movie)
       │     ├── Onglet « Ma collection » → HomeScreen
       │     ├── Onglet « Découvrir » / catalogue (selon catégorie)
       │     └── Wishlist (selon catégorie)
       ├── WishlistOverviewScreen (toutes catégories)
       ├── FriendsScreen / GroupsScreen
       ├── StatsScreen / InventoryManageScreen / LoansScreen
       └── SettingsScreen / ProfileEditScreen

ItemDetailScreen ← depuis toute grille/liste d’objets
```

### Routes nommées (`main.dart`)

| Route | Écran |
|-------|-------|
| `/categories` | `CategorySelectionScreen` |
| `/friends` | `FriendsScreen` |
| `/groups` | `GroupsScreen` |
| `/profile` | `ProfileEditScreen` |
| `/settings` | `SettingsScreen` |
| `/login` | `LoginScreen` |

---

## 2. Collections et catégories

Enum `CollectionCategory` — 12 valeurs, chacune mappée sur `collection_items.category` en base.

| Catégorie | Label UI | Menu principal | Hub dédié | API catalogue |
|-----------|----------|----------------|-----------|---------------|
| `boardgame` | Jeux de société | ✅ | `BoardgamesCollectionScreen` | BGG |
| `book` | Livres | ✅ | `BooksCollectionScreen` | Open Library + Google Books |
| `card` | Cartes | ✅ | `CardsCollectionScreen` | TCGdex, Scryfall, YGOProDeck, OPTCG, Lorcast |
| `media` | Vinyles / CD | ✅ | `MediaCollectionScreen` | Discogs + MusicBrainz |
| `lego` | Lego & maquettes | ✅ | `LegoCollectionScreen` | Rebrickable + Lego Fandom |
| `watch` | Montres | ✅ | `WatchCollectionScreen` | Saisie manuelle |
| `videogame` | Jeux vidéo | ✅ | `VideogameCollectionScreen` | RAWG + Steam |
| `movie` | Films (physique) | ✅ | `MovieCollectionScreen` | TMDB + iTunes |
| `car` | Voitures | ❌ (masquée) | — | Manuel |
| `stamp` | Timbres | ❌ (masquée) | — | Manuel |
| `coin` | Monnaies | ❌ (masquée) | — | Manuel |
| `custom` | Collection perso | ❌ (créée par l’utilisateur) | — | Manuel |

> Les catégories masquées (`hiddenFromMenu`) conservent leurs données en base ; elles restent accessibles via `HomeScreen` si des items existent.  
> La valeur legacy `manga` en base est mappée vers `book`.

### Champs communs à tous les objets (`CollectionItem`)

| Champ | Description |
|-------|-------------|
| `id`, `title`, `category`, `subcategory` | Identité |
| `imageUrl`, `metadata` (JSONB) | Visuel + données catalogue |
| `isWishlist` | Possédé vs souhaité |
| `quantity` | Duplicatas (badge ×N sur tuile) |
| `rating` (0–5), `review` | Avis personnel |
| `purchasePrice`, `condition` | Valeur et état (`ItemCondition`) |
| `locationId`, `locationLabel` | Où est l’objet |
| `groupId`, `groupName` | Collection de groupe |
| `addedBy`, `locationUserId` | Propriétaire / détenteur physique |
| `loanedToId`, `loanedToName`, `loanedAt` | Prêt en cours |
| `isForSale`, `isSold` | Inventaire vente |
| `tags` | Étiquettes utilisateur |
| `createdAt` | Date d’ajout |

### Champs spécifiques jeux de société (colonnes SQL)

| Champ | Description |
|-------|-------------|
| `minPlayers`, `maxPlayers`, `playingTime` | Fiche BGG |
| `gamesPlayed`, `personalRules` | Usage personnel |
| `isExpansion` | Extension BGG |
| `parentGameId` | Lien vers le jeu de base (UUID) |

---

## 3. Micro-fonctionnalités par catégorie

### 3.1 Jeux de société (`boardgame`)

#### Hub et découverte
- **`BoardgamesCollectionScreen`** : tuiles Popularité, Pour toi, Amis, 24 genres BGG, recherche
- **`BggCatalogGridScreen`** : grille catalogue avec sources `popular`, `forYou`, `friends`, `genre`, `search`
- **`BoardgameDiscoveryService`** : agrège BGG hot/search + catalogue curé (`boardgame_curated_catalog.dart`) + feed amis
- Pull-to-refresh, bouton shuffle (seed), pagination, masquage des jeux déjà possédés/wishlist
- Ajout rapide `+` / wishlist `♥` depuis la grille (`boardgame_bulk_add.dart`, `boardgame_quick_add.dart`)

#### Recherche et ajout BGG
- **`BggSearchDialog`** + **`BggService`**
- Préfetch des détails BGG avant dialogue d’ajout (image HD alignée collection)
- Champs metadata : `bgg_id`, `year_published`, `min_age`, `bgg_categories`, `bgg_is_expansion`, `base_game_bgg_id`, `base_game_title`

#### Extensions BGG (logique v2)
Gérée par **`BoardgameExpansionService`** avec colonnes `is_expansion` + `parent_game_id` :

| Scénario | Comportement |
|----------|--------------|
| **A — Base déjà possédée** | Extension ajoutée en enfant liée ; masquée de la liste globale ; visible cochée dans l’onglet Extensions du jeu de base |
| **B — Base absente** | Dialogue « Ajouter aussi le jeu de base ? » → Oui : crée base + lie extension ; Non : extension orpheline visible globalement avec mention « Extension de [base] » |
| **Orpheline** | Bannière + bouton « Ajouter le jeu de base » sur fiche détail → crée/lie base, redirige vers fiche base |
| **Réconciliation** | `reconcileBoardgameExpansions()` au premier ouverture « Mes jeux » — rattache legacy metadata → `parent_game_id` |
| **Masquage global** | `isBoardgameHiddenInGlobalCollection()` : extension avec `parent_game_id` OU legacy `owned_expansion_bgg_ids` sur la base |

Fichiers : `boardgame_expansion_flow.dart`, `boardgame_expansions_section.dart`, `boardgame_expansion_reconcile.dart`, `boardgame_collection_visibility.dart`, `boardgame_expansions.dart` (metadata legacy `owned_expansion_bgg_ids`).

#### Filtres et affichage collection
- Filtre **genres BGG** (24 catégories curées)
- Tri : titre, note, quantité, date, genre
- Scope : personnel / groupe / en prêt
- Badge vert **extensions** sur tuile (compte extensions possédées)
- **`ShakePickScreen`** : tirage aléatoire avec filtres joueurs/temps/genre
- Preview image long-press (`cover_preview_sheet.dart`, `boardgame_cover.dart`)

---

### 3.2 Livres (`book`)

#### Sous-catégories (`BookSubcategory`)
| Valeur | Label | Recherche Open Library |
|--------|-------|------------------------|
| `manga` | Manga | subject manga |
| `comic` | BD / Comics | subject comics |
| `novel` | Roman | fiction (hors comics/manga) |
| `other` | Autre | recherche libre |

#### Hub et navigation
- **`BooksCollectionScreen`** : hub par type + onglet wishlist (`BookWishlistTab`)
- **`BookSubcategorySeriesScreen`** : liste séries ou regroupement par auteur
- **`BookSeriesDetailScreen`** : checklist volumes (possédé / manquant / wishlist / lu)
- **`BookSeriesOverviewScreen`** : arbre séries / sous-séries
- **`BookAuthorDetailScreen`** : tous les livres d’un auteur
- **`NovelRatingMatrixScreen`** : grille notation type IMDB (saisons/chapitres)

#### Ajout et séries
- **`BookItemAddCoordinator`** : flux partagé ISBN scan, recherche, lien série, dialogue volume, wishlist
- **`SeriesAddCoordinator`** : création série depuis recherche Open Library
- **`BookSeriesService`** : CRUD `book_series` / `book_volumes`
- APIs : **`OpenLibraryService`**, **`GoogleBooksService`**, façade **`BookCatalogService`**
- Scan ISBN (`mobile_scanner`)
- Statut **`isRead`** (Lu / Non lu) sur volumes et items
- Metadata : `author`, `year`, `isbn`, `series_title`, `series_volume`, `google_books_id`

---

### 3.3 Cartes à collectionner (`card`)

#### Sous-catégories (`CardSubcategory`)
| Valeur | Label | Navigateur sets | API |
|--------|-------|-----------------|-----|
| `pokemon` | Pokémon | ✅ blocs FR/EN/JA | TCGdex |
| `magic` | Magic | ✅ blocs Scryfall | Scryfall |
| `yugioh` | Yu-Gi-Oh! | ✅ ères YGOProDeck | YGOProDeck |
| `onepiece` | One Piece | ✅ boosters OPTCG | OPTCG API |
| `lorcana` | Lorcana | ✅ chapitres Lorcast | Lorcast |
| `topps` | Topps | ❌ manuel | — |
| `panini` | Panini | ❌ manuel | — |
| `other` | Autre | ❌ manuel | — |

#### Écrans TCG
- **`CardsCollectionScreen`** : hub univers
- **`PokemonSeriesBlocksScreen`** : blocs Pokémon par langue (`PokemonCardLang`: FR, EN, JA)
- **`TcgSeriesBlocksScreen`** : blocs génériques (Magic, YGO, etc.)
- **`TcgSetsBlockScreen`** : sets d’un bloc (logos, codes)
- **`TcgSetCardsScreen`** : toutes les cartes d’un set + badges possédé + ajout bulk
- **`TcgGlobalSearchScreen`** : recherche cross-set
- **`TcgRarityGalleryScreen`** : galerie par rareté

#### Metadata cartes
- IDs catalogue par TCG, `set_name`, `block_name`, `card_number`, `rarity`, `card_lang`
- **`CardCondition`** (mint → poor), **`GradingCompany`** (PSA, PCA, BGS)
- Filtres collection : sous-catégorie, rareté, type Pokémon
- **`UserCardCollectionService`** : clés possédées/wishlist par univers
- Images web : chargement direct TCGdex/YGO quand possible (`web_image_proxy.dart`)

---

### 3.4 Vinyles / CD (`media`)

#### Formats (`MediaFormat`)
- `vinyl`, `cd`, `cassette`

#### Fonctionnalités
- **`MediaCollectionScreen`** : hub par format
- **`MediaArtistAlbumsScreen`** : albums regroupés par artiste
- Recherche **`MediaSearchDialog`** + scan code-barres
- APIs : **`DiscogsService`** (token) → fallback **`MusicBrainzService`**
- Metadata : `format`, `artist`, `disc_color`, `limited_edition`, `pressing`, `barcode`
- Formulaire metadata (`CategoryMetadataFields`)

---

### 3.5 Lego & maquettes (`lego`)

#### Types (`LegoBuildKind`)
- `lego`, `maquette`

#### Fonctionnalités
- **`LegoCollectionScreen`** : hub Lego vs maquette
- Recherche catalogue **`CatalogSearchSheet`**
- APIs : **`RebrickableService`** (clé) → fallback **`LegoFandomService`** (wiki gratuit)
- Metadata : `lego_kind`, `set_number`, `piece_count`, `is_built`, `box_included`, `rebrickable_id`
- Filtre hub par `fixedLegoKind` dans `HomeScreen`

---

### 3.6 Montres (`watch`)

- **`WatchCollectionScreen`** : hub + **`WatchQuickSearchSheet`** (saisie manuelle)
- Metadata : `brand`, `model`, `reference`, `year`
- Pas d’API externe

---

### 3.7 Jeux vidéo (`videogame`)

- **`VideogameCollectionScreen`** : hub + recherche catalogue
- APIs : **`RawgService`** (clé) → fallback **`SteamStoreService`**
- Metadata : `platform`, `year`, `rawg_id`

---

### 3.8 Films physiques (`movie`)

- **`MovieCollectionScreen`** : hub Blu-ray/DVD/coffrets
- APIs : **`TmdbService`** (clé) → fallback **`ItunesMovieService`**
- Metadata : `media_kind`, `year`, `director`, `tmdb_id`, `itunes_id`, `physical_format`

---

### 3.9 Catégories masquées (car, stamp, coin)

- Accès via `HomeScreen` uniquement (données legacy conservées)
- Formulaire metadata dédié (`usesMetadataForm = true`)
- **Voitures** : `mileage_km`, `maintenance_history`, `logbook`
- **Timbres / Monnaies** : `country`, `mint`, `rarity_tirage`

---

### 3.10 Collections personnalisées (`custom`)

- Création via **`CreateCustomCollectionDialog`**
- Table `user_collection_types` : `name`, `icon_key`, `color_hex`
- Items : `category = 'custom'`, `subcategory = user_collection_types.id`
- Metadata : `custom_type_name`

---

### 3.11 Fonctions communes à toutes les collections (`HomeScreen`)

| Fonctionnalité | Détail |
|----------------|--------|
| **Vue grille / liste** | `CollectionViewMode` — toggle persistant |
| **Filtres** | `CollectionFilterBar` + `CollectionListFilters` |
| **Recherche** | Par titre |
| **Tri** | Titre A-Z/Z-A, note, quantité, date, genre BGG |
| **Scope** | Tout / personnel / groupe / en prêt |
| **Statut** | Bien noté (≥4), avec emplacement |
| **Tags** | Filtre par étiquette utilisateur |
| **Emplacement** | Filtre par `locations` |
| **Holder** | Filtre « chez qui » (`user:`, `custom:`, `loan:`) |
| **Wishlist** | Onglet séparé dans chaque hub |
| **Pull-to-refresh** | Recharge depuis Supabase + `CollectionRefresh` |
| **Groupement duplicatas** | `CollectionGridGrouper` — badge ×N |
| **Preview couverture** | Long-press sur image |
| **Ajout** | Manuel, catalogue, scan (selon catégorie) |

---

## 4. Fonctionnalités globales et transverses

### 4.1 Authentification

- **Supabase Auth** email/mot de passe (`AuthService`)
- **`LoginScreen`** : inscription, connexion, reset password
- **`SplashScreen`** : animation pixel art + audio ; routage auth
- Auto-création profil (`handle_new_user` trigger + `ProfileService.ensureCurrentUserProfile`)
- Dev : `DEV_TEST_EMAIL`, `DEV_TEST_PASSWORD`, `DEV_SKIP_SPLASH`, `DEV_FAST_START`

### 4.2 Profil utilisateur

- **`ProfileEditScreen`** : avatar (upload storage), bio (280 car.), couleur accent
- **Trophées** : jusqu’à 6 objets favoris (`favorite_item_ids`) — arbre visuel `TrophyTree`
- **Showcase public** : lien tokenisé (`showcase_token`, `showcase_public`) → `web/showcase.html`
- **`ShowcaseService`** + RPC `get_public_showcase(token)`

### 4.3 Paramètres et thème

- **`SettingsScreen`** + **`SettingsService`** (SharedPreferences + sync Supabase)
- **Mode sombre** : `AppTheme.light` / `AppTheme.dark` (Material 3, Plus Jakarta Sans, seed violet `#5E35B1`)
- **`CategoryHubTheme`** : accents par catégorie
- **Notifications** : préférences locales
- **Confidentialité** (sync profil Supabase) :
  - `hide_collection_from_non_friends`
  - `hide_collection_from_friends`
  - `share_wishlist`

### 4.4 Amis

- **`FriendsScreen`** : liste, demandes en attente, recherche profils
- **`FriendService`** : demandes `pending` → `accepted`, blocage, `share_collections`
- **`FriendCollectionScreen`** : lecture seule collection/wishlist ami
- **`copy_friend_item.dart`** : copier un objet chez soi
- **`friend_item_overlap.dart`** : badges « Toi » / « ♥ » sur catalogues
- **`FriendsActivityFeed`** : flux intégré à l’écran amis

### 4.5 Groupes

- **`GroupsScreen`** / **`GroupEditScreen`** / **`GroupDetailScreen`**
- **`GroupService`** : création, invitation amis, photo groupe (storage `group-avatars`)
- Icônes preset (`GroupIcon`) : family, home, pets, etc.
- Items partagés : `group_id` sur `collection_items`
- Emplacements de groupe (`locations.group_id`)
- Filtres ownership : personnel vs groupes

### 4.6 Prêts

- **`LoanService`** + **`LoanItemDialog`**
- Prêt à un ami (profil) ou nom libre
- **`LoansScreen`** : registre des prêts actifs
- Filtre `onLoanOnly` dans collection
- Badge « Prêté » sur tuiles

### 4.7 Wishlist

- Flag `is_wishlist` sur chaque item
- **`WishlistOverviewScreen`** : vue globale par catégorie
- **`wishlist_promote.dart`** : convertir wishlist → possédé
- **`WishlistSuggestionService`** : suggestions jeux BGG basées sur amis
- Badge compteur sur tuiles hub catégories
- **`BookWishlistTab`** : wishlist livres dans hub livres

### 4.8 Flux d’activité

- Table **`activity_events`** : `item_added`, `wishlist_added`, `item_rated`, `trophies_updated`
- Trigger auto sur INSERT / UPDATE rating de `collection_items`
- **`ActivityService.fetchFriendsFeed`**
- **`activity_feed_grouper.dart`** : regroupe ajouts consécutifs
- **`FriendsActivityFeed`** widget

### 4.9 Tags et emplacements

- **`TagService`** : CRUD `item_tags` + liaison `collection_item_tags`
- **`ItemTagsEditor`** sur fiche détail
- **`LocationService`** : emplacements personnels ou de groupe
- **`ItemWhereaboutsField`** / **`PersonalWhereaboutsField`**

### 4.10 Inventaire et disposition

- **`InventoryManageScreen`** : duplicatas, à vendre, vendus
- Flags `isForSale`, `isSold` (mutuellement exclusifs en base)
- Tuiles grisées + badge « Vendu » / « Vente »

### 4.11 Statistiques et partage

- **`StatsScreen`** : totaux, valeur achat, top notes, wishlist par catégorie
- **`CollectionStatsService`**
- **`CollectionShareService`** : résumé texte/HTML
- **`CollectionExportService`** : export clipboard / fichier / share sheet
- **`ShareCollectionSheet`**

### 4.12 Shake Pick (tirage aléatoire)

- **`ShakePickScreen`** : capteur (`sensors_plus`) ou bouton
- Filtres joueurs, durée, genre (boardgames)
- **`shake_pick_filters.dart`**

### 4.13 Images et médias

- **`CollectionCoverImage`** / **`BggNetworkImage`** : rendu net (boxed, book, large)
- **`web_image_proxy.dart`** : proxy Supabase `image-proxy` sur web ; direct load quand CORS OK
- **`cover_preview_sheet.dart`** : preview HD long-press
- **`boardgame_cover.dart`** : URL stockage image BGG haute qualité
- Allowlist proxy : BGG, Open Library, TCGdex, Pokémon, YGO, Discogs, TMDB, RAWG, Steam, Rebrickable, Google Books…

### 4.14 Refresh collection

- **`CollectionRefresh`** : `ChangeNotifier` global — bump après toute mutation
- Écoute dans `HomeScreen` → reload DB
- Pull-to-refresh sur grilles

### 4.15 Phase 2 — Abstraction catalogue (en cours)

| Fichier | Rôle |
|---------|------|
| `catalog/models/catalog_entry.dart` | Interface entrée catalogue générique |
| `catalog/services/user_catalog_service.dart` | Interface owned/wishlist par clé catalogue |
| `catalog/catalog_owned_state.dart` | État partagé grilles catalogue |
| `BggCatalogGame implements CatalogEntry` | Premier adaptateur |
| `UserBoardgameCollectionService implements UserCatalogService` | Premier service adapté |

---

## 5. Infrastructure Supabase

**Projet lié** : `jfudrneoblsiingjqsio`  
**Note** : pas de dossier `supabase/migrations/` — schémas appliqués manuellement via scripts SQL Editor.

### 5.1 Tables principales

#### `profiles`
| Colonne | Description |
|---------|-------------|
| `id` | PK, FK → `auth.users` |
| `username` | Nom affiché |
| `avatar_url`, `accent_color`, `bio` | Profil |
| `share_wishlist` | Partage wishlist aux amis |
| `hide_collection_from_non_friends` | Confidentialité |
| `hide_collection_from_friends` | Confidentialité |
| `showcase_public`, `showcase_token` | Vitrine publique |
| `favorite_item_ids` | Trophées (max 6) |

#### `collection_items`
Voir section 2 + colonnes ajoutées par migrations :
- Personnelles : `rating`, `review`, `purchase_price`, `condition`, `games_played`, `personal_rules`, `metadata`, `subcategory`
- Sociales : `quantity`, `location_id`, `group_id`, `added_by`, `created_at`
- Prêts : `loaned_to_id`, `loaned_to_name`, `loaned_at`
- Disposition : `is_for_sale`, `is_sold`
- Livres : `series_id`, `volume_id`, `is_read`
- Boardgames : `is_expansion`, `parent_game_id` *(schema_boardgame_parent.sql)*

#### `locations`
Emplacements physiques (personnel ou groupe).

#### `groups` / `group_members`
Collections partagées entre amis.

#### `friendships`
`requester_id`, `addressee_id`, `status` (pending/accepted/blocked), `share_collections`.

#### `item_tags` / `collection_item_tags`
Étiquettes utilisateur et liaisons.

#### `book_series` / `book_volumes`
Séries livres, volumes, sous-séries (`parent_series_id`), notation série.

#### `activity_events`
Flux d’activité social.

#### `user_collection_types`
Types de collections personnalisées.

### 5.2 Storage buckets

| Bucket | Usage |
|--------|-------|
| `avatars` | Photos profil `{user_id}/` |
| `group-avatars` | Photos groupe `{group_id}/` |

### 5.3 Fonctions SQL

| Fonction | Rôle |
|----------|------|
| `handle_new_user()` | Crée profil à l’inscription |
| `is_group_member()` | SECURITY DEFINER — évite récursion RLS |
| `get_public_showcase(token)` | Vitrine publique anon |
| `log_collection_item_activity()` | Trigger activité |
| `set_book_series_updated_at()` | MAJ timestamp séries |

### 5.4 RLS (Row Level Security)

Politiques principales (post `schema_rls_fix_live.sql`) :

- **`collection_items`** : SELECT own + groupe + amis (si `share_collections` et pas caché) ; INSERT/UPDATE/DELETE own ou membre groupe
- **`friendships`** : CRUD limité aux parties
- **`groups` / `group_members`** : membre ou créateur
- **`book_series` / `book_volumes`** : owner only
- **`activity_events`** : own + amis acceptés
- Validation : `schema_rls_validate.sql`

### 5.5 Scripts SQL (ordre recommandé)

1. Base `profiles` + `collection_items` *(hors repo)*
2. `schema_profiles.sql` → `schema_profiles_backfill.sql`
3. `schema_social.sql` → `schema_personal_columns.sql` → `schema_tags_dates.sql`
4. `schema_collection_items_rls.sql`
5. `schema_friend_requests.sql` → **`schema_rls_fix_live.sql`** *(critique prod)*
6. `schema_rls_group_members_fix.sql`
7. `schema_profiles_share_wishlist.sql` → `schema_showcase.sql`
8. `schema_book_series.sql` → `schema_loans.sql` → `schema_item_disposition.sql`
9. `schema_groups_custom.sql` → `schema_profile_trophies.sql`
10. `schema_activity_feed.sql` → **`schema_boardgame_parent.sql`**
11. `schema_user_collection_types.sql` → `schema_collection_item_subcategory.sql`

### 5.6 Edge Functions

| Function | JWT | Secret | Rôle |
|----------|-----|--------|------|
| **`bgg-api`** | `--no-verify-jwt` | `BGG_APPLICATION_TOKEN` | API JSON BGG pour Flutter Web (search, hot, meta, game, expansions) |
| **`bgg-proxy`** | `--no-verify-jwt` | `BGG_APPLICATION_TOKEN` | Proxy XML brut BGG (native / fallback) |
| **`image-proxy`** | `--no-verify-jwt` | — | Proxy images externes (CORS web) |

---

## 6. APIs et catalogues externes

### 6.1 Tableau récapitulatif

| API | Catégorie | Clé `.env` | Fallback | Service Flutter |
|-----|-----------|------------|----------|-----------------|
| **BoardGameGeek** | Boardgames | `BGG_APPLICATION_TOKEN` | Edge proxy | `BggService` |
| **Open Library** | Livres | — (gratuit) | — | `OpenLibraryService` |
| **Google Books** | Livres | `GOOGLE_BOOKS_API_KEY` | Open Library | `GoogleBooksService` |
| **TCGdex** | Pokémon | — (gratuit) | — | `PokemonTcgService` |
| **Scryfall** | Magic | — (gratuit) | — | `ScryfallService` |
| **YGOProDeck** | Yu-Gi-Oh! | — (gratuit) | — | `YgoprodeckService` |
| **OPTCG API** | One Piece | — (gratuit) | — | `OnepieceTcgService` |
| **Lorcast** | Lorcana | — (gratuit) | — | `LorcastService` |
| **Discogs** | Vinyles/CD | `DISCOGS_TOKEN` | MusicBrainz | `DiscogsService` |
| **MusicBrainz** | Vinyles/CD | — (gratuit) | — | `MusicbrainzService` |
| **Rebrickable** | Lego | `REBRICKABLE_API_KEY` | Lego Fandom wiki | `RebrickableService` |
| **Lego Fandom** | Lego | — (gratuit) | — | `LegoFandomService` |
| **TMDB** | Films | `TMDB_API_KEY` | iTunes Search | `TmdbService` |
| **iTunes Search** | Films | — (gratuit) | — | `ItunesMovieService` |
| **RAWG** | Jeux vidéo | `RAWG_API_KEY` | Steam store | `RawgService` |
| **Steam Store** | Jeux vidéo | — (gratuit) | — | `SteamStoreService` |

### 6.2 Façades catalogue

| Service | Route vers |
|---------|------------|
| `BookCatalogService` | Open Library → Google Books |
| `CardCatalogService` | Service TCG selon sous-catégorie |
| `MediaCatalogService` | Discogs → MusicBrainz |
| `LegoCatalogService` | Rebrickable → Fandom |
| `MovieCatalogService` | TMDB → iTunes |
| `VideogameCatalogService` | RAWG → Steam |
| `BoardgameDiscoveryService` | BGG + curé + feed amis |

### 6.3 URLs et endpoints notables

- BGG XML : `boardgamegeek.com/xmlapi2`
- TCGdex : `api.tcgdex.net/v2`, assets `assets.tcgdex.net`
- Scryfall : `api.scryfall.com`
- YGOProDeck : `db.ygoprodeck.com/api/v7`
- OPTCG : `www.optcgapi.com`
- Lorcast : `api.lorcast.com/v0`
- Discogs : `api.discogs.com`
- MusicBrainz : `musicbrainz.org` + Cover Art Archive
- Rebrickable : `rebrickable.com/api/v3`
- Lego Fandom : `lego.fandom.com/api.php`
- TMDB : `api.themoviedb.org/3`
- RAWG : `api.rawg.io`
- Steam : `store.steampowered.com/api/storesearch`

---

## 7. Architecture Flutter

### 7.1 Écrans (39 fichiers)

#### App shell
- `splash_screen.dart`, `login_screen.dart`, `category_selection_screen.dart`
- `settings_screen.dart`, `profile_edit_screen.dart`, `stats_screen.dart`
- `inventory_manage_screen.dart`, `item_detail_screen.dart`, `home_screen.dart`

#### Social
- `friends_screen.dart`, `friend_collection_screen.dart`
- `groups_screen.dart`, `group_detail_screen.dart`, `group_edit_screen.dart`
- `loans_screen.dart`, `wishlist_overview_screen.dart`, `shake_pick_screen.dart`

#### Boardgames
- `boardgame/boardgames_collection_screen.dart`
- `boardgame/bgg_catalog_grid_screen.dart`

#### Books
- `books_collection_screen.dart`, `book_subcategory_series_screen.dart`
- `book_series_detail_screen.dart`, `book_series_overview_screen.dart`
- `book_author_detail_screen.dart`, `book_wishlist_tab.dart`
- `novel_rating_matrix_screen.dart`

#### Cards / TCG
- `cards_collection_screen.dart`
- `tcg/pokemon_series_blocks_screen.dart`, `tcg/tcg_series_blocks_screen.dart`
- `tcg/tcg_sets_block_screen.dart`, `tcg/tcg_set_cards_screen.dart`
- `tcg/tcg_global_search_screen.dart`, `tcg/tcg_rarity_gallery_screen.dart`

#### Autres catégories
- `media_collection_screen.dart`, `media_artist_albums_screen.dart`
- `lego_collection_screen.dart`, `watch_collection_screen.dart`
- `videogame_collection_screen.dart`, `movie_collection_screen.dart`

### 7.2 Services (45 fichiers)

#### Supabase / backend
`auth_service`, `profile_service`, `settings_service`, `friend_service`, `group_service`, `loan_service`, `activity_service`, `tag_service`, `location_service`, `collection_stats_service`, `collection_share_service`, `collection_export_service`, `showcase_service`, `inventory_service`, `user_collection_type_service`, `book_series_service`, `wishlist_suggestion_service`, `friend_boardgame_feed_service`, `user_boardgame_collection_service`, `user_card_collection_service`, `boardgame_expansion_service`, `collection_refresh`

#### APIs externes
`bgg_service`, `boardgame_discovery_service`, `open_library_service`, `google_books_service`, `book_catalog_service`, `pokemon_tcg_service`, `scryfall_service`, `ygoprodeck_service`, `onepiece_tcg_service`, `lorcast_service`, `card_catalog_service`, `discogs_service`, `musicbrainz_service`, `media_catalog_service`, `rebrickable_service`, `lego_fandom_service`, `lego_catalog_service`, `tmdb_service`, `itunes_movie_service`, `movie_catalog_service`, `rawg_service`, `steam_store_service`, `videogame_catalog_service`

### 7.3 Modèles (28 fichiers)

`collection_category`, `collection_item`, `category_metadata`, `collection_list_filters`, `card_subcategory`, `book_subcategory`, `book_series`, `book_volume`, `book_author_group`, `novel_rating_matrix`, `series_search_hit`, `bgg_catalog_game`, `bgg_expansion`, `tcg_set_info`, `pokemon_card_lang`, `lego_build_kind`, `media_format_ui`, `user_collection_type`, `user_profile`, `collection_group`, `group_icon`, `activity_event`, `collection_summary`, `category_stat`, `collection_view_mode`, `item_tag`, `storage_location`, `item_condition`

### 7.4 Widgets notables (68 fichiers)

| Widget | Rôle |
|--------|------|
| `main_drawer.dart` | Navigation latérale |
| `category_type_hub.dart` | Shell hub réutilisable (tabs) |
| `category_collection_shell.dart` | Scaffold collection + FAB |
| `collection_filter_bar.dart` | Filtres et tri |
| `collection_item_tile.dart` / `collection_item_list_tile.dart` | Tuiles grille/liste |
| `catalog/catalog_item_tile.dart` | Tuile catalogue générique (+ / ♥) |
| `add_item_options_dialog.dart` / `add_item_manual_dialog.dart` | Ajout |
| `bgg_search_dialog.dart` / `book_search_dialog.dart` / `card_search_dialog.dart` / `media_search_dialog.dart` | Recherche catalogue |
| `catalog_search_sheet.dart` | Bottom sheet (lego, jeux, films) |
| `boardgame_expansions_section.dart` | Extensions sur fiche jeu |
| `friends_activity_feed.dart` | Flux social |
| `wishlist_suggestions_banner.dart` | Suggestions BGG |
| `loan_item_dialog.dart` | Prêt |
| `create_custom_collection_dialog.dart` | Collection perso |
| `collapsible_collection_overview.dart` | Résumé hub |
| `share_collection_sheet.dart` | Export/partage |
| `profile/trophy_tree.dart` | Trophées profil |
| `category_metadata_fields.dart` | Formulaires metadata |
| `cover_preview_sheet.dart` | Preview HD |

### 7.5 Utils (46+ fichiers)

Boardgame : `boardgame_quick_add`, `boardgame_bulk_add`, `boardgame_expansion_flow`, `boardgame_expansions`, `boardgame_genres`, `boardgame_display`, `boardgame_cover`, `boardgame_collection_visibility`, `boardgame_expansion_reconcile`

TCG : `card_quick_add`, `tcg_bulk_add`, `tcg_card_display`, `tcg_rarity_order`, `navigate_to_card_set`, `onepiece_card_utils`, `tcgdex_assets`, `tcg_set_image_url`, `tcg_premium_rarities`

Books : `book_add_actions`, `book_title_parser`, `book_volume_cover`

Core : `collection_item_scope`, `collection_grid_grouper`, `collection_grid_layout`, `collection_item_filters`, `category_hub_order`, `catalog_hit_metadata`, `catalog_http`, `cover_image_url`, `web_image_proxy`

Social : `copy_friend_item`, `friend_item_overlap`, `activity_feed_grouper`, `wishlist_promote`

UX : `app_haptics`, `debounced_runner`, `dialog_layout`, `shake_pick_filters`, `french_plural`, `splash_audio`, `search_relevance`

### 7.6 Coordinators

- `book_item_add_coordinator.dart` — flux ajout livre unifié
- `series_add_coordinator.dart` — création série Open Library

### 7.7 Data statique

- `data/boardgame_curated_catalog.dart` — IDs BGG curés par genre (24 genres), top global

### 7.8 Thème

- `theme/app_theme.dart` — Material 3 light/dark
- `theme/category_hub_theme.dart` — accents par hub

### 7.9 Config

- `config/app_env.dart` — variables `.env` + fallback web
- `config/supabase_public_config.dart` — URL/clé anon hardcodées web
- `config/dev_auth_config.dart` — raccourcis dev

### 7.10 Web

- `web/index.html` — point d’entrée Flutter web
- `web/manifest.json` — PWA
- `web/showcase.html` — vitrine publique profil

### 7.11 Dépendances principales (`pubspec.yaml`)

`supabase_flutter`, `http`, `xml`, `flutter_dotenv`, `google_fonts`, `cached_network_image`, `image_picker`, `mobile_scanner`, `sensors_plus`, `share_plus`, `path_provider`, `file_selector`, `url_launcher`, `audioplayers`, `flutter_animate`, `flutter_svg`

---

## 8. Déploiement et configuration

### 8.1 GitHub Pages

- Workflow : `.github/workflows/deploy.yml`
- Trigger : push `main` ou `workflow_dispatch`
- Build : `flutter build web --release --base-href "/CollectionApp/"`
- Publish : branche `gh-pages` via `peaceiris/actions-gh-pages@v4`
- CI env : `scripts/write_ci_env.sh` génère `.env` depuis secrets GitHub

### 8.2 Variables d’environnement

| Variable | Obligatoire | Usage |
|----------|-------------|-------|
| `SUPABASE_URL` | ✅ | Backend |
| `SUPABASE_ANON_KEY` | ✅ | Backend |
| `BGG_APPLICATION_TOKEN` | Recommandé | BGG + edge functions |
| `GOOGLE_BOOKS_API_KEY` | Optionnel | Livres ISBN |
| `DISCOGS_TOKEN` | Optionnel | Vinyles |
| `TMDB_API_KEY` | Optionnel | Films |
| `RAWG_API_KEY` | Optionnel | Jeux vidéo |
| `REBRICKABLE_API_KEY` | Optionnel | Lego |
| `DEV_*` | Dev only | Tests locaux |

### 8.3 Edge functions (déploiement manuel)

```bash
supabase functions deploy bgg-api --no-verify-jwt
supabase functions deploy bgg-proxy --no-verify-jwt
supabase functions deploy image-proxy --no-verify-jwt
```

Secret Supabase : `BGG_APPLICATION_TOKEN`

### 8.4 Lancement local

- `.vscode/launch.json` : profils splash normal / dev rapide
- Scripts : `scripts/run-dev-fast.ps1`, `scripts/run-with-splash.ps1`

---

## 9. Annexes — fichiers clés

### Par domaine fonctionnel

| Domaine | Fichiers principaux |
|---------|---------------------|
| Collection core | `home_screen.dart`, `collection_item.dart`, `collection_list_filters.dart`, `collection_refresh.dart` |
| Boardgames | `bgg_service.dart`, `boardgame_expansion_service.dart`, `boardgames_collection_screen.dart`, `bgg_catalog_grid_screen.dart` |
| Livres | `book_series_service.dart`, `book_item_add_coordinator.dart`, `books_collection_screen.dart` |
| Cartes | `card_catalog_service.dart`, `tcg_set_cards_screen.dart`, `user_card_collection_service.dart` |
| Social | `friend_service.dart`, `group_service.dart`, `activity_service.dart`, `friends_screen.dart` |
| Auth/Profil | `auth_service.dart`, `profile_service.dart`, `settings_service.dart` |
| Images web | `web_image_proxy.dart`, `collection_cover_image.dart`, `supabase/functions/image-proxy/` |
| Supabase SQL | `supabase/schema_*.sql`, `supabase/README.md` |

### Structure dossiers `lib/`

```
lib/
├── catalog/          # Abstraction catalogue Phase 2
├── config/           # Env, dev, Supabase public
├── coordinators/     # Flux ajout livres/séries
├── data/             # Catalogues curés statiques
├── models/           # Domain models (28)
├── screens/          # UI (39 écrans)
├── services/         # Backend + APIs (45)
├── theme/            # AppTheme, hub themes
├── utils/            # Helpers (46+)
└── widgets/          # Composants réutilisables (68)
```

---

*Dernière mise à jour : juin 2026 — reflète l’état du dépôt incluant extensions BGG v2 (`is_expansion` / `parent_game_id`), fix images collection, et début Phase 2 catalogue.*
