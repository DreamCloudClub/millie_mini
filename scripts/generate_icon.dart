import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Script to generate app icon with Millie's face
/// Run with: flutter run scripts/generate_icon.dart

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Icon specs - needs to be 1024x1024 for flutter_launcher_icons
  const size = 1024.0;
  const faceBackgroundColor = Color(0xFF101316); // AppColors.faceBackground
  const eyeColor = Colors.white;
  const mouthColor = Colors.white;
  
  // Create the face widget
  final faceWidget = Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: faceBackgroundColor,
      borderRadius: BorderRadius.circular(size * 0.15),
    ),
    child: Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        // Eyes (rounded squares)
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildRoundedSquareEye(size * 0.35, eyeColor),
            SizedBox(width: size * 0.1),
            _buildRoundedSquareEye(size * 0.35, eyeColor),
          ],
        ),
        SizedBox(height: size * 0.12),
        // Mouth
        Container(
          width: size * 0.4,
          height: size * 0.08,
          decoration: BoxDecoration(
            color: mouthColor,
            borderRadius: BorderRadius.circular(size * 0.04),
          ),
        ),
      ],
    ),
  );
  
  // Render widget to image
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final sizeConstraints = BoxConstraints.tight(Size(size, size));
  final renderObject = RenderConstrainedBox(
    additionalConstraints: sizeConstraints,
    child: RenderPositionedBox(
      alignment: Alignment.center,
      child: RenderRepaintBoundary(
        child: _WidgetToRenderBoxAdapter(
          widget: faceWidget,
        ),
      ),
    ),
  );
  
  final pipelineOwner = PipelineOwner();
  final buildOwner = BuildOwner();
  final renderView = RenderView(
    view: ui.PlatformDispatcher.instance.views.first,
    child: renderObject,
    configuration: ViewConfiguration(
      size: Size(size, size),
      devicePixelRatio: 1.0,
    ),
  );
  
  pipelineOwner.rootNode = renderView;
  renderView.prepareInitialFrame();
  
  pipelineOwner.flushLayout();
  pipelineOwner.flushCompositingBits();
  pipelineOwner.flushPaint();
  
  final picture = recorder.endRecording();
  final image = await picture.toImage(size.toInt(), size.toInt());
  final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
  
  if (byteData != null) {
    final file = File('assets/icon/icon.png');
    await file.create(recursive: true);
    await file.writeAsBytes(byteData.buffer.asUint8List());
    print('Icon generated successfully at: ${file.path}');
  }
}

Widget _buildRoundedSquareEye(double size, Color color) {
  return Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(size * 0.2), // Rounded squares
      boxShadow: [
        BoxShadow(
          color: color.withOpacity(0.4),
          blurRadius: 8,
          spreadRadius: 2,
        ),
      ],
    ),
  );
}

// Helper class to convert Widget to RenderBox
class _WidgetToRenderBoxAdapter extends RenderBox {
  final Widget widget;
  late RenderBox _renderBox;

  _WidgetToRenderBoxAdapter({required this.widget}) {
    _renderBox = widget.createRenderObject(null) as RenderBox;
    _renderBox.attach(null);
  }

  @override
  void performLayout() {
    _renderBox.layout(constraints, parentUsesSize: true);
    size = _renderBox.size;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    context.paintChild(_renderBox, offset);
  }
}
