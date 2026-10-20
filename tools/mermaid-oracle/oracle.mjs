// mermaid.js as the oracle: parse each flowchart with mermaid's own parser and
// print what a reader would see, normalized to the comparison schema (see
// normalize.mjs) — one JSON line per source.
//
//   node oracle.mjs corpus.json > mermaid.jsonl
import { readFileSync } from 'node:fs';
import { JSDOM } from 'jsdom';
import { normalizeMermaid } from './normalize.mjs';

const dom = new JSDOM('<!doctype html><html><body></body></html>', { pretendToBeVisual: true });
globalThis.window = dom.window;
globalThis.document = dom.window.document;
const { default: mermaid } = await import('mermaid');
mermaid.initialize({ startOnLoad: false, securityLevel: 'loose' });

const sources = JSON.parse(readFileSync(process.argv[2], 'utf8'));
for (const source of sources) {
  let diagram;
  try {
    diagram = await mermaid.mermaidAPI.getDiagramFromText(source);
  } catch {
    // Mermaid's verdict: its grammar, or its own model, rejects the chart.
    console.log(JSON.stringify({ ok: false }));
    continue;
  }
  // Outside the try: a throw here is this harness failing, and it ends the
  // run instead of passing as a rejection. (compare.mjs's sentinels catch a
  // mermaid that can't run at all.)
  console.log(JSON.stringify(normalizeMermaid(diagram.db, dom.window.document)));
}
