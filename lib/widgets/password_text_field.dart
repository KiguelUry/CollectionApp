import 'package:flutter/material.dart';

/// Champ mot de passe avec icône œil pour afficher / masquer.
class PasswordTextField extends StatefulWidget {
  final TextEditingController controller;
  final String labelText;
  final String? hintText;
  final void Function(String)? onSubmitted;

  const PasswordTextField({
    super.key,
    required this.controller,
    this.labelText = 'Mot de passe',
    this.hintText,
    this.onSubmitted,
  });

  @override
  State<PasswordTextField> createState() => _PasswordTextFieldState();
}

class _PasswordTextFieldState extends State<PasswordTextField> {
  bool _visible = false;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: widget.controller,
      obscureText: !_visible,
      autocorrect: false,
      enableSuggestions: false,
      onSubmitted: widget.onSubmitted,
      decoration: InputDecoration(
        labelText: widget.labelText,
        hintText: widget.hintText,
        suffixIcon: IconButton(
          icon: Icon(
            _visible ? Icons.visibility_outlined : Icons.visibility_off_outlined,
          ),
          tooltip: _visible ? 'Masquer' : 'Afficher',
          onPressed: () => setState(() => _visible = !_visible),
        ),
      ),
    );
  }
}
