import 'package:flutter/material.dart';

import '../widgets/app_app_bar.dart';

/// Récap « Qui voit quoi » : amis, groupes, collections.
class PrivacyVisibilityScreen extends StatelessWidget {
  const PrivacyVisibilityScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: const AppAppBar(title: 'Qui voit quoi ?'),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _Section(
            title: 'Entre amis',
            icon: Icons.people_outline,
            color: scheme.primary,
            bullets: const [
              'Les demandes d\'amitié acceptées permettent de voir le profil et d\'envoyer des notifications.',
              'Ta collection personnelle est visible si le partage mutuel est activé et si tu n\'as pas masqué ta collection (Réglages → Confidentialité).',
              'Ta wishlist est visible si « Wishlist visible par mes amis » est activée sur ton profil.',
              'Les recommandations d\'objets et les parties partagées arrivent uniquement entre amis acceptés.',
            ],
          ),
          _Section(
            title: 'Dans un groupe',
            icon: Icons.groups_outlined,
            color: Colors.teal.shade700,
            bullets: const [
              'Seuls les membres du groupe voient les objets rattachés à ce groupe (collection partagée du groupe).',
              'Les invitations à rejoindre un groupe passent par le centre de notifications ; tu choisis d\'accepter ou refuser.',
              'Le tirage « On joue à quoi ce soir ? » utilise uniquement les jeux de société du groupe, visibles par les membres.',
            ],
          ),
          _Section(
            title: 'Public & BGG',
            icon: Icons.public_outlined,
            color: Colors.orange.shade800,
            bullets: const [
              'Le cache BGG (`bgg_catalog_cache`) est partagé entre tous les utilisateurs : fiches et extensions publiques, sans données personnelles.',
              'Les non-amis ne voient pas ta collection si « Masquer aux non-amis » est activé (recommandé).',
            ],
          ),
          _Section(
            title: 'Ce qui reste privé',
            icon: Icons.lock_outline,
            color: scheme.secondary,
            bullets: const [
              'Historique des parties, notes d\'achat, emplacements détaillés et prêts ne sont pas exportés vers les amis via les recommandations.',
              'Les identités joueurs (alias locaux) restent sur ton appareil sauf si tu les inclus dans un export JSON manuel.',
            ],
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color color;
  final List<String> bullets;

  const _Section({
    required this.title,
    required this.icon,
    required this.color,
    required this.bullets,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 10),
                Text(
                  title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            for (final b in bullets)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('•  '),
                    Expanded(child: Text(b, style: const TextStyle(height: 1.35))),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}
