// Compares MermaidKit's reading of each corpus chart with mermaid.js's.
//
//   node compare.mjs corpus.json mermaid.jsonl kit.jsonl [--baseline known-divergences.json] [--update | --accept]
//
// Each chart is one of:
//   agree       same vertices (id, label, shape), edges and direction. A
//               label or title MermaidKit shows with tag-like text a browser
//               hides as an element it doesn't know (`List<String>`, mermaid
//               "List") agrees too, on purpose: no text the author wrote
//               disappears. The summary counts those charts.
//   lenient     mermaid errors, MermaidKit draws (allowed: degrade, never break)
//   rejects     mermaid draws, MermaidKit returns nothing          (divergence)
//   differs     both draw, but something a reader sees differs     (divergence)
// Each divergence counts what a reader sees differently, by how bad it is:
//   missing  mermaid draws it and MermaidKit has nothing there: a node, an
//            edge between those endpoints (each parallel copy), the direction
//   wrong    it's there, but a property differs: a label, a shape, an
//            edge's label/stroke/head/arrows/length, the direction
//   extra    MermaidKit draws something mermaid doesn't
// Divergences order by (kind, missing, wrong, extra): drawing nothing is
// worse than any drawing, then losing what mermaid draws is worst, then
// drawing it wrong, then drawing extra. So no deletion can pass as progress:
// dropping anything mermaid draws raises `missing`, whatever else it fixes.
// With --baseline the run fails (exit 1) if a chart diverges that the
// baseline doesn't list, or a listed chart orders after its record: the
// baseline only ever shrinks. --update records improvements (fixed charts
// leave, better ones lower their counts) and refuses to write while anything
// got worse, or while a listed chart has left the corpus (lost coverage
// isn't a fix). --accept records everything as it stands, for a new
// baseline or a changed corpus; its diff is the reviewer's to approve.
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';
import { JSDOM } from 'jsdom';
import { collapse } from './normalize.mjs';

const [corpusPath, mermaidPath, kitPath] = process.argv.slice(2);
const baselineIdx = process.argv.indexOf('--baseline');
const baselinePath = baselineIdx > 0 ? process.argv[baselineIdx + 1] : null;
const update = process.argv.includes('--update'), accept = process.argv.includes('--accept');

const corpus = JSON.parse(readFileSync(corpusPath, 'utf8'));
const lines = p => readFileSync(p, 'utf8').trim().split('\n').map(l => JSON.parse(l));
const mermaid = lines(mermaidPath), kit = lines(kitPath);
if (mermaid.length !== corpus.length || kit.length !== corpus.length) {
  console.error(`length mismatch: corpus ${corpus.length}, mermaid ${mermaid.length}, kit ${kit.length}`);
  process.exit(2);
}
const hash = s => createHash('sha256').update(s).digest('hex').slice(0, 16);
const key = o => JSON.stringify(o, Object.keys(o).sort());

// Tag-like text: `<name …>` or `</name>` naming an element a browser doesn't
// know, which it hides. Asked of the HTML parser itself, as `visibleText`
// reads labels: `<svg>` and `<math>` are real (SVG and MathML), and a name
// only the parser accepts (`<K,V>`) is unknown.
const { document } = new JSDOM('').window;
const tagLike = /<\/?([A-Za-z][^\s/>]*)[^>]*>/g;
const unknownElement = name => {
  const fragment = document.createElement('template');
  fragment.innerHTML = `<${name}>`;
  return fragment.content.firstElementChild instanceof document.defaultView.HTMLUnknownElement;
};
// An unclosed one at the end (`List<String`), which a browser drops too.
const unclosedTagLike = /<([A-Za-z][^\s/>]*)[^>]*$/;
/** MermaidKit's text with its tag-like text removed, as a browser shows it. */
const hidingUnknownTags = text => collapse(text
  .replace(tagLike, (tag, name) => unknownElement(name) ? '' : tag)
  .replace(unclosedTagLike, (tag, name) => unknownElement(name) ? '' : tag));

/**
 * Whether MermaidKit's `kitText` reads as mermaid's: the same, or the same
 * but for tag-like text MermaidKit shows and the browser hides. (Notes that.)
 */
const sameText = (mermaidText, kitText, out) => {
  if (kitText === mermaidText) return true;
  if (hidingUnknownTags(kitText) !== mermaidText) return false;
  out.keptTags = true;
  return true;
};
const sameEdge = (e, f, out) =>
  key({ ...e, label: '' }) === key({ ...f, label: '' }) && sameText(e.label, f.label, out);

/** What a reader sees differently, sorted by how bad it is (see above). */
function differences(m, k) {
  const out = { missing: [], wrong: [], extra: [], keptTags: false };
  if (!k.ok) k = { direction: null, vertices: [], edges: [] };
  if (k.direction === null) out.missing.push(`direction ${m.direction}`);
  else if (m.direction !== k.direction) out.wrong.push(`direction ${m.direction} vs ${k.direction}`);
  const mv = new Map(m.vertices.map(v => [v.id, v])), kv = new Map();
  for (const v of k.vertices) {
    // A node drawn twice is one node and an extra copy (mermaid's side is a map).
    if (kv.has(v.id)) out.extra.push(`duplicate node ${JSON.stringify(v.id)}`); else kv.set(v.id, v);
  }
  for (const [id, v] of mv) {
    const w = kv.get(id);
    if (!w) { out.missing.push(`node ${JSON.stringify(id)}`); continue; }
    if (!sameText(v.label, w.label, out)) out.wrong.push(`node ${id} label ${JSON.stringify(v.label)} vs ${JSON.stringify(w.label)}`);
    if (v.shape !== w.shape) out.wrong.push(`node ${id} shape ${v.shape} vs ${w.shape}`);
  }
  for (const id of kv.keys()) if (!mv.has(id)) out.extra.push(`node ${JSON.stringify(id)}`);

  // Edges: exact copies pair first; what's left pairs by endpoints (a wrong
  // edge, one per pair), and the rest is missing or extra, copy by copy.
  const left = [...k.edges], unmatched = [];
  for (const e of m.edges) {
    let i = left.findIndex(f => key(f) === key(e));
    if (i < 0) i = left.findIndex(f => sameEdge(e, f, out));
    if (i >= 0) left.splice(i, 1); else unmatched.push(e);
  }
  for (const e of unmatched) {
    const i = left.findIndex(f => f.from === e.from && f.to === e.to);
    if (i < 0) { out.missing.push(`edge ${key(e)}`); continue; }
    out.wrong.push(`edge ${key(e)} vs ${key(left[i])}`);
    left.splice(i, 1);
  }
  for (const f of left) out.extra.push(`edge ${key(f)}`);

  // Subgraphs, by (normalized) id: a missing box is missing; a wrong title or
  // direction, or each member in the wrong box, is wrong; a box mermaid
  // doesn't draw is extra.
  const ms = new Map((m.subgraphs ?? []).map(s => [s.id, s])), ks = new Map((k.subgraphs ?? []).map(s => [s.id, s]));
  for (const [id, s] of ms) {
    const t = ks.get(id);
    if (!t) { out.missing.push(`subgraph ${JSON.stringify(id)}`); continue; }
    if (!sameText(s.title, t.title, out)) out.wrong.push(`subgraph ${id} title ${JSON.stringify(s.title)} vs ${JSON.stringify(t.title)}`);
    if (s.direction !== t.direction) out.wrong.push(`subgraph ${id} direction ${s.direction} vs ${t.direction}`);
    for (const n of s.members) if (!t.members.includes(n)) out.wrong.push(`subgraph ${id} lacks ${JSON.stringify(n)}`);
    for (const n of t.members) if (!s.members.includes(n)) out.wrong.push(`subgraph ${id} wrongly holds ${JSON.stringify(n)}`);
  }
  for (const id of ks.keys()) if (!ms.has(id)) out.extra.push(`subgraph ${JSON.stringify(id)}`);
  return out;
}
const counts = d => ({ missing: d.missing.length, wrong: d.wrong.length, extra: d.extra.length });
const total = d => d.missing.length + d.wrong.length + d.extra.length;
const describe = d => [...d.missing.map(x => `missing ${x}`), ...d.wrong.map(x => `wrong ${x}`),
                       ...d.extra.map(x => `extra ${x}`)];

// The corpus opens with sentinels.json: charts both parsers must read, and
// alike. If one doesn't, the harness is broken (mermaid failing to load
// would otherwise pass as every chart "lenient"), so nothing else counts.
const sentinels = JSON.parse(readFileSync(new URL('./sentinels.json', import.meta.url), 'utf8'));
sentinels.forEach((src, i) => {
  const m = mermaid[i], k = kit[i];
  if (corpus[i] !== src || !m.ok || !k.ok || total(differences(m, k))) {
    console.error(`sentinel #${i} failed — the oracle harness is broken, not the parser:\n  ` +
                  `mermaid ok=${m?.ok}, MermaidKit ok=${k?.ok}` + (m?.ok && k?.ok ? `: ${describe(differences(m, k)).join('; ')}` : ''));
    process.exit(2);
  }
});
// The tag-like-text rule must only ever excuse unknown tags: if it excuses
// anything else, it could hide a real divergence, so nothing else counts.
const tagRule = [
  ['List<String>', 'List', true], ['Map<K,V> x', 'Map x', true], ['a <T> b', 'a b', true],
  ['x<b>y</b>z', 'xyz', false], ['Vec<i> and List<a>', 'Vec and List', false], ['a<br>b', 'a\nb', false],
  ['x<svg>y', 'xy', false], ['x<math>y</math>', 'xy', false],
  ['<my-el>x', 'x', false], ['List<String>', 'Lis', false], ['p<0.05', 'p', false],
  ['List<String', 'List', true], ['<bbold</b', '', true], ['x<b', 'x', false], ['List<String x', 'List<String', false],
];
for (const [kitText, mermaidText, excused] of tagRule) {
  if ((kitText !== mermaidText && hidingUnknownTags(kitText) === mermaidText) !== excused) {
    console.error(`the tag-like-text rule is broken: ${JSON.stringify(kitText)} vs ${JSON.stringify(mermaidText)} ` +
                  `should ${excused ? '' : 'not '}agree`);
    process.exit(2);
  }
}
const tally = { agree: 0, lenient: 0, rejects: 0, differs: 0, keptTags: 0 };
const divergent = {};
corpus.forEach((src, i) => {
  const m = mermaid[i], k = kit[i];
  let kind;
  if (!m.ok && !k.ok) kind = 'agree';
  else if (!m.ok) kind = 'lenient';
  else if (!k.ok) kind = 'rejects';
  else kind = total(differences(m, k)) ? 'differs' : 'agree';
  tally[kind]++;
  if (kind === 'agree' && m.ok && k.ok && differences(m, k).keptTags) tally.keptTags++;
  if (kind === 'rejects' || kind === 'differs') {
    const diff = differences(m, k);
    divergent[hash(src)] = { index: i, kind, ...counts(diff), detail: describe(diff), source: src };
  }
});

console.log(`mermaid oracle: ${corpus.length} charts — ${tally.agree} agree (${tally.keptTags} keeping tag-like text), ${tally.lenient} lenient, ` +
            `${tally.rejects} rejected, ${tally.differs} differ`);
const tallyOf = d => `${d.missing} missing, ${d.wrong} wrong, ${d.extra} extra`;
const show = (tag, d) =>
  console.log(`\n${tag}#${d.index} ${d.kind} (${tallyOf(d)}): ${d.detail.join('; ')}\n  ${d.source.replace(/\n/g, '\n  ')}`);
if (!baselinePath) {
  for (const d of Object.values(divergent)) show('', d);
  process.exit(0);
}
// Hash → kind, corpus index and counts: the seeded corpus regenerates every
// source, and --report prints the details.
const write = entries => {
  const rows = entries.sort(([, a], [, b]) => a.index - b.index)
    .map(([h, d]) => `  ${JSON.stringify(h)}: ${JSON.stringify({ kind: d.kind, index: d.index, missing: d.missing, wrong: d.wrong, extra: d.extra })}`);
  writeFileSync(baselinePath, `{\n${rows.join(',\n')}\n}\n`);
  console.log(`baseline written: ${entries.length} known divergences`);
};
if (accept) { write(Object.entries(divergent)); process.exit(0); }

const baseline = JSON.parse(readFileSync(baselinePath, 'utf8'));
const inCorpus = new Set(corpus.map(hash));
const fresh = Object.entries(divergent).filter(([h]) => !baseline[h]);
// (kind, missing, wrong, extra) in order; see the top of this file.
const rank = d => [d.kind === 'rejects' ? 1 : 0, d.missing, d.wrong, d.extra];
const order = (a, b) => { const [x, y] = [rank(a), rank(b)]; return x.reduce((r, v, i) => r || v - y[i], 0); };
const worse = Object.entries(divergent).filter(([h, d]) => baseline[h] && order(d, baseline[h]) > 0);
const better = Object.entries(divergent).filter(([h, d]) => baseline[h] && order(d, baseline[h]) < 0);
const fixed = Object.keys(baseline).filter(h => inCorpus.has(h) && !divergent[h]);
const gone = Object.keys(baseline).filter(h => !inCorpus.has(h));
for (const [, d] of fresh) show('NEW ', d);
for (const [h, d] of worse) show(`WORSE (was ${baseline[h].kind}, ${tallyOf(baseline[h])}) `, d);
// A known chart leaving the corpus is lost coverage, not a fix.
for (const h of gone) console.log(`\nGONE ${h} (${baseline[h].kind} #${baseline[h].index}): no longer in the corpus`);
const failed = fresh.length + worse.length + gone.length > 0;
if (failed) console.log(`\n${fresh.length} new, ${worse.length} worse and ${gone.length} gone divergences`);
if (fixed.length || better.length)
  console.log(`${fixed.length} known divergences now agree and ${better.length} improved` +
              (update ? '' : ' — shrink the baseline with --update'));
if (update) {
  if (failed) { console.log('baseline not written: fix what got worse or went missing, or --accept it for review'); process.exit(1); }
  write(Object.entries(divergent));
}
process.exit(failed ? 1 : 0);
