// Every page of the site, and what is on it.
//
// One file so that the shape of the whole thing is readable at once. `at` is where a page is
// written, `nav` is what the sidebar calls it, and `body` is everything under the lede.

export const SECTIONS = [
  { key: "home", name: "overview", jp: "概要", home: "index.html" },
  { key: "arch", name: "architecture", jp: "構造", home: "architecture/index.html" },
  { key: "prog", name: "the four", jp: "四機", home: "programs/magi.html" },
  { key: "guide", name: "guides", jp: "手引", home: "guides/install.html" },
  { key: "cmp", name: "compared", jp: "比較", home: "compared/index.html" },
  { key: "ref", name: "reference", jp: "規格", home: "reference/wire.html" },
];

/** A drawing, with the plate furniture around it. */
const plate = (id, name, says) => `      <div class="plate">
        <header><b>${name}</b><span>${says}</span></header>
        <div class="body"><div class="dia" id="${id}"></div></div>
      </div>`;

/** A table from rows of [left, right]. */
const table = (head, rows) => `      <div class="tw"><table>
        <thead><tr>${head.map((h) => `<th>${h}</th>`).join("")}</tr></thead>
        <tbody>
${rows.map((r) => `          <tr>${r.map((c, i) => `<td${i ? ' class="wrap-ok"' : ""}>${c}</td>`).join("")}</tr>`).join("\n")}
        </tbody>
      </table></div>`;

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
      <div class="four">
        <a href="programs/magi.html"><img src="assets/logo/magi.svg" alt=""><span>magi</span></a>
        <a href="programs/casper.html"><img src="assets/logo/casper.svg" alt=""><span>casper</span></a>
        <a href="programs/melchior.html"><img src="assets/logo/melchior.svg" alt=""><span>melchior</span></a>
        <a href="programs/balthasar.html"><img src="assets/logo/balthasar.svg" alt=""><span>balthasar</span></a>
      </div>

      <div class="cards">
        <div class="card">
          <h4>magi</h4><div class="role">the harness</div>
          <p>The one you run. Holds the conversation, the screen, the tool registry and the
          permission ledger, and reaches the other three for everything else.</p>
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
  ['<a href="guides/install.html">install</a>', 'get the binaries, or <a href="guides/install.html#build">all four from one clone</a> — and check what a session here would be made of'],
  ['<a href="architecture/index.html">the map</a>', "every edge, what travels on it, and what happens when one end is missing"],
  ['<a href="guides/tools.html">write a tool</a>', "four fields of Lua, read at start-up — nothing is compiled in"],
  ['<a href="guides/roles.html">swap a program</a>', "any of the three siblings, replaced by anything that answers the same core verbs"],
  ['<a href="reference/wire.html">the wire</a>', "the shapes, the encodings, and the framing, in enough detail to write a peer"],
])}

      <h2 id="rules">What holds it together</h2>
      <ul class="plain">
        <li><b>No shared code, in either direction.</b> balthasar's Rust never parses magi's types
        and melchior does not know what a harness is. What crosses is data each side parses into
        its own shapes — so any one of them can be replaced by something that speaks the same
        words. That is written down as a contract: see <a href="guides/roles.html">swapping a
        program</a>.</li>
        <li><b>Every sibling but the memory layer is optional.</b> Without casper a session has
        three builtin tools; without melchior it has no model and no other agents, and runs and
        says so. Without a memory layer it does not start: that layer is the store, and a session
        that cannot record is refused rather than run on a copy that goes stale.</li>
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
  ["magi → balthasar", "magi, once per session", "every entry out; recalled memory and prior sessions back", "no session: magi refuses to start, because this is the store and there is no journal to fall back to"],
  ["session → session", "either, through melchior", "messages, questions and answers between agents", "a session with no siblings, which is the ordinary case"],
  ["front end → session", "the front end", "what was typed, up; everything to draw, down", "the turn keeps running — close the window and come back"],
])}
      <p>Each sibling is named by the role it fills — <code>memory</code>, <code>tools</code>,
      <code>model</code> — and which program fills it is one line of configuration. See
      <a href="../guides/roles.html">swapping a program</a>.</p>

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
${note("<b>A verb a program does not have is a refusal too</b> — on stdout, in the reply shape, at exit 0. An argument parser left to itself answers an unknown subcommand with usage on stderr and exit 2, which a caller cannot tell from a binary that is not installed.")}

      <h2 id="doors">Three doors</h2>
      <p>Every row <code>verbs</code> returns names the door it is reached on, and a program may
      not name a door it cannot open.</p>
${table(["door", "is", "who has one"], [
  ["<code>cli</code>", "the command line: one exec, one reply", "all four"],
  ["<code>socket</code>", "a bound socket, for anything that may knock", "melchior and balthasar. casper binds none: a socket that runs commands is a remote shell."],
  ["<code>tool</code>", "the vocabulary a model calls, one exec per request — <code>melchior tool --verb X</code>", "melchior, for coordination"],
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
  ["melchior", "<code>serve --project &lt;p&gt;</code>, on a pipe", "magi closes the pipe and it leaves — and it leaves too when magi is killed outright and closes nothing"],
  ["casper", "<code>run &lt;tool&gt;</code>, once per call", "it exits on its own, every call. A call in flight does not outlive the magi that asked, and neither does a program the call started."],
  ["a child session", "<code>magi fork</code>: its own magi, named by melchior", "the session that started it. The child is told its parent’s pid and leaves when it goes; the parent holds the secret that stops it sooner."],
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
      <p>Every one of these runs on the way to <code>main</code>, and all but the last in all
      four repositories.</p>
${table(["gate", "what it forbids"], [
  ["no cycles", "two top-level modules that depend on each other. This is what a reachability check cannot catch: a cycle is maximally reachable."],
  ["one wire", "a second way of saying the same thing across a boundary"],
  ["independence", "any file in a sibling naming a harness"],
  ["800 lines", "a source file bigger than one sitting"],
  ["reachable", "a file nobody declares — not a compile error, not a warning, and never run"],
  ["hermetic", "anything left behind in the temporary directory, checked under one of its own"],
  ["no model needed", "a memory test that only passes with a key and a network"],
  ["no dead weight", "a declared dependency the code does not use"],
  ["roles", "a program named for a role that does not answer that role’s core verbs — asked of the binary, not read from the source"],
  ["one Lua VM", "a second Lua VM in a program, or one that is not sandboxed"],
  ["comments", "a comment longer than a fifth of the code it describes"],
  ["twins", "magi’s and melchior’s copies of the model wire drifting apart — the one gate that needs two checkouts"],
])}
`,
});

// ------------------------------------------------------------------------------ the four -----
PAGES.push({
  at: "programs/magi.html",
  section: "prog",
  logo: "magi",
  nav: "magi",
  title: "magi",
  blurb:
    "The harness. The conversation, the screen, the tool registry and the permission ledger — and the " +
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
        <li><b>The session.</b> Its id, and which program holds its transcript — whatever fills
        the <a href="../guides/roles.html">memory role</a>.</li>
        <li><b>Other agents.</b> <code>magi fork</code> starts a child session of this one, and
        the screen moves between them from the keyboard. See
        <a href="../guides/sessions.html#fork">sessions</a>.</li>
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
magi fork "…"            <span class="c">start a child session of this one, and print what it is called</span>
magi --headless          <span class="c">a session with no terminal, reachable until something ends it</span>
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
  logo: "casper",
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
      <p>Every one is declared in Lua, in <code>~/.config/casper/tools.lua</code>, which
      <code>make install</code> puts there. Editing it changes the tools on the next call — no
      rebuild. It used to be compiled into the binary, which meant reading what the thirteen
      actually do, or changing one, was a build.</p>

      <h2 id="extend">Adding your own</h2>
      <p>A file in a directory. Nothing to register, no entry point to edit:</p>
      <pre>~/.config/casper/plugin/yours.lua              <span class="c">alphabetical, each on its own</span>
~/.local/share/casper/site/pack/*/start/*/plugin/*.lua   <span class="c">installed packages</span>
~/.config/casper/after/plugin/yours.lua        <span class="c">the last word</span></pre>
      <p>The registry replaces by name, so the order <i>is</i> the precedence: a file declaring
      <code>cat</code> means it, and <code>after/plugin/</code> is how you override something you
      did not write. <code>make install</code> overwrites <code>tools.lua</code> and never touches
      these. See <a href="../guides/tools.html">writing a tool</a>.</p>
${note("<b>A package you fetched does not run until you say so.</b> Files you put in your own <code>plugin/</code> directory run on sight. Anything under <code>site/pack/</code> is held back until <code>casper acknowledge</code> records its digest, and held back again the moment it changes.")}

      <h2 id="settings">What a coordinator may tell it</h2>
${table(["setting", "does"], [
  ["<code>tools</code>", "per tool, by name. <code>off</code> removes it entirely — not listed, and refused if the model guesses the name anyway. <code>hidden</code> keeps it runnable and takes it out of what the model is shown."],
  ["<code>load</code>", "an extra declarations file, read after everything on disk"],
  ["<code>output_bytes</code>", "how much of a result crosses back before it is cut. Head and tail both kept, and the note says how much went."],
])}
      <pre><span class="c">-- in magi's config, in casper's vocabulary</span>
magi.casper = { tools = { dino = { off = true } }, output_bytes = 65536 }</pre>

      <h2 id="exec">Why a spawn and not a socket</h2>
      <p>casper's job is running programs, and <b>a socket that runs commands is a remote shell
      wearing a friendly name</b>. The spawn link carries the trust instead: a parent that can
      spawn casper could have run the command itself, so nothing is granted by handing it over.
      One exec per call.</p>
${note('<b>casper fills the <code>tools</code> role, and is the default rather than the only choice.</b> <code>magi.tools</code> hands the role to any program that answers <code>tools</code> and <code>run</code> — see <a href="../guides/roles.html">swapping a program</a>. The settings table follows the program’s own name, so <code>magi.casper</code> is casper’s because casper is the one filling the role.')}

      <h2 id="cli">At a terminal</h2>
      <pre>casper tools                 <span class="c">every tool it offers, as declarations a harness can register</span>
casper run &lt;tool&gt;            <span class="c">run one; the call arrives as JSON on stdin</span>
casper surface &lt;tool&gt;        <span class="c">hold rows on the harness's screen and draw into them</span>
casper verbs                 <span class="c">what it answers, on each of its doors</span>
casper needs                 <span class="c">what a coordinator may tell it</span>
casper configure             <span class="c">take that configuration, as Lua on stdin</span>
casper acknowledge           <span class="c">clear the installed packages, so their declarations may run</span>
casper client                <span class="c">a refusal: casper is reached by spawning it with a call</span>

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
  logo: "melchior",
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
        <li><b>The crew.</b> Who started whom, who has claimed what, which task is whose, and a
        handoff when one agent passes work to another — reached by a model through one tool door.
        See <a href="../guides/sessions.html#crew">the crew</a>.</li>
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
melchior fork                <span class="c">a name and a secret for a session about to be started</span>
melchior tool --verb &lt;v&gt;     <span class="c">the coordination vocabulary a model calls, one exec per request</span>
melchior brief               <span class="c">what to tell a model about the sessions a prompt named</span>

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
  logo: "balthasar",
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
      <pre>&lt;project&gt;/balthasar/&lt;tool&gt;/project.db                   <span class="c">what is true here, kept</span>
&lt;project&gt;/balthasar/&lt;tool&gt;/&lt;run&gt;/transcript.db            <span class="c">that run's turns, verbatim</span>
&lt;project&gt;/balthasar/&lt;tool&gt;/&lt;run&gt;/&lt;agent&gt;/memory.db        <span class="c">one agent's scratch, dies with the run</span>
~/.local/share/balthasar/&lt;tool&gt;/global.db          <span class="c">yours, everywhere</span></pre>
      <p><b>The store lives in the project</b>, so renaming a checkout moves its memory rather than
      orphaning it. Which store a given directory gets is
      <a href="../guides/memory.html#scope">its own question</a>.</p>
${note('<b>balthasar fills the <code>memory</code> role.</b> It binds under <code>$XDG_RUNTIME_DIR/memory/</code>, the role’s name, and under the older <code>balthasar/</code> for one release so nothing that has not been rebuilt loses it. <code>magi.memory</code> names another program for the role — see <a href="../guides/roles.html">swapping a program</a>.')}

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
    "gates ran under — or all four from source, in one clone. Linux only.",
  body: `
      <h2 id="get">Get the binaries</h2>
      <pre>gh release download v0.1.0 --repo ai-nerv/magi --pattern '*-amd64.tar.gz'
tar -xzf magi-linux-amd64.tar.gz -C ~/.local/bin

<span class="c"># the siblings are separate releases. casper and melchior are optional; a memory layer is not</span>
gh release download v0.1.0 --repo ai-nerv/casper    --pattern '*-amd64.tar.gz'
gh release download v0.1.0 --repo ai-nerv/melchior  --pattern '*-amd64.tar.gz'
gh release download v0.1.0 --repo ai-nerv/balthasar --pattern '*-amd64.tar.gz'</pre>

      <h2 id="what">What each one buys you</h2>
${table(["", "without it"], [
  ["magi", "nothing — this is the one you run"],
  ["casper", "a session with three builtin tools: <code>read</code>, <code>write</code>, <code>edit</code>"],
  ["melchior", "no model and no siblings. The session runs and says so."],
  ["balthasar", 'no session: the memory layer is the store, so magi refuses to start rather than record nowhere. Another program can fill the role — see <a href="roles.html">swapping a program</a>.'],
])}

      <h2 id="check">Check before you start</h2>
      <pre>magi doctor</pre>
      <p>It answers everything a session decides at start-up: which configuration was read, which
      of its lines were kept, what the registry holds and where each entry came from, and whether
      the siblings actually <i>answer</i> — and whether the program named for each role can fill
      it at all. Asked, not looked for — a program on
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

      <h2 id="build">All four, from source</h2>
      <p>One clone holds the four programs as submodules, and its recipes build, run and install
      them together. It needs <code>oslo</code> and a Rust toolchain.</p>
      <pre>git clone --recursive https://github.com/ai-nerv/.github nerv
cd nerv
oslo make install   <span class="c"># all four to ~/.local/bin, each config to ~/.config/&lt;name&gt;</span></pre>
${table(["recipe", "does"], [
  ["<code>make build</code>", "every binary"],
  ["<code>make run</code>", "magi, with the other three fresh from their builds rather than installed. <code>make run --args doctor</code> runs <code>magi doctor</code> that way."],
  ["<code>make install</code>", "every binary to <code>~/.local/bin</code>, and each configuration"],
  ["<code>make test</code>", "every suite"],
  ["<code>make status</code>", "each checkout: its branch, commits not pushed, changes not committed"],
  ["<code>make update</code>", "every checkout to the tip of <code>develop</code>"],
  ["<code>make push</code>", "push each checkout, then pin what was pushed in this repository"],
])}
      <p>Each recipe goes into each checkout and calls the recipe of the same name there, so
      <code>make</code> inside a checkout still means that program alone. At an oslo prompt
      <code>make</code> is enough; elsewhere it is <code>oslo make</code>.</p>

      <h2 id="work">Working on them</h2>
      <p>Each checkout is a real clone. Commit in it as usual, then <code>make push</code> at the
      top: it checks all four are on <code>develop</code> with nothing uncommitted, pushes each, and
      records the new commits in one commit here. A pin to a commit GitHub has never seen is a clone
      that fails for everybody but you, which is why the push comes first.</p>
${note("<b>A fresh clone is not on a branch.</b> Submodules arrive at the exact commit that was pinned, so <code>make status</code> says <i>detached</i>. To work on one, <code>git checkout develop</code> inside it first — <code>make push</code> refuses until you have, and says why.")}

      <h2 id="one">One program on its own</h2>
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
    "One entry point for what you name, and three directories for what you install.",
  body: `
${plate("d-config", "plate 11", "load order, and where a project file is refused")}

      <h2 id="entry">The entry point</h2>
      <pre><span class="c">-- ~/.config/magi/init.lua — what you name explicitly.</span>
<span class="c">-- What you *install* is discovered: see writing a tool.</span>
magi.load("tools.lua")

magi.model   = "openrouter/anthropic/claude-sonnet-4.6"
magi.confine = true                     <span class="c">-- refuse paths outside the session root</span>
magi.allow   = { … }                    <span class="c">-- answered in advance, not under pressure</span></pre>

      <h2 id="settings">What it takes</h2>
${table(["setting", "does"], [
  ["<code>magi.model</code>", "which model, as <code>magi models</code> prints it"],
  ['<code>magi.memory</code> · <code>magi.tools</code> · <code>magi.melchior</code>', 'as a string, which program fills that role — see <a href="roles.html">swapping a program</a>'],
  ["<code>magi.confine</code>", "whether <code>read</code>, <code>write</code> and <code>edit</code> refuse paths outside the session's directory"],
  ["<code>magi.allow</code>", "permissions granted in advance, so they are not asked about"],
  ["<code>magi.trusted</code>", "directories whose <code>.magi.lua</code> is as good as this file"],
  ["<code>magi.env</code>", "environment every process magi starts is given, on top of what it inherits"],
  ["<code>magi.project</code>", "what this session is called, in the name other sessions see"],
  ["<code>magi.agent_talk</code>", "how far one session may reach another"],
  ["<code>magi.ui</code>", "every colour, glyph and measurement the screen draws with"],
  ["<code>magi.casper</code> · <code>magi.melchior</code> · <code>magi.balthasar</code>", "as a table, settings handed to that sibling, in <i>its</i> vocabulary — one place to edit rather than two. For the tools role the table is named after whichever program fills it."],
])}

      <h2 id="trust">A project's own file</h2>
      <p>A <code>.magi.lua</code> arrives with a checkout. Cloning a repository and running magi in
      it must not be enough to add a tool — a tool names a command to run — or to widen what runs
      without asking.</p>
${table(["a project file may", "and may not"], [
  ["choose a model the machine already offers", "declare a tool"],
  ["set ordinary settings", "touch <code>confine</code>, <code>allow</code> or <code>trusted</code> — fatal, not a warning"],
  ["load its own files", "name its own directory as trusted"],
  ["tune a sibling through its settings table", "name the program that fills a role — fatal, since it would run with the session’s authority"],
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
magi.melchior  = { max_tokens = 8192 }
magi.casper    = { tools = { dino = { off = true }, birdy = { hidden = true } } }</pre>
      <pre>$ balthasar needs      <span class="c"># what it will accept, in its own words</span>
$ melchior needs
$ casper needs</pre>
      <p>A setting the far side does not recognise comes back <b>named</b> rather than as a
      generic refusal, because "refused" is not something a coordinator can act on. Its own
      vocabulary, not magi's: renaming a setting on one side shows up as a line on stderr instead
      of failing silently on the other.</p>
${note("<b>A program spawned per call is told on every spawn.</b> <code>configure</code> sets something in the process that answers it — the whole of what a sibling needs when it is asked once and then runs for the session. casper is one process per call, so what magi decided rides on <i>every</i> spawn instead. Otherwise casper would report the setting taken and the next call would be a fresh process that had never heard of it.")}
`,
});

PAGES.push({
  at: "guides/roles.html",
  section: "guide",
  nav: "swapping a program",
  title: "Swapping a program",
  blurb:
    "A role is what a program is for; which program fills it is one line of configuration. " +
    "balthasar, casper and melchior are the defaults, not the only choices.",
  body: `
      <h2 id="three">Three roles</h2>
      <p>magi does not know that its memory is called balthasar. It knows the <code>memory</code>
      role is filled by whatever <code>magi.memory</code> names, and that whatever fills it answers
      the role’s verbs. Change the name and the program changes — nothing else does.</p>
${table(["role", "named by", "default", "core verbs", "unfilled"], [
  ["memory", "<code>magi.memory</code>", "balthasar", "<code>observe</code> <code>replay</code> <code>sessions</code>", "magi refuses to start: this is the store"],
  ["tools", "<code>magi.tools</code>", "casper", "<code>tools</code> <code>run</code>", "an ordinary session with the three builtin tools"],
  ["model", "<code>magi.melchior</code>", "melchior", "<code>models</code> <code>ask</code>", "no model to ask"],
])}
      <pre>magi.memory = "remembrance"   <span class="c">-- a program on $PATH</span>
magi.tools  = "workbench"</pre>
${note("<b><code>magi.model</code> is the model, not the program.</b> It named the model before roles existed, so the model role is named by <code>magi.melchior</code>, which has always meant the program. A table there is still that program’s settings; only a string names it.")}

      <h2 id="core">Core, and everything else</h2>
${table(["", "if a program refuses it"], [
  ["<b>core</b>", "it cannot fill the role. The gate fails, and <code>magi doctor</code> says so."],
  ["<b>extension</b>", "magi carries on with less — a model tool not declared, no compaction, an outcome loop that records nothing."],
])}
      <p>An extension is <i>refused</i>, not omitted: a program that does not do <code>plan</code>
      answers <code>plan</code> with a refusal in the reply shape, like any other. Silence is the one
      thing that is not allowed. The line was drawn from what magi actually calls, not from what any
      implementation happens to offer — see the <a href="../reference/verbs.html#balthasar">memory
      verbs</a>.</p>
${note("<b><code>sessions</code> is core because it was measured to be.</b> It was an extension in the first draft. A memory layer written to that draft was pointed at magi with <code>sessions</code> refused, and <code>--resume</code> came back empty at exit 0, saying nothing — magi asks it first, to find the newest run, before it can replay one. Running a second program against the contract is how the line got drawn in the right place.")}

      <h2 id="check">Before you name one</h2>
      <p>Ask the binary, not its source. The role gate lists the core verbs a program advertises
      and fails on any it does not:</p>
      <pre>$ scripts/gate-role.sh tools ./workbench
gate-role: workbench as tools
  tools          core       answered
  run            core       answered
  extensions                2 of 2

gate-role: workbench fills tools.</pre>
      <p>And <code>magi doctor</code> asks the same of whatever your configuration names, before a
      session depends on it. With <code>magi.memory = "casper"</code>, which cannot:</p>
      <pre>roles
  memory   casper — ~/.local/bin/casper — cannot fill memory: it answers no observe, replay, sessions
  tools    casper — ~/.local/bin/casper — 13 tools
  model    melchior — ~/.local/bin/melchior — 449 models</pre>

      <h2 id="proof">Two that exist to prove it</h2>
      <p>magi’s repository carries a second implementation of two of the roles, each one file of
      Rust with no dependencies, written from the contract rather than from magi’s source. Both run
      in magi’s own test suite against real sessions: one records a conversation and resumes it, the
      other is offered to the model, called, and answers.</p>
${table(["", "fills", "answers"], [
  ["<code>examples/remembrance</code>", "memory", "the family floor and the three core verbs, on a socket; refuses every extension"],
  ["<code>examples/workbench</code>", "tools", "<code>tools</code> and <code>run</code>, one exec per call, and one tool that reverses a string"],
])}
      <pre>rustc examples/workbench/workbench.rs -O -o ~/.local/bin/workbench</pre>

      <h2 id="told">What a tools program is told</h2>
      <p>Its settings come from the table named after the program itself, and ride on every spawn —
      there is no process alive between calls to send them to once.</p>
      <pre>magi.tools            = "workbench"
magi.workbench        = { quiet = true }   <span class="c">-- arrives as JSON in MAGI_TOOLS_CONFIGURE</span>
magi.workbench_sha256 = "…"               <span class="c">-- the bytes it must hash to, from magi doctor</span></pre>
      <p>For casper that is <code>magi.casper</code> and <code>magi.casper_sha256</code>, which is
      why a configuration written before roles existed still works: the default program’s table has
      the name it always had. The same value is also set as <code>CASPER_CONFIGURE</code>, which is
      what casper reads.</p>

      <h2 id="trust">Only your own configuration names one</h2>
      <p>A role’s program is started every turn with the session’s authority, which is more than a
      declared tool — and a project file is already refused a tool. So a <code>.magi.lua</code> that
      names a program for any role stops the session with a reason, rather than running what the
      checkout shipped beside itself. A project may still tune a sibling through its settings table;
      what is privileged is the name.</p>

      <h2 id="join">Writing one</h2>
      <p>Answer the family floor — <code>verbs</code> and <code>client</code>, in the reply shape —
      and the role’s core. Refuse the rest by name. There is no registration and no library to link:
      a library shared between these programs is the dependency the whole arrangement exists to
      prevent. The contract is <code>ROLES.md</code>, beside <code>FAMILY.md</code> in each of the
      four repositories.</p>
`,
});

PAGES.push({
  at: "guides/tools.html",
  section: "guide",
  nav: "writing a tool",
  title: "Writing a tool",
  blurb:
    "Drop a Lua file in a directory and it is in the next session. A declaration — a name, a " +
    "description, a parameter schema, and how the body is reached.",
  body: `
${plate("d-tools", "plate 04", "three sources, one registry, four ways to reach a tool")}

      <h2 id="where">Where the file goes</h2>
      <p>No entry point to edit, no manifest, no registration. Make the directory if it is not
      there:</p>
      <pre>~/.config/magi/plugin/yours.lua                        <span class="c">-- alphabetical, each on its own</span>
~/.local/share/magi/site/pack/*/start/*/plugin/*.lua   <span class="c">-- installed packages</span>
~/.config/magi/after/plugin/yours.lua                  <span class="c">-- the last word</span></pre>
      <p>The same three directories exist for <code>casper</code>, <code>melchior</code> and
      <code>balthasar</code>, holding their own registrars. Every registrar replaces by name, so
      the order <i>is</i> the precedence: <code>after/plugin/</code> is how you override something
      you did not write. Naming a file explicitly still works and is still the auditable case —
      <code>magi.load</code>, casper's <code>load</code> setting.</p>
${note("<b>A package you fetched does not run until you say so.</b> Files in your own <code>plugin/</code> directory are yours and run on sight; anything under <code>site/pack/</code> is held back until <code>magi acknowledge</code> records its digest, and held back again the moment it changes. Fetching is <code>git clone</code>; the idea is the lockfile.")}

      <h2 id="four">What a declaration owes</h2>
      <pre>magi.tool("branch", {
  description = "The git branch this directory is on.",
  parameters  = { type = "object", properties = {} },
  transport   = { kind = "lua" },        <span class="c">-- the body is the run below, in this VM</span>
  needs       = "run",                   <span class="c">-- read | write | run | reach</span>
  run = function(args)
    local out, err = magi.shell("git branch --show-current")
    if out == nil then return { content = err, is_error = true } end
    return { content = out }
  end,
})</pre>
${table(["field", "is"], [
  ["<code>description</code>", "what the model is told the tool does. This is the whole of how it decides to call it."],
  ["<code>parameters</code>", "JSON Schema for the arguments. The model is held to it before <code>run</code> is called."],
  ["<code>transport</code>", "how the body is reached. Not optional and no default — see below."],
  ["<code>needs</code>", "the permission verb this acts under. Omit it for a tool that touches nothing a person would want a say over."],
  ["<code>run</code>", "the body, for a <code>lua</code> transport. Returns <code>{ content = … }</code>, or <code>{ content = …, is_error = true }</code>."],
])}
      <p>There is no <code>os.execute</code> and no <code>io.popen</code> in the VM, and no
      <code>io</code> at all. <code>magi.shell</code> is the seam commands go through — the same
      ledger the shell tool passes, the same refusals — and <code>magi.fs.write</code> is the one
      for files. Both answer <code>nil, why</code> rather than raising.</p>

      <h2 id="transports">Four ways to be reached</h2>
${table(["transport", "is", "for"], [
  ["<code>lua</code>", "a body that runs in magi's own VM", "anything that is a few lines of logic"],
  ["<code>command</code>", "a program on <code>$PATH</code>, given the call as argv", "wrapping something that already exists"],
  ["<code>casper</code>", "<code>&lt;program&gt; run &lt;tool&gt;</code>, one exec per call", "whatever the tools role’s program offers — casper’s thirteen, unless <code>magi.tools</code> names another"],
  ["<code>builtin</code>", "compiled into magi", "the floor: <code>read</code>, <code>write</code>, <code>edit</code>"],
])}
      <p>The registry does not care which. One name, one entry, and the model sees the same
      declaration whichever way it is reached. A tool with a <code>run</code> and no transport is
      refused at load — the registry has no way to guess that the function is the point.</p>

      <h2 id="split">said and shown</h2>
      <p>A <b>casper</b> tool returns <code>said</code> and <code>shown</code> rather than
      <code>content</code>, and the split is the whole idea. <code>said</code> enters the
      transcript, is replayed on every subsequent request, and costs context every turn until the
      conversation is compacted. <code>shown</code> is drawn once and costs nothing.</p>
      <pre>casper.tool("patch", {
  description = "Show the difference between two files.",
  parameters  = { type = "object", properties = { old = { type = "string" } } },
  needs = "read",
  run = function(args)
    local done = casper.exec("diff", { "-u", args.old, args.new })
    return {
      said  = "3 files differ",                        <span class="c">-- the model reads this</span>
      shown = casper.paint.ansi(done.out, casper.theme), <span class="c">-- the person sees this</span>
    }
  end,
})</pre>
      <p>A tool that returns a hundred lines of diff as <code>said</code> has spent that budget for
      the rest of the session. The same diff as <code>shown</code>, with
      <code>said = "patched 3 files"</code>, costs four words. And a tool never names a colour: it
      says what its output <i>means</i> — <code>added</code>, <code>keyword</code>,
      <code>path</code> — and the harness resolves that against its own palette.</p>

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

      <h2 id="watch">Watching a session</h2>
      <p>The other registrar. A watcher is told after the fact and answers with nothing: it cannot
      change a result and cannot fail one, so observing a session is not a way to break it.</p>
      <pre>magi.watch("timing", {
  run = function(event)
    if event.kind ~= "turn.ended" then return end
    magi.fs.write(os.getenv("HOME") .. "/.local/state/magi/last", event.took_ms .. "ms\\n")
  end,
})</pre>
      <p>Branch on <code>event.kind</code> and nothing else. There are eight:
      <code>session.opened</code>, <code>turn.began</code>, <code>turn.ended</code>,
      <code>tool.finished</code>, <code>permission.asked</code>,
      <code>permission.answered</code>, <code>context.compacted</code> and
      <code>provider.retried</code>.</p>

      <h2 id="asking">A tool that asks a question</h2>
      <p>A declaration reads <code>args.answered</code> to know it is resuming. The answer travels
      <i>with</i> the arguments rather than beside them — merged, so a declaration writes
      <code>args.answered</code> and not <code>args.call.answered</code>. The answer is one more
      thing known about this call, which is what an argument is.</p>

      <h2 id="stable">What is stable</h2>
      <p><code>magi verbs</code> reports <code>surface</code>, which versions everything on this
      page. It is <b>1</b>. Adding a registrar, a field or an event does not move it — a file
      written against 1 keeps running. Renaming one, removing one, or changing what a field means
      does.</p>
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
      <p>The program holding it is whatever fills the <code>memory</code> role — balthasar unless
      <code>magi.memory</code> names another. <code>--resume</code> needs only the role’s core:
      <code>sessions</code> to find the newest run, <code>replay</code> to read it back. Both wait
      for a store that is still opening, rather than resuming into an empty conversation.</p>
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

      <h2 id="fork">A child of this session</h2>
      <pre>magi fork "review the parser" --role reviewer --role-description "reads diffs, writes none"</pre>
      <p>melchior names the child and mints the secret that makes it stoppable; magi starts the
      process. The child is told which session started it and leaves when that one does. It gets no
      more than its parent has — a child that wants something outside that is refused and told to
      ask its parent. A role given at birth is a label others can route by, and it grants
      nothing.</p>

      <h2 id="crew">The crew</h2>
      <p>A model reaches the other agents through one tool, whose verbs melchior answers on its
      <code>tool</code> door:</p>
${table(["verbs", "for"], [
  ["<code>list</code> <code>whoami</code> <code>about</code> <code>crew</code>", "who is here, who started whom, and what each is for"],
  ["<code>send</code> <code>ask</code> <code>reply</code> <code>inbox</code>", "talking — an answer can arrive long after the connection that carried the question has closed"],
  ["<code>claim</code> <code>claims</code> <code>release</code>", "saying what one is working on, so two agents do not both do it"],
  ["<code>assign</code> <code>task</code> <code>handoff</code>", "handing work to another agent, and keeping a handle on it"],
  ["<code>stop</code> <code>disband</code>", "ending a child, or a whole branch of them"],
])}
      <p>Every session publishes its screen beside its socket, so the one terminal you have moves
      from agent to agent rather than a window being opened per agent.</p>

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
      <p><b>It is the rows, and <code>n</code> is how many.</b> A verb that lists things puts each
      thing in <code>result</code> as its own value; it does not put the whole listing in as one
      value that is a list. <code>"result": [[…]]</code> with <code>"n": 1</code> is the mistake,
      and it is invisible from one side — one sibling sent every listing it had that way while the
      other three sent theirs flat, and the coordinator reading them row by row found an array
      where a declaration belonged and concluded it declared nothing at all.</p>

      <h2 id="version">Two version rules</h2>
      <p><code>family</code> is the revision of the wire a reply is written in. <b>A newer peer is
      refused by name; an older one is not.</b> A reply with no <code>family</code> at all is from
      before the check and is accepted.</p>
      <p><code>verbs</code> also carries <code>surface</code> — the revision of what a
      <i>third party</i> writes against. Two numbers, because they move for different reasons:</p>
${table(["", "versions", "read by"], [
  ["<code>family</code>", "the wire between these programs — the reply shape, the encodings, which verbs exist", "a sibling, or anything speaking to one"],
  ["<code>surface</code>", "the registrar names, the fields each declaration owes, what a callback is handed", "somebody's extension"],
])}
      <p>Both go up only when something already published stops working. Adding a registrar, a
      field, an event or a verb moves neither.</p>
      <p>The constants are duplicated in each sibling rather than shared. A crate held in common
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
      <p>These are the <code>memory</code> role’s verbs. The core three are what any memory
      layer owes; the rest it may refuse by name, and magi carries on with less — see
      <a href="../guides/roles.html">swapping a program</a>.</p>
${table(["verb", "does", "role"], [
  ["<code>observe</code>", "take a turn into this run's record, as it settles", "core"],
  ["<code>replay</code>", "everything a run said, in order", "core"],
  ["<code>sessions</code>", "which runs this project has had", "core"],
  ["<code>amend</code>", "revise a turn after it settled", "extension"],
  ["<code>recall</code> · <code>remember</code> · <code>forget</code> · <code>why</code>", "search, keep, let go, and show the evidence — the four a model is given as tools", "extension"],
  ["<code>scroll</code>", "a run's history a page at a time, so an elided tool result can be read back", "extension"],
  ["<code>plan</code>", "what to keep, mask, drop or summarise when the window is over budget", "extension"],
  ["<code>used</code> · <code>outcome</code>", "what a turn did with what it was given, and how that went", "extension"],
  ["<code>model</code> · <code>resume</code>", "which model a run talks to; where the store thinks it left off", "extension"],
])}
${note("<b><code>prompt</code>, <code>run</code> and <code>eval</code> are absent and stay absent.</b> A memory layer that can be told to run something is not a memory layer.")}

      <h2 id="melchior">melchior</h2>
${table(["door", "verbs"], [
  ["socket", "<code>identity</code> <code>tell</code> <code>inbox</code> <code>kin</code> <code>role</code> <code>status</code> <code>stop</code> <code>adopt</code> <code>adopted</code> <code>mint</code> <code>minted</code> — one program asking another session"],
  ["tool", "<code>whoami</code> <code>about</code> <code>list</code> <code>send</code> <code>ask</code> <code>reply</code> <code>inbox</code> <code>crew</code> <code>claim</code> <code>claims</code> <code>release</code> <code>assign</code> <code>task</code> <code>handoff</code> <code>disband</code> <code>stop</code> <code>role</code> <code>status</code> <code>attention</code> <code>trouble</code> <code>announce</code> <code>adopt</code> <code>help</code> — what a model calls"],
])}
      <p><code>identity</code> and <code>tell</code> on the socket are <code>whoami</code> and
      <code>send</code> on the tool door, and they are not aliases: one answers a program with a
      record, the other a model with a paragraph.</p>
      <p>No verb here runs anything, and melchior's own tests refuse one named <code>run</code>,
      <code>shell</code>, <code>exec</code> or <code>eval</code>.</p>

      <h2 id="casper">casper</h2>
${table(["command", "does"], [
  ["<code>tools</code>", "every tool it offers, as declarations a harness can register"],
  ["<code>run &lt;tool&gt;</code>", "one call, arriving as JSON on stdin"],
  ["<code>surface &lt;tool&gt;</code>", "hold rows on the harness's screen and exchange frames"],
  ["<code>verbs</code>", "what it answers, on each of its doors"],
])}
${note("<b><code>run</code> is deliberately not reachable over the socket.</b> casper's job is running programs, and a socket that runs commands is a remote shell wearing a friendly name. The spawn link carries the trust instead.")}

      <h2 id="both">Everywhere — the floor</h2>
      <p>Every program in the family answers these, in the reply shape, on its command line. A
      family where one program can be asked what it speaks and another cannot has stopped being
      one. <code>gate-family.sh</code> holds each of them to it on the merge path.</p>
${table(["", ""], [
  ["<code>verbs</code>", "what this program answers, and on which door. Everything it lists, it dispatches — that is one of the two rules that is tested rather than reviewed."],
  ["<code>client</code>", "the Lua client library for its surface, as source. A program whose surface is not reached from a VM still answers, saying so — silence is not parseable."],
  ["<code>acknowledge</code>", "clear the installed packages, so their declarations may run"],
  ["<code>--json</code> · <code>--cbor</code>", "which encoding the reply comes back in"],
])}

      <h2 id="coordinated">Coordinated — everything magi drives</h2>
${table(["", ""], [
  ["<code>needs</code>", "what a coordinator may tell this program, in its own vocabulary"],
  ["<code>configure</code>", "take that configuration, as Lua on stdin, and say what it did with each name"],
])}
      <p>magi answers neither: it coordinates rather than being coordinated, and there is nothing
      above it to hand it settings. A setting the far side does not recognise comes back
      <b>named</b> — "refused" without a name is not something a coordinator can act on.</p>
${note("<b>A setting a program declares must change something.</b> A <code>needs</code> entry that nothing reads is the same sin as a verb that is advertised and refused, one level down: a coordinator sets it, is told it was taken, and the behaviour never moves.")}
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
      --headless              <span class="c">serve with no terminal, reachable until something ends it</span>
      --role &lt;NAME&gt;           <span class="c">what this session is for, in one word; main when nothing says</span>
      --json | --cbor         <span class="c">which encoding a reply comes back in</span>

magi doctor                   <span class="c">what a session here would be made of, without starting one</span>
magi fork [PROMPT]            <span class="c">start a child session of this one, and print what it is called</span>
magi verbs                    <span class="c">what it answers, on each of its doors</span>
magi acknowledge              <span class="c">clear the installed packages, so they may run</span>
magi tools                    <span class="c">every tool the model can call, and how each is reached</span>
magi models                   <span class="c">the providers and models melchior knows about</span>
magi lua-api                  <span class="c">the Lua client library for magi's own surface</span>
magi ext &lt;kind&gt;               <span class="c">run a tool peer. not for people: magi spawns these itself</span>
magi fake-host                <span class="c">serve a recorded session, so the UI can be worked on without a model</span></pre>

      <h2 id="casper">casper</h2>
      <pre>casper tools                  <span class="c">every tool, with schemas</span>
casper run &lt;tool&gt;             <span class="c">one call on stdin, one result on stdout</span>
casper surface &lt;tool&gt;         <span class="c">frames both ways, for as long as it holds its rows</span>
casper verbs                  <span class="c">what it answers, on each of its doors</span>
casper needs                  <span class="c">what a coordinator may tell it</span>
casper configure              <span class="c">take that configuration, as Lua on stdin</span>
casper acknowledge            <span class="c">clear the installed packages, so their declarations may run</span>
  --json | --cbor             <span class="c">which encoding a reply comes back in</span></pre>

      <h2 id="melchior">melchior</h2>
      <pre>melchior models               <span class="c">what this machine could talk to</span>
melchior ask                  <span class="c">run a turn; an Ask on stdin</span>
melchior serve                <span class="c">bind this session's socket and answer for it</span>
  --project &lt;NAME&gt;            <span class="c">which project this session belongs to</span>
melchior needs                <span class="c">what a coordinator may tell it</span>
melchior configure            <span class="c">take that configuration, as Lua on stdin</span>
melchior fork                 <span class="c">a name and a secret for a session about to be started</span>
melchior tool --verb &lt;VERB&gt;   <span class="c">the coordination vocabulary a model calls, one exec per request</span>
melchior brief                <span class="c">what to tell a model about the sessions a prompt named</span>
melchior verbs                <span class="c">what it answers, on each of its doors</span>
melchior acknowledge          <span class="c">clear the installed packages, so their declarations may run</span>
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
balthasar replay              <span class="c">everything a run said, back out again</span>
balthasar export · import     <span class="c">every memory, one JSON object per line, and back</span>
balthasar outcomes            <span class="c">what a session reported, and how it went</span>
balthasar init                <span class="c">make this directory the root of its own memory</span>

balthasar serve               <span class="c">listen for other programs</span>
  --instance &lt;NAME&gt;           <span class="c">when more than one should be reachable at once</span>
  --scope &lt;SCOPE&gt;             <span class="c">global, project, or a path</span>
  --tied &lt;PID&gt;                <span class="c">end when that process ends, enforced by the kernel</span>
  --tool &lt;NAME&gt;               <span class="c">which tool the memory belongs to</span>
balthasar api &lt;VERB&gt; [ARGS]   <span class="c">answer one question, wire-shaped, and exit</span>
  --json | --cbor             <span class="c">which encoding a reply comes back in</span></pre>
${note("<b><code>--tied</code> is absent by default.</b> A balthasar started at a terminal or by a unit file is meant to outlive the thing that typed the command. magi passes it, naming its own process id, so the memory layer cannot outlive the window even if magi is killed outright.")}
`,
});

// ------------------------------------------------------------------------------ compared -----
// ------------------------------------------------------------------------------ compared -----
PAGES.push({
  at: "compared/index.html",
  section: "cmp",
  nav: "the originals",
  title: "Measured against two originals",
  blurb:
    "nerv was designed from two existing harnesses, both written in TypeScript. This compares " +
    "against those — and then against what happened when each was rewritten in Rust.",
  body: `
      <h2 id="three">The three systems</h2>
${table(["", "", ""], [
  ["<b>pi-ts</b>", "11 npm packages", "150,756 production lines, 6,286 commits. A package graph held by the npm resolver, on the critical path of every build."],
  ["<b>deepseek-ts</b>", "255 packages", "307,345 lines, 15,210 commits, plus a vendored dependency-injection framework and 989 rows of YAML that decide what is assembled."],
  ["<b>nerv</b>", "25 crates, 4 repos", "72,532 lines at the time of measurement, 407 commits, nine days old. Four programs that share no code."],
])}
${note("<b>Nine days against fifteen thousand commits.</b> Every claim below of the form “this discipline has held” is a prediction, and the discount cuts both ways: nerv accumulated six dead dependency edges out of fifty-nine in nine days, which is a faster drift rate than deepseek-ts's 282 of 1,304 over 15,210 commits. Claims about what the compiler <i>refuses</i> are not subject to it.")}

      <h2 id="glance">At a glance</h2>
      <p>Every number measured on the checkouts, not read off documentation.</p>
${table(["", "pi-ts", "deepseek-ts", "nerv"], [
  ["unit", "npm package", "npm package", "cargo crate"],
  ["units", "11", "255", "25, in 4 workspaces"],
  ["median unit size", "1,966", "<b>549</b>", "2,138"],
  ["largest unit", "<b>70,067</b>", "15,593", "9,004"],
  ["largest file", "6,592", "6,443", "<b>783</b>"],
  ["files ≥ 800 lines", "48 of 667", "50 of 1,592", "<b>0 of 421</b>"],
  ["build ceremony per unit", "77 lines", "95 lines", "<b>20 lines</b>"],
  ["declared edges per kLOC", "0.14", "<b>4.24</b>", "0.81"],
  ["undeclared test edges", "4 sites", "<b>76, across 50 packages</b>", "<b>0 — structurally impossible</b>"],
  ["lines compiled to test one unit", "a whole package — up to 70,067", "~22,000", "<b>~8,200</b>"],
  ["what refuses an undeclared edge", "a script, at pre-commit and in CI", "a gate that <b>writes the edge into your manifest</b>", "<b>the compiler, always</b>"],
])}

      <h2 id="verdict">The verdict, in one sentence</h2>
      <p>nerv owns <b>the only module boundary of the three that cannot be crossed by accident</b>,
      and — at the time of the analysis — the only enforcement tier that ran nowhere but a
      developer's laptop.</p>
      <p>Verified by writing the violation rather than reasoning about it:</p>
      <pre>error[E0433]: failed to resolve: use of unresolved module or unlinked crate <span class="a">magi_host</span></pre>
      <p>In pi-ts the same violation type-checks clean and fails at a consumer's runtime. In
      deepseek-ts it type-checks clean through a match-all alias map, and the gate's remedy is to
      <b>add the edge to your manifest for you</b>. Across programs it is stronger still: no
      manifest in the four workspaces names a sibling, so violating that boundary means editing a
      different repository.</p>

      <h2 id="deeper">Read on</h2>
${table(["", ""], [
  ['<a href="rewrite.html">what survived the rewrite</a>', "both originals were rewritten in Rust. Only the boundaries that were already <i>data</i> came through — which is the most useful thing in this comparison."],
  ['<a href="modularity.html">what a module is</a>', "units, edges, and what refuses a violation at each of the three"],
  ['<a href="permissions.html">three bets on safety</a>', "permission models, and what auditing ours found"],
  ['<a href="providers.html">where vendor knowledge lives</a>', "one question, and a tenfold difference in what the answer costs"],
  ['<a href="extending.html">extending it</a>', "the question a module graph does not answer: how does somebody who is not the author change what this does?"],
])}
`,
});

PAGES.push({
  at: "compared/rewrite.html",
  section: "cmp",
  nav: "what survived",
  title: "What survived the rewrite",
  blurb:
    "Both originals were rewritten in Rust. Comparing each pair is a controlled experiment in " +
    "which kinds of boundary survive a change of language — and the answer is narrow.",
  body: `
      <h2 id="what">What happened to each</h2>
${table(["", "before", "after"], [
  ["<b>pi</b>", "11 npm packages, 150,756 lines", "<b>one crate.</b> 145 <code>pub mod</code>, no workspace key, and a single 36,158-line file."],
  ["<b>deepseek</b>", "255 packages and a vendored DI framework, 307,345 lines", "20 crates, 8,390 lines, in two commits. The framework reduced to one trait that always says no."],
])}
      <p>deepseek's 39-fold shrink measures <b>scope abandoned</b>, not modularity won — its own
      README says as much: <i>“This is not a Cordis port.”</i> pi's is the interesting one, because
      nothing was abandoned. The packages simply stopped existing.</p>

      <h2 id="why">Why pi's boundary evaporated</h2>
      <p>pi-ts's package boundary was not held by discipline or by review. It was held by <b>the npm
      resolver</b>, which sits on the critical path of every build, plus a script that parsed every
      build program with the compiler's own API — at pre-commit <i>and</i> in CI.</p>
      <p>Rust has exactly one construct with that resolver property, and it is the crate.
      <b>Inside a crate there is no resolver at all.</b> So the rewrite did not weaken the
      eleven-package graph; it deleted it. Violating any conceptual boundary in pi today costs
      seven keystrokes and nothing fails.</p>
      <p>The measurement: under nerv's own hygiene rules, pi now holds a mutually recursive core of
      <b>23 modules</b> on the strict reading and 57 on the broad one.</p>
${note("<b>And pi is not a project that skipped its gates.</b> Its module-reachability check runs in CI and passes cleanly at 240,000 lines: 144 declared, 141 reachable, 0 unreachable. It built the <b>reachability</b> gate and never built the <b>direction</b> gate — and a 57-module cycle is maximally reachable. nerv's own <code>gate-reachable</code> has exactly the same blind spot, which is why <code>gate-cycles</code> was written.")}

      <h2 id="invariant">The invariant</h2>
      <p><b>Only the boundaries that were already data survived.</b> The npm package graph, the
      entry-file budgets, the dependency-injection container, the import-closure verifier — deleted,
      stubbed, or rebuilt at a fraction of their expressiveness. What translated intact was
      <i>declared dependencies between compilation units</i>, because Cargo implements it, and a
      YAML patch file, because it is a file.</p>
      <p>Which puts a sharp question to nerv: what here is data?</p>
${table(["", "would survive a rewrite"], [
  ["the Lua layer — 9,034 lines across four programs", "<b>yes.</b> Tool declarations, provider catalogs, wire protocols and client stubs are files, not code."],
  ["the socket and pipe protocols", "<b>yes.</b> A shape on a wire is a shape on a wire."],
  ["the crate graph inside each program", "only if the next language has a resolver at that granularity"],
  ["the module structure inside a crate", "<b>no.</b> This is exactly what pi lost."],
])}
      <p>The Lua layer is the closest thing in any of the six trees to the one deepseek-ts mechanism
      that came through its rewrite intact. That is an argument for putting more in it, not less.</p>

      <h2 id="unit">The unit you pick is permanent</h2>
      <p>pi chose <code>pub mod</code> in its first commit. Five thousand commits later there is no
      path back — nothing in the tree even discusses the alternative. A crate costs twenty lines of
      manifest.</p>
      <p>nerv's own tree shows the same force at work: <b>the two programs with production module
      cycles are exactly the two with no gates</b>. That is not a coincidence about those two
      programs; it is what happens wherever nothing refuses.</p>
`,
});

PAGES.push({
  at: "compared/modularity.html",
  section: "cmp",
  nav: "what a module is",
  title: "What a module is",
  blurb:
    "Three systems, three units, three things that refuse a violation — and only one of them " +
    "refuses at compile time.",
  body: `
      <h2 id="refuses">What refuses a violation</h2>
${table(["", "the unit", "what refuses", "when"], [
  ["<b>pi-ts</b>", "npm package", "a script parsing every build file with the compiler API", "pre-commit <b>and</b> CI <b>and</b> publish — the same nine-step chain in all three"],
  ["<b>deepseek-ts</b>", "npm package", "a gate that checks the manifest against real imports", "CI only — and its remedy <b>rewrites your manifest to match</b>"],
  ["<b>nerv</b>", "cargo crate", "<b>the compiler</b>", "every build, always. There is no mode in which it does not."],
])}
      <p>pi-ts's is the discipline worth envying: because every rule runs at commit time and not
      only in CI, its 21-edge graph has <b>zero cycles</b>, no relative import escaping a package,
      and declared dependencies matching actual imports exactly. nerv's declared graph was ten
      per cent fiction at the time of measurement — six declared-but-never-imported edges of
      fifty-nine.</p>

      <h2 id="below">Nothing constrains anything below the crate</h2>
      <p>This is the honest gap. Cargo enforces the crate edge and enforces nothing inside it, so a
      single crate can grow any shape it likes. pi-ts constrains boundary <i>depth</i> on a walked
      graph with a stated cost model, and can mark a subtree as excluded-from-build-but-imported —
      making it a boundary rather than a comment. nerv has no equivalent.</p>
      <p>What nerv legislates instead is <b>one ceiling: files</b>, at 800 lines, and it holds
      across every file in every repository. But deepseek-ts keeps 97% of its files under 800 with
      <b>no file-size gate at all</b> — so the rule buys the absence of a long tail rather than a
      better median. And the <i>unit</i> is unruled: two crates are half of magi.</p>
${note("<b>A number that was reported wrongly the first time.</b> Build ceremony was quoted as 31.7% against 0.8% until it was checked — three-quarters of that gap was READMEs and translations, which scores nerv's <i>absence of documentation</i> as a win. Like for like it is 20 lines per crate against 57 per npm package. A comparison that faults undocumented seams elsewhere cannot also bank their absence as a saving.")}

      <h2 id="test">What a test can reach</h2>
      <p>The sharpest measurable difference, and the one that compounds daily.</p>
${table(["", "to test one unit, this compiles"], [
  ["pi-ts", "the whole package — up to <b>70,067 lines</b>"],
  ["deepseek-ts", "about <b>22,000</b>, a median of eighteen packages"],
  ["nerv", "about <b>8,200</b>, a median of two crates — and all 25 pass their suites alone"],
])}
      <p>A test's reach here is exactly its declared dependencies and dev-dependencies. It is not a
      convention: there is no way to import something you did not declare. deepseek-ts has
      <b>76 undeclared test edges across 50 packages</b>, because its gate does not glob the test
      tree.</p>

      <h2 id="process">What a process boundary buys that a package edge cannot</h2>
      <ul class="plain">
        <li><b>Absence as an ordinary value.</b> A missing sibling returns an empty list or a
        <code>None</code>, not an error path — so “not installed” is the same shape as “nothing to
        say”.</li>
        <li><b>A typed refusal.</b> Four faults where an in-process call has one result, and a
        method separating “this cost you a feature” from “this cost you a turn”.</li>
        <li><b>Authority split by link.</b> casper answers read-only verbs on its socket and will
        run a command only when spawned. The same program, two different authorities, decided by
        how you reached it.</li>
      </ul>
      <p>The whole cross-program surface in magi is 1,632 lines — under five per cent of
      production — carrying in one crate what deepseek-ts spreads across seventeen.</p>
`,
});


PAGES.push({
  at: "compared/extending.html",
  section: "cmp",
  nav: "extending it",
  title: "Extending it",
  blurb:
    "The question a module graph does not answer: how does somebody who is not the author change " +
    "what this does? Three systems, three units of extension.",
  body: `
      <h2 id="unit">Three units</h2>
${table(["", "the unit", "machinery", "shipped content"], [
  ["<b>pi</b>", "a JavaScript file", "~160,000 lines — an embedded engine, a Node compatibility layer, a capability policy, a package manager", "107 embedded modules, ~78 example extensions"],
  ["<b>deepseek</b>", "a Rust crate", "~800 lines. Its plugin port has exactly one implementor, named <code>UnavailablePluginRuntime</code>", "none"],
  ["<b>nerv</b>", "a <b>Lua declaration</b>", "four VMs, one sandbox each — a removal list, not a permission model", "~9,000 lines of Lua, examples in every repository"],
])}
      <p>deepseek documents a plugin seam and ships the “unavailable” answer for it. That is
      honest, and it is the whole story. pi is thirteen times our size and is the only one of the
      three that has actually been extended by strangers — which is the fact worth taking
      seriously, and the reason for everything below.</p>

      <h2 id="reach">What a third party can reach</h2>
${table(["", "and how"], [
  ["a tool", "<code>magi.tool</code>, or <code>casper.tool</code> for one that runs a program"],
  ["a watcher", "<code>magi.watch</code> — eight events, told after the fact, answering nothing"],
  ["a wire protocol", "<code>melchior.api</code>. The registry is readable, so a dialect that differs from a shipped one in one function borrows the other three"],
  ["a provider", "<code>melchior.provider</code> — an endpoint, a credential, and either a model list or <code>discover = true</code>"],
  ["a memory source", "<code>balthasar.source</code>. No Rust file in balthasar names a harness; a new one is a file, not a release"],
  ["what a model is told", "<code>balthasar.section</code> — weight, order, filter, and a confidence floor"],
])}

      <h2 id="where">Where it goes</h2>
      <p>neovim's runtimepath, unchanged, in all four. Twenty years of real plugins have been
      written against it and most people arriving already know it; deviating buys nothing and
      costs everyone the transfer.</p>
      <pre>~/.config/&lt;program&gt;/plugin/*.lua                        <span class="c">alphabetical, each on its own</span>
~/.local/share/&lt;program&gt;/site/pack/*/start/*/plugin/*.lua  <span class="c">installed packages</span>
~/.config/&lt;program&gt;/after/plugin/*.lua                  <span class="c">the last word</span></pre>
      <p>Every registrar replaces by name, so the order <i>is</i> the precedence. No manifest, no
      registration, no entry point to edit — requiring an edit to your own <code>init.lua</code> to
      enable somebody's package makes every package a merge conflict with your configuration.</p>

      <h2 id="contain">What contains it</h2>
      <p>pi gives its extensions a default grant of read, write, http, events and session, and
      never asks. It has a capability policy because it embedded a language that can do anything;
      the policy exists to take that back.</p>
      <p>nerv never handed it over. The sandbox is a removal list — <code>os.execute</code>,
      <code>io.popen</code>, <code>io</code> entirely, <code>require</code>, <code>dofile</code>,
      <code>loadfile</code> — applied to the VM before any file runs. What is left cannot spawn or
      touch a file. Running a command goes through the same ledger the shell tool passes; writing
      one goes through the same gate the write tool passes. <b>A discovered file is held to exactly
      what a named one is.</b></p>
${note("<b>The inversion that made this urgent is closed.</b> For a while the one program loading third-party packages was the one VM still keeping <code>os.execute</code>. The removal list applies in all four now, and discovery arrived after it rather than before.")}

      <h2 id="trust">What a package costs to trust</h2>
      <p>pi's package manager is 8,579 lines: npm and git sources, user and project scopes, a
      lockfile with digests and trust states. Most of that is a package ecosystem nobody here
      wants to be in. The ten per cent worth having is the part about <i>trust</i> rather than
      fetching, and it is what pi conspicuously does for MCP servers and not for its own
      extensions.</p>
${table(["", ""], [
  ["a file you wrote", "runs on sight. A prompt about your own configuration is one nobody reads — it trains people to say yes."],
  ["a package you fetched", "held back until <code>&lt;program&gt; acknowledge</code> records its SHA-256, and held back again the moment it changes"],
])}
      <p>Fetching is <code>git clone</code>. The lockfile is the idea. A manifest that will not
      parse reads as empty, which holds everything back rather than letting everything through.</p>

      <h2 id="stable">What is promised</h2>
      <p><code>&lt;program&gt; verbs</code> reports <code>surface</code>, separate from
      <code>family</code>: one versions the wire between these programs, the other versions what an
      extension is written against. Both move only when something already published stops working.</p>
      <p>Five registrars were published, dead and unversioned for most of this project's life. A
      number an extension can read is what closes that window deliberately rather than by
      accident — and the examples in every repository are run by that repository's own test suite,
      because an example that does not load is worse than no example.</p>
${note("<b>Still ahead of us.</b> pi's ~78 example extensions are not documentation; they are how it knows the surface works, and ours has been used by nobody who did not write it. That is the measurement this section cannot yet make.")}
`,
});
PAGES.push({
  at: "compared/permissions.html",
  section: "cmp",
  nav: "permissions",
  title: "Three bets on safety",
  blurb:
    "pi bet on breadth plus in-process hardening. deepseek bet on layering, and has no " +
    "permission layer at all. nerv bet on the question a tool is made to ask. Measured against " +
    "the Rust ports, which is where these layers are comparable at all.",
  body: `
      <h2 id="shape">The shape of each</h2>
${table(["", "pi", "deepseek", "nerv"], [
  ["permission model", "3 global modes, allow or deny, not persisted", "<b>none</b>", "4 verbs × 5 widths, with a session ledger"],
  ["dangerous-command analysis", "a shell-out, or ten in-tree danger classes", "none", "<b>none</b>"],
  ["OS sandbox", "<b>none</b>, in 527k lines", "none", "<code>bwrap</code>, through the process transport"],
  ["secrets masking", "mask, restore for the human, re-mask on the way out", "none", "masked by value before anything is journalled"],
  ["path confinement", "<code>O_NOFOLLOW</code>, re-stat the descriptor, reject if it moved", "lexical prefix, no canonicalise", "lexical normalise, then prefix"],
  ["tool declaration", "one implementation <b>per tool</b> — 38 of them", "one per tool", "one <b>per transport</b> — five"],
])}

      <h2 id="transport">One implementation per transport</h2>
      <p>That last row is nerv's one genuinely better idea, and it is architectural rather than
      stylistic: <b>adding a way to reach a tool cannot add a way to run one.</b> Every
      cross-cutting concern lives at a single funnel, and there is exactly one place to put it —
      the output cap, the schema check, the argument repair, the secrets mask.</p>
      <p>pi's equivalent of the output cap is seven hundred lines of spill machinery <i>inside</i>
      its tool file, with its own redaction engine, because pi's tools each produce output
      independently. deepseek has no cap at all.</p>

      <h2 id="injection">The claim, and its limit</h2>
      <p>nerv's <code>command</code> transport runs a program with an <b>argument vector</b> built
      from the call. No shell, so a value containing <code>;</code> or <code>$(…)</code> is one
      argument, verbatim. It is the only one of the three where the default way to declare a new
      tool cannot be command-injected.</p>
      <p><b>That is a claim about the transport, not about the shipped tools.</b> The shell tool
      nerv actually ships is a Lua declaration that interpolates the model's string into a
      compound <code>sh -c</code>. It is a shell string end to end, exactly like pi's and
      deepseek's. Both facts belong in the ledger.</p>

      <h2 id="widths">Why five widths</h2>
      <p>One request can be answered at several widths, because how much you want to grant depends
      on what was asked. Saying yes to <i>this exact command, once</i> and yes to <i>anything under
      this directory, forever</i> are both reasonable answers to the same prompt — and a system
      offering only one of them will be answered carelessly.</p>
      <p>pi has three global modes and no persistence, so “allow always” is not expressible; the
      pressure that creates is toward the mode that stops asking. deepseek asks nothing.
      <a href="../guides/permissions.html">The widths are set out here.</a></p>

      <h2 id="found">What auditing this found</h2>
      <p>The design being the best of the three did not stop the implementation being weaker than
      it reads. Three holes were verified by running them, not by reading:</p>
      <ul class="plain">
        <li><b>A directory grant compared unnormalised paths</b>, so a grant on <code>work</code>
        covered <code>work/sub/../../secret</code>. Fixed: paths are normalised before the action
        is built.</li>
        <li><b>Confinement was silently dropped whenever anybody was watching.</b> It applied only
        to headless sessions — the exact case where nobody is there to catch anything. Fixed.</li>
        <li><b>A grant on <code>git</code> covered <code>git status; rm -rf /</code></b>, because
        the program was the first word and the command line sat in the rest. Fixed: a command
        carrying a shell metacharacter is covered by no program grant, so it is asked about
        instead.</li>
      </ul>
${note("<b>That last one was published on this site as already true before it was.</b> It was written from the design and never checked against the code. It is true now — a grant that answers “any <code>git</code> command” stops at the first <code>;</code> — and the way it was found is the argument for the whole exercise: pi's equivalent check is about fifteen lines and six tests, and reading it is what exposed the gap.")}

      <h2 id="still">Still open</h2>
      <ul class="plain">
        <li><b>Nothing analyses a command before running it.</b> nerv decides whether an action is
        permitted, not whether it is wise. pi has ten danger classes.</li>
        <li><b>A grant on <code>sh</code> is an unbounded shell by construction</b>, not by
        bypass — which is what the person asked for, and worth knowing they asked it.</li>
        <li><b>Automatic approvals are not audited.</b> A ledger hit returns quietly, so “what did
        this session do under standing grants” has no answer. pi audits every decision, including
        the ones nobody saw.</li>
        <li><b>File opens are not hardened against the race.</b> Lexical normalise, then read. pi
        canonicalises, opens with <code>O_NOFOLLOW</code>, re-stats the descriptor and refuses if
        it moved.</li>
      </ul>
`,
});

PAGES.push({
  at: "compared/providers.html",
  section: "cmp",
  nav: "providers",
  title: "Where the vendor knowledge lives",
  blurb:
    "One question — where does the knowledge of how to talk to a vendor live? — and a tenfold " +
    "difference in what the answer costs. Measured against the Rust ports.",
  body: `
${table(["", "pi", "deepseek", "nerv"], [
  ["where it lives", "in-process: thirteen protocol modules and a 103-row table", "one crate behind a port trait", "a separate program, spawned per turn"],
  ["size", "~9,700 production lines", "1,121 lines", "~5,300 production lines, plus 943 of Lua"],
  ["providers shipped", "103 — 88 of them pure data", "1", "8"],
  ["wire protocols", "13 native modules", "1", "8 Lua tables"],
  ["adding a compatible provider", "~17 lines of Rust data, then recompile", "not a supported operation", "~10 lines of Lua, no rebuild"],
  ["adding a <b>new protocol</b>", "a module, a route kind, a normaliser, recompile", "a new crate", "<b>a <code>do … end</code> block, no rebuild</b>"],
  ["HTTP", "hand-rolled HTTP/1.1, 3,034 lines", "a library", "a library"],
  ["does it stream", "yes", "<b>no</b>", "yes, end to end, across the pipe"],
  ["credential store", "13,156 lines: four OAuth flows, an AWS chain, an SSO cache, a rotation ring", "environment variables, 83 lines", "environment variables and one OAuth store"],
])}

      <h2 id="same">The same shape, at a tenth of the cost</h2>
      <p>pi and nerv arrive at structurally similar layers — a catalog of vendors as data, a small
      set of protocol adapters, one neutral message model. pi pays roughly ten times for it, and
      <b>most of that is not the process boundary</b>. It is the difference between “a protocol is
      a Rust module” and “a protocol is a Lua table”.</p>
      <pre><span class="c">-- melchior/config/providers.lua — one provider, no rebuild</span>
melchior.provider("deepseek", {
  name = "DeepSeek", api = "openai-completions",
  base_url = "https://api.deepseek.com",
  auth = { kind = "api-key", vars = { "DEEPSEEK_API_KEY" } },
  compat = { thinking_format = "deepseek" },
  models = { { id = "deepseek-chat" } },
})</pre>

      <h2 id="best">The best idea in pi's provider layer</h2>
      <p>Its table feeds everything else, including predicates that would otherwise be hardcoded
      lists — “is this provider keyless” is <i>derived</i> from having no auth variables and no
      auth header, so local runtimes work without being named anywhere — and including the
      published documentation, rendered from the same table with a golden test on the output.
      That is cheap and worth having.</p>

      <h2 id="ours">What the separate process is for</h2>
      <ul class="plain">
        <li><b>One parser for every provider's stream</b>, on a correct argument, rather than four.</li>
        <li><b>A typed failure class that reaches the loop and changes what the loop does</b> —
        rather than a regular expression over the vendor's prose.</li>
        <li><b>Retry and retraction as one end-to-end contract</b>: the screen is told to un-draw
        what a failed attempt already streamed. Neither of the others has this.</li>
        <li><b>Three protocol hostings sharing one body</b>, differing in about ten lines. pi's
        equivalent for one vendor is 1,882.</li>
      </ul>
${note("<b>What was deliberately not taken:</b> the 103-row table itself, the hand-rolled HTTP client, the failover chains, the credential-rotation ring, and the credential scavenging that reads other agents' configuration files. Seven providers answer the same question, and the eighth costs ten lines.")}
`,
});
