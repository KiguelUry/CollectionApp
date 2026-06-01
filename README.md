# collection_app

Application Flutter **Collectingo** (collections, amis, groupes).

## Configuration locale (chaque développeur)

1. Copier `.env.example` → `.env` à la racine du projet.
2. Remplir au minimum `SUPABASE_URL` et `SUPABASE_ANON_KEY` (dashboard Supabase → Settings → API).
3. **Ne jamais committer `.env`** — le transmettre au collaborateur par un canal sécurisé (mot de passe, 1Password, message privé), ou lui donner accès au même projet Supabase pour qu’il crée son propre `.env`.

Variables optionnelles :

| Variable | Usage |
|----------|--------|
| `BGG_APPLICATION_TOKEN` | Jeux de société (BGG) |
| `GOOGLE_BOOKS_API_KEY` | Livres / mangas — ISBN et recherche (ex. One Piece) |
| `DISCOGS_TOKEN` | Vinyles / CD — Discogs (recherche + code-barres) ; sans token → MusicBrainz seul |
| `DEV_TEST_EMAIL` / `DEV_TEST_PASSWORD` | Connexion rapide en debug |

## Catalogues externes

- **Livres** : Open Library + Google Books (ISBN), hub par type (manga, BD, roman) avec séries.
- **Cartes** : Pokémon via [TCGdex](https://tcgdex.dev) (FR, gratuit) ; Magic / Yu-Gi-Oh! / One Piece / Lorcana — navigateur par blocs ou recherche.
- **Vinyles / CD** : hub par format → **Discogs** (token) + scan EAN ; repli **MusicBrainz** (gratuit, sans clé).
- **Jeux de société** : BGG (proxy Supabase sur le web).

## Lancer l’app (Cursor / VS Code)

Le fichier `.vscode/launch.json` propose deux profils **Run and Debug** (F5) :

| Profil | Usage |
|--------|--------|
| **Collection — splash pixel (normal)** | Comme en prod (splash au démarrage). |
| **Collection — dev rapide (sans splash)** | Développement : saute le splash (`DEV_SKIP_SPLASH`, `DEV_FAST_START`). |

Équivalent terminal : `scripts/run-dev-fast.ps1` ou `flutter run`.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.
