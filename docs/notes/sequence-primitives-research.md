# Sequence-diagram primitives: the maximal set for MermaidKit

Research memo, 2026-07-08. Sources: mermaid.js official docs (develop branch,
`syntax/sequenceDiagram.md`, current through v11.15 features), PlantUML
sequence-diagram reference (plantuml.com/sequence-diagram), js-sequence-diagrams
(bramp.github.io), WebSequenceDiagrams (websequencediagrams.com), ZenUML as
integrated into mermaid (mermaid.js.org/syntax/zenuml.html), D2
(d2lang.com/tour/sequence-diagrams). Current-state references are to the
MermaidKit clone at `scratchpad/mermaidkit-ios`.

Current MermaidKit sequence support (baseline for every gap noted below):
`MermaidParser.parseSequence` (MermaidParser.swift:797) — participants/actors
with `as` aliases, arrow tokens `->` `-->` `->>` `-->>` `-x` `--x` `-)` `--)`
degraded to a single `dashed: Bool`, `+`/`-` activation shorthand stripped,
`autonumber` as a text prefix, notes (right of / left of / over) rendered,
fragment/box/activate lines skipped. Model `SequenceDiagram`
(MermaidModels.swift:100) has no arrow kind, no activations, no fragments, no
create/destroy. Layout (DiagramLayoutFlowchart.swift:669) is a flat row list:
one row per message, notes interleaved by `afterMessage`. Scene lowering
(DiagramScene+Sequence.swift) emits heads+notes as nodes, arrows as edges,
message texts as free labels.

---

## A. Canonical primitive taxonomy

Legend for "pull" (honest judgment of real-world usage frequency):
**core** = appears in most diagrams; **common** = appears regularly;
**niche** = real but occasional; **exotic** = rarely seen outside power users.

### A1. Participants & lifelines

| Primitive | Mermaid syntax | Also in | Pull |
|---|---|---|---|
| Implicit participant (first use in a message) | `A->>B: hi` | all five tools | core |
| Explicit `participant` (ordering + declaration) | `participant A` | all five | core |
| Alias | `participant A as Alice` | PlantUML, WSD, js-seq, ZenUML | core |
| `actor` (stick figure) | `actor A` | PlantUML, WSD (`participant:actor`), ZenUML `@Actor` | common |
| Typed participants: boundary/control/entity/database/collections/queue | mermaid v11: `participant A@{ "type": "database" }` (also `"alias"` in the same JSON) | PlantUML keywords (`database Foo`), WSD `participant:database`, ZenUML annotators `@Database` | niche (database/queue are the useful two) |
| Multiline / rich participant labels | mermaid: only via alias + `<br/>` | PlantUML multiline `participant P [ ... ]`, creole markup | niche |
| Participant ordering control | mermaid: declaration order only | PlantUML `participant X order 30` | exotic |
| Stereotypes `<< >>` | — | PlantUML only | exotic |
| Mirrored heads (footer boxes) | mermaid config `mirrorActors` | PlantUML footbox (on by default, `hide footbox`) | common (PlantUML users expect footers; mermaid defaults off) |
| Hide unlinked participants | — | PlantUML `hide unlinked` | exotic |

Current MermaidKit: implicit, explicit, alias, actor — done. Everything else missing.

### A2. Message arrows (line style x head style x direction)

Mermaid's full v11 arrow table (official docs, verbatim semantics):

| Token | Meaning | Pull |
|---|---|---|
| `->` | solid, no head | common (used as "line") |
| `-->` | dotted, no head | common |
| `->>` | solid + filled arrowhead (sync) | core |
| `-->>` | dotted + arrowhead (reply) | core |
| `<<->>` / `<<-->>` | bidirectional heads, solid/dotted (v11.0+) | niche |
| `-x` / `--x` | cross head (lost/failed message) | niche |
| `-)` / `--)` | open head, async | common |
| half-arrows `-\` `--\` `-/` `--/` `\-` `/-` … (v11.12.3+) | top/bottom half heads | exotic (brand new) |
| central connections: `()` appended/prepended, e.g. `Alice->>()John` (v11.12.3+) | arrow meets lifeline center dot | exotic (brand new) |

Beyond mermaid: PlantUML adds colored arrows (`-[#red]>`), circle endpoint
`->o` (found/lost message pairing with `->x`), short arrows `?->`,
reversed-direction spellings (`<-`, `<--` — mermaid deliberately has no
right-to-left spellings; direction comes from operand order), and slanted
arrows `->(10)` (also WSD) representing latency. Pull: colored niche, `->o`
exotic, slanted exotic-but-charming.

js-sequence-diagrams proves the essential floor: exactly `->` `-->` `->>`
`-->>` covers the overwhelming majority of real diagrams.

Current MermaidKit: all 8 classic tokens parse but collapse to `dashed`; head
styles (filled vs open vs cross vs none) are not modeled or drawn.
Bidirectional, half-arrows, central connections unparsed (likely become text
noise or drop).

### A3. Activations / execution specifications

| Primitive | Mermaid syntax | Also in | Pull |
|---|---|---|---|
| Keyword form | `activate A` / `deactivate A` | PlantUML, WSD | common |
| Shorthand on message | `A->>+B: req` / `B-->>-A: resp` | PlantUML `++`/`--`, WSD `+`/`-` | **core** — it's in mermaid's very first doc example; diagrams look visibly wrong without bars |
| Stacked activations (same actor activated twice) | multiple `+` | PlantUML nested, colored | common |
| Colored bars | — | PlantUML `activate A #Gold` | exotic |
| Autoactivation | — | PlantUML `autoactivate on`; ZenUML implicit (every sync call activates callee) | niche (but structural for ZenUML) |

Current MermaidKit: tokens tolerated (stripped so participant names don't get
corrupted), bars not drawn. This is the single most visible gap.

### A4. Combined fragments (frames)

UML 2 defines twelve interaction operators: `alt`, `opt`, `loop`, `break`,
`par`, `seq`, `strict`, `critical`, `neg`, `assert`, `ignore`, `consider`,
plus `ref` (interaction use). What tools actually ship:

| Fragment | Mermaid | PlantUML | WSD | ZenUML | Pull |
|---|---|---|---|---|---|
| `loop label … end` | yes | yes | yes | `while/for/forEach/loop` | **core** |
| `alt label … else label … end` | yes | yes | yes | `if/else if/else` | **core** |
| `opt label … end` | yes | yes | yes | `opt {}` | common |
| `par label … and label … end` (nestable) | yes | yes | yes (`par`, `parallel{}`) | `par {}` | common |
| `critical label … option label … end` | yes | yes | — | — | niche |
| `break label … end` | yes | yes | — | — | niche |
| `rect rgb(…) … end` background band (not a UML frame; no tab) | yes | group coloring `alt#Gold #LightBlue` | — | — | common (used for visual grouping in docs) |
| custom-label `group` | — | `group My label [second label]` | — | — | niche |
| `try/catch/finally` | — | — | — | ZenUML yes | structural for zenuml type |
| `seq`/`strict`/`neg`/`assert`/`ignore`/`consider` | — | — | `seq` only | — | exotic (nobody ships the full UML catalog) |
| `ref over A,B: label` (interaction use) | — | yes | yes | — | niche |

All fragments **nest arbitrarily** (mermaid docs show nested `par`; PlantUML
shows 3-deep alt/loop). Mermaid colors: `rect` takes `rgb()/rgba()`
(hex unsupported — `#` starts a comment).

Current MermaidKit: all fragment keywords recognized only to be skipped
(parser line 856–863, "tracked gap"). Messages inside fragments survive;
frames, guards, and else-lanes vanish.

### A5. Notes & annotations

| Primitive | Mermaid syntax | Also in | Pull |
|---|---|---|---|
| `Note right of A: t` / `left of` | yes | all | **core** |
| `Note over A: t` / `Note over A,B: t` | yes | all | **core** |
| Line breaks in notes/messages | `<br/>` | PlantUML `\n`, WSD `\n` | common |
| Multiline block notes | — | PlantUML/WSD `note over … end note` | common in PlantUML land, absent in mermaid |
| Aligned side-by-side notes | — | PlantUML `note over A / note over B` | exotic |
| Shaped notes `hnote`/`rnote`, `note across` | — | PlantUML | exotic |
| `state over A: STATE` | — | WSD | exotic |
| D2 notes = nested object on actor | structural curiosity only | D2 | — |

Current MermaidKit: all three positions parse and render;
`<br/>` line breaks not handled (single-line measure/draw).

### A6. Grouping of participants (boxes / lanes)

| Primitive | Mermaid syntax | Also in | Pull |
|---|---|---|---|
| `box [color] Label … end` around participant declarations | yes (colors: named, rgb, rgba, hsl, hsla, `transparent`) | PlantUML `box "L" #LightBlue … end box` | common (microservice groupings) |
| Nested boxes | — | PlantUML teoz | exotic |
| D2 groups (labeled container over a message range — actually a fragment) | — | D2 | — |

Current MermaidKit: parsed-and-skipped.

### A7. Lifecycle: create / destroy

Mermaid (v10.3+): `create participant B` / `create actor B` immediately before
the message that creates it ("only the recipient can be created"); `destroy A`
adjacent to the destroying message ("sender or recipient can be destroyed"),
drawn as an X on the lifeline. PlantUML: `create`, `destroy`, and shorthand
`**`/`!!` on arrows. WSD: `A->*B`. Pull: **common** — object-lifecycle
diagrams are a classic sequence-diagram use.
Current MermaidKit: unsupported (a `create participant B` line would parse as
a participant named `participant B`? No — it doesn't hasPrefix "participant",
it has prefix "create"; falls through to message matching and drops).

### A8. Ordering & numbering

| Primitive | Mermaid | Also in | Pull |
|---|---|---|---|
| `autonumber` | yes | PlantUML, WSD | common |
| `autonumber <start> <step>` (decimals to hundredths, v11.15+) | yes | PlantUML `autonumber 10 20` | niche |
| `autonumber off` / stop / resume / format | **not in mermaid** | PlantUML `stop`/`resume`/format string; WSD `autonumber off` | niche |
| Rendered as number chip on the arrow (config `showSequenceNumbers`) | yes | — | (rendering detail; mermaid draws a filled circle badge at the arrow tail, not a text prefix) |

Current MermaidKit: bare `autonumber` only, implemented as a `"1. "` text
prefix — works, but should become a stamped `number` on the message so the
renderer can draw the badge and labels don't get artificially wide.

### A9. Timing: delays, spacing, duration constraints

None of these exist in mermaid:

| Primitive | Syntax | Tool | Pull |
|---|---|---|---|
| Delay | `...` / `...5 minutes later...` | PlantUML | **the most-loved PlantUML-ism** — common there |
| Vertical spacing | `|||` / `||45||` | PlantUML | exotic |
| Duration constraints / anchors | `{start}` `{end}`, `{start} <-> {end}: d` | PlantUML teoz | exotic |
| Slanted (duration) arrows | `A->(10)B` | PlantUML, WSD | exotic |

### A10. Environment messages (to/from outside the diagram)

`[->A: msg` (from left frame edge), `A->]: msg` (to right edge), plus found
(`o->`) / lost (`->x` with the PlantUML meaning) messages. PlantUML and WSD
only; mermaid has none (mermaid's `-x` renders a cross head but has no
frame-edge endpoint concept). Pull: niche — useful for API-boundary diagrams,
but mermaid users have learned to fake it with a dummy participant.

### A11. Dividers / separators

`== Initialization ==` — PlantUML only. Pull: common in PlantUML land; the
cheapest, most-requested "why doesn't mermaid have this" feature (mermaid
users fake it with `Note over All: ——`).

### A12. Links & metadata

Mermaid actor menus: `link A: Dashboard @ https://…` (repeatable) and
`links A: {"Dashboard": "https://…"}` (JSON). Rendered as a popup menu on the
head in mermaid.js — inherently interactive, so for a static renderer this is
metadata, not geometry. Pull: exotic. Nothing comparable in the other tools.

### A13. Titles, comments, escaping, accessibility

| Primitive | Mermaid | Notes | Pull |
|---|---|---|---|
| Comments | `%% …` full line | PlantUML `'`, WSD/js-seq `#` | core (parser hygiene) |
| Entity codes | `#35;` for `#`, `#59;` for `;` | | niche |
| `<br/>` in messages | yes | | common |
| Title | **not in mermaid sequence** (js-seq `Title:`, WSD/PlantUML `title`) | mermaid uses front-matter `title:` | common |
| `accTitle: …` / `accDescr: …` / `accDescr { … }` | yes (all mermaid diagram types) | maps to MermaidKit's existing `MermaidAltText` | niche but cheap and on-mission for a native Apple renderer (VoiceOver) |
| Config: `mirrorActors`, `messageMargin`, `noteAlign`, `wrap`, fonts, margins | `%%{init}%%` / site config | structural ones: `mirrorActors`, `showSequenceNumbers`, `wrap`; the rest cosmetic → `DiagramTheme`/spacing constants | config plumbing, not syntax |

### A14. ZenUML-specific primitives (shared machinery)

MermaidKit already has a `zenuml` type (`MermaidParser+ZenUML.swift`: flat
messages, participant kinds actor/boundary/control/entity/database, no control
flow). ZenUML's full set: sync `A.method()` with **implicit activation and
nesting via `{}`**, async `A->B: msg`, `new` creation, replies via `return x`
/ `@return` / `x = A.method()`, `if/else if/else`, `while/for/forEach/loop`,
`opt`, `par`, `try/catch/finally`. Every one of these lowers onto the same
render primitives as sequence: lifelines, activation bars, fragment frames,
reply arrows, create heads. **Build the frame/bar layout machinery once,
generically, and the zenuml type inherits it.**

### A15. D2's structural lessons (not syntax to adopt)

D2 models activations as *named spans* (nested objects on an actor —
`alice.span1 -> bob`), fragments as generic labeled containers over a message
range, and notes as childless nested objects. Two takeaways for MermaidKit:
(1) activation bars are first-class geometry objects with identity, which is
exactly what the scene IR/linter wants; (2) a fragment is fundamentally
"a labeled rect spanning a row range x a participant range" — the same
computed geometry regardless of which keyword opened it.

---

## B. The maximal target set for MermaidKit

### Tier 1 — mermaid-parity, structural (must render; content is lost or lies without them)

1. **Fragment frames**: `loop`, `alt/else`, `opt`, `par/and`,
   `critical/option`, `break` — with label tab, guard text, dashed
   else/and/option dividers, arbitrary nesting. *(the tracked gap; biggest
   correctness win)*
2. **`rect rgb()/rgba() … end`** background bands (same row-span machinery,
   no tab, painted behind).
3. **Activation bars** as real bars: `+`/`-` shorthand, `activate`/
   `deactivate` keywords, stacking (nested bars offset right), arrows
   anchoring to the bar edge.
4. **`box [color] Label … end`** participant groupings with header label and
   tinted background.
5. **create / destroy**: lifeline starts at the create row (head box drawn
   mid-diagram), X marker and lifeline end at the destroy row.
6. **Arrow-head fidelity**: model line style x head style; draw filled
   (`->>`), open/async (`-)`), cross (`-x`), headless (`->`), and
   bidirectional `<<->>`/`<<-->>`.
7. **autonumber `<start> <step>`** with numbers stored on the message and
   rendered as tail badges (plus `showSequenceNumbers`-equivalent theme flag).
8. **`<br/>` line breaks** in messages and notes (multi-line measure + draw).
9. **Comments `%%` and entity codes** (parser hygiene; verify `%%` is already
   stripped upstream).

### Tier 2 — mermaid-parity, nice-to-have

10. **Typed participants** `@{ "type": "database" | "queue" | "boundary" |
    "control" | "entity" | "collections" }` + `@{"alias": …}` JSON form —
    database cylinder and queue are the two with real pull; the Booch trio can
    share simple glyphs. (Reuses ZenUML's `ParticipantKind`.)
11. **`mirrorActors` footer heads** (bottom-mirrored participant boxes) —
    theme/config flag; PlantUML refugees expect it.
12. **accTitle / accDescr** → `MermaidAltText` + VoiceOver label on
    `MermaidView`. Cheap, differentiating on Apple platforms.
13. **Actor links/menus** (`link`/`links`) — parse into participant metadata;
    render nothing (or a subtle affordance); expose for host apps. Don't build
    popup UI.
14. **Half-arrows and central connections `()`** (v11.12.3+) — parse-tolerate
    immediately (never corrupt participant names), render properly later;
    usage is near zero today.
15. **`wrap` / max-message-width** soft-wrapping of long message texts.

### Tier 3 — beyond mermaid (catalog complete; adoption mostly NOT recommended)

16. PlantUML **delays `...`** and **dividers `== title ==`** — genuinely loved,
    trivially cheap in a row-stream model (each is just another row kind).
17. PlantUML **`return`** keyword (auto-reply from newest activation).
18. **`ref over`** interaction-use boxes; **incoming/outgoing `[->` `->]`**;
    **duration constraints/anchors**; found/lost `->o`; colored arrows;
    `group` custom labels; multiline `note … end note`.
19. ZenUML control flow (`try/catch/finally`, nesting, returns) — **yes, but
    as the zenuml grammar**, not as sequence extensions.

**Recommendation on extending beyond mermaid syntax: don't.** MermaidKit's
value proposition is "what mermaid.js renders, we render natively" — Quoin
documents travel to GitHub/GitLab/editors where mermaid.js is the arbiter, so
any MermaidKit-only syntax creates documents that break everywhere else.
That asymmetry (renders at home, errors in the PR review) is worse than the
missing feature. The honest carve-outs: (a) *tolerate* PlantUML-isms in the
parser where they're unambiguous (never corrupt a diagram over them), but
don't advertise; (b) keep the internal model expressive enough for delays/
dividers/refs so a future `plantuml`-dialect front-end or an upstream mermaid
addition is a parser-only change — mermaid has a track record of absorbing
PlantUML features (typed participants and bidirectional arrows both landed in
v11), so model headroom is the cheap bet. If Quoin ever wants dividers, the
mermaid-compatible answer users already use is `Note over <all>: == title ==`,
which MermaidKit renders today.

---

## C. Layout & architecture implications for MermaidKit

### C1. The row-stream model (the one refactor everything hangs off)

Today `layout(_:SequenceDiagram:)` builds a flat row list: `rowOfMessage(i) =
i + notesBefore(i)`. Fragments break this. The minimal generalization —
keep rows, make them a typed stream:

```swift
enum SequenceRow {                    // parser output, source order
    case message(index: Int)          // into diagram.messages
    case note(index: Int)
    case fragmentOpen(kind: FragmentKind, label: String)   // loop/alt/opt/par/critical/break/rect/…
    case fragmentDivider(kind: DividerKind, label: String) // else / and / option
    case fragmentClose
    // Tier-3 headroom (parser never emits these today):
    // case divider(label: String), delay(label: String?)
}
```

- **Parser**: replace the skip-list with a stack machine; unbalanced `end`s
  degrade gracefully (auto-close at EOF, ignore orphan `end`) — never fail the
  whole diagram, matching the project's "content survives" ethic. The model
  gains `rows: [SequenceRow]`, and `Note.afterMessage` retires in favor of
  note rows (keep the field for source compatibility if needed).
- **Layout, pass 1 (y)**: walk rows top-down assigning `y`. `fragmentOpen`
  rows get header height (tab + guard label); `fragmentDivider` a divider
  row; `fragmentClose` a small padding row. Variable row heights (multiline
  `<br/>` texts, tall notes) fall out naturally once `y` is accumulated
  rather than `row * 34`.
- **Layout, pass 2 (x)**: a fragment's rect spans
  `[minLifelineX − pad·depthL, maxLifelineX + pad·depthR]` over the
  participants *touched by any row inside it* (messages' endpoints, notes'
  extents, nested frames' rects), where the per-side depth padding (≈8pt per
  nesting level) is what keeps nested frames visually distinct — compute by
  interval union bottom-up over the fragment tree. Frames also inflate
  **column widths**: a guard label (`[x > 0]`) and the tab must fit, so the
  column-widening loop must consider fragment labels, and self-message loops +
  right-edge frames must widen the canvas (extend the existing last-lifeline
  logic).
- **`rect`** is the same span computation with `isBackground: true` — painted
  first, no tab, no divider rows.
- **`box`** (participant grouping) is *columnar*, not row-based: a rect from
  above the head boxes to `lifelineBottom` (or just around heads, mermaid
  draws full-height tinted band behind heads + a label above) spanning member
  columns; layout-wise it only adds head-row height and inter-box gutters.

`SequenceLayout` gains: `frames: [Frame]` (rect, kind, label, tab rect,
divider segments+labels, depth, `isBackground`), `bars: [ActivationBar]`,
`boxes: [ParticipantBox]`, and per-head `lifelineTop/lifelineBottom`
(create/destroy). Renderer additions in `DiagramRenderer+Sequence.swift` are
then mechanical: rounded-rect frame + folded-corner tab + centered
guard text + dashed dividers, all behind arrows.

### C2. Activation bars as per-lifeline depth intervals

Semantic pass over the row stream keeping `active[participant] = stack of
openBarIndices`: `+`/`activate` pushes (bar opens at the message's y),
`-`/`deactivate` pops (bar closes at that y). Geometry:
`x = lifelineX − barW/2 + depth·barW·0.6` (mermaid stacks right), width ≈ 8pt,
y-interval = [openRow.y, closeRow.y]. Unclosed bars run to `lifelineBottom`;
pops of empty stacks are ignored (tolerance, again). **Arrow endpoints must
then anchor to the topmost bar's edge, not lifeline center** — sender exits
from the bar's near side, receiver enters the far side; self-message loops
start/end on the bar's right edge. This is the fiddly part; get it right once
and ZenUML's implicit activation nesting reuses it wholesale.

### C3. Scene IR & geometry linter

- **Frames, rects, and boxes lower as `isContainer: true` nodes** — the
  existing linter already exempts containers from `edge-occludes-node` and
  `nodes-overlap` while keeping them for plot-bounds checks
  (DiagramScene.swift:143). Add sequence-specific checks:
  `frame-contains-rows` (every message/note row opened inside a frame lies
  within its rect, with ≥4pt padding), `frames-properly-nested` (any two frame
  rects are disjoint-or-strictly-nested with ≥4pt clearance — exactly the
  class of bug eyeballing misses, per the "lint geometry, don't trust vision"
  memory), and `frame-tab-clear` (tab/guard label doesn't collide with the
  first row's arrow or label).
- **Activation bars** are neither obstacles nor containers: arrows *terminate
  on* them by design, and they deliberately overlap their own lifeline and
  their parent bar. Give the scene `Node` a role (or a `bars` side-channel)
  so the occlusion check skips them, plus checks: `bar-on-lifeline` (bar
  within its lifeline's x-band), `sibling-bars-distinct` (stacked bars offset
  by ≥ half a bar width), `arrow-meets-bar-edge` (endpoint x equals the
  active bar edge ±1pt when a bar is open).
- **Note boxes stay opaque nodes** (already correct), but a note inside a
  frame must also satisfy `frame-contains-rows`.
- Number badges and guard texts join `labels` as `backed` labels (exempt from
  `edge-cuts-label` by the existing rule).

### C4. Model-compatibility notes

`SequenceDiagram.Message` grows `kind: ArrowKind` (line: solid/dotted x head:
none/filled/open/cross/bidirectional), `number: Int?` (or Decimal for v11.15
fractional steps), `activateTarget/deactivateSender: Bool`. `Participant`
grows `kind: ParticipantKind` (unify with ZenUML's), `createdAtRow: Int?`,
`destroyedAtRow: Int?`, `links: [(label, url)]`. All additive with defaulted
properties — source-compatible for Quoin; MermaidKit is pre-1.0 so a tag bump
(0.3.0) suffices.

---

## D. Staged implementation plan

Effort in focused dev-days, ordered by user-visible value per effort. Stages
1–3 need no layout refactor and could ship as one release.

| # | Stage | What ships | Effort | Value |
|---|---|---|---|---|
| 1 | Arrow fidelity | `ArrowKind` in model+parser (all 8 classic tokens keep head identity), `<<->>`/`<<-->>`, renderer draws filled/open/cross/none/bidi heads; parse-tolerate half-arrows and `()` (strip, keep message) | 1d | High — every async/reply diagram stops lying about head semantics |
| 2 | Autonumber done right | `autonumber [start [step]]`, number on Message, tail badge rendering | 0.5d | Medium |
| 3 | Multiline text | `<br/>` in messages/notes; variable row heights groundwork (accumulated y) | 0.5–1d | Medium |
| 4 | **Row-stream refactor + fragment frames** | Stack-machine parser (`rows:`), two-pass layout, frames for loop/alt/else/opt/par/and/critical/option/break, `rect` bands, nesting, linter frame checks | 3–4d | **Highest — the tracked gap; unlocks everything after** |
| 5 | Activation bars | `+`/`-`, `activate/deactivate`, stacking, arrows anchored to bar edges, linter bar checks | 1.5–2d | High — diagrams match mermaid's canonical look |
| 6 | Boxes | `box [color] Label … end` tinted columnar groups | 0.5–1d (after 4) | Medium |
| 7 | create / destroy | Mid-diagram head placement, X marker, partial lifelines | 1–1.5d | Medium |
| 8 | Typed participants | `@{ "type": … }` JSON parse, database/queue/boundary/control/entity/collections glyphs (share with ZenUML kinds) | 1–1.5d | Low-medium |
| 9 | Config & a11y | `mirrorActors` footers, `showSequenceNumbers`, `wrap`, accTitle/accDescr → MermaidAltText/VoiceOver | 1d | Low-medium |
| 10 | Links metadata | `link`/`links` parsed to participant metadata, exposed not rendered | 0.5d | Low |
| 11 | ZenUML uplift | Reuse frames/bars/replies for zenuml control flow (`if/else`, loops, `try/catch/finally`, nesting, `return`, `new`) | 2–3d (after 4+5) | Medium — second diagram type for one machinery |
| — | Tier 3 (delays/dividers/ref/`[->`) | Not scheduled; model headroom only (row kinds reserved) | — | Revisit only if mermaid upstream adopts them |

Total to full mermaid parity (stages 1–10): ~11–14 dev-days. The dependency
spine is 4 → 5 → (6,7,11); stages 1–3 are independent quick wins.
