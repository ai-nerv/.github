<p align="center"><img src="profile/nerv.svg" width="120" alt="nerv"></p>

# nerv

A coding agent for Linux, in four programs that share no code. Each is its own repository; this
one holds all four as submodules and builds them together.

| | |
|---|---|
| [magi](https://github.com/ai-nerv/magi) | the harness — the one you run |
| [casper](https://github.com/ai-nerv/casper) | the tools, and the screen they draw on |
| [melchior](https://github.com/ai-nerv/melchior) | the model, and the other agents |
| [balthasar](https://github.com/ai-nerv/balthasar) | memory, in its own process |

## Getting it

```sh
git clone --recursive https://github.com/ai-nerv/.github nerv
cd nerv
oslo make install
```

The recipes need `oslo` and a Rust toolchain. At an oslo prompt in this directory `make` is
enough; elsewhere it is `oslo make`. Inside a checkout, `make` means that program's own recipes.

| recipe | does |
|---|---|
| `make build` | every binary |
| `make run` | magi and siblings from verified snapshots of their owner-selected build targets, never newest-mtime or installed fallbacks — `make run --args doctor` runs `magi doctor` that way |
| `make install` | every binary to `~/.local/bin`, and each configuration to `~/.config/<name>` |
| `make test` | every suite |
| `make test-family` | build all four, then require live integration tests against those exact binaries in a disposable environment |
| `make verify` | every member's full gate, with the same strict family integration requirements |
| `make baseline` | record runner fixtures, exact-family tests, deterministic acceptance and full verification, stopping at the first failure |
| `make prepare-advisories` | prepare pinned security-advisory data and locked package caches under `target/advisories/` for offline checks |
| `make test-launch-selection` | exercise authoritative target selection, rejection cases, spaces and argument forwarding in disposable checkouts |
| `make status` | each checkout: its branch, commits not pushed, changes not committed |
| `make update` | every checkout to the tip of `develop` |
| `make push` | push each checkout's `develop`, then pin what was pushed here |

`make run` keeps one private, hash-verified family directory per executable set under
`target/launch/` and puts only that directory first on `PATH`. Rebuilding the checkout does
not replace bytes used by an existing session. These snapshots remain after the UI exits;
remove them only when no detached session still uses them.

Opt-in, never part of `verify` or CI, each needing its own fixture: `make test-images` (image
delivery against a local provider fixture), `make test-mcp-blender` and `make test-images-blender`
(a running Blender with its MCP addon; `mcp-for-blender` is installed from the hash-pinned
`scripts/mcp-for-blender.lock`), and `make test-images-openrouter` (a live, capped run).

## With Nix

Each program is its own flake, and each release publishes a static build for x86_64 and aarch64
Linux to the `ai-nerv` Cachix cache. magi finds the other three on `PATH`, so install all four:

```sh
cachix use ai-nerv
nix profile install github:ai-nerv/magi github:ai-nerv/casper \
  github:ai-nerv/melchior github:ai-nerv/balthasar
```

Each package carries its default configuration under `share/<name>/config`; `make install` from a
checkout puts it in `~/.config/<name>`. `casper grammar fetch` gets the grammars `code` parses with.

## Working on them

Each checkout is a real clone on `develop`. Commit in it as usual; `make push` then pushes it and
records the new commit here, so a fresh `git clone --recursive` gets exactly what you pushed.

The website's source is `site/` — see [site/README.md](site/README.md). The organisation's profile
page is [profile/README.md](profile/README.md).

## Family verification

Audit input preparation is explicit and may download the pinned RustSec database and packages
already declared in the member lockfiles. It copies existing Cargo caches into private workspace
storage; it does not import Cargo configuration/credentials or change installed state:

```sh
nix develop ./magi --command oslo make prepare-advisories
CARGO_HOME="$PWD/target/advisories/$(jq -r .revision scripts/advisory-db.lock)/cargo" \
  nix develop ./magi --command oslo make baseline
```

Audit/deny checks remain offline and retain each member's dependency policy. Advisory findings
are failures to resolve, not permission to add exclusions. The prepared snapshot receipt records
its exact revision and cache locations.

In an ordinary shell use `oslo make test-family` or `oslo make verify`. With the pinned toolchain:

```sh
nix develop ./magi --command oslo make test-family
```

The runner needs Bash, Git, jq, coreutils, and Oslo. Recipes select native `/bin/bash` when
available; `NERV_BASH` can name another real Bash executable. Each member reports the binary its build
recipe selected; installed copies and newer unrelated artifacts are not substituted. Custom
`CARGO_TARGET_DIR` and `CARGO_BUILD_TARGET` overrides are refused by this lane.
Magi's process tests receive the selected executable through `MAGI_TEST_BINARY`; standalone
tests use Cargo's executable when that override is absent.
Casper's complete-source edit fixtures similarly use `CASPER_TEST_BINARY` in the family lane,
covering both doors/backends against the selected Casper rather than an unrelated build.
The native Magi host lane also receives `CASPER_TEST_TOOLS`, the selected shipped
`tools.lua` installed into the disposable fixture. Its native and shipped-declaration
cases both exercise ownership, stale guards, no-replace creation and reply-loss
recovery. Standalone `oslo make test-native-file-revisions` in Magi requires explicit
absolute `CASPER_TEST_BINARY` and `CASPER_TEST_TOOLS` paths plus `MAGI_REQUIRE_LIVE=1`.

Tests receive disposable HOME/XDG/runtime directories, a kernel-checked private `/var/tmp`
coordination domain, no inherited provider credentials or
agent sockets, and `MAGI_REQUIRE_LIVE=1`. Missing or incompatible required siblings fail rather
than skip. `CASPER_REQUIRE_CONTAINMENT=1` requires bubblewrap and Landlock kernel coverage;
unsupported hosts cannot pass this lane. Casper's checked-out tool declarations are loaded into the disposable config directory
through its `configs` recipe; the user's installed configuration is untouched.
Cargo dependency resolution is offline during the test stage; prepare any missing
test dependencies through the native environment rather than weakening the gate.

Family, deterministic acceptance and selected native-MCP runs preserve read-only
executable copies in their report's `bin/` directory. Acceptance also preserves its
HTTP provider and session-client fixtures. Runs use these copies and check their
hashes before member tests or scenarios and at exit.
Rebuilding a Cargo target cannot replace the selected runtime. Receipts retain the
original build location as `source_path` and the exercised copy as `path`.
`oslo make test-family-selection` checks build-output replacement and artifact-integrity refusal.
`oslo make test-preserved-binaries` checks the shared snapshot contract, including
paths with spaces, invalid destinations, missing sources and corrupted copies.

Each run records selected binary paths, commits, dirty flags, hashes, test results, and logs
under `target/family/run-*/`. `summary.json` reports PASS or FAIL. Standalone member tests remain
usable without the rest of the family; their optional live-test skips are not family acceptance.
No paid model calls are part of these recipes.
Processes left running in the disposable tree fail the lane and are terminated, with bounded
escalation to KILL. The summary reports their count as `leaked_processes`.

`oslo make baseline` writes `target/roadmap/00/run-*/receipt.json` before running its gates.
It retains exit codes, interruptions, timing, logs, toolchain facts and referenced gate summaries;
the selected family hashes must agree across gates. A failed gate leaves later cases NOT_RUN.
Logs are capped at 32 MiB per gate; overflow fails the receipt. Focused acceptance (`NERV_ONLY`)
cannot establish a full baseline. Optional missing audit tools are recorded separately from
required-case failures. A private, hash-recorded copy of bubblewrap keeps Nix store hardlinks
out of launcher selection without weakening Casper's launcher checks.
`oslo make test-receipts` exercises the recorder and rejects incomplete or contradictory reports.
The baseline does not run installs, change installed configuration or invoke paid acceptance.
