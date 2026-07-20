# MermaidKit for Android (Kotlin rendering half)

The Kotlin side of the Android bridge described in
[`docs/notes/android.md`](../docs/notes/android.md). It consumes the
platform-free **`SceneWire`** scene the Swift core emits (`mmk_scene_json` in the
`MermaidKitC` C ABI) and draws it with a real Android `Canvas`/`Paint`.

```
Swift core ─ mmk_scene_json ─▶ SceneWire JSON ─▶ SceneWire.parse ─▶ SceneRenderer.draw(canvas)
   (C ABI, per-ABI .so)          (the contract)      (this module — @Serializable, no glue)
```

Because [`RenderScene`](../Sources/MermaidLayout/RenderScene.swift) flattens all
30 diagram types into a tiny universal vocabulary (shape / polyline / text + a
theme), this module never needs to know what a "sequence diagram" is — it just
paints primitives in painter's order, exactly like the SVG backend.

![A flowchart rendered by SceneRenderer on an android-34 emulator](docs/on-device-render.png)

*Above: a flowchart drawn by `SceneRenderer` through a real android-34 emulator's
Skia `Canvas`, from the `SceneWire` JSON the Swift pipeline emitted — captured by
the instrumented test (`connectedDebugAndroidTest`).*

## Layout

- `mermaidkit/src/main/kotlin/ai/mermaidkit/scene/SceneWire.kt` — the wire model:
  plain `@Serializable` data classes with a `type` discriminator. Deserializes
  the exact JSON the C ABI emits with **zero custom serializers**.
- `mermaidkit/src/main/kotlin/ai/mermaidkit/scene/SceneRenderer.kt` — draws a
  `SceneWire` onto a `Canvas`: rounded rects / ellipses / polygons / arbitrary
  paths, stroked+arrowed edge polylines, and centered/rotated text with backing
  chips. Colors are `#RRGGBBAA` (8-bit, what Skia draws at); text is measured
  with the same `Paint` that draws it (the measure seam the C ABI callback pins).
- `mermaidkit/src/test/…/SceneWireTest.kt` — JVM unit tests that parse golden
  JSON captured from the real pipeline (`src/test/resources/*.json`).
- `mermaidkit/src/androidTest/…/RenderInstrumentedTest.kt` — the on-device proof:
  draws a scene through the emulator's Skia `Canvas` and asserts real ink lands.

## Build & test

```bash
# Library AAR + JVM unit tests + instrumented-test APK (no device needed):
./gradlew :mermaidkit:assembleDebug :mermaidkit:testDebugUnitTest :mermaidkit:assembleDebugAndroidTest

# On-device render test (needs a running emulator / device, i.e. KVM):
./gradlew :mermaidkit:connectedDebugAndroidTest
```

CI runs the first line on a native x86_64 runner (AAPT2 ships x86_64 only) and
the instrumented test on a KVM-accelerated android-34 emulator — see
`.github/workflows/ci.yml`.

## Not yet here (next slices)

- **JNI + the `.so`.** This module renders a `SceneWire` you hand it; wiring
  Kotlin → JNI → `mmk_scene_json` → the per-ABI `.so` (so the app passes a
  Mermaid *source* string and a `Paint.measureText` callback) is the next step,
  along with bundling the NDK-built `.so` into the AAR.
- **Compose / View wrappers, `MermaidTheme.fromMaterial()`, `contentDescription`
  from the narration, `onNodeClick` hit-testing** — the snap-in surface.
