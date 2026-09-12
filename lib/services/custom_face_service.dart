import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import '../models/custom_face.dart';
import 'openai_service.dart';
import 'storage_service.dart';

/// Service for managing custom faces (local storage)
class CustomFaceService {
  static const String _prefsKey = 'custom_faces';
  static const String _facesDirName = 'custom_faces';

  /// Standard prompt prepended to all face generation requests
  static const String standardPrompt = '''Portrait orientation. Extreme close-up of the face filling the entire frame. No background. No visible body, neck, shoulders, chest, torso, or head outline. The image must contain only a face. Eyes centered horizontally and positioned slightly above the vertical midpoint. Nose centered. Mouth slightly below the nose. Symmetrical composition. Friendly, approachable expression unless specified otherwise. Soft, even front lighting. No dramatic shadows. Clean cartoon style. High clarity and vibrant color. All areas outside of eyes, nose, and mouth must be filled with appropriate surface texture (fur, skin, scales, metal, fabric, etc.) based on the subject. Subject: ''';

  /// Get the custom faces directory
  static Future<Directory> _getFacesDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final facesDir = Directory('${appDir.path}/$_facesDirName');
    if (!await facesDir.exists()) {
      await facesDir.create(recursive: true);
    }
    return facesDir;
  }

  /// Load all custom faces from local storage
  static Future<List<CustomFace>> loadAll() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final jsonString = prefs.getString(_prefsKey);
      if (jsonString == null) return [];

      final List<dynamic> jsonList = json.decode(jsonString);
      final faces = jsonList
          .map((j) => CustomFace.fromJson(j as Map<String, dynamic>))
          .toList();

      // Filter out faces whose files no longer exist
      final validFaces = <CustomFace>[];
      for (final face in faces) {
        if (await File(face.localPath).exists()) {
          validFaces.add(face);
        }
      }

      // Update storage if we filtered any out
      if (validFaces.length != faces.length) {
        await _saveFacesList(validFaces);
      }

      return validFaces;
    } catch (e) {
      debugPrint('Error loading custom faces: $e');
      return [];
    }
  }

  /// Save the faces list to SharedPreferences
  static Future<void> _saveFacesList(List<CustomFace> faces) async {
    final prefs = await SharedPreferences.getInstance();
    final jsonList = faces.map((f) => f.toJson()).toList();
    await prefs.setString(_prefsKey, json.encode(jsonList));
  }

  /// Generate a face image using DALL-E
  static Future<String?> generateFace(String userDescription) async {
    try {
      final storageService = StorageService();
      await storageService.init();
      final openaiService = OpenAIService(storageService);

      // Combine standard prompt with user description
      final fullPrompt = '$standardPrompt$userDescription';
      debugPrint('Generating face with prompt: $fullPrompt');

      // Generate image (square format for faces)
      // Generate portrait image (1024x1792 for DALL-E 3)
      final imageUrl = await openaiService.generateImage(
        prompt: fullPrompt,
        size: '1024x1792',
      );
      return imageUrl;
    } catch (e) {
      debugPrint('Error generating face: $e');
      return null;
    }
  }

  /// Save a generated face locally
  static Future<CustomFace?> saveFace({
    required String imageUrl,
    required String description,
  }) async {
    try {
      // Download the image
      final response = await http.get(Uri.parse(imageUrl));
      if (response.statusCode != 200) {
        throw Exception('Failed to download face image');
      }

      // Generate unique ID
      final id = DateTime.now().millisecondsSinceEpoch.toString();

      // Save to local file
      final facesDir = await _getFacesDir();
      final filePath = '${facesDir.path}/$id.png';
      final file = File(filePath);
      await file.writeAsBytes(response.bodyBytes);

      // Create face object
      final face = CustomFace(
        id: id,
        description: description,
        localPath: filePath,
        createdAt: DateTime.now(),
      );

      // Add to saved list
      final faces = await loadAll();
      faces.add(face);
      await _saveFacesList(faces);

      debugPrint('Saved custom face: $id at $filePath');
      return face;
    } catch (e) {
      debugPrint('Error saving custom face: $e');
      return null;
    }
  }

  /// Delete a custom face
  static Future<bool> deleteFace(String id) async {
    if (CustomFace.builtInById(id) != null) return false;
    try {
      final faces = await loadAll();
      final faceIndex = faces.indexWhere((f) => f.id == id);
      if (faceIndex == -1) return false;

      final face = faces[faceIndex];

      // Delete the file
      final file = File(face.localPath);
      if (await file.exists()) {
        await file.delete();
      }

      // Remove from list and save
      faces.removeAt(faceIndex);
      await _saveFacesList(faces);

      debugPrint('Deleted custom face: $id');
      return true;
    } catch (e) {
      debugPrint('Error deleting custom face: $e');
      return false;
    }
  }

  /// Get a face by ID
  static Future<CustomFace?> getById(String id) async {
    final builtIn = CustomFace.builtInById(id);
    if (builtIn != null) return builtIn;
    final faces = await loadAll();
    try {
      return faces.firstWhere((f) => f.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get the local file path for a custom face
  static Future<String?> getLocalPath(String id) async {
    // Built-ins are bundled assets, not files on disk
    final builtIn = CustomFace.builtInById(id);
    if (builtIn != null) return builtIn.localPath;
    final face = await getById(id);
    if (face != null && await File(face.localPath).exists()) {
      return face.localPath;
    }
    return null;
  }
}
