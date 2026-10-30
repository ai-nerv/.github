#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 2 && $2 =~ ^[0-9a-f]{64}$ ]] || exit 2
binding_root=$(cd -- "$1" && pwd -P) binding_sha=$2
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
source "$root/scripts/evaluation/tree-identity.sh"
report=$(mktemp -d "$root/target/evaluation/sample-tests-XXXXXXXX")
passed=0 running=
collection=11111111111111111111111111111111
finish() {
    local code=$?
    trap - EXIT
    if [[ -n $running ]]; then kill -TERM "$running" 2>/dev/null || true; wait "$running" 2>/dev/null || true; fi
    jq -n --argjson code "$code" --argjson passed "$passed" '{schema:1,scope:"evaluation-produced-sample-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$passed,live_requests:0}' > "$report/summary.json"
    printf 'Evaluation produced sample test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
produce() {
    local name=$1 bindings=$2 sha=$3 id=$4 expected=$5 failure=$6 code=0
    bash "$root/scripts/evaluation/run-sample.sh" "$bindings" "$sha" "$id" "$collection" > "$report/$name.out" 2> "$report/$name.err" || code=$?
    if [[ $expected == PASS ]]; then [[ $code == 0 ]]; else [[ $code != 0 ]]; fi
    sample=$(sed -n 's/^Evaluation produced sample: //p' "$report/$name.out")
    [[ -d $sample ]]
    jq -e '.status=="SAMPLE_PUBLISHED"' "$sample/summary.json" >/dev/null
    jq -e --arg status "$expected" --arg failure "$failure" --arg id "$id" '.sample.status==$status and .sample.failure==(if $failure=="null" then null else $failure end) and .sample.id==$id' "$sample/result.json" >/dev/null
    jq -e '.cleanup_confirmed and .leaked_processes==0' "$sample/control.json" >/dev/null
    jq -e --slurpfile control "$sample/control.json" '.sample.elapsed_ms==$control[0].elapsed_ms and .sample.cleanup=={leaked_processes:0,remaining_processes:0}' "$sample/result.json" >/dev/null
    jq -e '.bytes<=16777216 and .files<=32' "$sample/evidence-counts.json" >/dev/null
    while IFS=$'\t' read -r path expected_sha; do
        actual=$(sha256sum < "$sample/sealed-evidence/$path"); [[ ${actual%% *} == "$expected_sha" ]]
    done < <(jq -r '.sample.evidence[]|[.path,.sha256]|@tsv' "$sample/result.json")
    passed=$((passed+1))
}
: > "$report/produced.jsonl"
for variant in baseline candidate; do
    produce "measured-$variant" "$binding_root" "$binding_sha" "output-only-overflow:$variant:1" PASS null
    jq -e 'all(.sample.metrics[];.!=null) and .sample.metrics.output_adjustments==1 and
        .sample.metrics.provider_attempts==2 and all(.sample.checks[];.status=="PASS")' "$sample/result.json" >/dev/null
    [[ -s $sample/sealed-evidence/raw.tar && -s $sample/worker-complete ]]
    jq -se 'any(.[];.event=="workload_result" and .record.status=="WORKLOAD_CHECKED" and .record.metrics_status=="MEASURED")' "$sample/sealed-evidence/events.jsonl" >/dev/null
    jq '.sample.metrics' "$sample/result.json" > "$report/expected-metrics.json"
    cmp "$report/expected-metrics.json" "$sample/sealed-evidence/metrics.json"
    jq -e '.reserved_sample_bytes>=4096 and .archive_bytes+.reserved_sample_bytes<=16777216' "$(sed -n 's/^Evaluation raw package: //p' "$sample/pack.out")/summary.json" >/dev/null
    jq -nc --arg id "output-only-overflow:$variant:1" --arg path "${sample#"$root/"}" \
        '{id:$id,result:($path+"/result.json"),evidence:($path+"/sealed-evidence")}' >> "$report/produced.jsonl"
    passed=$((passed+1))
done
jq -n -L "$root/scripts/evaluation" --arg sha "$binding_sha" --arg collection "$collection" \
    --slurpfile manifest "$binding_root/manifest/input" --slurpfile results "$report/produced.jsonl" '
    include "contract"; ($manifest[0]|planned|map(.id)) as $ids |
    {schema:1,bindings_sha256:$sha,collection_id:$collection,started_at:"2026-10-24T00:00:00Z",finished_at:"2026-10-24T00:01:00Z",
     results:($results|sort_by(.id as $id|$ids|index($id)))}' > "$report/collection.json"
code=0
bash "$root/scripts/evaluation/aggregate.sh" "$root" "${report#"$root/"}/collection.json" "$binding_root" "$binding_sha" \
    > "$report/aggregate.out" 2> "$report/aggregate.err" || code=$?
[[ $code == 1 ]]
aggregate=$(sed -n 's/^Evaluation aggregation: //p' "$report/aggregate.out")
jq -e '.status=="REPORT_COLLECTED" and .evaluation_status=="FAIL"' "$aggregate/summary.json" >/dev/null
jq -e '.collection_errors==[] and ([.samples[]|select(.status=="PASS")]|length)==2 and
    all(.samples[]; .status=="PASS" or .failure=="missing_result")' "$aggregate/bundle/report.json" >/dev/null
while IFS=$'\t' read -r id path; do
    jq '.sample' "$root/$path" > "$report/expected.json"
    jq --arg id "$id" '.samples[]|select(.id==$id)' "$aggregate/bundle/report.json" > "$report/collected.json"
    cmp "$report/expected.json" "$report/collected.json"
done < <(jq -r '.results[]|[.id,.result]|@tsv' "$report/collection.json")
passed=$((passed+1))
cat > "$report/metric-fault.sh" <<'SH'
if [[ $0 == */scripts/evaluation/sample-body.sh ]]; then
    trap 'if [[ $BASH_COMMAND == "worker=" ]]; then
        fault_run=$(sed -n "s/^Evaluation bound workload: //p" "$report/workload.out")
        jq -e '\''.metrics_status=="MEASURED"'\'' "$fault_run/summary.json" >/dev/null
        case $NERV_TEST_METRIC_FAULT in
            missing) rm -- "$fault_run/metrics.json" ;;
            partial) jq '\''.logical_turns=null'\'' "$fault_run/metrics.json" > "$fault_run/fault.tmp"; mv "$fault_run/fault.tmp" "$fault_run/metrics.json" ;;
            invalid-counter) jq '\''.input_tokens=9007199254740992'\'' "$fault_run/metrics.json" > "$fault_run/fault.tmp"; mv "$fault_run/fault.tmp" "$fault_run/metrics.json" ;;
            partial-status) jq '\''.metrics_status="PARTIAL"'\'' "$fault_run/summary.json" > "$fault_run/fault.tmp"; mv "$fault_run/fault.tmp" "$fault_run/summary.json" ;;
            *) exit 2 ;;
        esac
        printf "%s\n" "$NERV_TEST_METRIC_FAULT" > "$report/metric-fault-injected"
    fi' DEBUG
fi
SH
for mode in missing partial invalid-counter partial-status; do
    NERV_TEST_METRIC_FAULT="$mode" BASH_ENV="$report/metric-fault.sh" \
        produce "metric-$mode" "$binding_root" "$binding_sha" "output-only-overflow:candidate:3" FAIL invalid_result
    [[ $(cat "$sample/metric-fault-injected") == "$mode" ]]
    case $mode in
        missing|invalid-counter) jq -e 'all(.sample.metrics[];.==null)' "$sample/result.json" >/dev/null ;;
        partial) jq -e '.sample.metrics.logical_turns==null' "$sample/result.json" >/dev/null ;;
        partial-status) jq -e 'all(.sample.metrics[];.!=null)' "$sample/result.json" >/dev/null ;;
    esac
    passed=$((passed+1))
done
corrupt="$report/capped"
cp -R --reflink=auto "$binding_root" "$corrupt"
jq '(.tasks[]|select(.id=="output-only-overflow")|.max_provider_attempts)=1' "$binding_root/manifest/input" > "$corrupt/manifest/input"
printf '1\n' > "$corrupt/fixtures/output-only-overflow/provider-attempt-limit.txt"
printf '1\n' > "$corrupt/fixtures/output-only-overflow/client-attempt-limit.txt"
manifest_sha=$(sha256sum < "$corrupt/manifest/input"); manifest_sha=${manifest_sha%% *}
tree_identity "$corrupt/fixtures/output-only-overflow" > "$report/capped.tree"
fixture_sha=$(sha256sum < "$report/capped.tree"); fixture_sha=${fixture_sha%% *}
jq --arg manifest "$manifest_sha" --arg fixture "$fixture_sha" '.manifest_sha256=$manifest|
  (.tasks[]|select(.id=="output-only-overflow")|.fixture_sha256)=$fixture' "$binding_root/bindings.json" > "$corrupt/bindings.json"
sha=$(sha256sum < "$corrupt/bindings.json"); sha=${sha%% *}
for variant in baseline candidate; do
    produce "cap-$variant" "$corrupt" "$sha" "output-only-overflow:$variant:2" FAIL attempt_limit
    jq -se 'any(.[];.event=="client-limit" and .record.status=="ATTEMPT_LIMIT_CONFIRMED")' "$sample/sealed-evidence/events.jsonl" >/dev/null
    [[ -s $sample/sealed-evidence/raw.tar ]]
    passed=$((passed+1))
done
timeout_root="$report/timeout"
cp -R --reflink=auto "$binding_root" "$timeout_root"
jq '(.tasks[]|select(.id=="child-work")|.timeout_seconds)=1' "$binding_root/manifest/input" > "$timeout_root/manifest/input"
manifest_sha=$(sha256sum < "$timeout_root/manifest/input"); manifest_sha=${manifest_sha%% *}
jq --arg sha "$manifest_sha" '.manifest_sha256=$sha' "$binding_root/bindings.json" > "$timeout_root/bindings.json"
sha=$(sha256sum < "$timeout_root/bindings.json"); sha=${sha%% *}
produce timeout "$timeout_root" "$sha" child-work:candidate:3 TIMEOUT prompt_timeout
jq -e '.timed_out and .limit_ms==1000' "$sample/control.json" >/dev/null
passed=$((passed+1))
bash "$root/scripts/evaluation/run-sample.sh" "$binding_root" "$binding_sha" child-work:candidate:2 "$collection" \
    > "$report/interrupt.out" 2> "$report/interrupt.err" &
running=$!
child=
for _ in {1..400}; do
    [[ -z $(sed -n 's/^Evaluation produced sample: //p' "$report/interrupt.out") ]] || break
    children=
    read -r children < "/proc/$running/task/$running/children" || true
    for pid in $children; do
        args=()
        mapfile -d '' -t args < "/proc/$pid/cmdline" 2>/dev/null || continue
        if [[ ${args[0]:-} == */bin/eval-world && ${args[1]:-} == control && -d ${args[2]:-}/work ]]; then child=$pid; break; fi
    done
    if [[ -n $child ]]; then break; fi
    sleep 0.01
done
[[ -n $child ]]
kill -TERM "$running"
code=0; wait "$running" || code=$?; running=
[[ $code != 0 ]]
sample=$(sed -n 's/^Evaluation produced sample: //p' "$report/interrupt.out")
jq -e '.status=="SAMPLE_PUBLISHED" and .sample_status=="INTERRUPTED"' "$sample/summary.json" >/dev/null
jq -e '.interrupted==15 and .cleanup_confirmed and .leaked_processes==0' "$sample/control.json" >/dev/null
jq -e '.sample.status=="INTERRUPTED" and .sample.failure=="interrupted" and
    .sample.cleanup=={leaked_processes:0,remaining_processes:0}' "$sample/result.json" >/dev/null
passed=$((passed+1))
cat > "$report/launch-signal.sh" <<'SH'
if [[ $0 == */scripts/evaluation/sample-body.sh ]]; then
    trap 'if [[ $BASH_COMMAND == "worker=\$!" ]]; then
        kill -TERM "$PPID"
        while [[ $interrupted == 0 ]]; do sleep 0.005; done
    fi' DEBUG
fi
SH
code=0
BASH_ENV="$report/launch-signal.sh" bash "$root/scripts/evaluation/run-sample.sh" "$binding_root" "$binding_sha" \
    child-work:candidate:1 "$collection" > "$report/launch-race.out" 2> "$report/launch-race.err" || code=$?
[[ $code != 0 ]]
sample=$(sed -n 's/^Evaluation produced sample: //p' "$report/launch-race.out")
jq -e '.status=="SAMPLE_PUBLISHED" and .sample_status=="INTERRUPTED"' "$sample/summary.json" >/dev/null
jq -e '.interrupted==15 and .cleanup_confirmed and .leaked_processes==0 and .timed_out==false' "$sample/control.json" >/dev/null
[[ ! -e $sample/worker-complete ]]
passed=$((passed+1))
for mode in digest missing-task; do
    sha=$binding_sha id=output-only-overflow:candidate:3
    [[ $mode != digest ]] || sha=$(printf '%064d' 0)
    [[ $mode != missing-task ]] || id=unknown:candidate:3
    if bash "$root/scripts/evaluation/run-sample.sh" "$binding_root" "$sha" "$id" "$collection" > "$report/$mode.out" 2> "$report/$mode.err"; then
        echo "accepted invalid sample input: $mode" >&2; exit 1
    fi
    sample=$(sed -n 's/^Evaluation produced sample: //p' "$report/$mode.out")
    [[ -d $sample && ! -e $sample/result.json && ! -e $sample/control.json && ! -e $sample/workload.out ]]
    passed=$((passed+1))
done
printf 'Evaluation produced sample checks passed: %s\n' "$passed"
