// Proves the Flutter half: the exact JSON the native core emits (captured as a
// golden fixture) parses with the discriminated sealed classes, and renders real
// ink on Flutter's Canvas (Skia/Impeller — a fidelity match for Android).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mermaidkit/mermaid_diagram.dart';
import 'package:mermaidkit/mermaid_painter.dart';
import 'package:mermaidkit/scene_wire.dart';

SceneWire _loadFlowchart() =>
    SceneWire.parse(File('test/fixtures/flowchart.json').readAsStringSync());

void main() {
  test('parses flowchart with discriminated sealed types', () {
    final scene = _loadFlowchart();
    expect(scene.version, 1);
    expect(scene.elements, isNotEmpty);

    // The `type` discriminator lands each element on the right subclass.
    expect(scene.elements.whereType<PolylineElement>(), isNotEmpty);
    expect(scene.elements.whereType<ShapeElement>(), isNotEmpty);
    expect(scene.elements.whereType<TextElement>(), isNotEmpty);

    // Nested discriminated geometry: rounded rect, polygon (diamond), ellipse.
    final paths = scene.elements.whereType<ShapeElement>().map((e) => e.path).toList();
    expect(paths.any((p) => p is RoundedRect), isTrue);
    expect(paths.any((p) => p is Polygon), isTrue);
    expect(paths.any((p) => p is EllipseShape), isTrue);
  });

  test('paints a non-blank image on Flutter Canvas', () async {
    final scene = _loadFlowchart();
    final w = scene.size.w.ceil();
    final h = scene.size.h.ceil();

    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    MermaidPainter(scene).paint(canvas, Size(w.toDouble(), h.toDouble()));
    final image = await recorder.endRecording().toImage(w, h);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    final data = bytes!.buffer.asUint8List();

    // Shapes + strokes + arrowheads land ink regardless of font availability.
    var inked = 0;
    for (var i = 0; i < data.length; i += 4) {
      if (data[i] != 255 || data[i + 1] != 255 || data[i + 2] != 255) inked++;
    }
    expect(inked, greaterThan(300), reason: 'expected drawn ink, got $inked');
  });

  // Env-gated: writes the flowchart render to a PNG for visual inspection
  // (MMK_CAPTURE_DIR=/out flutter test). A no-op in normal CI runs.
  test('captures a flowchart render to PNG', () async {
    final dir = Platform.environment['MMK_CAPTURE_DIR'];
    if (dir == null) return;
    final scene = _loadFlowchart();
    // Optionally load a real font (MMK_FONT=path/to.ttf) and render labels with
    // it — proving the headless "black box" glyphs are just the font-less test
    // font, not a layout bug.
    final fontPath = Platform.environment['MMK_FONT'];
    String? family;
    if (fontPath != null) {
      await ui.loadFontFromList(File(fontPath).readAsBytesSync(), fontFamily: 'MmkFont');
      family = 'MmkFont';
    }
    const scale = 3.0;
    final w = (scene.size.w * scale).ceil();
    final h = (scene.size.h * scale).ceil();
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder)..scale(scale);
    MermaidPainter(scene, fontFamily: family).paint(canvas, Size(scene.size.w, scene.size.h));
    final image = await recorder.endRecording().toImage(w, h);
    final png = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/flutter-flowchart.png').writeAsBytesSync(png!.buffer.asUint8List());
  });

  test('parseSceneColor decodes #RRGGBBAA', () {
    expect(parseSceneColor('#1D1D1F59'), const Color(0x591D1D1F));
    expect(parseSceneColor('#5B8FF9'), const Color(0xFF5B8FF9)); // 6-digit = opaque
  });

  testWidgets('MermaidDiagram composes and sizes by aspect ratio', (tester) async {
    final scene = _loadFlowchart();
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(child: SizedBox(width: 400, child: MermaidDiagram(scene))),
      ),
    );
    expect(find.byType(MermaidDiagram), findsOneWidget);
    expect(find.byType(CustomPaint), findsWidgets);
  });
}
