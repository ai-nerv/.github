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
| `make run` | magi, with the other three fresh from their builds rather than installed — `make run --args doctor` runs `magi doctor` that way |
| `make install` | every binary to `~/.local/bin`, and each configuration to `~/.config/<name>` |
| `make test` | every suite |
| `make test-family` | build all four, then require live integration tests against those exact binaries in a disposable environment |
| `make verify` | every member's full gate, with the same strict family integration requirements |
| `make status` | each checkout: its branch, commits not pushed, changes not committed |
| `make update` | every checkout to the tip of `develop` |
| `make push` | push each checkout's `develop`, then pin what was pushed here |

## Working on them

Each checkout is a real clone on `develop`. Commit in it as usual; `make push` then pushes it and
records the new commit here, so a fresh `git clone --recursive` gets exactly what you pushed.

The website's source is `site/` — see [site/README.md](site/README.md). The organisation's profile
page is [profile/README.md](profile/README.md).

## Family verification

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

Tests receive disposable HOME/XDG/runtime directories, no inherited provider credentials or
agent sockets, and `MAGI_REQUIRE_LIVE=1`. Missing or incompatible required siblings fail rather
than skip. `CASPER_REQUIRE_CONTAINMENT=1` requires bubblewrap and Landlock kernel coverage;
unsupported hosts cannot pass this lane. Casper's checked-out tool declarations are loaded into the disposable config directory
through its `configs` recipe; the user's installed configuration is untouched.
Cargo dependency resolution is offline during the test stage; prepare any missing
test dependencies through the native environment rather than weakening the gate.

Each run records selected binary paths, commits, dirty flags, hashes, test results, and logs
under `target/family/run-*/`. `summary.json` reports PASS or FAIL. Standalone member tests remain
usable without the rest of the family; their optional live-test skips are not family acceptance.
No paid model calls are part of these recipes.
Processes left running in the disposable tree fail the lane and are terminated, with bounded
escalation to KILL. The summary reports their count as `leaked_processes`.
