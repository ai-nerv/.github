const UNITS = {
  magi: {
    kind: "crate",
    nodes: {"magi-model":{loc:739},"magi-proto":{loc:2947},"magi-ipc":{loc:1080},
      "magi-journal":{loc:808},"magi-tui":{loc:14151},"magi-tools":{loc:6287},
      "magi-lua":{loc:2877},"magi-core":{loc:435},"magi-host":{loc:9190},
      "magi-testkit":{loc:1080},"magi-cli":{loc:12474}},
    deps: {"magi-model":[],"magi-proto":["magi-model"],"magi-ipc":["magi-proto"],
      "magi-journal":["magi-proto"],"magi-tui":["magi-proto"],
      "magi-tools":["magi-ipc","magi-model","magi-proto"],"magi-lua":["magi-tools"],
      "magi-core":["magi-model"],"magi-testkit":["magi-ipc","magi-model","magi-proto"],
      "magi-host":["magi-core","magi-ipc","magi-journal","magi-lua","magi-model","magi-proto","magi-tools"],
      "magi-cli":["magi-host","magi-ipc","magi-lua","magi-model","magi-proto","magi-testkit","magi-tools","magi-tui"]},
    dev: {"magi-ipc":["magi-model"],"magi-journal":["magi-model"],"magi-lua":["magi-model"],
      "magi-host":["magi-testkit"],"magi-cli":["magi-journal"]},
    tests: 1414, strip: "magi-"
  },
  balthasar: {
    kind: "crate",
    nodes: {"balthasar-model":{loc:5262},"balthasar-ipc":{loc:693},"balthasar-embed":{loc:668},
      "balthasar-store":{loc:8417},"balthasar-lua":{loc:2989},"balthasar-buffer":{loc:695},
      "balthasar-recall":{loc:2411},"balthasar-distil":{loc:5125},"balthasar-host":{loc:1806},
      "balthasar-testkit":{loc:4106},"balthasar-cli":{loc:5765},"balthasar":{loc:9}},
    deps: {"balthasar-model":[],"balthasar-ipc":[],"balthasar-embed":[],
      "balthasar-store":["balthasar-model"],"balthasar-lua":["balthasar-model"],
      "balthasar-buffer":["balthasar-store"],
      "balthasar-recall":["balthasar-lua","balthasar-model","balthasar-store"],
      "balthasar-distil":["balthasar-lua","balthasar-model","balthasar-store"],
      "balthasar-host":["balthasar-buffer","balthasar-ipc","balthasar-lua","balthasar-model","balthasar-store"],
      "balthasar-testkit":["balthasar-distil","balthasar-lua","balthasar-model","balthasar-recall","balthasar-store"],
      "balthasar-cli":["balthasar-distil","balthasar-embed","balthasar-host","balthasar-ipc","balthasar-lua","balthasar-model","balthasar-recall","balthasar-store","balthasar-testkit"],
      "balthasar":["balthasar-cli"]},
    dev: {"balthasar-distil":["balthasar-embed"],"balthasar":["balthasar-model","balthasar-store"]},
    tests: 968, strip: "balthasar-"
  },
  melchior: {
    kind: "module",
    nodes: {wire:{loc:497},identity:{loc:287},inherited:{loc:53},scratch:{loc:166},
      tool:{loc:143},noted:{loc:93},framing:{loc:172},policy:{loc:531},mind:{loc:7314},
      asking:{loc:203},directory:{loc:750},answering:{loc:789},verbs:{loc:1278},
      briefing:{loc:225},serving:{loc:860}},
    deps: {wire:[],identity:[],inherited:[],scratch:[],tool:[],noted:["scratch"],
      framing:["wire"],policy:["inherited"],mind:["noted","scratch"],
      asking:["framing","identity","noted","wire"],
      directory:["asking","identity","inherited","policy","wire"],
      answering:["directory","identity","inherited","mind","policy","wire"],
      verbs:["asking","directory","identity","policy","wire"],
      briefing:["directory","policy","verbs","wire"],
      serving:["answering","asking","directory","framing","identity","inherited","policy","wire"]},
    dev: {}, tests: 334, strip: ""
  },
  casper: {
    kind: "module",
    nodes: {wire:{loc:174},noted:{loc:133},paint:{loc:445},tools:{loc:432},
      lua:{loc:2258},pty:{loc:1235},surface:{loc:871}},
    deps: {wire:[],noted:[],paint:[],tools:["paint"],lua:["noted","paint","tools"],
      pty:["noted","paint","tools"],surface:["lua","pty","tools"]},
    dev: {}, tests: 145, strip: ""
  }
};

function ranks(names, deps) {
  const rank = {};
  const of = (n, seen = new Set()) => {
    if (n in rank) return rank[n];
    if (seen.has(n)) return 0;
    seen.add(n);
    const ds = (deps[n] || []).filter(d => names.includes(d));
    rank[n] = ds.length ? 1 + Math.max(...ds.map(d => of(d, seen))) : 0;
    return rank[n];
  };
  names.forEach(n => of(n));
  return rank;
}

function draw(host, unit) {
  const names = Object.keys(unit.nodes);
  const rank = ranks(names, unit.deps);
  const depth = Math.max(...Object.values(rank));
  const maxLoc = Math.max(...names.map(n => unit.nodes[n].loc));
  const label = n => (unit.strip && n !== unit.strip.slice(0, -1)) ? n.replace(unit.strip, "") : n;
  const boxW = n => Math.round(Math.max(
    7.7 * label(n).length + 28,
    52 + 92 * Math.sqrt(unit.nodes[n].loc / maxLoc)
  ));

  const H = 38, GAP_X = 18, ROW = 88, PAD_L = 54, PAD_R = 18, PAD_T = 22, PAD_B = 22;
  const rows = [];
  for (let r = 0; r <= depth; r++) rows[r] = names.filter(n => rank[n] === r);
  rows[0].sort((a, b) => unit.nodes[b].loc - unit.nodes[a].loc);
  const pos = {};
  const place = r => {
    let x = 0;
    rows[r].forEach(n => { pos[n] = { x, w: boxW(n) }; x += boxW(n) + GAP_X; });
    return x - GAP_X;
  };
  let widest = place(0);
  for (let r = 1; r <= depth; r++) {
    rows[r].sort((a, b) => {
      const bary = n => {
        const ds = (unit.deps[n] || []).filter(d => d in pos);
        return ds.length ? ds.reduce((s, d) => s + pos[d].x + pos[d].w / 2, 0) / ds.length : 0;
      };
      return bary(a) - bary(b);
    });
    widest = Math.max(widest, place(r));
  }
  for (let r = 0; r <= depth; r++) {
    const rowW = rows[r].reduce((s, n) => s + boxW(n), 0) + GAP_X * (rows[r].length - 1);
    const off = (widest - rowW) / 2;
    rows[r].forEach(n => { pos[n].x += off; pos[n].y = PAD_T + (depth - r) * ROW; });
  }

  const W = PAD_L + widest + PAD_R;
  const Hgt = PAD_T + depth * ROW + H + PAD_B;
  const svg = el("svg", { viewBox: `0 0 ${W} ${Hgt}`, width: W, height: Hgt,
                          role: "img", "aria-label": `${unit.kind} graph` });

  for (let r = 0; r <= depth; r++) {
    const t = el("text", { x: PAD_L - 12, y: PAD_T + (depth - r) * ROW + H / 2, class: "rank-label" });
    t.textContent = r === 0 ? "leaf" : String(r);
    svg.appendChild(t);
  }

  const edges = [];
  const addEdges = (map, cls) => {
    for (const [from, list] of Object.entries(map)) {
      for (const to of list) {
        if (!(from in pos) || !(to in pos)) continue;
        const a = pos[from], b = pos[to];
        const x1 = PAD_L + a.x + a.w / 2, y1 = a.y + H;
        const x2 = PAD_L + b.x + b.w / 2, y2 = b.y;
        const mid = (y1 + y2) / 2;
        const p = el("path", { d: `M${x1} ${y1} C ${x1} ${mid}, ${x2} ${mid}, ${x2} ${y2}`,
                               class: `edge ${cls}` });
        p.dataset.from = from; p.dataset.to = to;
        edges.push(p); svg.appendChild(p);
      }
    }
  };
  addEdges(unit.deps, "");
  addEdges(unit.dev, "dev");

  names.forEach(n => {
    const { x, y, w } = pos[n];
    const g = el("g", { class: "node", tabindex: "0" });
    g.appendChild(el("rect", { x: PAD_L + x, y, width: w, height: H }));
    const t = el("text", { x: PAD_L + x + w / 2, y: y + 14 });
    t.textContent = label(n);
    g.appendChild(t);
    const l = el("text", { x: PAD_L + x + w / 2, y: y + 27, class: "loc" });
    l.textContent = unit.nodes[n].loc.toLocaleString();
    g.appendChild(l);
    const lit = on => {
      g.classList.toggle("lit", on);
      edges.forEach(e => {
        if (e.dataset.from === n || e.dataset.to === n) e.classList.toggle("lit", on);
      });
    };
    g.addEventListener("pointerenter", () => lit(true));
    g.addEventListener("pointerleave", () => lit(false));
    g.addEventListener("focus", () => lit(true));
    g.addEventListener("blur", () => lit(false));
    svg.appendChild(g);
  });
  host.appendChild(svg);
}

// Drawn only where the page asked for one. Every page loads this file; most want one graph or none.
for (const [name, unit] of Object.entries(UNITS)) {
  const host = document.getElementById("g-" + name);
  if (!host) continue;
  draw(host, unit);
  const meta = document.getElementById("meta-" + name);
  if (!meta) continue;
  const n = Object.keys(unit.nodes).length;
  const loc = Object.values(unit.nodes).reduce((s, c) => s + c.loc, 0);
  meta.textContent =
    `${n} ${unit.kind}s · ${loc.toLocaleString()} lines · ${unit.tests.toLocaleString()} tests`;
}
