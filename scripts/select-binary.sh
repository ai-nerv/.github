#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
member=${1:-}
case "$member" in magi|casper|melchior|balthasar) ;; *) echo 'unknown family member' >&2; exit 2 ;; esac
scratch=$(mktemp -d)
trap 'rm -rf -- "$scratch"' EXIT
set +e
(cd "$root/$member" && timeout --kill-after=2s 30s oslo make family-path) | {
    head -c 65537 > "$scratch/selection"
    wc -c > "$scratch/discarded"
}
code=${PIPESTATUS[0]}
set -e
(( code == 0 )) || { echo "family-path failed for $member: $code" >&2; exit 1; }
[[ $(wc -c < "$scratch/selection") -le 65536 && $(cat "$scratch/discarded") == 0 ]] || {
    echo "family-path output exceeds 64 KiB: $member" >&2; exit 1;
}
cmp -s "$scratch/selection" <(tr -d '\000' < "$scratch/selection") || {
    echo "NUL bytes in family-path output: $member" >&2; exit 1;
}
mapfile -t selections < <(sed -n 's/^NERV_BINARY=//p' "$scratch/selection")
[[ ${#selections[@]} == 1 ]] || { echo "expected one family-path selection: $member" >&2; exit 1; }
path=${selections[0]}
[[ $path == target/* && $path != *'/../'* && $path != */.. && $path != *$'\r'* ]] || {
    echo "invalid relative family-path selection: $member" >&2; exit 1;
}
binary=$(realpath -e -- "$root/$member/$path") || { echo "missing selected binary: $member" >&2; exit 1; }
[[ $binary == "$root/$member/target/"* && -f $binary && -x $binary ]] || {
    echo "selected binary must be an executable file inside $member/target" >&2; exit 1;
}
printf '%s\n' "$binary"
