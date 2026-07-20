# MermaidKit for Android (Kotlin rendering half)

The Android bridge described in [`docs/notes/android.md`](../docs/notes/android.md).
An app hands over a Mermaid **source string**; `MermaidNative` parses it natively
(JNI → the Swift `mmk_*` C ABI in `libmermaidkit.so`) into a platform-free
**`SceneWire`** scene, and `SceneRenderer` draws it with a real Android
`Canvas`/`Paint`.

```
source ─▶ MermaidNative ─(JNI)▶ mmk_scene_json ─▶ SceneWire JSON ─▶ SceneWire.parse ─▶ SceneRenderer.draw(canvas)
 (app)     (this module)     (Swift core, libmermaidkit.so)          (the contract)     (@Serializable, no glue)
```

Because [`RenderScene`](../Sources/MermaidLayout/RenderScene.swift) flattens all
30 diagram types into a tiny universal vocabulary (shape / polyline / text + a
theme), this module never needs to know what a "sequence diagram" is — it just
paints primitives in painter's order, exactly like the SVG backend.

## Rendering a diagram (the snap-in surface)

Compose:

```kotlin
MermaidDiagram(
    source = "flowchart LR\n  A[Start] --> B{Choice}\n  B -->|yes| C((Done))",
    modifier = Modifier.fillMaxWidth(),
)   // sizes to width, follows the system theme, narration → contentDescription
```

Classic View (no Compose dependency):

```kotlin
val view = MermaidView(context)
view.source = "flowchart LR\n A[Start] --> B[End]"   // that's it — parses, sizes, draws
```

Both go source → native parse → `SceneWire` → `Canvas`, measure text with the
drawing `Paint`, and set the diagram's accessibility narration as
`contentDescription`. For lower-level control, `MermaidNative.scene(source,
measurer = PaintMeasurer(paint))` returns a `SceneWire` you draw yourself with
`SceneRenderer`.

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
- `mermaidkit/src/main/kotlin/ai/mermaidkit/MermaidNative.kt` — the native bridge:
  `System.loadLibrary("mermaidkit")` + `external fun`s over the `mmk_*` C ABI.
  `MermaidNative.scene(source)` goes straight from a source string to a `SceneWire`.
  `PaintMeasurer.kt` backs the measure seam with an Android `Paint`.
- `mermaidkit/src/main/kotlin/ai/mermaidkit/MermaidView.kt` /
  `MermaidDiagram.kt` — the snap-in surface: a classic `View` (no Compose dep) and
  a `@Composable`, each rendering a source string in one line (see above).
- `native/` — the JNI native side: `Sources/MermaidJNI/mermaidkit_jni.c` (the C
  shim) and its own `Package.swift`. `build-jni.sh` cross-compiles it with the
  Swift Android SDK into `libmermaidkit.so` (the shim + `MermaidKitC` linked in)
  plus the transitive Swift-runtime `.so` closure — the AAR's `jniLibs/<abi>/`.
- `mermaidkit/src/androidTest/…/RenderInstrumentedTest.kt` — draws a scene through
  the emulator's Skia `Canvas` and asserts real ink lands.
- `mermaidkit/src/androidTest/…/NativeBridgeTest.kt` — the full seam on-device:
  source string → JNI → Swift → `SceneWire` → render.

## Build & test

```bash
# 1. Cross-compile the native .so bundle into jniLibs (needs Docker; per ABI):
docker run --rm -v "$PWD/..":/MermaidKit \
  -v "$PWD/mermaidkit/src/main/jniLibs/x86_64":/out \
  swift-android-6.2 bash /MermaidKit/android/native/build-jni.sh x86_64

# 2. Library AAR + JVM unit tests + instrumented-test APK (no device needed):
./gradlew :mermaidkit:assembleDebug :mermaidkit:testDebugUnitTest :mermaidkit:assembleDebugAndroidTest

# 3. On-device tests — render + the native JNI seam (needs an emulator, i.e. KVM):
./gradlew :mermaidkit:connectedDebugAndroidTest
```

The `jniLibs` `.so`s are **build artifacts** (gitignored) — CI (and a release
build) run step 1 to produce them. AAPT2 ships x86_64-only, so the Gradle build
must run on a native x86_64 host, and the emulator needs KVM — see
`.github/workflows/ci.yml`.

> Native size: the Swift runtime + Foundation/ICU make one ABI's `jniLibs` ~88 MB
> unstripped. Stripping and trimming the Foundation surface are follow-ups before
> a Maven release.

The **device measure seam** is wired: pass a `MermaidNative.Measurer` (use
`PaintMeasurer` over your drawing `Paint`) to `MermaidNative.scene(source,
measurer = …)` and native layout measures text with the same face that draws it
— a C trampoline bridges each measure request back into Kotlin on the JNI thread.

## Not yet here (next slices)

- **`MermaidTheme.fromMaterial()`** — inject Material color tokens across the
  bridge. Needs a C-ABI extension: `mmk_scene_json` takes only `prefers_dark`
  today, so the scene's colors come from a built-in light/dark preset.
- **`onNodeClick(nodeId)` hit-testing** — needs the ABI to emit a node→rect map
  alongside the scene; `SceneWire` is flattened primitives with no node identity.
- **Distribution** — per-ABI `.so`s (arm64-v8a, armeabi-v7a, x86_64) bundled into
  a stripped Maven Central AAR.
