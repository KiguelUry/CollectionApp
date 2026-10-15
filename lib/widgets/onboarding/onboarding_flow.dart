import 'package:flutter/material.dart';

import '../../services/onboarding_service.dart';
import '../bgg_collection_import_card.dart';

/// Affiche l'onboarding une seule fois après connexion.
Future<void> showOnboardingIfNeeded(BuildContext context) async {
  if (!context.mounted) return;
  if (await OnboardingService.instance.isCompleted()) return;
  if (!context.mounted) return;
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: false,
    pageBuilder: (_, _, _) => const OnboardingFlowDialog(),
  );
}

class OnboardingFlowDialog extends StatefulWidget {
  const OnboardingFlowDialog({super.key});

  @override
  State<OnboardingFlowDialog> createState() => _OnboardingFlowDialogState();
}

class _OnboardingFlowDialogState extends State<OnboardingFlowDialog> {
  final _page = PageController();
  var _index = 0;

  Future<void> _finish() async {
    await OnboardingService.instance.markCompleted();
    if (mounted) Navigator.pop(context);
  }

  void _next() {
    if (_index >= 2) {
      _finish();
      return;
    }
    _page.nextPage(
      duration: const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  @override
  void dispose() {
    _page.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.surface.withValues(alpha: 0.98),
      child: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _finish,
                child: const Text('Passer'),
              ),
            ),
            Expanded(
              child: PageView(
                controller: _page,
                onPageChanged: (i) => setState(() => _index = i),
                children: [
                  _StepPage(
                    icon: Icons.cloud_download_outlined,
                    title: 'Importe ta collection BGG',
                    body: const SingleChildScrollView(
                      child: BggCollectionImportCard(),
                    ),
                  ),
                  const _StepPage(
                    icon: Icons.inventory_2_outlined,
                    title: 'Ta fiche & tes prêts',
                    subtitle:
                        'Chaque jeu a une fiche Bento : quantité, emplacement, '
                        'prêt temporaire à un ami, coût par partie.',
                  ),
                  const _StepPage(
                    icon: Icons.casino_outlined,
                    title: 'Lance une partie ou un tirage',
                    subtitle:
                        'Enregistre tes parties, lie tes amis pour synchroniser '
                        'l\'historique, ou utilise le tirage au sort depuis le hub.',
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Row(
                children: [
                  for (var i = 0; i < 3; i++)
                    Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: i == _index
                            ? scheme.primary
                            : scheme.outlineVariant,
                      ),
                    ),
                  const Spacer(),
                  FilledButton(
                    key: const ValueKey('onboarding_next'),
                    onPressed: _next,
                    child: Text(_index >= 2 ? 'C\'est parti' : 'Suivant'),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepPage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? body;

  const _StepPage({
    required this.icon,
    required this.title,
    this.subtitle,
    this.body,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Icon(icon, size: 56, color: Theme.of(context).colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            title,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w800,
            ),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 12),
            Text(
              subtitle!,
              style: TextStyle(
                fontSize: 15,
                height: 1.4,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
          if (body != null) ...[
            const SizedBox(height: 16),
            Expanded(child: body!),
          ],
        ],
      ),
    );
  }
}
