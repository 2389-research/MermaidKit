import 'package:flutter/widgets.dart';
import 'mermaid_painter.dart';
import 'scene_wire.dart';

/// Renders a [SceneWire] as a Flutter widget — the snap-in surface. Sizes to the
/// width it's given, preserving the scene's aspect ratio.
///
/// ```dart
/// MermaidDiagram(scene)   // scene from MermaidNative.scene("flowchart LR\n A --> B")
/// ```
///
/// (The `dart:ffi` bridge to the native core — `MermaidNative` — is the next
/// slice; this renders a `SceneWire` you hand it, mirroring how the Android and
/// .NET renderers landed before their bridges.)
class MermaidDiagram extends StatelessWidget {
  final SceneWire scene;
  const MermaidDiagram(this.scene, {super.key});

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: scene.size.h > 0 ? scene.size.w / scene.size.h : 1.0,
      child: CustomPaint(
        painter: MermaidPainter(scene),
        size: Size.infinite,
      ),
    );
  }
}
