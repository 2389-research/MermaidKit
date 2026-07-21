// The dart:ffi seam end-to-end: a Mermaid source string → the native `mmk_*` C
// ABI in the Swift core (a shared library) → a `SceneWire`. Runs only where the
// native library is available (`MMK_LIB` set); soft-skips otherwise, unless
// `MMK_NATIVE=1` forces it (so a broken native path fails rather than passing).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:mermaidkit/mermaid_native.dart';
import 'package:mermaidkit/scene_wire.dart';

bool get _require => Platform.environment['MMK_NATIVE'] == '1';

/// The version string, or null to signal "native absent, skip" (unless required).
String? _tryNative() {
  try {
    return MermaidNative.version();
  } catch (e) {
    if (_require) rethrow;
    return null;
  }
}

void main() {
  const source = 'flowchart LR\n A[Start] --> B{Choice}\n B -->|yes| C((Done))';

  test('version loads through dart:ffi', () {
    final v = _tryNative();
    if (v == null) return;
    expect(v, contains('MermaidKitC'));
  });

  test('source string → SceneWire through dart:ffi', () {
    if (_tryNative() == null) return;
    final json = MermaidNative.sceneJson(source);
    expect(json, isNotNull);
    expect(json, contains('"type":"polyline"'));
    expect(json, contains('"type":"shape"'));

    final scene = MermaidNative.scene(source);
    expect(scene, isNotNull);
    expect(scene!.elements.whereType<ShapeElement>(), isNotEmpty);
    expect(scene.elements.whereType<PolylineElement>(), isNotEmpty);
  });

  test('narrate threads through dart:ffi', () {
    if (_tryNative() == null) return;
    final narration = MermaidNative.narrate(source);
    expect(narration, isNotNull);
    expect(narration, contains('Start'));
  });

  test('invalid source returns null', () {
    if (_tryNative() == null) return;
    expect(MermaidNative.sceneJson('not a diagram at all'), isNull);
  });
}
