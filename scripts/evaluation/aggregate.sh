#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 4 && $4 =~ ^[0-9a-f]{64}$ ]] || {
    echo 'usage: aggregate.sh RESULTS_ROOT ORDERED_INDEX BINDINGS_ROOT BINDINGS_SHA256' >&2; exit 2;
}
input_root=$1 index_path=$2 binding_root=$3 binding_sha=$4
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
source "$root/scripts/preserve-binary.sh"
source "$root/scripts/evaluation/tree-identity.sh"
mkdir -p "$root/target/evaluation"
receipt=$(mktemp -d "$root/target/evaluation/aggregate-XXXXXXXX")
mkdir -p "$receipt/bin" "$receipt/lib" "$receipt/retained" "$receipt/work" \
    "$receipt/bundle/samples" "$receipt/bundle/collection"
touch "$receipt/binaries.sha256" "$receipt/records.jsonl" "$receipt/errors.jsonl"
collected=false evaluation_status=UNKNOWN retained_sha= collection_id=
finish() {
    local code=$?
    trap - EXIT
    if ! verify_preserved_binaries "$receipt/binaries.sha256" > "$receipt/integrity.log" 2>&1; then code=1; collected=false; fi
    if [[ -f $receipt/retained-before.tree ]]; then
        if ! tree_identity "$receipt/retained" > "$receipt/retained-after.tree" ||
           ! cmp "$receipt/retained-before.tree" "$receipt/retained-after.tree" > "$receipt/retained-integrity.log" 2>&1; then
            code=1; collected=false
        fi
    fi
    if [[ -f $receipt/controls.sha256 ]] && ! sha256sum -c "$receipt/controls.sha256" > "$receipt/control-integrity.log" 2>&1; then code=1; collected=false; fi
    jq -n --argjson code "$code" --argjson collected "$collected" --arg status "$evaluation_status" \
        --arg binding "$binding_sha" --arg retained "$retained_sha" --arg collection "$collection_id" \
        '{schema:1,scope:"evaluation-report-collection",status:(if $collected then "REPORT_COLLECTED" else "FAIL" end),
          exit_code:$code,evaluation_status:$status,bindings_sha256:$binding,collection_id:$collection,
          retained_tree_sha256:($retained|if .=="" then null else . end),workers_started:0,live_requests:0}' > "$receipt/summary.json"
    printf 'Evaluation aggregation: %s\n' "$receipt"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
preserve_binary "$root/target/evaluation/bin/eval-input" "$receipt/bin/eval-input" "$receipt/binaries.sha256" >/dev/null
helper="$receipt/bin/eval-input"
for name in lexical json contract identity sample schedule report collection aggregate; do
    "$helper" file "$root/scripts/evaluation" "$name.jq" "$receipt/work/filter-$name" 131072 1 >/dev/null
    cp "$receipt/work/filter-$name/input" "$receipt/lib/$name.jq"
done
json_check() {
    jq -Rse --argjson max_json_bytes "$2" --argjson safe_integers true -f "$receipt/lib/lexical.jq" "$1" >/dev/null &&
    jq --stream --slurp -e -f "$receipt/lib/json.jq" "$1" >/dev/null
}
"$helper" file "$binding_root" bindings.json "$receipt/work/bindings" 131072 1 >/dev/null
actual=$(sha256sum < "$receipt/work/bindings/input"); [[ ${actual%% *} == "$binding_sha" ]]
"$helper" file "$binding_root" manifest/input "$receipt/work/manifest" 131072 1 >/dev/null
cp "$receipt/work/bindings/input" "$receipt/bundle/bindings.json"
cp "$receipt/work/manifest/input" "$receipt/bundle/manifest.json"
json_check "$receipt/bundle/bindings.json" 131072
json_check "$receipt/bundle/manifest.json" 131072
manifest_sha=$(sha256sum < "$receipt/bundle/manifest.json"); manifest_sha=${manifest_sha%% *}
jq -L "$receipt/lib" -e --slurpfile manifest "$receipt/bundle/manifest.json" --arg sha "$manifest_sha" \
    'include "contract"; include "identity"; validate_bindings(($manifest[0]|validate_manifest);$sha)' "$receipt/bundle/bindings.json" >/dev/null
jq -L "$receipt/lib" -f "$receipt/lib/schedule.jq" "$receipt/bundle/manifest.json" | jq '.samples' > "$receipt/schedule.json"
"$helper" file "$input_root" "$index_path" "$receipt/retained/index" 131072 1 >/dev/null
json_check "$receipt/retained/index/input" 131072
jq -L "$receipt/lib" --arg binding_sha "$binding_sha" --slurpfile plan "$receipt/schedule.json" \
    -f "$receipt/lib/collection.jq" "$receipt/retained/index/input" > "$receipt/classified.json"
collection_id=$(jq -er .collection_id "$receipt/retained/index/input")
jq -r '.results[]|[.ordinal,.result,.evidence]|@tsv' "$receipt/classified.json" > "$receipt/paths.tsv"
while IFS=$'\t' read -r ordinal result evidence; do
    entry="$receipt/retained/$ordinal"
    mkdir "$entry"
    raw_ok=true evidence_ok=true
    "$helper" file "$input_root" "$result" "$entry/raw" 1048576 1 > "$entry/raw-counts.json" 2> "$entry/raw.err" || raw_ok=false
    "$helper" tree "$input_root" "$evidence" "$entry/evidence" 16777216 32 > "$entry/evidence-counts.json" 2> "$entry/evidence.err" || evidence_ok=false
    jq -n --argjson raw "$raw_ok" --argjson evidence "$evidence_ok" --arg result "$result" \
        '{raw_ok:$raw,evidence_ok:$evidence,result_path:$result}' > "$entry/capture.json"
done < "$receipt/paths.tsv"
tree_identity "$receipt/retained" > "$receipt/retained-before.tree"
retained_sha=$(sha256sum < "$receipt/retained-before.tree"); retained_sha=${retained_sha%% *}
sha256sum "$receipt/bundle/bindings.json" "$receipt/bundle/manifest.json" "$receipt/lib/"*.jq \
    "$receipt/schedule.json" "$receipt/classified.json" "$receipt/retained-before.tree" > "$receipt/controls.sha256"
validate_entry() {
    local entry=$1 ordinal=$2 id=$3
    jq -e '.raw_ok and .evidence_ok' "$entry/capture.json" >/dev/null || return 1
    json_check "$entry/raw/input" 1048576 || return 1
    jq -L "$receipt/lib" -e --arg id "$id" --arg sha "$binding_sha" --arg collection "$collection_id" \
        --slurpfile plan "$receipt/schedule.json" --slurpfile manifest "$receipt/bundle/manifest.json" \
        --slurpfile bindings "$receipt/bundle/bindings.json" '
        include "contract"; include "sample";
        ($plan[0][]|select(.id==$id)) as $planned |
        ($manifest[0].tasks[]|select(.id==$planned.task_id)) as $task |
        ($bindings[0].tasks[]|select(.id==$planned.task_id)) as $binding |
        if exact(["schema","scope","bindings_sha256","collection_id","sample"]) and .schema==1 and
          .scope=="evaluation-sample-result" and .bindings_sha256==$sha and .collection_id==$collection and
          (try valid_sample(.sample;$planned;$task;$binding;$bindings[0].artifacts) catch false)
        then .sample else error("invalid or stale sample result") end' "$entry/raw/input" > "$receipt/work/sample-$ordinal.json" || return 1
    local sample="$receipt/work/sample-$ordinal.json" path expected actual
    [[ $(jq -r .files "$entry/evidence-counts.json") == "$(jq '.evidence|length' "$sample")" ]] || return 1
    jq -r '.evidence[]|[.path,.sha256]|@tsv' "$sample" > "$receipt/work/evidence-$ordinal.tsv" || return 1
    while IFS=$'\t' read -r path expected; do
        [[ -f $entry/evidence/$path && ! -L $entry/evidence/$path ]] || return 1
        actual=$(sha256sum < "$entry/evidence/$path") || return 1
        [[ ${actual%% *} == "$expected" ]] || return 1
    done < "$receipt/work/evidence-$ordinal.tsv"
}
jq -r '.results[]|[.ordinal,.id,(.kind//"")]|@tsv' "$receipt/classified.json" > "$receipt/entries.tsv"
while IFS=$'\t' read -r ordinal id kind; do
    entry="$receipt/retained/$ordinal"
    if [[ -z $kind ]] && ! validate_entry "$entry" "$ordinal" "$id" > "$receipt/work/validate-$ordinal.out" 2> "$receipt/work/validate-$ordinal.err"; then kind=invalid_result; fi
    if [[ -z $kind ]]; then
        cp -R --reflink=auto "$entry/evidence" "$receipt/bundle/samples/$id"
        jq -nc --arg id "$id" --slurpfile sample "$receipt/work/sample-$ordinal.json" \
            '{id:$id,kind:null,sample:$sample[0]}' >> "$receipt/records.jsonl"
    else
        source="$entry/raw/input"
        if [[ ! -f $source ]]; then source="$entry/capture.json"; fi
        cp "$source" "$receipt/bundle/collection/$ordinal.raw"
        sha=$(sha256sum < "$receipt/bundle/collection/$ordinal.raw"); sha=${sha%% *}
        jq -nc --arg kind "$kind" --arg path "$ordinal.raw" --arg sha "$sha" \
            '{kind:$kind,path:$path,sha256:$sha}' >> "$receipt/errors.jsonl"
        jq -nc --arg id "$id" --arg kind "$kind" '{id:$id,kind:$kind,sample:null}' >> "$receipt/records.jsonl"
    fi
done < "$receipt/entries.tsv"
jq -nc -L "$receipt/lib" --slurpfile manifest "$receipt/bundle/manifest.json" --slurpfile bindings "$receipt/bundle/bindings.json" \
    --slurpfile plan "$receipt/schedule.json" --slurpfile index "$receipt/retained/index/input" \
    --slurpfile records "$receipt/records.jsonl" --slurpfile errors "$receipt/errors.jsonl" \
    -f "$receipt/lib/aggregate.jq" > "$receipt/bundle/report.json"
json_check "$receipt/bundle/report.json" 1048576
jq -L "$receipt/lib" -e --slurpfile manifest "$receipt/bundle/manifest.json" --slurpfile bindings "$receipt/bundle/bindings.json" \
    --arg manifest_sha256 "$manifest_sha" -f "$receipt/lib/report.jq" "$receipt/bundle/report.json" > "$receipt/validated.json"
bash "$root/scripts/evaluation/evidence.sh" "$receipt/bundle" report.json manifest.json bindings.json \
    > "$receipt/evidence-check.out" 2> "$receipt/evidence-check.err"
evaluation_status=$(jq -er .status "$receipt/bundle/report.json")
collected=true
[[ $evaluation_status == PASS ]]
