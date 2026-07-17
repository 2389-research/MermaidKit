# MermaidKit on Android: fidelity, utility, and zero-hassle bridges

Design memo · the plan for first-class Android support. Not yet implemented;
this records the options, the reasoning, and what we decided so we build the
right thing.

## The goal

Three things, together — not a cheap port:

1. **Highest fidelity** on Android.
2. **Highest utility** for Android developers.
3. **Zero-hassle bridges** — they snap it into their app with no NDK, no Swift,
   no JNI, no friction.

## What "fidelity" means on Android

Crucially, it does **not** mean shipping macOS's exact pixels. It means drawing
with **Android's own 2D stack (`android.graphics.Canvas`/`Paint`, i.e. Skia) and
the device's real fonts** — so output is crisp at every DPI, matches the system,
and themes with Material. A pre-rasterized bitmap produced from a foreign font
stack (Cairo/FreeType with bundled fonts) is the *opposite* of that: fixed
resolution, wrong fonts, no Material theming. So the naive "easy" paths are out.

## The architecture we chose

**Swift does the intellectual work and returns a complete scene; Kotlin draws it
natively.**

    Swift core (.so, built once via NDK)              Kotlin/Compose (the .aar devs consume)
    ─────────────────────────────────────           ────────────────────────────────────────
    parse → IR → layout → lint → RenderScene  ─JSON─▶  SceneRenderer draws with Canvas/Paint
            ▲ measurement callback ◀───────────────    (Skia: native quality, real fonts, DPI-correct)

- The Swift side is the already-platform-free layer (parse, layout, lint). It
  never touches pixels on Android — it emits a **complete `RenderScene`**.
- The Kotlin side draws that scene with `Canvas`/`Paint`. This is a "backend"
  exactly like the Apple (CoreGraphics), Linux (Silica/Cairo), and terminal
  backends — it just lives on the Kotlin side of the bridge.
- **Layout measures against the fonts that actually draw** (see Measurement),
  so nothing clips and the geometry linter stays quiet.

## Options considered, and why

| Option | Fidelity | Utility / snap-in | Verdict |
| --- | --- | --- | --- |
| **SVG → WebView** | Medium (SVG renderer quirks; measure/render mismatch) | Poor — a WebView is not idiomatic, heavy, clunky | Rejected as the product path (SVG is still valuable as an *export* + reference, see below) |
| **Cairo/Silica raster → Bitmap** | Medium — foreign font stack; **Android has no FontConfig** (fonts live in `/system/fonts`), so font discovery doesn't transfer; fixed-resolution bitmap | Simple bridge (bytes→Bitmap), single draw impl | Rejected — re-inherits the font problem, not DPI-crisp, not Material |
| **Swift rasterizes → Bitmap** (pure-Swift or FreeType) | Medium — same font/DPI limits | Simple bridge | Rejected for the same reasons |
| **Swift `RenderScene` → Kotlin draws with Canvas** | **Highest** — native Skia AA, real fonts, DPI-correct, Material-themeable | **Highest** — idiomatic Compose/View | **Chosen** |

The cost of the chosen path is a **second draw implementation** (Kotlin Canvas,
alongside Swift's). We accept it because:
- It's the only path that hits *both* fidelity and idiomatic utility.
- The **draw-vs-scene conformance ratchet already exists** to keep the scene a
  faithful, complete description of the picture — so "draw the scene" in Kotlin
  and "draw the scene" in Swift stay in sync *by construction*, not by vigilance.

## The linchpin: a complete `RenderScene`

The one real blocker. Today's `DiagramScene` is **lossy** — it was built for the
linter, so it carries frames, polylines, and label frames but **drops shape and
color** (confirmed by the export-substrate research). A Kotlin renderer can't
draw shapes it can't see.

So the enabling step is a **complete `RenderScene`**: frames + shape +
fill/stroke/dash + arrowheads + text-with-font — a description that *fully
determines the picture*. This is not Android-only work:

- **SVG export (issue #15) needs the exact same complete scene.**
- It **is** the plugin/backend JSON contract (issue #14).

So this single piece unlocks Android, SVG, and the plugin ecosystem at once. Build
it in Swift first — provable *now*, no NDK required — with a **reference SVG
backend** as the proof that the scene fully determines the drawing (SVG is easy
to diff and read, and it's a shippable export in its own right).

## The snap-in surface (zero friction for the Android dev)

- **Compose-first + classic View**, mirroring the Apple `MermaidView`:
  ```kotlin
  MermaidDiagram(source = mmd, theme = MermaidTheme.fromMaterial(), modifier = Modifier.fillMaxWidth())
  ```
- **One Gradle line**, nothing else:
  ```kotlin
  implementation("ai.2389:mermaidkit-android:1.x")
  ```
  from Maven Central. The `.aar` bundles **prebuilt `.so` for every ABI**
  (arm64-v8a, armeabi-v7a, x86_64). The consumer never sees the NDK, Swift, or
  JNI — *we* eat the cross-compile so they don't. That is the whole "no
  frustration" requirement.

## Utility wins (an interactive diagram, not a static image)

- **Accessibility for free** — wire Android `contentDescription` straight from
  `MermaidAltText.narrate` (the step-by-step walkthrough already shipped). Instant
  differentiator.
- **Tap callbacks** — the scene carries every node's frame, so hit-testing gives
  `onNodeClick(nodeId)` with no extra layout work.
- **Material theming** (`DiagramTheme` ← `MaterialTheme` colors), light/dark,
  DPI-aware, and export to PNG/SVG/PDF from Kotlin.

## Measurement (the subtle fidelity detail)

Layout is only correct if it measures with the fonts that draw. Two clean ways;
pick during step 3:
- **Bundled Roboto + FreeType (Swift-side):** ship Android's default font, measure
  it with FreeType, draw it with Canvas — fast (no JNI per label), high fidelity
  as long as we control the font. Simplest.
- **JNI measurement callback:** Swift layout calls back into Kotlin
  `Paint.measureText`, **batched over one JNI hop** (all label strings+sizes in,
  all metrics out) and memoized (measurement is already memoized in the perf
  work). Highest fidelity when the app wants *its own* font.

## Obstacles, and how the decision handles each

- **No CoreGraphics on Android** → we don't need it; Kotlin draws with Canvas.
- **No FontConfig on Android** → irrelevant; native `Paint` handles fonts.
- **Swift↔Kotlin bridge** → tiny **C ABI** (`source + options + measure cb →
  scene bytes`, plus diagnostics), not the rich Swift API; hidden inside the AAR.
- **Toolchain friction** → borne once, in *our* CI (NDK + Swift Android SDK);
  invisible to consumers.
- **`MermaidView` (SwiftUI)** → doesn't port; Android gets the headless render +
  its own Compose/View wrappers.

## Staged plan

1. **Complete `RenderScene` + a reference SVG backend** (pure Swift, provable now;
   guarded by the draw-vs-scene ratchet). ← the linchpin; shared with #15/#14.
2. **C ABI + NDK build** of the Swift core → per-ABI `.so`, with the measurement
   callback.
3. **Kotlin `SceneRenderer`** (Canvas) + Compose/View wrappers + Material theming
   + narration→`contentDescription` + tap callbacks.
4. **Maven Central AAR** + a Gradle sample app; CI on an emulator.

## Open questions (decide as we go)

- Measurement: bundled-font vs JNI-callback (step 3) — likely start bundled, add
  callback as an opt-in.
- Serialization: JSON (readable, `Codable` today) vs a tighter binary/FlatBuffer
  if per-frame scene transfer ever gets hot.
- Swift-Java interop vs a hand-rolled C ABI as that ecosystem matures.

Related: `ir-compilation-targets.md`, `plugin-extensibility.md`, and issues #14
(runtime plugins) and #15 (export backends — the SVG that doubles as the Android
scene proof).
