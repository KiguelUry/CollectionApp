import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';
import '../services/auth_service.dart';
import '../services/profile_cache_service.dart';
import '../services/profile_service.dart';
import '../utils/hub_greeting.dart';
import '../utils/supabase_error_messages.dart';
import '../widgets/profile_avatar.dart';

/// Surnom obligatoire après un premier login Google ou Discord.
class FinishProfileScreen extends StatefulWidget {
  const FinishProfileScreen({super.key});

  @override
  State<FinishProfileScreen> createState() => _FinishProfileScreenState();
}

class _FinishProfileScreenState extends State<FinishProfileScreen> {
  final _profiles = ProfileService();
  final _auth = AuthService();
  final _username = TextEditingController();
  final _bio = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  String _accent = profileAccentPresets.first;
  String _identity = 'Non précisé';
  GrammarGender _grammar = GrammarGender.masculine;
  bool _passwordOpen = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _email.text = Supabase.instance.client.auth.currentUser?.email ?? '';
  }

  @override
  void dispose() {
    _username.dispose();
    _bio.dispose();
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _username.text.trim();
    if (name.isEmpty) {
      setState(() => _error = 'Le surnom est obligatoire.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final user = Supabase.instance.client.auth.currentUser;
      if (user == null) throw Exception('Session expirée');
      if (await _profiles.isUsernameTaken(name, excludeUserId: user.id)) {
        throw Exception('Ce surnom est déjà utilisé');
      }
      await _profiles.ensureCurrentUserProfile();
      final current = await _profiles.fetchCurrentProfile();
      final saved = await _profiles.updateProfileAndCache(
        current.copyWith(
          username: name,
          bio: _bio.text,
          accentColor: _accent,
          clearBio: _bio.text.trim().isEmpty,
        ),
      );
      await ProfileCacheService.instance.apply(saved);
      if (_identity.trim().isNotEmpty) {
        await _profiles.saveGreetingProfile(
          identity: _identity,
          grammar: _grammar.name,
        );
        await saveGenderIdentity(_identity);
        await saveGrammarGender(_grammar);
      }
      final password = _password.text;
      final email = _email.text.trim();
      final currentEmail = user.email ?? '';
      String? mailNote;
      if (_passwordOpen && password.trim().isNotEmpty) {
        if (email.isEmpty) {
          throw Exception(
            'Indique un e-mail pour pouvoir te connecter avec un mot de passe.',
          );
        }
        await _auth.updatePassword(password);
      }
      if (_passwordOpen && email.isNotEmpty && email != currentEmail) {
        await _auth.updateEmail(email);
        mailNote =
            'Un e-mail de confirmation a été envoyé à $email. L’adresse actuelle reste active tant que le lien n’est pas ouvert.';
      }
      await _auth.markProfileReady();
      if (!mounted) return;
      if (mailNote != null) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(mailNote)),
        );
      }
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = humanizeSupabaseError(e));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: const Text('Finaliser mon profil')),
        body: ListView(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            const Text(
              'Choisis le surnom visible par les autres. Le reste peut attendre.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _username,
              maxLength: 18,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                labelText: 'Surnom *',
                helperText: 'Obligatoire, unique',
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _bio,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'Bio',
                helperText: 'Optionnel',
              ),
            ),
            const SizedBox(height: 16),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Genre',
                helperText: 'Optionnel',
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  isExpanded: true,
                  value: _identity,
                  items: [
                    const DropdownMenuItem(
                      value: 'Non précisé',
                      child: Text('Non précisé'),
                    ),
                    for (final identity in kGenderIdentities)
                      DropdownMenuItem(value: identity, child: Text(identity)),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _identity = value);
                  },
                ),
              ),
            ),
            const SizedBox(height: 12),
            InputDecorator(
              decoration: const InputDecoration(
                labelText: 'Accord des salutations',
                helperText: 'Optionnel',
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<GrammarGender>(
                  isExpanded: true,
                  value: _grammar,
                  items: const [
                    DropdownMenuItem(
                      value: GrammarGender.feminine,
                      child: Text('Féminin'),
                    ),
                    DropdownMenuItem(
                      value: GrammarGender.masculine,
                      child: Text('Masculin'),
                    ),
                    DropdownMenuItem(
                      value: GrammarGender.neutral,
                      child: Text('Neutre'),
                    ),
                  ],
                  onChanged: (value) {
                    if (value == null) return;
                    setState(() => _grammar = value);
                  },
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text('Couleur d’accent'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final hex in profileAccentPresets)
                  GestureDetector(
                    onTap: () => setState(() => _accent = hex),
                    child: Container(
                      width: 28,
                      height: 28,
                      decoration: BoxDecoration(
                        color: ProfileAvatar.colorFromHex(hex),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: hex == _accent
                              ? Colors.white
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _saving
                    ? null
                    : () async {
                        try {
                          final url = await _profiles.pickAndUploadAvatar(
                            cropContext: context,
                          );
                          final current = await _profiles.fetchCurrentProfile();
                          await _profiles.updateProfileAndCache(
                            current.copyWith(avatarUrl: url),
                          );
                        } catch (e) {
                          final message = '$e';
                          if (message.contains('annulé') ||
                              message.contains('Aucune image')) {
                            return;
                          }
                          if (!mounted) return;
                          setState(() => _error = humanizeSupabaseError(e));
                        }
                      },
                icon: const Icon(Icons.photo_outlined),
                label: const Text('Photo de profil (optionnel)'),
              ),
            ),
            const SizedBox(height: 8),
            ExpansionTile(
              title: const Text('Ajouter un mot de passe de connexion (optionnel)'),
              initiallyExpanded: false,
              onExpansionChanged: (open) => setState(() => _passwordOpen = open),
              children: [
                TextField(
                  controller: _email,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: const InputDecoration(
                    labelText: 'E-mail',
                    helperText:
                        'Un changement d’adresse demande un clic dans le mail de confirmation.',
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _password,
                  obscureText: true,
                  decoration: const InputDecoration(
                    labelText: 'Mot de passe',
                    helperText: '6 caractères minimum, si tu veux aussi le mail.',
                  ),
                ),
              ],
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Valider mon profil'),
            ),
          ],
        ),
      ),
    );
  }
}
