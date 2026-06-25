/// Fiche encyclopédique (espèces / races connues) — données statiques.
class WildlifeCatalogEntry {
  final String id;
  final String label;
  final String description;
  final String? imageUrl;
  final String genusGroupId;

  const WildlifeCatalogEntry({
    required this.id,
    required this.label,
    required this.description,
    this.imageUrl,
    required this.genusGroupId,
  });
}

abstract final class WildlifeCatalog {
  static List<WildlifeCatalogEntry> featuredForGenusGroup(String groupId) {
    final all = _byGroup[groupId] ?? const [];
    return all.take(10).toList();
  }

  static List<WildlifeCatalogEntry> allForGenusGroup(String groupId) {
    return _byGroup[groupId] ?? const [];
  }

  static const _byGroup = <String, List<WildlifeCatalogEntry>>{
    'small_cats': [
      WildlifeCatalogEntry(
        id: 'cat_siamese',
        genusGroupId: 'small_cats',
        label: 'Siamois',
        description:
            'Chat oriental au pelage clair et aux extrémités foncées, très vocal et sociable.',
        imageUrl:
            'https://upload.wikimedia.org/wikipedia/commons/thumb/2/25/Siam_cat.jpg/320px-Siam_cat.jpg',
      ),
      WildlifeCatalogEntry(
        id: 'cat_persian',
        genusGroupId: 'small_cats',
        label: 'Persan',
        description:
            'Race au museau court et au pelage long, calme et affectueuse.',
        imageUrl:
            'https://upload.wikimedia.org/wikipedia/commons/thumb/1/15/Persian_Cat_%28cropped%29.jpg/320px-Persian_Cat_%28cropped%29.jpg',
      ),
      WildlifeCatalogEntry(
        id: 'cat_maine_coon',
        genusGroupId: 'small_cats',
        label: 'Maine Coon',
        description:
            'Grand chat nord-américain, reconnaissable à sa queue touffue et sa taille imposante.',
        imageUrl:
            'https://upload.wikimedia.org/wikipedia/commons/thumb/5/5a/Maine_Coon_cat.jpg/320px-Maine_Coon_cat.jpg',
      ),
      WildlifeCatalogEntry(
        id: 'cat_bengal',
        genusGroupId: 'small_cats',
        label: 'Bengal',
        description: 'Pelage tacheté rappelant le léopard, très actif et joueur.',
      ),
      WildlifeCatalogEntry(
        id: 'cat_british',
        genusGroupId: 'small_cats',
        label: 'British Shorthair',
        description: 'Corps rond, poil dense, tempérament posé et doux.',
      ),
      WildlifeCatalogEntry(
        id: 'cat_ragdoll',
        genusGroupId: 'small_cats',
        label: 'Ragdoll',
        description: 'Grand chat bleu aux yeux bleus, se détend quand on le porte.',
      ),
      WildlifeCatalogEntry(
        id: 'cat_abyssinian',
        genusGroupId: 'small_cats',
        label: 'Abyssin',
        description: 'Pelage « ticked », silhouette fine, curieux et grimpeur.',
      ),
      WildlifeCatalogEntry(
        id: 'cat_sphynx',
        genusGroupId: 'small_cats',
        label: 'Sphynx',
        description: 'Chat quasi sans poils, peau chaude, très attaché à son humain.',
      ),
      WildlifeCatalogEntry(
        id: 'cat_scottish_fold',
        genusGroupId: 'small_cats',
        label: 'Scottish Fold',
        description: 'Oreilles pliées vers l\'avant, regard rond et expressif.',
      ),
      WildlifeCatalogEntry(
        id: 'cat_european',
        genusGroupId: 'small_cats',
        label: 'Chat européen',
        description:
            'Chat de gouttière robuste, le plus répandu en Europe, chasseur né.',
      ),
    ],
    'big_cats': [
      WildlifeCatalogEntry(
        id: 'lion',
        genusGroupId: 'big_cats',
        label: 'Lion',
        description:
            'Grand félin social d\'Afrique, seul félin vivant en groupe (la fierté).',
        imageUrl:
            'https://upload.wikimedia.org/wikipedia/commons/thumb/7/73/Lion_waiting_in_Namibia.jpg/320px-Lion_waiting_in_Namibia.jpg',
      ),
      WildlifeCatalogEntry(
        id: 'tiger',
        genusGroupId: 'big_cats',
        label: 'Tigre',
        description: 'Plus grand des félins, rayé, solitaire, d\'Asie.',
        imageUrl:
            'https://upload.wikimedia.org/wikipedia/commons/thumb/3/3f/Walking_tiger_female.jpg/320px-Walking_tiger_female.jpg',
      ),
      WildlifeCatalogEntry(
        id: 'leopard',
        genusGroupId: 'big_cats',
        label: 'Léopard',
        description: 'Taches en rosettes, grimpeur, très adaptable.',
      ),
      WildlifeCatalogEntry(
        id: 'cheetah',
        genusGroupId: 'big_cats',
        label: 'Guépard',
        description: 'Félin le plus rapide au sprint, taches pleines, jour.',
      ),
      WildlifeCatalogEntry(
        id: 'jaguar',
        genusGroupId: 'big_cats',
        label: 'Jaguar',
        description: 'Plus grand félin des Amériques, mâchoire puissante.',
      ),
      WildlifeCatalogEntry(
        id: 'snow_leopard',
        genusGroupId: 'big_cats',
        label: 'Léopard des neiges',
        description: 'Haute montagne d\'Asie, pelage épais, longue queue.',
      ),
      WildlifeCatalogEntry(
        id: 'puma',
        genusGroupId: 'big_cats',
        label: 'Puma',
        description: 'Amériques, uni, surnommé lion de montagne.',
      ),
      WildlifeCatalogEntry(
        id: 'lynx_eurasia',
        genusGroupId: 'big_cats',
        label: 'Lynx boréal',
        description: 'Oreilles pointues, favoris, forêts froides.',
      ),
    ],
  };
}
