#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
[[ $# == 1 && $1 == manifests/* ]] || { echo 'usage: preflight.sh manifests/NAME.json' >&2; exit 2; }
source "$root/scripts/preserve-binary.sh"
mkdir -p "$root/target/evaluation"
report=$(mktemp -d "$root/target/evaluation/preflight-XXXXXXXX")
mkdir "$report/bin" "$report/inputs" "$report/lib"
touch "$report/binaries.sha256"
finish() {
    local code=$?
    trap - EXIT
    if [[ -s $report/binaries.sha256 ]] && ! verify_preserved_binaries "$report/binaries.sha256" > "$report/integrity.log" 2>&1; then code=1; fi
    jq -n --argjson code "$code" \
        '{schema:1,scope:"evaluation-input-preflight",status:(if $code==0 then "INPUTS_VALIDATED" else "FAIL" end),exit_code:$code,workers_started:0}' > "$report/summary.json"
    printf 'Evaluation input evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
preserve_binary "$root/target/evaluation/bin/eval-input" "$report/bin/eval-input" "$report/binaries.sha256" > "$report/helper.sha256"
helper="$report/bin/eval-input"
for filter in lexical json manifest schedule contract; do
    "$helper" file "$root/scripts/evaluation" "$filter.jq" "$report/filter-$filter" 131072 1 > "$report/filter-$filter-counts.json"
done
cp "$report/filter-contract/input" "$report/lib/contract.jq"
"$helper" file "$root/scripts/evaluation" "$1" "$report/manifest" 131072 1 > "$report/manifest-counts.json"
manifest="$report/manifest/input"
jq -Rse --argjson safe_integers true -f "$report/filter-lexical/input" "$manifest" > "$report/lexical.json"
jq --stream --slurp -e -f "$report/filter-json/input" "$manifest" > "$report/json.json"
jq -L "$report/lib" -e -f "$report/filter-manifest/input" "$manifest" > "$report/validated.json"
jq -L "$report/lib" -f "$report/filter-schedule/input" "$report/validated.json" > "$report/schedule.json"
jq -r '.tasks[]|[.id,.fixture]|@tsv' "$report/validated.json" > "$report/tasks.tsv"
while IFS=$'\t' read -r id fixture; do
    "$helper" tree "$root/scripts/evaluation" "$fixture" "$report/inputs/$id" 16777216 256 > "$report/$id-counts.json"
    [[ -f $report/inputs/$id/prompt.txt && ! -L $report/inputs/$id/prompt.txt ]] || { echo "missing prompt: $id" >&2; exit 1; }
done < "$report/tasks.tsv"
find "$report/inputs" "$report/manifest" "$report/lib" "$report"/filter-* -type f -exec sha256sum -- {} + > "$report/inputs.sha256"
