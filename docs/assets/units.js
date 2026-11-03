const UNITS = {
  magi: {
    kind: "crate",
    nodes: {"magi-cli":{"loc":37193},"magi-core":{"loc":436},"magi-host":{"loc":55361},
      "magi-ipc":{"loc":3967},"magi-journal":{"loc":526},"magi-lua":{"loc":5606},
      "magi-model":{"loc":1283},"magi-proto":{"loc":3995},"magi-testkit":{"loc":1772},
      "magi-tools":{"loc":10797},"magi-tui":{"loc":22703}},
    deps: {"magi-cli":["magi-host","magi-ipc","magi-lua","magi-model","magi-proto","magi-testkit","magi-tools","magi-tui"],
      "magi-core":["magi-model"],
      "magi-host":["magi-core","magi-ipc","magi-journal","magi-lua","magi-model","magi-proto","magi-tools"],
      "magi-ipc":["magi-proto"],"magi-journal":["magi-proto"],
      "magi-lua":["magi-model","magi-tools"],"magi-model":[],"magi-proto":["magi-model"],
      "magi-testkit":["magi-ipc","magi-model","magi-proto"],
      "magi-tools":["magi-ipc","magi-model","magi-proto"],"magi-tui":["magi-proto"]},
    dev: {"magi-cli":["magi-journal"],"magi-host":["magi-testkit"],
      "magi-ipc":["magi-model","magi-testkit"],"magi-journal":["magi-model"],
      "magi-lua":["magi-testkit"]},
    tests: 2814, strip: "magi-"
  },
  balthasar: {
    kind: "crate",
    nodes: {"balthasar-buffer":{"loc":2807},"balthasar-cli":{"loc":7605},"balthasar-distil":{"loc":7875},
      "balthasar-embed":{"loc":918},"balthasar-host":{"loc":23627},"balthasar-ipc":{"loc":3193},
      "balthasar-lua":{"loc":6737},"balthasar-model":{"loc":4982},"balthasar-recall":{"loc":2152},
      "balthasar-store":{"loc":19504},"balthasar-testkit":{"loc":4556},"balthasar":{"loc":2048}},
    deps: {"balthasar-buffer":["balthasar-store"],
      "balthasar-cli":["balthasar-distil","balthasar-embed","balthasar-host","balthasar-ipc","balthasar-lua","balthasar-model","balthasar-recall","balthasar-store","balthasar-testkit"],
      "balthasar-distil":["balthasar-lua","balthasar-model","balthasar-store"],"balthasar-embed":[],
      "balthasar-host":["balthasar-buffer","balthasar-ipc","balthasar-lua","balthasar-model","balthasar-store"],
      "balthasar-ipc":["balthasar-model"],"balthasar-lua":["balthasar-model"],"balthasar-model":[],
      "balthasar-recall":["balthasar-lua","balthasar-model","balthasar-store"],
      "balthasar-store":["balthasar-model"],
      "balthasar-testkit":["balthasar-distil","balthasar-lua","balthasar-model","balthasar-recall","balthasar-store"],
      "balthasar":["balthasar-cli"]},
    dev: {"balthasar-distil":["balthasar-embed"],
      "balthasar":["balthasar-ipc","balthasar-model","balthasar-store"]},
    tests: 1785, strip: "balthasar-"
  },
  melchior: {
    kind: "module",
    nodes: {"answering":{"loc":1554},"asking":{"loc":449},"briefing":{"loc":186},"directory":{"loc":3051},
      "events":{"loc":1898},"framing":{"loc":362},"identity":{"loc":230},"inherited":{"loc":78},
      "kin":{"loc":197},"mind":{"loc":18780},"noted":{"loc":235},"places":{"loc":419},
      "policy":{"loc":611},"scratch":{"loc":223},"serving":{"loc":1708},"verbs":{"loc":3495},
      "wire":{"loc":584}},
    deps: {"answering":["directory","framing","identity","inherited","mind","policy","verbs","wire"],
      "asking":["framing","identity","noted","places","wire"],
      "briefing":["directory","policy","verbs"],
      "directory":["asking","identity","inherited","noted","places","policy","wire"],"events":[],
      "framing":[],"identity":[],"inherited":[],"kin":[],
      "mind":["directory","events","framing","inherited","noted","places","verbs","wire"],
      "noted":[],"places":[],"policy":["inherited"],"scratch":[],
      "serving":["answering","asking","directory","framing","identity","inherited","kin","noted","places","policy","wire"],
      "verbs":["asking","directory","identity","places","policy","wire"],"wire":[]},
    dev: {},
    tests: 924, strip: ""
  },
  casper: {
    kind: "module",
    nodes: {"acknowledged":{"loc":144},"calling":{"loc":809},"cancelling":{"loc":153},
      "events":{"loc":2240},"files":{"loc":4309},"framing":{"loc":284},"grammars":{"loc":776},
      "highlight":{"loc":301},"images":{"loc":150},"indexing":{"loc":1294},"jail":{"loc":3550},
      "listing":{"loc":738},"lua":{"loc":3560},"mcp":{"loc":332},"mcp_client":{"loc":9196},
      "noted":{"loc":258},"paint":{"loc":436},"plugins":{"loc":252},"pty":{"loc":1206},
      "running":{"loc":572},"scratch":{"loc":150},"scripting":{"loc":1715},"seeking":{"loc":1148},
      "serving":{"loc":859},"setup":{"loc":337},"shelf":{"loc":146},"source":{"loc":285},
      "source_worker":{"loc":56},"surface":{"loc":835},"testing":{"loc":56},"tied":{"loc":461},
      "tools":{"loc":829},"web":{"loc":537},"wire":{"loc":286},"workflows":{"loc":1403}},
    deps: {"acknowledged":[],
      "calling":["acknowledged","events","files","highlight","images","jail","lua","mcp_client","noted","scripting","serving","setup","tools"],
      "cancelling":[],"events":[],"files":["framing","jail","running","source","tools","wire"],
      "framing":[],"grammars":["noted","running","shelf","wire"],"highlight":["paint"],
      "images":["running"],"indexing":["grammars","lua","running","shelf"],"jail":["noted"],
      "listing":["paint","running"],
      "lua":["highlight","images","listing","mcp_client","noted","paint","running","seeking","serving","source","tools","web"],
      "mcp":["calling","jail","mcp_client","tools","wire"],
      "mcp_client":["cancelling","events","files","images","jail","noted","plugins","tools","web","wire"],
      "noted":[],"paint":[],"plugins":[],"pty":["paint","tools"],
      "running":["cancelling","jail","noted"],"scratch":[],"scripting":[],
      "seeking":["listing","paint","running"],"serving":["events","framing","wire"],
      "setup":["lua","plugins"],"shelf":[],"source":["jail","running","source_worker","wire"],
      "source_worker":["jail"],"surface":["lua","noted","pty","tools"],"testing":[],"tied":[],
      "tools":["images","paint","running","source"],"web":["jail"],"wire":[],"workflows":["jail"]},
    dev: {},
    tests: 818, strip: ""
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
