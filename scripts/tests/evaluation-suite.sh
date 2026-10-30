#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 2 && $2 =~ ^[0-9a-f]{64}$ ]] || exit 2
binding_root=$(cd -- "$1" && pwd -P) binding_sha=$2
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/suite-tests-XXXXXXXX")
passed=0 running= canary=
finish() {
    local code=$?
    trap - EXIT
    if [[ -n $running ]]; then kill -TERM "$running" 2>/dev/null || true; wait "$running" 2>/dev/null || true; fi
    if [[ -n $canary ]]; then kill "$canary" 2>/dev/null || true; wait "$canary" 2>/dev/null || true; fi
    jq -n --argjson code "$code" --argjson checks "$passed" \
        '{schema:1,scope:"evaluation-offline-suite-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$checks,live_requests:0}' > "$report/summary.json"
    printf 'Evaluation offline suite test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
actual=$(sha256sum < "$binding_root/bindings.json"); [[ ${actual%% *} == "$binding_sha" ]]
select_suite() {
    local name=$1 task=$2 seconds=$3
    selected="$report/$name-bindings"
    cp -R --reflink=auto "$binding_root" "$selected"
    jq --arg suite "$name" --arg task "$task" --argjson seconds "$seconds" \
        '.suite=$suite|.tasks|=map(select(.id==$task)|.timeout_seconds=$seconds)' \
        "$binding_root/manifest/input" > "$selected/manifest/input"
    local manifest_sha
    manifest_sha=$(sha256sum < "$selected/manifest/input"); manifest_sha=${manifest_sha%% *}
    jq --arg task "$task" --arg sha "$manifest_sha" '.manifest_sha256=$sha|.tasks|=map(select(.id==$task))' \
        "$binding_root/bindings.json" > "$selected/bindings.json"
    sha=$(sha256sum < "$selected/bindings.json"); sha=${sha%% *}
}
collect() {
    local name=$1 expected=$2 code=0
    bash "$root/scripts/evaluate.sh" "$selected" "$sha" > "$report/$name.out" 2> "$report/$name.err" || code=$?
    [[ $code == "$expected" ]]
    suite=$(sed -n 's/^Evaluation offline suite: //p' "$report/$name.out")
    jq -e '.status=="SUITE_COLLECTED" and .samples_started==6 and .live_requests==0' "$suite/summary.json" >/dev/null
    aggregate=$(jq -er .aggregate_receipt "$suite/summary.json")
    jq -e '.status=="REPORT_COLLECTED"' "$aggregate/summary.json" >/dev/null
    jq -e --slurpfile plan "$suite/schedule.json" '[.results[].id]==[$plan[0].samples[].id] and
        (.results|length)==6 and (.collection_id|test("^[0-9a-f]{32}$"))' "$suite/index.json" >/dev/null
    jq -se --argjson code "$expected" 'length==6 and all(.[];.exit_code==$code and .result_captured and .evidence_captured) and
        (map(.receipt)|unique|length)==6' "$suite/attempts.jsonl" >/dev/null
    jq -e --arg status "$(if [[ $expected == 0 ]]; then printf PASS; else printf FAIL; fi)" \
        '.status==$status and .collection_errors==[] and (.samples|length)==6' "$aggregate/bundle/report.json" >/dev/null
    while IFS=$'\t' read -r ordinal id path; do
        jq '.sample' "$suite/$path" > "$report/expected.json"
        jq --arg id "$id" '.samples[]|select(.id==$id)' "$aggregate/bundle/report.json" > "$report/collected.json"
        cmp "$report/expected.json" "$report/collected.json"
        cmp "$suite/$path" "$aggregate/retained/$ordinal/raw/input"
    done < <(jq -r '.results|to_entries[]|[.key,.value.id,.value.result]|@tsv' "$suite/index.json")
    passed=$((passed+1))
}
select_suite overflow output-only-overflow 60
collect measured 0
jq -e 'all(.samples[];.status=="PASS" and .failure==null and
    all(.checks[];.status=="PASS") and all(.metrics[];.!=null))' "$aggregate/bundle/report.json" >/dev/null
passed=$((passed+1))
first_collection=$(jq -er .collection_id "$suite/summary.json")
select_suite child child-work 1
collect timeout 1
jq -e 'all(.samples[];.status=="TIMEOUT" and .failure=="prompt_timeout" and
    .cleanup=={leaked_processes:0,remaining_processes:0})' "$aggregate/bundle/report.json" >/dev/null
[[ $(jq -er .collection_id "$suite/summary.json") != "$first_collection" ]]
passed=$((passed+1))
sleep 120 & canary=$!
bash "$root/scripts/evaluate.sh" "$binding_root" "$binding_sha" > "$report/interrupt.out" 2> "$report/interrupt.err" &
running=$!
await_sample() {
sample_pid= controller=
for _ in {1..1000}; do
    children=
    read -r children < "/proc/$running/task/$running/children" || true
    for pid in $children; do
        args=(); mapfile -d '' -t args 2>/dev/null < "/proc/$pid/cmdline" || continue
        [[ ${args[1]:-} == "$root/scripts/evaluation/run-sample.sh" ]] || continue
        grandchildren=
        read -r grandchildren < "/proc/$pid/task/$pid/children" || true
        for child in $grandchildren; do
            args=(); mapfile -d '' -t args 2>/dev/null < "/proc/$child/cmdline" || continue
            if [[ ${args[0]:-} == */bin/eval-world && ${args[1]:-} == control-owned && -s ${args[2]:-}/workload.out ]]; then
                sample_pid=$pid; controller=$child; sample_receipt=${args[2]}; break
            fi
        done
    done
    [[ -z $controller ]] || break
    kill -0 "$running"
    sleep 0.01
done
[[ -n $controller ]]
}
await_sample
kill -TERM "$running"
code=0; wait "$running" || code=$?; running=
[[ $code == 143 ]]
suite=$(sed -n 's/^Evaluation offline suite: //p' "$report/interrupt.out")
jq -e '.status=="INTERRUPTED" and .interrupted==15 and .samples_started==1 and .evaluation_status=="INTERRUPTED"' "$suite/summary.json" >/dev/null
aggregate=$(jq -er .aggregate_receipt "$suite/summary.json")
jq -e '.status=="INTERRUPTED" and .collection_errors==[] and (.samples|length)==60 and
    .samples[0].status=="INTERRUPTED" and .samples[0].cleanup=={leaked_processes:0,remaining_processes:0} and
    all(.samples[1:][];.failure=="missing_result" and .cleanup=={leaked_processes:null,remaining_processes:null})' "$aggregate/bundle/report.json" >/dev/null
[[ $(wc -l < "$suite/attempts.jsonl") == 1 && ! -e $suite/active-sample.json ]]
! kill -0 "$sample_pid" 2>/dev/null
! kill -0 "$controller" 2>/dev/null
kill -0 "$canary"
passed=$((passed+1))
bash "$root/scripts/evaluate.sh" "$binding_root" "$binding_sha" > "$report/owner-death.out" 2> "$report/owner-death.err" &
running=$!
await_sample
suite=$(sed -n 's/^Evaluation suite receipt: //p' "$report/owner-death.out")
kill -KILL "$running"
code=0; wait "$running" 2>/dev/null || code=$?; running=
[[ $code == 137 ]]
for _ in {1..500}; do
    if jq -e '.status=="SAMPLE_PUBLISHED" and .sample_status=="INTERRUPTED"' "$sample_receipt/summary.json" >/dev/null 2>&1; then break; fi
    sleep 0.01
done
jq -e '.status=="SAMPLE_PUBLISHED" and .sample_status=="INTERRUPTED"' "$sample_receipt/summary.json" >/dev/null
jq -e '.interrupted==15 and .cleanup_confirmed and .leaked_processes==0 and .timed_out==false' "$sample_receipt/control.json" >/dev/null
jq -e '.sample.status=="INTERRUPTED" and .sample.cleanup=={leaked_processes:0,remaining_processes:0}' "$sample_receipt/result.json" >/dev/null
[[ ! -e $suite/index.json && ! -e $suite/summary.json && ! -e $suite/attempts/1 ]]
[[ $(sed -n 's/^Evaluation produced sample: //p' "$suite/attempts/0/stdout") == "$sample_receipt" ]]
! kill -0 "$controller" 2>/dev/null
kill -0 "$canary"
passed=$((passed+1))
env -u SHELLOPTS --default-signal=INT bash "$root/scripts/evaluate.sh" "$binding_root" "$binding_sha" \
    > "$report/ctrl-c.out" 2> "$report/ctrl-c.err" &
running=$!
await_sample
ignored=$(awk '/^SigIgn:/ {print $2}' "/proc/$sample_pid/status")
(( (16#$ignored & 2) == 2 ))
kill -INT "$running"
code=0; wait "$running" || code=$?; running=
[[ $code == 130 ]]
suite=$(sed -n 's/^Evaluation offline suite: //p' "$report/ctrl-c.out")
jq -e '.status=="INTERRUPTED" and .interrupted==2 and .samples_started==1 and .evaluation_status=="INTERRUPTED"' "$suite/summary.json" >/dev/null
aggregate=$(jq -er .aggregate_receipt "$suite/summary.json")
jq -e '.status=="INTERRUPTED" and .collection_errors==[] and .samples[0].status=="INTERRUPTED" and
    .samples[0].cleanup=={leaked_processes:0,remaining_processes:0} and
    all(.samples[1:][];.failure=="missing_result")' "$aggregate/bundle/report.json" >/dev/null
[[ $(wc -l < "$suite/attempts.jsonl") == 1 ]]
! kill -0 "$sample_pid" 2>/dev/null
! kill -0 "$controller" 2>/dev/null
kill -0 "$canary"
passed=$((passed+1))
for mode in digest manifest; do
    selected=$binding_root sha=$(printf '%064d' 0)
    if [[ $mode == manifest ]]; then
        selected="$report/invalid-bindings"
        cp -R --reflink=auto "$binding_root" "$selected"
        jq '.kind="live"' "$binding_root/manifest/input" > "$selected/manifest/input"
        manifest_sha=$(sha256sum < "$selected/manifest/input"); manifest_sha=${manifest_sha%% *}
        jq --arg sha "$manifest_sha" '.manifest_sha256=$sha' "$binding_root/bindings.json" > "$selected/bindings.json"
        sha=$(sha256sum < "$selected/bindings.json"); sha=${sha%% *}
    fi
    if bash "$root/scripts/evaluate.sh" "$selected" "$sha" > "$report/$mode.out" 2> "$report/$mode.err"; then exit 1; fi
    suite=$(sed -n 's/^Evaluation offline suite: //p' "$report/$mode.out")
    jq -e '.status=="FAIL" and .samples_started==0 and .evaluation_status=="UNKNOWN"' "$suite/summary.json" >/dev/null
    [[ ! -e $suite/index.json && ! -e $suite/aggregate.out && ! -s $suite/attempts.jsonl ]]
    passed=$((passed+1))
done
printf 'Evaluation offline suite checks passed: %s\n' "$passed"
