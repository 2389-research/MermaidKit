---
name: Diagram renders wrong (or not at all)
about: A Mermaid source that MermaidKit mis-renders, drops, or rejects
labels: rendering
---

**The source** (paste the exact text; say if it's DOT, Dippin, SQL DDL, or
`git log` output rather than Mermaid):

```mermaid

```

**Expected** — what mermaid.live shows (screenshot welcome):

**Actual** — what MermaidKit did (`nil` from parse? paste
`MermaidParser.diagnose(source)`; rendered but wrong? screenshot welcome):

**Platform & output**: OS and version (macOS/iOS/visionOS, Linux with
`LinuxRaster`, Android, Windows/.NET, WebAssembly, Flutter), MermaidKit
version or commit, and how you rendered it (`MermaidView`/image, PDF, SVG, a
`SceneWire` renderer, or `mermaidkit-term --mode …`).
