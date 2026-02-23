import 'dart:io';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:crypto/crypto.dart';
import 'supabase_service.dart';
import 'face_image_service.dart';

/// Service for caching animal, face, and food images locally
class ImageCacheService {
  static const String _cacheDir = 'animal_images';
  static const String _faceCacheDir = 'face_images';
  static const String _foodCacheDir = 'food_images';
  static const String _manifestFile = 'manifest.json';

  static Directory? _cacheDirectory;
  static Directory? _faceCacheDirectory;
  static Directory? _foodCacheDirectory;
  static Map<String, String> _manifest = {}; // url -> local filename
  static Map<String, String> _faceManifest = {}; // url -> local filename for faces
  static Map<String, String> _foodManifest = {}; // url -> local filename for foods
  static bool _isInitialized = false;
  static bool _isSyncing = false;
  static bool _isSyncingFaces = false;
  static bool _isSyncingFoods = false;

  /// Initialize the cache directory and load manifest
  static Future<void> init() async {
    if (_isInitialized) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      _cacheDirectory = Directory('${appDir.path}/$_cacheDir');
      _faceCacheDirectory = Directory('${appDir.path}/$_faceCacheDir');
      _foodCacheDirectory = Directory('${appDir.path}/$_foodCacheDir');

      if (!await _cacheDirectory!.exists()) {
        await _cacheDirectory!.create(recursive: true);
      }
      if (!await _faceCacheDirectory!.exists()) {
        await _faceCacheDirectory!.create(recursive: true);
      }
      if (!await _foodCacheDirectory!.exists()) {
        await _foodCacheDirectory!.create(recursive: true);
      }

      await _loadManifest();
      await _loadFaceManifest();
      await _loadFoodManifest();
      _isInitialized = true;
      debugPrint('ImageCacheService: Initialized with ${_manifest.length} animal, ${_faceManifest.length} face, ${_foodManifest.length} food images');
    } catch (e) {
      debugPrint('ImageCacheService: Error initializing: $e');
    }
  }

  /// Load the manifest file that tracks cached images
  static Future<void> _loadManifest() async {
    try {
      final manifestPath = '${_cacheDirectory!.path}/$_manifestFile';
      final file = File(manifestPath);

      if (await file.exists()) {
        final contents = await file.readAsString();
        final decoded = json.decode(contents) as Map<String, dynamic>;
        _manifest = decoded.map((k, v) => MapEntry(k, v as String));
      }
    } catch (e) {
      debugPrint('ImageCacheService: Error loading manifest: $e');
      _manifest = {};
    }
  }

  /// Save the manifest file
  static Future<void> _saveManifest() async {
    try {
      final manifestPath = '${_cacheDirectory!.path}/$_manifestFile';
      final file = File(manifestPath);
      await file.writeAsString(json.encode(_manifest));
    } catch (e) {
      debugPrint('ImageCacheService: Error saving manifest: $e');
    }
  }

  /// Load the face manifest file
  static Future<void> _loadFaceManifest() async {
    try {
      final manifestPath = '${_faceCacheDirectory!.path}/$_manifestFile';
      final file = File(manifestPath);

      if (await file.exists()) {
        final contents = await file.readAsString();
        final decoded = json.decode(contents) as Map<String, dynamic>;
        _faceManifest = decoded.map((k, v) => MapEntry(k, v as String));
      }
    } catch (e) {
      debugPrint('ImageCacheService: Error loading face manifest: $e');
      _faceManifest = {};
    }
  }

  /// Save the face manifest file
  static Future<void> _saveFaceManifest() async {
    try {
      final manifestPath = '${_faceCacheDirectory!.path}/$_manifestFile';
      final file = File(manifestPath);
      await file.writeAsString(json.encode(_faceManifest));
    } catch (e) {
      debugPrint('ImageCacheService: Error saving face manifest: $e');
    }
  }

  /// Load the food manifest file
  static Future<void> _loadFoodManifest() async {
    try {
      final manifestPath = '${_foodCacheDirectory!.path}/$_manifestFile';
      final file = File(manifestPath);

      if (await file.exists()) {
        final contents = await file.readAsString();
        final decoded = json.decode(contents) as Map<String, dynamic>;
        _foodManifest = decoded.map((k, v) => MapEntry(k, v as String));
      }
    } catch (e) {
      debugPrint('ImageCacheService: Error loading food manifest: $e');
      _foodManifest = {};
    }
  }

  /// Save the food manifest file
  static Future<void> _saveFoodManifest() async {
    try {
      final manifestPath = '${_foodCacheDirectory!.path}/$_manifestFile';
      final file = File(manifestPath);
      await file.writeAsString(json.encode(_foodManifest));
    } catch (e) {
      debugPrint('ImageCacheService: Error saving food manifest: $e');
    }
  }

  /// Generate a filename from URL using hash
  static String _getFilename(String url) {
    final hash = md5.convert(utf8.encode(url)).toString();
    final extension = url.split('.').last.split('?').first;
    return '$hash.$extension';
  }

  /// Get local path for a URL (returns null if not cached)
  static String? getLocalPath(String? url) {
    if (url == null || url.isEmpty) return null;
    if (!_isInitialized) return null;

    final filename = _manifest[url];
    if (filename == null) return null;

    final path = '${_cacheDirectory!.path}/$filename';
    return path;
  }

  /// Get local path for a face image URL (returns null if not cached)
  static String? getFaceLocalPath(String? url) {
    if (url == null || url.isEmpty) return null;
    if (!_isInitialized) return null;

    final filename = _faceManifest[url];
    if (filename == null) return null;

    final path = '${_faceCacheDirectory!.path}/$filename';
    return path;
  }

  /// Check if an image is cached
  static bool isCached(String? url) {
    if (url == null || url.isEmpty) return false;
    return _manifest.containsKey(url);
  }

  /// Check if a face image is cached
  static bool isFaceCached(String? url) {
    if (url == null || url.isEmpty) return false;
    return _faceManifest.containsKey(url);
  }

  /// Get local path for a food image URL (returns null if not cached)
  static String? getFoodLocalPath(String? url) {
    if (url == null || url.isEmpty) return null;
    if (!_isInitialized) return null;

    final filename = _foodManifest[url];
    if (filename == null) return null;

    final path = '${_foodCacheDirectory!.path}/$filename';
    return path;
  }

  /// Check if a food image is cached
  static bool isFoodCached(String? url) {
    if (url == null || url.isEmpty) return false;
    return _foodManifest.containsKey(url);
  }

  /// Sync all animal images from database
  /// Runs in background, doesn't block UI
  static Future<void> syncAnimalImages() async {
    if (_isSyncing) {
      debugPrint('ImageCacheService: Sync already in progress');
      return;
    }

    if (!_isInitialized) {
      await init();
    }

    _isSyncing = true;
    debugPrint('ImageCacheService: Starting sync...');

    try {
      // Fetch all animal image URLs from database
      final response = await SupabaseConfig.client
          .from('animals')
          .select('id, image_url');

      final animals = response as List;
      int downloaded = 0;
      int skipped = 0;

      for (final animal in animals) {
        final imageUrl = animal['image_url'] as String?;
        if (imageUrl == null || imageUrl.isEmpty) continue;

        // Check if already cached
        if (_manifest.containsKey(imageUrl)) {
          final localPath = '${_cacheDirectory!.path}/${_manifest[imageUrl]}';
          if (await File(localPath).exists()) {
            skipped++;
            continue;
          }
        }

        // Download and cache
        final success = await _downloadImage(imageUrl);
        if (success) {
          downloaded++;
        }
      }

      await _saveManifest();
      debugPrint('ImageCacheService: Sync complete - downloaded: $downloaded, skipped: $skipped');
    } catch (e) {
      debugPrint('ImageCacheService: Error syncing: $e');
    } finally {
      _isSyncing = false;
    }
  }

  /// Sync all face images from database
  /// Runs in background, doesn't block UI
  static Future<void> syncFaceImages() async {
    if (_isSyncingFaces) {
      debugPrint('ImageCacheService: Face sync already in progress');
      return;
    }

    if (!_isInitialized) {
      await init();
    }

    _isSyncingFaces = true;
    debugPrint('ImageCacheService: Starting face image sync...');

    try {
      // Fetch all face image URLs from service
      final imageUrls = await FaceImageService.getAllImageUrls();
      int downloaded = 0;
      int skipped = 0;

      for (final imageUrl in imageUrls) {
        if (imageUrl.isEmpty) continue;

        // Check if already cached
        if (_faceManifest.containsKey(imageUrl)) {
          final localPath = '${_faceCacheDirectory!.path}/${_faceManifest[imageUrl]}';
          if (await File(localPath).exists()) {
            skipped++;
            continue;
          }
        }

        // Download and cache
        final success = await _downloadFaceImage(imageUrl);
        if (success) {
          downloaded++;
        }
      }

      await _saveFaceManifest();
      debugPrint('ImageCacheService: Face sync complete - downloaded: $downloaded, skipped: $skipped');
    } catch (e) {
      debugPrint('ImageCacheService: Error syncing faces: $e');
    } finally {
      _isSyncingFaces = false;
    }
  }

  /// Sync all food images from database
  /// Runs in background, doesn't block UI
  static Future<void> syncFoodImages() async {
    if (_isSyncingFoods) {
      debugPrint('ImageCacheService: Food sync already in progress');
      return;
    }

    if (!_isInitialized) {
      await init();
    }

    _isSyncingFoods = true;
    debugPrint('ImageCacheService: Starting food image sync...');

    try {
      // Fetch all food image URLs from database
      final response = await SupabaseConfig.client
          .from('foods')
          .select('id, image_url');

      final foods = response as List;
      int downloaded = 0;
      int skipped = 0;

      for (final food in foods) {
        final imageUrl = food['image_url'] as String?;
        if (imageUrl == null || imageUrl.isEmpty) continue;

        // Check if already cached
        if (_foodManifest.containsKey(imageUrl)) {
          final localPath = '${_foodCacheDirectory!.path}/${_foodManifest[imageUrl]}';
          if (await File(localPath).exists()) {
            skipped++;
            continue;
          }
        }

        // Download and cache
        final success = await _downloadFoodImage(imageUrl);
        if (success) {
          downloaded++;
        }
      }

      await _saveFoodManifest();
      debugPrint('ImageCacheService: Food sync complete - downloaded: $downloaded, skipped: $skipped');
    } catch (e) {
      debugPrint('ImageCacheService: Error syncing foods: $e');
    } finally {
      _isSyncingFoods = false;
    }
  }

  /// Download a food image and cache it
  static Future<bool> _downloadFoodImage(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        debugPrint('ImageCacheService: Failed to download food $url (${response.statusCode})');
        return false;
      }

      final filename = _getFilename(url);
      final localPath = '${_foodCacheDirectory!.path}/$filename';
      final file = File(localPath);
      await file.writeAsBytes(response.bodyBytes);

      _foodManifest[url] = filename;
      return true;
    } catch (e) {
      debugPrint('ImageCacheService: Error downloading food $url: $e');
      return false;
    }
  }

  /// Download a face image and cache it
  static Future<bool> _downloadFaceImage(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        debugPrint('ImageCacheService: Failed to download face $url (${response.statusCode})');
        return false;
      }

      final filename = _getFilename(url);
      final localPath = '${_faceCacheDirectory!.path}/$filename';
      final file = File(localPath);
      await file.writeAsBytes(response.bodyBytes);

      _faceManifest[url] = filename;
      return true;
    } catch (e) {
      debugPrint('ImageCacheService: Error downloading face $url: $e');
      return false;
    }
  }

  /// Download a single image and cache it
  static Future<bool> _downloadImage(String url) async {
    try {
      final response = await http.get(Uri.parse(url));
      if (response.statusCode != 200) {
        debugPrint('ImageCacheService: Failed to download $url (${response.statusCode})');
        return false;
      }

      final filename = _getFilename(url);
      final localPath = '${_cacheDirectory!.path}/$filename';
      final file = File(localPath);
      await file.writeAsBytes(response.bodyBytes);

      _manifest[url] = filename;
      return true;
    } catch (e) {
      debugPrint('ImageCacheService: Error downloading $url: $e');
      return false;
    }
  }

  /// Clear all cached images
  static Future<void> clearCache() async {
    if (!_isInitialized) return;

    try {
      if (await _cacheDirectory!.exists()) {
        await _cacheDirectory!.delete(recursive: true);
        await _cacheDirectory!.create(recursive: true);
      }
      _manifest.clear();
      await _saveManifest();
      debugPrint('ImageCacheService: Cache cleared');
    } catch (e) {
      debugPrint('ImageCacheService: Error clearing cache: $e');
    }
  }

  /// Get cache size in bytes
  static Future<int> getCacheSize() async {
    if (!_isInitialized || _cacheDirectory == null) return 0;

    try {
      int totalSize = 0;
      await for (final entity in _cacheDirectory!.list()) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }
      return totalSize;
    } catch (e) {
      return 0;
    }
  }
}
