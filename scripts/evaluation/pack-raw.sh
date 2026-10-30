#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 3 && $3 =~ ^(0|[1-9][0-9]{0,7})$ && $3 -le 16777216 ]] || {
    echo 'usage: pack-raw.sh ROOT RELATIVE_TREE RESERVED_SAMPLE_BYTES' >&2; exit 2;
}
input_root=$1 relative=$2 reserved=$3
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
source "$root/scripts/preserve-binary.sh"
source "$root/scripts/evaluation/tree-identity.sh"
mkdir -p "$root/target/evaluation"
report=$(mktemp -d "$root/target/evaluation/packed-XXXXXXXX")
mkdir "$report/bin" "$report/evidence"
touch "$report/binaries.sha256"
bytes=0 archive_sha= tree_sha=
finish() {
    local code=$?
    trap - EXIT
    if [[ -f $report/evidence/raw.tar ]]; then bytes=$(wc -c < "$report/evidence/raw.tar"); fi
    if ! verify_preserved_binaries "$report/binaries.sha256" > "$report/integrity.log" 2>&1; then code=1; fi
    jq -n --argjson code "$code" --argjson bytes "$bytes" --argjson reserved "$reserved" \
        --arg sha "$archive_sha" --arg tree "$tree_sha" \
        '{schema:1,scope:"evaluation-raw-package",status:(if $code==0 then "RAW_PACKED" else "FAIL" end),
          exit_code:$code,archive_format:"pax",archive_bytes:$bytes,reserved_sample_bytes:$reserved,
          archive_sha256:(if $code==0 then $sha else null end),source_tree_sha256:(if $code==0 then $tree else null end),
          evidence:(if $code==0 then [{path:"raw.tar",sha256:$sha}] else [] end),workers_started:0}' > "$report/summary.json"
    printf 'Evaluation raw package: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
preserve_binary "$root/target/evaluation/bin/eval-input" "$report/bin/eval-input" "$report/binaries.sha256" >/dev/null
tar=$(realpath -e -- "$(type -P tar)")
[[ $tar == /nix/store/*/bin/tar ]]
preserve_binary "$tar" "$report/bin/tar" "$report/binaries.sha256" > "$report/tar.sha256"
"$report/bin/eval-input" tree "$input_root" "$relative" "$report/raw" 16777216 256 > "$report/source-counts.json"
tree_identity "$report/raw" > "$report/source-before.tree"
room=$((16777216-reserved))
env -i LC_ALL=C TZ=UTC "$report/bin/tar" --create --file=- --directory="$report/raw" \
    --format=posix --blocking-factor=1 --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner \
    --pax-option=exthdr.name=%d/PaxHeaders/%f,delete=atime,delete=ctime -- . |
    head -c "$((room+1))" > "$report/evidence/raw.tar"
bytes=$(wc -c < "$report/evidence/raw.tar")
(( bytes <= room )) || { echo 'raw archive exceeds remaining sample byte budget' >&2; exit 1; }
tree_identity "$report/raw" > "$report/source-after.tree"
cmp "$report/source-before.tree" "$report/source-after.tree"
tree_sha=$(sha256sum < "$report/source-before.tree"); tree_sha=${tree_sha%% *}
archive_sha=$(sha256sum < "$report/evidence/raw.tar"); archive_sha=${archive_sha%% *}
sha256sum "$report/evidence/raw.tar" > "$report/evidence.sha256"
