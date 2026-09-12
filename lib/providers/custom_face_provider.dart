import 'package:flutter/foundation.dart';
import '../models/custom_face.dart';
import '../services/custom_face_service.dart';

class CustomFaceProvider extends ChangeNotifier {
  List<CustomFace> _customFaces = [];
  bool _isLoading = false;
  String? _error;

  List<CustomFace> get customFaces => _customFaces;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      _customFaces = await CustomFaceService.loadAll();
      _error = null;
    } catch (e) {
      debugPrint('CustomFaceProvider: Error initializing: $e');
      _error = 'Failed to load custom faces';
    }

    _isLoading = false;
    notifyListeners();
  }

  /// Get a custom face by ID (synchronous lookup from cache)
  CustomFace? getById(String? id) {
    if (id == null) return null;
    final builtIn = CustomFace.builtInById(id);
    if (builtIn != null) return builtIn;
    try {
      return _customFaces.firstWhere((face) => face.id == id);
    } catch (_) {
      return null;
    }
  }

  /// Get the local file path for a custom face (synchronous)
  String? getLocalPath(String? id) {
    final face = getById(id);
    return face?.localPath;
  }

  /// Refresh the cache from storage
  Future<void> refresh() async {
    await init();
  }
}
