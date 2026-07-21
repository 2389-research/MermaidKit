// Draws a [SceneWire] onto a Flutter [Canvas] — the Dart twin of the Android
// Kotlin and .NET SkiaSharp renderers. Flutter's Canvas is Skia/Impeller, so this
// is a fidelity match for the Android backend. Driven entirely by the
// platform-free scene, so it never learns what a "sequence diagram" is; it paints
// primitives in painter's order, exactly like the SVG backend.

import 'dart:math' as math;
import 'package:flutter/widgets.dart';
import 'scene_wire.dart';

/// Parse a `#RRGGBBAA` (or `#RRGGBB`) wire color into a Flutter [Color].
Color parseSceneColor(String hex) {
  final s = hex.startsWith('#') ? hex.substring(1) : hex;
  final r = int.parse(s.substring(0, 2), radix: 16);
  final g = int.parse(s.substring(2, 4), radix: 16);
  final b = int.parse(s.substring(4, 6), radix: 16);
  final a = s.length >= 8 ? int.parse(s.substring(6, 8), radix: 16) : 255;
  return Color.fromARGB(a, r, g, b);
}

class MermaidPainter extends CustomPainter {
  final SceneWire scene;
  const MermaidPainter(this.scene);

  @override
  void paint(Canvas canvas, Size size) {
    final scale = scene.size.w > 0 ? size.width / scene.size.w : 1.0;
    canvas.save();
    canvas.scale(scale);
    canvas.drawColor(parseSceneColor(scene.background), BlendMode.src);
    for (final element in scene.elements) {
      switch (element) {
        case ShapeElement s:
          _drawShape(s, canvas);
        case PolylineElement p:
          _drawPolyline(p, canvas);
        case TextElement t:
          _drawText(t, canvas);
      }
    }
    canvas.restore();
  }

  // MARK: shapes

  void _drawShape(ShapeElement shape, Canvas canvas) {
    final path = _buildPath(shape.path);
    if (shape.fill != null) {
      canvas.drawPath(path, Paint()
        ..style = PaintingStyle.fill
        ..isAntiAlias = true
        ..color = parseSceneColor(shape.fill!));
    }
    if (shape.stroke != null) {
      canvas.drawPath(path, _strokePaint(shape.stroke!));
    }
  }

  Path _buildPath(ShapePath shape) {
    final path = Path();
    switch (shape) {
      case RoundedRect r:
        path.addRRect(RRect.fromRectAndRadius(
            Rect.fromLTWH(r.rect.x, r.rect.y, r.rect.w, r.rect.h),
            Radius.circular(r.radius)));
      case EllipseShape e:
        path.addOval(Rect.fromLTWH(e.rect.x, e.rect.y, e.rect.w, e.rect.h));
      case Polygon poly:
        if (poly.points.isNotEmpty) {
          path.moveTo(poly.points.first.x, poly.points.first.y);
          for (var i = 1; i < poly.points.length; i++) {
            path.lineTo(poly.points[i].x, poly.points[i].y);
          }
          path.close();
        }
      case PathShape ps:
        for (final v in ps.verbs) {
          switch (v) {
            case MoveVerb m:
              path.moveTo(m.point.x, m.point.y);
            case LineVerb l:
              path.lineTo(l.point.x, l.point.y);
            case QuadVerb q:
              path.quadraticBezierTo(q.control.x, q.control.y, q.to.x, q.to.y);
            case CloseVerb _:
              path.close();
          }
        }
    }
    return path;
  }

  // MARK: polylines (edges + arrowheads)

  void _drawPolyline(PolylineElement line, Canvas canvas) {
    if (line.points.length < 2) return;
    final path = Path()..moveTo(line.points.first.x, line.points.first.y);
    for (var i = 1; i < line.points.length; i++) {
      path.lineTo(line.points[i].x, line.points[i].y);
    }
    canvas.drawPath(path, _strokePaint(line.stroke));

    final ink = parseSceneColor(line.stroke.color);
    if (line.endArrow) {
      _arrowhead(canvas, line.points[line.points.length - 2], line.points.last, ink);
    }
    if (line.startArrow) {
      _arrowhead(canvas, line.points[1], line.points.first, ink);
    }
  }

  void _arrowhead(Canvas canvas, ScenePoint from, ScenePoint tip, Color color) {
    final angle = math.atan2(tip.y - from.y, tip.x - from.x);
    const len = 8.0;
    const spread = 22 * math.pi / 180;
    final path = Path()
      ..moveTo(tip.x, tip.y)
      ..lineTo(tip.x - len * math.cos(angle - spread), tip.y - len * math.sin(angle - spread))
      ..lineTo(tip.x - len * math.cos(angle + spread), tip.y - len * math.sin(angle + spread))
      ..close();
    canvas.drawPath(path, Paint()
      ..style = PaintingStyle.fill
      ..isAntiAlias = true
      ..color = color);
  }

  // MARK: text

  void _drawText(TextElement text, Canvas canvas) {
    final tp = TextPainter(
      text: TextSpan(
        text: text.string,
        style: TextStyle(
          color: parseSceneColor(text.color),
          fontSize: text.fontSize,
          fontWeight: switch (text.weight) {
            'medium' => FontWeight.w500,
            'semibold' => FontWeight.w600,
            _ => FontWeight.w400,
          },
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    canvas.save();
    if (text.rotation != 0) {
      canvas.translate(text.center.x, text.center.y);
      canvas.rotate(text.rotation);
      canvas.translate(-text.center.x, -text.center.y);
    }
    final origin = Offset(text.center.x - tp.width / 2, text.center.y - tp.height / 2);
    if (text.backing != null) {
      canvas.drawRect(
        Rect.fromLTWH(origin.dx - 2, origin.dy, tp.width + 4, tp.height),
        Paint()..color = parseSceneColor(text.backing!),
      );
    }
    tp.paint(canvas, origin);
    canvas.restore();
  }

  Paint _strokePaint(Stroke s) => Paint()
    ..style = PaintingStyle.stroke
    ..isAntiAlias = true
    ..color = parseSceneColor(s.color)
    ..strokeWidth = s.width;

  @override
  bool shouldRepaint(covariant MermaidPainter oldDelegate) => oldDelegate.scene != scene;
}
