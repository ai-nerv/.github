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
| `make status` | each checkout: its branch, commits not pushed, changes not committed |
| `make update` | every checkout to the tip of `develop` |
| `make push` | push each checkout's `develop`, then pin what was pushed here |

## Working on them

Each checkout is a real clone on `develop`. Commit in it as usual; `make push` then pushes it and
records the new commit here, so a fresh `git clone --recursive` gets exactly what you pushed.

The website's source is `site/` — see [site/README.md](site/README.md). The organisation's profile
page is [profile/README.md](profile/README.md).
