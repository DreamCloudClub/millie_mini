import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/models.dart';
import '../providers/providers.dart';
import '../services/image_cache_service.dart';
import '../utils/constants.dart';

class FacePreview extends StatelessWidget {
  final FaceColor faceColor;
  final EyeShape eyeShape;
  final String? faceImageId;
  final double size;
  final bool showBackground;

  const FacePreview({
    super.key,
    required this.faceColor,
    required this.eyeShape,
    this.faceImageId,
    this.size = 120,
    this.showBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    // If faceImageId is set, display the face image
    if (faceImageId != null) {
      return _buildFaceImagePreview(context);
    }

    // Default robot face
    return _buildRobotFace();
  }

  Widget _buildFaceImagePreview(BuildContext context) {
    final faceImageProvider = context.watch<FaceImageProvider>();
    final faceImage = faceImageProvider.getById(faceImageId);

    if (faceImage == null) {
      // Fallback to robot face if image not found
      return _buildRobotFace();
    }

    final localPath = ImageCacheService.getFaceLocalPath(faceImage.imageUrl);

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: showBackground ? AppColors.faceBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(size * 0.08),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.08),
        child: localPath != null
            ? Image.file(
                File(localPath),
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => _buildPlaceholder(faceImage.name),
              )
            : faceImage.imageUrl.isNotEmpty
                ? Image.network(
                    faceImage.imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => _buildPlaceholder(faceImage.name),
                  )
                : _buildPlaceholder(faceImage.name),
      ),
    );
  }

  Widget _buildPlaceholder(String name) {
    return Container(
      color: Colors.grey.shade400,
      child: Center(
        child: Text(
          name.isNotEmpty ? name[0].toUpperCase() : '?',
          style: TextStyle(
            fontSize: size * 0.4,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
      ),
    );
  }

  Widget _buildRobotFace() {
    final eyeWidth = size * 0.24;
    final eyeHeight = size * 0.32;
    final eyeGap = size * 0.08;
    final mouthWidth = size * 0.32;
    final mouthHeight = size * 0.025;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: showBackground ? AppColors.faceBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(size * 0.08),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Eyes
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              _buildEye(eyeWidth, eyeHeight),
              SizedBox(width: eyeGap),
              _buildEye(eyeWidth, eyeHeight),
            ],
          ),
          SizedBox(height: size * 0.12),
          // Mouth
          Container(
            width: mouthWidth,
            height: mouthHeight,
            decoration: BoxDecoration(
              color: faceColor.color,
              borderRadius: BorderRadius.circular(mouthHeight / 2),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEye(double width, double height) {
    double borderRadius;
    switch (eyeShape) {
      case EyeShape.circles:
        borderRadius = width / 2;
        break;
      case EyeShape.squares:
        borderRadius = 0;
        break;
      case EyeShape.roundedSquares:
        borderRadius = width * 0.1;
        break;
    }

    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: faceColor.color,
        borderRadius: BorderRadius.circular(borderRadius),
        boxShadow: [
          BoxShadow(
            color: faceColor.color.withOpacity(0.4),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
    );
  }
}
