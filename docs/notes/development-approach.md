# How we build MermaidKit — what's actually working

A reflective take on the practices behind this project, grounded in what we've
actually done rather than generic advice. It sits alongside the technical design
memos as a record of *how* the work gets made, not just what it produces.

## Architecture as the real force multiplier

The single most consequential decision was the **frontend → IR → backend** split,
with the middle (`MermaidLayout`) kept ruthlessly platform-free. It doesn't just
organize the code; it changes what's *cheap*. DOT and Dippin were "only" parsers
because the IR, layout, linter, and every backend were waiting downstream. A new
export target is "only" a `switch` over a scene. That's why we can casually scope
*seven* new formats at once — the architecture makes each one a small, bounded
piece rather than a vertical slog. When adding a whole graph language is a weekend
and adding LaTeX output is a `draw()` mirror, you brainstorm differently. Good
boundaries don't just prevent bugs; they expand the space of things worth trying.

## Encoding taste as machine-checked invariants

The most distinctive move is turning **aesthetic judgment into tests**. When a
label sits on a bend, or `fail` and `reject` crowd each other, the fix isn't
"nudge it and eyeball" — it becomes a *named geometric rule* (`label-on-fixture`,
`label-crowds-edge`, `edges-doubled`) enforced by the linter, plus a guard test
whose name reads like the original complaint (`testFailRejectLabelsStaggerVertically`).
The governing principle, stated once: **fix the generator *and* install a ratchet
so it can never regress** — the router shouldn't produce the bad geometry, and the
linter should catch it if it ever does. The "keep a ledger until I say I'm done"
workflow is the pipeline for this: each subjective gripe gets converted into an
objective, permanent check. Taste is usually the thing you can't automate; here
we quietly automate it.

## Verification over trust — including of the tools

The habit that repeatedly saves us is **never merging on assertion, always on a
full-suite run against real `main`.** That discipline is exactly what surfaced a
silently-red `main` once — an interaction between two PRs that neither PR's own
tests caught, because they were never in the same tree until merged. A "tests are
green on my branch" report is a hypothesis, not a fact; the merged tree is the
fact. The same instinct drives pixel-diffing regenerated images (`AE=0` means
re-encode noise; keep only the ones that truly changed) instead of committing a
pile of identical-looking blobs. The through-line: claims get checked,
measurements beat opinions, and empiricism shows up everywhere — the terminal
renderer *queries* capabilities rather than guessing them; label placement is
driven by measured stubs, not eyeballed offsets.

## The working relationship

The collaboration has a clear division of labor that plays to both sides: **the
human brings vision, taste, and sharp course-correction; the assistant brings
breadth, execution, and verification.** Direction is delegated wide — "handle all
the review feedback," "fix everything up" — with the work fanned out, parallelized
across isolated worktrees, and driven to green. But it's high-trust, not
blind-trust: the corrections that land are precise and load-bearing. "The DOT/Dippin
work shouldn't be in the same PR as the terminal renderer." "The label midpoint
should be the line minus its arrows on either end." Each of those redirected real
work and encoded a principle.

Two things make this productive. First, a standing demand for **real fixes over
rubber-stamps** — triage automated review feedback, apply what's genuine, decline
the noise with a reason. Second, a preference for **honesty over reassurance**:
flagging that a reported "bug" wasn't actually a memory bug, that `main` was red
before anyone touched it, that a screenshot diff was mostly noise — those land as
useful, not as failures. That's the environment that lets problems get *surfaced*
instead of papered over, which is the only way the verification discipline above
actually works. A collaborator who punishes bad news gets less of it, not fewer
bugs.

## The compounding effect

What ties it together is that each practice makes the next one cheaper. The clean
architecture makes small PRs natural; small PRs make full-suite gating fast; fast
gating makes aggressive parallel delegation safe; the linter ratchet means quality
won by hand yesterday is defended for free tomorrow. A single sitting can ship two
frontends, a terminal renderer, and a layout overhaul, recover a tangled multi-PR
merge, and regenerate the docs — *because* the groundwork makes each of those a
bounded, checkable step.

The short version: **strong boundaries so change is local, tests that encode taste
so quality is permanent, verification so nothing lands on faith, and a working
relationship where direction flows down clearly and bad news flows up safely.**
None of it is exotic. It's the compounding that makes MermaidKit punch above its
weight.
