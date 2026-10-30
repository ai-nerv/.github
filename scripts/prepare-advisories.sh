#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
for program in git cargo jq timeout realpath cp mv find; do
    command -v "$program" >/dev/null || { echo "missing advisory prerequisite: $program" >&2; exit 2; }
done
revision=$(jq -er '.revision | select(test("^[0-9a-f]{40}$"))' "$root/scripts/advisory-db.lock")
url=$(jq -er '.url | select(. == "https://github.com/RustSec/advisory-db.git")' "$root/scripts/advisory-db.lock")
source_home=$(realpath -e -- "${CARGO_HOME:-$HOME/.cargo}")
base="$root/target/advisories/$revision"
mkdir -p "$base/cargo"
chmod 700 "$base" "$base/cargo"
for name in registry git; do
    [[ -d $source_home/$name ]] || { echo "missing existing Cargo cache: $name" >&2; exit 2; }
    if [[ -L $base/cargo/$name ]]; then
        [[ $(realpath -e "$base/cargo/$name") == "$source_home/$name" ]] || {
            echo "workspace Cargo cache does not match: $name" >&2; exit 2;
        }
        rm -- "$base/cargo/$name"
    fi
    if [[ ! -e $base/cargo/$name ]]; then
        staging=$(mktemp -d "$base/cache-copy.XXXXXX")
        cp -a --reflink=auto "$source_home/$name/." "$staging/"
        mv -- "$staging" "$base/cargo/$name"
    fi
done
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null GIT_TERMINAL_PROMPT=0
snapshot="$base/cargo/advisory-db"
if [[ ! -d $snapshot/.git ]]; then
    git init -q "$snapshot"
    git -C "$snapshot" remote add origin "$url"
fi
if ! git -C "$snapshot" rev-parse --verify HEAD >/dev/null 2>&1; then
    timeout --kill-after=10s 5m git -C "$snapshot" fetch --depth=1 origin "$revision"
    git -C "$snapshot" -c core.hooksPath=/dev/null checkout -q --detach FETCH_HEAD
fi
[[ $(git -C "$snapshot" rev-parse HEAD) == "$revision" ]] || { echo 'advisory snapshot revision mismatch' >&2; exit 2; }
export CARGO_HOME="$base/cargo"
if [[ ! -d $CARGO_HOME/advisory-dbs ]]; then
    timeout --kill-after=10s 5m cargo deny --manifest-path "$root/magi/Cargo.toml" fetch db
fi
mapfile -t databases < <(find "$CARGO_HOME/advisory-dbs" -mindepth 1 -maxdepth 1 -type d)
[[ ${#databases[@]} == 1 ]] || { echo 'expected one workspace advisory database' >&2; exit 2; }
database=${databases[0]}
if [[ $(git -C "$database" rev-parse HEAD) != "$revision" ]]; then
    git -C "$database" fetch -q --depth=1 "$snapshot" "$revision"
    git -C "$database" -c core.hooksPath=/dev/null checkout -q --detach "$revision"
fi
[[ $(git -C "$database" rev-parse HEAD) == "$revision" ]] || exit 2
for database in "$snapshot" "$database"; do
    [[ -z $(git -C "$database" status --porcelain) ]] || { echo 'advisory snapshot has local changes' >&2; exit 2; }
done
for member in magi casper melchior balthasar; do
    timeout --kill-after=10s 10m cargo fetch --locked --manifest-path "$root/$member/Cargo.toml"
done
jq -n --arg url "$url" --arg revision "$revision" --arg cargo_home "$CARGO_HOME" \
    --arg source_cache "$source_home" --arg deny_database "$database" \
    '{url:$url,revision:$revision,cargo_home:$cargo_home,source_cache:$source_cache,deny_database:$deny_database,private_cache_copy:true}' \
    > "$base/receipt.json"
printf 'NERV_CARGO_HOME=%s\n' "$CARGO_HOME"
