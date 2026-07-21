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
> renders labels too.

## Not yet here (next slice)

- **The `dart:ffi` bridge** — `MermaidNative` over `mmk_scene_json` in the Swift
  core built as a shared library, so an app passes a Mermaid *source string*
  (`MermaidNative.scene("flowchart LR\n A --> B")`) rather than a pre-lowered
  scene. The Flutter analogue of the Android JNI and .NET P/Invoke bridges — `dart:ffi`
  calls the same `@_cdecl` C ABI directly.
- Then a `MermaidDiagram.source(...)` convenience + theming across the ABI.
