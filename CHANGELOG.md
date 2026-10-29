# Changelog

## 2.10.0 — Subgraphs that span rows, fans that don't cross, ends that don't hook

Flowchart routing gets a long overdue overhaul. A subgraph's box spans the
rows its members take when an edge would otherwise point backwards; two
edges never draw as one; a fan's edges cross far less, and every jog in a
layer gap takes its track in the order that crosses least; and no edge ends
on a hook. Two new linter rules find what was wrong deterministically. Over
3,000 dense random charts, doubled edges fall from 1,246 on 2.9.1 to 0; over
the fan, gap and hook work alone, routes through a node fall from 73 to 15,
crossings from 419 to 258, and hooked ends (counted by the new rule) from
2,530 to 59. Layouts change for the charts these fixes touch: a handful of
corpus charts, and the cross-platform conformance signature, now
`b26cce4b4a877478`, the same on every platform.

### Added

- **Two linter rules.** `edge-end-hooked` flags a bending route that leaves
  or meets a node on a straight run shorter than an arrowhead and the
  router's shortest step (`DiagramLayoutLinter.minEndRun`, 19.5pt), except a
  loop and a decision's vertex. `label-cut-by-own-edge` flags a caption that
  straddles a step of its own route. `DiagramScene.Node.isDecision` marks a
  decision (a flowchart diamond, a state chart's choice), whose branches
  fork at its vertices; it is not part of the encoded scene.
  `DiagramLayoutLinter.minCaptionStub` names the 10pt stub
  `label-crowds-edge` already used.

### Fixed

- **A C4 relationship that leaves a cycle points down.** C4 rows came from a
  longest-path pass capped at the element count, so on a cycle such as
  `a ⇄ b` the nodes climbed to the cap, and a relationship out of the cycle
  (`b → c`) could no longer push its target below: C sat above B and the
  arrow ran up. The pass now drops the cycle's back edges first, as
  flowcharts do, so only a relationship on a cycle points up. A C4 diagram
  with a cycle may lay out differently; one without a cycle is unchanged.
  (#102)
- **Layer assignment ignores self-edges, as documented.** The longest-path
  seed lifted a node through its own self-edge on every pass, which could
  leave `x → y` with both ends in one layer. No chart was affected, since
  every caller already drops self-loops first. (#104)

- **A subgraph's box spans the rows its members take when it must.** A
  subgraph was always laid out as one box in one row of its parent. When an
  edge left it and a path came back in (`X → A → Y`, with X and Y in the
  subgraph and A outside), the box had to sit both above and below A, so an
  edge on no cycle was drawn back up. Such a subgraph is now laid out with its
  parent's nodes, as mermaid's is: its box spans the rows its members take,
  border nodes in each of those rows keep everything else out, and it takes
  its parent's direction. An edge naming it ends on its box, and its own loop
  (`S --> S`) goes round its box. Only charts that
  drew an edge the wrong way change; every other chart lays out exactly as
  before. (#103)

- **Two edges no longer draw as one.** Where two routes shared a line, the
  linter's `edges-doubled`, they read as one connector. Two fixes:
  - A face with more ports than room slid them all along, pushing its first
    ports past the face's end, where they were clamped back onto their
    neighbours: two edges into one point, or closer than the minimum gap.
    Now only those ports move back, keeping the gap; every other port is
    where it was.
  - Two unrelated edges could still jog in one track, meet end to end in one
    column, or share a line where a jog clamped onto a node's face ran along
    it. A last pass finds exactly the pairs the linter would flag and moves
    one segment aside, a jog track at a time (a run along a face steps off
    it on a stub away from the node), only where its neighbours keep their
    direction, it runs through no node, and no new pair doubles. It runs
    within each layout, and once more across a subgraph's edges and the ones
    round it.
  Over 3,000 seeded random charts, doubled pairs fall from 1,246 to 3, and
  over 3,000 with subgraphs from 474 to 0; no chart gains a route through a
  node. Every corpus chart lays out exactly as before, and so does any chart
  with neither defect.

- **A wide fan's jogs fit in their layer gap.** The edges into one node, and
  the edges out of one, jog on tracks 10pt apart, one per edge, centred on
  the gap's middle. A fan wider than the gap had its outer jogs clamped onto
  the nodes' faces, where they shared a line (from a 7-edge fan in a plain
  gap). A gap now grows until every track fits an arrowhead clear of each
  face. A fan's tracks apply only where it meets its hub: an edge jogs on
  its fan-out's track in the gap it leaves by, on its fan-in's in the gap it
  enters by, and mid-gap in between, so a long fan widens only the gaps
  beside its ends. A gap that carries no fan keeps the configured layer gap.
  Where two edges cross in an X between ports that line up, no whole jog
  track separates them, so the last separation pass also tries half a
  track. The issue's 20-edge fan has no doubled line; across 3,000 dense
  random charts, lint errors fall from 232 to 162 and routes through a node
  from 73 to 20. Those charts grow taller where a fan needs it; one corpus
  chart, which stays lint-clean, changes. A fan with more edges than its
  node's face has room for still crowds their ports nearer than a line
  apart. (#108)

- **A fan's edges cross one another far less.** A fan's jogs were stacked
  in cross order across the whole fan, which suits only one side of its hub:
  on the other, every two edges that jogged crossed, a plain 4-edge fan
  included. Each side of a hub now takes its fan's tracks from the one
  nearest the hub, the edge reaching farthest out first, so a lone fan's
  edges never cross, and edges through the hub's other face spread over
  their own tracks. Parallel edges go in the order of their ports, so their
  places in the fan they leave and the one they enter agree instead of
  cancelling onto the gap's middle. A captioned back edge with one bend now slides the bend toward its
  arrowhead, as a forward one does, leaving its caption one long run. A run
  pushed apart from another edge's is no longer pushed into a node. With
  #108, over 3,000 dense random charts, lint errors fall from 232 on 2.9.1
  to 79, crossings from 419 to 358, and no two edges share a line; over
  3,000 with subgraphs, errors fall from 168 to 91. Three corpus charts
  change, each still lint-clean. (#110)

- **Jogs in a gap take their tracks in the order that crosses least.** Two
  jogs in one layer gap cross only where one's run passes through the
  other's step, so which is higher decides it. A last ordering pass keeps
  each gap's tracks, so its room still holds, and moves one jog at a time to
  wherever in the order it crosses least. That repairs what ranking each fan
  alone missed: an edge between adjacent layers jogged on the sum of its
  places in two fans, which could reverse one of them. A captioned edge's
  single bend may now stop as short of its source as of its target, where
  its caption still fits, and a gap that carries a captioned two-cycle
  (`A -->|go| B`, `B -->|back| A`) holds the caption past a bend at either
  end. A jog that shares a port with another, as at a decision's vertex,
  or carries a caption it isn't such a bend for, keeps its track, and no
  move brings a run within a minimum jog of another edge's. Over 300 seeded
  random two-row charts, crossings between edges that share a node fall
  from 186 to 129; over 3,000 dense random charts all crossings fall from
  358 to 281, and over 3,000 with subgraphs from 225 to 160, with lint
  errors about level (79 to 81, 91 to 89). Every corpus chart lays out as
  before. (#112)

- **No edge ends on a hook.** A route that bent within an arrowhead of a
  node drew a hook: the arrow bent over at its target, or the line kinked
  against the face it left. A captioned bend stopped exactly an arrowhead
  short of its target, a fan's outer tracks sat an arrowhead from the
  faces, and later passes nudged, straightened and grid-snapped bends
  closer still. A new linter rule, `edge-end-hooked`, now finds every such
  end from the geometry alone: a bending route must leave and meet its
  nodes on a straight run of at least an arrowhead and the router's
  shortest step (19.5pt). Loops, and a decision's vertex, where branches
  fork at once, are exempt. The layout keeps to it: fan tracks and caption
  bends stop that far from a face, a captioned bend's gap holds the extra
  room, separating, straightening and snapping never shorten an end run
  below it, and a captioned bend that would cross another may go back to
  its fan track, or stop as short of its source where its caption still
  fits. Over 3,000 dense random charts, hooked ends fall from 2,530 to 60,
  and over 3,000 with subgraphs from 1,677 to 87; edge crossings fall
  too (281 to 258, 160 to 135), and captions on a bend or crossing (30 to
  6, 36 to 5). A second new rule, `label-cut-by-own-edge`, finds a caption
  that straddles a step of its own route without covering either corner.
  Captions that meet one node across one gap and can't stack across the
  flow, more of them than its face holds, sit one after another along their
  runs, and their gap holds them all: captions short of a full stub stay
  about level (36 to 34, 19 to 37), and on a 1,500-chart mixed-shape probe
  fall from 161 to 112. (#114, #115)

New tests check, over seeded random graphs with cycles, self-loops and
parallel edges, that an edge on no cycle points strictly down: in the layer
solver, in C4 diagrams and in flowcharts, nested subgraphs and direction
overrides included. They also check that no subgraph box overlaps a node
outside it, and, over 2,000 dense random charts, that no two edges share a
line.

## 2.9.1 — Captions placed in near-linear time

Charts with many edge captions lay out far faster, with every caption where
it was. Output for every chart is byte-identical to 2.9.0.

### Fixed

- **Charts with many edge captions lay out far faster.** The caption placer
  scored every candidate position against every node, caption, bend,
  crossing and arrowhead in the chart, so its cost grew about n^2.5 with the
  number of labeled edges: a fan of 320 labeled edges took 18 s (debug
  build). It now reads only what a spatial grid finds near each candidate,
  skips a candidate whose unavoidable penalties already lose to the best one
  so far, counts the bends and crossings in a caption's way without sorting
  them, and tests only route segments that could cross: the same fan takes
  0.3 s, 480 labeled edges 0.5 s, and 160 labeled self-loops 0.07 s instead
  of 4.2 s. The placement is bit for bit what it was: every skipped term was
  exactly zero and every skipped candidate could not have won, and a test
  holds the new placer to the old one over real layouts and 300 seeded random
  ones. (#97, #99, #101)

## 2.9.0 — Mac Catalyst, and self-loops that loop

MermaidRender now builds and runs on Mac Catalyst, and a flowchart edge from
a node to itself draws as a loop round the node. Additive: no existing call
changes, and output for every chart in the fixture set is byte-identical to
2.8.0.

### Added

- **Mac Catalyst.** Catalyst can `import AppKit`, so every
  `#if canImport(AppKit)` took the AppKit branch there and hit
  `NSFont.Weight`, `NSColor.withAlphaComponent` and other APIs Catalyst
  doesn't have. Those checks now test `os(macOS)`, so Catalyst draws with
  UIKit like iOS; macOS is unchanged. `Package.swift` declares Mac Catalyst
  17, the floor it already inherited from iOS 17. CI runs the tests on
  Catalyst too, which also gives the UIKit render path, iOS's, a test host.
  (#94)

### Fixed

- **A flowchart self-loop draws as a loop.** `A --> A` used to route
  straight through its own node, with its caption on the box, and it took
  a face port from the node's real edges, pushing them into jogs. The loop
  now wraps round the node's cross-far side (the right in `TD`, the bottom
  in `LR`) with its caption beside the far run, and the row and layer gaps
  make room for both. Several loops on one node nest outward. A chart with
  subgraphs used to drop its self-loops altogether; they now draw the same
  way, inside a subgraph or round one. (#96)

Thanks to @randomor for both.

## 2.8.0 — Flowcharts read like mermaid, down to the label

Flowchart text now reads the way mermaid's does, character by character. Of
the 1,588 charts the mermaid.js oracle compares, 1,330 read the same as in
mermaid 12.2.0, and none that mermaid draws is rejected. The recorded
divergences went from 256 to 19, and what remains is documented. Output for
every chart in the fixture set is byte-identical to 2.7.1.

### Changed

- **A flowchart with nothing to draw draws empty**, as in mermaid: a header
  alone (`graph LR;`), or only comments and `classDef`, `class`, `click` or
  valid `linkStyle` lines. `diagnose` notes "nothing to draw" at the header, so a
  host can still tell, and alt text reads "Empty flowchart." A chart with
  nothing drawn and a statement MermaidKit couldn't read, or a header mermaid
  doesn't accept (`graphical`, `flowchart LR junk`), still doesn't parse; a
  subgraph's box counts as drawn. **Behavior change:** `parse` used to return
  nil for these, so hosts that treat nil as "show the source" now get a blank
  diagram. (#91)

### Fixed

- **Entities read as a browser reads them.** Labels decode every named
  character reference HTML defines (2,231 names from the WHATWG table, up
  from 57), the way mermaid's labels reach the reader. The longest name that
  matches wins, legacy names need no `;` (`&amp more` reads "& more",
  `&copy 2024` "© 2024"), numeric references need none either (`&#169`), and
  mermaid's own `#name;` uses the same table (`#notin;` reads "∉"). An
  unknown `&name;` and control characters stay as written; an unknown
  `#name;` reads `&name;`, as mermaid shows it. One deliberate difference
  from mermaid: `&#169;` reads "©", where mermaid shows "&©". (#90)
- **Reading a label never spells a line break the author didn't write.**
  Labels are read in one linear scan of the text as written, tags and
  references alike. Every character a break is made of must be written, side
  by side: a `<br…>` tag's `<`, `b`, `r` and closing `>`, and both halves of
  `\n`. Otherwise the reference that supplied one, or the tag dropped between
  two, stays as written. This fixes breaks spelled by a reference supplying a
  letter (`<b&#114;>`), by a `<` far from its `>`, and by a dropped tag
  (`\<i>n`, since 2.6). A dropped tag no longer joins a reference either
  (`&am<b></b>p;` shows as written). A seeded property test checks the rule
  over 40,000 labels. Long runs of `&lt;` read about 15× faster. (#90)
- **A label is text to every step of reading a line.** The statement scanner
  now also gives each statement's syntax, with its labels masked, and links,
  `|labels|` and `&` fans are found only there. So an asymmetric node's text
  can hold `&` and `]` (`B --- S>"a & b"]` was dropped whole, and
  `x>a & b] -..-> Y` read as one node labeled `a & b] -..-> Y`), and inline
  link text can hold `-` or `&` (`-- a-b -->`). A node's shape must close
  where its token ends, so a line that doesn't parse as links is never read
  as one node with the rest of the line as its label. (#93)
- **`B&C` is one node**, as in mermaid: `&` joins a fan only between
  whitespace. (#93)
- **A start head that doesn't match the end counts toward the link**, as in
  mermaid: `<---` is two ranks long, like `----`, and `o==>` is solid. (#93)
- **`style X …` draws node `X`** even if nothing else names it, as in
  mermaid; the styling itself is still ignored. (#93)
- **A `linkStyle` that names no link is noted.** Its targets must be indexes
  of links read before it (`linkStyle 1` after one link names none, nor does
  `linkStyle nope`). Mermaid rejects such a chart; MermaidKit draws the rest,
  as before, and `diagnose` now notes the statement. A chart with nothing else
  in it doesn't parse. (#91)
- **A header is split on any whitespace**, so `flowchart\tLR` reads
  left-to-right, as in mermaid. A header with words after its direction, or
  an unknown keyword, is noted. (#91)

### Tooling

- **The mermaid.js oracle counts tag-like text as agreeing.** MermaidKit
  shows `List<String>` where a browser hides `<String>` as an element it
  doesn't know, and mermaid shows "List". That's deliberate, so nothing the
  author wrote disappears. The rule excuses only elements the HTML parser
  doesn't know, including one left unclosed at the end (`-- List<String -->`):
  a real tag (`<b>`, `<svg>`, `<br>`) and any other difference still count.
  The rule checks itself on every run, and the summary counts the charts it
  excuses. (#92)
- **What the oracle still records is documented.** 18 of the 19 remaining
  divergences come from one mermaid quirk MermaidKit doesn't copy: before it
  parses, mermaid deletes the last `;` of any line matching
  `style.*:\S*#.*;`, so a line that mentions a node named `styleguide` loses
  a label's `;`. (#93)

## 2.7.1 — Every word, every line, every box

Fixes for labels and charts that drew less than they said. C4 boxes keep
every word, `<br>` breaks lines in SVG and on Android, Windows and Flutter,
class generics read `List<T>`, bold is bold on Linux, and a reused subgraph
id is one box, as in mermaid. Additive: no existing call changes. On Apple
platforms, raster output for every fixture is byte-identical to 2.7.0 except
C4, whose boxes now hold the words they used to drop; on Linux, bold text is
bold.

### Fixed

- **Bold draws bold on Linux.** Titles, headers and other emphasis were
  always set in regular DejaVu Sans: Silica reads a `Family-Bold` name, and
  took FontConfig's `Family:bold` as a family that doesn't exist. Linux
  renders with emphasis change (boxes grow to fit the bold text);
  Apple platforms are unaffected. (#81)

- **Class generics read as `List<T>`**, as in mermaid. `class Box~T~` is the
  class `Box` drawn as `Box<T>`, so `Box~T~ --> Item` and `Box --> Item` meet
  the same box (the generic once split it into two), and `Box~T~ : +x` adds
  its member (it was dropped). Members pair their tildes the way mermaid
  does: `+List~List~int~~ xs` reads `+List<List<int>> xs`, a method's name,
  parameters and return type each on their own, and a lone `~` stays as
  written. New `ClassDiagram.Class.generic` and `.label` and
  `ClassLayout.Box.label`; `name` is the id without the generic. Alt text
  reads `Box<T>` too. Charts without `~` are byte-identical. (#72)

- **`<br/>` breaks the line in SVG and `SceneWire` too.** `scene`/`svg` and
  the scene JSON the C ABI hands Android, Windows and Flutter now break a
  label at `<br/>`, `<br>`, a literal `\n` or a newline in every diagram type,
  on the same line centers the raster image draws, instead of showing the tag
  as text in flowchart, class, state and other labels. Each line is its own
  text element, and a chipped label (an edge label) gets one chip behind the
  whole block, so the wire format and the platform renderers are unchanged.
  A break tag in any case (`<BR>`, `<Br/>`) breaks on every path now, the
  raster image included, through one new `DiagramLayoutEngine.hasLineBreak`.
  Raster output is otherwise byte-identical. (#71)

- **C4 boxes keep every word of their title and description.** The wrap
  stopped at its last line and dropped the words after it, so "Drop-in
  diagram view following the color scheme" drew as "Drop-in diagram view
  following". Titles and descriptions now wrap in full and the box grows
  taller to hold them; boxes keep their uniform width. A label too long for
  any box (past 4 title or 12 description lines) ends in "…", and a chart
  that would still outgrow the canvas tightens those caps, so no box runs off
  it. (#70)

- **A reused subgraph id is one subgraph**, as in mermaid. A second
  `subgraph two … end` block adds its members to `two` (the first title and
  direction stand) instead of drawing an untitled second box that took them.
  A quoted one-word title is the subgraph's id too (`subgraph "Anon"` is
  `Anon`, so `Anon --> C` targets the box). A title with a space is never an
  id, quoted or not, so two `subgraph My Group` blocks stay two boxes. Found
  by the mermaid oracle's new subgraph comparison. (#88)

### Tooling

- **The mermaid.js oracle compares subgraphs too**: each one's id, title,
  declared direction and direct members (nodes and child subgraphs). A
  title-only subgraph, whose id each side synthesizes and numbers
  differently, is matched by its title and named members. It found the
  reused-id bug above. 1,044 of 1,549 charts now agree with mermaid, and the
  recorded divergences went from 268 to 256. (#79)

## 2.7.0 — Diagrams in your app's font

Diagram labels can now be set in the font the rest of your app uses. A new
`DiagramTheme.fontFamily` takes a family name, and every label is measured
and drawn in that family, so boxes still fit the text. At the default (`nil`,
the system font), output is byte-identical to 2.6.0. Additive: no existing
call changes.

- **`DiagramTheme.fontFamily`** sets and measures every label in a chosen
  family (`DiagramTheme(prefersDark: false, fontFamily: "Inter")`), for the
  raster renders (`MermaidView`, `image`, `pdfData`, `attachmentString`). Body
  text takes the family's regular face where it has no medium, so text never
  draws wider than it was measured. A family the device doesn't have is the
  system font, byte for byte, on Apple platforms and Linux. It's part of the
  theme's cache fingerprint. `scene`/`svg` stay in the system font. Additive;
  the default is unchanged. (#77)

Thanks to @hipstersmoothie, who built this so chat apps can draw diagrams in
the interface font their users pick.

## 2.6.0 — Flowcharts read the way mermaid reads them

Flowcharts now read like mermaid.js in many more cases, and every rule is
checked against mermaid's own parser. A new test compares 1,534 charts with
mermaid 12.2.0: on 2.5.0, 430 of them read the same as mermaid; on 2.6.0,
1,029 do, and none reads worse. Output for every chart in the fixture set is
byte-identical to 2.5.0.

- **`;` separates statements**, as in mermaid: `graph LR; A --> B; B --> C`
  draws two edges, and `graph LR;` sets the direction. A `;` stays part of the
  text when it's inside a label: quotes, node text (`[…]`, `(…)`, `{…}`,
  `>…]`, `[[…]]`, `[(…)]`…), pipe labels (`|…|`), inline link text
  (`-- … -->`, `== … ==>`, `-. … .->`) or an entity (`#quot;`). In `style`,
  `classDef` and `linkStyle`, a `;` ends the statement, so `fill:#f96;` stays
  a color. A `%%` after a `;` comments out the rest of the line. (#76)
- **Entities in labels are decoded**: mermaid's `#quot;`, `#35;` and
  `#name;`, and HTML's `&amp;`, `&#169;` and `&#x2665;`. Numeric references
  read as a browser reads them: `#133;` is "…", per Windows-1252. Control
  characters, noncharacters and anything that would spell a line break stay
  as written. An unknown `#name;` shows `&name;`, as mermaid shows it. (#76)
- **Inline formatting tags** (`<b>`, `<i>`, `<code>`, `<span …>`…) are dropped,
  and their text kept, since the renderers can't style it. `<br>` breaks
  stay. (#76)
- **Keywords are whole words**: `styleguide --> B`, `subgraphs --> B` and
  `direction --> B` are edges between nodes, as in mermaid. (#76)
- **`MermaidParser.diagnose` notes what a flowchart that parses left out**,
  at its line in the source:
  - a statement it couldn't read;
  - an `end` with no subgraph open;
  - an unknown direction, or a top-level `direction`, which has no effect;
  - an `&` fan endpoint that isn't a node.

  Hosts can now tell a diagram that rendered whole from one with parts
  missing. **Behavior change:** `diagnose` used to return `[]` for any source
  that parsed. It can now return `.note`s for one; check `severity` if you
  only want errors. (#76)

Thanks to @hipstersmoothie for #76.

### Tooling

- **A mermaid.js oracle** (`scripts/check-mermaid-oracle.sh`, run in CI) parses
  a fixed and a seeded generated corpus with mermaid's own parser and with
  MermaidKit, and compares what a reader sees. Known divergences are recorded,
  each counted as missing, wrong or extra. CI fails if a chart diverges
  newly, a known one gets worse, or a chart leaves the corpus, so the list
  only shrinks. It went from 934 known divergences to 256 in this release.
  See `tools/mermaid-oracle/README.md`. (#78)

## 2.5.0 — Dynamic Type for diagrams, everywhere

Diagram text can now follow the reader's text size. `DiagramSpacing.textScale`
lays a diagram out at a larger (or smaller) text size: the boxes, rows and gaps
that hold text grow with it, while lines, arrowheads and markers keep their
weight. That's different from scaling a finished image, which thickens every
line and blurs bitmaps. At the default size (1), output is byte-identical to
2.4.0. Additive: no existing call changes.

- **`DiagramSpacing.textScale`** (0.5–3; a non-finite value is the default size).
  It's honored by every entry point that takes a spacing: `MermaidView`, the
  `MermaidRenderer` image/PDF/SVG/attachment API, `RenderScene`, the headless
  `DiagramLayoutEngine.layout(_:measure:spacing:)` engines, and the new
  `DiagramScene.lower(_:measure:spacing:)`, so headless geometry and lint match
  the image. It's part of the render-cache fingerprint. (#73)
- **`MermaidView` follows Dynamic Type** (`dynamicTypeSize`), multiplied by any
  `textScale` you set. (#73)
- **Every platform:**
  - **C ABI:** `mmk_scene_json_options(source, theme_json, prefers_dark,
    text_scale, measure, userdata)` is the general scene call, and asks the
    host's measure callback at the scaled size.
  - **Android:** `MermaidNative.scene(…, textScale)`. `MermaidView` and
    `MermaidDiagram` follow the system font size (`Configuration.fontScale`).
  - **Flutter:** `MermaidNative.scene(…, textScale:)`. Pass
    `MediaQuery.textScalerOf(context).scale(12) / 12` (the scale at the diagrams' 12pt base size,
    since Flutter's text scaling can be nonlinear).
  - **Windows/.NET:** `MermaidNative.Scene(…, textScale:)`.
  - **Terminal:** `mermaidkit-term --text-scale K` for the raster tiers.
- **`DiagramScene.lower(_:measure:spacing:)`** lints a layout with its spacing:
  density, grid snap (which the linter couldn't see before) and text scale.

Thanks to @hipstersmoothie, who built this for chat apps where text follows the
user's size.

- **The geometry linter gives the same answers on Linux.**
  swift-corelibs-foundation's `CGRect.contains(CGRect)` is `union(r) == self`,
  which is false for about three fractional rects in four. On Linux, a box
  nested inside another was therefore reported as `nodes-overlap`, and
  `mark-escapes-plot` rarely found its plot, so it silently didn't run. The
  linter now compares edges. (#74)
- **Treemaps:** a group whose header label can't fit no longer reserves an
  empty strip above its children. The layout and both renderers now share one
  header rule. (#73)

## 2.4.0 — Every flowchart link, every classic shape

Mermaid's full set of flowchart link styles and its classic node shapes now
draw as written, where 2.3.0 drew them as plain arrows, circles and
rectangles. Rendering only changes for diagrams that use this syntax.

> **Source compatibility.** `Flowchart.NodeShape` gains six cases. Code
> outside the package that switches *exhaustively* over `NodeShape` stops
> compiling until it handles them; an `@unknown default:` branch turns that into
> a warning instead. This follows the 1.2.0 precedent (`hexagon`, `subroutine`). Everything else is
> additive: the new `Edge` and `PlacedEdge` fields have defaults, and the
> wire format and the Android, Flutter and Windows backends are unchanged.

- **Link styles.** Thick links (`==>`, `===`) draw at 2pt, and invisible
  links (`~~~`) are laid out but not drawn: they rank and order nodes but
  never move a drawn edge or label, and the linter, ASCII renderer and alt
  text skip them. Circle (`--o`) and cross (`--x`) heads work at one end or
  both, on any stroke and with inline text. Before, they were plain arrows.
  New fields: `Flowchart.Edge.head`, `.thick`, `.invisible`, `.length`, and
  `PlacedEdge.head`, `.thick`, `.invisible`. (#68)
- **Link length.** Each extra `-`, `=`, `.` or `~` adds a rank, counted as
  mermaid counts them (`--->` spans two). It's capped at 10 per link and 100
  extra ranks per chart, so a pathological chart still lays out in well under
  a second. (#68)
- **Node shapes.** `doubleCircle` `((( )))`, `parallelogram` `[/ /]`,
  `parallelogramAlt` `[\ \]`, `trapezoid` `[/ \]`, `trapezoidAlt` `[\ /]` and
  `asymmetric` `> ]`, plus their `@{ shape: … }` names (`dbl-circ`,
  `lean-r`/`in-out`, `lean-l`/`out-in`, `trap-b`/`priority`, `trap-t`/`manual`,
  `odd`). Edges land on the slanted sides and the flag's notch, not on the
  frame. (#68)
- **DOT and ASCII.** `doublecircle`, `parallelogram`, `trapezium` and
  `invtrapezium` map both ways. `style=bold`/`invis`, dot-family arrowheads and
  `minlen` carry thick, invisible, circle heads and length. `arrowhead=none` /
  `arrowtail=none` now suppress that end. The terminal renderer has glyphs
  for the new shapes. (#68)

Thanks to @hipstersmoothie, who wrote this from the diagrams coding agents
actually emit.

- The docs gallery flowchart draws `Scene IR` as the parallelogram it's
  written as. (#68)

### Docs

- **A full documentation audit**, every claim checked against the code: the
  README, website, DocC catalogs, API doc comments, platform READMEs and design
  notes. Highlights: the website's lint demo used rule names that don't exist
  and a `mermaidkit-lint` command that was never built; conformance claims now
  say CI gates macOS, Linux, WASM and Windows (Android was verified on an
  emulator); the terminal CLI's tier order and flowchart-only box tiers are
  described as they behave; DOT round-trips list their lossy cases; the
  coverage audit and dated design memos carry v2.4.0 reconciliation notes; the
  contributor guide covers the `RenderScene` lowering and the semver rule as
  practiced. Both DocC catalogs now build with zero warnings (nine broken
  symbol links fixed), and the README has an install snippet.

## 2.3.0 — Flowcharts as agents write them, on a grid

The flowchart forms coding agents actually emit in chat now parse instead of
silently dropping the line, and box layouts get a grid: a metric that measures
alignment and an opt-in quantizer that snaps flowcharts onto it. Additive; the
default output only changes where a diagram used to render wrong.

- **Flowchart syntax coverage.** Ids with `-` and `.` between word characters
  (`api-gateway`, `auth.service`); `{{hexagon}}` and `[[subroutine]]` (which
  previously matched the single-bracket forms and drew a diamond labelled
  `{Redis}`); and mermaid's `id@{ shape: …, label: … }` shape data, with its
  named shapes and aliases (`diam`/`decision`, `cyl`/`database`,
  `hex`/`prepare`, `subproc`/`fr-rect`, …) mapped onto the existing cases.
  Shapes without a model case keep their label instead of their delimiters:
  `(((…)))` draws as a circle, and the slanted `[/…/]` family and the
  asymmetric `>…]` as rectangles. Before, any of these failed its endpoint,
  which dropped the whole edge line. Thanks to @hipstersmoothie. (#65)
- **Grid-alignment metric.** `DiagramLayoutLinter.gridAlignment(_:unit:)`
  reports how many of a box-family diagram's coordinates sit on a pixel grid
  (default 4px; `nil` for pie/radar/timeline/sequence), and `report(_:)` adds a
  non-gating `grid:` line. `GridAlignmentTests` holds a per-type floor the
  layout may only ratchet up. (#62)
- **`GridQuantizer`: opt-in grid snapping for flowcharts.**
  `DiagramSpacing(gridSnap: 4)` snaps nodes, containers and edge waypoints onto
  the grid inside `DiagramLayoutEngine.layout`, so CoreGraphics, `RenderScene`
  and the linter all see the same geometry. Boxes only ever grow, edge
  endpoints are re-anchored to the snapped borders, and `gridSnap` is part of
  the spacing fingerprint so snapped and unsnapped renders never share a cache
  entry. Off by default. (#63)

### Fixed

- **Docs gallery flowchart** now draws the fixture as written: the
  `diagnose: did you mean…` step as a subroutine and `Scene IR` without its
  slashes, both of which the old parser misread. (#65)
- **Android CI** runs again: `setup-android` v3's default install included the
  SDK's removed `tools` package, which failed all three Android jobs. (#66)

### Docs

- A full accuracy pass over the README, platform notes and DocC reference:
  shipped-platform, SVG and P/Invoke claims; version pins and test counts;
  build recipes and source paths; non-compiling examples and symbol links;
  diagram labels and the linter table. (#57–#61, #64)

## 2.2.0 — Any source format, inline and narrated

Format-aware entry points, so a rich-text host (a live editor, a document view)
gets the same sized, themed `NSAttributedString` attachment **and** accessibility
narration for *every* supported source format — not just Mermaid — without ever
touching the parsers.

- **Format-aware `MermaidRenderer` API.** A new `DiagramSourceFormat`
  (`.mermaid`, `.dot`, `.dippin`, `.sqlDDL`, `.gitLog`) drives format-aware
  `image` / `pngData` / `attachmentString` / `altText(source:format:)`, plus
  diagram-based twins.
  DOT, Dippin, SQL DDL and git-log sources now render inline and narrate exactly
  like Mermaid. (#46, #47)
- Non-Mermaid formats ride the **same NSCache path** as Mermaid — keyed by
  format tag + source so same-text DOT and Mermaid can't collide — so a live
  editor doesn't re-parse and re-render on every keystroke.

### Fixed

- **Arrowheads over tinted group boxes** (C4, architecture, block) no longer show
  a pale canvas-colored **wedge**. The head is now a single opaque triangle
  rather than a translucent head painted over a canvas-colored shaft-eraser —
  which removes both the seam the eraser prevented and the wedge it caused. Both
  render paths (CoreGraphics + the platform-free `RenderScene`) change in lockstep
  so the draw-vs-scene conformance ratchet still holds. (#23)

### Docs

- The architecture/pipeline diagrams in the platform notes and package READMEs
  are now **Mermaid** (` ```mermaid ` — rendered natively by GitHub, and by
  MermaidKit itself), replacing the ASCII-art code fences. MermaidKit now
  dogfoods its own renderer in its docs. (#49)

## 2.1.0 — Flutter, and any bare surface

A sixth native platform (**Flutter**) and the raw-raster primitive that drives
**any bare surface** — a Raspberry Pi framebuffer, an SDL2 window, a GPU texture.
Additive; existing platforms and output are unchanged.

- **Flutter** (`flutter/mermaidkit`) renders all 30 types with a Dart
  `CustomPainter` on Flutter's Skia/Impeller canvas — a fidelity match for the
  Android backend, and one plugin reaches iOS, Android, web, and desktop:
  - A `SceneWire` Dart model (sealed classes + a `type` discriminator) and
    `MermaidPainter` / `MermaidDiagram`.
  - A **`dart:ffi` bridge** (`MermaidNative`) over `mmk_scene_json` in the Swift
    core built as a shared library, so an app passes a Mermaid *source string*:
    `MermaidNative.scene("flowchart LR\n A --> B")`. The Flutter analogue of
    Android's JNI and .NET's P/Invoke — `dart:ffi` calls the `@_cdecl` C ABI
    directly.
  - Optional `fontFamily` for bundled/custom label fonts.
- **Raw raster on Linux.** `MermaidRenderer.rgbaRaster` — previously Apple-only —
  now returns raw RGBA pixels on Linux too, reading the Cairo (Silica) image
  surface directly. This is the primitive every display-server-free surface needs
  (a PNG isn't enough): framebuffers, SDL, GPU upload.
- **`tools/pi-canvas`** — a demo/proof: an infinite, pannable canvas of diagrams
  composited into a 640×480 framebuffer, over the raw raster with no display
  server. A single `Framebuffer` seam with three backends — a PNG stand-in,
  `/dev/fb0` (RGB565), and **SDL2** (streaming texture) — verified on the Pi's
  aarch64 architecture with the Silica/Cairo raster.
- A `MermaidKitCShared` dynamic product already existed (the Windows DLL); it now
  also backs the Flutter `dart:ffi` bridge and any P/Invoke-style consumer.

## 2.0.0 — Native everywhere

MermaidKit renders natively on **five platforms** — macOS/iOS, Linux, **Android**,
**Windows/.NET**, and **WebAssembly** — from one Swift layout core. The Swift
package's public API is **additive** (no breaking changes); the major bump marks
the platform expansion. Android, Windows, and .NET ship as their own `0.1.0`
artifacts.

- **Native Android rendering.** The [`android/`](android/) Gradle module renders
  all 30 diagram types with a Kotlin `Canvas`:
  - A `SceneWire` Kotlin model (plain `@Serializable`) + a `SceneRenderer` (Skia
    `Canvas`) that draws the platform-free scene the core emits.
  - A **JNI bridge** — `MermaidNative` over a per-ABI `libmermaidkit.so` (the
    Swift core + a C shim, built by `android/native/build-jni.sh`) — so an app
    passes a Mermaid *source string*: `MermaidDiagram("…", Modifier.fillMaxWidth())`.
  - The **device measure seam** (`Paint.measureText` threaded through JNI, so
    layout measures with the face that draws), **Material theming**
    (`MermaidTheme.fromMaterial(MaterialTheme.colorScheme)`, default), a Compose
    `MermaidDiagram` + classic `MermaidView`, and `contentDescription` from the
    narration.
  - A release **AAR** bundling stripped `.so` for arm64-v8a, armeabi-v7a, and
    x86_64; verified end-to-end on an android-34 emulator in CI.
- **Native Windows / .NET rendering.** The [`windows/`](windows/) .NET library
  renders with **SkiaSharp** (real Skia — the same engine as Android, a fidelity
  match; no SVG fallback): a `SceneWire` model, a `SceneRenderer` over `SKCanvas`,
  and a **P/Invoke bridge** (`MermaidNative` over a Swift-built
  `MermaidKitCShared.dll`) so a .NET app goes from a source string to a Skia
  diagram. Gated on `windows-latest` in CI.
- **WebAssembly.** The platform-free core compiles to `wasm32-unknown-wasi` and
  emits SVG (or a Canvas2D scene) in the browser.
- **Cross-platform conformance — proven byte-identical.** A new conformance
  harness (`tools/conformance`) + CI gate (`conformance.yml`) run the same
  fixtures through the core on macOS, Linux, Android, WASM, and Windows and assert
  one signature. Reaching byte-identity caught and fixed two real determinism bugs:
  - `JSONEncoder` serializes `Double`s differently across Foundation
    implementations (Darwin's shortest round-trip vs swift-corelibs' full
    precision) — `SceneWire` now **quantizes coordinates to an exact 1/256 grid**
    (sub-pixel; SVG unaffected) so the wire JSON is identical everywhere.
  - Pie arc tessellation used `ceil(sweep / (π/8))`, which flipped the segment
    count on a 1-ULP `sin`/`cos` difference (WASM's math lib vs glibc/Darwin) —
    fixed with an epsilon before the `ceil`.
- **C ABI additions** (`MermaidKitC`, still `MermaidLayout`-only):
  - `mmk_scene_json_themed(source, theme_json, measure, userdata)` — theme a scene
    with explicit caller colors via the new **`ThemeWire`** JSON, instead of a
    built-in preset.
  - A dynamic **`MermaidKitCShared`** product (the C ABI as a shared library — the
    Windows DLL the .NET bridge P/Invokes).
  - WASI portability: `TerminalCapabilities` guards its termios/tty paths for
    WebAssembly; libc imports guard for Bionic/Android.

## 1.4.0

A platform-free render IR with SVG output, and a fifth input front-end. Additive;
the rendered output of existing diagrams is unchanged.

- **SVG export.** `MermaidRenderer.svg(source:theme:)` renders **any of the 30
  diagram types** to a standalone SVG document — with **no CoreGraphics**. It goes
  through a new public, platform-free render IR:
  - **`RenderScene`** (`MermaidLayout`) — a `Codable` display list that fully
    determines the picture (shaped nodes, arrowed/dashed edges, text, containers,
    canvas), lowered from every diagram type. `MermaidRenderer.renderScene(source:theme:)`
    builds it; `SVGRenderer.svg(_:)` paints it. This is the foundation for the
    planned native Android renderer and a plugin/interchange contract (see
    `docs/notes/android.md`).
  - Cross-process determinism is CI-gated for the RenderScene/SVG pipeline as well
    as the raster path — the same source serializes byte-identically across
    process launches (the wire-format guarantee those consumers need).
- **New front-end: `git log` → gitgraph.** `GitLogParser.parse(_:)` turns
  `git log` output into the `GitGraph` IR — a fifth input front-end after Mermaid,
  DOT, Dippin, and SQL. Two-pass topological ordering, branch-lane derivation from
  ref decorations, and `--format gitlog` in `mermaidkit-term`.
- **Docs.** An Android support plan (`docs/notes/android.md`) and a development
  approach memo (`docs/notes/development-approach.md`).

## 1.3.0

Three new capabilities on the front/back-end seam — all additive; the rendered
output of existing diagrams is unchanged.

- **DOT export.** `DOTExporter.export(_:)` emits a `Flowchart` as Graphviz DOT —
  the inverse of the DOT front-end, so MermaidKit is now a **Mermaid ⇄ DOT
  converter**. Flat charts round-trip exactly (`parse(export(chart)) == chart`);
  clustered charts round-trip structurally. Also `export(_ diagram:) -> String?`
  for the diagram union.
- **SQL DDL → ER front-end.** `SQLDDLParser.parse(_:)` turns a `CREATE TABLE`
  schema dump into the `ERDiagram` IR: typed columns, `PRIMARY`/`FOREIGN`/`UNIQUE`
  keys (inline and table-level), and `REFERENCES` mapped to one-to-many crow's-foot
  relationships. Handles dialect quoting (`"x"`, `` `x` ``, `[x]`) and comments;
  ignores unknown clauses; degrades to `nil` on malformed/huge input.
  - **New:** `ERDiagram.Attribute.keys: [Key]` (`.primary`/`.foreign`/`.unique`),
    rendered as a compact `PK`/`FK`/`UK` badge in the entity box. The field has a
    defaulted initializer and the badge is a no-op when empty, so existing
    `erDiagram` rendering and all `Attribute(type:name:)` call sites are unchanged.
- **Diagram narration.** `MermaidAltText.narrate(_:)` gives a step-by-step
  accessibility *walkthrough* (a richer companion to `describe`'s one-line
  summary): it follows a flowchart's edges through its decisions, reads a state
  machine from its initial state, spells out an ER schema's cardinalities, and
  replays a sequence message by message; every other type falls back to
  `describe`. Deterministic and length-bounded. Mirrors `describe`'s API
  (`narrate(_:)`, `narrate(_:metadata:)`, `narrate(source:)`).
- **Docs.** Design memos on how the project is built (`development-approach.md`)
  and a runtime-plugin extensibility sketch (`plugin-extensibility.md`).

## 1.2.0

Two new front-ends, a terminal renderer, and a layout-quality pass. Additive to
the public API; the rendered output of the layered/graph families changes (for
the better), so gallery images are regenerated to match.

- **New front-ends: Graphviz DOT and Dippin.** `DOTParser.parse(_:)` and
  `DippinParser.parse(_:)` turn a `.dot` or `.dip` source into MermaidKit's
  `Flowchart` IR, so any DOT/Dippin file renders through the same layout and
  every backend (CoreGraphics/CoreText on Apple, Silica/Cairo on Linux, and the
  terminal). The DOT parser handles subgraphs/clusters, attribute defaults,
  `dir=back`, and shape mapping; the Dippin parser maps its eight node kinds
  (agent, tool, human, conditional, parallel, fan_in, subgraph, manager_loop)
  to shapes and collapses simple `when` equalities to concise edge labels.
- **New: render an already-parsed diagram.** `MermaidRenderer.pngData(diagram:)`,
  `image(diagram:)`, and `rgbaRaster(diagram:)` render a `MermaidDiagram` without
  re-serializing to Mermaid text — the path the front-ends use. `rgbaRaster`
  bounds `targetWidth` (and the derived height) to `maxRasterDimension` and
  rejects non-finite/oversized requests before allocating.
- **New shapes:** `NodeShape.hexagon` and `.subroutine`.
- **Terminal rendering (experimental).** A new `mermaidkit-term` CLI renders any
  Mermaid/DOT/Dippin source in the terminal, picking the best tier the terminal
  answers to: Kitty graphics (real image) → half-block truecolor (1×2 color
  pixels) → colored box-drawing → plain ASCII, with OSC 11 background detection
  and capability probing. Platform-free (lives in `MermaidLayout`), so it runs
  headless on Linux/CI.
- **Layout: edge labels and back-edges.** Flowchart (and the shared state /
  swimlane / ER / class families) now center edge labels on the arrow-free run
  midpoint and reserve enough connector length to clear a minimum visible stub,
  stagger crowded parallel captions, route back-edges up a gutter, and
  straighten needless jogs; fan-out edges sharing a source spread onto distinct
  tracks. New geometry-linter rules ratchet all of this: `label-on-fixture`,
  `label-crowds-edge`, and `edges-doubled`. Gallery/website images for the
  affected families are regenerated; all others render pixel-identical.

## 1.1.0

Performance and metadata refinements — additive and output-identical. The public
API and layout are unchanged except for one new convenience method.

- **New: `MermaidParser.parseWithMetadata(_:)`** — parse a source and get the
  extracted YAML front-matter (`title`, `accTitle`, `accDescr`) back in one call
  as `(diagram, DiagramMetadata)`, avoiding a second scan over the source.
- **Perf: shared-pipeline fixes** — rendered output is byte-identical (verified
  against the draw-vs-scene conformance ratchet): text measurement is now
  memoized, so each label is typeset once instead of at both layout and draw;
  the render cache key hashes the source once and keys by reference rather than
  rebuilding an interpolated string on every call.
- The one profiled optimization that *didn't* pan out — an 8-bit sRGB render
  backing store — was measured ~2× slower than the f16 default on Apple silicon
  and rejected; kept as a documented negative result.
- **Docs**: a full performance memo (`docs/notes/performance.md`) with
  methodology, per-type numbers, and where the time goes; a
  terminal-rendering-capabilities note; and the coverage audit reconciled
  against 1.0. Project site: https://2389-research.github.io/MermaidKit/

## 1.0.0

Stable release. The public API is frozen: the entry points (`MermaidParser`,
`DiagramLayoutEngine`, `DiagramScene`, `DiagramLayoutLinter`, `MermaidRenderer`,
`MermaidView`, `DiagramTheme`) are stable, and from here model/layout field
changes are semver-major.

What 1.0 is: **30 diagram types** parsed, laid out, and rendered natively —
CoreGraphics/CoreText on Apple, Silica/Cairo on Linux (behind the `LinuxRaster`
trait) — with no JavaScript and no WebView. Layout quality is machine-checked
by a geometry linter and a draw-vs-scene conformance ratchet in CI; the package
is cleanly `from:`-consumable on every platform (Silica-free by default).

- **Line breaks in labels.** `<br>` in every form (`<br>`, `<br/>`, `<br />`,
  case-insensitive, with attributes) plus a literal `\n` and any real newline
  break box/node labels and sequence notes onto multiple lines (the box grows);
  fixed chrome (legends, chart axes) collapses them to a space.

Known issue: a cross-process layout-ordering nondeterminism in a few non-layered
types (the layered/flowchart family is deterministic); tracked as an open issue.

## 0.12.0

MermaidKit is stably consumable again. **Problem: v0.11.0 pinned the Silica
Linux backend to `branch: master`, an unstable-version dependency. SwiftPM
forbids a package consumed via a stable version tag (`from: "0.x.0"`) from
transitively depending on a branch/revision, so every tagged 0.11.0 release
was UNRESOLVABLE by a normal `from:`-pinned host** (this is what stranded
Quoin on 0.10.0). Worse, even platform-conditioned, SwiftPM still fetched
Silica and its entire transitive graph (Cairo, FontConfig, PureSwift/Android,
Kotlin, JavaScriptKit, swift-java, swift-syntax — 16 packages) on macOS/iOS
consumers that never link a Silica symbol.

- The Silica/Cairo dependency and the `SilicaCairo`/`Cairo` product links are
  now gated behind a **package trait, `LinuxRaster` (SwiftPM 6.1+), default
  OFF**. A consumer that doesn't opt in resolves a graph with ZERO
  Silica/Cairo/branch dependencies — so a stable `from:` resolve is clean on
  every platform, and Apple hosts never fetch the Linux raster stack. Verified:
  a default `swift package resolve` produces an empty external graph (0
  checkouts); `--traits LinuxRaster` brings Silica + its 16-package graph back.
- Linux users who want the native raster backend opt in:
  `.package(url: "…/MermaidKit", from: "0.12.0", traits: ["LinuxRaster"])`,
  or `swift build --traits LinuxRaster`.
- CI's Linux job builds and tests with `--traits LinuxRaster` (exercising the
  Silica backend) AND builds `MermaidLayout` with default traits (proving the
  headless, Silica-free graph a `from:` consumer gets). `Package.resolved` is
  no longer committed (a trait-on lockfile would re-fetch the whole graph for
  MermaidKit's own default build); it is git-ignored.
- MermaidLayout + MermaidRender build on macOS, iOS, and Linux; the 183-test
  macOS suite and the Linux suite stay green.

Flowchart cycle back-edges (issue #1): the layered engine already routes a
back-edge through a real, node-attached polyline (confirmed across LR/TD,
tight two-node cycles, and multi-rank cycles), but nothing *guaranteed* it.

- `routeChains` can no longer emit a degenerate edge: the old
  "< 2 points" fallback shipped a `[.zero, .zero]` stub (a dangling wire at the
  origin — the reported "stray vertical line / no connector"). It now falls
  back to a straight border-to-border segment between the two nodes' anchors,
  so every flowchart edge is a non-degenerate, attached polyline.
- New scoped linter rule `edge-endpoint-detached` (node-graph families only —
  flowchart/state, whose every edge connects two boxes): flags any edge whose
  first/last polyline point is a degenerate/zero stub or lands off every node
  or container border. Sequence/ishikawa/gitgraph/wardley/treeview, whose edges
  attach to lifelines/spines/plot geometry, are exempt by construction.
- BackEdgeReproTests now asserts NON-degeneracy (distinct endpoints, real
  extent, label on the path) in addition to endpoint attachment.
- Node re-declaration (`B{Decision}` then `B[Figga]`) is deliberate and
  matches mermaid.js `addVertex`: a later explicit shape+label overrides the
  earlier; a bare back-reference (`D -->|who| B`) preserves the earlier shape.

## 0.11.0

Native rendering on **Linux**. `MermaidRender` now draws with Silica
(Cairo/FontConfig) as well as CoreGraphics/CoreText, sharing the exact layout
and per-type draw code — all 30 diagram types render to PNG and PDF headless on
swift-corelibs-foundation. See `docs/notes/linux-rendering-via-silica.md`.
(0.12.0 puts this backend behind the `LinuxRaster` trait — see above — so the
"Silica's transitive graph forces the toolchain floor / is fetched everywhere"
notes below now apply only when the trait is enabled.)

- **Toolchain floor is now Swift 6.2 / Xcode 26.** The manifest moved to
  `swift-tools-version: 6.2` (also required by package traits). All consumers
  must build with Swift 6.2+.
- `SilicaCairo` + `Cairo` are **Linux-only** target dependencies; on Apple they
  are never linked (CoreGraphics/CoreText are used, output unchanged).
- On Linux, `MermaidRenderer.image(...)` returns a `PlatformImage` with
  `pngData()` / `writePNG(to:)`; `pdfData(...)` works via Cairo's PDF surface.
  `attachmentString` (NSTextAttachment) stays Apple-only.
- **Fix Linux build** (#2): a public `CGVector` shim for swift-corelibs-foundation
  (which lacks it); a Linux CI job (`swift:6.2` + Cairo/FontConfig) that builds
  and tests the whole package, compiler-enforcing the platform-free contract.
- Flowchart cycle back-edge (#1): regression tests pinning that every edge
  attaches to its nodes and that node re-declaration matches mermaid.js.

## 0.10.0

Front-matter and accessibility metadata are first-class. Previously the
YAML front-matter block was stripped wholesale (its `title:` discarded) and
`accTitle:`/`accDescr:` lines were only tolerated by a couple of dialects.

- `MermaidParser.metadata(in:)` returns the new `DiagramMetadata`
  (`title`, `accessibilityTitle`, `accessibilityDescription`); one linear
  scan, no diagram parse. Front-matter keys other than a top-level `title:`
  (`config:`, `layout:`, `look:`, `theme:`, …) stay a graceful no-op.
- `accTitle:` / `accDescr:` statements (single-line and `accDescr { … }`
  block form, keyword case-insensitive) are stripped before any dialect
  parses the body, so they can never mint stray nodes — in ANY type.
- The front-matter `title:` renders as mermaid.js's centred caption above
  the diagram (standard title ink via the `DiagramTheme` seam), in both the
  raster and PDF paths. Dialects that draw their own title (pie, gantt, …)
  are untouched — no doubling.
- `DiagramScene` gains optional `title` / `accessibilityTitle` /
  `accessibilityDescription` fields; `DiagramScene.lower(_:metadata:measure:)`
  stamps them (geometry unchanged — metadata is data, not layout).
- `MermaidAltText` leads with the author's own accTitle/accDescr (or the
  front-matter title) before the generated structural summary;
  `attachmentString`/`MermaidView` pick that up automatically.

## 0.9.0

Flowchart subgraphs render as group boxes — the first of the audit's
"big-four structural gaps." Previously `subgraph id[Label] … end` flattened:
members drew, but the labeled group box was lost and any edge targeting a
subgraph id minted a phantom node.

- `subgraph id[Label] … end` now draws a labeled rounded box around its
  members. Nesting is arbitrary (a box inside a box), and an inner
  `direction LR/TB` reorients that group's interior independently.
- Membership follows mermaid: the first subgraph block a node textually
  appears in claims it (an inside reference wins over an earlier outside
  one; an inner block wins over its outer).
- An edge whose endpoint names a subgraph id (`Z --> GroupID`) now resolves
  to that group's box border instead of fabricating a phantom node.
- Layout is recursive: each group's interior is laid out as its own
  flowchart and placed as one sized rectangle by the parent's layered pass,
  so group boxes never overlap non-members (the geometry linter stays
  clean). Inter-group edges terminate on the box border. A group's box
  lowers to the scene as a container; its header lowers as a checked label.

Clustering also tightened member placement: the self-referential flowchart
fixture's total edge length fell from 3335 to 2808.

## 0.8.0

Sequence lifecycle and typography — the remaining Tier-1 items, validated
against websequencediagrams.com's classic feature set (all in mermaid
syntax; no extensions):

- `create participant/actor X` places the head at its creation row;
  `destroy X` ends the lifeline with the classic cross (open activation
  bars die with it).
- `<br/>` (and `<br>`) line breaks in messages and notes: rows grow,
  note boxes size to their widest line, message labels stack above the
  arrow, and column sizing measures lines rather than raw strings.
- Typed participants — `participant DB@{ "type": "database" }` — render
  head glyphs for database, queue, collections, boundary, control, and
  entity (websequencediagrams' participant types, absorbed by mermaid
  v11).

## 0.7.0

Sequence diagrams reach structural mermaid-parity for everyday syntax —
the sequence-primitives research memo's Tier 1, shipped:

- `box [color] Label ... end` participant groupings render as full-height
  background bands (color tokens recognized and dropped; our theme
  palette supplies the tint), heads dropping to give the band label
  headroom; `end` disambiguates correctly between boxes and fragments.

- Sequence diagrams: combined fragments render — `loop`/`alt`+`else`/
  `opt`/`par`+`and`/`critical`+`option`/`break` frames with kind tabs,
  guard labels, and dividers, arbitrarily nested (tolerant stack machine;
  a missing `end` closes at end-of-diagram), plus `rect` background
  bands. The layout's flat row list became a typed row stream (the
  sequence-primitives research memo's design), which variable-height rows
  and future activation bars build on. Frames lower to the scene as
  containers.
- Sequence activation bars render: `->>+`/`->>-` shorthand and explicit
  `activate`/`deactivate` statements produce execution bars on lifelines,
  nested activations stacking with rightward depth offsets; unclosed bars
  run to the lifeline bottom. Bars lower into the scene as slim nodes.
- Sequence arrows carry their identity: all mermaid arrow tokens map to
  true head styles (none/filled/cross/open/both, including v11's
  `<<->>`); `autonumber start step off` variants render as badge chips.
- Sequence `Note right of / left of / over` boxes render (author content
  that previously vanished); `actor` participants draw as stick figures.
- README/fixture: the sequence self-portrait now exercises an actor, a
  note, and an alt/else fragment.

## 0.6.0

The parser honesty sprint: syntax that used to be silently dropped — or
worse, corrupted into confident phantom content — now parses to what the
author wrote. Every fix is pinned by a regression test using the exact
previously-broken form (ParserHonestyTests).

Fabrication/corruption fixes:
- sequence: `->>+`/`->>-` activation shorthand no longer mints phantom
  `+Name`/`-Name` lifelines (the docs' first example was affected); the
  `participant P as an actor guy` alias no longer loses text to a global
  "actor " strip.
- gantt: directive lines containing colons (`axisFormat %H:%M`,
  `todayMarker`, `click ... href`) no longer become phantom task bars;
  `until` no longer becomes a task id; `y/M/s/ms` duration units parse.
- radar: positional `{1, 2, 3}` values (the docs' primary form) no longer
  render every curve flat at the minimum; multiple `axis` lines append;
  the ceiling grows to the data when `max` is unset.
- packet: `+N` is a field WIDTH after the previous field, not an absolute
  single bit — relative layouts were confidently wrong before.
- treemap: `:::styleClass` no longer destroys leaf values; `classDef`
  lines are no longer literal tree nodes.
- zenuml: comments and assignment targets no longer fabricate
  participants.
- C4: `RelIndex(i, from, to, ...)` no longer shifts the index into `from`.
- gitGraph: `cherry-pick` appears on the timeline instead of vanishing.

New flowchart syntax (was silently erased whole-line before):
- chained edges `A --> B --> C`; `&` fan-out (`A & B --> C & D`, label-safe);
  inline `-- text -->` labels; min-length links (`---->`); bidirectional
  `<-->` (new `backArrow` on Edge, drawn at both ends); `--o`/`--x` heads
  (drawn as plain arrows — honest degradation); edge IDs (`e1@-->`);
  `:::class` suffixes.

Cross-cutting: YAML front-matter (`---title/config---`) is stripped, so
every config-bearing doc example now native-renders. Fixtures exercise the
new syntax with graph-identical rewrites, so the lint corpus proves it.

## 0.5.0

Full mermaid.js type parity: **all 30 documented diagram types render.**

Seven new types, each full-stack (parser + layout + renderer + scene
lowering + linter coverage + alt-text + PDF + gallery self-portrait):

- `treeView-beta` — indentation hierarchy with folder/file glyphs; accepts
  pasted `tree` output (box-drawing normalizes to indents).
- `venn-beta` — 1-3 sets, area-proportional radii, overlap labels pushed
  into their region's private lens.
- `cynefin-beta` — the fixed 2x2 + confusion disk; transitions run in the
  outer corridor past the item stacks.
- `wardley-beta` — author-coordinate scatter with evolution bands, links,
  dashed evolve arrows, inertia bars, collision-staggered labels.
- `ishikawa-beta` — classic fishbone: spine, alternating 60-degree ribs,
  horizontal twigs (upstream's minimal documented grammar).
- `eventmodeling` — strict time-by-lane grid with typed color-coded
  frames and elbow connectors.
- `swimlane-beta` — flowchart semantics under lane constraints: global
  columns from network-simplex layering, authored lane bands, cross-lane
  orthogonal edges.

Linter refinements the new types forced: T-junctions no longer count as
edge crossings (strict-orientation test), and `mark-escapes-plot` applies
only to a sole bounding container (lanes/composites are not plots).

Benchmarks re-measured across all 30 (worst: sankey 35.8 ms rasterized —
its fixture grew and its labels gained chips; still 7x under the CI cap).

## 0.4.1

- Fix the iOS build under Swift 6.1: `UIImage.accessibilityLabel` is
  `@MainActor` in the iOS SDK, so the attachment path now sets it only
  when already on the main thread (the real text-view embedding case);
  `MermaidView`'s own accessibility label covers the view path regardless.
  Local Swift 6.2 accepted the unguarded mutation — CI's 6.1 correctly
  rejected it, and the CI step now preserves compiler diagnostics on
  failure instead of swallowing them with `tail`.

## 0.4.0

Three capabilities from the IR-compilation design review (docs/website has
the memo's conclusions; SVG/ASCII backends are deliberately deferred until
there's a concrete consumer):

- **Vector PDF export** — `MermaidRenderer.pdfData(source:theme:spacing:)`:
  the same layout and draw code as the raster path, into a `CGPDFContext`.
  Crisp at any zoom; the export/print path. All 23 fixture types verified.
- **Accessibility alt-text** — every diagram describes itself.
  `MermaidView` exposes a full content description to VoiceOver
  ("Flowchart with 12 nodes and 14 connections: ..."), `attachmentString`
  sets it on the embedded image, `MermaidRenderer.altText(source:)` and
  the platform-free `MermaidAltText.describe(_:)` expose it directly.
- **`DiagramColor`** — platform-free sRGB color values in MermaidLayout,
  and `DiagramTheme.resolved`: every theme color as `DiagramColor`,
  resolved once under the theme's pinned appearance (the fingerprint now
  derives from the same pass). The color groundwork for future
  non-CoreGraphics backends, fully additive.
- Internals: the per-type render dispatch is factored into `renderPlan` +
  `paddedCanvas`, shared by raster and PDF — new types reach every output
  format at once.

## 0.3.1

- Chain straightening after Brandes-Koepf placement, in both the flowchart
  pipeline and the class/ER/state layeredRoutes: BK's balancing step leaves
  single-parent chains a few points off their neighbour's centre (a visible
  jog, with the edge label on the kink). A gap-clamped priority pass
  (Gansner et al. section 4.2, degree-1 case) snaps them straight; where
  parent and child alignment genuinely conflict, one clean alignment wins
  over two half-jogs. Pinned by ChainAlignmentTests at 0.5pt.

## 0.3.0

The gallery becomes the documentation, and the linter learns to read.

- **Self-referential fixtures**: every example diagram is now about
  MermaidKit itself — the class diagram is the real public API, the sankey
  hero is the render pipeline, the gantt/timeline/gitgraph are the actual
  project history, the xychart plots the published benchmark numbers. The
  same 23 files are the gallery, the lint corpus, and the benchmark suite.
- **New linter invariant, `edge-cuts-label` (error)**: an edge traveling
  through bare label text fails CI. `DiagramScene.Label` gained
  `anchorEdge` (an edge label sits on its own route by design) and `backed`
  (an opaque chip interrupts a crossing line; the text stays readable) so
  the check flags only genuine defects. Found and fixed a real one on
  arrival: sankey's outboard labels now draw on canvas chips.
- **gitgraph engine upgrades** (all exposed by real-word fixture labels):
  commit columns space adaptively by measured label width; auto-generated
  ids (`c1`, `merge2`) no longer render as labels; a label whose dot has a
  branch/merge leg below it flips above the rail (or slides aside when a
  tag occupies the top).
- Docs: benchmark table re-measured on the 0.2.0 engine (worst 24.7 ms,
  most types under 12 ms); every claim audited against the code.

Model additions (pre-1.0 reshape per the stability policy):
`GitGraph.Commit.hasExplicitID`, `GitGraphLayout.Commit.label/labelCenter`,
`DiagramScene.Label.anchorEdge/backed` — all defaulted where possible.

## 0.2.0

ELK-inspired layout upgrades ("what can we learn from the Eclipse Layout
Kernel" — the answer, implemented):

- Network-simplex layering (ELK/dot's default) replaces longest-path for
  the layered family: class fixture total edge length -36%, state -32%.
- Edge labels are layout citizens: multi-layer edges reserve a real channel
  (widened median dummy) and draw their label exactly there; adjacent-layer
  labeled edges grow their inter-layer gap. Previously merged label pairs
  render separated.
- Fixed-side ports: architecture honors author-declared edge sides
  (`waf:R --> L:gateway`); Edge.fromSide/toSide are now optional (nil =
  engine picks the facing side).
- Edit stability (ELK's "consider model order"): explicit declaration-order
  tie-breaking in crossing minimization, fully deterministic optimization
  (no Set-iteration order dependence), verified by SceneDelta-based tests —
  re-runs are bit-identical, a same-width label rename moves nothing, and
  appending a leaf node has a bounded blast radius.
- `DiagramSpacing` — the density knob (`.compact`/`.regular`/
  `.comfortable`, or custom gaps), threaded through flowchart/class/ER/
  state/architecture and surfaced on MermaidView/MermaidRenderer; render
  cache keys include it. Preset safety is tested (compact stays
  occlusion-free; presets order canvas area).

## 0.1.1

- Fix iOS build: v0.1.0's trait pinning used a nonexistent
  `UIGraphicsImageRendererFormat.traitCollection` property (the UIKit branch
  had never been compiled). The format is now resolved via `.preferred()`
  under the pinned traits.
- CI now compiles MermaidRender for the iOS Simulator on every push, so the
  UIKit branch can't silently break again.

## Unreleased (pre-0.1)

Initial public release — extracted from the markdown editor it grew inside.

- 23 Mermaid diagram types parsed, laid out, and rendered natively
  (Swift + CoreGraphics, zero dependencies).
- `MermaidView` (SwiftUI), `MermaidRenderer.image`/`.attachmentString`,
  `DiagramTheme`.
- `DiagramScene` geometry IR + `DiagramLayoutLinter` — layout quality
  enforced in CI as geometric invariants.
- Adversarial-input hardening: numeric sanitation at the parser boundary,
  mermaid.js-style input caps (`maxTextSize` 50k, `maxEdges` 500), fuzz-style
  pipeline tests.
- Render benchmarks: every fixture type renders cold in <25 ms on Apple
  silicon (CI-enforced <250 ms).
- Themeable categorical palette: `DiagramTheme(palette:)` re-skins node
  tints/pie slices/sankey bands across all types; render cache now keys on
  the full theme fingerprint (a same-appearance theme change previously
  could serve a stale cached render).
- Second external audit round: fixed two reproduced process crashes
  (gantt `inf`/`nan` duration skipping the sanitizer; packet bit index at
  Int.max overflowing in layout) and two hostile-input hangs (packet
  0..1M-bit ranges, unbounded radar tick loops) — all now clamped at parse
  with adversarial regression tests. Render-layer correctness: iOS trait
  resolution pinned to the theme's appearance (dynamic colors no longer
  bake at ambient traits), theme fingerprint resolved under the same
  pinned appearance and memoized (was ambient-dependent, with a crash
  path on unconvertible colors), cache cost accounts for backing-scale
  bytes, cache hits skip re-parsing, and returned NSImages are copies so
  host mutations can't poison the cache. Async API renamed to
  `renderImage` (a same-name overload made the sync path unreachable in
  async contexts) and now propagates cancellation. Benchmarks force
  rasterization — published numbers were flattered by NSImage's deferred
  drawing; honest worst is ~19 ms (was reported 13.1).
- Swift 6 language mode (swift-tools-version 6.0), zero warnings; async
  `MermaidRenderer.image(source:theme:)` twin renders off the calling
  thread via `sending`.
- `MermaidParser.diagnose(_:)`: human-readable parse failures with 1-based
  line numbers, cap explanations, and did-you-mean header suggestions.
- Performance/robustness audit: A* router's open set is a binary heap
  (architecture fixture 22.4 -> 13.1 ms cold); render cache is bounded
  (64 MB cost limit, NSCache pressure eviction) and wrapped Sendable; both
  targets compile with ZERO warnings under -strict-concurrency=complete.
- DocC documentation catalogs for both targets (Getting Started, Theming,
  Embedding in Text Views, Headless Layout, Scene Geometry and Linting,
  Adding a Diagram Type) + `.spi.yml` for Swift Package Index hosting.
