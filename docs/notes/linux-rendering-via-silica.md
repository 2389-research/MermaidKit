# Porting a CoreGraphics/CoreText renderer to Linux with Silica

*Design memo — 2026-07-15. Written up from the MermaidKit Linux rendering port
(shipped v0.11.0) as a playbook for other first-party engines — notably
Vinculum — that draw with CoreGraphics/CoreText on Apple and want native Linux
output with no browser, no JS, no headless Chrome.*

---

## TL;DR

Silica (PureSwift) is a pure-Swift CoreGraphics reimplementation with a Cairo +
FontConfig backend for Linux. If your renderer already funnels all drawing
through `CGContext`, the port is mostly a **thin adapter** that gives Silica's
`CGContext` the exact Apple method names you already call, plus a small
platform layer (`PlatformColor`/`Font`/`Image`) and a **text path** that trades
CoreText for Silica's glyph API. MermaidKit renders all 30 diagram types on
Linux (opt-in via the `LinuxRaster` package trait), sharing 100% of the layout
and per-type draw code. Output is faithful to
macOS — same geometry, same drawing — not pixel-identical: the system font
differs (DejaVu via FontConfig vs SF), so glyphs and text-driven node sizes
shift slightly. The only genuinely different subsystem is text.

The cost you pay: **the toolchain floor rises to Swift 6.2** (Silica's
transitive graph forces it — see Gotchas).

---

## Why this works: the drawing seam

The port is cheap in direct proportion to how well the renderer is already
funnelled. MermaidKit draws every diagram through a single closure:

```swift
renderPlan(for:theme:spacing:) -> (size: CGSize,
                                   edgePolylines: [[CGPoint]],
                                   draw: (CGContext) -> Void)
```

Every per-type renderer is `draw(_ layout:, theme:, in context: CGContext)`.
Nothing else touches the graphics context. So "port to Linux" reduces to:
*make a `CGContext` on Linux, and make the ~40 methods the draw code calls
resolve.* No per-type renderer changed.

**First thing to check in your engine:** is there one context type threaded
through all drawing, or do renderers reach for `NSImage`/`UIGraphicsImageRenderer`/
CoreText directly in a hundred places? The former is a weekend; the latter is a
refactor-first job. (Do that refactor regardless — it's good hygiene.)

The full CoreGraphics surface MermaidKit actually used was small and worth
knowing up front: gstate save/restore, CTM translate/scale/rotate,
setFill/StrokeColor, line width/dash/cap/join, path building (move/addLine/
addRect/addEllipse/addArc/addCurve/addQuadCurve/addPath/close), path painting
(fill/stroke/drawPath), the rect/ellipse convenience calls, and text. **No**
gradients, shadows, clipping, blend modes, transparency layers, or
image-into-context compositing. If your engine uses those, check Silica's
support per-feature before committing (it has most, but verify).

---

## The five moving parts

### 1. Platform types (`PlatformColor` / `PlatformFont` / `PlatformImage`)

On Apple these are `NSColor`/`UIColor`, `NSFont`/`UIFont`, `NSImage`/`UIImage`
behind typealiases. On Linux there is no AppKit/UIKit, so vend equivalents:

- `PlatformColor` — a plain fixed-RGBA struct. MermaidKit's themes never used
  appearance-dynamic colors (everything was a literal or the system accent), so
  there was no appearance system to emulate. **Check this in your engine**: if
  you lean on dynamic `NSColor`s that resolve at draw time, you need a
  light/dark resolution shim; if not, a struct is enough.
- `PlatformFont` — carries a weight and resolves a Silica `CGFont` by FontConfig
  family name, cached. (See text, below.)
- `PlatformImage` — wraps the Cairo `Surface` and exposes `pngData()` /
  `writePNG(to:)`. This is where the Apple/Linux public surface legitimately
  diverges: Apple returns `NSImage`; Linux returns bytes.

### 2. The `CGContext` adapter

Silica's `CGContext` is a **protocol**, close to Apple's but not identical.
Bridge the gaps with an extension so the shared draw code compiles unchanged:

| Apple call | Silica | Adapter |
| :--- | :--- | :--- |
| `saveGState()` / `restoreGState()` | `save()` / `restore()` (throwing) | `try? save()` |
| `rotate(by:)` | `rotateBy(_)` | forward |
| `fill(_ rect:)`, `stroke(_:)`, `fillEllipse(in:)`, `strokeEllipse(in:)` | — | `beginPath(); addRect/Ellipse; fill/strokePath` |
| `setLineJoin(_:)` / `setLineCap(_:)` | `lineJoin` / `lineCap` properties | property set |
| `fillPath()` (winding default) | `fillPath(using:)` / `fillPath(evenOdd:preserve:)` | `fillPath(using: .winding)` |

`setFillColor`/`setStrokeColor`/`setLineWidth`/`setLineDash`/`addPath`/
`addEllipse(in:)`/`drawPath(using:)`/the two `addArc` forms already exist in
Silica.

### 3. `CGPath` construction

Silica's `CGPath` is a class with a `CGMutablePath` subclass — but **no
`init(roundedRect:)`/`init(ellipseIn:)`/`init(rect:)`, and `CGMutablePath` has
no arc primitive.** Provide the Apple-shaped convenience initializers yourself,
building rounded corners from quad curves. (This is the one place the Linux and
Apple output can differ by a hair — quad-curve vs true-arc corners — but it's
sub-pixel at diagram radii.)

### 4. Text — the only real work

This is where a CoreText renderer and Silica diverge hard. Silica has **no
CoreText** (`CTLine`, `CTLineGetTypographicBounds`, `CTLineDraw`). Instead:

- **Fonts** resolve through FontConfig: `CGFont(name: "DejaVu Sans")`, or
  `"Family:bold"`. Cache them.
- **Measurement**: `font.singleLineWidth(text:fontSize:)` for width;
  `font.ascent` / `font.descent` (fractions of em, descent is **negative**) for
  height — so `height = (ascent - descent) * fontSize`.
- **Drawing** a whole string: `context.setFont(f); context.fontSize = s;
  context.textMatrix = <translation>; context.show(text:)`. In a *flipped*
  (top-left-origin) context, `show(text:)` treats `textMatrix.ty` as the text
  **top** — it adds `ascent * fontSize` internally to reach the baseline. So to
  center on a point: `ty = center.y - height/2`, `tx = center.x - width/2`.
- **Drawing positioned glyphs**: `context.draw(glyphs: [(glyph: CGGlyph,
  position: CGPoint)])`, with `font.glyph(for: scalar)` for cmap lookup and
  `font.advances(for:fontSize:)` for metrics.

**For Vinculum specifically:** the positioned-glyph API is a *better* fit than
MermaidKit's single-line `show(text:)`. A math engine already computes exact
glyph positions (fraction bars, radical placement, script offsets, big-operator
limits); those map straight onto `draw(glyphs:[(glyph, position)])`, and
`advances(for:)` replaces your CoreText metric calls. The layout math is
platform-free and unchanged; only the final "emit glyph at point" call swaps.

The honest caveat for Vinculum: **OpenType MATH-table support**. CoreText
exposes math constants, italic corrections, cut-ins, and large/assembled-glyph
variants; whether Silica/FreeType surface enough of the MATH table for
Latin-Modern-Math-quality output is the open question and the thing to probe
FIRST (see below). If the MATH table isn't reachable, you either read it
yourself via FreeType or accept reduced fidelity. Don't assume — measure.

### 5. Output pipeline

- **Raster**: create a Cairo image surface, wrap it in a `CairoContext(surface:
  size:flipped: true)`, fill the canvas, run the shared `draw(context)`, then
  `surface.writePNG(...)` (or `context.makeImage() -> CGImage`).
- **PDF**: `CairoContext(pdf: url, size:)` → draw → `finish()` → read the file.
- Keep `attachmentString`/NSCache/SwiftUI view Apple-only — they're host-integration,
  not rendering.

---

## Packaging: `#if` strategy

- Add SilicaCairo + Cairo as **Linux-only target dependencies**
  (`.product(..., condition: .when(platforms: [.linux]))`). On Apple they are
  never linked; CoreGraphics/CoreText are used.
- Widen every render file's guard from
  `#if canImport(AppKit) || canImport(UIKit)` to
  `... || canImport(SilicaCairo)`. `canImport(SilicaCairo)` is the precise
  "Linux backend is linked" signal.
- Move `import CoreGraphics`/`CoreText`/`AppKit`/`UIKit` into an **Apple-only
  inner branch**; on Linux the shared files see Silica's `CGContext`/`CGColor`/
  `CGPath`/`CGFont` via `@_exported import Silica` from one platform file. Watch
  the trap: an existing `#if canImport(AppKit) … #else import UIKit #endif`
  block's `#else` now also catches Linux — change it to `#elseif
  canImport(UIKit)`.

---

## Gotchas (each cost real time)

1. **Swift 6.2 toolchain floor.** Silica's dependency graph transitively pulls
   `PureSwift/Android`, which requires swift-tools 6.2 — and SwiftPM parses
   *every* manifest in the graph regardless of platform. So the moment you add
   Silica, the whole package (and all its consumers) needs Swift 6.2 / Xcode 26.
   There's no per-platform escape without dependency-override surgery. Decide
   this deliberately; it's a breaking change for downstream.
2. **Geometry types are shared; `CGAffineTransform` is not.** On Linux
   `CGRect`/`CGPoint`/`CGSize`/`CGFloat` come from swift-corelibs-foundation and
   are the same types Silica's context consumes — no conversions. But Silica
   ships its **own** `CGAffineTransform` (no `init(translationX:y:)`/`scaleX:` —
   use `init(a:b:c:d:tx:ty:)`), and its own `CGColor`/`CGPath`/`CGFont`. And
   `CGVector` is absent from corelibs-foundation entirely (shim it).
3. **Flip consistency.** The shared draw code assumes a flipped, top-left-origin,
   y-down CTM (Apple gets it from `NSImage(flipped:)`/`UIGraphicsImageRenderer`).
   Create Cairo contexts with `flipped: true` and the text baseline math above
   just works; a PDF context that isn't flipped will mirror everything.
4. **Container plumbing.** The `swift:6.2` image needs `libcairo2-dev
   libfontconfig1-dev pkg-config` and a font (`fonts-dejavu-core`) + `fc-cache
   -f`. In a sandboxed Docker, `apt` may only reach mirrors over 443 — flip
   sources to HTTPS. Docker Desktop on macOS only shares `/Users` back to the
   host, so write verification PNGs there, not `/tmp`.
5. **Rendering isn't reproducible across process launches by default.** Swift
   randomizes the `Set`/`Dictionary` hash seed per process, and a few layouts
   iterate hashed collections in a way that reaches geometry — so the same
   source renders a hair differently in two runs. Within-process determinism
   tests miss it; a golden-image test (comparing against an image from another
   process) catches it immediately. Set `SWIFT_DETERMINISTIC_HASHING=1` for any
   reference-image testing. **Open follow-up:** the underlying cross-process
   layout nondeterminism (a hashed-collection order leaking into coordinates —
   at least in the zenuml layout, likely a couple of others) is worth fixing at
   the source (sort before iterating / use model order) so output is stable for
   users too, not just under the test's fixed seed. If Vinculum's math layout
   uses hashed collections anywhere positions are derived, it will have the same
   latent issue.

---

## Method: probe before you port

Don't refactor 30 files against a guessed API. The sequence that worked:

1. **Probe** — a throwaway executable depending on SilicaCairo that draws a
   rounded box + a measured, centered label + an arrow to PNG. This pins the
   real API (initializers, method names, text positioning) and proves the
   toolchain (Cairo, FontConfig, a font) works in the container — before
   touching the real package. Getting *text centered correctly* in the probe is
   the milestone; everything else is easy by comparison.
2. **Integrate** — platform layer + adapter + guards, driven by the compiler:
   build on Linux, fix the batch of errors, repeat. With Silica cached this is
   fast.
3. **Sweep** — render every fixture and diff against the Apple output. "It
   compiles" is not "it renders"; the all-fixtures pass is what catches a
   per-type renderer hitting an unsupported path.

For Vinculum, insert a **step 0**: a probe that renders one non-trivial formula
(a fraction with a radical and a summation with limits) using
`draw(glyphs:[(glyph, position)])` against a real math font, and *look at it*.
That single image answers the MATH-table fidelity question that decides whether
this is a weekend or a project.

---

## What you get

One package, one set of drawing code, two backends selected at compile time.
Apple output is byte-identical to before (Silica isn't even linked). Linux gets
native PNG/PDF with no browser and no JavaScript — same layout, same drawing,
just a different system font — the same "the source is the truth, we draw it
ourselves" story, now everywhere Swift runs.
