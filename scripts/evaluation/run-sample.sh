#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ ( $# == 4 || $# == 5 ) && $2 =~ ^[0-9a-f]{64}$ && $3 =~ ^[a-z][a-z0-9-]{0,63}:(baseline|candidate):[1-3]$ && $4 =~ ^[0-9a-f]{32}$ && ( $# == 4 || $5 =~ ^[1-9][0-9]{0,9}$ ) ]] || {
    echo 'usage: run-sample.sh BINDINGS_ROOT SHA256 SAMPLE_ID COLLECTION_ID [OWNER_PID]' >&2; exit 2;
}
bindings=$1 binding_sha=$2 id=$3 collection=$4 owner=${5:-}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
source "$root/scripts/preserve-binary.sh"
report=$(mktemp -d "$root/target/evaluation/sample-XXXXXXXX")
mkdir "$report/bin" "$report/lib" "$report/inputs"
touch "$report/binaries.sha256"
published=false sample_status=UNKNOWN supervisor= interrupted=0
finish() {
    local code=$?
    trap - EXIT
    if [[ -n $supervisor ]]; then kill -TERM "$supervisor" 2>/dev/null || true; wait "$supervisor" 2>/dev/null || true; fi
    if ! verify_preserved_binaries "$report/binaries.sha256" > "$report/binary-integrity.log" 2>&1; then code=1; published=false; fi
    if [[ -f $report/inputs.sha256 ]] && ! sha256sum -c "$report/inputs.sha256" > "$report/input-integrity.log" 2>&1; then code=1; published=false; fi
    if [[ $published != true ]]; then rm -f "$report/result.json"; fi
    jq -n --argjson code "$code" --argjson published "$published" --arg status "$sample_status" --arg id "$id" \
      '{schema:1,scope:"evaluation-produced-sample",status:(if $published then "SAMPLE_PUBLISHED" else "FAIL" end),sample_status:$status,id:$id,exit_code:$code,live_requests:0,
        timing_scope:"supervised-workload-measurement-package-and-cleanup",sealing:"bounded-post-cleanup-metadata"}' > "$report/summary.json"
    printf 'Evaluation produced sample: %s\n' "$report"
    exit "$code"
}
forward() { interrupted=$1; if [[ -n $supervisor ]]; then kill -"$1" "$supervisor" 2>/dev/null || true; fi; }
trap finish EXIT
trap 'forward 2' INT
trap 'forward 15' TERM
for name in eval-input eval-world; do preserve_binary "$root/target/evaluation/bin/$name" "$report/bin/$name" "$report/binaries.sha256" >/dev/null; done
preserve_binary "$(type -P jq)" "$report/bin/jq" "$report/binaries.sha256" >/dev/null
helper="$report/bin/eval-input" parser="$report/bin/jq"
for name in contract identity sample assemble-sample; do
    "$helper" file "$root/scripts/evaluation" "$name.jq" "$report/inputs/filter-$name" 131072 1 >/dev/null
    cp "$report/inputs/filter-$name/input" "$report/lib/$name.jq"
done
"$helper" file "$bindings" bindings.json "$report/inputs/bindings" 131072 1 >/dev/null
"$helper" file "$bindings" manifest/input "$report/inputs/manifest" 131072 1 >/dev/null
"$helper" json "$report/inputs/bindings" input 131072 >/dev/null
"$helper" json "$report/inputs/manifest" input 131072 >/dev/null
actual=$(sha256sum < "$report/inputs/bindings/input"); [[ ${actual%% *} == "$binding_sha" ]]
manifest_sha=$(sha256sum < "$report/inputs/manifest/input"); manifest_sha=${manifest_sha%% *}
"$parser" -e -L "$report/lib" --slurpfile manifest "$report/inputs/manifest/input" --arg sha "$manifest_sha" \
    'include "contract"; include "identity"; validate_bindings(($manifest[0]|validate_manifest);$sha)' "$report/inputs/bindings/input" >/dev/null
"$parser" -e -L "$report/lib" --arg id "$id" 'include "contract"; validate_manifest|planned[]|select(.id==$id)' \
    "$report/inputs/manifest/input" > "$report/planned.json"
task=$("$parser" -er .task_id "$report/planned.json")
variant=$("$parser" -er .variant "$report/planned.json")
millis=$("$parser" -er --arg task "$task" '.tasks[]|select(.id==$task)|.timeout_seconds*1000' "$report/inputs/manifest/input")
find "$report/inputs" "$report/lib" -type f -exec sha256sum -- {} + > "$report/inputs.sha256"
sha256sum "$root/scripts/evaluation/sample-body.sh" "$root/scripts/evaluation/run-sample.sh" >> "$report/inputs.sha256"
launcher=$BASHPID
[[ $interrupted == 0 ]] || exit "$((128+interrupted))"
control=(control "$report" "$millis" "$launcher")
if [[ -n $owner ]]; then control=(control-owned "$report" "$millis" "$launcher" "$owner"); fi
"$report/bin/eval-world" "${control[@]}" bash "$root/scripts/evaluation/sample-body.sh" \
    "$root" "$bindings" "$binding_sha" "$task" "$variant" "$report" "$id" > "$report/supervisor.out" 2> "$report/supervisor.err" &
supervisor=$!
[[ $interrupted == 0 ]] || kill -"$interrupted" "$supervisor" 2>/dev/null || true
while :; do code=0; wait "$supervisor" || code=$?; kill -0 "$supervisor" 2>/dev/null || break; done
supervisor=
[[ $interrupted == 0 ]] || code=$((128+interrupted))
mkdir -p "$report/evidence" "$report/work"
if [[ ! -f $report/assembly-base.json ]]; then
    "$parser" -n --arg task "$task" --arg variant "$variant" --arg sha "$binding_sha" --argjson code "$code" \
      '{summary:{schema:1,scope:"evaluation-bound-workload",task_id:$task,variant:$variant,bindings_sha256:$sha,status:"FAIL",failure:"invalid_result",exit_code:$code},checks:null,metrics:null}' > "$report/assembly-base.json"
fi
"$helper" file "$report" assembly-base.json "$report/inputs/assembly" 4194304 1 >/dev/null
"$helper" json "$report/inputs/assembly" input 16777216 >/dev/null
"$helper" file "$report" control.json "$report/inputs/control" 4096 1 >/dev/null
"$helper" json "$report/inputs/control" input 131072 >/dev/null
not_run=false
if "$parser" -e '.summary.status=="NOT_RUN" and .summary.failure=="unsupported_features"' "$report/assembly-base.json" >/dev/null; then not_run=true; fi
worker_complete=false
if [[ -f $report/worker-complete ]] && cmp <(printf '%s\n' "$id") "$report/worker-complete" >/dev/null; then worker_complete=true; fi
if [[ $not_run != true && $worker_complete != true && $code == 0 ]]; then code=1; fi
if [[ $not_run != true ]]; then cp "$report/inputs/control/input" "$report/evidence/cleanup.json"; fi
"$helper" tree "$report" evidence "$report/sealed-evidence" 16777216 32 > "$report/evidence-counts.json"
: > "$report/evidence.jsonl"
while IFS= read -r -d '' file; do
    path=${file#"$report/sealed-evidence/"}
    sha=$(sha256sum < "$file"); sha=${sha%% *}
    "$parser" -nc --arg path "$path" --arg sha "$sha" '{path:$path,sha256:$sha}' >> "$report/evidence.jsonl"
done < <(find "$report/sealed-evidence" -type f -print0 | LC_ALL=C sort -z)
"$parser" --slurpfile control "$report/inputs/control/input" --slurpfile evidence "$report/evidence.jsonl" --argjson code "$code" \
    --argjson complete "$worker_complete" --argjson not_run "$not_run" '
    .control=$control[0]|.evidence=$evidence|.summary.elapsed_ms=$control[0].elapsed_ms|.summary.exit_code=$code|
    if ($complete|not) and ($not_run|not) or ($code!=0 and .summary.status=="WORKLOAD_CHECKED") then
      .summary.status="FAIL"|.summary.failure="invalid_result" else . end' \
    "$report/inputs/assembly/input" > "$report/work/assembly-input.json"
"$parser" -e -L "$report/lib" --slurpfile manifest "$report/inputs/manifest/input" --slurpfile bindings "$report/inputs/bindings/input" \
    --arg manifest_sha "$manifest_sha" --arg binding_sha "$binding_sha" --arg collection "$collection" --arg id "$id" \
    -f "$report/lib/assemble-sample.jq" "$report/work/assembly-input.json" > "$report/result.json"
"$helper" json "$report" result.json 1048576 >/dev/null
sha256sum -c "$report/inputs.sha256" > "$report/input-integrity.log"
sample_status=$("$parser" -er .sample.status "$report/result.json")
published=true
[[ $sample_status == PASS || $sample_status == NOT_RUN ]]
