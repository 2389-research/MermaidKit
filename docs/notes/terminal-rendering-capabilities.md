# Beyond ASCII: rendering MermaidKit diagrams in modern terminals

Companion to the experimental `experimental/ascii-renderer` branch (a bit-plane
box-drawing renderer over `DiagramScene`). That POC targets the lowest common
denominator — monospace box glyphs. This note maps what richer terminals,
specifically **Kitty** and **Ghostty**, expose, and how MermaidKit can exploit
each tier while degrading gracefully.

The through-line: MermaidKit already produces a full raster (CoreGraphics on
Apple, Silica/Cairo on Linux) and a vector PDF. So "better than ASCII" is mostly
a *transport* problem — getting bytes into an escape sequence — not a new
renderer. Only the richest text tier needs scene-level work.

## The capability ladder (best fidelity → most portable)

    Kitty graphics ─► Sixel ─► half-block truecolor ─► colored box-drawing ─► plain ASCII
      (real image)     (bitmap)   (1×2 color pixels)      (semantic + palette)   (POC today)

Pick the top tier the terminal actually answers to; fall through on no response.

### Tier 1 — real raster images (Kitty graphics protocol)
Kitty originated, and Ghostty implements, the **Kitty graphics protocol**:
transmit RGBA/PNG via escape sequences (chunked base64, or shared-memory /
temp-file for large images), and the terminal blits it with **pixel precision**.
Features that matter here:

- placement by cell or exact pixel offset; query cell pixel size first;
- **z-index / layering** (draw under or over text) and **alpha**;
- **animation frames** (could animate layout transitions / diffs);
- **Unicode placeholders** — tie an image to a run of cells so it *reflows and
  scrolls* with surrounding text (embedding a diagram inline in a TUI);
- explicit delete/replace for redraws.

MermaidKit path: render the diagram to a PNG at the target pixel size, stream it
into the protocol. This is **full desktop fidelity in the terminal** and reuses
the existing rasterizer wholesale. This is the best option whenever it's
available.

### Tier 2 — bitmap fallbacks
- **Sixel**: DEC bitmap, ~256-color palette, generally no alpha. Both Kitty and
  Ghostty support it. Use when Tier 1 isn't detected but a bitmap still beats
  glyphs — and it survives some environments (screen/tmux passthrough) better.

### Tier 3 — "pixels" out of characters (truecolor + block glyphs)
When no graphics protocol is available (or you want copy-pasteable, reflowable,
greppable output), approximate the raster with characters:

- **24-bit truecolor** (`SGR 38;2;r;g;b`) — the full mermaid palette per cell,
  no 16-color quantization.
- **Half-blocks** `▀▄` with independent fg/bg color = **two full-color pixels
  per cell** (1×2). The classic `chafa`/`viu` trick; looks surprisingly good.
- **Quadrants / sextants (2×3) / Unicode-16 octants (2×4) / Braille (2×4 dots)**
  push *shape* resolution higher, but only 1–2 colors per cell (fg/bg) — best
  for line art and limited-color regions, not full-color fills.

MermaidKit path: rasterize its own bitmap small, map pixels → colored block
glyphs. Resolution-independent-ish, needs no external tool, works over SSH into
any truecolor terminal. **Highest-value portable tier.**

### Tier 4 — semantic box-drawing (the POC, enriched)
Keep the structured Unicode diagram (bit-plane `Canvas`), but add:

- **truecolor** on the box glyphs → nodes/edges in the mermaid palette;
- **styled + colored underlines** (Kitty pioneered undercurl/dotted/dashed;
  Ghostty supports them) → dotted edges, emphasis;
- **OSC 8 hyperlinks** → make nodes *clickable* (link to source line, URL, docs);
- **mouse reporting + the Kitty keyboard protocol** → hit-test clicks/hover on
  nodes; interactive pan/zoom. A real TUI diagram, not a static dump.

This is the only tier whose output stays **selectable text with clickable
nodes** — a different axis from Tier 1's fidelity. MermaidKit could reasonably
offer both "best image" and "most useful as text."

## Capability detection

Query, don't guess. Combine:

- **Kitty graphics**: send a tiny query (`\e_Gi=…\e\\`) and read for a response;
  no response within a short deadline → not supported.
- **`$TERM`**: `xterm-kitty`, `xterm-ghostty`.
- **Env markers**: `$KITTY_WINDOW_ID`; Ghostty sets `$GHOSTTY_*` /
  `$TERM_PROGRAM=ghostty`.
- **Sixel**: Device Attributes (`CSI c`) advertises sixel (`;4`).
- **Truecolor**: `$COLORTERM=truecolor|24bit`.

Beware multiplexers (tmux/screen) and SSH: passthrough may drop graphics
protocols even when the outer terminal supports them — which is exactly why the
lower tiers must exist and be reachable by the same detector.

## Where this lives in MermaidKit

An ASCII/terminal backend is **platform-free** — pure bytes over a `DiagramScene`
(+ the existing rasterizer for Tiers 1–3) — so it belongs in the `MermaidLayout`
layer (zero graphics deps), runnable headless on Linux/CI. That also makes it the
natural home for an **LLM-friendly** diagram-as-text output, which is the same
motivation behind the box-drawing POC.

Suggested build order:
1. Tier 4 truecolor + palette on the existing POC (cheap, immediate win).
2. Tier 1 Kitty-graphics transport over the existing PNG render (highest
   fidelity, small surface).
3. Tier 3 half-block truecolor (best portable fallback).
4. Detection ladder tying them together; Sixel and OSC-8/mouse interactivity as
   follow-ups.

Related: `linux-rendering-via-silica.md` (the raster backend these tiers reuse),
`ir-compilation-targets.md`.
