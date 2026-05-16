import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'category_selection_screen.dart';

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

      // CORRIGÉ : On vérifie si le widget est encore là avant de naviguer
      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (c) => const CategorySelectionScreen()),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text("Erreur : $e")));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(_isSignUp ? "Créer un compte" : "Connexion")),
      body: Padding(
        padding: const EdgeInsets.all(20.0),
        child: SingleChildScrollView(
          child: Column(
            children: [
              if (_isSignUp)
                TextField(
                  controller: _usernameController,
                  decoration: const InputDecoration(
                    labelText: "Pseudo (ex: Papa)",
                  ),
                ),
              TextField(
                controller: _emailController,
                decoration: const InputDecoration(labelText: "Email"),
              ),
              TextField(
                controller: _passwordController,
                decoration: const InputDecoration(labelText: "Mot de passe"),
                obscureText: true,
              ),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _handleAuth,
                child: Text(_isSignUp ? "S'inscrire" : "Se connecter"),
              ),
              TextButton(
                onPressed: () => setState(() => _isSignUp = !_isSignUp),
                child: Text(
                  _isSignUp
                      ? "Déjà un compte ? Connecte-toi"
                      : "Pas de compte ? Inscris-toi",
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
