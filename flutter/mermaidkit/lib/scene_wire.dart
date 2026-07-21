// The Dart twin of Swift's `SceneWire` — the platform-free wire schema the native
// core emits (`mmk_scene_json`). Pure Dart (no Flutter import): sealed classes +
// a `type` discriminator, parsed with `dart:convert`. Coordinates are points in a
// top-left-origin space; colors are `#RRGGBBAA` strings.

import 'dart:convert';

double _d(Object? v) => (v as num).toDouble();

class ScenePoint {
  final double x, y;
  const ScenePoint(this.x, this.y);
  factory ScenePoint.fromJson(Map<String, dynamic> j) => ScenePoint(_d(j['x']), _d(j['y']));
}

class SceneSize {
  final double w, h;
  const SceneSize(this.w, this.h);
  factory SceneSize.fromJson(Map<String, dynamic> j) => SceneSize(_d(j['w']), _d(j['h']));
}

class SceneRect {
  final double x, y, w, h;
  const SceneRect(this.x, this.y, this.w, this.h);
  factory SceneRect.fromJson(Map<String, dynamic> j) =>
      SceneRect(_d(j['x']), _d(j['y']), _d(j['w']), _d(j['h']));
}

class Stroke {
  final String color;
  final double width;
  final bool dashed;
  const Stroke(this.color, this.width, this.dashed);
  factory Stroke.fromJson(Map<String, dynamic> j) =>
      Stroke(j['color'] as String, _d(j['width']), (j['dashed'] as bool?) ?? false);
}

sealed class ShapePath {
  factory ShapePath.fromJson(Map<String, dynamic> j) => switch (j['type']) {
        'roundedRect' => RoundedRect(SceneRect.fromJson(j['rect']), _d(j['radius'])),
        'ellipse' => EllipseShape(SceneRect.fromJson(j['rect'])),
        'polygon' => Polygon([for (final p in j['points']) ScenePoint.fromJson(p)]),
        'path' => PathShape([for (final v in j['verbs']) PathVerb.fromJson(v)]),
        final other => throw FormatException('unknown ShapePath type "$other"'),
      };
}

class RoundedRect implements ShapePath {
  final SceneRect rect;
  final double radius;
  const RoundedRect(this.rect, this.radius);
}

class EllipseShape implements ShapePath {
  final SceneRect rect;
  const EllipseShape(this.rect);
}

class Polygon implements ShapePath {
  final List<ScenePoint> points;
  const Polygon(this.points);
}

class PathShape implements ShapePath {
  final List<PathVerb> verbs;
  const PathShape(this.verbs);
}

sealed class PathVerb {
  factory PathVerb.fromJson(Map<String, dynamic> j) => switch (j['type']) {
        'move' => MoveVerb(ScenePoint.fromJson(j['point'])),
        'line' => LineVerb(ScenePoint.fromJson(j['point'])),
        'quad' => QuadVerb(ScenePoint.fromJson(j['to']), ScenePoint.fromJson(j['control'])),
        'close' => const CloseVerb(),
        final other => throw FormatException('unknown PathVerb type "$other"'),
      };
}

class MoveVerb implements PathVerb {
  final ScenePoint point;
  const MoveVerb(this.point);
}

class LineVerb implements PathVerb {
  final ScenePoint point;
  const LineVerb(this.point);
}

class QuadVerb implements PathVerb {
  final ScenePoint to, control;
  const QuadVerb(this.to, this.control);
}

class CloseVerb implements PathVerb {
  const CloseVerb();
}

sealed class Element {
  factory Element.fromJson(Map<String, dynamic> j) => switch (j['type']) {
        'shape' => ShapeElement(
            ShapePath.fromJson(j['path']),
            j['fill'] as String?,
            j['stroke'] == null ? null : Stroke.fromJson(j['stroke'])),
        'polyline' => PolylineElement(
            [for (final p in j['points']) ScenePoint.fromJson(p)],
            Stroke.fromJson(j['stroke']),
            (j['startArrow'] as bool?) ?? false,
            (j['endArrow'] as bool?) ?? false),
        'text' => TextElement(
            j['string'] as String,
            ScenePoint.fromJson(j['center']),
            _d(j['fontSize']),
            j['weight'] as String,
            j['color'] as String,
            j['backing'] as String?,
            j['rotation'] == null ? 0.0 : _d(j['rotation'])),
        final other => throw FormatException('unknown Element type "$other"'),
      };
}

class ShapeElement implements Element {
  final ShapePath path;
  final String? fill;
  final Stroke? stroke;
  const ShapeElement(this.path, this.fill, this.stroke);
}

class PolylineElement implements Element {
  final List<ScenePoint> points;
  final Stroke stroke;
  final bool startArrow, endArrow;
  const PolylineElement(this.points, this.stroke, this.startArrow, this.endArrow);
}

class TextElement implements Element {
  final String string;
  final ScenePoint center;
  final double fontSize;
  final String weight;
  final String color;
  final String? backing;
  final double rotation;
  const TextElement(this.string, this.center, this.fontSize, this.weight,
      this.color, this.backing, this.rotation);
}

class SceneWire {
  final int version;
  final SceneSize size;
  final String background;
  final List<Element> elements;
  const SceneWire(this.version, this.size, this.background, this.elements);

  factory SceneWire.fromJson(Map<String, dynamic> j) => SceneWire(
        j['version'] as int,
        SceneSize.fromJson(j['size']),
        j['background'] as String,
        [for (final e in j['elements']) Element.fromJson(e)],
      );

  static SceneWire parse(String jsonText) =>
      SceneWire.fromJson(jsonDecode(jsonText) as Map<String, dynamic>);
}
