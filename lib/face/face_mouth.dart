import 'package:flutter/material.dart';
import '../models/models.dart';

class FaceMouth extends StatefulWidget {
  final FaceState faceState;
  final double screenWidth;
  final FaceColor faceColor;

  const FaceMouth({
    super.key,
    required this.faceState,
    required this.screenWidth,
    required this.faceColor,
  });

  @override
  State<FaceMouth> createState() => _FaceMouthState();
}

class _FaceMouthState extends State<FaceMouth> with SingleTickerProviderStateMixin {
  late AnimationController _glowController;
  late Animation<double> _glowAnimation;

  @override
  void initState() {
    super.initState();
    
    _glowController = AnimationController(
      duration: const Duration(milliseconds: 600),
      vsync: this,
    );
    
    _glowAnimation = Tween<double>(begin: 0.3, end: 0.6).animate(
      CurvedAnimation(parent: _glowController, curve: Curves.easeInOut),
    );
    
    _updateAnimation();
  }

  @override
  void didUpdateWidget(FaceMouth oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.faceState != widget.faceState) {
      _updateAnimation();
    }
  }

  void _updateAnimation() {
    if (widget.faceState == FaceState.speaking) {
      _glowController.repeat(reverse: true);
    } else {
      _glowController.stop();
      _glowController.value = 0;
    }
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  double get _baseOpacity {
    switch (widget.faceState) {
      case FaceState.idle:
        return 0.6;
      case FaceState.listening:
      case FaceState.processing:
        return 0.8;
      case FaceState.speaking:
        return 1.0;
    }
  }

  @override
  Widget build(BuildContext context) {
    final mouthWidth = widget.screenWidth * 0.50;
    const mouthHeight = 16.0; // Thicker mouth for main face page

    return AnimatedBuilder(
      animation: _glowController,
      builder: (context, child) {
        final glowIntensity = widget.faceState == FaceState.speaking
            ? _glowAnimation.value
            : 0.2;

        final mouthColor = widget.faceColor.color;
        return Opacity(
          opacity: _baseOpacity,
          child: Container(
            width: mouthWidth,
            height: mouthHeight,
            decoration: BoxDecoration(
              color: mouthColor,
              borderRadius: BorderRadius.circular(mouthHeight / 2),
              boxShadow: [
                BoxShadow(
                  color: mouthColor.withOpacity(glowIntensity),
                  blurRadius: 15,
                  spreadRadius: 2,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

