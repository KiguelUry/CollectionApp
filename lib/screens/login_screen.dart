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

  @override
  void initState() {
    super.initState();
    if (DevAuthConfig.testEmail != null) {
      _emailController.text = DevAuthConfig.testEmail!;
    }
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Erreur : $e')),
      );
    }
  }

  Future<void> _devQuickLogin() async {
    if (!DevAuthConfig.hasAutoLogin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Ajoute DEV_TEST_EMAIL et DEV_TEST_PASSWORD dans ton fichier .env',
          ),
        ),
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Connexion dev : $e')),
        );
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
