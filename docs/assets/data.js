/* ------------------------------------------------------------------- shared drawings ------- */
/* Every page loads this; each draws only the plates it declared a container for. */
const plot = (id, spec) => { const h = document.getElementById(id); if (h) graph(h, spec); };
const flow = (id, spec) => { const h = document.getElementById(id); if (h) lanes(h, spec); };

/* ------------------------------------------------------------------------ the drawings ---- */
const B = (id, x, y, label, sub, kind, w = 150, h = 46) => ({ id, x, y, w, h, label, sub, kind });

plot("d-map", {
  w: 860, h: 330,
  nodes: [
    B("p",  355, 6,   "person", null, "ext", 150, 34),
    B("m",  330, 96,  "magi", "turns · screen · ledger", "hub", 200, 52),
    B("c",  40,  216, "casper", "tools · surfaces", null),
    B("e",  355, 216, "melchior", "the model · agents", null),
    B("b",  670, 216, "balthasar", "memory", null),
    B("os", 40,  292, "files · commands", null, "ext", 150, 30),
    B("api",355, 292, "provider", null, "ext", 150, 30),
    B("st", 670, 292, "project.db", null, "ext", 150, 30),
  ],
  edges: [
    { from: "p", to: "m" },
    { from: "m", to: "c", label: "argv + stdin|one exec per call", hot: true },
    { from: "m", to: "e", label: "pipe|one json per line", hot: true },
    { from: "m", to: "b", label: "socket|length-prefixed", hot: true },
    { from: "c", to: "os", dash: true },
    { from: "e", to: "api", dash: true, label: "https" },
    { from: "b", to: "st", dash: true },
  ],
});

plot("d-wire", {
  w: 860, h: 330,
  nodes: [
    B("own",  20,  10,  "magi's own wire", "front end ↔ session|session ↔ its tool peers", "hub", 250, 74),
    B("fam",  20,  132, "the family wire", "magi ↔ casper · melchior · balthasar", null, 250, 74),
    B("cb",   340, 22,  "CBOR", "always", null, 140, 50),
    B("js",   340, 144, "JSON", "by default", null, 140, 50),
    B("cb2",  340, 216, "CBOR", "asked for on a one-shot,|read from the first byte on a socket", null, 140, 62),
    B("fr",   560, 78,  "4-byte big-endian length", "then the body", null, 280, 50),
    B("sh",   560, 168, "{call, args} → {ok, family, n, result}", "or {event: …}, which nobody answers", null, 280, 62),
  ],
  edges: [
    { from: "own", to: "cb", hot: true },
    { from: "fam", to: "js" },
    { from: "fam", to: "cb2", hot: true },
    { from: "cb", to: "fr" },
    { from: "js", to: "fr" },
    { from: "cb2", to: "sh" },
    { from: "js", to: "sh" },
  ],
});

flow("d-turn", {
  laneW: 152, step: 29,
  lanes: [
    { label: "person" }, { label: "magi", hub: true },
    { label: "balthasar" }, { label: "melchior" }, { label: "casper" },
  ],
  steps: [
    { from: 0, to: 1, label: "types a line" },
    { from: 1, to: 2, label: "observe" },
    { from: 1, to: 2, label: "recall — on a clock" },
    { from: 2, to: 1, label: "memories + confidence", back: true },
    { at: 1, note: "only what clears the floor" },
    { from: 1, to: 3, label: "ask + tool declarations" },
    { from: 3, to: 1, label: "it wants `shell`", back: true },
    { at: 1, note: "the ledger decides" },
    { from: 1, to: 4, label: "run shell", hot: true },
    { from: 4, to: 1, label: "output, capped", back: true },
    { from: 1, to: 3, label: "ask again, with the result" },
    { from: 3, to: 1, label: "the answer", back: true },
    { from: 1, to: 2, label: "outcome — did it help" },
    { from: 1, to: 0, label: "drawn" },
  ],
});

plot("d-tools", {
  w: 800, h: 300,
  nodes: [
    B("lua", 20,  16,  "tools.lua", "name · needs · run", null, 190),
    B("cas", 20,  92,  "casper tools", "13, asked for at start", null, 190),
    B("bin", 20,  168, "builtin", "read · write · edit", null, 190),
    B("reg", 300, 84,  "the registry", "one name, one entry", "hub", 180, 62),
    B("dec", 560, 16,  "declarations", "→ the model", null, 210, 40),
    B("t1",  560, 74,  "casper run <tool>", null, null, 210, 34),
    B("t2",  560, 118, "any program on PATH", null, null, 210, 34),
    B("t3",  560, 162, "lua, in the vm", null, null, 210, 34),
    B("t4",  560, 206, "builtin, in magi", null, null, 210, 34),
  ],
  edges: [
    { from: "lua", to: "reg" }, { from: "cas", to: "reg" }, { from: "bin", to: "reg" },
    { from: "reg", to: "dec" },
    { from: "reg", to: "t1", label: "a call" }, { from: "reg", to: "t2" },
    { from: "reg", to: "t3" }, { from: "reg", to: "t4" },
  ],
});

flow("d-screen", {
  laneW: 220, step: 30,
  lanes: [{ label: "magi · owns the terminal", hub: true }, { label: "casper · the surface" }],
  steps: [
    { from: 0, to: 1, label: "start — you have 14 rows" },
    { from: 1, to: 0, label: "a frame, drawn in roles", back: true },
    { from: 0, to: 1, label: "a key, a click, a resize" },
    { at: 0, note: "…repeats until it ends" },
    { from: 1, to: 0, label: "done, and what to record", back: true },
    { at: 0, note: "the rows go back" },
  ],
});

plot("d-mem", {
  w: 820, h: 260,
  nodes: [
    B("com", 20,  16,  "an entry is committed", null, null, 200, 40),
    B("q",   20,  74,  "queued, not awaited", null, null, 200, 40),
    B("st",  330, 96,  "the store", "sqlite, in the project", "hub", 160, 56),
    B("rec", 610, 16,  "recall", "on a deadline", null, 190, 44),
    B("flo", 610, 76,  "the floor", "weak matches dropped", null, 190, 44),
    B("win", 610, 136, "a framed preface", "in the window", null, 190, 44),
    B("out", 330, 196, "used · outcome", "did it help", null, 160, 44),
  ],
  edges: [
    { from: "com", to: "q" },
    { from: "q", to: "st", label: "observe →", hot: true },
    { from: "st", to: "rec", label: "← recall", hot: true },
    { from: "rec", to: "flo" }, { from: "flo", to: "win" },
    { from: "win", to: "out", bend: 60 },
    { from: "out", to: "st" },
  ],
});

plot("d-scope", {
  w: 780, h: 330,
  nodes: [
    B("cwd", 300, 8,   "the working directory", null, "ext", 190, 34),
    B("q1",  270, 62,  "nobody owns this?", "/tmp · above $HOME · /", "ask", 250, 62),
    B("st",  560, 62,  "stop.", "it is its own scope", "stop", 200, 62),
    B("q2",  270, 148, "a store somebody made?", "balthasar init", "ask", 250, 62),
    B("h1",  560, 148, "that is the scope", null, null, 200, 44),
    B("q3",  270, 234, "a checkout, and not $HOME?", ".git", "ask", 250, 62),
    B("h2",  560, 234, "the repository is the scope", "worktrees share it", null, 200, 50),
    B("up",  30,  148, "walk up|one level", null, null, 170, 50),
  ],
  edges: [
    { from: "cwd", to: "q1" },
    { from: "q1", to: "st", label: "yes", hot: true },
    { from: "q1", to: "q2", label: "no" },
    { from: "q2", to: "h1", label: "yes" },
    { from: "q2", to: "q3", label: "no" },
    { from: "q3", to: "h2", label: "yes" },
    { from: "q3", to: "up", label: "no" },
    { from: "up", to: "q1", bend: -70 },
  ],
});

plot("d-sess", {
  w: 800, h: 260,
  nodes: [
    B("a1", 40,  30,  "main", "alpha-rho", "hub", 150, 46),
    B("a2", 240, 30,  "main", "iota-mu", null, 150, 46),
    B("s1", 20,  150, "subagent", null, null, 130, 40),
    B("s2", 170, 150, "subagent", null, null, 130, 40),
    B("pa", 10,  6,   "project A", null, "ext", 400, 220),
    B("b1", 500, 30,  "main", "tau-nu", null, 150, 46),
    B("pb", 470, 6,   "project B", null, "ext", 220, 220),
  ],
  edges: [
    { from: "a1", to: "a2", label: "may talk", both: true },
    { from: "a1", to: "s1" }, { from: "a1", to: "s2" },
    { from: "pa", to: "pb", label: "never, at any setting", hot: true },
  ],
});

plot("d-life", {
  w: 820, h: 250,
  nodes: [
    B("m",  310, 12,  "magi", "one window", "hub", 200, 52),
    B("b",  20,  120, "balthasar", "lives as long as the window", null, 220, 50),
    B("e",  300, 120, "melchior", "lives as long as the window", null, 220, 50),
    B("c",  580, 120, "casper", "lives for one call", null, 220, 50),
    B("x1", 20,  200, "killed on exit — or by the kernel", null, "stop", 220, 36),
    B("x2", 300, 200, "the pipe closes", null, "ext", 220, 36),
    B("x3", 580, 200, "it returns", null, "ext", 220, 36),
  ],
  edges: [
    { from: "m", to: "b", label: "starts|holds a socket" },
    { from: "m", to: "e", label: "starts|holds a pipe" },
    { from: "m", to: "c", label: "starts|once per call" },
    { from: "b", to: "x1", hot: true }, { from: "e", to: "x2" }, { from: "c", to: "x3" },
  ],
});

plot("d-permit", {
  w: 800, h: 340,
  nodes: [
    B("a",  290, 6,   "a tool wants to act", null, "ext", 220, 32),
    B("n",  290, 52,  "normalise the path", "or split the command", null, 220, 46),
    B("w",  280, 116, "inside the session root?", "only if confine is on", "ask", 240, 60),
    B("g1", 280, 194, "already granted?", "config, then this session", "ask", 240, 60),
    B("q",  280, 272, "anyone at the keyboard?", null, "ask", 240, 52),
    B("ok", 580, 194, "it runs", null, null, 190, 40),
    B("no", 580, 116, "refused.", "no prompt, no appeal", "stop", 190, 50),
    B("no2",580, 272, "refused, and told why", null, "stop", 190, 40),
    B("ask",30,  272, "ask · record it", "at the width given", null, 200, 46),
  ],
  edges: [
    { from: "a", to: "n" }, { from: "n", to: "w" },
    { from: "w", to: "no", label: "no", hot: true },
    { from: "w", to: "g1", label: "yes" },
    { from: "g1", to: "ok", label: "yes" },
    { from: "g1", to: "q", label: "no" },
    { from: "q", to: "no2", label: "no", hot: true },
    { from: "q", to: "ask", label: "yes" },
    { from: "ask", to: "ok", bend: -110 },
  ],
});

plot("d-config", {
  w: 820, h: 300,
  nodes: [
    B("i",  20,  16,  "init.lua", "the only entry point", "hub", 200, 50),
    B("l",  20,  92,  "what it names", "clients · tools", null, 200, 44),
    B("s",  20,  164, "remember", "confine · allow · trusted", null, 200, 50),
    B("p",  300, 164, ".magi.lua", "arrives with a checkout", null, 190, 50),
    B("ch", 550, 152, "did it change|a privileged one?", null, "ask", 250, 74),
    B("f",  550, 250, "fatal. refused by name.", null, "stop", 250, 38),
    B("r",  550, 60,  "kept", "settings · a model chosen", null, 250, 44),
    B("d",  550, 8,   "tools it declared are dropped", null, "ext", 250, 34),
  ],
  edges: [
    { from: "i", to: "l" }, { from: "l", to: "s" }, { from: "s", to: "p" },
    { from: "p", to: "ch" },
    { from: "ch", to: "f", label: "yes", hot: true },
    { from: "ch", to: "r", label: "no" },
    { from: "r", to: "d" },
  ],
});

