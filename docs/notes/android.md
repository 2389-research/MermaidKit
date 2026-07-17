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

## Cross-project alignment (Vinculum)

An independent design at Vinculum converged on nearly the same architecture:
on-device native, Swift-thinks / Kotlin-draws-natively, prebuilt multi-ABI AAR
from Maven, Compose + View, a pure-Swift foundation with a reference renderer
before the NDK, and emulator CI. Their production experience sharpened two
decisions recorded below — **pin measurement to the drawing engine** and **thread
accessibility through the bridge from the first surface** — both from bugs they
actually shipped. Where the projects *diverge* (the font axis) is deliberate and
correct; see Fonts.

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

- **Accessibility, designed in from the first surface** — thread the
  `MermaidAltText.narrate` walkthrough through the JNI boundary as part of the
  *initial* C ABI (returned alongside the scene), wired to `contentDescription`.
  **Not** bolted on per-view later: cheap if designed in, painful to retrofit
  (Vinculum's lesson). Instant differentiator.
- **Tap callbacks** — the scene carries every node's frame, so hit-testing gives
  `onNodeClick(nodeId)` with no extra layout work.
- **Material theming** (`DiagramTheme` ← `MaterialTheme` colors), light/dark,
  DPI-aware, and export to PNG/SVG/PDF from Kotlin.

## Measurement — decided: measure with the engine that draws

Layout is only correct if it measures with the **exact face that draws**.
**Decision (product surface): the batched `Paint.measureText` callback — the
device's Skia face both measures and draws.** This is committed, not an "or."

Why we pin it rather than leave it open (Vinculum's lesson, their issue #62):
measuring with a bundled Roboto in Swift while drawing with the device's
Skia/Roboto is *two different faces* — they diverge by font **version**,
**hinting**, and the user's system **font-scale** (accessibility) setting — which
clips and misaligns labels in a way **no renderer-conformance check can catch**
(both renderers faithfully draw a scene that was laid out against the wrong
metrics; the ratchet only guarantees scene→pixels fidelity, not that the metrics
were right). So: Swift layout calls back into Kotlin `Paint.measureText`,
**batched over one JNI hop** (all label strings + sizes in, all metrics out),
memoized (the measurement path is already memoized from the perf work).

Bundled-Roboto + FreeType measurement stays **only** as the headless/SVG fallback
(no device present) — never the product path.

**Standing seam check — a cross-backend golden gate.** Measure a shared corpus
and diff *size-normalized ink signatures* across backends (CoreText / Skia /
FreeType); drift means the measure-face and draw-face have separated on some
backend. Same shape as the cross-process determinism gate we just shipped — a
ratchet on a seam unit tests structurally can't see.

## Fonts: device Skia for labels; the math axis stays different

The principle *measure with the engine that draws* is universal; the **font
choice is not**, and Vinculum and MermaidKit correctly diverge here — keep it.
For diagram **labels**, native = fidelity, so MermaidKit draws device text via
Skia and measures with the **same Skia face**; we do **not** bundle a label font.
Math is the exception a math-rendering project faces: its glyphs come from an
OpenType `MATH` table no system font ships, so that project bundles a math font
and draws/measures it via FreeType. Same principle, different fonts — do not
unify this axis.

## Obstacles, and how the decision handles each

- **No CoreGraphics on Android** → we don't need it; Kotlin draws with Canvas.
- **No FontConfig on Android** → irrelevant; native `Paint` handles fonts.
- **Swift↔Kotlin bridge** → tiny **C ABI**: takes `source + options + a batched
  measure callback`, returns the **scene + the narration/alt-text + diagnostics**
  (accessibility threaded from the first surface, per Vinculum). Not the rich
  Swift API; hidden inside the AAR.
- **Toolchain friction** → borne once, in *our* CI (NDK + Swift Android SDK);
  invisible to consumers.
- **`MermaidView` (SwiftUI)** → doesn't port; Android gets the headless render +
  its own Compose/View wrappers.

## Phased plan

Each phase is independently valuable and testable; nothing needs the Android
toolchain until Phase 1.

### Phase 0 — Complete `RenderScene` + SVG reference renderer (pure Swift) ← START HERE
The linchpin. A new **complete, `Codable` `RenderScene`** that fully determines
the picture — shaped nodes (frame, shape, fill/stroke/dash), edges (polyline +
arrowheads + dash), text with font size, containers, canvas — lowered from the
per-type `*Layout`, plus an **SVG backend** that renders it. Buildable and provable
now, no NDK. Ships value on its own as SVG export (#15) and *is* the plugin/Android
scene contract (#14).
- **0a:** `RenderScene` types + `RenderScene.from(.flowchart, theme:, measure:)`
  + `SVGRenderer` for the flowchart family + tests (valid SVG, expected shapes).
- **0b:** extend `from(…)` to the remaining diagram families (about one commit
  per family), reusing what `DiagramRenderer` already knows how to draw.
- **0c:** the cross-backend golden gate — size-normalized ink-signature diff
  across backends as a standing seam check.
- *Acceptance:* every fixture lowers to a `RenderScene` and renders to valid SVG;
  no field the renderer needs is missing (the scene fully determines the picture).

### Phase 1 — C ABI + NDK cross-compile
Swift core → per-ABI `.so` (arm64-v8a, armeabi-v7a, x86_64) via the NDK + Swift
Android SDK. Thin C ABI: `source + options + batched measure callback → scene +
narration/alt-text + diagnostics`.
- *Acceptance:* a headless C harness on Android returns a `RenderScene` for a fixture.

### Phase 2 — Kotlin `SceneRenderer` + snap-in surface
`SceneRenderer` draws the `RenderScene` with `Canvas`/`Paint`; the batched
`Paint.measureText` callback feeds layout; `MermaidDiagram` Compose + `MermaidView`
View; `MermaidTheme.fromMaterial()`; `contentDescription` from the narration;
`onNodeClick(nodeId)` hit-testing.
- *Acceptance:* a sample app renders every fixture natively, light/dark, with
  a11y labels and tap callbacks.

### Phase 3 — Distribution
Maven Central `.aar` bundling the prebuilt `.so`; a one-Gradle-line sample app;
emulator CI.
- *Acceptance:* `implementation("ai.2389:mermaidkit-android:…")` in a fresh app
  renders a diagram with no NDK/Swift setup.

## Open questions (decide as we go)

- ~~Measurement seam~~ — **decided**: device `Paint.measureText` callback on the
  product surface; bundled-Roboto only as the headless/SVG fallback (see
  Measurement).
- Serialization: JSON (readable, `Codable` today) vs a tighter binary/FlatBuffer
  if per-frame scene transfer ever gets hot.
- Swift-Java interop vs a hand-rolled C ABI as that ecosystem matures.

Related: `ir-compilation-targets.md`, `plugin-extensibility.md`, and issues #14
(runtime plugins) and #15 (export backends — the SVG that doubles as the Android
scene proof).
