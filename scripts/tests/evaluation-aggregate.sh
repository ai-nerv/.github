#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/aggregate-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" \
        '{schema:1,scope:"evaluation-aggregation-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$passed,workers_started:0}' > "$report/summary.json"
    printf 'Evaluation aggregation test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
bundle="$report/input"
mkdir -p "$bundle/bindings/manifest" "$bundle/results"
jq '.suite="overflow"|.tasks|=map(select(.id=="output-only-overflow"))' \
    "$root/scripts/evaluation/manifests/offline.json" > "$bundle/bindings/manifest/input"
manifest_sha=$(sha256sum < "$bundle/bindings/manifest/input"); manifest_sha=${manifest_sha%% *}
jq -n --arg sha "$manifest_sha" '{schema:2,manifest_sha256:$sha,runner_sha256:("a"*64),
 artifacts:{baseline:("b"*64),candidate:("c"*64)},tasks:[{id:"output-only-overflow",fixture_sha256:("d"*64),
 config_sha256:{baseline:("e"*64),candidate:("f"*64)},models:[{provider:"evaluation",id:"echo-1",api:"openai-completions"}]}]}' \
    > "$bundle/bindings/bindings.json"
binding_sha=$(sha256sum < "$bundle/bindings/bindings.json"); binding_sha=${binding_sha%% *}
jq -L "$root/scripts/evaluation" -f "$root/scripts/evaluation/schedule.jq" "$bundle/bindings/manifest/input" | jq '.samples' > "$report/schedule.json"
printf '{"synthetic":true}\n' > "$report/content"
content_sha=$(sha256sum < "$report/content"); content_sha=${content_sha%% *}
for ordinal in {0..5}; do
    mkdir -p "$bundle/results/$ordinal/evidence"
    for name in requests.jsonl events.jsonl checks.json cleanup.json; do cp "$report/content" "$bundle/results/$ordinal/evidence/$name"; done
    jq -n -L "$root/scripts/evaluation" --argjson ordinal "$ordinal" --arg sha "$binding_sha" --arg content "$content_sha" \
        --slurpfile plan "$report/schedule.json" --slurpfile bindings "$bundle/bindings/bindings.json" '
        include "sample";
        $plan[0][$ordinal] as $p | $bindings[0] as $b | $b.tasks[0] as $t |
        {schema:1,scope:"evaluation-sample-result",bindings_sha256:$sha,collection_id:("1"*32),sample:{schema:2,id:$p.id,status:"PASS",failure:null,
          artifact_sha256:$b.artifacts[$p.variant],fixture_sha256:$t.fixture_sha256,config_sha256:$t.config_sha256[$p.variant],models:$t.models,
          elapsed_ms:10,exit_code:0,checks:["same-input","lower-output","no-summary"]|map({id:.,status:"PASS",evidence_path:"checks.json"}),
          metrics:((metric_names|map({key:.,value:0})|from_entries)+{logical_turns:1,provider_attempts:1,request_bytes:19}),
          cleanup:{leaked_processes:0,remaining_processes:0},resources:{status:"NOT_MEASURED",peak_rss_bytes:null,cpu_ms:null},
          evidence:["requests.jsonl","events.jsonl","checks.json","cleanup.json"]|map({path:.,sha256:$content})}}' > "$bundle/results/$ordinal/result.json"
done
jq -n --arg sha "$binding_sha" --slurpfile plan "$report/schedule.json" '{schema:1,bindings_sha256:$sha,collection_id:("1"*32),
    started_at:"2026-10-22T00:00:00Z",finished_at:"2026-10-22T00:01:00Z",
    results:[$plan[0]|to_entries[]|{id:.value.id,result:("results/"+(.key|tostring)+"/result.json"),evidence:("results/"+(.key|tostring)+"/evidence")} ]}' > "$bundle/index.json"
cp "$bundle/index.json" "$report/original-index.json"
cp "$bundle/results/0/result.json" "$report/original-result.json"
collect() {
    local name=$1 expected=$2 code=0
    bash "$root/scripts/evaluation/aggregate.sh" "$bundle" index.json "$bundle/bindings" "$binding_sha" > "$report/$name.out" 2> "$report/$name.err" || code=$?
    [[ $code == "$expected" ]] || { cat "$report/$name.err" >&2; return 1; }
    result=$(sed -n 's/^Evaluation aggregation: //p' "$report/$name.out")
    jq -e '.status=="REPORT_COLLECTED" and .workers_started==0' "$result/summary.json" >/dev/null
    [[ -s $result/retained-before.tree ]]
    cmp "$result/retained-before.tree" "$result/retained-after.tree"
    passed=$((passed+1))
}
collect valid 0
jq -e '.status=="PASS" and (.samples|length)==6 and .collection_errors==[]' "$result/bundle/report.json" >/dev/null
for ordinal in {0..5}; do cmp "$bundle/results/$ordinal/result.json" "$result/retained/$ordinal/raw/input"; done
for mode in empty missing duplicate unknown reorder stale stale-batch missing-metric failed interrupted timeout invalid-json duplicate-key changed-bytes extra-file missing-file unsafe-file unsafe-result wrong-id wrong-artifact; do
    cp "$report/original-index.json" "$bundle/index.json"
    cp "$report/original-result.json" "$bundle/results/0/result.json"
    case $mode in
        empty) jq '.results=[]' "$report/original-index.json" > "$bundle/index.json" ;;
        missing) jq '.results|=.[1:]' "$report/original-index.json" > "$bundle/index.json" ;;
        duplicate) jq '.results=[.results[0]]+.results' "$report/original-index.json" > "$bundle/index.json" ;;
        unknown) jq '.results+=[(.results[0]+{id:"unknown:baseline:1"})]' "$report/original-index.json" > "$bundle/index.json" ;;
        reorder) jq '.results|=reverse' "$report/original-index.json" > "$bundle/index.json" ;;
        stale) jq '.bindings_sha256=("0"*64)' "$report/original-result.json" > "$bundle/results/0/result.json" ;;
        stale-batch) jq '.collection_id=("2"*32)' "$report/original-result.json" > "$bundle/results/0/result.json" ;;
        missing-metric) jq '.sample.metrics.provider_attempts=null' "$report/original-result.json" > "$bundle/results/0/result.json" ;;
        failed) jq '.sample.status="FAIL"|.sample.failure="check_failed"|.sample.metrics.provider_attempts=null|.sample.cleanup.leaked_processes=1' "$report/original-result.json" > "$bundle/results/0/result.json" ;;
        interrupted) jq '.sample.status="INTERRUPTED"|.sample.failure="interrupted"|.sample.exit_code=130' "$report/original-result.json" > "$bundle/results/0/result.json" ;;
        timeout) jq '.sample.status="TIMEOUT"|.sample.failure="prompt_timeout"|.sample.elapsed_ms=60001' "$report/original-result.json" > "$bundle/results/0/result.json" ;;
        invalid-json) printf '\377invalid\n' > "$bundle/results/0/result.json" ;;
        duplicate-key) printf '{"schema":1,"schema":1}\n' > "$bundle/results/0/result.json" ;;
        changed-bytes) printf 'changed\n' > "$bundle/results/0/evidence/checks.json" ;;
        extra-file) : > "$bundle/results/0/evidence/extra" ;;
        missing-file) rm "$bundle/results/0/evidence/checks.json" ;;
        unsafe-file) rm "$bundle/results/0/evidence/checks.json"; ln -s "$report/content" "$bundle/results/0/evidence/checks.json" ;;
        unsafe-result) rm "$bundle/results/0/result.json"; ln -s "$report/original-result.json" "$bundle/results/0/result.json" ;;
        wrong-id) jq '.sample.id="output-only-overflow:candidate:3"' "$report/original-result.json" > "$bundle/results/0/result.json" ;;
        wrong-artifact) jq '.sample.artifact_sha256=("0"*64)' "$report/original-result.json" > "$bundle/results/0/result.json" ;;
    esac
    collect "$mode" 1
    jq -e '.status!="PASS" and (.samples|length)==6' "$result/bundle/report.json" >/dev/null
    case $mode in
        empty|missing)
            jq -e '.samples[0].failure=="missing_result" and all(.samples[0].metrics[]; .==null) and
                .samples[0].cleanup=={leaked_processes:null,remaining_processes:null}' "$result/bundle/report.json" >/dev/null ;;
        duplicate) jq -e '[.collection_errors[].kind]==["duplicate_result","duplicate_result"] and .samples[0].status=="FAIL"' "$result/bundle/report.json" >/dev/null ;;
        unknown) jq -e '[.collection_errors[].kind]==["unexpected_result"]' "$result/bundle/report.json" >/dev/null ;;
        reorder) jq -e '(.collection_errors|length)==6 and all(.samples[]; .status=="FAIL")' "$result/bundle/report.json" >/dev/null ;;
        failed|interrupted|timeout)
            jq '.sample' "$bundle/results/0/result.json" > "$report/expected-sample.json"
            jq '.samples[0]' "$result/bundle/report.json" > "$report/actual-sample.json"
            cmp "$report/expected-sample.json" "$report/actual-sample.json" ;;
        *) jq -e '.samples[0].failure=="invalid_result" and [.collection_errors[].kind]==["invalid_result"]' "$result/bundle/report.json" >/dev/null ;;
    esac
    if [[ $mode == invalid-json || $mode == duplicate-key ]]; then cmp "$bundle/results/0/result.json" "$result/bundle/collection/0.raw"; fi
    if [[ $mode == changed-bytes ]]; then cmp "$bundle/results/0/evidence/checks.json" "$result/retained/0/evidence/checks.json"; fi
    rm -f "$bundle/results/0/result.json" "$bundle/results/0/evidence/checks.json" "$bundle/results/0/evidence/extra"
    cp "$report/original-result.json" "$bundle/results/0/result.json"
    cp "$report/content" "$bundle/results/0/evidence/checks.json"
done
for mode in identity batch escaping absolute excessive timestamp duplicate-index-key; do
    case $mode in
        identity) jq '.bindings_sha256=("0"*64)' "$report/original-index.json" > "$bundle/index.json" ;;
        batch) jq '.collection_id="not-an-id"' "$report/original-index.json" > "$bundle/index.json" ;;
        escaping) jq '.results[0].result="../secret"' "$report/original-index.json" > "$bundle/index.json" ;;
        absolute) jq '.results[0].evidence="/tmp"' "$report/original-index.json" > "$bundle/index.json" ;;
        excessive) jq '.results=[range(0;65) as $n|.results[0]]' "$report/original-index.json" > "$bundle/index.json" ;;
        timestamp) jq '.finished_at="2020-01-01T00:00:00Z"' "$report/original-index.json" > "$bundle/index.json" ;;
        duplicate-index-key) printf '{"schema":1,"schema":1}\n' > "$bundle/index.json" ;;
    esac
    if bash "$root/scripts/evaluation/aggregate.sh" "$bundle" index.json "$bundle/bindings" "$binding_sha" > "$report/index-$mode.out" 2> "$report/index-$mode.err"; then exit 1; fi
    result=$(sed -n 's/^Evaluation aggregation: //p' "$report/index-$mode.out")
    jq -e '.status=="FAIL" and .evaluation_status=="UNKNOWN" and .workers_started==0' "$result/summary.json" >/dev/null
    [[ ! -e $result/bundle/report.json && ! -e $result/retained/0 ]]
    passed=$((passed+1))
done
bundle="$report/full-input"
mkdir -p "$bundle/bindings/manifest" "$bundle/results"
cp "$root/scripts/evaluation/manifests/offline.json" "$bundle/bindings/manifest/input"
manifest_sha=$(sha256sum < "$bundle/bindings/manifest/input"); manifest_sha=${manifest_sha%% *}
jq --arg sha "$manifest_sha" '{schema:2,manifest_sha256:$sha,runner_sha256:("a"*64),
 artifacts:{baseline:("b"*64),candidate:("c"*64)},tasks:[.tasks[]|{id,fixture_sha256:("d"*64),
 config_sha256:{baseline:("e"*64),candidate:("f"*64)},models:(
 [{provider:"evaluation",id:"echo-1",api:"openai-completions"}]+
 if .id=="cache-accounting" or .id=="child-work" then
 [{provider:"evaluation",id:"echo-2",api:"anthropic-messages"}] else [] end)}]}' \
    "$bundle/bindings/manifest/input" > "$bundle/bindings/bindings.json"
binding_sha=$(sha256sum < "$bundle/bindings/bindings.json"); binding_sha=${binding_sha%% *}
jq -L "$root/scripts/evaluation" -f "$root/scripts/evaluation/schedule.jq" "$bundle/bindings/manifest/input" | jq '.samples' > "$report/full-schedule.json"
for ordinal in {0..59}; do
    mkdir -p "$bundle/results/$ordinal/evidence"
    for name in requests.jsonl events.jsonl checks.json cleanup.json; do cp "$report/content" "$bundle/results/$ordinal/evidence/$name"; done
    jq --argjson ordinal "$ordinal" --arg sha "$binding_sha" --slurpfile plan "$report/full-schedule.json" \
        --slurpfile bindings "$bundle/bindings/bindings.json" --slurpfile manifest "$bundle/bindings/manifest/input" '
        $plan[0][$ordinal] as $p | $bindings[0] as $b | ($b.tasks[]|select(.id==$p.task_id)) as $t |
        .bindings_sha256=$sha | .sample.id=$p.id | .sample.artifact_sha256=$b.artifacts[$p.variant] |
        .sample.fixture_sha256=$t.fixture_sha256 | .sample.config_sha256=$t.config_sha256[$p.variant] |
        .sample.models=$t.models | .sample.checks=[$manifest[0].tasks[]|select(.id==$p.task_id)|.checks[]|
          {id:.,status:"PASS",evidence_path:"checks.json"}]' "$report/original-result.json" > "$bundle/results/$ordinal/result.json"
done
jq --arg sha "$binding_sha" --slurpfile plan "$report/full-schedule.json" '.bindings_sha256=$sha |
    .results=[$plan[0]|to_entries[]|{id:.value.id,result:("results/"+(.key|tostring)+"/result.json"),
      evidence:("results/"+(.key|tostring)+"/evidence")}]' "$report/original-index.json" > "$bundle/index.json"
collect full-multi-model 0
jq -e --slurpfile plan "$report/full-schedule.json" '.status=="PASS" and [.samples[].id]==[$plan[0][].id] and
    ([.samples[]|select((.models|length)==2)]|length)==12 and .collection_errors==[]' "$result/bundle/report.json" >/dev/null
cp "$bundle/index.json" "$report/full-index.json"
jq '.results += [range(0;4) as $n|.results[0]+{id:("unknown:baseline:"+($n|tostring))}]' \
    "$report/full-index.json" > "$bundle/index.json"
collect maximum-index 1
jq -e '.status=="FAIL" and (.samples|length)==60 and all(.samples[];.status=="PASS") and
    (.collection_errors|length)==4 and all(.collection_errors[];.kind=="unexpected_result")' "$result/bundle/report.json" >/dev/null
[[ $(find "$result/retained" -mindepth 1 -maxdepth 1 -type d | wc -l) == 65 ]]
printf 'Evaluation aggregation checks passed: %s\n' "$passed"
