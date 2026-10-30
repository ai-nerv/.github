#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 7 ]] || exit 2
root=$1 bindings=$2 binding_sha=$3 task=$4 variant=$5 report=$6 id=$7
lib="$root/scripts/evaluation"
helper="$report/bin/eval-input"
worker= interrupted=0 launching=false
cancel() {
    interrupted=$1
    if [[ -n $worker ]]; then kill -TERM "$worker" 2>/dev/null || true
    elif [[ $launching != true ]]; then exit "$((128+$1))"; fi
}
finish() {
    local code=$?
    trap - EXIT
    if [[ -n $worker ]]; then kill -TERM "$worker" 2>/dev/null || true; wait "$worker" 2>/dev/null || true; fi
    exit "$code"
}
trap finish EXIT
trap 'cancel 2' INT
trap 'cancel 15' TERM
mkdir "$report/evidence" "$report/work" "$report/captures"
code=0
launching=true
[[ $interrupted == 0 ]] || exit "$((128+interrupted))"
bash "$lib/run-workload.sh" "$bindings" "$binding_sha" "$task" "$variant" > "$report/workload.out" 2> "$report/workload.err" &
worker=$!
launching=false
[[ $interrupted == 0 ]] || kill -TERM "$worker" 2>/dev/null || true
while :; do code=0; wait "$worker" || code=$?; kill -0 "$worker" 2>/dev/null || break; done
worker=
[[ $interrupted == 0 ]] || exit "$((128+interrupted))"
run=$(sed -n 's/^Evaluation bound workload: //p' "$report/workload.out")
if [[ -z $run ]]; then run=$(sed -n 's/^Evaluation workload receipt: //p' "$report/workload.out" | head -n 1); fi
[[ $run == "$root/target/evaluation/execution-"* && -d $run ]]
printf '%s\n' "$run" > "$report/workload-path"
for name in summary control checks metrics; do
    printf 'null\n' > "$report/work/$name.json"
    if [[ -e $run/$name.json || -L $run/$name.json ]]; then
        "$helper" file "$run" "$name.json" "$report/captures/$name" 1048576 1 >/dev/null
        "$helper" json "$report/captures/$name" input 1048576 >/dev/null
        cp "$report/captures/$name/input" "$report/work/$name.json"
    fi
done
jq -e --arg task "$task" --arg variant "$variant" --arg sha "$binding_sha" \
    '.schema==1 and .scope=="evaluation-bound-workload" and .task_id==$task and .variant==$variant and .bindings_sha256==$sha' \
    "$report/work/summary.json" >/dev/null
jq -n --slurpfile summary "$report/work/summary.json" --slurpfile checks "$report/work/checks.json" --slurpfile metrics "$report/work/metrics.json" \
    '{summary:$summary[0],checks:$checks[0],metrics:$metrics[0]}' > "$report/assembly-base.json"
if jq -e '.status=="NOT_RUN" and .failure=="unsupported_features"' "$report/work/summary.json" >/dev/null; then exit "$code"; fi
jq -nc --slurpfile summary "$report/work/summary.json" --slurpfile control "$report/work/control.json" \
    '{event:"workload_result",record:$summary[0]},{event:"workload_control",record:$control[0]}' > "$report/evidence/events.jsonl"
for name in reconciled-usage normalized-prefix client-attempts client-limit activity; do
    if [[ -e $run/$name.json || -L $run/$name.json ]]; then
        "$helper" file "$run" "$name.json" "$report/captures/$name" 4194304 1 >/dev/null
        "$helper" json "$report/captures/$name" input 16777216 >/dev/null
        jq -nc --arg event "$name" --slurpfile record "$report/captures/$name/input" '{event:$event,record:$record[0]}' >> "$report/evidence/events.jsonl"
    fi
done
if jq -e '.!=null' "$report/work/checks.json" >/dev/null; then cp "$report/work/checks.json" "$report/evidence/checks.json"; fi
if jq -e '.!=null' "$report/work/metrics.json" >/dev/null; then cp "$report/work/metrics.json" "$report/evidence/metrics.json"; fi
world=$(jq -r '.world_receipt//empty' "$report/work/summary.json")
if [[ -n $world ]]; then
    "$helper" tree "$run" "$world/receipt" "$report/raw" 16777216 256 > "$report/raw-counts.json"
    if [[ -e $report/raw/evidence/requests.jsonl || -L $report/raw/evidence/requests.jsonl ]]; then
        "$helper" file "$report/raw" evidence/requests.jsonl "$report/captures/requests" 8388608 1 >/dev/null
        cp "$report/captures/requests/input" "$report/evidence/requests.jsonl"
    fi
    reserved=4096
    while IFS= read -r -d '' file; do reserved=$((reserved+$(wc -c < "$file"))); done < <(find "$report/evidence" -type f -print0)
    bash "$lib/pack-raw.sh" "$report" raw "$reserved" > "$report/pack.out" 2> "$report/pack.err"
    packed=$(sed -n 's/^Evaluation raw package: //p' "$report/pack.out")
    [[ $packed == "$root/target/evaluation/packed-"* ]]
    jq -e '.status=="RAW_PACKED"' "$packed/summary.json" >/dev/null
    "$helper" file "$packed" evidence/raw.tar "$report/captures/archive" 16777216 1 >/dev/null
    cp "$report/captures/archive/input" "$report/evidence/raw.tar"
elif [[ $code == 0 ]]; then
    echo 'completed workload has no world evidence' >&2
    exit 1
fi
"$helper" tree "$report" evidence "$report/worker-evidence" 16773120 31 > "$report/worker-evidence-counts.json"
printf '%s\n' "$id" > "$report/worker-complete"
exit "$code"
