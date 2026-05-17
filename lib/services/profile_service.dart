import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/user_profile.dart';

class ProfileService {
  final _client = Supabase.instance.client;
  final _picker = ImagePicker();

  String? get _userId => _client.auth.currentUser?.id;

  Future<UserProfile> fetchCurrentProfile() async {
    final id = _userId;
    if (id == null) throw Exception('Non connecté');

    final row = await _client.from('profiles').select().eq('id', id).single();
    return UserProfile.fromJson(Map<String, dynamic>.from(row));
  }

  Future<UserProfile> fetchProfile(String profileId) async {
    final row =
        await _client.from('profiles').select().eq('id', profileId).single();
    return UserProfile.fromJson(Map<String, dynamic>.from(row));
  }

  Future<UserProfile> updateProfile(UserProfile profile) async {
    final id = _userId;
    if (id == null || id != profile.id) {
      throw Exception('Modification non autorisée');
    }

    final row = await _client
        .from('profiles')
        .update(profile.toUpdateJson())
        .eq('id', id)
        .select()
        .single();

    return UserProfile.fromJson(Map<String, dynamic>.from(row));
  }

  /// Choisit une image (galerie) et l'envoie dans Storage `avatars/{userId}/avatar.jpg`.
  Future<String> pickAndUploadAvatar() async {
    final id = _userId;
    if (id == null) throw Exception('Non connecté');

    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 512,
      maxHeight: 512,
      imageQuality: 85,
    );
    if (picked == null) {
      throw Exception('Aucune image sélectionnée');
    }

    final bytes = await picked.readAsBytes();
    return uploadAvatarBytes(bytes);
  }

  Future<String> uploadAvatarBytes(Uint8List bytes) async {
    final id = _userId;
    if (id == null) throw Exception('Non connecté');

    final path = '$id/avatar.jpg';
    await _client.storage.from('avatars').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            upsert: true,
            contentType: 'image/jpeg',
          ),
        );

    final publicUrl = _client.storage.from('avatars').getPublicUrl(path);
    // Cache-bust pour forcer le rafraîchissement après remplacement
    return '$publicUrl?v=${DateTime.now().millisecondsSinceEpoch}';
  }

  Future<void> removeAvatar() async {
    final id = _userId;
    if (id == null) throw Exception('Non connecté');

    try {
      await _client.storage.from('avatars').remove(['$id/avatar.jpg']);
    } catch (_) {
      // Fichier peut ne pas exister
    }

    await _client
        .from('profiles')
        .update({'avatar_url': null})
        .eq('id', id);
  }
}
