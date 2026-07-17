# Runtime plugins: frontends & backends without writing Swift

A design sketch for letting people extend MermaidKit — new input formats
(frontends) and new output formats (backends) — at runtime, in any language, or
by handing a spec to a coding agent. Not yet implemented; this captures the shape
so we build the right thing.

## The seam is the IR, not the code

MermaidKit already funnels everything through a small set of value types. A
**frontend** is `text → IR` (`DOTParser`/`DippinParser`/`SQLDDLParser` produce
`Flowchart`/`ERDiagram`), and a **backend** is `IR/scene → bytes` (the raster
renderer, the terminal tiers, `DOTExporter`). So we don't generalize "frontends"
or "backends" — we generalize the **thing they exchange**. Make the IR and the
laid-out scene serializable and the plugin boundary writes itself.

- A frontend plugin reads source text and emits **IR-as-JSON**; MermaidKit
  decodes it into the real `Flowchart`/`ERDiagram`/… and runs its own layout,
  linter, and renderer. The plugin never touches Swift or CoreGraphics.
- A backend plugin reads **scene-JSON** (+ theme) and writes SVG/TikZ/DOT/…
  `DiagramScene` is *already* `Codable`, so the backend contract is 80% done.

Prep work: give the frontend IRs a `Codable` conformance (they're plain value
types today) and freeze a documented JSON shape. **That shape is the plugin API.**
No FFI, no embedded interpreter required for the basic version.

## Loader mechanisms — and the platform catch

Three ways to actually run a plugin; MermaidKit's iOS/visionOS target forces the
choice, because that sandbox can neither spawn subprocesses nor JIT.

| Mechanism | Languages | Runs on | Trust | Cost |
|---|---|---|---|---|
| **Subprocess** (stdin/stdout JSON) | anything | macOS, Linux, CLI, server | unsandboxed (arbitrary code) | spawn per call; **not iOS** |
| **Embedded WASM** (WasmKit, pure Swift) | anything → `.wasm` | **everywhere incl. iOS/visionOS** | **sandboxed** (safe for untrusted) | interp overhead; more integration |
| Embedded JS / Lua | JS or Lua | JS = Apple-only (JavaScriptCore); Lua = portable + C dep | scriptable sandbox | medium |

The honest split: **subprocess is the easy 80%** — perfect for the CLI, a server,
or macOS — but on-device plugins need **WASM via WasmKit**, the only portable,
sandboxed path that also runs on iOS. That's the security story too: subprocess
plugins are "trust the author"; WASM plugins are "trust nobody, sandbox
everything," which is what you want for plugins you didn't write.

## The LLM authoring kit

Orthogonal to *loading* is *authoring*, and it's the highest-leverage piece. Ship:

1. **A JSON Schema** per IR — machine-checkable, not prose.
2. **A conformance harness** — sample inputs + expected-shape assertions a plugin
   validates against automatically.
3. **A paste-ready prompt**: "Write a MermaidKit frontend that parses `<format>`.
   Read source on stdin, emit JSON conforming to `<schema>`. Golden examples:
   `<…>`. Validate against `<harness>`."

Hand that to any coding agent and it builds a correct, self-verifying plugin with
zero knowledge of MermaidKit's internals — because the schema and conformance
tests *are* the spec. Very on-brand for a library whose thesis is "structured,
checkable, no magic."

## Build order

1. **`Codable` IRs + a frozen JSON shape** — the real leverage; small.
2. **Subprocess frontend-plugin loader** — a `~/.mermaidkit/plugins/` directory
   with a small manifest (name, kind, file-match/sniff, invoke command). Prove it
   by reimplementing the **Dippin frontend as an external Python plugin**: same
   output, zero Swift. That's the end-to-end demo.
3. **The authoring kit** (schema + harness + prompt) — cheap, and it's what turns
   this into an ecosystem.
4. **WASM tier** — the ambitious, sandboxed, everywhere-including-iOS version.

## Design constraints to honor up front

- **Version the contract.** The JSON schema becomes a public API you can't
  casually break — tag it (`"mermaidkit.ir/v1"`) from day one.
- **Keep the caps.** A plugin's output still feeds the layout engine, so the same
  `maxTextSize`/`maxEdges`/raster-dimension guards must apply to plugin output —
  a plugin must not be able to hand the engine pathological input.
- **Degrade like a native frontend.** A plugin that errors, times out, or emits
  invalid JSON returns `nil` (host falls back to showing the raw source) — never
  a crash or a hang.
- **Native parsers win ties.** Discovery order: built-in parsers first, then
  plugins, so a plugin can add formats but never silently shadow a shipped one.

Related: `ir-compilation-targets.md`, `terminal-rendering-capabilities.md`.
