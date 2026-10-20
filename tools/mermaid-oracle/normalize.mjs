// The comparison schema both sides are reduced to — what a reader sees:
//   { ok, direction, vertices: [{id, label, shape}], edges: [{from, to, label,
//     stroke, head, arrows, length}], subgraphs: [{id, title, members,
//     direction}] }
// label: visible text (entities decoded, HTML rendered, <br> as "\n",
// whitespace collapsed). shape: MermaidKit's NodeShape names, with shapes
// MermaidKit has no case for reported as "rectangle" (its documented
// fallback). stroke: normal|thick|dotted|invisible. head: arrow|circle|cross.
// arrows: none|end|both.

const classicShapes = {
  square: 'rectangle', default: 'rectangle', round: 'rounded', stadium: 'stadium',
  subroutine: 'subroutine', cylinder: 'cylinder', circle: 'circle',
  doublecircle: 'doubleCircle', diamond: 'diamond', hexagon: 'hexagon',
  lean_right: 'parallelogram', lean_left: 'parallelogramAlt',
  trapezoid: 'trapezoid', inv_trapezoid: 'trapezoidAlt', odd: 'asymmetric',
  ellipse: 'rounded',
};
// mermaid's @{ shape: … } names and aliases that have a MermaidKit case
// (from mermaid's shape registry); every other name is the rectangle fallback.
const namedShapes = {
  rect: 'rectangle', rectangle: 'rectangle', proc: 'rectangle', process: 'rectangle',
  rounded: 'rounded', event: 'rounded', stadium: 'stadium', pill: 'stadium',
  terminal: 'stadium', diam: 'diamond', diamond: 'diamond', decision: 'diamond',
  question: 'diamond', circle: 'circle', circ: 'circle', 'dbl-circ': 'doubleCircle',
  'double-circle': 'doubleCircle', cyl: 'cylinder', cylinder: 'cylinder',
  database: 'cylinder', db: 'cylinder', hex: 'hexagon', hexagon: 'hexagon',
  prepare: 'hexagon', subproc: 'subroutine', subprocess: 'subroutine',
  subroutine: 'subroutine', 'fr-rect': 'subroutine', 'framed-rectangle': 'subroutine',
  'lean-r': 'parallelogram', 'lean-right': 'parallelogram', 'in-out': 'parallelogram',
  'lean-l': 'parallelogramAlt', 'lean-left': 'parallelogramAlt', 'out-in': 'parallelogramAlt',
  'trap-b': 'trapezoid', 'trapezoid-bottom': 'trapezoid', priority: 'trapezoid',
  'trap-t': 'trapezoidAlt', 'trapezoid-top': 'trapezoidAlt', manual: 'trapezoidAlt',
  odd: 'asymmetric',
};

export function visibleText(raw, document) {
  // mermaid stores entities as placeholders and decodes them when it renders.
  const html = String(raw ?? '')
    .replace(/ﬂ°°(\d+)¶ß/g, '&#$1;')
    .replace(/ﬂ°(\w+)¶ß/g, '&$1;')
    .replace(/<br\s*\/?>/gi, '\n');
  const el = document.createElement('div');
  el.innerHTML = html;
  return collapse(el.textContent);
}

export const collapse = s => s.split('\n').map(l => l.replace(/\s+/g, ' ').trim()).join('\n').trim();

function shapeOf(type) {
  return classicShapes[type] ?? namedShapes[type] ?? 'rectangle';
}

function edgeOf(e, document) {
  const type = e.type ?? 'arrow_point';
  const both = type.startsWith('double_');
  const end = type.replace(/^double_/, '');
  const head = end === 'arrow_circle' ? 'circle' : end === 'arrow_cross' ? 'cross' : 'arrow';
  const arrows = end === 'arrow_open' ? 'none' : both ? 'both' : 'end';
  return {
    from: e.start, to: e.end, label: visibleText(e.text, document),
    stroke: e.stroke ?? 'normal', head: arrows === 'none' ? 'arrow' : head, arrows,
    length: e.length ?? 1,
  };
}

export function normalizeMermaid(db, document, source = '') {
  const raw = db.getVertices();
  const vertices = [...(raw instanceof Map ? raw.values() : Object.values(raw))].map(v => ({
    id: v.id, label: visibleText(v.text ?? v.id, document), shape: shapeOf(v.type ?? 'default'),
  }));
  const subgraphs = anonymized((db.getSubGraphs?.() ?? []).map(s => ({
    id: s.id, title: visibleText(s.title ?? '', document), members: [...s.nodes],
    direction: s.dir ? (s.dir === 'TD' ? 'TB' : s.dir) : null,
  })), id => /^subGraph\d+$/.test(id) && !declares(source, id));
  return { ok: true, direction: db.getDirection?.() ?? 'TB', vertices,
           edges: db.getEdges().map(e => edgeOf(e, document)), subgraphs };
}

/** Whether `source` names `id` in a `subgraph` statement itself (so it's not synthesized). */
function declares(source, id) {
  return new RegExp(`(^|[\\n;])\\s*subgraph\\s+${id}(?![\\w-])`).test(source);
}

/**
 * Subgraphs in a form both sides share: a title-only subgraph's synthesized
 * id (mermaid's `subGraph0`, MermaidKit's `§sub0`) becomes `§anon<k>` by its
 * place among them, in members too; members (direct nodes and child
 * subgraphs) are sorted, since only who belongs where is visible.
 */
export function anonymized(subgraphs, isSynthesized) {
  const synth = subgraphs.map(s => s.id).filter(isSynthesized)
    .sort((a, b) => Number(a.match(/\d+$/)[0]) - Number(b.match(/\d+$/)[0]));
  const name = id => synth.includes(id) ? `§anon${synth.indexOf(id)}` : id;
  return subgraphs.map(s => ({ ...s, id: name(s.id), members: s.members.map(name).sort() }))
    .sort((a, b) => (a.id < b.id ? -1 : a.id > b.id ? 1 : 0));
}
