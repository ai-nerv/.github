#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 2 && $2 =~ ^[0-9a-f]{64}$ ]] || {
    echo 'usage: run-suite.sh FROZEN_BINDINGS BINDINGS_SHA256' >&2; exit 2;
}
bindings=$1 binding_sha=$2
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
source "$root/scripts/preserve-binary.sh"
report=$(mktemp -d "$root/target/evaluation/suite-XXXXXXXX")
mkdir "$report/bin" "$report/lib" "$report/inputs" "$report/bindings" "$report/results" "$report/attempts"
touch "$report/binaries.sha256" "$report/attempts.jsonl" "$report/results.jsonl"
running= interrupted=0 started=0 collected=false evaluation_status=UNKNOWN collection= aggregate=
owner=$BASHPID
finish() {
    local code=$?
    trap - EXIT
    if [[ -n $running ]]; then kill -TERM "$running" 2>/dev/null || true; wait "$running" 2>/dev/null || true; fi
    if ! verify_preserved_binaries "$report/binaries.sha256" > "$report/binary-integrity.log" 2>&1; then code=1; collected=false; fi
    if [[ -f $report/inputs.sha256 ]] && ! sha256sum -c "$report/inputs.sha256" > "$report/input-integrity.log" 2>&1; then code=1; collected=false; fi
    jq -n --argjson code "$code" --argjson collected "$collected" --argjson interrupted "$interrupted" \
        --argjson started "$started" --arg binding "$binding_sha" --arg collection "$collection" \
        --arg status "$evaluation_status" --arg aggregate "$aggregate" \
        '{schema:1,scope:"evaluation-offline-suite",status:(if $interrupted!=0 then "INTERRUPTED" elif $collected then "SUITE_COLLECTED" else "FAIL" end),
          exit_code:$code,interrupted:$interrupted,samples_started:$started,bindings_sha256:$binding,
          collection_id:$collection,evaluation_status:$status,aggregate_receipt:$aggregate,live_requests:0}' > "$report/summary.json"
    printf 'Evaluation offline suite: %s\n' "$report"
    exit "$code"
}
forward() { interrupted=$1; if [[ -n $running ]]; then kill -TERM "$running" 2>/dev/null || true; fi; }
trap finish EXIT
trap 'forward 2' INT
trap 'forward 15' TERM
printf 'Evaluation suite receipt: %s\n' "$report"
for name in eval-input; do preserve_binary "$root/target/evaluation/bin/$name" "$report/bin/$name" "$report/binaries.sha256" >/dev/null; done
preserve_binary "$(type -P jq)" "$report/bin/jq" "$report/binaries.sha256" >/dev/null
helper="$report/bin/eval-input" parser="$report/bin/jq"
for name in contract identity schedule; do
    "$helper" file "$root/scripts/evaluation" "$name.jq" "$report/inputs/filter-$name" 131072 1 >/dev/null
    cp "$report/inputs/filter-$name/input" "$report/lib/$name.jq"
done
"$helper" file "$bindings" bindings.json "$report/inputs/bindings" 131072 1 >/dev/null
"$helper" file "$bindings" manifest/input "$report/bindings/manifest" 131072 1 >/dev/null
cp "$report/inputs/bindings/input" "$report/bindings/bindings.json"
"$helper" json "$report/bindings" bindings.json 131072 >/dev/null
"$helper" json "$report/bindings" manifest/input 131072 >/dev/null
actual=$(sha256sum < "$report/bindings/bindings.json"); [[ ${actual%% *} == "$binding_sha" ]]
manifest_sha=$(sha256sum < "$report/bindings/manifest/input"); manifest_sha=${manifest_sha%% *}
"$parser" -e -L "$report/lib" --slurpfile manifest "$report/bindings/manifest/input" --arg sha "$manifest_sha" \
    'include "contract"; include "identity"; validate_bindings(($manifest[0]|validate_manifest);$sha)' "$report/bindings/bindings.json" >/dev/null
"$parser" -e -L "$report/lib" -f "$report/lib/schedule.jq" "$report/bindings/manifest/input" > "$report/schedule.json"
"$parser" -r '.samples|to_entries[]|[.key,.value.id]|@tsv' "$report/schedule.json" > "$report/schedule.tsv"
collection=$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')
[[ $collection =~ ^[0-9a-f]{32}$ ]]
started_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
find "$report/inputs" "$report/bindings" "$report/lib" -type f -exec sha256sum -- {} + > "$report/inputs.sha256"
sha256sum "$report/schedule.json" "$report/schedule.tsv" "$root/scripts/evaluate.sh" "$root/scripts/evaluation/run-suite.sh" \
    "$root/scripts/evaluation/run-sample.sh" "$root/scripts/evaluation/aggregate.sh" >> "$report/inputs.sha256"
while IFS=$'\t' read -r ordinal id; do
    [[ $interrupted == 0 ]] || break
    attempt="$report/attempts/$ordinal"
    result="$report/results/$ordinal"
    mkdir "$attempt" "$result" "$result/empty-evidence"
    bash "$root/scripts/evaluation/run-sample.sh" "$bindings" "$binding_sha" "$id" "$collection" "$owner" \
        > "$attempt/stdout" 2> "$attempt/stderr" &
    running=$!
    started=$((started+1))
    "$parser" -n --arg id "$id" --argjson ordinal "$ordinal" --argjson pid "$running" \
        '{id:$id,ordinal:$ordinal,pid:$pid}' > "$report/active-sample.json"
    [[ $interrupted == 0 ]] || kill -TERM "$running" 2>/dev/null || true
    while :; do code=0; wait "$running" || code=$?; kill -0 "$running" 2>/dev/null || break; done
    running=
    rm -f "$report/active-sample.json"
    source= raw_ok=false evidence_ok=false
    mapfile -t receipts < <(sed -n 's/^Evaluation produced sample: //p' "$attempt/stdout")
    if [[ ${#receipts[@]} == 1 && ${receipts[0]} =~ ^"$root"/target/evaluation/sample-[A-Za-z0-9]{8}$ ]]; then
        source=${receipts[0]}
        "$helper" file "$source" result.json "$result/raw" 1048576 1 > "$attempt/raw-counts.json" 2> "$attempt/raw.err" && raw_ok=true
        "$helper" tree "$source" sealed-evidence "$result/evidence" 16777216 32 > "$attempt/evidence-counts.json" 2> "$attempt/evidence.err" && evidence_ok=true
    fi
    "$parser" -n --arg id "$id" --argjson ordinal "$ordinal" --argjson code "$code" \
        --arg receipt "${source#"$root/"}" --argjson raw "$raw_ok" --argjson evidence "$evidence_ok" \
        '{ordinal:$ordinal,id:$id,exit_code:$code,receipt:$receipt,result_captured:$raw,evidence_captured:$evidence}' > "$attempt/capture.json"
    "$parser" -c . "$attempt/capture.json" >> "$report/attempts.jsonl"
    result_path="attempts/$ordinal/capture.json" evidence_path="results/$ordinal/empty-evidence"
    [[ $raw_ok != true ]] || result_path="results/$ordinal/raw/input"
    [[ $evidence_ok != true ]] || evidence_path="results/$ordinal/evidence"
    "$parser" -nc --arg id "$id" --arg result "$result_path" --arg evidence "$evidence_path" \
        '{id:$id,result:$result,evidence:$evidence}' >> "$report/results.jsonl"
done < "$report/schedule.tsv"
finished_at=$(date -u +%Y-%m-%dT%H:%M:%SZ)
"$parser" -n --arg sha "$binding_sha" --arg collection "$collection" --arg started "$started_at" --arg finished "$finished_at" \
    --slurpfile results "$report/results.jsonl" \
    '{schema:1,bindings_sha256:$sha,collection_id:$collection,started_at:$started,finished_at:$finished,results:$results}' > "$report/index.json"
code=0
bash "$root/scripts/evaluation/aggregate.sh" "$report" index.json "$report/bindings" "$binding_sha" \
    > "$report/aggregate.out" 2> "$report/aggregate.err" || code=$?
aggregate=$(sed -n 's/^Evaluation aggregation: //p' "$report/aggregate.out")
[[ $aggregate =~ ^"$root"/target/evaluation/aggregate-[A-Za-z0-9]{8}$ ]]
"$parser" -e '.status=="REPORT_COLLECTED"' "$aggregate/summary.json" >/dev/null
evaluation_status=$("$parser" -er .status "$aggregate/bundle/report.json")
collected=true
[[ $interrupted == 0 ]] || exit "$((128+interrupted))"
[[ $code == 0 && $evaluation_status == PASS ]]
