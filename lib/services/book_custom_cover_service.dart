import 'dart:typed_data';

import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Couvertures personnalisées (hors-série) — bucket `book-custom-covers`.
class BookCustomCoverService {
  final _client = Supabase.instance.client;
  final _picker = ImagePicker();

  String? get _userId => _client.auth.currentUser?.id;

  Future<Uint8List?> pickImageBytes() async {
    final picked = await _picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1600,
      imageQuality: 88,
    );
    if (picked == null) return null;
    return picked.readAsBytes();
  }

  Future<String> uploadCover({
    required String seriesId,
    required Uint8List bytes,
    String? volumeId,
  }) async {
    final userId = _userId;
    if (userId == null) throw StateError('Non connecté');

    final stamp = DateTime.now().millisecondsSinceEpoch;
    final suffix = volumeId ?? 'new';
    final path = '$userId/$seriesId/$suffix-$stamp.jpg';

    await _client.storage.from('book-custom-covers').uploadBinary(
          path,
          bytes,
          fileOptions: const FileOptions(
            contentType: 'image/jpeg',
            upsert: true,
          ),
        );

    return _client.storage.from('book-custom-covers').getPublicUrl(path);
  }
}
