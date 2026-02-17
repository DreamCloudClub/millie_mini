import 'package:flutter/foundation.dart';
import '../models/face_image.dart';
import 'supabase_service.dart';

/// Service for loading and caching face images from database
class FaceImageService {
  static List<FaceImage>? _cachedFaceImages;

  /// Load all face images from database (cached after first load)
  static Future<List<FaceImage>> loadAll() async {
    if (_cachedFaceImages != null) {
      return _cachedFaceImages!;
    }

    try {
      final response = await SupabaseConfig.client
          .from('face_images')
          .select()
          .order('display_order', ascending: true);

      _cachedFaceImages = (response as List)
          .map((json) => FaceImage.fromJson(json))
          .where((face) => face.imageUrl.isNotEmpty)
          .toList();

      debugPrint('FaceImageService: Loaded ${_cachedFaceImages!.length} face images');
      return _cachedFaceImages!;
    } catch (e) {
      debugPrint('FaceImageService: Error loading face images: $e');
      return [];
    }
  }

  /// Get a face image by ID
  static Future<FaceImage?> getById(String id) async {
    await loadAll();

    for (final face in _cachedFaceImages ?? []) {
      if (face.id == id) {
        return face;
      }
    }
    return null;
  }

  /// Clear the cache (useful for testing or forcing refresh)
  static void clearCache() {
    _cachedFaceImages = null;
  }

  /// Get all face image URLs for caching
  static Future<List<String>> getAllImageUrls() async {
    await loadAll();
    return (_cachedFaceImages ?? [])
        .map((face) => face.imageUrl)
        .where((url) => url.isNotEmpty)
        .toList();
  }
}
