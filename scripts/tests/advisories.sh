#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
scratch=$(mktemp -d /tmp/nerv-advisory-test.XXXXXX)
trap 'rm -rf -- "$scratch"' EXIT
project="$scratch/project with spaces"
mkdir -p "$project/scripts" "$scratch/bin" "$scratch/cache/registry" "$scratch/cache/git"
cp "$root/scripts/prepare-advisories.sh" "$project/scripts/"
revision=1111111111111111111111111111111111111111
jq -n --arg revision "$revision" '{url:"https://github.com/RustSec/advisory-db.git",revision:$revision}' > "$project/scripts/advisory-db.lock"
printf 'source cache\n' > "$scratch/cache/registry/sentinel"
printf 'do not import\n' > "$scratch/cache/config.toml"
printf 'synthetic do not import\n' > "$scratch/cache/credentials.toml"
for member in magi casper melchior balthasar; do mkdir "$project/$member"; touch "$project/$member/Cargo.toml"; done
cat > "$scratch/bin/git" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == init ]]; then mkdir -p "${@: -1}/.git"; exit; fi
[[ $1 == -C ]] || exit 99
dir=$2; shift 2
while [[ ${1:-} == -c ]]; do shift 2; done
case "$1" in
    remote) [[ $2 == add && $3 == origin && $4 == https://github.com/RustSec/advisory-db.git ]] ;;
    fetch) mkdir -p "$dir/crates"; echo "$PROBE_REV" > "$dir/.git/FETCH_HEAD" ;;
    checkout) cp "$dir/.git/FETCH_HEAD" "$dir/.git/HEAD" ;;
    rev-parse) [[ -f $dir/.git/HEAD ]] || exit 1; cat "$dir/.git/HEAD" ;;
    status) [[ ! -f $dir/dirty ]] || echo ' M crates/synthetic' ;;
    *) echo "unexpected fixture git command: $*" >&2; exit 99 ;;
esac
SH
cat > "$scratch/bin/cargo" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [[ $1 == deny ]]; then
    [[ $2 == --manifest-path && $4 == fetch && $5 == db ]]
    mkdir -p "$CARGO_HOME/advisory-dbs/fixture/.git"
    echo "$PROBE_REV" > "$CARGO_HOME/advisory-dbs/fixture/.git/HEAD"
else
    [[ $1 == fetch && $2 == --locked && $3 == --manifest-path && -f $4 ]]
    [[ -d $CARGO_HOME/registry && ! -L $CARGO_HOME/registry ]]
    [[ -d $CARGO_HOME/git && ! -L $CARGO_HOME/git ]]
    [[ ! -e $CARGO_HOME/config.toml && ! -e $CARGO_HOME/credentials.toml ]]
    touch "$CARGO_HOME/registry/written" "$CARGO_HOME/git/written"
    echo "$4" >> "$PROBE_LOG"
fi
SH
chmod +x "$scratch/bin/"*
export PATH="$scratch/bin:$PATH" CARGO_HOME="$scratch/cache" PROBE_REV="$revision" PROBE_LOG="$scratch/fetches"
run() { "$BASH" "$project/scripts/prepare-advisories.sh" > "$scratch/out" 2>&1; }
run || { cat "$scratch/out"; exit 1; }
home="$project/target/advisories/$revision/cargo"
[[ $(wc -l < "$PROBE_LOG") == 4 ]]
[[ ! -e $CARGO_HOME/registry/written && ! -e $CARGO_HOME/git/written ]]
[[ ! -e $home/config.toml && ! -e $home/credentials.toml ]]
cmp "$CARGO_HOME/registry/sentinel" "$home/registry/sentinel"
jq -e --arg revision "$revision" --arg home "$home" \
    '.revision == $revision and .cargo_home == $home and .private_cache_copy == true' \
    "${home%/cargo}/receipt.json" >/dev/null
run
[[ $(wc -l < "$PROBE_LOG") == 8 ]]
touch "$home/advisory-db/dirty"
if run; then echo 'dirty advisory snapshot was accepted' >&2; exit 1; fi
[[ -f $home/advisory-db/dirty && $(wc -l < "$PROBE_LOG") == 8 ]]
jq '.revision = "invalid"' "$project/scripts/advisory-db.lock" > "$scratch/lock"
mv "$scratch/lock" "$project/scripts/advisory-db.lock"
if run; then echo 'invalid advisory pin was accepted' >&2; exit 1; fi
echo 'advisory inputs: private cache, pinned data, no credentials, idempotence and drift refusals PASS'
