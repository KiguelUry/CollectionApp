import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';
import '../widgets/password_text_field.dart';

/// Écran affiché après le clic sur le lien « mot de passe oublié » dans l’e-mail.
class ResetPasswordScreen extends StatefulWidget {
  const ResetPasswordScreen({super.key});

  @override
  State<ResetPasswordScreen> createState() => _ResetPasswordScreenState();
}

class _ResetPasswordScreenState extends State<ResetPasswordScreen> {
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _auth = AuthService();
  bool _loading = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (password.length < 6) {
      _showError('Le mot de passe doit faire au moins 6 caractères.');
      return;
    }
    if (password != confirm) {
      _showError('Les deux mots de passe ne sont pas identiques.');
      return;
    }

    setState(() => _loading = true);
    try {
      await _auth.updatePassword(password);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: Icon(
            Icons.check_circle_outline,
            color: Theme.of(ctx).colorScheme.primary,
            size: 40,
          ),
          title: const Text('Mot de passe mis à jour'),
          content: const Text(
            'Tu peux maintenant te connecter avec ton nouveau mot de passe.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Continuer'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      Navigator.pushNamedAndRemoveUntil(context, '/categories', (_) => false);
    } catch (e) {
      if (!mounted) return;
      final msg = e is AuthException ? e.message : e.toString();
      _showError('Impossible d’enregistrer le mot de passe : $msg');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  void _showError(String message) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Attention'),
        content: Text(message),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('OK'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Nouveau mot de passe')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Choisis un nouveau mot de passe pour ton compte.',
                style: Theme.of(context).textTheme.bodyLarge,
              ),
              const SizedBox(height: 20),
              PasswordTextField(
                controller: _passwordController,
                labelText: 'Nouveau mot de passe',
              ),
              const SizedBox(height: 12),
              PasswordTextField(
                controller: _confirmController,
                labelText: 'Confirmer le mot de passe',
              ),
              const SizedBox(height: 28),
              FilledButton(
                onPressed: _loading ? null : _submit,
                child: _loading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Enregistrer'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
