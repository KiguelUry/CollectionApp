import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

/// Titres du hub (« Salut … »). Un seul qualificatif par famille
/// (stellaire, lunaire, nuits blanches…) pour éviter l'effet répétitif.
const kGreetingTitles = <String>[
  'Aventurier',
  'Collectionneur',
  'Chasseur d\'étoiles',
  'Capitaine',
  'Explorateur',
  'Voyageur stellaire',
  'Pirate des nuits blanches',
  'Corsaire',
  'Flibustier',
  'Mousquetaire',
  'Paladin',
  'Chevalier errant',
  'Ninja',
  'Samouraï',
  'Shérif',
  'Détective',
  'Magicien',
  'Alchimiste',
  'Druide',
  'Barde',
  'Archéologue',
  'Cartographe',
  'Navigateur',
  'Astronaute',
  'Cosmonaute',
  'Rêveur cosmique',
  'Voyageur lunaire',
  'Comète',
  'Étoile filante',
  'Météore',
  'Phénix',
  'Dragon',
  'Noctambule',
  'Nomade',
  'Globe-trotteur',
  'Baroudeur',
  'Pionnier',
  'Prodige',
  'Virtuose',
  'Maestro',
  'Rockstar',
  'Champion',
  'Légende',
  'Héros du dimanche',
  'Esprit libre',
  'Chercheur de trésors',
  'Gentleman cambrioleur',
  'Funambule',
  'Dompteur de dragons',
  'Sentinelle de minuit',
  'Grand stratège',
  'Petit génie',
  'Mystérieux inconnu',
  'Faiseur de miracles',
  'Gardien de la galaxie',
  'Explorateur des abysses',
  'Voyageur temporel',
  'Âme vagabonde',
  'Boss final',
  'Roi du suspense',
];

enum HubGreetingSource { pseudo, title }

/// Accord grammatical des titres d'accueil.
enum GrammarGender { masculine, feminine, neutral }

const kGreetingTitlesFeminine = <String>[
  'Aventurière',
  'Collectionneuse',
  'Chasseuse d\'étoiles',
  'Capitaine',
  'Exploratrice',
  'Voyageuse stellaire',
  'Pirate des nuits blanches',
  'Corsaire',
  'Flibustière',
  'Mousquetaire',
  'Paladine',
  'Chevalière errante',
  'Ninja',
  'Samouraï',
  'Shérif',
  'Détective',
  'Magicienne',
  'Alchimiste',
  'Druidesse',
  'Barde',
  'Archéologue',
  'Cartographe',
  'Navigatrice',
  'Astronaute',
  'Cosmonaute',
  'Rêveuse cosmique',
  'Voyageuse lunaire',
  'Comète',
  'Étoile filante',
  'Météore',
  'Phénix',
  'Dragonne',
  'Noctambule',
  'Nomade',
  'Globe-trotteuse',
  'Baroudeuse',
  'Pionnière',
  'Prodige',
  'Virtuose',
  'Maestra',
  'Rockstar',
  'Championne',
  'Légende',
  'Héroïne du dimanche',
  'Esprit libre',
  'Chercheuse de trésors',
  'Gentleman cambrioleur',
  'Funambule',
  'Dompteuse de dragons',
  'Sentinelle de minuit',
  'Grande stratège',
  'Petit génie',
  'Mystérieuse inconnue',
  'Faiseuse de miracles',
  'Gardienne de la galaxie',
  'Exploratrice des abysses',
  'Voyageuse temporelle',
  'Âme vagabonde',
  'Boss final',
  'Reine du suspense',
];

const kGenderIdentities = <String>[
  'Femme',
  'Homme',
  'Non-binaire',
  'Genre fluide',
  'Agenre',
  'Transgenre',
  'Intersexe',
  'Bispirituel·le',
  'Autre',
];

class HubGreeting {
  final String name;
  final HubGreetingSource source;

  const HubGreeting({required this.name, required this.source});

  String get text => 'Salut $name';
}

/// 20 % pseudo, 80 % titre tiré uniformément dans [kGreetingTitles].
/// [previous] évite de retomber sur le même titre deux fois de suite.
HubGreeting pickHubGreeting({
  required String username,
  String? previous,
  Random? random,
  GrammarGender grammar = GrammarGender.masculine,
}) {
  final rng = random ?? Random();
  if (grammar == GrammarGender.neutral || rng.nextDouble() < 0.2) {
    return HubGreeting(name: username, source: HubGreetingSource.pseudo);
  }
  final pool = grammar == GrammarGender.feminine
      ? kGreetingTitlesFeminine
      : kGreetingTitles;
  var name = pool[rng.nextInt(pool.length)];
  if (name == previous && pool.length > 1) {
    final i = pool.indexOf(name);
    name = pool[(i < 0 ? 0 : i + 1) % pool.length];
  }
  return HubGreeting(name: name, source: HubGreetingSource.title);
}

/// Salutation du hub : fixe tant qu'on reste sur l'accueil ;
/// [reroll] tire un nouveau surnom au retour sur le Hub.
class HubGreetingSession {
  static HubGreeting? greeting;
  static GrammarGender? grammar;
  static String? identity;
  static bool profileReady = false;

  static HubGreeting ensure({
    required String username,
    GrammarGender? grammarOverride,
  }) {
    final g = grammarOverride ?? grammar ?? GrammarGender.masculine;
    grammar = g;
    final current = greeting;
    if (current != null) {
      if (current.source == HubGreetingSource.pseudo &&
          current.name != username) {
        greeting = HubGreeting(name: username, source: HubGreetingSource.pseudo);
      }
      return greeting!;
    }
    greeting = pickHubGreeting(username: username, grammar: g);
    return greeting!;
  }

  /// Nouveau tirage (retour Hub). Garde [previous] pour éviter le même titre.
  static HubGreeting reroll({
    required String username,
    GrammarGender? grammarOverride,
  }) {
    final g = grammarOverride ?? grammar ?? GrammarGender.masculine;
    grammar = g;
    greeting = pickHubGreeting(
      username: username,
      previous: greeting?.name,
      grammar: g,
    );
    return greeting!;
  }
}

const kGrammarPrefsKey = 'greeting_grammar_v1';
const kIdentityPrefsKey = 'gender_identity_v1';

Future<GrammarGender> loadGrammarGender() async {
  final prefs = await SharedPreferences.getInstance();
  final value = switch (prefs.getString(kGrammarPrefsKey)) {
    'feminine' => GrammarGender.feminine,
    'neutral' => GrammarGender.neutral,
    _ => GrammarGender.masculine,
  };
  HubGreetingSession.grammar = value;
  return value;
}

Future<void> saveGrammarGender(GrammarGender gender) async {
  HubGreetingSession.grammar = gender;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kGrammarPrefsKey, gender.name);
}

Future<String?> loadGenderIdentity() async {
  final prefs = await SharedPreferences.getInstance();
  final value = prefs.getString(kIdentityPrefsKey);
  if (value != null) HubGreetingSession.identity = value;
  return value;
}

Future<void> saveGenderIdentity(String identity) async {
  HubGreetingSession.identity = identity;
  final prefs = await SharedPreferences.getInstance();
  await prefs.setString(kIdentityPrefsKey, identity);
}

/// Précharge genre + accord des salutations en mémoire (0 ms à l'ouverture Profil).
Future<void> preloadGreetingProfile({
  Future<({String? identity, String? grammar})> Function()? remoteFetch,
}) async {
  final localGrammar = await loadGrammarGender();
  final localIdentity = await loadGenderIdentity();
  var identity = localIdentity ?? HubGreetingSession.identity ?? 'Non précisé';
  var grammar = localGrammar;

  if (remoteFetch != null) {
    try {
      final remote = await remoteFetch();
      if (remote.identity != null && remote.identity!.trim().isNotEmpty) {
        identity = remote.identity!;
      }
      grammar = switch (remote.grammar) {
        'feminine' => GrammarGender.feminine,
        'neutral' => GrammarGender.neutral,
        'masculine' => GrammarGender.masculine,
        _ => grammar,
      };
    } catch (_) {}
  }

  await saveGenderIdentity(identity);
  await saveGrammarGender(grammar);
  HubGreetingSession.profileReady = true;
}
