#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
[[ $# == 4 ]] || { echo 'usage: evidence.sh ROOT REPORT MANIFEST FROZEN_BINDINGS' >&2; exit 2; }
input_root=$1
source "$root/scripts/preserve-binary.sh"
mkdir -p "$root/target/evaluation"
receipt=$(mktemp -d "$root/target/evaluation/evidence-XXXXXXXX")
mkdir "$receipt/bin" "$receipt/lib" "$receipt/samples" "$receipt/collection"
touch "$receipt/binaries.sha256"
evaluation_status=UNKNOWN
verified_files=0
finish() {
    local code=$?
    trap - EXIT
    if [[ -s $receipt/binaries.sha256 ]] && ! verify_preserved_binaries "$receipt/binaries.sha256" > "$receipt/integrity.log" 2>&1; then code=1; fi
    jq -n --argjson code "$code" --arg status "$evaluation_status" --argjson files "$verified_files" \
        '{schema:1,scope:"evaluation-evidence-integrity",status:(if $code==0 then "EVIDENCE_VALIDATED" else "FAIL" end),
          evaluation_status:$status,exit_code:$code,verified_files:$files,workers_started:0}' > "$receipt/summary.json"
    printf 'Evaluation evidence integrity: %s\n' "$receipt"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
preserve_binary "$root/target/evaluation/bin/eval-input" "$receipt/bin/eval-input" "$receipt/binaries.sha256" > "$receipt/helper.sha256"
helper="$receipt/bin/eval-input"
for filter in lexical json report contract identity sample; do
    "$helper" file "$root/scripts/evaluation" "$filter.jq" "$receipt/filter-$filter" 131072 1 > "$receipt/filter-$filter-counts.json"
done
cp "$receipt/filter-contract/input" "$receipt/lib/contract.jq"
cp "$receipt/filter-identity/input" "$receipt/lib/identity.jq"
cp "$receipt/filter-sample/input" "$receipt/lib/sample.jq"
snapshot_json() {
    local relative=$1 name=$2 limit=$3
    "$helper" file "$input_root" "$relative" "$receipt/$name" "$limit" 1 > "$receipt/$name-counts.json"
    jq -Rse --argjson max_json_bytes "$limit" --argjson safe_integers true -f "$receipt/filter-lexical/input" "$receipt/$name/input" >/dev/null
    jq --stream --slurp -e -f "$receipt/filter-json/input" "$receipt/$name/input" >/dev/null
}
snapshot_json "$2" report 1048576
snapshot_json "$3" manifest 131072
snapshot_json "$4" bindings 131072
manifest_sha=$(sha256sum < "$receipt/manifest/input"); manifest_sha=${manifest_sha%% *}
jq -L "$receipt/lib" -e --slurpfile manifest "$receipt/manifest/input" --slurpfile bindings "$receipt/bindings/input" \
    --arg manifest_sha256 "$manifest_sha" -f "$receipt/filter-report/input" "$receipt/report/input" > "$receipt/validated.json"
jq -r '.samples[]|[.id,(.evidence|length)]|@tsv' "$receipt/validated.json" > "$receipt/samples.tsv"
while IFS=$'\t' read -r id count; do
    [[ $count != 0 ]] || continue
    "$helper" tree "$input_root" "samples/$id" "$receipt/samples/$id" 16777216 32 > "$receipt/$id-counts.json"
    jq -r --arg id "$id" '.samples[]|select(.id==$id)|.evidence[]|[.sha256,.path]|@tsv' "$receipt/validated.json" > "$receipt/expected.tsv"
    actual_count=$(find "$receipt/samples/$id" -type f -printf x | wc -c)
    [[ $actual_count == "$count" ]] || { echo "unlisted evidence in sample: $id" >&2; exit 1; }
    while IFS=$'\t' read -r expected path; do
        actual=$(sha256sum < "$receipt/samples/$id/$path"); actual=${actual%% *}
        [[ $actual == "$expected" ]] || { echo "evidence digest mismatch: $id/$path" >&2; exit 1; }
        verified_files=$((verified_files+1))
    done < "$receipt/expected.tsv"
done < "$receipt/samples.tsv"
jq -r '.collection_errors[]|[.sha256,.path]|@tsv' "$receipt/validated.json" > "$receipt/collection.tsv"
index=0
while IFS=$'\t' read -r expected path; do
    "$helper" file "$input_root" "collection/$path" "$receipt/collection/$index" 1048576 1 > "$receipt/collection-$index-counts.json"
    actual=$(sha256sum < "$receipt/collection/$index/input"); actual=${actual%% *}
    [[ $actual == "$expected" ]] || { echo "collection digest mismatch: $path" >&2; exit 1; }
    verified_files=$((verified_files+1))
    index=$((index+1))
done < "$receipt/collection.tsv"
evaluation_status=$(jq -r '.status' "$receipt/validated.json")
find "$receipt/samples" "$receipt/collection" "$receipt/report" "$receipt/manifest" "$receipt/bindings" "$receipt/lib" \
    "$receipt"/filter-* -type f -exec sha256sum -- {} + > "$receipt/inputs.sha256"
