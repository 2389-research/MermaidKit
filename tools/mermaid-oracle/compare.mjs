// Compares MermaidKit's reading of each corpus chart with mermaid.js's.
//
//   node compare.mjs corpus.json mermaid.jsonl kit.jsonl [--baseline known-divergences.json] [--update]
//
// Each chart is one of:
//   agree       same vertices (id, label, shape), edges and direction
//   lenient     mermaid errors, MermaidKit draws (allowed: degrade, never break)
//   rejects     mermaid draws, MermaidKit returns nothing          (divergence)
//   differs     both draw, but something a reader sees differs     (divergence)
// With --baseline, a divergence not in the baseline fails the run (exit 1),
// and fixed ones are reported so the baseline only ever shrinks (--update
// rewrites it).
import { readFileSync, writeFileSync } from 'node:fs';
import { createHash } from 'node:crypto';

const [corpusPath, mermaidPath, kitPath] = process.argv.slice(2);
const baselineIdx = process.argv.indexOf('--baseline');
const baselinePath = baselineIdx > 0 ? process.argv[baselineIdx + 1] : null;
const update = process.argv.includes('--update');

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
  for (const [e, n] of me) if ((ke.get(e) ?? 0) < n) out.push(`missing edge ${e}`);
  for (const [e, n] of ke) if ((me.get(e) ?? 0) < n) out.push(`extra edge ${e}`);
  return out;
}

const tally = { agree: 0, lenient: 0, rejects: 0, differs: 0 };
const divergent = {};
corpus.forEach((src, i) => {
  const m = mermaid[i], k = kit[i];
  let kind, detail = [];
  if (!m.ok && !k.ok) kind = 'agree';
  else if (!m.ok) kind = 'lenient';
  else if (!k.ok) kind = 'rejects';
  else { detail = differences(m, k); kind = detail.length ? 'differs' : 'agree'; }
  tally[kind]++;
  if (kind === 'rejects' || kind === 'differs') divergent[hash(src)] = { index: i, kind, detail: detail.slice(0, 4), source: src };
});

console.log(`mermaid oracle: ${corpus.length} charts — ${tally.agree} agree, ${tally.lenient} lenient, ` +
            `${tally.rejects} rejected, ${tally.differs} differ`);
if (!baselinePath) {
  for (const d of Object.values(divergent).slice(0, 25))
    console.log(`\n#${d.index} ${d.kind}: ${d.detail.join('; ')}\n  ${d.source.replace(/\n/g, '\n  ')}`);
  process.exit(0);
}
const baseline = update ? {} : JSON.parse(readFileSync(baselinePath, 'utf8'));
const known = new Set(Object.keys(baseline));
const fresh = Object.entries(divergent).filter(([h]) => !known.has(h));
const fixed = [...known].filter(h => !divergent[h]);
if (update) {
  // Hash → kind and corpus index only: the seeded corpus regenerates every
  // source, and --report prints the details.
  const out = Object.fromEntries(Object.entries(divergent).sort(([, a], [, b]) => a.index - b.index)
    .map(([h, d]) => [h, `${d.kind} #${d.index}`]));
  writeFileSync(baselinePath, JSON.stringify(out, null, 2) + '\n');
  console.log(`baseline rewritten: ${Object.keys(out).length} known divergences`);
  process.exit(0);
}
if (fixed.length) console.log(`${fixed.length} known divergences now agree — shrink the baseline with --update`);
for (const [, d] of fresh) console.log(`\nNEW ${d.kind}: ${d.detail.join('; ')}\n  ${d.source.replace(/\n/g, '\n  ')}`);
process.exit(fresh.length ? 1 : 0);
