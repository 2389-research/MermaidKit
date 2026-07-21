# MermaidKit for Flutter (Dart / CustomPainter renderer)

The Flutter side of MermaidKit. It consumes the platform-free **`SceneWire`** scene
the Swift core emits (`mmk_scene_json`) and paints it on Flutter's `Canvas` with a
`CustomPainter`. Flutter's Canvas is Skia/Impeller — the same engine as the Android
`Canvas` — so this is a fidelity match for the Android backend.

The leverage: **one plugin reaches all of Flutter's targets** — iOS, Android, web,
Windows, macOS, Linux — from a single Dart integration, because Flutter draws its
own UI rather than using native widgets (exactly MermaidKit's model).

```
Swift core ─ mmk_scene_json ─▶ SceneWire JSON ─▶ SceneWire.parse ─▶ MermaidPainter (CustomPainter)
   (C ABI, via dart:ffi)          (the contract)     (sealed classes)      (Skia/Impeller Canvas)
```

## Layout

- `lib/scene_wire.dart` — the wire model: pure-Dart **sealed classes** with a
  `type` discriminator, parsed via `dart:convert`. The Dart analogue of Kotlin's
  `@JsonClassDiscriminator` and the C# converters.
- `lib/mermaid_painter.dart` — `MermaidPainter extends CustomPainter`: draws a
  `SceneWire` onto a `Canvas` — rounded rects / ellipses / polygons / paths,
  stroked + arrowed edge polylines, centered/rotated text (via `TextPainter`).
  Colors are `#RRGGBBAA`.
- `lib/mermaid_diagram.dart` — `MermaidDiagram(scene)`: the widget, sized by the
  scene's aspect ratio.
- `test/scene_render_test.dart` — the golden JSON the core emits parses via the
  sealed classes and renders real ink on Flutter's Canvas (`flutter test`,
  headless via `PictureRecorder`/`toImage`).

## Build & test

```bash
flutter pub get
flutter test
```

> Text in a headless `flutter test` renders as boxes — the test environment ships
> no real font (the standard Flutter "tofu"), same as a headless Skia build. Shapes,
> strokes, and arrowheads render exactly; a real Flutter app (with system fonts)
> renders labels too. Pass `fontFamily:` to `MermaidDiagram`/`MermaidPainter` to
> use a bundled/custom font (and to render text in the font-less test — see the
> `MMK_FONT` path in `scene_render_test.dart`).

## The native bridge (dart:ffi)

`MermaidNative` (`lib/mermaid_native.dart`) is the Flutter analogue of Android's
JNI and .NET's P/Invoke — `dart:ffi` calls the same `@_cdecl` C ABI directly, so a
Flutter app hands over a Mermaid **source string** and gets a scene:

```dart
final scene = MermaidNative.scene("flowchart LR\n A[Start] --> B[End]");
// → CustomPaint(painter: MermaidPainter(scene!))
```

It loads `MermaidKitCShared` (the Swift core built as a shared library —
`swift build --product MermaidKitCShared`; an app bundles the `.so`/`.dylib`/`.dll`
next to its binary, or points at one via the `MMK_LIB` env var). `test/ffi_test.dart`
drives the full seam — source → native → `SceneWire` — verified in CI (a Swift job
builds the lib, the Flutter job tests against it).

## Not yet here (next slice)

- A `MermaidDiagram.source(...)` convenience wrapping `MermaidNative.scene`, and
  theming across the ABI (`mmk_scene_json_themed`, already on the Swift side).
