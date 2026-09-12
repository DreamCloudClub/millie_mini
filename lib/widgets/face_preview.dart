import 'dart:io';
import 'package:flutter/material.dart';
import '../models/models.dart';
import '../models/custom_face.dart';
import '../services/custom_face_service.dart';
import '../utils/constants.dart';

class FacePreview extends StatelessWidget {
  final FaceColor faceColor;
  final EyeShape eyeShape;
  final String? faceImageId; // Deprecated - kept for compatibility
  final String? customFaceId;
  final double size;
  final bool showBackground;

  const FacePreview({
    super.key,
    required this.faceColor,
    required this.eyeShape,
    this.faceImageId,
    this.customFaceId,
    this.size = 120,
    this.showBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    // Built-in brand faces are bundled assets shown as a centered logo
    final builtIn = CustomFace.builtInById(customFaceId);
    if (builtIn != null) {
      return _buildBuiltInPreview(builtIn);
    }

    // If customFaceId is set, display the custom face image from local storage
    if (customFaceId != null) {
      return _buildCustomFacePreview();
    }

    // Default robot face
    return _buildRobotFace();
  }

  Widget _buildBuiltInPreview(CustomFace face) {
    return Container(
      width: size,
      height: size,
      padding: EdgeInsets.all(size * 0.06),
      decoration: BoxDecoration(
        color: showBackground ? AppColors.faceBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(size * 0.08),
      ),
      child: Image.asset(face.localPath, fit: BoxFit.contain),
    );
  }

  Widget _buildCustomFacePreview() {
    return FutureBuilder<String?>(
      future: CustomFaceService.getLocalPath(customFaceId!),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: showBackground ? AppColors.faceBackground : Colors.transparent,
              borderRadius: BorderRadius.circular(size * 0.08),
            ),
            child: const Center(
              child: CircularProgressIndicator(color: Colors.white54),
            ),
          );
        }

        final localPath = snapshot.data;
        if (localPath == null) {
          // Fallback to robot face if custom face not found
          return _buildRobotFace();
        }

        return Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            color: showBackground ? AppColors.faceBackground : Colors.transparent,
            borderRadius: BorderRadius.circular(size * 0.08),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(size * 0.08),
            child: Image.file(
              File(localPath),
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => _buildRobotFace(),
            ),
          ),
        );
      },
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
