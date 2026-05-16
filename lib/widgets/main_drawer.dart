import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/auth_service.dart';
import '../screens/login_screen.dart';

class MainDrawer extends StatelessWidget {
  const MainDrawer({super.key});

  @override
  Widget build(BuildContext context) {
    final user = Supabase.instance.client.auth.currentUser;

    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: BoxDecoration(color: Colors.deepPurple.shade400),
            accountName: const Text(
              "Ma Collection Famille",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            accountEmail: Text(user?.email ?? "Non connecté"),
            currentAccountPicture: const CircleAvatar(
              backgroundColor: Colors.white,
              child: Icon(Icons.person, size: 40, color: Colors.deepPurple),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.home),
            title: const Text('Choisir une collection'),
            onTap: () => Navigator.pushReplacementNamed(context, '/categories'),
          ),
          ListTile(
            leading: const Icon(Icons.groups),
            title: const Text('Groupes'),
            onTap: () => Navigator.pushNamed(context, '/groups'),
          ),
          ListTile(
            leading: const Icon(Icons.people),
            title: const Text('Amis'),
            onTap: () => Navigator.pushNamed(context, '/friends'),
          ),
          const Divider(),
          const Spacer(), // Pousse le bouton déconnexion vers le bas
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              "Déconnexion",
              style: TextStyle(color: Colors.red),
            ),
            onTap: () async {
              await AuthService().signOut();
              if (context.mounted) {
                Navigator.pushAndRemoveUntil(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                  (route) => false,
                );
              }
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }
}
