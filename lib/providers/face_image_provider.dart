import 'package:flutter/foundation.dart';
import '../models/face_image.dart';
import '../services/face_image_service.dart';

class FaceImageProvider extends ChangeNotifier {
  List<FaceImage> _faceImages = [];
  bool _isLoading = false;
  String? _error;

  List<FaceImage> get faceImages => _faceImages;
  bool get isLoading => _isLoading;
  String? get error => _error;

  Future<void> init() async {
    _isLoading = true;
    notifyListeners();

    try {
      _faceImages = await FaceImageService.loadAll();
      _error = null;
    } catch (e) {
      debugPrint('FaceImageProvider: Error initializing: $e');
      _error = 'Failed to load face images';
    }

    _isLoading = false;
    notifyListeners();
  }

  FaceImage? getById(String? id) {
    if (id == null) return null;
    try {
      return _faceImages.firstWhere((face) => face.id == id);
    } catch (_) {
      return null;
    }
  }

  Future<void> refresh() async {
    FaceImageService.clearCache();
    await init();
  }
}
