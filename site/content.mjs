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
          <p>The one you run. Holds the conversation, the screen, the registry and who decides
          what may run — and runs no tool of its own. Everything else it asks the other three.</p>
          <a href="programs/magi.html">what it owns →</a>
        </div>
        <div class="card">
          <h4>casper</h4><div class="role">tools · the jail</div>
          <p>Nineteen tools, MCP servers in both directions, and the kernel jail every command runs
          in. It knows nothing about models, turns or transcripts.</p>
          <a href="programs/casper.html">what it owns →</a>
        </div>
        <div class="card">
          <h4>melchior</h4><div class="role">the model · other agents</div>
          <p>Which providers exist, what credential each takes, what a run has spent, and how one
          session reaches another. It does not know what a harness is.</p>
          <a href="programs/melchior.html">what it owns →</a>
        </div>
        <div class="card">
          <h4>balthasar</h4><div class="role">memory · the context</div>
          <p>What every request holds, what happened this session, what is true, and how things
          are done here. Its own store, its own process, and it never calls a model.</p>
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
  ['<a href="guides/permissions.html">what may run</a>', "four modes, three kinds of rule, and the jail every command runs in"],
  ['<a href="guides/tools.html">write a tool</a>', "a few fields of Lua, read on the next call — nothing is compiled in"],
  ['<a href="guides/skills.html">skills</a>', "a Markdown workflow, picked with <code>/skill</code>, that grants nothing"],
  ['<a href="guides/mcp.html">MCP</a>', "outside servers as tools, and casper's own tools as a server"],
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
        <li><b>Every sibling but the memory layer is optional.</b> Without casper a session has no
        tool that touches the machine — magi keeps only <code>spawn</code> and the tools that
        reach its siblings. Without melchior it has no model and no other agents, and runs and says
        so. Without a memory layer it does not start: that layer is the store, and a session that
        cannot record is refused rather than run on a copy that goes stale.</li>
        <li><b>Linux only, and that is a decision.</b> Peer identity comes from
        <code>SO_PEERCRED</code>, which means there is no handshake token to design, issue or
        leak.</li>
        <li><b>One shape, two encodings.</b> JSON for anything a person might read; CBOR for a
        caller that is only going to parse it. Nothing is negotiated — a body says which it is in
        its first byte.</li>
      </ul>
${note("<b>magi is the only command.</b> It starts a balthasar and a melchior for each session and ends both, and runs casper once per tool call — or keeps one <code>casper serve</code> for the session, if you ask it to. There is no daemon to launch and no unit file to install.")}
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
  ["magi → casper", "magi, once per tool call — or one <code>serve</code> for the session", "the call as argv and stdin, or over a keyed socket; the result back", "no tool touches the machine. magi keeps <code>spawn</code> and the tools that reach its siblings."],
  ["magi → melchior", "magi, once per session", "what the session is doing, up; what the model said, what it cost, and who is calling, down", "no model and no siblings — the session runs and says so"],
  ["magi → balthasar", "magi, once per session", "every entry out; the layout of each request, and the jobs its helpers should run, back", "no session: magi refuses to start, because this is the store and there is no journal to fall back to"],
  ["session → session", "either, through melchior", "messages, questions, reports and answers between agents", "a session with no siblings, which is the ordinary case"],
  ["front end → session", "the front end — the terminal, a second screen, or an editor over ACP", "what was typed, up; everything to draw, down", "a <code>--headless</code> session keeps running; attach to it again with <code>--attach</code>"],
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
${note('<b>A second implementation is what keeps a protocol honest.</b> magi’s repository carries a second memory layer and a second tools program, each one file of Rust written from the contract rather than from magi’s source, and both run against real sessions in its test suite. A protocol with one implementation is a function call with extra steps — see <a href="../guides/roles.html#proof">swapping a program</a>.')}
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
      bytes, and never more than 16 MiB in any of the four. Self-delimiting, so a peer that dies
      mid-frame is caught at the length rather than misparsed deeper in — and a writer checks the
      size before it sends, so the reader is never the first to find out.</p>

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
  ["<code>socket</code>", "a bound socket, for anything that may knock", "melchior and balthasar, one each per session — and casper under <code>serve</code>, for the one session that started it. magi's own socket speaks magi's wire, not this one."],
  ["<code>tool</code>", "the vocabulary a model calls, one exec per request — <code>melchior tool --verb X</code>", "melchior, for coordination"],
])}
      <p>A socket that changes something asks for a key. balthasar's writes and every call to
      casper's <code>serve</code> carry the one the program was handed on stdin when it started,
      or the one it minted beside its socket; reading needs none. The kernel still names the
      caller, and the key says which session's caller it is.</p>
${note("<b>casper's socket runs commands, and that was argued against here for a long time.</b> A socket that runs commands is a remote shell wearing a friendly name — unless it can run nothing its spawner could not. So the jail is fixed when <code>serve</code> starts, by whoever started it, and no call can name another; only that session holds the key. What the socket buys is an MCP server's session that survives between calls.")}
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
  ["observe", "the handover is waited for before the next layout, up to a minute", "the entry is still in the window; only the durable record is lost."],
  ["layout", "yes — two seconds per request", "the last layout, extended by what was said since — or, with none, the whole live conversation."],
  ["ask", "no — a turn takes as long as it takes. A run past its spending cap is refused unsent.", "there is no answer, and the session says so. A request is tried up to four times first."],
  ["a tool call", "per tool", "the failure is handed back to the model as the result, not raised."],
  ["outcome", "a quarter of a second", "balthasar learns nothing from this turn. Nothing else changes."],
])}

      <h2 id="ledger">The model never reaches anything</h2>
      <p>It emits a request naming a tool. magi decides whether it may run — or the mode it is in
      decides who is asked — and casper runs it, inside the jail magi chose. Nothing the model says
      becomes an action without passing the ledger — see
      <a href="../guides/permissions.html">what may run</a>.</p>

      <h2 id="window">What the model is actually sent</h2>
      <p>Not the transcript verbatim, and not magi's choice. Before every request magi asks
      balthasar for a <b>layout</b>, and renders what comes back. In the order the prompt cache
      wants it:</p>
      <ul class="plain">
        <li>the system message — what magi is, the date, this session's directory and platform,
        and the project's <code>AGENTS.md</code>.</li>
        <li>every tool declaration the registry holds that is not deferred, as a schema the model
        can call. The rarely needed ones are behind casper's <code>tools</code> manual.</li>
        <li><b>rules</b>, on the user's channel: standing instructions a person actually gave,
        each checked against the line they gave it in.</li>
        <li><b>observations</b> and the <b>catalog</b>, as helper context: what was noticed, and
        one line per thing the project holds as true — with the last line saying whether that is
        everything.</li>
        <li>the conversation — word for word, a tool result cut to a stub, or a stored
        <b>summary</b> where a span of it was.</li>
        <li><b>memory</b>, just before the latest prompt: what is current, stated, and what is
        merely on record, hedged under a heading that says so.</li>
      </ul>
${note('<b>balthasar decides, and never calls a model.</b> When a summary is due, notes could be drawn from a turn, or two claims disagree, the layout hands magi a <i>job</i> — an instruction, an input, a schema — and magi runs it on a helper model and hands the answer back. See <a href="../guides/memory.html">memory</a>.')}
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
  ["balthasar", "<code>serve --instance &lt;session&gt; --scope project --tied &lt;pid&gt;</code>, on a socket, with its key on stdin", "killed on the way out, <b>and</b> by the kernel if that never runs"],
  ["melchior", "<code>serve --project &lt;p&gt; --ui</code>, on a pipe", "magi closes the pipe and it leaves — and it leaves too when magi is killed outright and closes nothing"],
  ["casper", "<code>run &lt;tool&gt;</code>, once per call — or <code>serve --at &lt;socket&gt;</code> once, when <code>MAGI_TOOLS_DOOR=library</code>", "a call exits on its own; a <code>serve</code> ends with the session. Neither outlives the magi that asked, and neither does a program a call started."],
  ["a child session", "<code>magi fork</code>, or a model calling <code>spawn</code>: its own magi, named by melchior", "the session that started it. The child is told its parent’s pid and leaves when it goes; the parent holds the secret that stops it sooner."],
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

      <div class="unit-head"><h4>magi</h4><span class="role">harness — ui, host, turns, the registry</span>
        <span class="meta" id="meta-magi"></span></div>
      <div class="graph" id="g-magi"></div>
      <div class="unit-head"><h4>balthasar</h4><span class="role">memory, in its own process</span>
        <span class="meta" id="meta-balthasar"></span></div>
      <div class="graph" id="g-balthasar"></div>
      <div class="unit-head"><h4>melchior</h4><span class="role">the model, and other agents</span>
        <span class="meta" id="meta-melchior"></span></div>
      <div class="graph" id="g-melchior"></div>
      <div class="unit-head"><h4>casper</h4><span class="role">tools, the jail, and the screen they draw on</span>
        <span class="meta" id="meta-casper"></span></div>
      <div class="graph" id="g-casper"></div>

      <h2 id="gates">What holds the shape</h2>
      <p>Every one of these runs on the way to <code>main</code>. Each repository runs its own
      set, because each has its own way to go wrong; the last column says where.</p>
${table(["gate", "what it forbids", "in"], [
  ["no cycles", "two top-level modules that depend on each other. This is what a reachability check cannot catch: a cycle is maximally reachable.", "all four"],
  ["one wire", "a second way of saying the same thing across a boundary", "all four"],
  ["800 lines", "a source file bigger than one sitting", "all four"],
  ["hermetic", "anything left behind anywhere a test may write, checked under a root of its own", "all four"],
  ["comments", "a comment longer than a fifth of the code it describes", "all four"],
  ["one Lua VM", "a second Lua VM in a program, or one that is not sandboxed", "all four"],
  ["family", "a program that does not answer the family floor, or advertises a verb it does not dispatch — asked of the binary", "all four"],
  ["roles", "a program named for a role that does not answer that role’s core verbs — asked of the binary, not read from the source", "all four"],
  ["no dead weight", "a declared dependency the code does not use", "all four"],
  ["independence", "any file in a sibling naming a harness", "the three siblings"],
  ["modules", "a file nobody declares — not a compile error, not a warning, and never run", "all but balthasar"],
  ["reachable", "a crate the shipping binary does not reach", "magi"],
  ["one store", "a second copy of a session's history: balthasar holds it, and magi keeps none", "magi"],
  ["no unsafe", "<code>unsafe</code> anywhere, and a lint any crate turns back off", "magi"],
  ["twins", "magi’s and melchior’s copies of the model wire drifting apart — the one gate that needs two checkouts", "magi"],
  ["isolation", "a jail that lets a command read your keys or reach the network — proved against a real <code>bwrap</code>", "casper"],
  ["spawn · writes", "a program started anywhere but the named places, or not tied to casper; a file changed outside the modules allowed to", "casper"],
  ["no model needed", "a test that passes only with a key, a network or embeddings", "balthasar"],
  ["no exec · no delete", "a memory that runs the action it describes; a memory erased rather than retired", "balthasar"],
  ["witnessed · untrusted · served", "a memory shown as true that cannot say how it is known; untrusted text becoming a standing instruction; anything closed or forgotten offered as memory", "balthasar"],
])}
${note("<b>And above the four, one more.</b> The root repository builds all four from the pinned commits, runs every gate and every suite against the binaries it just built, then runs fifteen end-to-end scenarios against real processes and a scripted provider — on every push. It is how a change in one program that breaks another is caught before either is released.")}
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
    "The harness. The conversation, the screen, the registry and the permission ledger — and the " +
    "only one of the four a person runs. It runs no tool of its own.",
  body: `
      <h2 id="owns">What it owns</h2>
      <ul class="plain">
        <li><b>The turn loop.</b> Rendering what balthasar laid out, reading what the model wants,
        and deciding what happens next.</li>
        <li><b>The screen.</b> The transcript as blocks in native scrollback — a running command
        stays live in its own, and one can be pinned or searched — live streaming, and an
        editor-grade prompt with <code>:</code> commands for everything a session can be asked.</li>
        <li><b>The registry.</b> One name, one entry — whatever the tool's transport. Every tool
        that touches the machine is supplied by the <a href="../guides/roles.html">tools role</a>;
        magi's own builtin is <code>spawn</code>.</li>
        <li><b>Who decides.</b> The permission ledger, standing rules, and the
        <a href="../guides/permissions.html">mode</a> — you, you for anything but an edit here, a
        second model, or nobody.</li>
        <li><b>The session.</b> Its id, its socket, and which program holds its transcript —
        whatever fills the <a href="../guides/roles.html">memory role</a>.</li>
        <li><b>The helpers.</b> When balthasar hands out a job — a summary, notes to draw from a
        turn, two claims to reconcile — magi runs it on whichever model that kind of work is
        given.</li>
        <li><b>Other agents.</b> <code>magi fork</code>, or a model calling <code>spawn</code>,
        starts a child session; <code>magi.agents</code> names the kinds it may start. The screen
        moves between them from the keyboard. See
        <a href="../guides/sessions.html#fork">sessions</a>.</li>
        <li><b>Skills.</b> <code>/skill &lt;name&gt;</code> puts a Markdown workflow into the
        conversation. See <a href="../guides/skills.html">skills</a>.</li>
      </ul>

      <h2 id="not">What it does not own</h2>
      <p>Which endpoint a model lives at, what credential it takes, what a 429 means, what a run
      has spent — melchior's. What a tool does, and the jail it runs in — casper's. What a request
      holds and what is worth remembering — balthasar's. A config here that held an opinion about
      any of them would be a second catalog to keep in step.</p>

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
magi --attach &lt;id&gt;       <span class="c">another screen on a running session; --view-only to watch</span>
magi tools               <span class="c">every tool the model can call, and how each is reached</span>
magi models              <span class="c">what melchior says this machine could talk to</span>
magi acp                 <span class="c">the same sessions, for an editor that speaks ACP</span></pre>
${note("<b><code>magi doctor</code> never fails.</b> A configuration that will not load is reported rather than exited over — the whole point is to be usable on the machine where something is wrong.")}

      <h2 id="daemon">There is no daemon</h2>
      <p>There was. <code>magi</code> spawned <code>magi host</code> as a background child that
      owned the journal and the socket, and a UI quitting was a <i>detach</i>. Two problems
      followed. The daemon's socket was named after the working directory, so the second
      <code>magi</code> in a project found the first one's session. And nothing ever ended one, so
      a week of work left a process per project.</p>
      <p>The session is the process now. It binds a socket of its own, named after the session
      and not the directory, so a second screen can attach to it — and returning from
      <code>magi</code> is still the end of it. A session that should outlive its terminal says so:
      <code>--headless</code>.</p>

      <h2 id="acp">In an editor</h2>
      <p><code>magi acp</code> speaks the Agent Client Protocol on stdio, for an editor that
      drives agents that way. It starts ordinary magi sessions — the same turn loop, the same
      permissions, the same memory — rather than being a second agent. It is marked experimental,
      and it advertises only what it does: a session can be created, loaded, prompted and
      cancelled, with permission questions passed to the editor.</p>
`,
});

PAGES.push({
  at: "programs/casper.html",
  section: "prog",
  logo: "casper",
  nav: "casper",
  title: "casper",
  blurb:
    "The tools a coding agent runs, the jail every command runs in, and the screen they draw on. " +
    "It knows nothing about models, turns or transcripts.",
  body: `
      <h2 id="tools">What it offers</h2>
      <p>Nineteen tools. Ten are in front of the model on every request; the other nine are
      <i>deferred</i> — listed in the <code>tools</code> manual and declared only when the model
      asks for them, so they cost nothing until then.</p>
${table(["tools", "for"], [
  ["<code>read</code> <code>write</code> <code>edit</code>", "a file — text, or an image resized and sent as an image. <code>edit</code> replaces an exact piece and answers with the diff."],
  ["<code>ls</code> <code>tree</code> <code>code</code>", "the shape of the tree, and a source file's skeleton — types, signatures, line ranges — for a fraction of reading it"],
  ["<code>sese</code>", "where something lives, by meaning rather than by string: a ranked list of passages and nothing else"],
  ["<code>shell</code> <code>execute</code>", "a command; or a Python script in which the read-only tools are functions, for a chain of looks in one call"],
  ["<code>tools</code>", "the manual: the deferred tools, and every outside MCP server's"],
  ["<code>web</code>", "a search, or one page fetched and read — no scripts run. Deferred."],
  ["<code>screen</code>", "an interactive program — a pager, an editor, <code>htop</code>, <code>git add -p</code> — in a block of its own. Deferred."],
  ["<code>hexe</code> <code>oslo</code> <code>session</code>", "asking the multiplexer, the shell, or the harness about themselves. Deferred."],
  ["<code>dino</code> <code>birdy</code> <code>doom</code> <code>games</code>", "games, because a surface that can draw a game can draw anything. Deferred."],
])}
      <p>Every one is declared in Lua, in <code>~/.config/casper/tools.lua</code>, read fresh on
      every call — editing it changes the tools on the next one, no rebuild. <code>code</code>
      parses through grammars casper does not ship: <code>casper grammar fetch</code> builds the
      pinned set into your data directory.</p>

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
  ["<code>output_bytes</code>", "how much of a result crosses back before it is cut — 256 KiB unless set. Head and tail both kept, and the note says how much went."],
  ["<code>mcp_servers</code>", 'outside MCP servers to connect to, by name — see <a href="../guides/mcp.html">MCP</a>'],
  ["<code>web</code>", "how <code>web</code> searches and fetches"],
])}
      <pre><span class="c">-- in magi's config, in casper's vocabulary</span>
magi.casper = { tools = { dino = { off = true } }, output_bytes = 65536 }</pre>

      <h2 id="jail">The jail</h2>
      <p>Every command casper runs — a <code>shell</code> call, a <code>screen</code>, an MCP
      server it starts — runs in a kernel jail magi chose when it started casper, never one the
      call names. <b>bubblewrap</b> where it is installed; <b>Landlock and seccomp</b> where it is
      not; and where neither can be fully enforced, the command is refused rather than run
      without one.</p>
${table(["inside", ""], [
  ["reads", "system and toolchain directories, and the workspace"],
  ["writes", "the workspace, the grants magi added, and a private temporary directory"],
  ["the network", "open when magi says so — it is essential to most work — and nothing local through it: no host Unix socket, no abstract one where the kernel can scope it"],
  ["your keys", "credential stores, the home directory's dotfiles, and anything they link to are unreadable, even when a grant would cover them — that grant is refused"],
  ["a project's own config", "<code>.magi.lua</code>, <code>.balthasar.lua</code>, <code>.git/config</code> and <code>.git/hooks</code> stay read-only, so a command cannot change what the next unjailed program will run"],
  ["the kernel", "<code>ptrace</code>, <code>bpf</code>, <code>io_uring</code>, mounts, new namespaces and their kin fail with <code>EPERM</code>"],
])}
      <p>The environment is an allowlist, not what magi inherited: a provider key in your shell is
      not in the command's. magi turns the jail on for every session unless your own
      configuration says <code>magi.isolation = false</code>, and a project file cannot.</p>

      <h2 id="exec">A spawn, or a socket</h2>
      <p>casper's job is running programs, and <b>a socket that runs commands is a remote shell
      wearing a friendly name</b> — unless it can run nothing its spawner could not. By default
      magi spawns casper once per call. <code>casper serve</code> is the other door: one process
      for the session, whose jail is the one it was started in, answering only calls that carry
      the key it read on stdin. It exists because an MCP server's session has to survive between
      calls.</p>
${note('<b>casper fills the <code>tools</code> role, and is the default rather than the only choice.</b> <code>magi.tools</code> hands the role to any program that answers <code>tools</code> and <code>run</code> — see <a href="../guides/roles.html">swapping a program</a>. The settings table follows the program’s own name, so <code>magi.casper</code> is casper’s because casper is the one filling the role.')}

      <h2 id="cli">At a terminal</h2>
      <pre>casper tools                 <span class="c">every tool it offers, as declarations a harness can register</span>
casper run &lt;tool&gt;            <span class="c">run one; the call arrives as JSON on stdin</span>
casper serve --at &lt;path&gt;     <span class="c">one process for a session, on a keyed socket</span>
casper surface &lt;tool&gt;        <span class="c">hold rows on the harness's screen and draw into them</span>
casper mcp                   <span class="c">its own tools, as an MCP server on stdio</span>
casper mcp-auth · mcp-status · mcp-logout   <span class="c">an outside server's OAuth</span>
casper code &lt;path&gt;           <span class="c">a source file's outline</span>
casper grammar fetch         <span class="c">build the grammars code parses with</span>
casper image &lt;path&gt;          <span class="c">read and resize an image</span>
casper verbs                 <span class="c">what it answers, on each of its doors</span>
casper needs                 <span class="c">what a coordinator may tell it</span>
casper configure             <span class="c">take that configuration, as Lua on stdin</span>
casper acknowledge           <span class="c">clear the installed packages, so their declarations may run</span>

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
        each speaks, and what this machine could therefore talk to. Nine providers and nine wire
        protocols ship, all of them Lua; OpenRouter's and Ollama's model lists are discovered and
        kept for a day. <code>melchior card --model &lt;id&gt;</code> says everything known about
        one: its window, its prices, what it can take, and who serves it.</li>
        <li><b>The turn.</b> One request, streamed back, with the failure classified rather than
        quoted: a transport error, an overload, a throttle, a bad key, a request too long. Each
        class is retried — or not — on its own terms, and a retried attempt that had already
        streamed tells the screen to un-draw it.</li>
        <li><b>What a run spends.</b> Every ask adds its cost to the run's ledger — what the
        provider reported, else the model's own rates, cached reads and writes included. A run is
        a root session and everything started under it, and it may spend
        <code>spend_cap_usd</code>, ten dollars unless something says otherwise. Past it, the next
        ask is refused with nothing sent, and told why and how to raise it.</li>
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
      <pre>melchior models              <span class="c">what this machine could talk to; --refresh to ask again</span>
melchior card --model &lt;id&gt;   <span class="c">one model in full: window, prices, capabilities, who serves it</span>
melchior ask                 <span class="c">run a turn; an Ask on stdin</span>
melchior auth login · status · logout   <span class="c">a provider that signs in with OAuth</span>
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
${note("<b>No verb a model calls runs anything.</b> The coordination vocabulary sends messages, reads an inbox, reports, and says who is listening — deliberately, and melchior's own tests refuse a verb named <code>run</code>, <code>shell</code>, <code>exec</code> or <code>eval</code>. That is why magi can grant the agent tool in advance without a prompt.")}
`,
});

PAGES.push({
  at: "programs/balthasar.html",
  section: "prog",
  logo: "balthasar",
  nav: "balthasar",
  title: "balthasar",
  blurb:
    "Memory for agents, and the layout of every request a harness sends. Short-term and " +
    "long-term in one layer, with its own store — not a library a harness links.",
  body: `
      <h2 id="four">The four things it holds</h2>
${table(["", ""], [
  ["the window", "what each request holds — balthasar lays it out, and the harness renders it"],
  ["the session", "what happened in this run, verbatim — the only copy of what was said"],
  ["the project", "what is true here, how things are done, and the rules a person gave"],
  ["everywhere", "what is true of you, whichever project you are in"],
])}
      <p>And the ladder between them: ten kinds of evidence — a person saying so, a correction, a
      commit, a choice, a repetition, and more — each weighed, and floors deciding what may climb
      from one level to the next and what is stated rather than hedged. A session is distilled when
      it has gone quiet, and what recurred across sessions is carried up once a day.</p>

      <h2 id="layout">Every request, laid out</h2>
      <p>Before each request the harness asks for a layout, and balthasar answers with the slots
      to send, in the order a prompt cache wants: the rules a person gave, the notes drawn from
      past turns, a catalog of what the project holds, the conversation — word for word, stubbed,
      or summarised where it has to be — and the memory this prompt calls for, just before it.
      Nothing is recorded by answering; the harness says what it actually sent.</p>
      <p><b>It never calls a model.</b> When a summary is due, notes could be drawn from a finished
      turn, or two claims disagree, it hands the harness a job, and takes the answer back. A rule
      a person later took back is not offered again, and neither is anything drawn from the turns
      that rule cited.</p>

      <h2 id="cli">At a terminal</h2>
      <pre>balthasar remember "we run the tests with make test"
balthasar recall "tests" --explain
balthasar why &lt;handle&gt;            <span class="c">the evidence, not just the number</span>
balthasar context                 <span class="c">exactly what a model would be told</span>
balthasar disagreements           <span class="c">claims that cannot both be true, waiting on you</span>
balthasar settle                  <span class="c">say which one is right</span>
balthasar decay                   <span class="c">what today's forgetting would take, before it takes it</span>
balthasar sessions                <span class="c">which runs this project has had</span>
balthasar eval                    <span class="c">measure whether memory earns its place</span>
balthasar serve                   <span class="c">listen for other programs</span></pre>

      <h2 id="store">Where a store lives</h2>
      <pre>&lt;project&gt;/.balthasar/&lt;tool&gt;/project.db                <span class="c">what is true here, kept</span>
&lt;project&gt;/.balthasar/&lt;tool&gt;/project-transcript.db     <span class="c">every run's turns, verbatim</span>
&lt;project&gt;/.balthasar/&lt;tool&gt;/&lt;run&gt;/&lt;agent&gt;/memory.db    <span class="c">one agent's scratch, dies with the run</span>
~/.local/share/balthasar/&lt;tool&gt;/global.db            <span class="c">yours, everywhere</span></pre>
      <p><b>The store lives in the project</b>, hidden like the rest of a checkout's tool state
      and with a <code>.gitignore</code> of its own, so renaming a checkout moves its memory
      rather than orphaning it. A store found in the older, visible <code>balthasar/</code> is
      moved on sight. Which store a given directory gets is
      <a href="../guides/memory.html#scope">its own question</a>.</p>
${note('<b>balthasar fills the <code>memory</code> role.</b> It binds under <code>$XDG_RUNTIME_DIR/memory/</code>, the role’s name. A write on its socket carries the key it was handed on stdin; a read needs none. <code>magi.memory</code> names another program for the role — see <a href="../guides/roles.html">swapping a program</a>.')}

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
    "gates ran under — or each from its own Nix flake, or all four from source, in one clone. " +
    "Linux only.",
  body: `
      <h2 id="get">Get the binaries</h2>
      <pre>gh release download v0.8.0 --repo ai-nerv/magi --pattern '*-amd64.tar.gz'
tar -xzf magi-linux-amd64.tar.gz -C ~/.local/bin

<span class="c"># the siblings are separate releases. casper and melchior are optional; a memory layer is not</span>
gh release download v0.9.1 --repo ai-nerv/casper    --pattern '*-amd64.tar.gz'
gh release download v0.8.0 --repo ai-nerv/melchior  --pattern '*-amd64.tar.gz'
gh release download v0.8.0 --repo ai-nerv/balthasar --pattern '*-amd64.tar.gz'</pre>
      <p>Each tarball is the binary and nothing else. Each carries its shipped configuration, so
      a fresh install already speaks; the files to edit come from a checkout's
      <code>make configs</code>. <code>casper grammar fetch</code> builds the grammars its
      <code>code</code> tool parses with.</p>

      <h2 id="nix">With Nix</h2>
      <p>Each program is its own flake, and every release is in a binary cache:</p>
      <pre>nix run github:ai-nerv/magi -- doctor
nix profile install github:ai-nerv/magi github:ai-nerv/casper \\
                    github:ai-nerv/melchior github:ai-nerv/balthasar

<span class="c"># the cache, so nothing is built on your machine — in nix.conf</span>
extra-substituters = https://cache.bresilla.com/bresilla
extra-trusted-public-keys = bresilla:zsecaZYIrjCJQS4AuGPmEVU5PRkiMmB/Mds3KaCzTvE=</pre>

      <h2 id="what">What each one buys you</h2>
${table(["", "without it"], [
  ["magi", "nothing — this is the one you run"],
  ["casper", "no tool that touches the machine: no reading, writing or running. magi keeps <code>spawn</code> and the tools that reach its siblings."],
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
  ["<code>make verify</code>", "every member's gates and suites against the binaries just built, then fifteen end-to-end scenarios — what CI runs"],
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
${note("<b><code>make install</code> ends by syncing the configuration</b>, file by file, and where your copy and the shipped one differ the newer side wins. <code>make configs --keep</code> leaves every file you edited alone.")}
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

magi.model = {
  main   = "openrouter/anthropic/claude-sonnet-4.6",
  helper = { summary = "deepseek/deepseek-chat", safety = "openai/gpt-5.1-mini" },
}
magi.mode  = "ask"                      <span class="c">-- who decides what no rule covers</span>
magi.allow = { … }                      <span class="c">-- answered in advance, not under pressure</span></pre>

      <h2 id="settings">What it takes</h2>
${table(["setting", "does"], [
  ["<code>magi.model</code>", "which model, as <code>magi models</code> prints it — or a table: <code>main</code>, and a model per kind of helper work under <code>helper</code>"],
  ["<code>magi.thinking</code>", "how hard the model reasons, where it can be told"],
  ['<code>magi.mode</code> · <code>magi.allow</code> · <code>magi.ask</code> · <code>magi.deny</code>', 'who decides, and the rules that come first — see <a href="permissions.html">what may run</a>'],
  ["<code>magi.isolation</code>", "whether commands run in casper's jail. On unless this says <code>false</code>."],
  ["<code>magi.confine</code>", "whether file operations refuse paths outside the session's directory"],
  ['<code>magi.memory</code> · <code>magi.tools</code> · <code>magi.melchior</code>', 'as a string, which program fills that role — see <a href="roles.html">swapping a program</a>'],
  ["<code>magi.helpers</code>", "which kinds of helper work run at all, how long one may take, and what a prompt may spend on them"],
  ["<code>magi.agents</code> · <code>magi.may_spawn</code>", 'the kinds of agent a session may start, and whether it may start any — see <a href="sessions.html#fork">sessions</a>'],
  ["<code>magi.system</code>", "what the system message says, on top of what magi writes"],
  ["<code>magi.trusted</code>", "directories whose <code>.magi.lua</code> is as good as this file"],
  ["<code>magi.env</code>", "environment every process magi starts is given, on top of what it inherits"],
  ["<code>magi.project</code>", "what this session is called, in the name other sessions see"],
  ["<code>magi.agent_talk</code>", "how far one session may reach another"],
  ["<code>magi.ui</code>", "every colour, glyph and measurement the screen draws with, the spinner included"],
  ["<code>magi.events</code>", "local operational events, for tooling that watches sessions. Off unless set."],
  ["<code>magi.casper</code> · <code>magi.melchior</code> · <code>magi.balthasar</code>", "as a table, settings handed to that sibling, in <i>its</i> vocabulary — one place to edit rather than two. For the tools role the table is named after whichever program fills it."],
])}
      <p>Inside a session, <code>:env KEY=value</code> and <code>:source file.sh</code> change that
      session's environment — the next request, helper and tool see it — without touching your shell
      or any file. A model that was waiting for its key becomes ready the moment the key is set.</p>

      <h2 id="trust">A project's own file</h2>
      <p>A <code>.magi.lua</code> arrives with a checkout. Cloning a repository and running magi in
      it must not be enough to add a tool, to widen what runs without asking, or to change what
      anything is told. So a project file runs in a VM of its own — no socket, no filesystem, no
      environment, no <code>load</code> — and may set three things.</p>
${table(["a project file may", "and anything else"], [
  ["<code>model</code> — a model the machine already offers", "is refused by name, and the refusal is fatal"],
  ["<code>thinking</code> — how hard it reasons", "including a model for <code>helper</code> or <code>safety</code> work, since that decides what runs without asking"],
  ["<code>ui</code> — how it looks", "including a sibling's settings, a tool, a role's program, and every rule"],
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
magi.melchior  = { max_tokens = 8192, spend_cap_usd = 25 }
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
  ["tools", "<code>magi.tools</code>", "casper", "<code>tools</code> <code>run</code>", "a session with no tool that touches the machine"],
  ["model", "<code>magi.melchior</code>", "melchior", "<code>models</code> <code>ask</code>", "no model to ask"],
])}
      <pre>magi.memory = "remembrance"   <span class="c">-- a program on $PATH</span>
magi.tools  = "workbench"</pre>
${note("<b><code>magi.model</code> is the model, not the program.</b> It named the model before roles existed, so the model role is named by <code>magi.melchior</code>, which has always meant the program. A table there is still that program’s settings; only a string names it.")}

      <h2 id="core">Core, and everything else</h2>
${table(["", "if a program refuses it"], [
  ["<b>core</b>", "it cannot fill the role. The gate fails, and <code>magi doctor</code> says so."],
  ["<b>extension</b>", "magi carries on with less — a model tool not declared, no layout and so the whole live conversation sent, an outcome loop that records nothing."],
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
  tools    casper — ~/.local/bin/casper — 19 tools
  model    melchior — ~/.local/bin/melchior — … models</pre>

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

      <h2 id="four">A tool that runs something</h2>
      <p>Anything that touches the machine is the tools program's, so a tool that runs a program
      is a <code>casper.tool</code>:</p>
      <pre>casper.tool("query", {
  description = "Run a jq filter over a JSON file.",
  parameters  = { type = "object", properties = { filter = { type = "string" },
                                                  path   = { type = "string" } } },
  needs  = "read",                     <span class="c">-- read | write | run | reach</span>
  script = true,                       <span class="c">-- callable from execute; only with needs = "read"</span>
  run = function(args)
    local done = casper.exec("jq", { args.filter, args.path })
    return { said = done.out }
  end,
})</pre>
${table(["field", "is"], [
  ["<code>description</code>", "what the model is told the tool does. This is the whole of how it decides to call it."],
  ["<code>parameters</code>", "JSON Schema for the arguments. The model is held to it before <code>run</code> is called."],
  ["<code>needs</code>", "the permission verb this acts under. Omit it for a tool that touches nothing a person would want a say over."],
  ["<code>deferred</code>", "keep it out of every request until the model looks it up in the <code>tools</code> manual"],
  ["<code>script</code>", "make it a function inside <code>execute</code>'s Python. Only a <code>read</code> tool may: a script's calls are never put to anybody."],
  ["<code>run</code>", "the body. Returns <code>said</code>, and optionally <code>shown</code>, <code>images</code>, or <code>failed = true</code>."],
])}
      <p>There is no <code>os.execute</code> and no <code>io.popen</code> in the VM, and no
      <code>io</code> at all. <code>casper.exec</code> is the seam: a program and a list of
      arguments, no shell in between, run inside the same jail as every other command.</p>

      <h2 id="magi">A tool that thinks</h2>
      <p>magi's own registrar is for what is not machine work: a few lines of logic in its VM, or
      a call to a sibling.</p>
      <pre>magi.tool("today", {
  description = "Today's date.",
  parameters  = { type = "object", properties = {} },
  transport   = { kind = "lua" },        <span class="c">-- or { kind = "command", command = "melchior", args = { … } }</span>
  run = function() return { content = os.date("%Y-%m-%d") } end,
})</pre>
      <p><code>transport</code> is not optional and has no default: a tool with a <code>run</code>
      and no transport is refused at load, because the registry has no way to guess that the
      function is the point. A <code>command</code> transport exists to reach a sibling — the
      memory tools reach balthasar and <code>agent</code> reaches melchior that way. A tool that
      does work on the machine belongs to casper, not to magi.</p>

      <h2 id="transports">Four ways to be reached</h2>
${table(["transport", "is", "for"], [
  ["<code>supplied</code>", "whatever the tools role’s program offers, per call or through its <code>serve</code>", "casper’s nineteen and every outside MCP server’s — unless <code>magi.tools</code> names another program"],
  ["<code>lua</code>", "a body that runs in magi's own VM", "anything that is a few lines of logic"],
  ["<code>command</code>", "a sibling program, given the call as argv", "reaching another program of the family"],
  ["<code>builtin</code>", "compiled into magi", "<code>spawn</code>, and nothing else: starting another agent is coordination, not machine work"],
])}
      <p>The registry does not care which. One name, one entry, and the model sees the same
      declaration whichever way it is reached — checked against the same schema, asked about in
      the same way, and capped and masked on the way back.</p>

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
      <p>A casper tool may put a question to the harness — a choice for the person, or, as
      <code>sese</code> does, an answer from a model casper holds no key for. The declaration reads
      <code>args.answered</code> to know it is resuming. The answer travels
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
    "Every read, write, command and host passes the ledger before it happens, the mode decides " +
    "who is asked, and the jail holds whatever was allowed to what it said it would do.",
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

      <h2 id="advance">Rules, decided in advance</h2>
      <pre>magi.allow = {
  { verb = "read",  directory = "/home/you/work" },
  { verb = "run",   program = "git" },
}
magi.ask  = { { verb = "run", program = "rm" } }         <span class="c">-- always the person</span>
magi.deny = { { verb = "reach", anything = true } }      <span class="c">-- never, in any mode</span></pre>
      <p>A rule written down is not a question asked. The standing answers are ones you decided in
      advance, in a file, rather than under time pressure mid-turn. <code>deny</code> and
      <code>ask</code> come first in every mode: what <code>deny</code> names never runs, and what
      <code>ask</code> names always reaches a person. <b>A rule naming no width is no rule.</b></p>

      <h2 id="modes">Four modes</h2>
      <p>The mode decides who is asked about what no rule covers. Set it with
      <code>magi.mode</code>, or change it in a session with <code>:mode</code> or
      <kbd>shift</kbd>+<kbd>tab</kbd>.</p>
${table(["mode", "asks"], [
  ["<code>ask</code>", "the person, every time. <b>The default.</b>"],
  ["<code>edits</code>", "the person — except for writes inside the session's directory"],
  ["<code>auto</code>", "a second model, the one <code>magi.model.helper.safety</code> names. It is shown what the person asked for and the action, never a tool's output, so a file cannot talk its way through."],
  ["<code>locked</code>", "nobody: what would have been asked is refused. For a run nobody is watching."],
])}
${note("<b>A project cannot choose who judges.</b> <code>magi.mode</code>, every rule and the safety model are your configuration's alone; a <code>.magi.lua</code> that sets any of them is refused before the session starts.")}

      <h2 id="confine">Confinement is a wall</h2>
      <p><code>magi.confine</code> refuses paths outside the session root outright — no prompt, no
      grant, no appeal. It applies whether or not there is anybody there to ask, which is why it
      sits before the ledger rather than inside it.</p>

      <h2 id="jail">The jail is what contains anything</h2>
      <p>A permission decides whether an action may happen; it cannot stop a command from doing
      more than it said. So every command casper runs — the shell, a screen, an MCP server — runs
      in a kernel jail chosen when casper was started: the workspace writable, your credential
      stores and dotfiles unreadable, the project's own config read-only, a short list of syscalls
      refused, and the network open, because most real work needs it. It is on unless your own
      configuration says <code>magi.isolation = false</code>. See
      <a href="../programs/casper.html#jail">casper</a>.</p>

      <h2 id="nobody">When nobody is there</h2>
      <p>A run with no UI attached has nobody to ask. It is refused, and the tool is told why — a
      session whose front end has detached does not get to assume the answer would have been yes.
      That is why <code>magi -p</code> refuses an ungranted read rather than hanging on a question
      nobody can see. A child agent's question is not refused: it is passed up to the session that
      started it, which has somebody to ask.</p>
`,
});

PAGES.push({
  at: "guides/memory.html",
  section: "guide",
  nav: "memory",
  title: "Memory",
  blurb:
    "Writing must never stall a turn. Reading must never be trusted blindly. And what a request " +
    "holds is the memory layer's decision, made fresh before every one.",
  body: `
${plate("d-mem", "plate 06", "out, in, and back again")}

      <h2 id="out">Out: handed over before it is needed</h2>
      <p>A session is behind a mutex and a commit is a short lock, so what is committed is handed
      to a writer and the turn carries on. Before the next request is laid out, magi waits for that
      handover to land — balthasar cannot lay out what it has not been told. If it never lands, the
      entry is still in the conversation; only the durable record is lost.</p>

      <h2 id="in">In: nothing is trusted blindly</h2>
      <p>The memory slot of each layout holds what this prompt calls for, chosen once per prompt —
      a prompt that is only <i>“ok, go on”</i> keeps the last one's, byte for byte. Each memory is
      presented for what it is:</p>
${table(["", "is"], [
  ["current", "stated — witnessed well enough and confirmed recently enough to be true now"],
  ["on record", "kept below a heading that says it is weakly witnessed or not confirmed lately, and to check before acting on it"],
  ["quarantined", "not shown at all"],
])}
${table(["bound", "limits"], [
  ["inject floor", "how sure balthasar must be before a memory is stated rather than hedged"],
  ["live floor", "the lower bar for something recalled inside the current session"],
  ["window share", "how much of a request's room memory may take — five per cent unless set"],
])}
${note("<b>Something you said once in March is not something true now.</b> Flattening the two would present an old remark as a standing fact, so the hedge is kept rather than the memory dropped — the model can still use it, and is told how much to trust it.")}

      <h2 id="notes">Rules, notes and the catalog</h2>
      <p>After a turn, a helper may be handed the job of drawing notes from it. A note becomes a
      <b>rule</b> — sent on the user's channel — only when it matches a complete instruction a
      person actually gave, word for word, negations and conditions kept; anything paraphrased,
      quoted or said by another agent stays an <b>observation</b>, lower trust. Every change is
      recorded and can be undone, and with <code>balthasar.memory.review</code> on, each one waits
      for your approval. The <b>catalog</b> lists what the project holds as true, one line each, and
      says whether that is all of it — so a model can tell <i>nothing is held about this</i> from
      <i>the search missed it</i>.</p>
      <p>Two claims that cannot both be true are linked rather than one quietly winning:
      <code>balthasar disagreements</code> lists them, and <code>balthasar settle</code> says which
      is right. A rule a person later takes back is not recalled again, and neither is what it had
      cited.</p>

      <h2 id="back">Back: did it help</h2>
      <p>A turn may report what it used and how that went, and balthasar keeps the ledger —
      <b>off by default</b>, on with <code>balthasar.outcome = { capture = true }</code>. The
      harness reports the event; it does not claim a match it did not verify, which would be
      asserting an analysis rather than reporting what happened.</p>
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
      survives is the store, not a running thing. <code>--resume-run &lt;id&gt;</code> carries on
      a particular run rather than the newest — how a script hands work from one invocation to the
      next.</p>
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
      more than its parent has — a question it cannot answer itself is passed up to the session
      that started it. A role given at birth is a label others can route by, and it grants
      nothing.</p>
      <p>A model starts one with the <code>spawn</code> tool, and your configuration names the kinds
      it may start:</p>
      <pre>magi.agents = {
  reviewer = { description = "reads a diff and says what is wrong with it",
               prompt = "Review the change you are given. Write nothing.",
               model = "anthropic/claude-sonnet-4-5" },
}
magi.may_spawn = true</pre>
      <p>Every session publishes its screen beside its socket, so the one terminal moves from agent
      to agent — <kbd>alt</kbd>+<kbd>,</kbd> and <kbd>alt</kbd>+<kbd>.</kbd> — and
      <code>:agents</code> shows the whole tree, live. <code>magi --attach &lt;id&gt;</code> puts a
      second screen on any of them; <code>--view-only</code> watches without typing.</p>

      <h2 id="crew">The crew</h2>
      <p>A model reaches the other agents through one tool, whose verbs melchior answers on its
      <code>tool</code> door:</p>
${table(["verbs", "for"], [
  ["<code>list</code> <code>whoami</code> <code>about</code> <code>crew</code> <code>role</code> <code>status</code>", "who is here, who started whom, what each is for, and what each is doing now"],
  ["<code>send</code> <code>ask</code> <code>reply</code> <code>inbox</code> <code>announce</code>", "talking — an answer can arrive long after the connection that carried the question has closed"],
  ["<code>report</code>", "a child handing its result back, rather than sending it as a message"],
  ["<code>attention</code> <code>trouble</code>", "the one message that may interrupt a turn, and saying something has gone wrong"],
  ["<code>watch</code> <code>unwatch</code>", "being told when another agent changes phase — starts, works, waits, finishes — without asking"],
  ["<code>claim</code> <code>claims</code> <code>release</code>", "saying what one is working on, so two agents do not both do it"],
  ["<code>assign</code> <code>task</code> <code>handoff</code> <code>adopt</code>", "handing work to another agent, keeping a handle on it, and taking over a whole branch"],
  ["<code>stop</code> <code>disband</code>", "ending a child, or a whole branch of them"],
])}
      <p>A message is a sentence, not a payload: at most 2,000 characters, and 24 a minute per
      session. A session may start eight children, and a tree may go eight deep.</p>

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
      <p>When the tool says so, or when the person ends it. Then magi repaints around it and the
      rows go back.</p>

      <h2 id="block">Or a block of its own</h2>
      <p>A surface may ask for a block in the conversation instead of rows lent below the prompt.
      <code>screen</code> does: the call answers at once, and the program keeps running in its
      block where it was started — live while the conversation goes on above it, and still there
      when you scroll back. A running block can be pinned, and found again.</p>

      <h2 id="why">Why frames and not one exec</h2>
      <p>A surface is a stream of frames both ways for as long as the tool holds its rows — keys
      and clicks down, a drawn frame back. One exec per event would restart the program between
      keystrokes, which is not an editor.</p>
${note("<b>The permission prompt is itself a surface.</b> That is why it can show a wrapped command in full rather than a truncated one — and a command cut in the middle is a command somebody allows without having seen the end of.")}
`,
});

PAGES.push({
  at: "guides/skills.html",
  section: "guide",
  nav: "skills",
  title: "Skills",
  blurb:
    "A workflow written down once and picked by name: a Markdown file, put into the turn that " +
    "asked for it. It is text, not code, and it grants nothing.",
  body: `
      <h2 id="first">A first one</h2>
      <pre><span class="c"># .magi/skills/review/SKILL.md</span>
---
name: review
description: "Review changes: correctness and tests"
---
Review the requested files for correctness and missing tests.
Explain findings before proposing edits.</pre>
      <p>Then, at the prompt, <code>/skill review src/lib.rs</code>. <code>/skill </code> completes
      the names, and <code>:skills</code> refreshes them. The same works where nobody is typing:</p>
      <pre>magi -p '/skill review src/lib.rs'</pre>

      <h2 id="where">Where they are found</h2>
${table(["first", "root"], [
  ["1", "<code>.magi/skills/&lt;name&gt;/SKILL.md</code>, under the directory magi was started in"],
  ["2", "<code>.agents/skills/&lt;name&gt;/SKILL.md</code>, the same"],
  ["3", "<code>~/.config/magi/skills/&lt;name&gt;/SKILL.md</code>, yours, everywhere"],
])}
      <p>Only those three, and only one level deep. There is no walk up to a parent, no search of a
      repository's root, and no reading of another tool's directories — a nested directory does not
      quietly pick up a skill from above it. <code>magi.workflow_workspace</code>, in your own
      configuration, names another root.</p>

      <h2 id="what">What it is, and is not</h2>
      <ul class="plain">
        <li><b>Text.</b> The body is added to that turn's context, and kept with the run in
        balthasar, with where it came from — so a resumed session knows what it was told.</li>
        <li><b>Not a template.</b> Arguments are appended as data, labelled as data. Nothing is
        substituted, nothing is expanded, and a <code>$(…)</code> in an argument is the characters
        <code>$(…)</code>.</li>
        <li><b>Not a grant.</b> A skill that says <i>“run the tests”</i> is a request like any
        other. Every action it leads to passes the same ledger.</li>
        <li><b>Not code.</b> It is not a Lua plugin and cannot declare a tool. That is what
        <a href="tools.html">writing a tool</a> is for.</li>
      </ul>
${note("<b>A skill that cannot be found is refused, visibly.</b> A bare <code>/skill</code>, a bad name or a missing file is an error rather than an ordinary prompt sent to the model — and <code>magi -p</code> exits non-zero rather than carrying on as though it had been asked something else.")}
`,
});

PAGES.push({
  at: "guides/mcp.html",
  section: "guide",
  nav: "MCP",
  title: "MCP, both ways",
  blurb:
    "casper speaks the Model Context Protocol in both directions: outside servers become tools a " +
    "session can call, and casper's own tools are a server something else can call.",
  body: `
      <h2 id="client">An outside server, as tools</h2>
      <p>One JSON file per server, named after it, in casper's data directory — and nowhere else.
      No other program's configuration is read, and no project's.</p>
      <pre><span class="c"># ~/.local/share/casper/mcp/filesystem.json</span>
{
  "command": "/absolute/path/to/an/mcp-server",
  "args": ["--root", "/your/project"],
  "needs": "run",
  "timeout_secs": 60
}</pre>
      <p>A server over HTTP gives a <code>url</code> and its <code>headers</code> instead. Its
      tools appear in the session as <code>mcp__&lt;server&gt;__&lt;tool&gt;</code>, and the
      <code>tools</code> manual describes each server and what it offers. A server that will not
      start costs its own tools and nothing else.</p>
${table(["", ""], [
  ["where it runs", "a server over stdio starts <b>inside the jail</b>, with only its own environment. One over HTTP needs the network granted, like any other reach."],
  ["what it may do", "its <code>needs</code> is the permission verb every call is asked under — the ledger does not know or care that the tool came from MCP"],
  ["who signs in", "<code>casper mcp-auth</code> runs a server's OAuth, with your browser and your consent; <code>mcp-status</code> and <code>mcp-logout</code> do the rest"],
  ["between calls", "a server's session is kept while magi holds casper's <code>serve</code> open — which is what that door exists for"],
])}
      <p>Your own configuration can also name servers through casper's settings, and those win
      over a file of the same name:</p>
      <pre>magi.casper = {
  mcp_servers = {
    remote = { url = "https://example.org/mcp", needs = "reach",
               headers = { Authorization = "Bearer …" } },
  },
}</pre>

      <h2 id="server">casper's tools, as a server</h2>
      <pre>casper mcp --root /path/to/project --tools=read,web</pre>
      <p>Any MCP client can then call casper's tools over stdio. Started this way, casper runs every
      command in its conservative jail unless told otherwise — the one place it defaults to jailed
      rather than to whatever its spawner chose, because here the spawner is somebody else's
      program. A tool that is off or hidden is not offered; a call that is cancelled or runs out of
      time stops the process it started.</p>
${note("<b>magi has no MCP client of its own.</b> Running a tool is casper's, whoever wrote it — so an MCP server's tools pass the same jail, the same ledger, the same output cap and the same secret masking as casper's own, through the one door every tool already uses.")}
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
  ["frame", "16 MiB, in all four, checked by the writer before it sends. An unbounded read is a way to make a session allocate until it dies."],
  ["a message between sessions", "2,000 characters, and 24 a minute. A message between instances is a sentence, not a payload."],
  ["socket path", "108 bytes, which is the kernel's limit and not anybody's choice. Long temporary directories are how this is usually met."],
  ["identity", "<code>SO_PEERCRED</code>. A caller the kernel will not identify gets nothing."],
  ["a key", "a write on balthasar's socket, and any call to casper's <code>serve</code>, carries the key the program read on stdin when it started — or one it minted beside its socket. Reads need none."],
])}

      <h2 id="environment">What a child is told</h2>
      <p>Some environment carries capability — which door to use, which session a child belongs
      to, what a sibling was configured with: <code>MAGI_TOOLS_DOOR</code>,
      <code>MAGI_MEMORY_DOOR</code>, <code>MAGI_AGENT_DOOR</code>, <code>CASPER_CONFIGURE</code>,
      <code>MAGI_GRANTS</code>, the <code>MAGI_MELCHIOR_*</code> identity. The family's own
      children are given it; every other program magi or casper starts has it stripped, so a tool
      cannot inherit a session's authority by accident. <code>FAMILY.md</code> in each repository
      lists all of it.</p>
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
      <p>The surface is not a mirror of what balthasar can do; it is what another program has a
      real reason to ask a memory layer — which, now that the memory layer lays out every request,
      is more than it was.</p>
      <p>These are the <code>memory</code> role’s verbs. The core three are what any memory
      layer owes; the rest it may refuse by name, and magi carries on with less — see
      <a href="../guides/roles.html">swapping a program</a>.</p>
${table(["verb", "does", "role"], [
  ["<code>observe</code>", "take a turn into this run's record, as it settles", "core"],
  ["<code>replay</code>", "everything a run said, in order", "core"],
  ["<code>sessions</code>", "which runs this project has had", "core"],
  ["<code>layout</code> · <code>applied</code> · <code>overflowed</code>", "what the next request holds; what was actually sent and what it cost; a tighter layout for a request refused as too long", "extension"],
  ["<code>jobs</code> · <code>job_done</code>", "the helper work waiting — a summary, notes, a contradiction — and its answer", "extension"],
  ["<code>notes</code> · <code>note_open</code> · <code>changes</code> · <code>undo</code> · <code>approve</code> · <code>reject</code>", "the pinned rules and observations, every change made to them, and taking one back or letting it through", "extension"],
  ["<code>amend</code> · <code>rename</code>", "revise a turn after it settled; retitle a run", "extension"],
  ["<code>recall</code> · <code>remember</code> · <code>forget</code> · <code>why</code>", "search, keep, let go, and show the evidence — the four a model is given as tools", "extension"],
  ["<code>disagreements</code> · <code>settle</code>", "claims that cannot both be true, and saying which is", "extension"],
  ["<code>scroll</code>", "a run's history a page at a time, so an elided tool result can be read back", "extension"],
  ["<code>plan</code>", "what to keep, mask, drop or summarise — asked only of a memory layer that refuses <code>layout</code>", "extension"],
  ["<code>used</code> · <code>outcome</code> · <code>trace</code> · <code>utility</code>", "what a turn did with what it was given, how that went, and what using a memory has led to", "extension"],
  ["<code>model</code> · <code>resume</code> · <code>writer</code> · <code>writer_status</code>", "which model a run talks to; where the store thinks it left off; who holds the right to write", "extension"],
])}
${note("<b><code>prompt</code>, <code>run</code>, <code>exec</code>, <code>shell</code> and <code>purge</code> are absent from the socket and stay absent.</b> A memory layer that can be told to run something is not a memory layer. <code>eval</code> exists only on the command line, for a person measuring it.")}

      <h2 id="melchior">melchior</h2>
${table(["door", "verbs"], [
  ["socket", "<code>identity</code> <code>tell</code> <code>inbox</code> <code>kin</code> <code>role</code> <code>status</code> <code>stop</code> <code>adopt</code> <code>adopted</code> <code>mint</code> <code>minted</code> <code>needs</code> <code>tool</code> — one program asking another session"],
  ["tool", "<code>whoami</code> <code>about</code> <code>list</code> <code>crew</code> <code>role</code> <code>status</code> <code>send</code> <code>ask</code> <code>reply</code> <code>inbox</code> <code>announce</code> <code>report</code> <code>attention</code> <code>trouble</code> <code>watch</code> <code>unwatch</code> <code>claim</code> <code>claims</code> <code>release</code> <code>assign</code> <code>task</code> <code>handoff</code> <code>adopt</code> <code>disband</code> <code>stop</code> <code>help</code> — what a model calls"],
])}
      <p><code>identity</code> and <code>tell</code> on the socket are <code>whoami</code> and
      <code>send</code> on the tool door, and they are not aliases: one answers a program with a
      record, the other a model with a paragraph.</p>
      <p>No verb here runs anything, and melchior's own tests refuse one named <code>run</code>,
      <code>shell</code>, <code>exec</code> or <code>eval</code>.</p>

      <h2 id="casper">casper</h2>
${table(["door", "verbs"], [
  ["cli", "<code>tools</code> <code>run</code> <code>serve</code> <code>surface</code> <code>mcp</code> <code>mcp-auth</code> <code>mcp-status</code> <code>mcp-logout</code> <code>code</code> <code>replace-source</code> <code>grammar</code> <code>image</code> <code>workflows</code> <code>needs</code> <code>configure</code> <code>client</code> <code>acknowledge</code> <code>verbs</code>"],
  ["socket", "<code>tools</code> <code>run</code> — under <code>serve</code> only, for the session holding its key"],
])}
${note("<b><code>run</code> over the socket runs in the jail <code>serve</code> was started in, never one the call names.</b> casper's job is running programs, and a socket that runs commands is a remote shell wearing a friendly name — unless it can run nothing its spawner could not, and nobody else can reach it.")}

      <h2 id="both">Everywhere — the floor</h2>
      <p>Every program in the family answers these, in the reply shape, on its command line. A
      family where one program can be asked what it speaks and another cannot has stopped being
      one. <code>gate-family.sh</code> holds each of them to it on the merge path.</p>
${table(["", ""], [
  ["<code>verbs</code>", "what this program answers, and on which door. Everything it lists, it dispatches — that is one of the two rules that is tested rather than reviewed."],
  ["<code>client</code>", "the Lua client library for its surface, as source — <code>lua-api</code> in magi and balthasar. A program whose surface is not reached from a VM still answers, saying so — silence is not parseable."],
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
      --resume-run &lt;ID&gt;       <span class="c">continue that run, whichever is newest</span>
      --socket &lt;SOCKET&gt;       <span class="c">connect to a named socket</span>
      --headless              <span class="c">serve with no terminal, reachable until something ends it</span>
      --attach &lt;ID&gt;           <span class="c">another screen on a running session</span>
      --view-only             <span class="c">and watch it, without typing into it</span>
      --role &lt;NAME&gt;           <span class="c">what this session is for, in one word; main when nothing says</span>
      --role-description &lt;T&gt;  <span class="c">what that role means, for the others</span>
      --logs [FILE] · -v      <span class="c">where the diagnostic log goes, and how much of it</span>
      --json | --cbor         <span class="c">which encoding a reply comes back in</span>

magi doctor                   <span class="c">what a session here would be made of, without starting one</span>
magi fork [PROMPT]            <span class="c">start a child session of this one, and print what it is called</span>
magi verbs                    <span class="c">what it answers, on each of its doors</span>
magi acknowledge              <span class="c">clear the installed packages, so they may run</span>
magi tools                    <span class="c">every tool the model can call, and how each is reached</span>
magi models [--all]           <span class="c">the providers and models melchior knows about</span>
magi lua-api                  <span class="c">the Lua client library for magi's own surface</span>
magi acp                      <span class="c">the Agent Client Protocol on stdio, for an editor. experimental</span>
magi fake-host --replay FILE  <span class="c">serve a recorded session, so the UI can be worked on without a model</span></pre>
      <p>Inside a session, <code>:</code> opens a command — among them <code>:mode</code>,
      <code>:model</code>, <code>:think</code>, <code>:context</code>, <code>:memory</code>,
      <code>:notes</code>, <code>:agents</code>, <code>:crew</code>, <code>:tools</code>,
      <code>:permissions</code>, <code>:rewind</code>, <code>:rename</code>, <code>:env</code>,
      <code>:source</code> and <code>:skills</code> — and <code>/skill &lt;name&gt;</code> runs a
      skill.</p>

      <h2 id="casper">casper</h2>
      <pre>casper tools                  <span class="c">every tool, with schemas</span>
casper run &lt;tool&gt;             <span class="c">one call on stdin, one result on stdout</span>
casper serve --at &lt;PATH&gt;      <span class="c">one process for a session, on a socket; its key on stdin</span>
casper surface &lt;tool&gt;         <span class="c">frames both ways, for as long as it holds its rows</span>
casper mcp                    <span class="c">its own tools as an MCP server, on stdio</span>
  --root &lt;DIR&gt; --tools=a,b    <span class="c">where, and which</span>
casper mcp-auth · mcp-status · mcp-logout   <span class="c">an outside server's OAuth</span>
casper code &lt;PATH&gt;            <span class="c">a source file's outline</span>
casper grammar fetch · build · list         <span class="c">the grammars code parses with</span>
casper image &lt;PATH&gt;           <span class="c">read and resize an image</span>
casper verbs                  <span class="c">what it answers, on each of its doors</span>
casper needs                  <span class="c">what a coordinator may tell it</span>
casper configure              <span class="c">take that configuration, as Lua on stdin</span>
casper acknowledge            <span class="c">clear the installed packages, so their declarations may run</span>
  --json | --cbor             <span class="c">which encoding a reply comes back in</span></pre>

      <h2 id="melchior">melchior</h2>
      <pre>melchior models [--refresh]   <span class="c">what this machine could talk to</span>
melchior card --model &lt;ID&gt;    <span class="c">one model in full</span>
melchior ask                  <span class="c">run a turn; an Ask on stdin</span>
melchior auth login · status · logout       <span class="c">a provider that signs in with OAuth</span>
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
balthasar disagreements       <span class="c">claims that cannot both be true, still waiting on you</span>
balthasar settle              <span class="c">say which of two is right — or reconcile them, or neither</span>
balthasar context             <span class="c">exactly what a model would be told</span>
balthasar sessions            <span class="c">which runs this project has had</span>
balthasar replay              <span class="c">everything a run said, back out again</span>
balthasar ingest              <span class="c">read a source's existing transcripts into memory</span>
balthasar distil              <span class="c">run the extractors over what this project's runs said</span>
balthasar decay               <span class="c">what today's forgetting would take, before it takes it</span>
balthasar consolidate         <span class="c">carry what recurred across sessions — and commits — into the project</span>
balthasar trust · utility     <span class="c">where a memory's evidence came from, and what using it led to</span>
balthasar trace               <span class="c">follow one search to whatever came of it</span>
balthasar eval                <span class="c">measure whether memory earns its place</span>
balthasar train · dataset     <span class="c">fit a ranking from this store, and say whether to believe it</span>
balthasar export · import     <span class="c">every memory, one JSON object per line, and back</span>
balthasar outcomes            <span class="c">what a session reported, and how it went</span>
balthasar init                <span class="c">make this directory the root of its own memory</span>
balthasar configs             <span class="c">install the shipped configuration</span>
  --scope · --tool · --store · --no-config    <span class="c">which memory, and which configuration</span>

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
${note("<b>Two months on, the predictions can be checked.</b> nerv is still 25 units — 23 crates in two workspaces, and two programs that are one crate each — and close to 1,900 commits. It is 327,852 lines of Rust in 1,347 files, tests included, and 26,113 of Lua. Of the ceilings: no file is over 800 lines, the largest is exactly 800, and the compiler still refuses every undeclared edge. The units grew: the median is now 4,982 lines and the largest, magi-host, 55,361 — the unit is still the thing nothing rules. The comparison below is the one made at nine days, and is not redone here: the other two have moved too.")}

      <h2 id="glance">At a glance</h2>
      <p>Every number measured on the checkouts, not read off documentation — at nine days.</p>
${table(["", "pi-ts", "deepseek-ts", "nerv, at nine days"], [
  ["unit", "npm package", "npm package", "cargo crate"],
  ["units", "11", "255", "25, in 4 repositories"],
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
  ["the Lua layer — 9,034 lines across four programs then, 26,113 now", "<b>yes.</b> Tool declarations, provider catalogs, wire protocols and client stubs are files, not code."],
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
      <p>nerv's own tree showed the same force at work: <b>the two programs with production module
      cycles were exactly the two with no gates</b>. That is not a coincidence about those two
      programs; it is what happens wherever nothing refuses. All four run the cycle gate now, and
      none of them has a cycle.</p>
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
      better median. And the <i>unit</i> is unruled: two crates were half of magi, and two months
      later they are nearly two-thirds of it.</p>
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
        <li><b>Authority fixed by link.</b> What casper may do is decided by whoever spawned it — the
        jail is chosen at the spawn — and no call, over argv or over its socket, can name another.
        The same program, reached two ways, with one authority.</li>
      </ul>
      <p>At the time of measurement the whole cross-program surface in magi was 1,632 lines —
      under five per cent of production — carrying in one crate what deepseek-ts spreads across
      seventeen.</p>
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
  ["<b>nerv</b>", "a <b>Lua declaration</b>", "four VMs, one sandbox each — a removal list, not a permission model", "~9,000 lines of Lua when measured, ~26,000 now; examples in every repository"],
])}
      <p>deepseek documents a plugin seam and ships the “unavailable” answer for it. That is
      honest, and it is the whole story. pi is thirteen times our size and is the only one of the
      three that has actually been extended by strangers — which is the fact worth taking
      seriously, and the reason for everything below.</p>

      <h2 id="reach">What a third party can reach</h2>
${table(["", "and how"], [
  ["a tool", "<code>casper.tool</code> for anything that touches the machine, <code>magi.tool</code> for logic or a sibling"],
  ["an MCP server", 'a JSON file in casper\'s data directory — see <a href="../guides/mcp.html">MCP</a>'],
  ["a workflow", 'a Markdown file, picked with <code>/skill</code> — see <a href="../guides/skills.html">skills</a>'],
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
  ["permission model", "3 global modes, allow or deny, not persisted", "<b>none</b>", "4 verbs × 5 widths, with a session ledger; allow, ask and deny rules; four modes"],
  ["dangerous-command analysis", "a shell-out, or ten in-tree danger classes", "none", "<b>none</b> — but <code>auto</code> mode puts each action to a second model"],
  ["OS sandbox", "<b>none</b>, in 527k lines", "none", "casper's jail — bubblewrap, or Landlock and seccomp — and a refusal where neither holds"],
  ["secrets masking", "mask, restore for the human, re-mask on the way out", "none", "masked by value before anything is journalled; keys kept out of every command's environment"],
  ["path confinement", "<code>O_NOFOLLOW</code>, re-stat the descriptor, reject if it moved", "lexical prefix, no canonicalise", "lexical normalise, then prefix — inside a jail that bounds what any path can reach"],
  ["tool declaration", "one implementation <b>per tool</b> — 38 of them", "one per tool", "one <b>per transport</b> — four"],
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
      <p>A declaration runs a program through <code>casper.exec</code>, which takes an
      <b>argument vector</b>. No shell, so a value containing <code>;</code> or <code>$(…)</code>
      is one argument, verbatim. It is the only one of the three where the default way to declare
      a new tool cannot be command-injected.</p>
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
        permitted, not whether it is wise. <code>auto</code> mode puts the decision to a second
        model, shown what was asked for and what is about to run — a judgment, not an analysis.
        pi has ten danger classes.</li>
        <li><b>A grant on <code>sh</code> is an unbounded shell by construction</b>, not by
        bypass — which is what the person asked for, and worth knowing they asked it.</li>
        <li><b>Automatic approvals are not audited.</b> A ledger hit returns quietly, so “what did
        this session do under standing grants” has no answer. pi audits every decision, including
        the ones nobody saw.</li>
        <li><b>File opens were not hardened against the race.</b> Lexical normalise, then read. pi
        canonicalises, opens with <code>O_NOFOLLOW</code>, re-stats the descriptor and refuses if
        it moved. The file tools are casper's now and run inside its jail, which bounds what a race
        could reach; whether each open is hardened as pi's are has not been audited again.</li>
      </ul>
${note("<b>Closed since:</b> containment. The OS sandbox this page once credited to a <code>bwrap</code> in front of one transport is now casper's own jail around every command, with your credential stores, the network's local side and the project's own config walled off — and a refused spawn wherever it cannot be enforced.")}
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
${table(["", "pi", "deepseek", "nerv, at nine days"], [
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

${note("<b>Two months on, melchior is bigger, and this page's headline number is a measurement from nine days.</b> It ships nine providers and nine protocols, still all Lua — 1,352 lines of it — and about 20,000 lines of production Rust. Most of what was added is not the vendor layer: a spending cap and the ledger behind it, usage normalised across six providers' ways of reporting it, prompt caching, model discovery, OAuth, and the coordination between sessions, which lives in the same program. The like-for-like comparison has not been redone, so read “a tenth of the cost” as true of the program it was measured on.")}

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
${note("<b>What was deliberately not taken:</b> the 103-row table itself, the hand-rolled HTTP client, the failover chains, the credential-rotation ring, and the credential scavenging that reads other agents' configuration files. Eight providers answer the same question, and the ninth costs ten lines.")}
`,
});
