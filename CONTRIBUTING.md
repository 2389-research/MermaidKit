# Contributing to MermaidKit

## The lay of the land

One diagram type = three small, independent pieces:

- `Sources/MermaidLayout/MermaidParser+<Type>.swift` — text → model
- `Sources/MermaidLayout/DiagramLayout<Type>.swift` — model → geometry
  (frames/polylines; text metrics come in through `DiagramTextMeasurer`)
- `Sources/MermaidRender/DiagramRenderer+<Type>.swift` — geometry → drawing
  (one `CGContext` seam: CoreGraphics on Apple, Silica/Cairo on Linux)

Plus a lowering (`DiagramScene+<Type>.swift`) that hands the geometry to the
layout linter.

## Ground rules

- `swift test` must stay green (the package is the repo root — there is no `MermaidKit/` subpackage).
- **Layout changes are judged by geometry.** Every type's dense fixture in
  `Fixtures/diagrams/` must lint clean (`LayoutLintTests`); iterate on one
  type with `MERMAIDKIT_LINT_TYPE=<type> swift test --filter testLintSingleType`.
  The linter is necessary, not sufficient — also render your fixture and
  *look at it*.
- **The parser never crashes.** New numeric fields go through
  `MermaidParser.finiteDouble`; new syntax must tolerate garbage (see
  `AdversarialInputTests` — add cases for anything you touch).
- Performance: `RenderBenchmarks` renders and rasterizes every fixture as a
  correctness smoke — it never asserts on wall-clock (timing gates flake under
  CI load). Measure the perf table opt-in with
  `BENCH_TABLE=1 swift test --filter RenderBenchmarks`.
- `MermaidLayout` stays zero-dependency and platform-free (`Foundation` +
  `CoreGraphics` geometry only, `canImport`-guarded — it must keep building on
  swift-corelibs-foundation). `MermaidRender` is CoreGraphics on Apple and
  links Silica only on Linux, and only when the `LinuxRaster` package trait is
  enabled (default OFF, so `from:`-pinned consumers get a Silica-free graph);
  don't add other dependencies.
- Regenerate README images with `scripts/gen-gallery.sh` when a fix changes
  how a fixture renders.

## Developing on Linux

`MermaidRender` draws on Linux via Silica (Cairo/FontConfig) — the same layout
and per-type draw code as Apple. The Silica backend is behind the `LinuxRaster`
package trait (default OFF, so Apple/`from:`-pinned consumers never fetch the
Silica graph), so Linux builds opt in with `swift build --traits LinuxRaster`.
To build and test the whole package the way CI does, in a `swift:6.2`
container:

    scripts/test-linux.sh   # requires Docker; enables LinuxRaster

Check a per-type renderer change on both backends: `swift test` on Apple and
`scripts/test-linux.sh` for Linux (its `LinuxRenderTests` render every fixture).
The porting approach is written up in
`docs/notes/linux-rendering-via-silica.md`. The toolchain floor is Swift 6.2 /
Xcode 26 — package traits (and Silica's graph, when enabled) require it.

## API stability stance

The wide public surface — every model and layout struct — is deliberate:
headless geometry is a feature, not leakage. The deal that keeps it from
becoming a semver trap:

- The *entry points* (`MermaidParser.parse`/`diagnose`,
  `DiagramLayoutEngine.layout`, `DiagramScene.lower`, `DiagramLayoutLinter`,
  `MermaidRenderer`, `MermaidView`, `DiagramTheme`) are stable — and always
  have been.
- **As of 1.0, model/layout field changes are semver-major.** Before 1.0 they
  could reshape to follow the diagrams' needs; that window is closed.

## Most-wanted

- Syntax-coverage gaps in existing types (bring the diagram that broke).
- Lower OS floors, with CI to prove them.
