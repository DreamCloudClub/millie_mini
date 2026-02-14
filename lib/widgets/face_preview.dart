import 'package:flutter/material.dart';
import '../models/models.dart';
import '../utils/constants.dart';

class FacePreview extends StatelessWidget {
  final FaceColor faceColor;
  final EyeShape eyeShape;
  final double size;
  final bool showBackground;

  const FacePreview({
    super.key,
    required this.faceColor,
    required this.eyeShape,
    this.size = 120,
    this.showBackground = true,
  });

  @override
  Widget build(BuildContext context) {
    final eyeWidth = size * 0.24; // Narrow horizontally - reduced
    final eyeHeight = size * 0.32; // Tall vertically - reduced
    final eyeGap = size * 0.08; // Reduced gap
    final mouthWidth = size * 0.32; // Reduced mouth width
    final mouthHeight = size * 0.025; // Even thinner mouth line
    
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: showBackground ? AppColors.faceBackground : Colors.transparent,
        borderRadius: BorderRadius.circular(size * 0.08), // Reduced face corner radius
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
        borderRadius = width * 0.1; // Reduced eye corner radius
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

