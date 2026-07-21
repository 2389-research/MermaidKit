# MermaidKit coverage audit vs upstream mermaid.js

> **⟳ Reconciled 2026-07-15 against MermaidKit 1.0.** This audit was written 2026-07-07 against an older snapshot (`scratchpad/mermaidkit-ios`). Since then a **parser-honesty pass** plus a **flowchart/sequence rewrite** have landed. Net effect on this document:
> - **Part A is obsolete** — all 7 "missing" types now ship end-to-end (6 fully; EventModeling partial). See the Part A banner.
> - **Largely FIXED:** flowchart (8/13), sequenceDiagram (12 gaps + the alias bug), packet-beta (→ 0 gaps), radar-beta (3/4), treemap-beta (2/3), gantt phantom-task hazard + duration units, and the cross-cutting front-matter fence.
> - **Still accurate:** classDiagram, stateDiagram-v2, erDiagram (untouched by the honesty pass), plus mindmap, block/kanban/architecture/sankey/pie/quadrant/requirement and several beta feature-gaps.
> - **Parser locations** — the big-five parsers cited below (flowchart/sequence/class/state/er) still live in the monolithic `MermaidParser.swift`; only the newer diagram types have per-type `MermaidParser+<Type>.swift` files. Cited `MermaidParser.swift` line numbers may have drifted since this audit.
>
> Individual sections carry a bold **Reconciled 2026-07-15:** note; resolved worst-gaps are struck through and tagged **[FIXED]/[PARTIAL]/[remains]**.

Date: 2026-07-07. Audited: MermaidKit clone at `scratchpad/mermaidkit-ios` (Sources/MermaidLayout parsers + models + scene/layout files) against live mermaid.js docs (mermaid.js.org). Scope per policy: STRUCTURAL gaps only count; styling/theming = COSMETIC (noted, not counted); click/interaction/animation = N/A.

## Summary table

Status/worst-gap cells below carry the reconciled 1.0 verdict; struck-through text is the resolved 2026-07-07 finding.

| Type | Status | Structural gaps | Worst gap | Effort to close |
|---|---|---|---|---|
| flowchart | 8/13 fixed | 13 → 4+1 partial | ~~chained edges `A --> B --> C` silently erase the whole line~~ **[FIXED]** — remains: invisible `~~~`, 8 classic shapes, `@{shape}` spec, markdown/entities | L (chains/`&` M; subgraphs, `@{shape}` L) |
| sequenceDiagram | 12+bug fixed | 12 (+1 bug) → 1 | ~~`->>+`/`->>-` activation shorthand mints phantom `+John`/`-John` lifelines~~ **[FIXED]** — remains only obscure `A->>()E:` phantom | L (S fix for phantoms; fragments L) |
| classDiagram | 0 fixed | 10 **[remains]** | `class X["label"]` splits one class into two; multiplicity discarded (generics now also split) | M–L |
| stateDiagram-v2 | 0 fixed | 6 **[remains]** | `id : description` lines dropped (can delete the state); note bodies leak as phantom states | M (2 worst fixes are S) |
| erDiagram | 0 fixed | 7 **[remains]** | word-form relationships (`only one to zero or more`) vanish entirely | M |
| journey | complete | 0 | — | — |
| gantt | phantom+units fixed | 8 → 3+4 partial | ~~colon-bearing directives become **phantom task bars**~~ **[FIXED]**; units `y/M/s/ms` **[FIXED]**; non-ISO `dateFormat`/`axisFormat`/`until` **[PARTIAL]** (corruption gone, feature unrendered) | L (phantom guard is S) |
| pie | near-complete | 2 **[remains]** | negative-value slice silently dropped | S |
| quadrantChart | near-complete | 1 **[remains]** | zero-point chart rejected (visible fallback — least-bad class) | S |
| requirementDiagram | near-complete | 2 **[remains]** | quoted multi-word names mangled; relations to them dangle | S–M |
| gitGraph | cherry-pick fixed | 6 → 5 | ~~`cherry-pick` commit (id+tag) silently erased~~ **[FIXED]** — remains: `type:`, multi-tag, `order:`, orientation, `mainBranchName` | M–L (TB/BT orientation L) |
| C4 | RelIndex fixed | 6 → 5 | ~~`RelIndex` args shift → fabricated relation from node "1"~~ **[FIXED]** — remains: boundaries, deploy nodes, Db/Queue, BiRel (now one-way), multi-line | M–L (boundaries/deploy nodes L) |
| mindmap | 0 fixed | 4 **[remains]** | bang/cloud delimiters `))…((` leak into drawn labels | S–M |
| timeline | `<br>` fixed | 2 → 1+partial | ~~`<br>` kept verbatim~~ **[FIXED]** (**[PARTIAL]** — card sizing lags, multi-line events can overflow); LR/TD direction **[remains]** | L (only if direction wanted) |
| zenuml | `//`+assign fixed | 8 → 6+partial | ~~`//`-comments / `x = A.method()` fabricate participants~~ **[FIXED]**; braces **[PARTIAL]**; `new`/`return`/`as`/fragments **[remain]** | L (corruption guards S) |
| sankey-beta | strongest | 2 (minor) **[remains]** | zero-value row dropped | S |
| xychart-beta | labeled pts partial | 4 → 3+partial | labeled points: colon-form `[10:"l",8]` **[FIXED]**, space-form **[remains]**; horizontal/numeric-x/quoted-comma **[remain]** | M |
| block-beta | 0 fixed | 7 **[remains]** | `A --- B` inserts a phantom `---` block; `a:2` width breaks all edges to the block | M–L (composites L) |
| packet-beta | **FIXED → 0** | ~~1~~ 0 | ~~`+N` relative fields render a confidently wrong bit layout~~ **[FIXED]** (cursor + width) | S |
| kanban | 0 fixed | 3 **[remains]** | `@{ assigned: … }` silently dropped; `priority` parsed but never drawn | S–M |
| architecture-beta | 0 fixed | 4 **[remains]** | `{group}` edges silently dropped; nesting flattened; `<--` arrowhead on wrong end | M |
| radar-beta | 3/4 fixed | 4 → 1 | ~~positional `{1, 2, 3}` values → all curves flat at min~~ **[FIXED]** (+ axis append, auto-max); multiple curves per line **[remains]** | S |
| treemap-beta | 2/3 fixed | 3 → 1 | ~~`:::class` suffix destroys the leaf's value AND label~~ **[FIXED]** (+ classDef-as-node); unquoted `Foo: 2` `:`-truncation **[remains]** | S |
| **Cross-cutting** | **FIXED** | ~~1~~ 0 | ~~YAML front-matter (`---\nconfig:…\n---`) rejects the whole diagram, for ALL 23 types~~ **[FIXED]** — `parse` now `stripMetadata`-strips the fence and surfaces title/accTitle/accDescr | S strip / M honor |

**Totals (2026-07-07): 115 structural gaps across 23 types + 1 cross-cutting.** **Reconciled 2026-07-15:** roughly a third of the catalogued gaps are now closed — disproportionately the *worst* ones (the silent-fabrication / phantom-content class the audit called out). packet-beta and the cross-cutting front-matter fence are down to zero; flowchart, sequence, radar, treemap, gantt-phantoms and cherry-pick/RelIndex are largely fixed. classDiagram, stateDiagram-v2 and erDiagram were untouched and hold their full counts (the big four now really carry only class+state; flowchart/sequence are mostly closed). All **30** diagram types (23 audited + the 7 former "Part A" types) now ship end-to-end. Journey, sankey, quadrant, pie, requirement, timeline, kanban were already in good shape (≤3 gaps each).

**Recurring pattern (worst finding of the audit):** these parsers almost never *reject*. Unrecognized syntax either falls through a per-line `continue` (silent drop) or gets half-matched by a substring connector search (phantom/corrupted content). Because the styled-source fallback only triggers when the whole parse returns nil, authors get a confident-looking but wrong diagram instead of the fallback. `ParseDiagnostics.swift` defines a `.note` severity for exactly this ("author content set aside") and **no parser currently emits it**.

---

# PART A — New mermaid.js diagram types ~~MermaidKit lacks~~ **NOW SHIPPED in 1.0**

> **Reconciled 2026-07-15: this entire Part is obsolete as a gap list — all 7 now ship.** Six ship end-to-end (parser → layout → renderer → fixture): **Swimlane, Venn, Ishikawa, Wardley, Cynefin, TreeView**. **EventModeling is PARTIAL** (see its tagged subsection). Renderers live in `DiagramRenderer+NewTypes.swift` (TreeView/Venn/Cynefin/Wardley) and `DiagramRenderer+MethodDiagrams.swift` (Ishikawa/EventModeling/Swimlane). The per-type grammar notes below are retained as implementation reference.

Verdict (2026-07-07): **all 7 are real, shipped types** with docs pages. Ishikawa's page is thin (near-stub) but the type shipped in v11.13.0. None is vaporware. **(2026-07-15: all 7 are now implemented in MermaidKit itself — 6 fully, EventModeling partially.)**

## Swimlanes (`swimlane-beta`, v11.16.0+) — SHIPPED, docs complete
Flowchart semantics partitioned into lanes. Header + direction (TB/TD/BT/LR/RL); lanes are `subgraph id[Label] … end`; nodes are a flowchart subset (`[ ]`, `( )`, `([ ])`, `{ }`, `(( ))`); edges `-->`, `---`, `-->|label|`, `-.->`, `==>`, cross-lane allowed; `accTitle`/`accDescr`.
```
swimlane-beta LR
  subgraph ops[Operations]
    A[Receive order] --> B{In stock?}
  end
  subgraph wh[Warehouse]
    C[Pick items]
  end
  B -->|yes| C
```
Effort: **L** — parser nearly free (reuse flowchart node/edge parse, subgraph-as-lane), but layout is a constrained layered layout: nodes pinned to lane bands while topological order flows in the diagram direction. Existing DiagramLayoutFlowchart/Layering is the starting point; lane-band constraints + cross-lane routing are real work.

## Event Modeling (`eventmodeling`, v11.15.0+) — **[PARTIAL] in 1.0**
> **Reconciled 2026-07-15:** core `tf`/`timeframe` frames and type-derived lanes render. **Not yet handled:** inline `{…}` data, `[[…]]` data-blocks, `->>` connectors, and `Namespace.Entity` lanes.

Timeline of frames across fixed swimlanes (UI/Automation, Command/ReadModel, Events). `tf|timeframe <nn> <type> <Entity>` with types `ui, command|cmd, readmodel|rmo, event|evt, processor|pcr`; inline data `{…}`; data blocks `[[identifier]]` with type annotations (`json`/`html`/`text`); `rf|resetframe <nn>`; `->>` multi-connect; `Namespace.Entity` adds swimlanes.
Effort: **M** — strict grid layout (time on x, type-determined lanes on y) with elbow connectors; simpler than swimlanes because lane membership is derived from entity type. Data-block chips are the fiddly part.

## Venn (`venn-beta`) — SHIPPED, docs complete
`set A ["label"]` (optional `:N` size), `union A, B ["label"]` (2+ sets), indented `text` nodes, `style` (cosmetic).
Effort: **S/M** — 2–3 overlapping circles, fixed geometry; the work is label placement in intersection regions (lens/curved-triangle centroids) and proportional sizing. Trivial CoreGraphics.

## Ishikawa / fishbone (`ishikawa-beta`, v11.13.0) — SHIPPED, docs THIN
Docs document only the core rule: first line = problem (fish head), indented lines = causes/sub-causes; syntax explicitly "may evolve".
Effort: **S parser / M layout** — parsing is the mindmap indentation walk already in the codebase; layout is bespoke fishbone geometry (spine, alternating diagonal ribs, twigs). Consider deferring until syntax stabilizes, or ship the minimal grammar.

## Wardley (`wardley-beta`) — SHIPPED, docs complete
`component Name [visibility, evolution]` (0–1 each; OWM convention: y first), `anchor`, links `->`/`-->`, flow `+>`, `note "…" [v,e]`, `evolve Name targetEvo` (dashed arrow to future position), decorators `(inertia)`, `(build|buy|outsource|market)`.
Effort: **M** — no graph layout at all (coordinates are author-given): 2D scatter + axis chrome (4 evolution bands, visibility axis) + evolve arrows. Label collision avoidance is the only nontrivial bit. **Best value-to-effort of the seven.**

## Cynefin (`cynefin-beta`, v11.16.0+) — SHIPPED, docs complete
Domain blocks `complex/complicated/clear/chaotic/confusion` containing quoted item strings; transitions `complex --> complicated : "label"`; `title`. Config: width/height/padding, showDomainDescriptions, boundaryAmplitude (wavy borders), seed.
Effort: **S** — fixed 2×2 + center ellipse; items are per-quadrant text lists; transitions arrows between fixed regions. Easiest of the seven.

## TreeView (`treeView-beta`, v11.14.0+) — SHIPPED, docs complete
Indentation hierarchy; trailing `/` = directory (bold); box-drawing input (`├──`/`└──`) auto-detected; quoted labels; `:::className`; `## inline description`; `icon(name)`; `%%` comments. Config: showIcons, icon packs, rowIndent, padding, lineThickness.
Effort: **S** — indentation parse (reuse mindmap/treemap walk) + vertical list with connector lines. Reduce icon packs to a small built-in folder/file glyph set (same policy as architecture-beta's iconify treatment).

---

# PART B — Structural gaps in the existing 23 types

Line references are to files under `Sources/MermaidLayout/` in the audited clone. Legend: **SD** = silent drop, **PC** = phantom/corrupted content (worse — invents wrong content), **DEG** = degraded but visible, **ERR** = visible whole-diagram fallback.

## Cross-cutting: YAML front-matter (all 23 types)
**Reconciled 2026-07-15: FIXED.** `MermaidParser.parse` now runs `stripMetadata` (`MermaidParser+Metadata.swift`) which removes the leading `---` fence before header detection and surfaces `title`/`accTitle`/`accDescr` via `DiagramMetadata`. The whole-diagram rejection below no longer occurs.

`MermaidParser.parse` (MermaidParser.swift:87–92) takes the first non-empty non-`%%` line as the header. A doc-standard `---\ntitle: …\nconfig: …\n---` block makes the header `---`, matches nothing → nil → styled-source fallback for the whole diagram. **ERR (visible, not silent) — but every config-bearing doc example fails to native-render.** `%%{init:…}%%` is safely dropped by the `%%` filter. Effort: **S** to strip (+ extract `title:`), **M** to honor config contents.

## flowchart (MermaidParser.swift parseFlowchart L172–311) — 13 structural gaps
> **Reconciled 2026-07-15: 8 FIXED, 1 PARTIAL, 4 remain.** The flowchart rewrite closed the "guard kills the whole line" failure mode entirely — that headline (and the Supported: line, which now understates) is obsolete.
> - **FIXED:** chained edges `A-->B-->C`; `&` fan-out; inline `-- text -->` labels; min-length links; bidirectional (`<-->`/`o--o`/`x--x`); circle/cross ends (honest degrade — plain arrows, no phantom nodes); subgraphs (+ inner direction); edge IDs.
> - **PARTIAL:** thick edges (parse + draw, but no thickness field; the no-arrow `===` form is still dropped).
> - **Remains:** invisible `~~~`; the 8 missing classic shapes (delimiter leak); `@{shape}` (spec dropped, though the separate edge line now survives); markdown / entity codes.

Supported: directions TD/TB/LR/BT/RL; 6 shapes (`[]`, `()`, `([])`, `[()]`, `(())`, `{}`); `-->`, `---`, `-.->`, `-.-`, `==>` (drawn solid); `|label|`; quoted labels; redeclaration label upgrade.
Failure mode: `parseEdgeLine` finds the first connector then `guard let fromNode…toNode… else { return nil }` (L246–248) — any unparseable endpoint kills the entire line (edge + label + both node declarations), and the standalone-node fallback fails on the same text.

| Feature | Syntax | Behavior | Effort |
|---|---|---|---|
| Chained edges | `A --> B --> C` | ~~**SD whole line**~~ **[FIXED]** | M |
| Ampersand fan-out | `A & B --> C & D` | ~~**SD whole line**~~ **[FIXED]** | M |
| Inline edge label | `A-- text -->B` | ~~**SD whole line**~~ **[FIXED]** | S |
| Min-length links | `A ---->B`, `-...-`, `====` | ~~**SD whole line**~~ **[FIXED]** | S |
| Invisible link | `A ~~~ B` | SD (ranking constraint lost) **[remains]** | S |
| Bidirectional | `A <--> B`, `o--o`, `x--x` | ~~SD~~ **[FIXED]** | M |
| Circle/cross ends | `A --o B`, `A --x B` | ~~**PC** phantom nodes~~ **[FIXED]** — honest degrade to plain arrows | M |
| Thick edges | `A ==> B` / `===` | **[PARTIAL]** parse+draw, but no thickness field; no-arrow `===` still dropped | S |
| Subgraphs + inner direction | `subgraph one … end` | ~~SD of grouping~~ **[FIXED]** (recursive cluster layout + inner direction) | L |
| 8 missing classic shapes | `[[ ]]`, `{{ }}`, `[/ /]`, `[\ \]`, `[/ \]`, `[\ /]`, `((( )))`, `>x]` | DEG w/ delimiter leak **[remains]** | M |
| `@{ shape: … }` (~30 shapes) | `A@{ shape: doc }` | **[remains]** spec dropped, but the separate edge line now survives | L |
| Edge IDs | `A e1@--> B` | ~~**SD whole line**~~ **[FIXED]** | S |
| Markdown strings / entity codes | `` A["`**b**`"] ``, `&#35;` | DEG literal **[remains]** | M |

Cosmetic: style/classDef/class/linkStyle skipped — but `:::` on a node token makes the tokenizer reject → node SD. N/A: click, curve/elk config.
**Worst: chained edges — the most common idiom in real flowcharts erases silently.**

## sequenceDiagram (parseSequence L677–732) — 12 gaps (+1 bug)
> **Reconciled 2026-07-15: 12 gaps + the alias bug FIXED, 1 remains.** The sequence rewrite closed nearly everything. The Supported: line ("model holds only participants + messages") is now badly wrong — the model carries Note / Fragment / Box / Event / actor-flag / arrowheads.
> - **FIXED:** `->>+`/`->>-` activation (bars drawn); cross `-x`; async `-)`; bidirectional `<<->>`; activate/deactivate; notes; fragments (loop/alt/opt/par/critical/break with else/and/option); boxes; create/destroy; autonumber; actor figure; the `replacingOccurrences("actor ")` alias bug.
> - **Remains:** only the obscure central-connection `A->>()E:` phantom.

Supported: implicit participants, `participant`/`actor` with `as` alias, `->`, `-->`, `->>`, `-->>`, self-messages. Model holds only participants + messages — no actor flag, activations, notes, fragments, boxes; scene layer confirms nothing else is drawable. **(2026-07-15: this Supported: line is now obsolete — see the reconciliation note above.)**

| Feature | Syntax | Behavior | Effort |
|---|---|---|---|
| Activation shorthand | `Alice->>+John:`, `John->>-Alice:` | ~~**PC — worst in audit**: phantom lifelines~~ **[FIXED]** — activation bars drawn | S strip / M bars |
| Cross arrows | `A-x B:`, `A--x B:` | ~~**SD whole message**~~ **[FIXED]** | S/M |
| Async open arrows | `A-) B:`, `A--) B:` | ~~**SD whole message**~~ **[FIXED]** | S/M |
| Bidirectional | `A<<->>B:` | ~~**PC** phantom `A<<`~~ **[FIXED]** | M |
| Central connection | `A->>()E:` | **PC** phantom `()E` **[remains]** | M |
| activate/deactivate | `activate Bob` | ~~SD — bars never drawn~~ **[FIXED]** | M |
| Notes | `Note right of A: text`, `Note over A,B:` | ~~**SD**~~ **[FIXED]** | M |
| Fragments | `loop/alt/else/opt/par/and/critical/option/break … end` | ~~SD of frames + condition labels~~ **[FIXED]** | L |
| Boxes | `box Aqua Team … end` | ~~SD~~ **[FIXED]** | M |
| create/destroy | `create participant B` | ~~SD~~ **[FIXED]** | M |
| autonumber | `autonumber` | ~~SD~~ **[FIXED]** | S |
| actor figure | `actor Alice` | ~~DEG plain participant~~ **[FIXED]** — actor flag in model | S–M |
| Alias bug | `participant P as an actor guy` | ~~**PC bug**: `replacingOccurrences(of: "actor ", …)`~~ **[FIXED]** | S |

**Worst: `+`/`-` shorthand phantom lifelines — silently mis-draws nearly every real-world sequence diagram.**

## classDiagram (parseClass L492–590) — 10 gaps
**Reconciled 2026-07-15: still accurate — unchanged in 1.0** (the parser-honesty pass did not touch classDiagram). Minor addendum: class generics `List~int~` also *split* the class, slightly worse than the "tildes literal" degrade noted below.

Supported: `class X` / bodies / colon shorthand; attribute-vs-method split; all 8 relation connectors incl. reversed; relation labels; multiplicity tolerated (stripped).

| Feature | Syntax | Behavior | Effort |
|---|---|---|---|
| Multiplicity text | `ClassA "1" --> "*" ClassB` | **SD**: `stripMultiplicity` (L518–523) discards; no model fields | M |
| Class label | `class Animal["Domestic animals"]` | **PC**: class *named* the full literal; relations to `Animal` mint a second class — diagram splits | S |
| Standalone annotation | `<<Interface>>` after class | SD (L552) | S |
| In-body annotation | `class X { <<Service>> }` | DEG: filed as attribute row, not header badge | S |
| Namespaces | `namespace BaseShapes { … }` | SD of grouping (inner classes parse) | L |
| Notes | `note for Duck "can fly"` | **SD** (L552) — note text lost | M |
| direction | `direction LR` | SD (no model field) | M |
| Generics | `List~int~` | DEG: tildes literal (should show `<int>`) | S |
| Two-way relation | `ClassA <|--|> ClassB` | **PC**: `<\|--` matches first, phantom class `\|> ClassB` | S–M |
| Lollipop | `foo --() bar` | **PC**: phantom class `() bar` | M |
| `:::` shorthand | `Animal:::styleClass` | **PC**: colon-shorthand branch (L556–563) adds bogus attribute `::styleClass` | S |

**Worst: multiplicity discarded (most common feature); `class X["label"]` silently splitting a class is nastiest.**

## stateDiagram-v2 (parseState L319–488) — 6 gaps
**Reconciled 2026-07-15: still accurate — unchanged in 1.0** (untouched by the parser-honesty pass; every gap and the Supported: line remain correct).

Supported: `-->` + labels, scope-local `[*]`, composites with recursion, `state "desc" as id`, `state X : desc`, `<<choice/fork/join>>` with back-patching, one global direction, bare ids.

| Feature | Syntax | Behavior | Effort |
|---|---|---|---|
| Description w/o keyword | `s2 : This is a description` | **SD — the docs' canonical form**; bare-id check (L440) fails on spaces → line vanishes; unreferenced state disappears entirely | S |
| Notes | `note right of Active … end note` | **SD + PC**: only header skipped (L379); single-word body lines become **phantom states** | S skip / M render |
| Concurrency | `--` regions in composite | **SD** — regions silently merge | L |
| Composite alias | `state "desc" as id { … }` | **PC**: node id becomes the literal quoted string (L382–390, no `as` in that path) | S |
| `:::styleClass` | `Crash:::bad --> [*]` | **SD of the whole transition** (endpoint guard L368) | S |
| Per-composite direction | `state X { direction LR }` | DEG: first direction in file wins (L462–468) | M |

Minor: cross-scope transitions duplicate nodes per scope. **Worst: `id : description` dropped wholesale.**

## erDiagram (parseER L594–673) — 7 gaps
**Reconciled 2026-07-15: still accurate — unchanged in 1.0** (untouched by the parser-honesty pass). Minor addendum: word-form relationships and bare-entity declarations, when they are the *sole* body content, now hit the visible styled-source fallback rather than a silent drop.

Supported: all 8 crow's-foot glyphs, `--` vs `..` identifying, labels incl. quoted, entity blocks with `type name` attributes.

| Feature | Syntax | Behavior | Effort |
|---|---|---|---|
| Word-form relationships | `CAR only one to zero or more PERSON : allows` | **SD — relationship (and entities declared only there) vanish** (separator loop L640 exhausts) | S |
| Attribute keys | `string plate PK` | SD: tokens past index 1 discarded (L622–626); model has only type+name | M |
| Attribute comments | `string name "comment"` | SD (same path) | M (shares) |
| Entity aliases | `p[Person]` | **PC**: entity literally named `p[Person]`; relation against `p` duplicates | S |
| Quoted entity names | `"ENTITY NAME" { }` | DEG: literal quotes in box | S |
| Bare entity declaration | `CUSTOMER` alone | **SD** unless referenced by a relation | S |
| direction | `direction LR` | SD; layout direction fixed | M |

**Worst: word-form relationship lines disappearing with no diagnostic.**

## journey (MermaidParser+Journey.swift) — 0 gaps
title/section/tasks with score+actors all supported and drawn; score clamps degrade more gracefully than mermaid. Cleanest type in the audit.

## gantt (MermaidParser+Gantt.swift) — 8 gaps + phantom-task hazard
> **Reconciled 2026-07-15:**
> - **FIXED:** the colon-directive phantom-task hazard (a `directiveKeywords` allow-list guard now runs before the task-colon split) and duration units `y/M/s/ms`.
> - **PARTIAL:** `dateFormat` non-ISO, `axisFormat`, `todayMarker`, `until` — the phantom / id-corruption is gone for all four, but the feature itself is still unrendered.
> - **Remains:** excludes/includes, `tickInterval`, `vert`.
>
> The Supported: line now understates (units are broader).

Supported: title, section, done/active/crit/milestone, ids, `after id…`, start+end / start+duration / implicit-after-previous, `d/w/h/m` durations.
Core hazard: any non-task directive containing a colon falls through `guard let colon = line.firstIndex(of: ":")` (L29) and is parsed **as a task — a phantom bar**.

| Feature | Syntax | Behavior | Effort |
|---|---|---|---|
| `dateFormat` non-ISO | `dateFormat DD-MM-YYYY` | **Silent corruption**: directive ignored; `dayOrdinal` (L107–111) only accepts `YYYY-MM-DD` → every bar mistimed | L |
| Date axis / `axisFormat` | `axisFormat %m/%d` | SD (dates normalized to day-0 doubles at parse, L93–99; axis renders integer days). Bonus: `%H:%M` colon → **phantom task "axisFormat %H"** | M–L |
| `todayMarker` | `todayMarker stroke-width:5px…` / `off` | **PC: phantom task "todayMarker stroke-width"**; `off` SD | S guard + M marker |
| excludes/includes/weekend/weekday | `excludes weekends` | SD → durations diverge from mermaid | M |
| `tickInterval` | `tickInterval 1week` | SD | M |
| `until` dependency | `t2 : a, date, until t3` | SD: `until t3` becomes the task id (L57), end lost | S |
| Units `s/ms/M/y` | `1y` | SD: becomes the id, duration defaults 1d (L133–138) | S |
| `vert` markers | `deadline : vert, date` | PC-ish: renders as a normal 1-day bar | M |

N/A `click … href "https://…"` — but the `https://` colon makes it a **phantom task** (needs the same S guard). **Worst in whole audit for fabrication: colon directives become fake bars.**

## pie (MermaidParser+Pie.swift) — 2 gaps
**Reconciled 2026-07-15: still accurate — unchanged in 1.0.**

Supported: title (header or line), quoted labels, decimals, declaration order.
- `showData` flag never read (legend shows % but not raw values) — SD, S.
- Negative values: `guard value >= 0 else { continue }` (L27) — **slice silently dropped and rest renormalize** (mermaid errors) — S.

## quadrantChart (MermaidParser+Quadrant.swift) — 1 gap
**Reconciled 2026-07-15: still accurate — unchanged in 1.0.**

Supported: title, both axes incl. single-ended labels, quadrant-1..4, points with clamping; `:::class` degrades gracefully.
- Zero-point chart: `guard !points.isEmpty` (L43) → **whole-diagram ERR** (mermaid renders the empty grid) — S. Point styling (`radius:`/`color:`) dropped after `]` — cosmetic (radius arguably minor-structural).

## requirementDiagram (MermaidParser+Requirement.swift) — 2 gaps
**Reconciled 2026-07-15: still accurate — unchanged in 1.0.**

Supported: all 6 req kinds, id/text/risk/verifymethod, element type/docref, all 7 relation verbs, both arrow forms, `%%`.
- Quoted names `requirement "test req" {`: header tokens split on whitespace (L141–145) → box named `"test` (**mangled**) and relations to the full name dangle — **PC**, S.
- `direction` ignored — SD, M.

## gitGraph (MermaidParser+GitGraph.swift) — 6 gaps
> **Reconciled 2026-07-15: cherry-pick FIXED** (now renders). **Remains:** commit `type:`, multiple tags, `branch order:`, orientation, `mainBranchName`.

Supported: commit id/tag (quoted/unquoted), branch, checkout/switch, merge with id/tag as two-parent commit.

| Feature | Behavior | Effort |
|---|---|---|
| `cherry-pick id:"A" …` | ~~**SD — whole commit + tag erased**~~ **[FIXED]** — now renders | M |
| `commit type: HIGHLIGHT/REVERSE` | SD (no model field) | M |
| Multiple `tag:` per commit | SD beyond the first (`field()` uses first range) | S |
| `branch X order: N` | SD (name only kept, L45) — lane order wrong | S |
| Orientation `LR:/TB:/BT:` | SD — layout hardcoded LR (DiagramLayoutGitGraph.swift:8–12) | L |
| `mainBranchName` (frontmatter) | `main` hardcoded (L11); `checkout master` pre-declaration silently ignored | M |

**Worst: cherry-pick commits vanish.**

## C4 (MermaidParser+C4.swift) — 6 gaps
> **Reconciled 2026-07-15: `RelIndex` arg-shift FIXED. Remains:** boundaries, deployment nodes, Db/Queue shapes, `BiRel` (now captured but drawn one-directional), multi-line macros.

Supported: all 5 headers dispatch, title, Person/System/Container/Component families with `_Ext`, correct per-kind arg order, Rel with techn. sprites/tags/links = N/A (unimplemented upstream too).

| Feature | Behavior | Effort |
|---|---|---|
| `RelIndex(1,a,b,"l")` | ~~**PC**: args shift → relation from phantom node "1"~~ **[FIXED]** | S + M badges |
| Boundaries (all 4 forms) | SD of frame AND its label (`contains("Boundary") { continue }`, L112); children flatten | L |
| `Deployment_Node`/`Node/_L/_R` | SD of node labels/tech; C4Deployment renders bare | L |
| Db/Queue shape variants | DEG: collapse to base kind — cylinder/pipe shapes lost | M |
| `BiRel` | **[PARTIAL]** now captured, still drawn one-directional (was DEG one-directional) | S–M |
| Multi-line macro calls | SD (needs `(` and `)` on one line, L94–98) | S |

Cosmetic: UpdateElementStyle/UpdateRelStyle/UpdateLayoutConfig skipped. **Worst: RelIndex corruption.**

## mindmap (MermaidParser+Mindmap.swift) — 4 gaps
**Reconciled 2026-07-15: still accurate — unchanged in 1.0** (all 4 gaps remain — shape identity, bang/cloud leak, inline `:::`, markdown).

Supported: indentation tree with nearest-ancestor attach, tab=2.

| Feature | Behavior | Effort |
|---|---|---|
| Shape identity (`[x]`, `(x)`, `((x))`, `{{x}}`) | SD: wrappers stripped, all nodes drawn as same box (model has label+children only) | M |
| Bang `))x((` / cloud `)x(` | **PC: delimiters leak into the drawn label** (close>open fails, raw string returned, L59–62) | S + M shapes |
| Inline `:::class` | PC: `":::urgent"` leaks into label text | S |
| Markdown strings | DEG: backticks/`**` literal | M |

Own-line `::icon()` / `:::` skipped (cosmetic/N-A). **Worst: bang/cloud delimiter leak.**

## timeline (MermaidParser+Timeline.swift) — 2 gaps
> **Reconciled 2026-07-15:** `<br>` **FIXED** at the render layer (**PARTIAL** — layout card sizing lags, so multi-line events can overflow their card). LR/TD direction **remains**.

Supported: title, sections, `period : e : e`, continuation `: e` lines, bare periods.
- `timeline LR/TD` direction token discarded; layout is a fixed vertical spine (itself a departure from mermaid's horizontal default) — L. **[remains]**
- ~~`<br>` kept verbatim~~ **[FIXED]** at render (**[PARTIAL]** — card sizing lags; multi-line events can overflow) — S.
No silent content loss; cleanest after journey.

## zenuml (MermaidParser+ZenUML.swift) — 8 gaps, weakest coverage
> **Reconciled 2026-07-15:**
> - **FIXED:** `//` comments skipped; `x = A.method()` assignment strip (no phantom participant).
> - **PARTIAL:** nesting braces — a bare `{` is now skipped, but `call() {` still leaks a `{`.
> - **Remains:** `new X()` dropped; `return` dropped; `as` aliases; sync-call semantics; while/for/loop + if/else/opt/par fragments (dotted condition still fabricates `"while(order"`).

Supported: `@Actor/@Database/…` annotators (unknown → plain), `A->B: msg`, title.

| Feature | Behavior | Effort |
|---|---|---|
| `new PaymentService()` | **SD — creation message vanishes** (no `->`, no `.`) | M |
| `return x` / `@return` | SD **[remains]**; ~~`x = A.method()` → **PC participant `"x = A"`**~~ **[FIXED]** (assignment stripped) | M |
| Aliases `A as Alice` | SD bare / PC with annotator (participant named `"A as Alice"`) | S |
| Sync call semantics | `A.method()` modeled as self-call A→A; nested calls draw wrong arrows | L |
| Nesting braces | **[PARTIAL]** bare `{` skipped, but `call() {` still leaks `{`; activation nesting unmodeled | S strip / L |
| while/for/loop fragments | SD headers, bodies flatten; dotted condition → **PC `"while(order"`** | L |
| if/else, opt, par, try/catch | Same | L |
| `//` comments | ~~SD; comment containing a dot → **PC bogus participant**~~ **[FIXED]** (skipped) | S |

**Worst: creation/return drops + fabricated participants. S-effort guards (skip `//`, handle `as`, `return`/`new` keywords, strip `{`) stop the corruption today.**

## sankey-beta (MermaidParser+Sankey.swift) — 2 minor gaps, strongest coverage
**Reconciled 2026-07-15: still accurate — unchanged in 1.0.**

Full CSV state machine (quoted commas, `""` escapes), first-appearance node order, finite-value hardening. Gaps: zero/negative-value rows silently dropped (S); <3-field rows skipped (arguably correct). Config knobs all cosmetic (blocked by front-matter anyway).

## xychart-beta (MermaidParser+XYChart.swift) — 4 gaps
> **Reconciled 2026-07-15: PARTIAL.** Labeled points: the colon-form `[10:"l",8]` is now kept; the space-form still drops (a dubious gap). **Remains:** horizontal, numeric x-range, quoted-comma category.

Supported: title, categorical x-axis + title, y-axis title + range, multiple bar/line series, auto-categories.

| Feature | Behavior | Effort |
|---|---|---|
| Line point labels `[2.3 "label", 45]` | **[PARTIAL]** colon-form `[10:"l",8]` kept; space-form still **SD** (shifts later values) | S/M |
| `xychart-beta horizontal` | SD: header token never seen (dispatch passes body only); silently rendered vertical | M |
| Numeric x-range `x-axis 0 --> 100` | PC: literal `0 --> 100` becomes the axis *title*, categories default 1..n | S/M |
| Quoted category with comma | PC: naive comma split mangles the label | S |

**Worst: labeled points dropping data.**

## block-beta (MermaidParser+Block.swift) — 7 gaps, weakest of the beta seven
**Reconciled 2026-07-15: still accurate — unchanged in 1.0** (all 7 gaps remain).

Supported: `columns N`, bare ids, `id["…"]`/`id("…")`/`id(("…"))`, `space`, `-->` with `|label|`, chains.

| Feature | Behavior | Effort |
|---|---|---|
| `A --- B` | **PC: a literal `---` block inserted into the grid** (only `-->` checked, L84; `---` tokenizes as a block) | S |
| Width `a:2` | **PC + edge loss**: id/label become `"a:2"`, edges to `a` fail the realIDs filter (L102) and are dropped | M |
| Composites `block:group … end` | SD of frame/id/label (`continue` L80–82); children flatten; inner `columns` overwrites outer | L |
| Missing shapes (stadium/subroutine/cylinder/rhombus/hexagon/parallelogram/trapezoid/double-circle) | DEG shape; `[/x/]`/`[\x\]` leak slashes into labels | M |
| Asymmetric `id>label]` | PC: raw delimiters rendered as text | M |
| Block arrows `x<["…"]>(right)` | PC: rectangle labeled with raw junk | L |
| Edge label `A -- "yes" --> B` | SD of the label (only `\|label\|` handled, L179) | S |

**Worst: phantom `---` node; `a:2` breaking edges.**

## packet-beta (MermaidParser+Packet.swift) — ~~1 gap, severe~~ **0 gaps [FIXED]**
> **Reconciled 2026-07-15: FIXED → 0 gaps.** The `+N` relative-field bug is resolved (cursor + width semantics), exactly the fix suggested below.

Supported: both headers, title, `start-end: "label"` (reversed normalized, clamped), single-bit fields.
- ~~`+16: "Payload"` relative syntax (v11.7+): `Int("+16")` == 16 → single-bit field at absolute bit 16 instead of a 16-bit-wide field after the previous one. **Every `+N` row wrong offset and width; mixed examples overlap. Confidently wrong render.**~~ **[FIXED]** — cursor + width semantics (leading `+` treated as width).
- bitsPerRow/bitWidth/showBits config — cosmetic (blocked by front-matter).

## kanban (MermaidParser+Kanban.swift) — 3 gaps
**Reconciled 2026-07-15: still accurate — unchanged in 1.0** (all 3 gaps remain).

Supported: indentation columns/cards, `id[Label]`, `@{ ticket, priority }` with quoting.
- `assigned:` metadata: `default: break` in the switch (L58–62) — **SD, no model field** — S/M.
- `priority`: parsed into model but **never drawn** (zero hits in scene/layout) — S/M.
- Quote-blind metadata comma split (L53) mangles `assigned: "a, b"` — S.
`ticketBaseUrl` = N/A (links).

## architecture-beta (MermaidParser+Architecture.swift) — 4 gaps
**Reconciled 2026-07-15: still accurate — unchanged in 1.0** (all 4 gaps remain).

Supported: groups (icon+label), services with `in group`, junctions, edge side specifiers `id:L -- R:id`, arrows; icon names drawn as text captions (deliberate).

| Feature | Behavior | Effort |
|---|---|---|
| `{group}` edges `server{group}:B --> T:subnet{group}` | **SD: edge dropped without trace** (id `"server{group}"` matches nothing; layout guard `continue`, DiagramLayoutArchitecture.swift:295) | M |
| Nested groups `group b(...)[B] in a` | SD of hierarchy: `in` parsed then discarded (Group has no parent, L104) — renders top-level | M/L |
| Arrow direction `<--`, `<-->` | PC: single Bool arrow; `<` `>` trimmed → `a <-- b` draws head at the wrong end | M |
| `align row/column` (v11.16) | SD (benign-ish layout hint) | S/M |

Iconify glyphs = cosmetic-by-design (L for bundled assets). **Worst: {group} edges vanishing.**

## radar-beta (MermaidParser+Radar.swift) — 4 gaps, severe
> **Reconciled 2026-07-15: 3 FIXED, 1 remains.** FIXED: positional `{1,2,3}` values, multiple `axis` lines (now appended), auto-max ceiling. **Remains:** multiple curves per line (a dubious gap).

Supported: title, `axis` with aliases, key:value curve maps, max/min/ticks.

| Feature | Behavior | Effort |
|---|---|---|
| Positional values `curve a{1, 2, 3}` — the docs' primary form | ~~**SD of ALL values** → curve flat at minValue~~ **[FIXED]** | S |
| Multiple `axis` lines | ~~**SD: second line replaces the first**~~ **[FIXED]** (now appended) | S |
| Multiple curves per line `curve a{…}, b{…}` | PC: values span across both curves, merged garbled **[remains]** (dubious) | S |
| No `max` given | ~~Defaults 100; data >100 clipped~~ **[FIXED]** (auto-max ceiling) | S |

graticule circle/polygon + showLegend = cosmetic. **Worst: positional values zeroing every curve.**

## treemap-beta (MermaidParser+Treemap.swift) — 3 gaps
> **Reconciled 2026-07-15: 2 FIXED, 1 remains.** FIXED: `:::class` value/label preservation, and `classDef`-as-node. **Remains:** the minor unquoted `Foo: 2` `:`-truncation edge case.

Supported: indentation hierarchy, quoted sections, `"Leaf": value`, child sums, zero-total rejection.
- ~~`"Phones": 50:::urgent` — `lastIndex(of: ":")` lands inside `:::` → **value destroyed (leaf area vanishes) AND label mangled**~~ **[FIXED]** — S.
- ~~`classDef urgent fill:#f00` line becomes a **literal tree node**~~ **[FIXED]** — S.
- Labels containing `:` near values truncate (edge case) **[remains]** — S.
showValues/valueFormat/padding = cosmetic (front-matter). **Worst: `:::class` destroying leaf values.**

---

# PART C — Prioritized plan

## Tier 1 — Stop the lying (silent corruption / fabrication / content loss; almost all S)
> **Reconciled 2026-07-15: most of Tier 1 has since landed (~60%).** Done: sequence `+`/`-` + alias bug (1), gantt colon-guard + units (2), radar positional + axis (3), packet `+N` (4), treemap (5), zenuml `//` + assignment (6, *partial* — fragments/`new`/`return`/`as` still open), C4 `RelIndex` (7), and front-matter strip (14). **Notable remainders:** class (9), state (10), er/requirement (13), and the mindmap parts of (12); the block parts of (8) also remain. In short — class/state/er/mindmap are the main Tier-1 work left.

These make MermaidKit render a confident, wrong diagram. One "parser-honesty sprint" clears nearly all of them, ideally emitting `ParseDiagnostics` `.note` for anything still set aside (the severity exists and is unused).

1. **Sequence `+`/`-` activation shorthand** — strip markers before participant resolution (S; docs' first example is currently corrupted). Also fix the `replacingOccurrences("actor ")` alias bug (S).
2. **Gantt colon-directive guard** — known-keyword check before the task-colon split (S): kills phantom bars from `todayMarker`, `axisFormat %H:%M`, `click … href`. Plus `until` and `y/M/s/ms` unit handling (S).
3. **Radar positional `{1,2,3}` values + axis-line append** (both S; the canonical doc example currently renders as a dot).
4. **Packet `+N` relative fields** — cursor + width semantics (S; wrong bit layouts today).
5. **Treemap `:::class` + classDef-as-node** (both S).
6. **ZenUML corruption guards** — skip `//`, handle `as` aliases, `return`/`new` keywords, strip trailing `{` (all S; stops fabricated participants even before fragments exist).
7. **C4 `RelIndex` arg shift** (S).
8. **Block `---` phantom node + `a:2` width** (S/M).
9. **Class `class X["label"]`, `:::` bogus attribute, `<|--|>` phantom** (S each).
10. **State `id : description` + note-body phantom states + composite alias** (S each).
11. **Flowchart `--o`/`--x` phantom nodes; min-length links; edge-ID lines** (S–M).
12. **Mindmap bang/cloud delimiter leak; inline `:::` in labels** (S).
13. **ER word-form relationships, entity aliases, bare declarations; requirement quoted names** (S each).
14. **Front-matter strip** in `parse()` (+ pass `title:` through) — one S fix unblocking every config-bearing doc example across all 23 types.

Estimated: 2–3 focused sessions; parser-only, tests in MermaidKit CI.

## Tier 2 — High-value structural gaps in the big four
- **Flowchart**: chained edges + `&` fan-out (M — biggest single win in the audit), inline `-- text -->` labels (S), remaining classic shapes (M), bidirectional/thick edges (S–M). Then subgraphs (L) and `@{ shape }` (L) as separate projects.
- **Sequence**: cross/async arrow tokens (S parse, M arrowheads), notes (M), autonumber (S), actor figure (S–M), activations model+bars (M), boxes (M). Fragments (loop/alt/opt/par/critical/break) are the flagship L item — a frame model shared with the future block/composite work.
- **Class**: multiplicity fields + rendering (M), annotations as badges (S), notes (M), generics display (S). Namespaces (L) later.
- **State**: per-composite direction (M); concurrency regions (L) later.

Estimated: flowchart chains + sequence arrows/notes first (one session each), fragments + subgraphs as two L projects.

## Tier 3 — New types by value/effort
1. **TreeView** (S — indentation walk + list layout; reuse mindmap/treemap machinery).
2. **Cynefin** (S — fixed 2×2 geometry).
3. **Venn** (S/M — circle geometry, intersection label placement).
4. **Wardley** (M — author-given coordinates, no graph layout; high strategic-diagram value).
5. **Event Modeling** (M — grid + fixed lanes).
6. **Ishikawa** (S parser / M fishbone layout — docs thin; consider waiting for syntax to stabilize).
7. **Swimlanes** (L — lane-constrained layered layout; do after flowchart subgraphs, which it shares machinery with).

## Tier 4 — Everything else
- gitGraph cherry-pick (M) — genuinely silent history loss, promote if git diagrams matter; commit `type:` (M); tag/order fixes (S). TB/BT orientation (L).
- Architecture `{group}` edges + nesting + arrow direction (M each).
- C4 boundaries + deployment nodes (L each), Db/Queue shapes (M), BiRel (S–M).
- Gantt real date axis (`dateFormat`/`axisFormat`/excludes/tickInterval) — one L project to keep dates in the model instead of day-offsets.
- XYChart horizontal (M), point labels (S/M), numeric x-range (S/M).
- Kanban assigned+priority rendering (S/M). ER attribute keys/comments (M). Block composites (L). ZenUML sync-call semantics + fragments (L). Timeline/gitGraph orientation (L, only on demand).

## Suggested sequencing
1. **Sprint 1 — parser honesty**: all of Tier 1 + front-matter + start emitting `.note` diagnostics. Small diffs, huge trust win; every fix is testable with doc-copied fixtures.
2. **Sprint 2 — flowchart/sequence bread-and-butter**: chained/`&` edges, inline labels, missing arrow tokens, notes, autonumber, actor figures, class annotations/multiplicity, state descriptions.
3. **Sprint 3 — quick new types**: TreeView, Cynefin, Venn, Wardley (four shippable wins, S–M each).
4. **Sprint 4 — frames project (L)**: sequence fragments + boxes, flowchart subgraphs, block composites, C4 boundaries — all four want the same nested-frame layout concept; build it once.
5. **Sprint 5+ — on demand**: `@{ shape }` library, gantt date axis, Event Modeling, Swimlanes, orientation variants.
