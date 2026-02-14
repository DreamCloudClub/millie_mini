import 'package:flutter/material.dart';
import '../models/models.dart';

class FaceEyes extends StatefulWidget {
  final FaceColor faceColor;
  final EyeShape eyeShape;
  final FaceState faceState;
  final double screenWidth;
  final double screenHeight;

  const FaceEyes({
    super.key,
    required this.faceColor,
    required this.eyeShape,
    required this.faceState,
    required this.screenWidth,
    required this.screenHeight,
  });

  @override
  State<FaceEyes> createState() => _FaceEyesState();
}

class _FaceEyesState extends State<FaceEyes> with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _breathController;
  late Animation<double> _pulseAnimation;
  late Animation<double> _breathAnimation;
  late Animation<double> _opacityAnimation;

  @override
  void initState() {
    super.initState();
    
    // Pulse animation for speaking state
    _pulseController = AnimationController(
      duration: const Duration(milliseconds: 800),
      vsync: this,
    );
    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.06).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );
    
    // Breath animation for listening state
    _breathController = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    );
    _breathAnimation = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _breathController, curve: Curves.easeInOut),
    );
    _opacityAnimation = Tween<double>(begin: 0.85, end: 1.0).animate(
      CurvedAnimation(parent: _breathController, curve: Curves.easeInOut),
    );
    
    _updateAnimations();
  }

  @override
  void didUpdateWidget(FaceEyes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.faceState != widget.faceState) {
      _updateAnimations();
    }
  }

  void _updateAnimations() {
    // Stop all animations first
    _pulseController.stop();
    _breathController.stop();
    
    switch (widget.faceState) {
      case FaceState.idle:
        // Slightly dim static
        break;
      case FaceState.listening:
        // Minimal breathing pulse
        _breathController.repeat(reverse: true);
        break;
      case FaceState.processing:
        // Static, fully bright
        break;
      case FaceState.speaking:
        // Gentle rhythmic pulse
        _pulseController.repeat(reverse: true);
        break;
    }
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _breathController.dispose();
    super.dispose();
  }

  double get _baseOpacity {
    switch (widget.faceState) {
      case FaceState.idle:
        return 0.7;
      case FaceState.listening:
      case FaceState.processing:
      case FaceState.speaking:
        return 1.0;
    }
  }

  double get _glowIntensity {
    switch (widget.faceState) {
      case FaceState.idle:
        return 0.2;
      case FaceState.listening:
        return 0.4;
      case FaceState.processing:
        return 0.5;
      case FaceState.speaking:
        return 0.6;
    }
  }

  @override
  Widget build(BuildContext context) {
    final eyeWidth = widget.screenWidth * 0.32;
    final eyeHeight = widget.screenHeight * 0.28;
    final eyeGap = widget.screenWidth * 0.06;

    return AnimatedBuilder(
      animation: Listenable.merge([_pulseController, _breathController]),
      builder: (context, child) {
        double scale = 1.0;
        double opacity = _baseOpacity;
        
        if (widget.faceState == FaceState.speaking) {
          scale = _pulseAnimation.value;
        } else if (widget.faceState == FaceState.listening) {
          scale = _breathAnimation.value;
          opacity = _opacityAnimation.value;
        }

        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildEye(eyeWidth, eyeHeight, scale, opacity),
            SizedBox(width: eyeGap),
            _buildEye(eyeWidth, eyeHeight, scale, opacity),
          ],
        );
      },
    );
  }

  Widget _buildEye(double width, double height, double scale, double opacity) {
    double borderRadius;
    switch (widget.eyeShape) {
      case EyeShape.circles:
        borderRadius = width / 2;
        break;
      case EyeShape.squares:
        borderRadius = 0;
        break;
      case EyeShape.roundedSquares:
        borderRadius = width * 0.15;
        break;
    }

    return Transform.scale(
      scale: scale,
      child: Opacity(
        opacity: opacity,
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: widget.faceColor.color,
            borderRadius: BorderRadius.circular(borderRadius),
            boxShadow: [
              BoxShadow(
                color: widget.faceColor.color.withOpacity(_glowIntensity),
                blurRadius: 20 * _glowIntensity * 2,
                spreadRadius: 5 * _glowIntensity,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

