# Cross-platform conformance: proving the output is functionally equivalent everywhere

**The claim, made precise:** the platform-free core (parse → layout →
`RenderScene` → `SceneWire`/SVG) produces **byte-identical** output on every
platform it compiles to, given the same measurement input. Because the scene
*fully determines* the picture, byte-identical scenes == functional equivalence:
each platform's renderer (CoreGraphics, Cairo, Android Canvas, Canvas2D, …) is
only a thin painter over the same geometry.

## How it's proven

`tools/conformance` is a standalone Swift executable — the same source compiled to
every target — that runs a fixed fixture set (flowchart, sequence, state, class,
pie) through the core with the **deterministic coarse measurer** (pure arithmetic,
no platform fonts, so any divergence is a real core difference, not a font one)
and prints a stable FNV-1a signature of the sorted-key `SceneWire` JSON and the
SVG for each, plus a combined digest.

Run it on each platform and compare the `COMBINED` line. `scripts/check-conformance.sh`
asserts it equals the pinned reference; the `conformance.yml` workflow runs it on
macOS, Linux, WebAssembly, and Windows as a standing gate.

**Verified byte-identical — `COMBINED 3f94e22042aa59eb`:**

| Platform | libc | Foundation | how it was run |
|----------|------|------------|----------------|
| macOS | Darwin | Darwin Foundation | native |
| Linux | glibc | swift-corelibs | `swift:6.2` container |
| Android | Bionic | swift-corelibs | cross-compiled, run on an android-34 emulator via `adb` |
| WebAssembly | wasi-libc (musl) | swift-corelibs | `wasm32-unknown-wasi` SDK, run under WasmKit |
| Windows | MSVC CRT | swift-corelibs | `windows-latest` CI runner |

Three distinct libc implementations, two Foundation implementations — all identical.

## The two divergences it caught (and how they were fixed)

Getting to byte-identity surfaced two real cross-platform determinism bugs that no
single-platform test could see:

### 1. `Double` → JSON differs across Foundation implementations

`JSONEncoder` serializes a `Double` differently on Darwin vs swift-corelibs:
Darwin emits the shortest round-trip (`111.8`), swift-corelibs (Linux/Android/WASM)
sometimes emits full precision (`111.80000000000001`). So a coordinate from layout
arithmetic produced different wire bytes across platforms — while the SVG (which
formats its own numbers via `SVGRenderer.num`) stayed identical.

**Fix** (`SceneWire.q`): quantize every wire coordinate to an exact 1/256 (2⁻⁸)
grid before encoding. An exact binary fraction has *one* shortest representation
every encoder agrees on, so the wire JSON is identical everywhere. 1/256 px is
sub-pixel and imperceptible; SVG is untouched.

### 2. Arc tessellation step-count amplified 1-ULP math noise

Pie slice arcs are tessellated into `ceil(sweep / (π/8))` quadratic segments. For a
"nice" slice (a 50% slice sweeps exactly π = 8·(π/8)), that ratio is an integer
**± 1 ULP** — and because `sin`/`cos`/`π` differ by ~1 ULP across platform math
libraries, `ceil` turned that noise into a **±1 segment-count difference**, which
discretized the whole arc differently (WASM's wasi-libc math diverged from Darwin
and glibc, which happened to agree).

**Fix** (`RenderScene+Pie.arcQuads`): subtract a tiny epsilon before the `ceil`, so
an integer-plus-noise ratio rounds to the integer. The per-segment `sin`/`cos`
values still differ by ~1 ULP across platforms, but those differences are far below
the 1/256 wire grid and vanish in quantization.

## Why this matters

- **The wire is now a true cross-platform contract.** An iOS app (Darwin) and an
  Android app (Bionic) — or a browser (WASM) — produce the *same* `SceneWire`
  bytes for the same diagram, so goldens, caches, and diffs are portable.
- **It generalizes the determinism gate.** `check-determinism.sh` proved
  *cross-process* stability (issue #1, hashed-iteration order); this proves
  *cross-platform* stability (Foundation + libm differences). Both are now gated.
- **New platforms are cheap to add.** The proof for WASM and the argument for
  Windows are the same: compile the platform-free core, and its output already
  matches — the only platform-specific work is a thin renderer (or reuse SVG).
