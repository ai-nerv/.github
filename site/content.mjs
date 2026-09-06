// Every page of the site, and what is on it.
//
// One file so that the shape of the whole thing is readable at once. `at` is where a page is
// written, `nav` is what the sidebar calls it, and `body` is everything under the lede.

export const SECTIONS = [
  { key: "home", name: "overview", home: "index.html" },
  { key: "arch", name: "architecture", home: "architecture/index.html" },
  { key: "prog", name: "the four", home: "programs/magi.html" },
  { key: "guide", name: "guides", home: "guides/install.html" },
  { key: "ref", name: "reference", home: "reference/wire.html" },
];

/** A drawing, with the plate furniture around it. */
const plate = (id, name, says) => `      <div class="plate">
        <header><b>${name}</b><span>${says}</span></header>
        <div class="body"><div class="dia" id="${id}"></div></div>
      </div>`;

/** A table from rows of [left, right]. */
const table = (head, rows) => `      <table>
        <thead><tr>${head.map((h) => `<th>${h}</th>`).join("")}</tr></thead>
        <tbody>
${rows.map((r) => `          <tr>${r.map((c, i) => `<td${i ? ' class="wrap-ok"' : ""}>${c}</td>`).join("")}</tr>`).join("\n")}
        </tbody>
      </table>`;

const note = (text) => `      <div class="note">${text}</div>`;

export const PAGES = [];

// ------------------------------------------------------------------------------- overview ----
PAGES.push({
  at: "index.html",
  section: "home",
  nav: "overview",
  title: "Four programs, no shared code",
  blurb:
    "magi is a coding agent for Linux. It is one of four programs that talk over argv, a pipe " +
    "and a socket — and share not one line of code. This is how they fit together.",
  body: `
      <div class="cards">
        <div class="card">
          <h4>magi</h4><div class="role">the harness</div>
          <p>The one you run. Holds the conversation, the screen, the journal and the permission
          ledger, and reaches the other three for everything else.</p>
          <a href="programs/magi.html">what it owns →</a>
        </div>
        <div class="card">
          <h4>casper</h4><div class="role">tools · surfaces</div>
          <p>Thirteen tools and the screen they draw on. One process per call. It knows nothing
          about models, turns or transcripts.</p>
          <a href="programs/casper.html">what it owns →</a>
        </div>
        <div class="card">
          <h4>melchior</h4><div class="role">the model · other agents</div>
          <p>Which providers exist, what credential each takes, and how one session reaches
          another. It does not know what a harness is.</p>
          <a href="programs/melchior.html">what it owns →</a>
        </div>
        <div class="card">
          <h4>balthasar</h4><div class="role">memory</div>
          <p>What is in the window now, what happened this session, what is true, and how things
          are done here. Its own store, its own process.</p>
          <a href="programs/balthasar.html">what it owns →</a>
        </div>
      </div>

      <h2 id="map">How they connect</h2>
      <p>Nothing in the ring talks to anything but magi, and every arrow is a process boundary
      somebody crosses on purpose.</p>
${plate("d-map", "plate 01", "magi is the only program you run")}

      <h2 id="start">Start here</h2>
${table(["", ""], [
  ['<a href="guides/install.html">install</a>', "get the binaries, and check what a session here would be made of"],
  ['<a href="architecture/index.html">the map</a>', "every edge, what travels on it, and what happens when one end is missing"],
  ['<a href="guides/tools.html">write a tool</a>', "four fields of Lua, read at start-up — nothing is compiled in"],
  ['<a href="reference/wire.html">the wire</a>', "the shapes, the encodings, and the framing, in enough detail to write a peer"],
])}

      <h2 id="rules">What holds it together</h2>
      <ul class="plain">
        <li><b>No shared code, in either direction.</b> balthasar's Rust never parses magi's types
        and melchior does not know what a harness is. What crosses is data each side parses into
        its own shapes — so any one of them can be replaced by something that speaks the same
        words.</li>
        <li><b>Every sibling is optional.</b> magi with nothing else installed is a session with
        three builtin tools, no model and no memory — which runs, and says so.</li>
        <li><b>Linux only, and that is a decision.</b> Peer identity comes from
        <code>SO_PEERCRED</code>, which means there is no handshake token to design, issue or
        leak.</li>
        <li><b>One shape, two encodings.</b> JSON for anything a person might read; CBOR for a
        caller that is only going to parse it. Nothing is negotiated — a body says which it is in
        its first byte.</li>
      </ul>
${note("<b>magi is the only command.</b> It starts a balthasar and a melchior for each session and ends both, and runs casper once per tool call. There is no daemon to launch and no unit file to install.")}
`,
});

// --------------------------------------------------------------------------- architecture ----
PAGES.push({
  at: "architecture/index.html",
  section: "arch",
  nav: "the map",
  title: "The map",
  blurb:
    "Four programs, three transports, and one program a person actually runs. Every edge below " +
    "is a process boundary, and every one of them can be absent.",
  body: `
${plate("d-map", "plate 01", "nothing in the ring talks to anything but magi")}

      <h2 id="edges">Every edge</h2>
${table(["edge", "who starts it", "carries", "absent?"], [
  ["magi → casper", "magi, once per tool call", "the call as argv and stdin; the result on stdout", "three builtin tools remain: <code>read</code>, <code>write</code>, <code>edit</code>"],
  ["magi → melchior", "magi, once per session", "what the session is doing, up; what the model said and who is calling, down", "no model and no siblings — the session runs and says so"],
  ["magi → balthasar", "magi, once per session", "every entry out; recalled memory and prior sessions back", "the journal on disk becomes the record instead"],
  ["session → session", "either, through melchior", "messages, questions and answers between agents", "a session with no siblings, which is the ordinary case"],
  ["front end → session", "the front end", "what was typed, up; everything to draw, down", "the turn keeps running — close the window and come back"],
])}

      <h2 id="why">Why separate processes</h2>
      <p>Three things fall out of the split that do not fall out of modules in one binary.</p>
      <ul class="plain">
        <li><b>A crash is contained.</b> A tool that segfaults takes down one process that was
        going to exit anyway. The turn sees a failed result, not a dead harness.</li>
        <li><b>The kernel does the identifying.</b> <code>SO_PEERCRED</code> names the program on
        the other end of a socket, so there is no token to issue and none to leak.</li>
        <li><b>The boundary is checkable.</b> A gate on the merge path refuses any file in a
        sibling that names a harness — the separation is enforced, not merely intended.</li>
      </ul>
${note("<b>A second implementation is what keeps a protocol honest.</b> magi ships a second tool peer written in Lua, deliberately unlike the first — a different language, a different lifecycle, and one thing it cannot do at all. A protocol with one implementation is a function call with extra steps.")}
`,
});

PAGES.push({
  at: "architecture/wire.html",
  section: "arch",
  nav: "the wire",
  title: "Two protocols",
  blurb:
    "magi's own wire is CBOR. The family's speaks JSON and CBOR both, and nothing is negotiated " +
    "— a body says which encoding it is in its first byte.",
  body: `
${plate("d-wire", "plate 02", "two protocols, three transports, two encodings")}

      <h2 id="two">Which wire is which</h2>
${table(["wire", "between", "encoding"], [
  ["magi's own", "a front end and its session, and a session and its own tool peers", "<b>CBOR</b>, always, inside an envelope carrying a protocol version"],
  ["the family", "magi and casper, melchior, balthasar — and sessions with each other", "<b>JSON</b> by default, <b>CBOR</b> on request; the reply comes back in whichever the call arrived in"],
])}
      <p>The framing is the same on both: a big-endian <code>u32</code> byte count, then that many
      bytes. Self-delimiting, so a peer that dies mid-frame is caught at the length rather than
      misparsed deeper in.</p>

      <h2 id="shapes">Two shapes</h2>
      <p>A <b>call</b> expects an answer. An <b>event</b> does not, and nothing ever replies to
      one. The difference is whether anybody is waiting.</p>
      <pre><span class="c">a call, and its reply</span>
→ {"call":"recall","args":["how do we run the tests"]}
← {"ok":true,<span class="a">"family"</span>:1,"n":2,"result":[ … ]}

<span class="c">an event. nobody replies.</span>
→ {"event":"doing","busy":true,"working_for":7,"waiting":0}</pre>

      <h2 id="fields">The reply, field by field</h2>
${table(["field", "meaning"], [
  ["ok", "whether the call was answered. A refusal is <code>false</code> with a zero exit status."],
  ["family", "which revision of the wire this reply is written in. A <i>newer</i> one is refused by name; an older one is not."],
  ["n", "how many values came back."],
  ["result", "the values, <b>always a list</b>. A client that unpacks reads a bare-value server as having returned nothing at all, so the bug presents as an empty memory rather than as an error."],
  ["error", "why not, when <code>ok</code> is false."],
  ["fault", "which kind of no. Its absence means <code>refused</code> — the answer that costs a feature rather than a turn."],
])}

      <h2 id="encodings">Asking for CBOR</h2>
      <p>Every one-shot door takes <code>--cbor</code>; every socket answers in whatever it was
      asked in. The three siblings agree byte for byte.</p>
      <pre>$ casper tools --cbor | xxd | head -1
00000000: <span class="a">a4 62 6f 6b f5 66 66 61 6d 69 6c 79 01</span> 61 6e 01  <span class="c">{ok: true, family: 1, n: 1, …}</span>

$ balthasar needs --cbor | xxd | head -1
00000000: <span class="a">a4 62 6f 6b f5 66 66 61 6d 69 6c 79 01</span> 61 6e 05  <span class="c">the same prefix</span></pre>
${note("<b>Nothing is negotiated.</b> JSON's top level here is an object or an array, so it begins <code>{</code> or <code>[</code>. CBOR's is a map or an array, whose first byte is <code>0x80</code>–<code>0xBF</code>. The ranges do not overlap, so reading the encoding off the body is a reading rather than a guess — and a peer that has never heard of CBOR is unaffected.")}

      <h2 id="errors">Refusals, and the other kind</h2>
      <p>A refused verb is <code>{\"ok\":false,…}</code> with <b>exit status zero</b>. A real error
      arriving as “exited 1” is indistinguishable from the binary being missing, and the two
      need different responses: one is a bug to report, the other is a sibling to carry on
      without.</p>
${table(["fault", "means", "the caller should"], [
  ["refused", "the verb was declined", "carry on without that feature"],
  ["unavailable", "nothing answered — no socket, a dead socket, a connection that died", "carry on without the sibling"],
  ["failed", "the write did not land", "not assume what it handed over was recorded"],
  ["malformed", "the reply was not the shape the family agreed", "report it — this is a bug, not a condition"],
])}
`,
});

PAGES.push({
  at: "architecture/turn.html",
  section: "arch",
  nav: "a turn",
  title: "A turn, end to end",
  blurb: "One line typed, one answer back. Each column is a separate process, and each hop can fail.",
  body: `
${plate("d-turn", "plate 03", "fourteen hops, four processes")}

      <h2 id="clocks">What is on a clock, and what is not</h2>
${table(["hop", "clock", "if it fails"], [
  ["recall", "yes — a short deadline", "the turn proceeds with nothing recalled. Memory is never on the critical path."],
  ["observe", "no — queued, never awaited", "the entry is still in the window; only the durable record is lost."],
  ["ask", "no — a turn takes as long as it takes", "there is no answer, and the session says so."],
  ["a tool call", "per tool", "the failure is handed back to the model as the result, not raised."],
  ["outcome", "no", "balthasar learns nothing from this turn. Nothing else changes."],
])}

      <h2 id="ledger">The model never reaches anything</h2>
      <p>It emits a request naming a tool. magi decides whether it may run, and magi is the one
      that runs it. Nothing the model says becomes an action without passing the ledger — see
      <a href="../guides/permissions.html">what may run</a>.</p>

      <h2 id="window">What the model is actually sent</h2>
      <p>Not the transcript verbatim. A turn assembles, in order:</p>
      <ul class="plain">
        <li>the system message — what magi is, plus this session's own facts: directory,
        platform, what is installed.</li>
        <li>every tool declaration the registry holds, as a schema the model can call.</li>
        <li><b>a framed preface</b>, when balthasar recalled anything that cleared the floor. One
        user message that says what it is — never slipped in as though the conversation had
        contained it.</li>
        <li>the conversation, capped. Output from a tool is bounded before it ever lands here.</li>
      </ul>
${note("<b>A recall that found only weak matches still says so.</b> The frame line is written first, because a hedged recall that is presented as certainty is worse than no recall at all.")}
`,
});

PAGES.push({
  at: "architecture/lifetime.html",
  section: "arch",
  nav: "lifetimes",
  title: "What starts what",
  blurb:
    "magi convenes its siblings rather than finding them running. One balthasar per window, " +
    "not one per project — and both mechanisms that end it.",
  body: `
${plate("d-life", "plate 09", "one per window, and what ends each")}

      <h2 id="one">One per window, not one per project</h2>
      <p>A session that waited for somebody else to have launched a memory layer would record
      sometimes and not others. So it starts its own, named after the session. Two windows in a
      project therefore get one each and neither can take the other's down — they meet in the
      project's store file rather than in a process.</p>

      <h2 id="ends">What ends each</h2>
${table(["sibling", "how magi starts it", "what ends it"], [
  ["balthasar", "<code>serve --instance &lt;session&gt; --tied &lt;pid&gt;</code>, on a socket", "killed on the way out, <b>and</b> by the kernel if that never runs"],
  ["melchior", "<code>serve --project &lt;p&gt;</code>, on a pipe", "magi closes the pipe; the read returns nothing and it leaves"],
  ["casper", "<code>run &lt;tool&gt;</code>, once per call", "nothing to end — it exits on its own, every call"],
])}

      <h2 id="twice">Why balthasar needs it twice</h2>
      <p>A cleanup on the way out covers the exits that <i>have</i> a way out. A panic, an OOM and
      a <code>kill -9</code> run nothing at all inside magi, and those are exactly the exits that
      would strand a memory layer. So the kernel holds the second copy of the rule: magi names its
      own process id at spawn, and balthasar asks to be signalled when that process dies.</p>
${table(["exit", "what ends balthasar"], [
  ["ordinary", "magi kills it, then unlinks the socket — in that order, because after the wait the process is gone and the name cannot still be answering"],
  ["panic · OOM · kill -9", "the kernel signals it, because magi runs nothing"],
  ["magi died before it started", "it notices its parent is not the one that named itself, and leaves"],
  ["started by hand, no parent named", "nothing — which is what a terminal or a unit file wants"],
])}
${note("<b>Clearing a leftover socket is not the same as ending a process.</b> A sweep removes a <i>name</i>, and it keeps any socket that still answers — correctly, since a live sibling's socket looks exactly like a dead one's. An orphan answers. So the name survives and so does the process behind it, which is why the kernel has to be what enforces this.")}
`,
});

PAGES.push({
  at: "architecture/inside.html",
  section: "arch",
  nav: "inside each",
  title: "Inside each program",
  blurb:
    "The same question one level down: what depends on what, within a single repository. " +
    "Read from the repositories rather than drawn by hand.",
  body: `
      <p>Foundations at the bottom, dependents above; an arrow points at what a thing needs. Box
      width follows line count, so the shape of each program is its real shape. Hover anything to
      light its edges. Dashed edges are test-only.</p>

      <div class="unit-head"><h4>magi</h4><span class="role">harness — ui, host, turns, tools</span>
        <span class="meta" id="meta-magi"></span></div>
      <div class="graph" id="g-magi"></div>
      <div class="unit-head"><h4>balthasar</h4><span class="role">memory, in its own process</span>
        <span class="meta" id="meta-balthasar"></span></div>
      <div class="graph" id="g-balthasar"></div>
      <div class="unit-head"><h4>melchior</h4><span class="role">the model, and other agents</span>
        <span class="meta" id="meta-melchior"></span></div>
      <div class="graph" id="g-melchior"></div>
      <div class="unit-head"><h4>casper</h4><span class="role">tools, and the screen they draw on</span>
        <span class="meta" id="meta-casper"></span></div>
      <div class="graph" id="g-casper"></div>

      <h2 id="gates">What holds the shape</h2>
      <p>Every one of these runs on the way to <code>main</code>, in all four repositories.</p>
${table(["gate", "what it forbids"], [
  ["no cycles", "two top-level modules that depend on each other. This is what a reachability check cannot catch: a cycle is maximally reachable."],
  ["one wire", "a second way of saying the same thing across a boundary"],
  ["independence", "any file in a sibling naming a harness"],
  ["800 lines", "a source file bigger than one sitting"],
  ["reachable", "a file nobody declares — not a compile error, not a warning, and never run"],
  ["hermetic", "anything left behind in the temporary directory, checked under one of its own"],
  ["no model needed", "a memory test that only passes with a key and a network"],
  ["no dead weight", "a declared dependency the code does not use"],
])}
`,
});

// ------------------------------------------------------------------------------ the four -----
PAGES.push({
  at: "programs/magi.html",
  section: "prog",
  nav: "magi",
  title: "magi",
  blurb:
    "The harness. The conversation, the screen, the journal and the permission ledger — and the " +
    "only one of the four a person runs.",
  body: `
      <h2 id="owns">What it owns</h2>
      <ul class="plain">
        <li><b>The turn loop.</b> Assembling what the model is sent, reading what it wants, and
        deciding what happens next.</li>
        <li><b>The screen.</b> Differential rendering into native scrollback, live streaming, and
        an editor-grade prompt. Close the window and the turn keeps running.</li>
        <li><b>The registry.</b> One name, one entry — whatever the tool's transport.</li>
        <li><b>The permission ledger.</b> Nothing the model asks for becomes an action without
        passing it.</li>
        <li><b>The session.</b> Its id, its journal, and which balthasar holds its transcript.</li>
      </ul>

      <h2 id="not">What it does not own</h2>
      <p>Which endpoint a model lives at, what credential it takes, what a 429 means — melchior's.
      What a tool does — casper's. What is worth remembering — balthasar's. A config here that
      held an opinion about any of them would be a second catalog to keep in step.</p>

      <h2 id="shape">The shape of it</h2>
      <div class="unit-head"><h4>magi</h4><span class="role">eleven crates</span>
        <span class="meta" id="meta-magi"></span></div>
      <div class="graph" id="g-magi"></div>

      <h2 id="cli">At a terminal</h2>
      <pre>magi                     <span class="c">a session in this directory</span>
magi -p "…"              <span class="c">one prompt, one answer, no terminal</span>
magi --resume            <span class="c">carry on from this directory's most recent session</span>
magi doctor              <span class="c">what a session here would be made of, without starting one</span>
magi tools               <span class="c">every tool the model can call, and how each is reached</span>
magi models              <span class="c">what melchior says this machine could talk to</span></pre>
${note("<b><code>magi doctor</code> never fails.</b> A configuration that will not load is reported rather than exited over — the whole point is to be usable on the machine where something is wrong.")}

      <h2 id="daemon">There is no daemon</h2>
      <p>There was. <code>magi</code> spawned <code>magi host</code> as a background child that
      owned the journal and the socket, and a UI quitting was a <i>detach</i>. Two problems
      followed. The daemon's socket was named after the working directory, so the second
      <code>magi</code> in a project found the first one's session. And nothing ever ended one, so
      a week of work left a process per project.</p>
      <p>The session is the process now. Returning from <code>magi</code> is the end of it, with
      no socket, no pid file and no second process.</p>
`,
});

PAGES.push({
  at: "programs/casper.html",
  section: "prog",
  nav: "casper",
  title: "casper",
  blurb:
    "The tools a coding agent runs, and the screen they draw on. One process per call, and it " +
    "knows nothing about models, turns or transcripts.",
  body: `
      <h2 id="tools">What it offers</h2>
${table(["tools", "for"], [
  ["<code>cat</code> <code>ls</code> <code>find</code> <code>grep</code> <code>patch</code>", "reading the tree"],
  ["<code>shell</code> <code>pwd</code>", "running a command, and remembering where it ran"],
  ["<code>screen</code>", "an interactive program — a pager, an editor, <code>htop</code>, <code>git add -p</code> — in rows on the screen"],
  ["<code>hexe</code> <code>oslo</code> <code>session</code>", "asking the multiplexer, the shell, or the harness about themselves"],
  ["<code>dino</code> <code>birdy</code>", "two games, because a surface that can draw a game can draw anything"],
])}
      <p>Every one is declared in <code>config/tools.lua</code>, in Lua, and nothing about them is
      compiled in. A tool of your own goes in the same file — see
      <a href="../guides/tools.html">writing a tool</a>.</p>

      <h2 id="exec">Why a spawn and not a socket</h2>
      <p>casper's job is running programs, and <b>a socket that runs commands is a remote shell
      wearing a friendly name</b>. The spawn link carries the trust instead: a parent that can
      spawn casper could have run the command itself, so nothing is granted by handing it over.
      One exec per call.</p>

      <h2 id="cli">At a terminal</h2>
      <pre>casper tools                 <span class="c">every tool it offers, as declarations a harness can register</span>
casper run &lt;tool&gt;            <span class="c">run one; the call arrives as JSON on stdin</span>
casper surface &lt;tool&gt;        <span class="c">hold rows on the harness's screen and draw into them</span>
casper verbs                 <span class="c">what its socket answers</span>

casper tools --cbor          <span class="c">the same reply, as bytes</span></pre>

      <h2 id="shape">The shape of it</h2>
      <div class="unit-head"><h4>casper</h4><span class="role">one crate, by module</span>
        <span class="meta" id="meta-casper"></span></div>
      <div class="graph" id="g-casper"></div>
`,
});

PAGES.push({
  at: "programs/melchior.html",
  section: "prog",
  nav: "melchior",
  title: "melchior",
  blurb:
    "The model, and the other agents on this machine: who is running, how each stands to this " +
    "one, what it may say to them, and what it may not.",
  body: `
      <h2 id="owns">What it owns</h2>
      <ul class="plain">
        <li><b>The catalog.</b> Which providers exist, which credential each takes, what protocol
        each speaks, and what this machine could therefore talk to.</li>
        <li><b>Naming.</b> This session's name, in the form other sessions see:
        <code>project/role/id</code>. It names the session because it can see the namespace and
        magi cannot.</li>
        <li><b>The walls.</b> Which session may reach which — see
        <a href="../guides/sessions.html">sessions</a>.</li>
      </ul>

      <h2 id="dir">Where sessions live</h2>
      <pre>$XDG_RUNTIME_DIR/melchior/
  myproject/                 <span class="c">one directory per project</span>
    alpha-rho                <span class="c">a socket, named by the id and nothing else</span>
    iota-mu
    iota-mu.parent           <span class="c">"alpha-rho": who started it</span></pre>
      <p>There is no server for the layer as a whole. Every session binds its own socket and
      answers for itself, so <b>the directory is the registry</b> — a process that died did not get
      to remove itself from a list, and a socket nobody answers is discovered on the first call
      rather than trusted.</p>

      <h2 id="cli">At a terminal</h2>
      <pre>melchior models              <span class="c">what this machine could talk to</span>
melchior ask                 <span class="c">run a turn; an Ask on stdin</span>
melchior needs               <span class="c">what a coordinator may tell it</span>
melchior configure           <span class="c">take configuration, as Lua on stdin</span>
melchior serve               <span class="c">bind this session's socket and answer for it</span>

melchior models --cbor       <span class="c">any of them, as bytes</span></pre>

      <h2 id="shape">The shape of it</h2>
      <div class="unit-head"><h4>melchior</h4><span class="role">one crate, by module</span>
        <span class="meta" id="meta-melchior"></span></div>
      <div class="graph" id="g-melchior"></div>
${note("<b>No verb here runs anything.</b> It sends messages, reads an inbox, and says who is listening — deliberately, and its own tests refuse a verb named <code>run</code>, <code>shell</code>, <code>exec</code> or <code>eval</code>. That is why magi can grant the agent tool in advance without a prompt.")}
`,
});

PAGES.push({
  at: "programs/balthasar.html",
  section: "prog",
  nav: "balthasar",
  title: "balthasar",
  blurb:
    "Memory for agents. Short-term and long-term in one layer, with its own store — not a " +
    "library a harness links.",
  body: `
      <h2 id="four">The four things it holds</h2>
${table(["", ""], [
  ["the window", "what is in the context right now"],
  ["the session", "what happened in this run, verbatim — the only copy of what was said"],
  ["the project", "what is true here, and how things are done"],
  ["everywhere", "what is true of you, whichever project you are in"],
])}
      <p>And the ladder between them: eight kinds of evidence and two floors, deciding what is
      allowed to climb from one level to the next.</p>

      <h2 id="cli">At a terminal</h2>
      <pre>balthasar remember "we run the tests with make test"
balthasar recall "tests" --explain
balthasar why &lt;handle&gt;            <span class="c">the evidence, not just the number</span>
balthasar decay                   <span class="c">what today's forgetting would take, before it takes it</span>
balthasar sessions                <span class="c">which runs this project has had</span>
balthasar serve                   <span class="c">listen for other programs</span></pre>

      <h2 id="store">Where a store lives</h2>
      <pre>&lt;project&gt;/balthasar/&lt;tool&gt;/project.db              <span class="c">what is true here, kept</span>
&lt;project&gt;/balthasar/&lt;tool&gt;/&lt;session&gt;/memory.db     <span class="c">that run's scratch, dies with it</span>
&lt;project&gt;/balthasar/&lt;tool&gt;/&lt;session&gt;/transcript.db
~/.local/share/balthasar/&lt;tool&gt;/global.db          <span class="c">yours, everywhere</span></pre>
      <p><b>The store lives in the project</b>, so renaming a checkout moves its memory rather than
      orphaning it. Which store a given directory gets is
      <a href="../guides/memory.html#scope">its own question</a>.</p>

      <h2 id="shape">The shape of it</h2>
      <div class="unit-head"><h4>balthasar</h4><span class="role">twelve crates</span>
        <span class="meta" id="meta-balthasar"></span></div>
      <div class="graph" id="g-balthasar"></div>
${note("<b>One store per tool.</b> A harness and a shell reaching the same daemon are two memories, and neither is opened on the chance that it might be. The kernel names the caller, so a peer reads its own memory rather than everybody's.")}
`,
});

// -------------------------------------------------------------------------------- guides -----
PAGES.push({
  at: "guides/install.html",
  section: "guide",
  nav: "install",
  title: "Install",
  blurb:
    "Binaries for x86_64 and aarch64, built on the runner from the same pinned toolchain the " +
    "gates ran under. Linux only.",
  body: `
      <h2 id="get">Get the binaries</h2>
      <pre>gh release download v0.1.0 --repo ai-nerv/magi --pattern '*-amd64.tar.gz'
tar -xzf magi-linux-amd64.tar.gz -C ~/.local/bin

<span class="c"># the siblings are separate releases, and every one of them is optional</span>
gh release download v0.1.0 --repo ai-nerv/casper    --pattern '*-amd64.tar.gz'
gh release download v0.1.0 --repo ai-nerv/melchior  --pattern '*-amd64.tar.gz'
gh release download v0.1.0 --repo ai-nerv/balthasar --pattern '*-amd64.tar.gz'</pre>

      <h2 id="what">What each one buys you</h2>
${table(["", "without it"], [
  ["magi", "nothing — this is the one you run"],
  ["casper", "a session with three builtin tools: <code>read</code>, <code>write</code>, <code>edit</code>"],
  ["melchior", "no model and no siblings. The session runs and says so."],
  ["balthasar", "a journal file instead of a store. Everything else is the same."],
])}

      <h2 id="check">Check before you start</h2>
      <pre>magi doctor</pre>
      <p>It answers everything a session decides at start-up: which configuration was read, which
      of its lines were kept, what the registry holds and where each entry came from, and whether
      the siblings actually <i>answer</i>. Asked, not looked for — a program on
      <code>$PATH</code> is not a running one, and a socket that accepts is not one that
      answers.</p>
${note("<b><code>magi</code> is the only command.</b> It starts a balthasar and a melchior for each session and ends both. <code>doctor</code> reporting <i>“balthasar installed, but not reachable: no socket to try”</i> is correct output outside a session — there is no session, so there is no socket.")}

      <h2 id="model">Choosing a model</h2>
      <p>magi holds only the name. Which endpoint it lives at and what credential it takes are
      melchior's, so ask melchior what this machine can reach:</p>
      <pre>magi models | head
<span class="c"># then, in ~/.config/magi/init.lua</span>
magi.model = "openrouter/anthropic/claude-sonnet-4.6"</pre>
      <p>A model that reports <code>ready: false</code> names the variable it wants. Set that, and
      it becomes ready — nothing else has to change.</p>

      <h2 id="build">From source</h2>
      <pre>git clone https://github.com/ai-nerv/magi &amp;&amp; cd magi
oslo make build     <span class="c"># a release binary</span>
oslo make test      <span class="c"># the suite</span>
oslo make verify    <span class="c"># the whole local gate, which is what CI runs</span>
oslo make install   <span class="c"># to ~/.local/bin, and the config to ~/.config/magi</span></pre>
${note("<b><code>make install</code> overwrites <code>~/.config/magi/init.lua</code>.</b> Keep your edits somewhere, or expect to re-apply them after every install.")}
`,
});

PAGES.push({
  at: "guides/configure.html",
  section: "guide",
  nav: "configuration",
  title: "Configuration",
  blurb:
    "Lua, and a program rather than a data file: it may probe the machine, loop and branch. " +
    "Nothing is discovered by scanning — a file the entry point does not name does not load.",
  body: `
${plate("d-config", "plate 11", "load order, and where a project file is refused")}

      <h2 id="entry">The entry point</h2>
      <pre><span class="c">-- ~/.config/magi/init.lua — the only entry point.</span>
<span class="c">-- Nothing is discovered by scanning: a file not named here does not load.</span>
magi.load("clients/hexe.lua")
magi.load("clients/oslo.lua")
magi.load("clients/balthasar.lua")
magi.load("tools.lua")

magi.model   = "openrouter/anthropic/claude-sonnet-4.6"
magi.confine = true                     <span class="c">-- refuse paths outside the session root</span>
magi.allow   = { … }                    <span class="c">-- answered in advance, not under pressure</span></pre>

      <h2 id="settings">What it takes</h2>
${table(["setting", "does"], [
  ["<code>magi.model</code>", "which model, as <code>magi models</code> prints it"],
  ["<code>magi.confine</code>", "whether <code>read</code>, <code>write</code> and <code>edit</code> refuse paths outside the session's directory"],
  ["<code>magi.allow</code>", "permissions granted in advance, so they are not asked about"],
  ["<code>magi.trusted</code>", "directories whose <code>.magi.lua</code> is as good as this file"],
  ["<code>magi.env</code>", "environment every process magi starts is given, on top of what it inherits"],
  ["<code>magi.project</code>", "what this session is called, in the name other sessions see"],
  ["<code>magi.agent_talk</code>", "how far one session may reach another"],
  ["<code>magi.ui</code>", "every colour, glyph and measurement the screen draws with"],
  ["<code>magi.melchior</code> · <code>magi.balthasar</code>", "settings handed to that sibling, in <i>its</i> vocabulary — one place to edit rather than two"],
])}

      <h2 id="trust">A project's own file</h2>
      <p>A <code>.magi.lua</code> arrives with a checkout. Cloning a repository and running magi in
      it must not be enough to add a tool — a tool names a command to run — or to widen what runs
      without asking.</p>
${table(["a project file may", "and may not"], [
  ["choose a model the machine already offers", "declare a tool"],
  ["set ordinary settings", "touch <code>confine</code>, <code>allow</code> or <code>trusted</code> — fatal, not a warning"],
  ["load its own files", "name its own directory as trusted"],
])}
      <p>The one way past it is from your own configuration: naming a directory in
      <code>magi.trusted</code> makes its project file as good as yours. A decision made once, in
      advance, in the file only you can edit. Without a way to say yes, the rule would be worked
      around instead of used.</p>
${note("<b>What magi does not keep, it says so about.</b> A declaration for something a sibling owns, or a setting nested past what can be described, is reported on stderr rather than dropped. A config line that did nothing used to look exactly like one that worked.")}

      <h2 id="siblings">Configuring a sibling through magi</h2>
      <p>magi asks each sibling what it takes, hands over what your config named, and reports
      anything the far side would not accept — a coordinator and a sibling disagreeing about what
      a name means is worth a line on stderr.</p>
      <pre>magi.balthasar = { promote_floor = 0.6 }
magi.melchior  = { max_tokens = 8192 }</pre>
      <pre>$ balthasar needs      <span class="c"># what it will accept, in its own words</span>
$ melchior needs</pre>
`,
});

PAGES.push({
  at: "guides/tools.html",
  section: "guide",
  nav: "writing a tool",
  title: "Writing a tool",
  blurb:
    "A declaration — a name, a description, a parameter schema, and how to reach it. Written in " +
    "Lua and read at start-up; none of it is compiled in.",
  body: `
${plate("d-tools", "plate 04", "three sources, one registry, four ways to reach a tool")}

      <h2 id="four">Four fields</h2>
      <pre>magi.tool("branch", {
  description = "the git branch this directory is on",
  needs = { },
  run = function()
    local out = magi.exec("git", { "branch", "--show-current" })
    return {
      said  = out,                       <span class="c">-- the model reads this. costs context.</span>
      shown = "on " .. out,              <span class="c">-- the person sees this. costs nothing.</span>
    }
  end,
})</pre>
${table(["field", "is"], [
  ["<code>description</code>", "what the model is told the tool does. This is the whole of how it decides to call it."],
  ["<code>needs</code>", "the parameter schema, as the model is shown it. Empty means it takes none."],
  ["<code>run</code>", "what happens. Returns <code>said</code> and <code>shown</code>."],
  ["<code>transport</code>", "how it is reached, when it is not this Lua body — see below."],
])}

      <h2 id="split">said and shown</h2>
      <p>The split is the whole idea. <code>said</code> enters the transcript, is replayed on every
      subsequent request, and costs context every turn until the conversation is compacted.
      <code>shown</code> is drawn once and costs nothing.</p>
      <p>A tool that returns a hundred lines of diff as <code>said</code> has spent that budget for
      the rest of the session. The same diff as <code>shown</code>, with
      <code>said = "patched 3 files"</code>, costs four words.</p>

      <h2 id="transports">Four ways to be reached</h2>
${table(["transport", "is", "for"], [
  ["<code>lua</code>", "a body that runs in magi's own VM", "anything that is a few lines of logic"],
  ["<code>command</code>", "a program on <code>$PATH</code>, given the call as argv", "wrapping something that already exists"],
  ["<code>casper</code>", "<code>casper run &lt;tool&gt;</code>", "the thirteen casper ships"],
  ["<code>builtin</code>", "compiled into magi", "the floor: <code>read</code>, <code>write</code>, <code>edit</code>"],
])}
      <p>The registry does not care which. One name, one entry, and the model sees the same
      declaration whichever way it is reached.</p>

      <h2 id="caps">Two caps you do not opt out of</h2>
      <ul class="plain">
        <li><b>Output is bounded.</b> Beyond the limit, the middle is dropped — head and tail both
        kept, because which one matters depends on the tool: a file read wants its head, a build
        that failed wants its tail. The whole of it is spilled to a file the note names.</li>
        <li><b>Secrets are masked by value.</b> The actual contents of this process's
        credential variables are replaced by their names before anything enters a transcript. Not
        by pattern — by value, so a key that does not look like a key is caught too.</li>
      </ul>
${note("<b>Here rather than in the tools</b>, because a peer is another program and cannot be trusted to cap itself, a Lua tool has no way to write a spill file, and a shipped declaration has no knob to set. Every result of every transport passes through one place, which is the only place that is true of.")}

      <h2 id="asking">A tool that asks a question</h2>
      <p>A declaration reads <code>args.answered</code> to know it is resuming. The answer travels
      <i>with</i> the arguments rather than beside them — merged, so a declaration writes
      <code>args.answered</code> and not <code>args.call.answered</code>. The answer is one more
      thing known about this call, which is what an argument is.</p>
`,
});

PAGES.push({
  at: "guides/permissions.html",
  section: "guide",
  nav: "what may run",
  title: "What may run",
  blurb:
    "Every read, write, command and host passes the ledger before it happens — and the answer is " +
    "reusable, or every session is a hundred prompts.",
  body: `
${plate("d-permit", "plate 10", "the ledger, in order")}

      <h2 id="verbs">Four verbs</h2>
${table(["verb", "is about to"], [
  ["read", "open a file"],
  ["write", "create or change one"],
  ["run", "execute a command"],
  ["reach", "connect to a host"],
])}

      <h2 id="width">Five widths</h2>
      <p>The verb is what is about to happen; the width is how far the answer reaches. The width is
      what makes a ledger worth having instead of a prompt per call.</p>
${table(["width", "covers"], [
  ["<code>once</code>", "this call and nothing else — the default, and the only answer that cannot be over-granted"],
  ["<code>exact</code>", "this path, or this exact command line, again"],
  ["<code>directory</code>", "anything under it. Paths are normalised <b>before</b> the check, so <code>work/sub/../../secret</code> is not covered by a grant on <code>work</code>."],
  ["<code>program</code>", "<code>git</code>, whatever the arguments. A command line carrying a metacharacter is refused rather than matched — <code>git status; rm -rf /</code> is not <code>git</code>."],
  ["<code>anything</code>", "every action of that verb, for this session"],
])}

      <h2 id="advance">Granting in advance</h2>
      <pre>magi.allow = {
  { verb = "read",  directory = "/home/you/work" },
  { verb = "run",   program = "git" },
}</pre>
      <p>A rule written down is not a question asked. The standing answers are ones you decided in
      advance, in a file, rather than under time pressure mid-turn. <b>A rule naming no width
      grants nothing.</b></p>

      <h2 id="confine">Confinement is a wall</h2>
      <p><code>magi.confine</code> refuses paths outside the session root outright — no prompt, no
      grant, no appeal. It applies whether or not there is anybody there to ask, which is why it
      sits before the ledger rather than inside it.</p>
${note("<b>It is not containment.</b> Confinement covers <code>read</code>, <code>write</code> and <code>edit</code>. It moved work to the shell, which has none — <code>bwrap</code> in front of the shell peer is what actually contains anything.")}

      <h2 id="nobody">When nobody is there</h2>
      <p>A run with no UI attached has nobody to ask. It is refused, and the tool is told why — a
      session whose front end has detached does not get to assume the answer would have been yes.
      That is why <code>magi -p</code> refuses an ungranted read rather than hanging on a question
      nobody can see.</p>
`,
});

PAGES.push({
  at: "guides/memory.html",
  section: "guide",
  nav: "memory",
  title: "Memory",
  blurb:
    "Writing must never slow a turn. Reading must never be trusted blindly. The two directions " +
    "have opposite rules, and both are best-effort.",
  body: `
${plate("d-mem", "plate 06", "out, in, and back again")}

      <h2 id="out">Out: nothing waits on it</h2>
      <p>A session is behind a mutex and a commit is a short lock. Putting a socket round trip
      inside one would make every entry wait on another process, so what is committed is
      <i>queued</i> and the turn carries on. If the write never lands, the entry is still in the
      window — only the durable record is lost.</p>

      <h2 id="in">In: nothing is trusted blindly</h2>
      <p>Recall returns memories with a confidence. Anything below the floor is dropped rather
      than hedged, and what survives is written into the window as <b>one user message that says
      what it is</b> — never slipped in as though the conversation had contained it.</p>
${table(["bound", "limits"], [
  ["inject floor", "how sure balthasar must be before a memory reaches the window at all"],
  ["live floor", "the lower bar for something recalled inside the current session"],
  ["window share", "the fraction of the context memory may ever occupy"],
  ["most", "a hard count, so a broad query cannot flood a turn"],
])}
${note("<b>The frame line is written first.</b> A recall that found only weak matches still says so — a hedged recall presented as certainty is worse than no recall at all.")}

      <h2 id="back">Back: did it help</h2>
      <p>A turn reports what it used and how that went. balthasar decides for itself whether the
      action followed from anything it gave; a harness claiming a match it did not verify would be
      asserting an analysis rather than reporting an event.</p>
      <pre>→ {"call":"used","args":["inject-1788683868-e3b0c442",{"tool":"shell","action":"…"}]}
← {"ok":true,"family":1,"n":1,"result":[{"action":"use-1788683868-inject-17886"}]}
→ {"call":"outcome","args":["use-1788683868-inject-17886",{"kind":"succeeded"}]}</pre>
      <p>Without it a memory layer can rank by recency and by similarity, and never by whether
      anything it offered was any use.</p>

      <h2 id="scope">Which store a directory gets</h2>
${plate("d-scope", "plate 07", "walk up until something claims it")}
      <p>A store somebody made deliberately wins first; then the checkout the directory is in.
      Five worktrees of one project share one memory rather than starting each other's amnesia.</p>
${note("<b>Both walks stop before a directory nobody owns.</b> Without a ceiling, one stray marker high up collects everything beneath it — and both kinds occur naturally: a leftover store in the temporary directory, and a <code>.git</code> at <code>$HOME</code>, which is what an ordinary dotfiles repository is. Either would put unrelated projects into a single memory. The rule is stricter for the <i>inferred</i> marker than the deliberate one: a repository at <code>$HOME</code> is not the project a subdirectory belongs to, while a store somebody explicitly created there is.")}

      <h2 id="resume">Resuming</h2>
      <p>With balthasar running there is <b>no journal on disk at all</b> — it is the store, and a
      second copy is a copy that goes stale. <code>magi --resume</code> asks balthasar which runs
      this project has had and replays the newest.</p>
      <pre>$ magi -p "remember the number 8231, just say ok"
ok
$ magi --resume -p "what number did I ask you to remember?"
8231</pre>
      <p>A separate process, after the first one and the balthasar it started are both gone. What
      survives is the store, not a running thing.</p>
`,
});

PAGES.push({
  at: "guides/sessions.html",
  section: "guide",
  nav: "sessions",
  title: "One session to another",
  blurb:
    "Every session binds its own socket and answers for itself, so the directory is the " +
    "registry. Two walls decide who may reach whom.",
  body: `
${plate("d-sess", "plate 08", "the project wall and the instance wall")}

      <h2 id="walls">Two walls</h2>
${table(["wall", "means"], [
  ["the project wall", "a session sees only its own project's directory. Not <i>should not</i> — another project's sessions are somewhere this one never lists."],
  ["the instance wall", "a main is its instance's front door; the subagents behind it are private."],
])}

      <h2 id="talk">Widening the second one</h2>
${table(["<code>magi.agent_talk</code>", "lets"], [
  ["<code>\"mains\"</code>", "two sessions started at a terminal talk to each other, and a subagent talk to whoever started it. Nothing else. <b>The default.</b>"],
  ["<code>\"instance\"</code>", "and subagents of the same parent talk to each other"],
  ["<code>\"project\"</code>", "and anything in the project reach anything else in it"],
])}
      <p>Sessions in different projects never can, at any setting. This only widens things inside
      one project, and nothing widens it further.</p>

      <h2 id="verbs">What a session may say</h2>
      <p>The vocabulary has <b>no verb that runs anything</b>. It sends messages, reads an inbox,
      and says who is listening — deliberately, and melchior's own tests refuse a verb named
      <code>run</code>, <code>shell</code>, <code>exec</code> or <code>eval</code>.</p>
      <p>That is why magi grants the agent tool in advance rather than asking. Granting it grants
      the ability to talk to other sessions, which is the whole of what the tool is for — and
      asking here cannot work anyway: the prompt would land mid-conversation, stopping the turn a
      sibling's question started on a keystroke nobody was told about.</p>

      <h2 id="dead">A socket nobody answers</h2>
      <p>A process that died did not get to remove itself from a list, so a stale socket looks
      exactly like a live one until something connects. Liveness is <b>asked, never assumed</b>:
      one cheap call settles it. Dialling is not liveness either — the kernel accepts on behalf of
      a listener whose owner has stopped reading, so a wedged sibling accepts instantly and then
      never answers.</p>
`,
});

PAGES.push({
  at: "guides/screen.html",
  section: "guide",
  nav: "the screen",
  title: "The screen, lent out",
  blurb:
    "Most tools print and exit. Some need the screen — a pager, an editor, a picker, a " +
    "permission prompt. Such a tool asks for rows and then owns them.",
  body: `
${plate("d-screen", "plate 05", "lend, draw, hand back")}

      <h2 id="roles">A tool never names a colour</h2>
      <p>A surface draws in <b>roles</b> — this is a heading, this is selected, this is an error —
      and magi resolves each role against the palette the person configured.</p>
${table(["the tool says", "magi decides"], [
  ["a role", "which palette index, from <code>magi.ui</code>"],
  ["how many rows it wants", "how many it gets, against the floor and the window"],
  ["that it is finished", "when the rows are reclaimed and repainted"],
])}
      <p>A tool that named a colour would look wrong on somebody else's terminal, and the person's
      own settings would stop applying the moment a tool drew anything.</p>

      <h2 id="ends">How it ends</h2>
      <p>When the tool says so, or when the person presses escape twice. Then magi repaints around
      it and the rows go back.</p>

      <h2 id="why">Why frames and not one exec</h2>
      <p>A surface is a stream of frames both ways for as long as the tool holds its rows — keys
      and clicks down, a drawn frame back. One exec per event would restart the program between
      keystrokes, which is not an editor.</p>
${note("<b>The permission prompt is itself a surface.</b> That is why it can show a wrapped command in full rather than a truncated one — and a command cut in the middle is a command somebody allows without having seen the end of.")}
`,
});

// ----------------------------------------------------------------------------- reference -----
PAGES.push({
  at: "reference/wire.html",
  section: "ref",
  nav: "the wire",
  title: "Wire reference",
  blurb:
    "Enough to write a peer: the framing, the shapes, the encodings, the version rule and the " +
    "failure modes. Three transports, two shapes, two encodings.",
  body: `
      <h2 id="transports">Three transports</h2>
${table(["transport", "framing", "for"], [
  ["<b>argv</b>", "one JSON object on stdout, then exit", "a program that runs once per call. Nothing to keep alive, and a fresh process knows everything the last one did."],
  ["<b>pipe</b>", "one object per line, newline-delimited", "a program held for the session, talking to the one that started it."],
  ["<b>socket</b>", "four bytes of big-endian length, then that many bytes", "anything that may knock. Self-delimiting, so a peer that dies mid-frame is caught at the length."],
])}
${note("<b>An encoding is not a transport.</b> JSON is on all three; naming it as one is how a diagram of this family came to have “argv + json” on an edge.")}

      <h2 id="shapes">Two shapes</h2>
      <pre><span class="c">a call — somebody is waiting</span>
{"call": "&lt;verb&gt;", "args": [ … ]}
{"ok": true, "family": 1, "n": &lt;count&gt;, "result": [ … ]}

<span class="c">an event — nobody is</span>
{"event": "&lt;name&gt;", … }</pre>
      <p><code>result</code> is <b>always a list</b>, so one call answers with what the function
      did. Two ends disagreeing about that fail <i>silently</i>: a client that unpacks reads a
      bare-value server as having returned nothing at all, so the bug presents as an empty memory
      rather than as an error.</p>

      <h2 id="version">The version rule</h2>
      <p><code>family</code> is the revision of the wire a reply is written in. <b>A newer peer is
      refused by name; an older one is not.</b> A reply with no <code>family</code> at all is from
      before the check and is accepted.</p>
      <p>The constant is duplicated in each sibling rather than shared. A crate held in common
      would be a dependency between repositories, and this family has none.</p>

      <h2 id="encodings">Two encodings</h2>
${table(["", ""], [
  ["JSON", "the default. What every peer understands, and what somebody with <code>socat</code> can read."],
  ["CBOR", "the same shape as bytes, for a caller that is not going to read it."],
])}
      <p>On a one-shot door, ask with <code>--cbor</code>. On a socket, just send it: the server
      answers in whatever it was asked in.</p>
      <pre><span class="c">how the encoding is read off a body — no handshake, no setting</span>
first non-space byte  '{' or '['   → json
                      0x80..0xBF   → cbor   <span class="c">(a cbor map or array)</span>
                      anything else → json  <span class="c">(so the error message is the useful one)</span></pre>

      <h2 id="refusals">Refusals</h2>
      <p>A refused verb is <code>ok: false</code> with <b>exit status zero</b>, and a refusal is a
      reply: only the transport failing closes anything. That is what lets a caller tell “it said
      no” from “it is not there”.</p>
${table(["fault", "the caller loses"], [
  ["<code>refused</code>", "a feature. Carry on."],
  ["<code>unavailable</code>", "the sibling. Carry on without it."],
  ["<code>failed</code>", "the write. Do not assume it was recorded."],
  ["<code>malformed</code>", "nothing yet — but this is a bug to report, not a condition to handle."],
])}

      <h2 id="limits">Limits</h2>
${table(["", ""], [
  ["frame", "16 MiB on magi's own wire; 1 MiB between sessions. A message between instances is a sentence, not a payload — an unbounded read is a way to make a session allocate until it dies."],
  ["socket path", "108 bytes, which is the kernel's limit and not anybody's choice. Long temporary directories are how this is usually met."],
  ["identity", "<code>SO_PEERCRED</code>. A caller the kernel will not identify gets nothing."],
])}
`,
});

PAGES.push({
  at: "reference/verbs.html",
  section: "ref",
  nav: "verbs",
  title: "Verbs",
  blurb: "What each door answers, and what it deliberately does not.",
  body: `
      <h2 id="balthasar">balthasar</h2>
      <p>The surface is small on purpose. It is not a mirror of what balthasar can do; it is the
      handful of things another program has a real reason to ask a memory layer.</p>
${table(["verb", "does"], [
  ["<code>verbs</code>", "what this socket answers. The one call every balthasar has had since v1, and what a caller asks first."],
  ["<code>observe</code>", "take an entry into this run's record"],
  ["<code>recall</code>", "search, and say how sure it is about each answer"],
  ["<code>context</code>", "exactly what a model would be told"],
  ["<code>resume</code> · <code>replay</code>", "a prior run's entries, back out again"],
  ["<code>sessions</code>", "which runs this project has had"],
  ["<code>used</code> · <code>outcome</code>", "what a turn did with what it was given, and how that went"],
  ["<code>plan</code>", "what it would cost to inject, before injecting"],
])}
${note("<b><code>prompt</code>, <code>run</code> and <code>eval</code> are absent and stay absent.</b> A memory layer that can be told to run something is not a memory layer.")}

      <h2 id="melchior">melchior</h2>
${table(["verb", "does"], [
  ["<code>listening</code>", "where this session is, and what it is called"],
  ["<code>doing</code>", "what it is busy with — an <i>event</i>, so nobody replies"],
  ["<code>message</code>", "put something in another session's inbox"],
  ["<code>ask</code> · <code>reply</code>", "a question to a session, and its answer — which arrives long after the connection that carried the question has closed"],
  ["<code>who</code>", "who is listening, within the walls"],
  ["<code>mint</code> · <code>minted</code>", "a token for a session of one's own. Self only."],
])}
      <p>No verb here runs anything, and melchior's own tests refuse one named <code>run</code>,
      <code>shell</code>, <code>exec</code> or <code>eval</code>.</p>

      <h2 id="casper">casper</h2>
${table(["command", "does"], [
  ["<code>tools</code>", "every tool it offers, as declarations a harness can register"],
  ["<code>run &lt;tool&gt;</code>", "one call, arriving as JSON on stdin"],
  ["<code>surface &lt;tool&gt;</code>", "hold rows on the harness's screen and exchange frames"],
  ["<code>verbs</code>", "what its socket answers"],
])}
${note("<b><code>run</code> is deliberately not reachable over the socket.</b> casper's job is running programs, and a socket that runs commands is a remote shell wearing a friendly name. The spawn link carries the trust instead.")}

      <h2 id="both">Everywhere</h2>
${table(["", ""], [
  ["<code>needs</code>", "what a coordinator may tell this program, in its own vocabulary"],
  ["<code>configure</code>", "take that configuration, as Lua on stdin, and say what it did with it"],
  ["<code>--json</code> · <code>--cbor</code>", "which encoding the reply comes back in"],
])}
`,
});

PAGES.push({
  at: "reference/cli.html",
  section: "ref",
  nav: "commands",
  title: "Commands",
  blurb: "Every binary, and what it answers to.",
  body: `
      <h2 id="magi">magi</h2>
      <pre>magi [PROMPT]                 <span class="c">a session here; the prompt is submitted on start</span>
  -p, --print                 <span class="c">print the answer and exit, instead of opening the UI</span>
  -r, --resume                <span class="c">continue this directory's most recent session</span>
      --socket &lt;PATH&gt;         <span class="c">connect to a named socket instead of one per directory</span>
      --sessions &lt;DIR&gt;        <span class="c">where session journals live</span>

magi doctor                   <span class="c">what a session here would be made of, without starting one</span>
magi tools                    <span class="c">every tool the model can call, and how each is reached</span>
magi models                   <span class="c">the providers and models melchior knows about</span>
magi lua-api                  <span class="c">the Lua client library for magi's own surface</span>
magi ext &lt;kind&gt;               <span class="c">run a tool peer. not for people: magi spawns these itself</span>
magi fake-host                <span class="c">serve a recorded session, so the UI can be worked on without a model</span></pre>

      <h2 id="casper">casper</h2>
      <pre>casper tools                  <span class="c">every tool, with schemas</span>
casper run &lt;tool&gt;             <span class="c">one call on stdin, one result on stdout</span>
casper surface &lt;tool&gt;         <span class="c">frames both ways, for as long as it holds its rows</span>
casper verbs                  <span class="c">what its socket answers</span>
  --json | --cbor             <span class="c">which encoding a reply comes back in</span></pre>

      <h2 id="melchior">melchior</h2>
      <pre>melchior models               <span class="c">what this machine could talk to</span>
melchior ask                  <span class="c">run a turn; an Ask on stdin</span>
melchior serve                <span class="c">bind this session's socket and answer for it</span>
  --project &lt;NAME&gt;            <span class="c">which project this session belongs to</span>
melchior needs                <span class="c">what a coordinator may tell it</span>
melchior configure            <span class="c">take that configuration, as Lua on stdin</span>
melchior tool                 <span class="c">the agent surface, as a harness calls it</span>
  --json | --cbor             <span class="c">which encoding a reply comes back in</span></pre>

      <h2 id="balthasar">balthasar</h2>
      <pre>balthasar remember &lt;TEXT&gt;     <span class="c">keep something, and say who says so</span>
balthasar recall &lt;QUERY&gt;      <span class="c">search</span>
  --explain                   <span class="c">and say why each answer came back</span>
balthasar why &lt;HANDLE&gt;        <span class="c">the evidence, not just the number</span>
balthasar promote             <span class="c">carry something out of a session into the project's memory</span>
balthasar forget              <span class="c">move a memory out of the live set, or remove it outright</span>
balthasar context             <span class="c">exactly what a model would be told</span>
balthasar sessions            <span class="c">which runs this project has had</span>
balthasar decay               <span class="c">what today's forgetting would take, before it takes it</span>
balthasar consolidate         <span class="c">carry what recurred across sessions into the project</span>
balthasar eval                <span class="c">measure whether memory earns its place</span>

balthasar serve               <span class="c">listen for other programs</span>
  --instance &lt;NAME&gt;           <span class="c">when more than one should be reachable at once</span>
  --scope &lt;SCOPE&gt;             <span class="c">global, project, or a path</span>
  --tied &lt;PID&gt;                <span class="c">end when that process ends, enforced by the kernel</span>
balthasar api &lt;VERB&gt; [ARGS]   <span class="c">answer one question, wire-shaped, and exit</span>
  --json | --cbor             <span class="c">which encoding a reply comes back in</span></pre>
${note("<b><code>--tied</code> is absent by default.</b> A balthasar started at a terminal or by a unit file is meant to outlive the thing that typed the command. magi passes it, naming its own process id, so the memory layer cannot outlive the window even if magi is killed outright.")}
`,
});
