// The corpus: hand-written regression cases (cases.json — every edge case a
// review has found) plus generated flowcharts that combine every construct the
// flowchart parser reads with the characters that have broken it: ; | # & < > "
// ( ) [ ] { } : @ % ~ — in node labels, edge labels and inline link text,
// joined by newlines or `;`. Deterministic (seeded), so a divergence can be
// pinned in known-divergences.json and re-found by its index.
//
//   node corpus.mjs [count] > corpus.json
import { readFileSync } from 'node:fs';

const count = Number(process.argv[2] ?? 1500);
// mulberry32: exact 32-bit integer arithmetic (Math.imul), so the sequence
// doesn't collapse into a short cycle the way a multiply in doubles does.
let seed = 0x2389;
const rand = () => {
  seed = (seed + 0x6D2B79F5) | 0;
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const pick = a => a[Math.floor(rand() * a.length)];

const ids = ['A', 'B', 'node1', 'api-gateway', 'auth.service', 'db_primary', 'x', 'o', 'styleguide', 'endpoint', 'Classy'];
const words = ['start', 'retry', 'then fail', 'yes', 'no', 'Store it', 'p<0.05', 'a & b', 'x;y', 'List<String>',
  '#quot;hi#quot;', '&amp; more', '#35;1', '<b>bold</b>', 'fill:#f96;', 'a|b', '(paren)', '[box]', 'k: v', 'user@host', '100%'];
const shapes = [['[', ']'], ['(', ')'], ['([', '])'], ['[[', ']]'], ['[(', ')]'], ['((', '))'], ['(((', ')))'],
  ['{', '}'], ['{{', '}}'], ['[/', '/]'], ['[\\', '\\]'], ['[/', '\\]'], ['[\\', '/]'], ['>', ']']];
const links = ['-->', '---', '==>', '===', '-.->', '-.-', '~~~', '--o', '--x', 'o--o', 'x--x', '<-->', '--->', '-..->', '====>'];

function label() {
  const w = pick(words);
  return rand() < 0.6 ? `"${w}"` : w.replace(/[\[\](){}|;"<>]/g, '');
}
function node() {
  const id = pick(ids);
  const r = rand();
  if (r < 0.3) return id;
  if (r < 0.9) { const [o, c] = pick(shapes); return `${id}${o}${label()}${c}`; }
  return `${id}@{ shape: ${pick(['diam', 'lean-r', 'cyl', 'doc', 'hex'])}, label: "${pick(words).replace(/"/g, '')}" }`;
}
function link() {
  const l = pick(links);
  const r = rand();
  if (r < 0.25) return `${l}|${pick(words).replace(/\|/g, '')}|`;
  if (r < 0.35 && l === '-->') return `-- ${pick(words).replace(/[-|>]/g, '')} -->`;
  return l;
}
function statement() {
  const r = rand();
  if (r < 0.55) return `${node()} ${link()} ${node()}`;
  if (r < 0.65) return `${node()} ${link()} ${node()} ${link()} ${node()}`;
  if (r < 0.72) return `${node()} & ${node()} ${link()} ${node()}`;
  if (r < 0.80) return node();
  if (r < 0.84) return pick([`classDef hot fill:#f96`, `style ${pick(ids)} fill:#f96,stroke:#333`, `class ${pick(ids)} hot`,
    `linkStyle 0 stroke:red`, `click ${pick(ids)} callback`, `${pick(ids)}:::hot --> ${pick(ids)}`]);
  if (r < 0.88) return `%% a comment; with ${pick(words)}`;
  return `subgraph ${pick(['one', 'two'])} [${pick(['Title', 'Group'])}]\n  ${node()} ${link()} ${node()}\nend`;
}

const charts = [];
for (let i = 0; i < count; i++) {
  const header = `${pick(['flowchart', 'graph'])} ${pick(['LR', 'TD', 'TB', 'RL', 'BT'])}`;
  const n = 1 + Math.floor(rand() * 4);
  const body = Array.from({ length: n }, statement);
  charts.push(rand() < 0.3 ? `${header}; ${body.filter(s => !s.includes('\n') && !s.startsWith('%%')).join('; ')}`
                            : `${header}\n  ${body.join('\n  ')}`);
}
const cases = JSON.parse(readFileSync(new URL('./cases.json', import.meta.url), 'utf8'));
// A corpus that repeats itself tests less than its size claims (a weak PRNG
// once cycled every ~320 charts); refuse one that does.
const distinct = new Set(charts).size;
if (distinct < charts.length * 0.98) {
  console.error(`corpus.mjs: only ${distinct} of ${charts.length} generated charts are distinct`);
  process.exit(1);
}
console.log(JSON.stringify([...cases, ...charts]));
