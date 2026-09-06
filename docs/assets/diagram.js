/* ------------------------------------------------------------------ drawing primitives ---- */
const NS = "http://www.w3.org/2000/svg";
const el = (n, a = {}) => {
  const e = document.createElementNS(NS, n);
  for (const [k, v] of Object.entries(a)) e.setAttribute(k, v);
  return e;
};
const text = (x, y, s, cls) => { const t = el("text", { x, y, class: cls }); t.textContent = s; return t; };

/* A sheet with an arrowhead defined, sized to its own contents. */
function sheet(w, h) {
  const svg = el("svg", { viewBox: `0 0 ${w} ${h}`, width: w, height: h, role: "img" });
  const defs = el("defs");
  for (const [id, cls] of [["ar", "line"], ["arh", "hot"]]) {
    const m = el("marker", { id, viewBox: "0 0 8 8", refX: 7, refY: 4,
      markerWidth: 7, markerHeight: 7, orient: "auto-start-reverse" });
    const p = el("path", { d: "M0,0 L8,4 L0,8 z" });
    p.setAttribute("fill", cls === "hot" ? "var(--accent)" : "var(--line)");
    m.appendChild(p); defs.appendChild(m);
  }
  svg.appendChild(defs);
  return svg;
}

/* Where a straight line from `a` to `b` leaves a's border. */
function edgeOf(a, to) {
  const cx = a.x + a.w / 2, cy = a.y + a.h / 2;
  const dx = to.x - cx, dy = to.y - cy;
  if (dx === 0 && dy === 0) return [cx, cy];
  const sx = dx === 0 ? Infinity : (a.w / 2) / Math.abs(dx);
  const sy = dy === 0 ? Infinity : (a.h / 2) / Math.abs(dy);
  const s = Math.min(sx, sy);
  return [cx + dx * s, cy + dy * s];
}

/* One node: a rectangle, or a diamond when it asks a question. */
function drawNode(svg, n) {
  const cx = n.x + n.w / 2, cy = n.y + n.h / 2;
  const cls = n.kind === "hub" ? "n-hub" : n.kind === "ext" ? "n-ext"
            : n.kind === "stop" ? "n-stop" : "n-box";
  if (n.kind === "ask") {
    svg.appendChild(el("polygon", {
      points: `${cx},${n.y} ${n.x + n.w},${cy} ${cx},${n.y + n.h} ${n.x},${cy}`, class: "n-box" }));
  } else {
    svg.appendChild(el("rect", { x: n.x, y: n.y, width: n.w, height: n.h, rx: 2, class: cls }));
  }
  const lines = String(n.label).split("|");
  const subs = n.sub ? String(n.sub).split("|") : [];
  const total = lines.length + subs.length;
  let ty = cy - (total - 1) * 6.5 + 4;
  for (const l of lines) { svg.appendChild(text(cx, ty, l, "n-lab")); ty += 13; }
  for (const s of subs) { svg.appendChild(text(cx, ty, s, "n-sub")); ty += 12; }
}

/* One edge, with an optional label on a chip so it reads over anything. */
function drawEdge(svg, from, to, e) {
  const bend = e.bend || 0;
  const [x1, y1] = edgeOf(from, { x: to.x + to.w / 2, y: to.y + to.h / 2 });
  const [x2, y2] = edgeOf(to, { x: from.x + from.w / 2, y: from.y + from.h / 2 });
  const hot = e.hot ? " hot" : "";
  const dash = e.dash ? " dash" : "";
  let d, mx, my;
  if (bend) {
    const cx = (x1 + x2) / 2 + bend, cy = (y1 + y2) / 2;
    d = `M${x1},${y1} Q${cx},${cy} ${x2},${y2}`;
    mx = (x1 + 2 * cx + x2) / 4; my = (y1 + 2 * cy + y2) / 4;
  } else {
    d = `M${x1},${y1} L${x2},${y2}`;
    mx = (x1 + x2) / 2; my = (y1 + y2) / 2;
  }
  const p = el("path", { d, class: `e-line${hot}${dash}` });
  p.setAttribute("marker-end", e.hot ? "url(#arh)" : "url(#ar)");
  if (e.both) p.setAttribute("marker-start", e.hot ? "url(#arh)" : "url(#ar)");
  svg.appendChild(p);
  if (!e.label) return;
  const rows = String(e.label).split("|");
  const wide = Math.max(...rows.map(r => r.length)) * 5.6 + 10;
  const h = rows.length * 11 + 4;
  svg.appendChild(el("rect", { x: mx - wide / 2, y: my - h / 2, width: wide, height: h, class: "e-chip" }));
  let ty = my - (rows.length - 1) * 5.5 + 3.5;
  for (const r of rows) { svg.appendChild(text(mx, ty, r, `e-lab${hot}`)); ty += 11; }
}

/* A node-and-edge drawing, laid out by hand: positions are the design. */
function graph(host, spec) {
  const svg = sheet(spec.w, spec.h);
  const at = Object.fromEntries(spec.nodes.map(n => [n.id, n]));
  for (const e of spec.edges) drawEdge(svg, at[e.from], at[e.to], e);
  for (const n of spec.nodes) drawNode(svg, n);
  host.appendChild(svg);
}

/* A lane drawing: columns are processes, each row is one message. */
function lanes(host, spec) {
  const LANE_W = spec.laneW || 150, TOP = 46, STEP = spec.step || 30;
  const w = spec.lanes.length * LANE_W, h = TOP + spec.steps.length * STEP + 26;
  const svg = sheet(w, h);
  const x = i => i * LANE_W + LANE_W / 2;
  spec.lanes.forEach((l, i) => {
    svg.appendChild(el("line", { x1: x(i), y1: TOP, x2: x(i), y2: h - 14, class: "lane" }));
    const bw = Math.min(LANE_W - 14, l.label.length * 7.5 + 20);
    svg.appendChild(el("rect", { x: x(i) - bw / 2, y: 8, width: bw, height: 26, rx: 2,
      class: l.hub ? "n-hub" : "n-box" }));
    svg.appendChild(text(x(i), 25, l.label, "n-lab"));
  });
  spec.steps.forEach((s, i) => {
    const y = TOP + 20 + i * STEP;
    if (s.note) {
      svg.appendChild(el("rect", { x: x(s.at) - 78, y: y - 12, width: 156, height: 22,
        rx: 2, class: "n-stop" }));
      svg.appendChild(text(x(s.at), y + 3, s.note, "n-sub"));
      return;
    }
    const a = x(s.from), b = x(s.to);
    const dir = b > a ? -1 : 1;
    const p = el("path", { d: `M${a + dir * -4},${y} L${b + dir * 4},${y}`,
      class: `e-line${s.back ? " dash" : ""}${s.hot ? " hot" : ""}` });
    p.setAttribute("marker-end", s.hot ? "url(#arh)" : "url(#ar)");
    svg.appendChild(p);
    svg.appendChild(text((a + b) / 2, y - 6, s.label, `e-lab${s.hot ? " hot" : ""}`));
    svg.appendChild(text(Math.min(a, b) - 12, y + 3, String(i + 1), "step-n"));
  });
  host.appendChild(svg);
}

