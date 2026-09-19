#!/usr/bin/env bash
# What the `family` workflow runs, one phase to a step. Kept here rather than in the workflow so
# that what CI does is read, run and changed like any other script of this repository.
#
#   scripts/ci.sh runner     build the pinned recipe runner and put it on the path
#   scripts/ci.sh backend    install the containment backend and see that it works here
#   scripts/ci.sh verify     member gates and required family integration
set -euo pipefail

# v0.7.2: the first oslo release that builds anywhere but its author's machine.
OSLO=86d9ded3cc0929fe57ce1d27dc0de30e3b8488b4

case ${1:-} in
    runner)
        nix build "github:termworks/oslo/$OSLO" --out-link "$RUNNER_TEMP/oslo"
        "$RUNNER_TEMP/oslo/bin/oslo" --version
        echo "$RUNNER_TEMP/oslo/bin" >> "$GITHUB_PATH"
        ;;
    backend)
        sudo apt-get update
        sudo apt-get install -y bubblewrap
        # This image forbids the unprivileged user namespaces the jail is made of; a developer's
        # machine does not, and the jail is what is under test, not the image's policy.
        sudo sysctl -w kernel.apparmor_restrict_unprivileged_userns=0 || true
        bwrap --ro-bind / / true
        ;;
    verify)
        # As a path and not through git: a checkout made for CI is not one nix will read a
        # flake out of, and what is verified is the tree on disk either way.
        shell=(nix develop "path:$PWD/magi" --command)
        # Verification runs offline on purpose, so that nothing it proves depends on the network;
        # a developer's cache is warm and this machine's is empty. Everything the lockfiles name
        # is fetched first, for every target and feature, which is what `clippy --all-features`
        # reaches and an ordinary build does not.
        for member in magi casper melchior balthasar; do
            "${shell[@]}" cargo fetch --locked --manifest-path "$member/Cargo.toml"
        done
        "${shell[@]}" oslo make verify
        ;;
    *)
        echo "usage: scripts/ci.sh runner | backend | verify" >&2
        exit 2
        ;;
esac
