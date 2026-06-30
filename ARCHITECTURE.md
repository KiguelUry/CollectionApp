# Collectingo — Cartographie architecturale

> **Audit technique** — lecture seule, généré le 2 juin 2026.  
> Application Flutter multi-collections (jeux de société, livres, TCG, médias, nature, restaurants…) avec backend **Supabase** (PostgreSQL + Auth + Storage + Edge Functions) et catalogues externes (BGG, Open Library, Discogs, iNaturalist, etc.).

---

## Table des matières

1. [Vue d'ensemble](#1-vue-densemble)
2. [Stack et infrastructure](#2-stack-et-infrastructure)
3. [Arborescence et inventaire des fichiers](#3-arborescence-et-inventaire-des-fichiers)
4. [Diagrammes de flux de données (UML textuel)](#4-diagrammes-de-flux-de-données-uml-textuel)
5. [Chasse au code mort](#5-chasse-au-code-mort)
6. [Audit performance et scaling](#6-audit-performance-et-scaling)
7. [Schéma Supabase (référence)](#7-schéma-supabase-référence)
8. [Roadmap produit — idées et priorisation](#8-roadmap-produit--idées-et-priorisation)

---

## 1. Vue d'ensemble

### 1.1 Pattern architectural

```
┌─────────────────────────────────────────────────────────────────┐
│                        PRESENTATION                              │
│  screens/  widgets/  theme/                                      │
│  StatefulWidget + setState ; peu de state management global      │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                     ORCHESTRATION                                │
│  coordinators/  utils/*_quick_add.dart  utils/*_bridge.dart      │
└────────────────────────────┬────────────────────────────────────┘
                             │
┌────────────────────────────▼────────────────────────────────────┐
│                      DOMAIN / MODELS                             │
│  models/  catalog/models/                                        │
└────────────────────────────┬────────────────────────────────────┘
                             │
         ┌───────────────────┼───────────────────┐
         ▼                   ▼                   ▼
┌─────────────┐    ┌─────────────────┐   ┌──────────────────┐
│  services/  │    │ SharedPreferences│   │  APIs externes   │
│  Supabase   │    │ (cache local)    │   │  BGG, Discogs…   │
└─────────────┘    └─────────────────┘   └──────────────────┘
```

**Pas de couche Repository unifiée** : les appels PostgREST sont distribués entre `services/`, `screens/` et `utils/`. La cohérence repose sur des utilitaires partagés (`whereabouts_persistence`, `wishlist_promote`, `supabase_embeds`).

### 1.2 Entité centrale

`CollectionItem` (`lib/models/collection_item.dart`) est le pivot de toutes les catégories. Une seule table Supabase `collection_items` avec colonnes typées + blob JSON `metadata` pour les données spécifiques au domaine.

### 1.3 Points d'entrée navigation

| Route / écran | Rôle |
|---------------|------|
| `SplashScreen` | Auth gate → `/categories` ou login |
| `/categories` | `CategorySelectionScreen` — hub des catégories |
| `HomeScreen(category)` | Grille/liste collection + wishlist par catégorie |
| `ItemDetailScreen` | Fiche objet complète |
| `/groups`, `/friends`, `/profile`, `/settings` | Social et compte |

---

## 2. Stack et infrastructure

| Couche | Technologie |
|--------|-------------|
| UI | Flutter 3.x, Material 3, `google_fonts` |
| Backend | Supabase (`supabase_flutter`) — Auth, PostgREST, Realtime, Storage |
| Cache local | **SharedPreferences uniquement** (pas de SQLite/Hive/Isar) |
| Images | `cached_network_image`, proxy web CORS (`web_image_proxy`) |
| i18n | `intl` — locale fixe `fr_FR` |
| Config | `.env` (`flutter_dotenv`) + `SupabasePublicConfig` (web CI) |
| Déploiement | GitHub Actions (Pages), `vercel.json` (web) |
| Edge Functions | `bgg-api`, `bgg-proxy`, `image-proxy`, `riftscribe-proxy` |

### 2.1 Dépendances `pubspec.yaml` — usage

| Package | Utilisé ? | Fichiers principaux |
|---------|-----------|---------------------|
| `supabase_flutter` | Oui | Tous les services, `main.dart` |
| `http` | Oui | 18+ services catalogues |
| `xml` | Oui | `bgg_service.dart` |
| `shared_preferences` | Oui | Settings, holder history, orphans plays |
| `cached_network_image` | Oui | `collection_cover_image.dart`, `tcg_set_logo.dart` |
| `google_fonts` | Oui | `app_theme.dart`, détail expansions |
| `audioplayers` | Oui | `splash_audio.dart` |
| `image` / `image_picker` | Oui | Avatar, compression, wildlife |
| `flutter_map` / `latlong2` / `geolocator` | Oui | Cartes wildlife/restaurant |
| `mobile_scanner` | Oui | `isbn_scan_sheet.dart` |
| `sensors_plus` | Oui | `shake_pick_screen.dart` |
| `share_plus` / `path_provider` / `file_selector` | Oui | Export collection |
| `flutter_animate` | Oui | `wildlife_collection_screen.dart` |
| `flutter_svg` | Oui | `tcg_set_logo.dart` |
| `flutter_markdown` | **Mort** | Uniquement `markdown_rules_editor.dart` (non importé) |
| `cupertino_icons` | **Non importé** | Déclaré mais aucun `CupertinoIcons` dans `lib/` |
| `flutter_localizations` | Oui | `main.dart` |

---

## 3. Arborescence et inventaire des fichiers

**337 fichiers Dart** sous `lib/`. Format : `Fichier` — rôle — appelé par / appelle.

Légende dépendances : **↑** appelants typiques, **↓** dépendances principales.

---

### 3.1 Racine

| Fichier | Rôle | Dépendances |
|---------|------|-------------|
| `main.dart` | Bootstrap : dotenv, Settings, Supabase, `MaterialApp` routes | ↓ `AppEnv`, `SettingsService`, `SplashScreen` |

---

### 3.2 `lib/config/` (3)

| Fichier | Rôle | Dépendances |
|---------|------|-------------|
| `app_env.dart` | Lit URL/clé Supabase depuis `.env` | ↑ `main.dart`, `BggService` |
| `supabase_public_config.dart` | Clés publiques hardcodées (web/GitHub Pages) | ↑ `AppEnv` |
| `dev_auth_config.dart` | Identifiants debug auto-login | ↑ `SplashScreen` |

---

### 3.3 `lib/constants/` (1)

| Fichier | Rôle | Dépendances |
|---------|------|-------------|
| `book_accent.dart` | Couleurs accent module livres | ↑ écrans/widgets livres |

---

### 3.4 `lib/data/` (1)

| Fichier | Rôle | Dépendances |
|---------|------|-------------|
| `boardgame_curated_catalog.dart` | IDs BGG statiques par genre (discovery) | ↑ `BoardgameDiscoveryService` |

---

### 3.5 `lib/navigation/` (1)

| Fichier | Rôle | Dépendances |
|---------|------|-------------|
| `app_navigation.dart` | Reset navigation vers `/categories` | ↑ `CategorySelectionScreen` |

---

### 3.6 `lib/catalog/` (3)

| Fichier | Rôle | Dépendances |
|---------|------|-------------|
| `catalog_owned_state.dart` | **MORT** — état owned/wishlist en mémoire pour grilles catalogue | — |
| `models/catalog_entry.dart` | Interface `CatalogEntry` (clé, titre, image) | ↑ `BggCatalogGame`, hits catalogue |
| `services/user_catalog_service.dart` | Abstraction service clés owned/wishlist | ↑ `UserBoardgameCollectionService` |

---

### 3.7 `lib/coordinators/` (2)

| Fichier | Rôle | Dépendances |
|---------|------|-------------|
| `book_item_add_coordinator.dart` | Orchestration ajout livre (ISBN, recherche, série, manuel) | ↓ book services/widgets ; ↑ hubs livres |
| `series_add_coordinator.dart` | Recherche Open Library → création série locale | ↓ `BookSeriesService`, `SeriesSearchDialog` |

---

### 3.8 `lib/theme/` (4)

| Fichier | Rôle | Dépendances |
|---------|------|-------------|
| `app_theme.dart` | Thèmes clair/sombre Material 3 | ↑ `main.dart` |
| `category_accent_theme.dart` | Dégradés header par catégorie | ↑ `CategoryCollectionHeader` |
| `category_hub_theme.dart` | Identité visuelle hubs (films, jeux, Lego) | ↑ `CategoryTypeHub` |
| `wildlife_pokedex_theme.dart` | Palette rétro Pokédex | ↑ module wildlife |

---

### 3.9 `lib/models/` (37)

| Fichier | Rôle | Dépendances |
|---------|------|-------------|
| `activity_event.dart` | Événement fil d'activité amis | ↑ `ActivityService` |
| `bgg_catalog_game.dart` | Jeu catalogue BGG (`CatalogEntry`) | ↑ grilles BGG, quick-add |
| `bgg_expansion.dart` | Métadonnées extension BGG | ↑ expansion service/section |
| `boardgame_play_session.dart` | Session de partie (scores, gagnant, grille) | ↑ historique, `metadata.boardgame_plays` |
| `boardgame_score_grid.dart` | Grille scores multi-joueurs/équipes | ↑ éditeur scores, sessions |
| `book_author_group.dart` | Regroupement auteur pour grilles | ↑ `BookAuthorDetailScreen` |
| `book_series.dart` | Entité série + stats ; getter `novelMatrix` **inutilisé** | ↑ `BookSeriesService` |
| `book_subcategory.dart` | Enum BD/manga/romans | ↑ hubs livres |
| `book_volume.dart` | Volume, statut lecture, slots grille | ↑ tous écrans volumes |
| `card_subcategory.dart` | Enum TCG (Pokémon, MTG, etc.) | ↑ écrans TCG |
| `category_metadata.dart` | Parse/affichage metadata par catégorie | ↑ `CollectionItem`, détail |
| `category_stat.dart` | Snapshot stats par catégorie | ↑ `CollectionStatsService` |
| `collection_category.dart` | Enum catégories + icônes/couleurs | ↑ routing global |
| `collection_group.dart` | Groupe de partage | ↑ `GroupService`, badges |
| `collection_item.dart` | **Entité centrale** — fromJson, toInsertJson, toUpdateJson | ↑ quasi tout le projet |
| `collection_list_filters.dart` | Filtres/tri (`CollectionSort`, ownership, holder) | ↑ `HomeScreen`, `CollectionFilterBar` |
| `collection_summary.dart` | DTO résumé collection | ↑ stats |
| `collection_view_mode.dart` | Enum grille/liste | ↑ `HomeScreen` |
| `group_icon.dart` | Options icône groupe | ↑ `GroupEditScreen` |
| `item_condition.dart` | État objet (neuf, bon, etc.) | ↑ dialogs ajout |
| `item_tag.dart` | Tag utilisateur | ↑ `TagService` |
| `lego_build_kind.dart` | Type build Lego | ↑ metadata Lego |
| `marketplace_listing.dart` | Annonce marketplace groupe | ↑ `MarketplaceService` |
| `media_format_ui.dart` | Extension UI formats média | ↑ hub média |
| `novel_rating_matrix.dart` | Matrice notes romans — **API largement morte** | ↑ `book_series.dart` |
| `pokemon_card_lang.dart` | Codes langue cartes Pokémon | ↑ écrans Pokémon |
| `restaurant_visit.dart` | Visite restaurant | ↑ `RestaurantService` |
| `rule_section.dart` | Sections règles groupe structurées | ↑ `ModularRuleEditor` |
| `series_search_hit.dart` | Résultat recherche série Open Library | ↑ coordinators |
| `storage_location.dart` | Emplacement physique | ↑ `InventoryService` |
| `tcg_set_info.dart` | Block, set, carte catalogue TCG | ↑ écrans TCG |
| `user_collection_type.dart` | Type collection personnalisé | ↑ `UserCollectionTypeService` |
| `user_list.dart` | Liste de lecture custom | ↑ `UserListService` |
| `user_profile.dart` | Profil utilisateur | ↑ `ProfileService` |
| `wildlife_catalog.dart` | Entrée espèce catalogue | ↑ `WildlifeService` |
| `wildlife_observation.dart` | Observation terrain (GPS, photo) | ↑ wildlife screens |
| `wildlife_taxonomy.dart` | Realm/royaume/famille taxonomie | ↑ Pokédex UI |

---

### 3.10 `lib/services/` (65)

| Fichier | Rôle | Dépendances |
|---------|------|-------------|
| `activity_service.dart` | Fil événements amis (Supabase) | ↑ `FriendsActivityFeed` |
| `auth_service.dart` | Auth Supabase sign-in/up/out | ↑ `SplashScreen`, `LoginScreen`, drawer |
| `bgg_service.dart` | API BGG XML (+ proxy Edge Function web) | ↑ boardgame flows, catalogues |
| `boardgame_discovery_service.dart` | Discovery BGG par genre curaté | ↓ `boardgame_curated_catalog` |
| `boardgame_expansion_service.dart` | Sync extensions BGG ↔ collection | ↑ expansion section, reconcile |
| `book_catalog_service.dart` | Orchestration recherche livres multi-sources | ↓ Google Books, Open Library, iTunes |
| `book_custom_cover_service.dart` | Upload couvertures custom (Storage) | ↑ volume detail |
| `book_intelligence_service.dart` | Recherche enrichie livres | ↓ Riftscribe, catalogues |
| `book_series_service.dart` | CRUD séries/volumes Supabase | ↑ tous écrans livres |
| `card_catalog_service.dart` | Catalogue TCG unifié | ↓ Pokémon, Scryfall, YGO, Lorcast, One Piece |
| `category_hub_preferences.dart` | Prefs visibilité tuiles hub (SharedPreferences) | ↑ `CategoryManageScreen` |
| `collection_export_service.dart` | Export fichier + share | ↓ `share_plus`, `path_provider` |
| `collection_refresh.dart` | **ChangeNotifier** global `bump()` post-écriture | ↑ tous flows add/update/delete |
| `collection_share_service.dart` | Liens partage collection | ↑ `ShareCollectionSheet` |
| `collection_stats_service.dart` | Agrégats stats collection | ↑ `StatsScreen` |
| `discogs_service.dart` | API Discogs (médias) | ↑ `MediaCatalogService` |
| `friend_boardgame_feed_service.dart` | Feed jeux joués par amis | ↑ activity |
| `friend_ratings_service.dart` | Notes amis sur un objet | ↑ `FriendRatingsPanel` |
| `friend_service.dart` | Amitiés et demandes | ↑ `FriendsScreen` |
| `global_play_history_service.dart` | Historique parties global + orphelins (prefs) | ↑ `GlobalPlayHistoryScreen` |
| `google_books_service.dart` | API Google Books | ↑ `BookCatalogService` |
| `group_community_service.dart` | Règles + wanted posts groupe | ↑ `GroupRulesPanel`, `GroupWantedBoard` |
| `group_service.dart` | CRUD groupes et membres | ↑ group screens, whereabouts |
| `holder_place_history_service.dart` | Historique lieux « Autre » (SharedPreferences) | ↑ `CompactWhereaboutsDropdown` |
| `image_compression_service.dart` | Compression avant upload | ↑ avatar, covers |
| `inaturalist_service.dart` | API iNaturalist taxons | ↑ wildlife search/log |
| `inventory_service.dart` | Emplacements stockage CRUD | ↑ `InventoryManageScreen` |
| `item_group_service.dart` | Junction `collection_item_groups` M:N | ↑ add flows, group sync |
| `itunes_books_service.dart` | Recherche livres iTunes | ↑ `BookCatalogService` |
| `itunes_movie_service.dart` | Recherche films iTunes | ↑ `MovieCatalogService` |
| `lego_catalog_service.dart` | Catalogue Lego unifié | ↓ Rebrickable, Fandom |
| `lego_fandom_service.dart` | Images fallback wiki Lego | ↑ `LegoCatalogService` |
| `loan_service.dart` | Prêts entre amis | ↑ `LoansScreen` |
| `location_service.dart` | Lieux géocodés sauvegardés | ↑ location picker |
| `lorcast_service.dart` | API Lorcana | ↑ `CardCatalogService` |
| `marketplace_service.dart` | Annonces marketplace groupe | ↑ `MarketplaceScreen` |
| `media_catalog_service.dart` | Recherche média unifiée | ↓ Discogs, MusicBrainz |
| `movie_catalog_service.dart` | Films unifié | ↓ TMDB, iTunes |
| `musicbrainz_service.dart` | MusicBrainz + Cover Art Archive | ↑ `MediaCatalogService` |
| `nominatim_service.dart` | Géocodage OpenStreetMap | ↑ restaurant, location |
| `onepiece_tcg_service.dart` | API One Piece TCG | ↑ `CardCatalogService` |
| `open_library_service.dart` | Open Library works/authors/series | ↑ book flows |
| `pokemon_tcg_service.dart` | Pokémon via TCGdex | ↑ écrans Pokémon |
| `profile_cache_service.dart` | Cache profil mémoire + prefs | ↑ drawer, avatar |
| `profile_service.dart` | CRUD profils Supabase | ↑ auth, profile edit |
| `quick_log_service.dart` | Quick logs profil | ↑ `QuickLogTimeline` |
| `rawg_service.dart` | API RAWG jeux vidéo | ↑ `VideogameCatalogService` |
| `rebrickable_service.dart` | API Rebrickable Lego | ↑ `LegoCatalogService` |
| `recommendation_service.dart` | Recommandations catalogue | ↑ `RecommendationsBanner` |
| `restaurant_service.dart` | Visites restaurants CRUD | ↑ restaurant screens |
| `riftscribe_service.dart` | API Riftscribe romans | ↑ book intelligence |
| `scryfall_service.dart` | API Scryfall MTG | ↑ `CardCatalogService` |
| `settings_service.dart` | Thème, notifications, privacy (prefs + sync profil) | ↑ `main.dart`, settings |
| `showcase_service.dart` | Favoris et trophées profil | ↑ profile widgets |
| `steam_store_service.dart` | API Steam Store | ↑ `VideogameCatalogService` |
| `tag_service.dart` | Tags items CRUD | ↑ `ItemTagsEditor` |
| `tmdb_service.dart` | API TMDB films | ↑ `MovieCatalogService` |
| `user_boardgame_collection_service.dart` | Clés owned/wishlist boardgame | ↑ BGG catalog grid |
| `user_card_collection_service.dart` | Clés owned cartes TCG | ↑ TCG set screens |
| `user_collection_type_service.dart` | Types collection custom | ↑ dialog création |
| `user_list_service.dart` | Listes lecture CRUD | ↑ user list screens |
| `videogame_catalog_service.dart` | Jeux vidéo unifié | ↓ RAWG, Steam |
| `wildlife_service.dart` | Observations + stats + carte (Supabase) | ↑ wildlife screens |
| `wishlist_suggestion_service.dart` | Suggestions wishlist | ↑ `WishlistSuggestionsBanner` |
| `ygoprodeck_service.dart` | API Yu-Gi-Oh Pro Deck | ↑ `CardCatalogService` |

---

### 3.11 `lib/utils/` (62)

| Fichier | Rôle | Dépendances |
|---------|------|-------------|
| `activity_feed_grouper.dart` | Regroupe événements activity consécutifs | ↑ `FriendsActivityFeed` |
| `app_haptics.dart` | Retour haptique léger | ↑ tiles interactives |
| `boardgame_bulk_add.dart` | Add/remove silencieux boardgame + wishlist | ↑ BGG catalog grid |
| `boardgame_collection_visibility.dart` | Masque expansions en collection globale | ↑ `HomeScreen`, tiles |
| `boardgame_cover.dart` | URL couverture BGG + preview | ↑ catalog, preview sheet |
| `boardgame_display.dart` | Format joueurs, durée, note BGG ; `bggShortDescription` **mort** | ↑ tiles, détail |
| `boardgame_expansion_flow.dart` | Insert/link expansions avec dialogs | ↑ expansion sheets |
| `boardgame_expansion_reconcile.dart` | Réparation liens expansions orphelins | ↑ `HomeScreen` init |
| `boardgame_expansions.dart` | Helpers IDs expansions owned metadata | ↑ tiles |
| `boardgame_genres.dart` | Extraction genres BGG metadata | ↑ filtres HomeScreen |
| `boardgame_past_players.dart` | Noms joueurs sessions passées | ↑ logging parties |
| `boardgame_play_stats.dart` | Agrégats classements, podiums | ↑ ranking panels |
| `boardgame_quick_add.dart` | Quick-add BGG depuis catalogue | ↓ `whereabouts_persistence`, BGG |
| `boardgame_volume_cover.dart` | **MORT** — helper couverture volume | — |
| `book_add_actions.dart` | Point d'entrée sheets ajout livre | ↑ hubs livres |
| `book_series_focus.dart` | Filtre volumes par série/focus | ↑ `BookCollectionScreen` |
| `book_title_parser.dart` | Parse titre → série/volume | ↑ `BookItemAddCoordinator` |
| `card_item_metadata.dart` | Parse types Pokémon, sous-catégories | ↑ filtres cartes |
| `card_quick_add.dart` | Quick-add carte TCG | ↑ set screens |
| `catalog_hit_metadata.dart` | Map hit catalogue → metadata JSON | ↑ quick-add flows |
| `catalog_http.dart` | Headers HTTP catalogues | ↑ services API |
| `collection_count_label.dart` | Libellé français compteur objets | ↑ `HomeScreen` |
| `collection_grid_grouper.dart` | Regroupe doublons pour grille | ↑ `HomeScreen` |
| `collection_grid_layout.dart` | Colonnes responsive, aspect ratio | ↑ grilles |
| `collection_item_filters.dart` | `isActiveCollectionItem`, shake-pick | ↑ `HomeScreen` |
| `collection_item_scope.dart` | Filtres PostgREST scope personnel/groupe | ↑ services requêtes |
| `copy_friend_item.dart` | Copie objet ami → ma collection | ↑ `FriendCollectionScreen` |
| `cover_image_url.dart` | URLs couvertures dimensionnées | ↑ images |
| `debounced_runner.dart` | Debounce recherche | ↑ search sheets |
| `dialog_layout.dart` | Hauteur dialog adaptative clavier | ↑ search dialogs |
| `french_plural.dart` | Pluriel français jeux | ↑ UI boardgame |
| `friend_item_overlap.dart` | Index chevauchement collection ami | ↑ tiles |
| `holder_filter.dart` | Options filtre « chez qui » | ↑ `HomeScreen`, filter bar |
| `holder_label_utils.dart` | Format labels lieu manuel | ↑ whereabouts partout |
| `http_user_agent.dart` | User-Agent TCG APIs | ↑ services TCG |
| `hub_category_visibility.dart` | Tuiles hub visibles | ↑ category selection |
| `category_hub_order.dart` | Ordre tuiles hub (prefs) | ↑ manage/selection |
| `item_stock_persistence.dart` | Persist quantité, ventes, échanges | ↑ inventory sheets |
| `marketplace_status.dart` | Flags marketplace metadata | ↑ marketplace |
| `navigate_to_card_set.dart` | Navigation set depuis tuile carte | ↑ `CollectionItemTile` |
| `onepiece_card_utils.dart` | IDs/raretés One Piece | ↑ service One Piece |
| `owned_quantity_index.dart` | Index quantités cross-tab par match key | ↑ `HomeScreen`, wishlist |
| `picked_image_bytes.dart` | Export conditionnel IO/stub | ↑ upload images |
| `picked_image_bytes_io.dart` | Lecture bytes mobile/desktop | ↑ export `picked_image_bytes` |
| `picked_image_bytes_stub.dart` | Stub web | ↑ export `picked_image_bytes` |
| `pokemon_series_labels_fr.dart` | Labels FR séries Pokémon | ↑ écrans Pokémon |
| `pokemon_set_labels_fr.dart` | Labels FR sets Pokémon | ↑ écrans Pokémon |
| `search_relevance.dart` | Score pertinence titre | ↑ `BggService` |
| `shake_pick_filters.dart` | Filtres shake-pick | ↑ `ShakePickScreen` |
| `splash_audio.dart` | Son splash + fade | ↑ `CollectingoSplash` |
| `supabase_embeds.dart` | Chaînes select PostgREST (joins) | ↑ requêtes items |
| `tcg_bulk_add.dart` | Add bulk TCG + wishlist toggle | ↑ TCG screens |
| `tcg_card_display.dart` | Affichage sous-titre cartes | ↑ tiles TCG |
| `tcg_premium_rarities.dart` | **MORT** — tiers raretés premium | — |
| `tcg_rarity_order.dart` | Ordre tri raretés par TCG | ↑ set screens |
| `tcg_set_image_url.dart` | URLs logos sets/blocks | ↑ `TcgSetLogo` |
| `tcgdex_assets.dart` | URLs assets TCGdex | ↑ Pokémon service |
| `transaction_history.dart` | Parse/append ventes/échanges metadata | ↑ stock sheets |
| `web_image_proxy.dart` | Proxy images CORS web | ↑ `BggNetworkImage` |
| `whereabouts_apply.dart` | Apply whereabouts in-memory | ↑ détail, sheets |
| `whereabouts_persistence.dart` | Payload insert/update lieu + group_ids | ↑ tous inserts |
| `wishlist_collection_bridge.dart` | Pont wishlist ↔ collection (qty 0/1) | ↑ inventory sheets |
| `wishlist_promote.dart` | Promote wishlist, findDuplicateRow | ↑ coordinators, bridge |

---

### 3.12 `lib/screens/` (50)

| Fichier | Rôle | Dépendances |
|---------|------|-------------|
| `splash_screen.dart` | Splash + auth gate | ↓ `AuthService`, `ProfileService` |
| `login_screen.dart` | Connexion/inscription | ↓ `AuthService` |
| `category_selection_screen.dart` | Hub catégories post-login | ↑ route `/categories` |
| `category_manage_screen.dart` | Réordonner/masquer catégories hub | ↓ prefs hub |
| `home_screen.dart` | **Écran central** collection+wishlist, stream Realtime | ↓ Supabase stream, tiles, filters |
| `item_detail_screen.dart` | Fiche objet complète multi-catégorie | ↓ nombreux widgets panels |
| `wishlist_overview_screen.dart` | **MORT** — vue wishlist cross-catégorie | — |
| `stats_screen.dart` | Dashboard statistiques | ↓ `CollectionStatsService` |
| `settings_screen.dart` | Préférences app | ↓ `SettingsService` |
| `profile_edit_screen.dart` | Édition profil, avatar, showcase | ↓ `ProfileService` |
| `friends_screen.dart` | Liste amis | ↓ `FriendService` |
| `friend_collection_screen.dart` | Collection lecture seule ami | ↓ `copy_friend_item` |
| `groups_screen.dart` | Liste groupes | ↓ `GroupService` |
| `group_detail_screen.dart` | Détail groupe + items stream | ↓ stream, community |
| `group_edit_screen.dart` | Créer/éditer groupe | ↓ `GroupService` |
| `global_play_history_screen.dart` | Historique parties + classement all-time | ↓ `GlobalPlayHistoryService` |
| `shake_pick_screen.dart` | Tirage aléatoire (accéléromètre) | ↓ `sensors_plus` |
| `inventory_manage_screen.dart` | CRUD emplacements | ↓ `InventoryService` |
| `loans_screen.dart` | Prêts actifs/retournés | ↓ `LoanService` |
| `books_collection_screen.dart` | Hub livres (sous-catégories) | ↑ navigation livres |
| `book_author_detail_screen.dart` | Grille volumes par auteur | ↓ Open Library |
| `book_series_detail_screen.dart` | Détail série + volumes | ↓ `BookSeriesService` |
| `book_subcategory_series_screen.dart` | Liste séries par sous-catégorie | ↓ coordinators |
| `book_wishlist_tab.dart` | Onglet wishlist livres + stream | ↓ Supabase stream |
| `cards_collection_screen.dart` | Hub TCG | ↑ navigation TCG |
| `lego_collection_screen.dart` | Hub Lego | ↓ `LegoCatalogService` |
| `media_collection_screen.dart` | Hub média (vinyles, CD) | ↓ Discogs |
| `media_artist_albums_screen.dart` | Albums par artiste | ↓ MusicBrainz |
| `movie_collection_screen.dart` | Hub films | ↓ TMDB |
| `videogame_collection_screen.dart` | Hub jeux vidéo | ↓ RAWG/Steam |
| `watch_collection_screen.dart` | Hub montres | ↓ catalogues watch |
| `boardgame/boardgames_collection_screen.dart` | Shell collection jeux société | ↑ → `HomeScreen` |
| `boardgame/bgg_catalog_grid_screen.dart` | Grille catalogue BGG browse/add | ↓ `BggService`, bulk add |
| `book/book_collection_screen.dart` | Grille volumes personnels | ↓ `BookCatalogService` |
| `book/book_catalog_grid_screen.dart` | Grille catalogue livres externe | ↓ catalogues |
| `book/user_lists_hub_screen.dart` | Hub listes lecture custom | ↓ `UserListService` |
| `book/user_list_detail_screen.dart` | Détail liste ordonnée | ↓ `UserListService` |
| `marketplace/marketplace_screen.dart` | Marketplace groupe | ↓ `MarketplaceService` |
| `restaurant/restaurant_collection_screen.dart` | Journal restaurants + stream | ↓ stream, visits |
| `restaurant/restaurant_map_screen.dart` | Carte visites | ↓ `flutter_map` |
| `restaurant/restaurant_search_screen.dart` | Recherche/ajout restaurant | ↓ Nominatim |
| `tcg/pokemon_series_blocks_screen.dart` | Blocs Pokémon par langue | ↓ `PokemonTcgService` |
| `tcg/tcg_series_blocks_screen.dart` | Blocs TCG génériques | ↓ `CardCatalogService` |
| `tcg/tcg_sets_block_screen.dart` | Sets d'un block | ↓ navigation sets |
| `tcg/tcg_set_cards_screen.dart` | Grille cartes d'un set | ↓ quick-add TCG |
| `tcg/tcg_global_search_screen.dart` | Recherche cartes cross-set | ↓ `CardCatalogService` |
| `tcg/tcg_rarity_gallery_screen.dart` | **MORT** — galerie raretés premium | — |
| `wildlife/wildlife_collection_screen.dart` | Pokédex espèces | ↓ `WildlifeService` |
| `wildlife/wildlife_species_screen.dart` | Détail espèce + observations | ↓ geolocator |
| `wildlife/wildlife_map_screen.dart` | Carte observations | ↓ `flutter_map` |

---

### 3.13 `lib/widgets/` (106)

Regroupés par sous-dossier. Fichiers **MORT** marqués.

#### Racine `widgets/` (82)

| Fichier | Rôle |
|---------|------|
| `add_friend_sheet.dart` | Sheet ajout ami par username |
| `add_item_manual_dialog.dart` | Formulaire ajout manuel |
| `add_item_options_dialog.dart` | Dialog options ajout (wishlist, groupe, whereabouts, note BGG) |
| `add_volume_to_series_sheet.dart` | Ajouter volume catalogue à série |
| `app_app_bar.dart` | AppBar cohérente |
| `assign_book_series_sheet.dart` | Assigner volumes orphelins à série |
| `author_avatar.dart` | Avatar auteur Open Library |
| `avatar_crop_sheet.dart` | Recadrage avatar avant upload |
| `bgg_community_rating_panel.dart` | Panneau note communautaire BGG |
| `bgg_network_image.dart` | Image réseau BGG (wrapper `CollectionCoverImage`) |
| `bgg_search_dialog.dart` | Dialog recherche BGG |
| `boardgame_expansion_detail_sheet.dart` | Détail extension + attach |
| `boardgame_expansions_section.dart` | Section expansions fiche détail |
| `boardgame_play_history_panel.dart` | Historique parties par jeu |
| `boardgame_ranking_detail_screen.dart` | Matrice classement plein écran |
| `boardgame_ranking_panel.dart` | Podium et stats classement |
| `boardgame_score_grid_editor.dart` | Éditeur grille scores |
| `boardgame_tile_inventory_sheets.dart` | Sheets qty/groupe/expansion + stock |
| `boardgame_tile_meta_icons.dart` | 5 icônes interactives (grille + liste) |
| `boardgame_tile_sheets.dart` | Sheets note et lieu tuile |
| `book_add_choice_sheet.dart` | Choix mode ajout livre |
| `book_manual_volume_dialog.dart` | Dialog volume manuel |
| `book_quick_search_sheet.dart` | **Déprécié** — wrapper recherche livre |
| `book_search_dialog.dart` | Dialog recherche livre multi-sources |
| `book_series_tile.dart` | Tuile série dans grilles |
| `book_subcategory_picker.dart` | Picker sous-catégorie livre |
| `book_volume_add_cell.dart` | Cellule « ajouter volume » |
| `book_volume_cell.dart` | Cellule volume série |
| `book_volume_detail_sheet.dart` | Sheet détail/édition volume |
| `book_volume_status_sheet.dart` | **MORT** — picker statut lecture |
| `card_quick_search_sheet.dart` | Recherche rapide cartes |
| `card_search_dialog.dart` | Dialog recherche cartes |
| `catalog_search_sheet.dart` | Sheet recherche catalogue générique |
| `category_catalog_hub_body.dart` | Corps hub avec sources catalogue |
| `category_collection_header.dart` | Header gradient catégorie |
| `category_collection_shell.dart` | Scaffold partagé hubs (tabs, FAB) |
| `category_hub_header.dart` | Header landing hub |
| `category_metadata_fields.dart` | Champs metadata éditables par catégorie |
| `category_type_hub.dart` | Grille sous-types hub |
| `collapsible_collection_overview.dart` | **MORT** — overview expandable |
| `collapsible_section.dart` | Section expandable générique |
| `collection_cover_image.dart` | Image couverture cachée + proxy web |
| `collection_filter_bar.dart` | Barre recherche + Tri + Filtre |
| `collection_item_list_tile.dart` | Ligne liste collection |
| `collection_item_tile.dart` | Tuile grille collection |
| `collection_summary_card.dart` | **MORT** — carte résumé stats |
| `compact_whereabouts_dropdown.dart` | Sélecteur « Chez qui ? » (ExpansionTiles) |
| `cover_preview_sheet.dart` | Preview couverture plein écran |
| `create_book_series_dialog.dart` | **MORT** — dialog création série |
| `create_custom_collection_dialog.dart` | Créer type collection custom |
| `discogs_market_value_card.dart` | Valeur marché Discogs |
| `focus_filter_button.dart` | Bouton focus partage (livres) |
| `friend_picker_dialog.dart` | Dialog choix ami |
| `friend_rating_detail_sheet.dart` | Détail note ami |
| `friend_ratings_panel.dart` | Panel notes amis |
| `friends_activity_feed.dart` | Fil activité amis |
| `group_badge.dart` | Badge nom/icône groupe |
| `group_member_location_field.dart` | **MORT** — champ membre groupe (remplacé par compact dropdown) |
| `group_members_sheet.dart` | Sheet membres groupe |
| `group_rules_panel.dart` | Règles maison groupe |
| `group_stats_banner.dart` | Bannière stats groupe |
| `group_wanted_board.dart` | Tableau « recherché » groupe |
| `isbn_scan_sheet.dart` | Scanner ISBN |
| `item_aspect_ratings_section.dart` | Notes multi-aspects |
| `item_tags_editor.dart` | Éditeur tags |
| `item_whereabouts_field.dart` | **MORT** — champ whereabouts legacy |
| `loan_item_dialog.dart` | Dialog prêt objet |
| `location_picker_field.dart` | **MORT** — champ géolocalisation |
| `main_drawer.dart` | Drawer navigation principale |
| `mark_volumes_owned_sheet.dart` | **MORT** — marquer volumes possédés |
| `markdown_rules_editor.dart` | **MORT** — éditeur markdown règles |
| `media_quick_search_sheet.dart` | Recherche rapide média |
| `media_search_dialog.dart` | Dialog recherche média |
| `modular_rule_editor.dart` | Éditeur règles structurées |
| `password_text_field.dart` | Champ mot de passe |
| `personal_whereabouts_field.dart` | **MORT** — whereabouts personnel legacy |
| `profile_avatar.dart` | Avatar profil circulaire |
| `recommendations_banner.dart` | Bannière recommandations |
| `restaurant_visits_panel.dart` | Panel visites restaurant |
| `rich_section_text_field.dart` | Champ texte riche règles |
| `series_link_confirm_dialog.dart` | **MORT** — confirmation lien série |
| `series_search_dialog.dart` | Recherche série Open Library |
| `share_collection_sheet.dart` | Export/partage collection |
| `star_rating_bar.dart` | Barre étoiles interactive |
| `volume_number_dialog.dart` | Dialog numéro de volume |
| `watch_quick_search_sheet.dart` | Recherche rapide montres |
| `wishlist_suggestions_banner.dart` | Suggestions wishlist |

#### `widgets/catalog/` (1)

| Fichier | Rôle |
|---------|------|
| `catalog_item_tile.dart` | Tuile générique grille catalogue |

#### `widgets/marketplace/` (1)

| Fichier | Rôle |
|---------|------|
| `marketplace_inquiry_sheet.dart` | Sheet demande achat/échange marketplace |

#### `widgets/profile/` (5)

| Fichier | Rôle |
|---------|------|
| `favorites_showcase.dart` | Vitrine favoris profil |
| `quick_log_timeline.dart` | Timeline quick logs |
| `retro_avatar.dart` | Avatar rétro showcase |
| `trophy_picker_sheet.dart` | Picker trophées profil |
| `trophy_tree.dart` | **MORT** — arbre trophées |

#### `widgets/splash/` (1)

| Fichier | Rôle |
|---------|------|
| `collectingo_splash.dart` | Animation splash branding |

#### `widgets/tcg/` (2)

| Fichier | Rôle |
|---------|------|
| `tcg_catalog_card_tile.dart` | Tuile carte dans grille set |
| `tcg_set_logo.dart` | Logo set/block TCG (SVG/network) |

#### `widgets/ui/` (4)

| Fichier | Rôle |
|---------|------|
| `add_option_tile.dart` | Tuile option dans sheets ajout |
| `empty_state.dart` | État vide générique |
| `hub_search_bar.dart` | Barre recherche hubs |
| `loading_placeholder.dart` | Skeleton chargement |

#### `widgets/wildlife/` (5)

| Fichier | Rôle |
|---------|------|
| `inat_search_dialog.dart` | Recherche espèce iNaturalist |
| `pokedex_completion_ring.dart` | **MORT** — anneau complétion Pokédex |
| `pokedex_stats_panel.dart` | Panel stats par royaume |
| `wildlife_field_log_sheet.dart` | Log observation terrain |
| `wildlife_friends_compare_sheet.dart` | Comparaison espèces amis |

---

## 4. Diagrammes de flux de données (UML textuel)

### 4.1 Flux UI → State

```
┌──────────────┐     initState      ┌─────────────────────────────────┐
│ HomeScreen   │──────────────────►│ Supabase Realtime Stream         │
│              │                    │ collection_items.eq(category)    │
│              │◄── stream event ───│ → _filterAndScopeRows (client)   │
│              │                    └────────────┬────────────────────┘
│              │                                 │ trigger
│              │     _reloadItemsFromDb()        ▼
│              │◄─────────────────────── PostgREST SELECT (embed joins)
│              │
│              │     CollectionRefresh.bump() ──► même reload
│              │
│              │     setState:
│              │       _itemRows → _parseItems → _enrichedItems (tags)
│              │       filters.apply() → filtered list
│              │       CollectionGridGrouper.group() → tiles
└──────────────┘

États locaux notables (HomeScreen) :
  - _collectionFilters / _wishlistFilters (indépendants par onglet Tab)
  - _viewMode (grid | list)
  - _derivedCacheSource → cache groupActivity + holderFilterOptions
  - TabController (Collection | Wishlist) — rebuild complet _buildTab à chaque setState
```

**Pattern refresh** :

```
[Action UI: add/update/delete]
        │
        ▼
[Supabase INSERT/UPDATE/DELETE]
        │
        ├──► CollectionRefresh.instance.bump()
        │         └──► HomeScreen._reloadItemsFromDb()
        │
        └──► Realtime stream event (latence variable)
                  └──► même _reloadItemsFromDb()
```

**ChangeNotifier globaux** :

| Notifier | Rôle |
|----------|------|
| `CollectionRefresh` | Bump post-mutation collection |
| `SettingsService` | Thème → rebuild `MyApp` |
| `ProfileCacheService` | Avatar/username drawer |

Pas de Provider/Riverpod/Bloc — état majoritairement **local StatefulWidget**.

---

### 4.2 Flux Cache Local (SharedPreferences)

```
┌─────────────────────────────────────────────────────────────────┐
│                    SharedPreferences                             │
├─────────────────────────────────────────────────────────────────┤
│ settings_service          │ theme, notifications, privacy flags  │
│                           │ → sync privacy vers profiles (Supabase)│
├───────────────────────────┼─────────────────────────────────────┤
│ profile_cache_service     │ cache profil (id, username, avatar)   │
├───────────────────────────┼─────────────────────────────────────┤
│ category_hub_preferences  │ catégories masquées hub               │
│ category_hub_order        │ ordre tuiles hub v2                   │
├───────────────────────────┼─────────────────────────────────────┤
│ holder_place_history      │ holder_places_{groupId}               │
│                           │ holder_places_user_{userId}           │
│                           │ → suggestions « Autre (personne/lieu)»│
├───────────────────────────┼─────────────────────────────────────┤
│ global_play_history       │ orphan_boardgame_plays_{userId}       │
│                           │ → parties orphelines (jeu supprimé)   │
├───────────────────────────┼─────────────────────────────────────┤
│ group_rules_panel         │ preferred group rule id               │
├───────────────────────────┼─────────────────────────────────────┤
│ UX tips (books/cards hub) │ flags one-shot                        │
└─────────────────────────────────────────────────────────────────┘

Note : PAS de SQLite. Données collection = toujours autoritaires via Supabase.
Images réseau = cache mémoire/disque via cached_network_image (hors SharedPreferences).
```

---

### 4.3 Flux Supabase

#### 4.3.1 Tables principales

```
profiles ─────┬──── friendships
              │
groups ───────┼──── group_members
              │
collection_items ◄────┬──── collection_item_groups (M:N item↔group)
              │       │
              │       ├── locations (location_id)
              │       ├── item_tags (via collection_item_tags)
              │       └── profiles (location_user_id, added_by, loaned_to)
              │
              ├── book_series / book_volumes
              ├── wildlife_observations
              ├── restaurant_visits
              ├── user_lists / user_list_items
              ├── marketplace_inquiries
              ├── activity_events
              └── group_rule_entries, group_wanted_posts
```

#### 4.3.2 Lecture (SELECT)

```
HomeScreen:
  STREAM  collection_items
          .eq('category', X)
          → map(_filterAndScopeRows)  // filtre client: user + groupes membres

  SELECT  collection_items
          .select(SupabaseEmbeds.collectionItemList)  // joins locations, groups, holder profile, tags
          → _parseItems → TagService.enrichItems → _enrichedItems

GroupDetailScreen:
  STREAM  collection_items.eq('group_id', gid)
  +       SELECT junction collection_item_groups pour items multi-groupes

Scopes (collection_item_scope.dart):
  personnel: group_id IS NULL AND (added_by = me OR location_user_id = me)
  groupe:    group_id IN mes groupes
```

#### 4.3.3 Écriture (INSERT/UPDATE)

```
Pipeline insert standard (boardgame exemple):

  UI Dialog (AddItemOptions)
       │
       ▼
  buildCollectionItemInsertPayload()     [whereabouts_persistence.dart]
       │  ├─ prepareItemWhereabouts (manual holder vs membre)
       │  ├─ metadataWithGroupIds
       │  ├─ finalizeMetadataPayload (force holder_label)
       │  └─ toInsertJson
       ▼
  supabase.from('collection_items').insert(payload).select().single()
       │
       ▼ (si groupId)
  ItemGroupService.syncItemGroupsWithItem(item, [groupId])
       │  ├─ UPSERT collection_item_groups
       │  └─ UPDATE collection_items (group_id, metadata, location_user_id)
       ▼
  CollectionRefresh.instance.bump()
```

#### 4.3.4 Relations groupes (triple représentation)

| Représentation | Champ | Rôle |
|----------------|-------|------|
| Primaire | `collection_items.group_id` | Premier groupe sélectionné |
| Metadata | `metadata.group_ids: List<String>` | Tous les groupes |
| Junction | `collection_item_groups (item_id, group_id)` | **Source M:N** |

`ItemGroupService.syncItemGroups()` fait diff incrémental junction ; `syncItemGroupsWithItem()` fusionne metadata DB avant update.

#### 4.3.5 Realtime streams (4 écrans)

| Écran | Filtre stream |
|-------|---------------|
| `HomeScreen` | `category` |
| `GroupDetailScreen` | `group_id` |
| `RestaurantCollectionScreen` | `category=restaurant` |
| `BookWishlistTab` | `category=book` + wishlist |

Chaque stream déclenche **aussi** un SELECT complet (double fetch).

#### 4.3.6 Metadata JSON — champs critiques

| Clé | Usage |
|-----|-------|
| `holder_label` | Lieu manuel « Autre » (location_user_id = null) |
| `group_ids` | Multi-appartenance groupes |
| `bgg_id`, `bgg_avg_rating`, `bgg_categories` | Boardgame |
| `boardgame_plays` | **Array JSON** sessions (`BoardgamePlaySession.toJson`) |
| `transaction_history` | Ventes/échanges |
| `owned_expansion_bgg_ids` | Extensions possédées |
| `inaturalist_id`, `wildlife_*` | Nature |
| `discogs_release_id` | Médias |

---

### 4.4 Flux API Externes

```
┌──────────── BGG ────────────┐
│ Native: boardgamegeek.com   │
│ Web: Edge Function bgg-api  │
│   actions: search|game|     │
│   expansions|hot|meta       │
└─────────────┬───────────────┘
              │ getGameFullDetails(bggId)
              ▼
        metadata JSON → collection_items.insert
        (snapshot au moment de l'ajout — pas de resync auto)

┌──────── Open Library / Google Books / iTunes ─────┐
│ BookCatalogService orchestration                   │
└─────────────┬──────────────────────────────────────┘
              ▼
        book_series / book_volumes / collection_items

┌──────── TCG APIs ───────────┐
│ Pokémon→TCGdex, MTG→Scryfall│
│ Lorcana→Lorcast, YGO→YGOPro  │
│ One Piece→API dédiée          │
└─────────────┬───────────────┘
              ▼
        CardCatalogService → collection_items (subcategory)

┌──────── Discogs / MusicBrainz ──┐
│ Token .env DISCOGS_TOKEN         │
└─────────────┬────────────────────┘
              ▼
        MediaCatalogService → metadata format/artist/year

┌──────── TMDB / RAWG / Steam / Rebrickable ──┐
│ Films, jeux vidéo, Lego                        │
└─────────────┬────────────────────────────────┘
              ▼
        collection_items.metadata

┌──────── iNaturalist ──────────┐
│ api.inaturalist.org/v1/taxa   │
└─────────────┬─────────────────┘
              ▼
        collection_items + wildlife_observations (GPS)
```

**Proxy images web** : `image-proxy` Edge Function + `web_image_proxy.dart` pour CORS (BGG, TCG, etc.).

---

### 4.5 Flux Collection ↔ Wishlist

```
                    collection_items
                    is_wishlist: bool
                    quantity: int (0 autorisé)
                           │
        ┌──────────────────┼──────────────────┐
        ▼                  ▼                  ▼
 owned_quantity_index   wishlist_promote   wishlist_collection_bridge
 (match key:            findDuplicateRow    addOneToCollectionFromWishlist
  bgg:{id} ou           promote in-place    zeroOutCollectionItem
  title|cat|sub)        OR new row          addToWishlistFromCollection

Match key (owned_quantity_index.dart):
  1. metadata.bgg_id → "bgg:{id}"
  2. sinon → "title:{lower}|{category}|{subcategory}"

HomeScreen:
  - Onglet Collection: isActiveCollectionItem = !wishlist && quantity > 0
  - Onglet Wishlist: is_wishlist = true
  - ownedIndex partagé: affiche « tu possèdes N » sur wishlist
```

---

### 4.6 Sérialisation historique parties

```
BoardgamePlaySession
    │
    ├─ toJson() → Map
    │
    └─ stocké dans metadata.boardgame_plays[] (jsonb array)

parseBoardgamePlays(metadata):
    List → BoardgamePlaySession.fromJson → tri compareBoardgamePlaySessions

Orphelins (jeu supprimé):
    archivePlaysFromDeletedItem → SharedPreferences orphan_boardgame_plays_{userId}

GlobalPlayHistoryService.loadAllEntries():
    SELECT tous collection_items boardgame
    + parse boardgame_plays
    + merge orphan prefs
    → groupPlayHistoryEntries() (streaks)
```

**Risque sérialisation** : `boardgame_plays` grossit sans limite dans jsonb ; pas de pagination côté DB.

---

## 5. Chasse au code mort

> **CHANTIER 1 (terminé)** — 20 fichiers Dart et 2 dépendances (`flutter_markdown`, `cupertino_icons`) supprimés ; symboles morts (`bggShortDescription`, `novelMatrix`, `saveNovelMatrix`, `NovelRatingMatrix`) retirés. L'inventaire détaillé ci-dessous est conservé à titre d'archive ; les chemins listés n'existent plus dans le dépôt.

### 5.1 Fichiers Dart supprimés (19 + modèle orphelin)

| Fichier | Statut |
|---------|--------|
| `lib/utils/tcg_premium_rarities.dart` | ✓ supprimé |
| `lib/screens/tcg/tcg_rarity_gallery_screen.dart` | ✓ supprimé |
| `lib/screens/wishlist_overview_screen.dart` | ✓ supprimé |
| `lib/widgets/create_book_series_dialog.dart` | ✓ supprimé |
| `lib/widgets/mark_volumes_owned_sheet.dart` | ✓ supprimé |
| `lib/widgets/series_link_confirm_dialog.dart` | ✓ supprimé |
| `lib/catalog/catalog_owned_state.dart` | ✓ supprimé |
| `lib/widgets/profile/trophy_tree.dart` | ✓ supprimé |
| `lib/utils/book_volume_cover.dart` | ✓ supprimé |
| `lib/widgets/item_whereabouts_field.dart` | ✓ supprimé |
| `lib/widgets/personal_whereabouts_field.dart` | ✓ supprimé |
| `lib/widgets/location_picker_field.dart` | ✓ supprimé |
| `lib/widgets/group_member_location_field.dart` | ✓ supprimé |
| `lib/widgets/collapsible_collection_overview.dart` | ✓ supprimé |
| `lib/widgets/collection_summary_card.dart` | ✓ supprimé |
| `lib/widgets/book_quick_search_sheet.dart` | ✓ supprimé |
| `lib/widgets/markdown_rules_editor.dart` | ✓ supprimé |
| `lib/widgets/wildlife/pokedex_completion_ring.dart` | ✓ supprimé |
| `lib/widgets/book_volume_status_sheet.dart` | ✓ supprimé |
| `lib/models/novel_rating_matrix.dart` | ✓ supprimé (orphelin après §5.2) |

### 5.2 Symboles morts nettoyés

| Fichier | Symbole | Statut |
|---------|---------|--------|
| `utils/boardgame_display.dart` | `bggShortDescription` | ✓ supprimé |
| `models/book_series.dart` | getter `novelMatrix` | ✓ supprimé |
| `services/book_series_service.dart` | `saveNovelMatrix` | ✓ supprimé |

### 5.3 Packages retirés

| Package | Statut |
|---------|--------|
| `flutter_markdown` | ✓ retiré de `pubspec.yaml` |
| `cupertino_icons` | ✓ retiré de `pubspec.yaml` |

### 5.4 Clusters fonctionnels abandonnés (reste à auditer)

1. **Novel rating matrix screen** — écran potentiellement orphelin (`novel_rating_matrix_screen.dart`)
2. **Book series dialogs** — flows actuels passent par coordinators, pas par dialogs dédiés
3. **Écrans TCG/livres non routés** — voir inventaire §3 pour candidats restants

*Clusters TCG Rarity Gallery, Wishlist Overview et Whereabouts legacy : entièrement supprimés en CHANTIER 1.*

---

## 6. Audit performance et scaling

### 6.1 Goulots d'étranglement identifiés

#### A. Double fetch Realtime + SELECT (`HomeScreen`)

```
Chaque événement stream → _scheduleReloadItemsFromDb() → debounce 300 ms → _reloadItemsFromDb()
Chaque CollectionRefresh.bump() → idem
Pull-to-refresh → _reloadItemsFromDb() immédiat (sans debounce)
```

**Impact résiduel** : le stream Realtime reçoit déjà les lignes mais déclenche quand même un SELECT complet — le debounce réduit les rafales (bulk add) à **un seul** SELECT final.

**CHANTIER 2 (terminé)** : debounce 300 ms via `DebouncedRunner` sur stream + `CollectionRefresh` ; `RefreshIndicator` et chargement initial restent immédiats.

**Piste future** : parser le payload stream au lieu de re-SELECT.

#### B. Enrichissement tags asynchrone

```
_onItemRows → _scheduleEnrich → TagService.enrichItems(parsed)
  → setState(_enrichedItems)  // 2e rebuild après SELECT
```

Chaque reload déclenche **2 cycles setState** (rows puis enriched).

#### C. Enrichissement BGG ratings lazy

```
Tri par note communautaire → _enrichBggRatingsForSort()
  → N appels BggService.getGameFullDetails pour items sans bgg_avg_rating
  → N PATCH metadata Supabase
```

Peut saturer API BGG et générer N writes si collection grande et tri activé.

#### D. Rebuild `_buildTab` sur chaque frappe filtre/recherche

```
onFiltersChanged → setState → filters.apply(items) + rebuild grille complète
```

Filtres appliqués côté client sur liste complète — OK jusqu'à ~500–1000 items, puis lag UI.

Mitigation partielle récente : cache `_derivedCacheSource` pour `groupActivity` et `holderFilterOptions`.

#### E. Vue liste boardgame — widgets lourds

`CollectionItemListTile` + `BoardgameTileMetaIcons` = 5 `GestureDetector` + décorations par ligne. `RepaintBoundary` + `cacheExtent: 640` ajoutés pour limiter repaints scroll.

#### F. `GroupDetailScreen` — double source items

Stream `group_id` + requête junction `collection_item_groups` + merge client — risque doublons et requêtes redondantes.

#### G. Historique parties — chargement monolithique

`GlobalPlayHistoryService.loadAllEntries()` charge **tous** les `boardgame_plays` de **tous** les jeux en une passe + prefs orphelins. Croissance O(total parties) en mémoire.

#### H. Expansion reconcile au premier chargement boardgame

`repairAndReconcileBoardgameExpansions()` au init `HomeScreen` — peut déclencher multiples reads/writes BGG + Supabase au cold start.

### 6.2 Risques scaling Supabase

| Scénario | Risque | Sévérité |
|----------|--------|----------|
| Collection > 500 items même catégorie | SELECT embed lourd, filtres client lents | Moyen |
| metadata.boardgame_plays[] > 50 sessions/jeu | jsonb volumineux, parse lent | Moyen |
| Multi-groupes par item | Triple sync (junction + group_id + group_ids) — désync possible | Faible |
| 4 streams Realtime ouverts simultanément | Connexions websocket multiples | Faible |
| RLS + filtre client double | Données filtrées deux fois — OK sécurité, coût réseau | Faible |

### 6.3 Robustesse indexation Collection ↔ Wishlist

**Points forts** :
- `collectionItemMatchKey` stable via `bgg_id` quand disponible
- `owned_quantity_index` agrège cross-scope pour affichage wishlist
- `findDuplicateRow` aligne promote/bridge sur même clé

**Points faibles** :
- Sans `bgg_id`, collision possible sur titres identiques sous-catégories différentes (clé inclut subcategory — OK)
- Wishlist et collection peuvent être **deux lignes** pour même jeu (`wishlist_collection_bridge` vs `promoteWishlistToCollection` — chemins différents)
- `quantity = 0` en collection + ligne wishlist séparée = états ambigus sans discipline UI

### 6.4 Robustesse JSON `boardgame_plays`

- Pas de schema version dans metadata
- `BoardgamePlaySession.fromJson` tolérant (champs optionnels)
- `parseBoardgamePlays` ignore entrées mal formées (`whereType<Map>`)
- Tri stable via `compareBoardgamePlaySessions` (date → createdAt → index)
- **Pas de limite taille array** — risque à long terme

---

## 7. Schéma Supabase (référence)

Fichiers SQL sous `supabase/` (migrations manuelles, non auto-appliquées) :

| Fichier | Contenu |
|---------|---------|
| `schema_personal_columns.sql` | Colonnes personnelles `collection_items`, metadata jsonb |
| `schema_collection_item_groups.sql` | Table junction M:N |
| `schema_quantity_allow_zero.sql` | Contrainte `quantity >= 0` |
| `schema_groups_custom.sql` | Groupes personnalisés |
| `schema_social.sql` | Amitiés, activity |
| `schema_marketplace.sql` | Marketplace |
| `schema_wildlife_restaurant.sql` | Observations, visites |
| `schema_book_*.sql` | Séries, volumes, couvertures |
| `schema_loans.sql` | Prêts |
| `schema_*_rls*.sql` | Politiques RLS |

Edge Functions (`supabase/functions/`) :

| Function | Rôle |
|----------|------|
| `bgg-api` | Proxy BGG XML pour web |
| `bgg-proxy` | Proxy alternatif BGG |
| `image-proxy` | Proxy images CORS |
| `riftscribe-proxy` | Proxy API romans |

---

## 8. Roadmap produit — idées et priorisation

> Backlog vivant — idées discutées en revue produit (juin 2026).  
> **Légende effort** : S (< 1 j), M (2–5 j), L (1–2 sem), XL (chantier multi-sprints).  
> **Légende valeur** : impact perçu pour l’utilisateur collectionneur / social.

### 8.1 Comment lire ce document

| Priorité | Signification | Action |
|----------|---------------|--------|
| **A — À faire** | Faisable avec l’existant, fort ROI, peu de dette API | Candidats prochains sprints |
| **B — Plus tard** | Utile mais dépendance externe, effort moyen, ou niche | Backlog quand A épuisé |
| **C — Hors scope / veille** | Complexe, coût récurrent, ou ROI faible vs maintenance | Ne pas planifier sauf changement de besoin |
| **✓ Fait / en cours** | Déjà livré ou correction récente | Référence seulement |

### 8.2 Modules matures (plateau)

| Module | État | Pistes restantes (polish uniquement) |
|--------|------|--------------------------------------|
| **Jeux de société** | Très abouti (BGG, extensions v2, discovery, shake pick, historique + classement) | « Pas joué depuis X mois », win rate par jeu, import collection BGG, planificateur soirée |
| **TCG catalogue** (Pokémon, Magic, YGO, OPTCG, Lorcana, Riftbound) | Navigateur sets + bulk add opérationnel | Voir §8.3 complétion ; RiftScribe corrigé (`sort=default`) |
| **Topps / Panini** | Saisie manuelle volontaire | Voir §8.5 — catalogues externes écartés |

---

### 8.3 Priorité A — Faisable et utile (recommandé en premier)

| Idée | Valeur | Effort | Prérequis / notes |
|------|--------|--------|-------------------|
| **Complétion TCG** — % par set/bloc/TCG, cartes manquantes, filtre inverse dans `TcgSetCardsScreen`, barres dans le hub cartes | Très haute pour collectionneurs | M | Réutilise `owned/total` existant, clés `UserCardCollectionService`, pas de nouvelle API |
| **Insights transversaux** — bandeau ou section sur `CategorySelectionScreen` : garanties tech expirantes, prêts anciens, séries livres « prochain tome », sets TCG quasi complets, valeur d’achat cumulée | Haute — donne une « intelligence » à l’app | M | Données déjà en base (`purchase_price`, `warranty_end`, `loaned_at`, séries livres) |
| **Social wishlist / doublons** — « X amis veulent cet objet », « tu as un doublon, Y l’a en wishlist », comparaison complétion entre amis (TCG) | Haute — différenciation vs apps solo | M–L | S’appuie sur `friend_item_overlap`, `FriendService`, wishlist partagée |
| **High-Tech V2 — alertes garantie** — bandeau hub + fiche détail + éventuellement entrée dans insights | Haute au quotidien | S–M | V1 livrée (`tech_warranty.dart`, metadata `warranty_end`) |
| **Wildlife — défis & progression** — badges par règne/famille, défis mensuels (« 5 oiseaux »), export life list | Haute — module différenciant | M | Pokédex déjà riche ; pas d’API nouvelle |
| **Livres — prochain à lire/acheter** — dans `BookSeriesDetailScreen`, suggérer le prochain volume manquant ou non lu | Moyenne–haute | S–M | `BookSeriesService`, flags `isRead` / wishlist volumes |
| **Stats enrichies** — étendre `StatsScreen` : valeur achat toutes catégories, complétion TCG agrégée, top manques wishlist | Moyenne | M | `CollectionStatsService` déjà partiel (Discogs musique) |
| **Rappels prêts** — prêt non rendu depuis N jours → insight ou badge `LoansScreen` | Moyenne | S | `loaned_at` en base |
| **Abstraction catalogue Phase 2** — généraliser `CatalogEntry` / `UserCatalogService` au-delà BGG | Moyenne (technique) | L | Enabler pour discovery unifiée ; déjà amorcé dans `lib/catalog/` |

**Ordre suggéré pour un plan concret :**

1. Complétion TCG (quick win visible)
2. Insights transversaux (valeur globale)
3. Alertes garantie High-Tech
4. Social wishlist léger
5. Wildlife défis

---

### 8.4 Priorité B — Utile mais effort ou dépendance plus lourds

| Idée | Valeur | Effort | Prérequis / notes |
|------|--------|--------|-------------------|
| **Marketplace / échanges** — enrichir `MarketplaceScreen` (match wishlist, négociation, notifs) | Haute si groupes actifs | L–XL | `marketplace_service.dart` early ; ROI dépend de l’usage réel des groupes |
| **Wildlife — heatmap carte** — densité observations sur `WildlifeMapScreen` | Moyenne–haute | M | `flutter_map` déjà en place |
| **Restaurant — « où aller »** — wishlist restos + géoloc / carte | Moyenne (niche fun) | M | `restaurant_map_screen.dart` |
| **Vinyles — valeur marché étendue** — même pattern que `DiscogsService.fetchMarketStats` pour plus d’items média | Moyenne | M | Clé Discogs, quotas API |
| **Showcase public** — refonte `web/showcase.html` (plus visuel, partage social) | Moyenne | M | `ShowcaseService` + RPC existants |
| **Recommandations** — élargir `RecommendationService` cross-catégories, pas seulement notes amis | Moyenne | M | Déjà dans `StatsScreen` |
| **Groupes — wishlist collaborative** | Moyenne | M–L | Tables / RLS à définir |
| **High-Tech V2 — configurateur PC** | Moyenne (niche) | L | Master configs Supabase, liens composants |
| **High-Tech — scan code-barres / EAN** | Moyenne | M | `mobile_scanner` déjà utilisé pour ISBN livres |
| **Boardgames — polish** | Faible–moyenne | S–M each | Module déjà au plateau ; faire seulement si passion perso |
| **Performance — `scrollCacheExtent`** | Technique | S | Voir §6.1 audit ; migration API Flutter |
| **Realtime HomeScreen** — parser payload stream au lieu de re-SELECT | Technique | M | Voir §6.2 piste future |

---

### 8.5 Priorité C — Hors scope actuel (veille ou abandon explicite)

| Idée | Pourquoi écarter (pour l’instant) | Réouverture possible si… |
|------|-----------------------------------|---------------------------|
| **Topps — catalogue toutes collections** | Pas d’API officielle gratuite ; [CardSight](https://cardsight.ai/) freemium (~750 req/mois), clé + quotas + tiers | Collection Topps importante + acceptation clé payante |
| **Panini — catalogue tous albums** | Pas d’API unifiée ; un JSON par album à maintenir (CDM, Euro…) ; sous-catégorie app = **stickers**, pas cartes Prizm | Un album précis (ex. CDM 2026) via JSON embarqué — effort ciblé, pas « toutes collections » |
| **Panini cartes sport (Prizm, Select…)** | Non modélisé dans l’app ; chevauche CardSight / Topps | Nouvelle sous-catégorie ou fusion avec Topps |
| **Riftbound — prix marché** ([riftbound-api.com](https://riftbound-api.com/)) | API payante RapidAPI ; catalogue déjà couvert par RiftScribe gratuit | Besoin explicite valeur collection / arbitrage |
| **High-Tech — catalogue produit (GSMArena, Icecat)** | Matching produit fragile, quotas, peu aligné inventaire perso + garantie | Scan EAN fiable ou partenariat API |
| **BGG — sync collection import** | API BGG rate-limit, doublons avec logique extensions locale | Demande forte utilisateurs BGG power |
| **Matrice notes romans (IMDB)** | Feature retirée (`novel_rating_matrix.dart` supprimé) | Redesign plus simple (note par tome + moyenne série) |
| **Prix marché universel** (TCG, boardgames, tech) | APIs payantes hétérogènes ; Discogs seul cas partiel | Budget API ou cache serveur dédié |

**Décision produit (juin 2026)** : Topps et Panini restent en **saisie manuelle** ; pas de chantier catalogue externe tant qu’il n’y a pas d’API gratuite illimitée type Scryfall/RiftScribe.

---

### 8.6 Corrections récentes (référence)

| Sujet | Problème | Correctif |
|-------|----------|-----------|
| **Riftbound / RiftScribe** | `sort=collector_number` → HTTP 422, grille vide | `sort=default` dans `riftscribe_service.dart` ; mapping search `card_id` / `thumbnail_url` |

---

### 8.7 Matrice décision rapide

```
                    VALEUR UTILISATEUR
                    faible          forte
              ┌─────────────┬─────────────┐
    faible    │  C — veille │  B — si fun │
 EFFORT       │  (Topps all)│  (resto map)│
              ├─────────────┼─────────────┤
    fort      │  C — abandon│  A — plan   │
              │  (mktplace  │  (TCG %,    │
              │   complet)  │   insights) │
              └─────────────┴─────────────┘
```

**Question de cadrage avant de prioriser** (à trancher en équipe / usage perso) :

1. App surtout **solo** ou **groupes/amis actifs** ? → social vs complétion solo
2. Catégorie la plus remplie ? → TCG complétion vs wildlife vs livres
3. Préférence **utile quotidien** (garanties, prêts) vs **fun collectionneur** (%, badges) ?

---

## Annexe — Diagramme composants simplifié

```
                    ┌─────────────┐
                    │   main.dart  │
                    └──────┬──────┘
                           │
              ┌────────────┼────────────┐
              ▼            ▼            ▼
        SplashScreen  SettingsService  Supabase
              │                         │
              ▼                         │
     CategorySelection ─────────────────┤
              │                         │
    ┌─────────┼─────────┬───────────────┤
    ▼         ▼         ▼               ▼
 HomeScreen  Groups   Friends      ItemDetail
    │                                    │
    ├─ CollectionFilterBar               ├─ Category panels
    ├─ CollectionItemTile/ListTile       ├─ BoardgameExpansions
    ├─ AddItemOptionsDialog              ├─ PlayHistoryPanel
    └─ BggCatalogGrid                    └─ Whereabouts save
              │                                    │
              └──────── CollectionRefresh.bump() ──┘
                           │
                           ▼
                    collection_items (Supabase)
```

---

*Document généré par audit statique du dépôt. Pour validation code mort, exécuter `dart analyze` et `dart run dependency_validator` en complément.*
