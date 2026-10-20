// Compares MermaidKit's reading of each corpus chart with mermaid.js's.
//
//   node compare.mjs corpus.json mermaid.jsonl kit.jsonl [--baseline known-divergences.json] [--update | --accept]
//
// Each chart is one of:
//   agree       same vertices (id, label, shape), edges and direction
//   lenient     mermaid errors, MermaidKit draws (allowed: degrade, never break)
//   rejects     mermaid draws, MermaidKit returns nothing          (divergence)
//   differs     both draw, but something a reader sees differs     (divergence)
// Each divergence has a cost: how many things a reader sees differently
// (a rejected chart costs everything mermaid drew, plus its direction).
// With --baseline the run fails (exit 1) if a chart diverges that the
// baseline doesn't list, or a listed chart costs more than recorded: the
// baseline only ever shrinks. --update records improvements (fixed charts
// leave, cheaper ones lower their cost) and refuses to write while anything
// got worse, or while a listed chart has left the corpus (lost coverage
// isn't a fix). --accept records everything as it stands, for a new
// baseline or a changed corpus; its diff is the reviewer's to approve.
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

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

function differences(m, k) {
  const out = [];
  if (!k.ok) k = { direction: null, vertices: [], edges: [] };
  if (m.direction !== k.direction) out.push(`direction ${m.direction} vs ${k.direction}`);
  const mv = new Map(m.vertices.map(v => [v.id, v])), kv = new Map(k.vertices.map(v => [v.id, v]));
  for (const [id, v] of mv) {
    const w = kv.get(id);
    if (!w) { out.push(`missing node ${JSON.stringify(id)}`); continue; }
    if (v.label !== w.label) out.push(`node ${id} label ${JSON.stringify(v.label)} vs ${JSON.stringify(w.label)}`);
    if (v.shape !== w.shape) out.push(`node ${id} shape ${v.shape} vs ${w.shape}`);
  }
  for (const id of kv.keys()) if (!mv.has(id)) out.push(`extra node ${JSON.stringify(id)}`);
  const count = es => es.reduce((m, e) => (m.set(key(e), (m.get(key(e)) ?? 0) + 1), m), new Map());
  const me = count(m.edges), ke = count(k.edges);
  // One difference per missing or extra copy, so parallel edges count each.
  for (const [e, n] of me) for (let c = ke.get(e) ?? 0; c < n; c++) out.push(`missing edge ${e}`);
  for (const [e, n] of ke) for (let c = me.get(e) ?? 0; c < n; c++) out.push(`extra edge ${e}`);
  return out;
}

// The corpus opens with sentinels.json: charts both parsers must read, and
// alike. If one doesn't, the harness is broken (mermaid failing to load
// would otherwise pass as every chart "lenient"), so nothing else counts.
const sentinels = JSON.parse(readFileSync(new URL('./sentinels.json', import.meta.url), 'utf8'));
sentinels.forEach((src, i) => {
  const m = mermaid[i], k = kit[i];
  if (corpus[i] !== src || !m.ok || !k.ok || differences(m, k).length) {
    console.error(`sentinel #${i} failed — the oracle harness is broken, not the parser:\n  ` +
                  `mermaid ok=${m?.ok}, MermaidKit ok=${k?.ok}` + (m?.ok && k?.ok ? `: ${differences(m, k).join('; ')}` : ''));
    process.exit(2);
  }
});
const tally = { agree: 0, lenient: 0, rejects: 0, differs: 0 };
const divergent = {};
corpus.forEach((src, i) => {
  const m = mermaid[i], k = kit[i];
  let kind;
  if (!m.ok && !k.ok) kind = 'agree';
  else if (!m.ok) kind = 'lenient';
  else if (!k.ok) kind = 'rejects';
  else kind = differences(m, k).length ? 'differs' : 'agree';
  tally[kind]++;
  if (kind === 'rejects' || kind === 'differs') {
    const detail = differences(m, k);
    divergent[hash(src)] = { index: i, kind, cost: detail.length, detail, source: src };
  }
});

console.log(`mermaid oracle: ${corpus.length} charts — ${tally.agree} agree, ${tally.lenient} lenient, ` +
            `${tally.rejects} rejected, ${tally.differs} differ`);
const show = (tag, d) =>
  console.log(`\n${tag}#${d.index} ${d.kind} (cost ${d.cost}): ${d.detail.join('; ')}\n  ${d.source.replace(/\n/g, '\n  ')}`);
if (!baselinePath) {
  for (const d of Object.values(divergent)) show('', d);
  process.exit(0);
}
// Hash → kind, corpus index and cost: the seeded corpus regenerates every
// source, and --report prints the details.
const write = entries => {
  const rows = entries.sort(([, a], [, b]) => a.index - b.index)
    .map(([h, d]) => `  ${JSON.stringify(h)}: ${JSON.stringify({ kind: d.kind, index: d.index, cost: d.cost })}`);
  writeFileSync(baselinePath, `{\n${rows.join(',\n')}\n}\n`);
  console.log(`baseline written: ${entries.length} known divergences`);
};
if (accept) { write(Object.entries(divergent)); process.exit(0); }

const baseline = JSON.parse(readFileSync(baselinePath, 'utf8'));
const inCorpus = new Set(corpus.map(hash));
const fresh = Object.entries(divergent).filter(([h]) => !baseline[h]);
const worse = Object.entries(divergent).filter(([h, d]) => baseline[h] && d.cost > baseline[h].cost);
const better = Object.entries(divergent).filter(([h, d]) => baseline[h] && d.cost < baseline[h].cost);
const fixed = Object.keys(baseline).filter(h => inCorpus.has(h) && !divergent[h]);
const gone = Object.keys(baseline).filter(h => !inCorpus.has(h));
for (const [, d] of fresh) show('NEW ', d);
for (const [h, d] of worse) show(`WORSE (was cost ${baseline[h].cost}) `, d);
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
