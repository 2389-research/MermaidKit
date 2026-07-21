# pi-canvas — an infinite, pannable canvas on a bare framebuffer

A proof that MermaidKit can drive an **infinite, pannable canvas of Mermaid
diagrams composited into a fixed framebuffer** — e.g. `/dev/fb0` on a Raspberry
Pi, no X11/Wayland/desktop — over the existing headless raster. No core changes.

```
swift run pi-canvas <out-dir>                    # macOS: CoreGraphics raster
swift run --traits LinuxRaster pi-canvas <dir>   # Linux/Pi: Silica/Cairo raster
```

## What it shows

- **`InfiniteCanvas`** — diagrams placed at positions in an unbounded virtual
  space. Each is rendered once to an RGBA raster (cached; zoom re-rasterizes for
  crispness rather than scaling a bitmap). Each frame culls to the viewport and
  blits only the visible cards.
- **`Framebuffer`** — the presentation seam. `PNGFramebuffer` (the testable
  stand-in) writes each frame as a PNG; `LinuxFramebuffer` (`#if os(Linux)`)
  `mmap`s `/dev/fb0` and blits, packing RGB565 at 16bpp or BGRA at 32bpp.
- The demo pans across a wall of diagrams, then zooms in.

Panning over already-rendered cards is pure memcpy — smooth at 60fps on a Pi 5;
only the *first* sight of a new diagram costs a render.

## What's proven, and where

- **Compositor, culling, zoom-reraster, framebuffer/PNG** — verified visually on
  macOS (CoreGraphics) **and on aarch64 Linux — the Pi's exact architecture —
  with the Silica/Cairo raster** (the same stack the Pi runs), producing the same
  composite.
- **RGB565 packing** — `Rgb565.pack`/`convert` are pure and platform-free.
- **The one on-device line** — the final `mmap`+`memcpy` to a real `/dev/fb0`
  can only run on hardware; everything feeding it is exercised headlessly.

## The gap it closed

This exercise surfaced the "portable raw raster" gap: `MermaidRenderer.rgbaRaster`
was **Apple-only** — the Linux/Silica backend exposed PNG, not raw pixels, so a
framebuffer/GPU/SDL consumer couldn't get a buffer without decoding a PNG. It now
has a **Linux implementation** (reads the Cairo ARGB32 surface → RGBA), which
unlocks not just the Pi but SDL2, game engines, and any bare surface on Linux.

## On a real Pi

Swap `PNGFramebuffer` for `LinuxFramebuffer()` and drive `viewportX/Y` from
`evdev` (touch/gamepad). Nothing else changes.
