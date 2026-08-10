import 'package:flutter/material.dart';
import '../config/dev_auth_config.dart';
import '../services/auth_service.dart';
import '../widgets/password_text_field.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _usernameController = TextEditingController();
  final _authService = AuthService();
  bool _isSignUp = false;
  bool _devLoading = false;
  bool _resetLoading = false;

  @override
  void initState() {
    super.initState();
    if (DevAuthConfig.testEmail != null) {
      _emailController.text = DevAuthConfig.testEmail!;
    }
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _usernameController.dispose();
    super.dispose();
  }

  Future<void> _goToApp() async {
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/categories');
  }

  Future<void> _handleAuth() async {
    try {
      if (_isSignUp) {
        await _authService.signUp(
          _emailController.text,
          _passwordController.text,
          _usernameController.text,
        );
      } else {
        await _authService.signIn(
          _emailController.text,
          _passwordController.text,
        );
      }
      await _goToApp();
    } catch (e) {
      if (!mounted) return;
      await _showInfoDialog(
        title: 'Connexion impossible',
        message: '$e',
      );
    }
  }

  Future<void> _forgotPassword() async {
    final email = _emailController.text.trim();
    if (email.isEmpty) {
      await _showInfoDialog(
        title: 'E-mail manquant',
        message:
            'Tape d’abord l’adresse e-mail du compte dans le champ ci-dessus, '
            'puis appuie à nouveau sur « Mot de passe oublié ? ».',
      );
      return;
    }

    setState(() => _resetLoading = true);
    try {
      await _authService.sendPasswordResetEmail(email);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => AlertDialog(
          icon: Icon(
            Icons.mark_email_read_outlined,
            color: Theme.of(ctx).colorScheme.primary,
            size: 44,
          ),
          title: const Text('E-mail envoyé'),
          content: Text(
            'Un message a été envoyé à :\n\n$email\n\n'
            '1. Ouvre ta boîte mail (et les indésirables / spam)\n'
            '2. Clique sur le lien dans le mail\n'
            '3. Choisis ton nouveau mot de passe\n\n'
            'Le lien peut mettre 1–2 minutes à arriver.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Compris'),
            ),
          ],
        ),
      );
    } catch (e) {
      if (!mounted) return;
      await _showInfoDialog(
        title: 'Envoi impossible',
        message:
            'Impossible d’envoyer l’e-mail de réinitialisation.\n\n$e\n\n'
            'Vérifie que l’adresse est la bonne, puis réessaie.',
      );
    } finally {
      if (mounted) setState(() => _resetLoading = false);
    }
  }

  Future<void> _showInfoDialog({
    required String title,
    required String message,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
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

  Future<void> _devQuickLogin() async {
    if (!DevAuthConfig.hasAutoLogin) {
      await _showInfoDialog(
        title: 'Mode debug',
        message:
            'Ajoute DEV_TEST_EMAIL et DEV_TEST_PASSWORD dans ton fichier .env',
      );
      return;
    }

    setState(() => _devLoading = true);
    try {
      await _authService.signIn(
        DevAuthConfig.testEmail!,
        DevAuthConfig.testPassword!,
      );
      await _goToApp();
    } catch (e) {
      if (mounted) {
        await _showInfoDialog(title: 'Connexion dev', message: '$e');
      }
    } finally {
      if (mounted) setState(() => _devLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isSignUp ? 'Créer un compte' : 'Connexion')),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              if (_isSignUp)
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: 'Pseudo (ex: Papa)',
                  ),
                ),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: 'Email'),
                keyboardType: TextInputType.emailAddress,
                autocorrect: false,
              ),
              PasswordTextField(controller: _passwordController),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _handleAuth,
                child: Text(_isSignUp ? "S'inscrire" : 'Se connecter'),
              ),
              if (!_isSignUp)
                TextButton(
                  onPressed: _resetLoading ? null : _forgotPassword,
                  child: _resetLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('Mot de passe oublié ?'),
                ),
              TextButton(
                onPressed: () => setState(() => _isSignUp = !_isSignUp),
                child: Text(
                  _isSignUp
                      ? 'Déjà un compte ? Connecte-toi'
                      : 'Pas de compte ? Inscris-toi',
                ),
              ),
              if (DevAuthConfig.isActive) ...[
                const SizedBox(height: 24),
                const Divider(),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _devLoading ? null : _devQuickLogin,
                  icon: _devLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.developer_mode),
                  label: Text(DevAuthConfig.loginButtonLabel),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    DevAuthConfig.hasAutoLogin
                        ? 'Mode debug · connexion auto au démarrage si la session a expiré'
                        : 'Mode debug · configure .env pour éviter de retaper tes identifiants',
                    textAlign: TextAlign.center,
                    style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
