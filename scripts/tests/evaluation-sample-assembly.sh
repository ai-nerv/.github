#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/sample-assembly-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" '{schema:1,scope:"evaluation-sample-assembly-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$passed,workers_started:0}' > "$report/summary.json"
    printf 'Evaluation sample assembly evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
manifest="$root/scripts/evaluation/manifests/offline.json"
manifest_sha=$(sha256sum < "$manifest"); manifest_sha=${manifest_sha%% *}
jq -n -L "$root/scripts/evaluation" --arg sha "$manifest_sha" --slurpfile manifest "$manifest" '
 include "workloads";
 {schema:2,manifest_sha256:$sha,runner_sha256:("a"*64),artifacts:{baseline:("b"*64),candidate:("c"*64)},
 tasks:[$manifest[0].tasks[]|{id,fixture_sha256:("d"*64),config_sha256:{baseline:("e"*64),candidate:("f"*64)},models:(workload(.id).models)}]}' > "$report/bindings.json"
binding_sha=$(sha256sum < "$report/bindings.json"); binding_sha=${binding_sha%% *}
jq -n -L "$root/scripts/evaluation" --arg binding "$binding_sha" --slurpfile manifest "$manifest" '
 include "sample";
 {summary:{schema:1,scope:"evaluation-bound-workload",status:"WORKLOAD_CHECKED",failure:null,task_id:"small-bug-fix",variant:"baseline",
 bindings_sha256:$binding,artifact_sha256:("b"*64),fixture_sha256:("d"*64),config_sha256:("e"*64),runner_sha256:("a"*64),elapsed_ms:100,exit_code:0,metrics_status:"MEASURED"},
 control:{schema:1,scope:"evaluation-controller",elapsed_ms:100,limit_ms:60000,exit_code:0,timed_out:false,interrupted:0,invalid_limit:false,
 leaked_processes:0,cleanup_confirmed:true,output_limit_exceeded:false},
 checks:{task_id:"small-bug-fix",status:"PASS",checks:[$manifest[0].tasks[0].checks[]|{id:.,status:"PASS"}]},
 metrics:((metric_names|map({key:.,value:0})|from_entries)+{logical_turns:1,provider_attempts:1,request_bytes:19}),
 evidence:["requests.jsonl","events.jsonl","checks.json","cleanup.json"]|map({path:.,sha256:("1"*64)})}' > "$report/base.json"
for mode in normal missing-metrics partial-metrics partial-status unsafe-counter negative-counter extra-metric wrong-charge \
    missing-summary missing-control cap timeout tool-timeout interrupt cleanup-failure leak precedence \
    failed-check missing-check wrong-check-order wrong-task wrong-variant wrong-binding wrong-artifact \
    wrong-fixture wrong-config wrong-runner wrong-elapsed controller-exit invalid-limit output-limit \
    unsupported unsupported-evidence missing-canonical bad-evidence duplicate-evidence bad-controller unknown-id; do
    expected=FAIL failure=invalid_result filter= id=small-bug-fix:baseline:1
    case $mode in
        normal) expected=PASS; failure=null ;;
        missing-metrics) filter='del(.metrics)' ;;
        partial-metrics) filter='.metrics.logical_turns=null' ;;
        partial-status) filter='.summary.metrics_status="PARTIAL"' ;;
        unsafe-counter) filter='.metrics.input_tokens=9007199254740992' ;;
        negative-counter) filter='.metrics.input_tokens=-1' ;;
        extra-metric) filter='.metrics.extra=0' ;;
        wrong-charge) filter='.metrics.charged_micros=1' ;;
        missing-summary) filter='.summary=null' ;;
        missing-control) filter='.control=null' ;;
        cap) filter='.summary.status="FAIL"|.summary.failure="attempt_limit"|.summary.exit_code=1|.control.exit_code=1'; failure=attempt_limit ;;
        timeout) filter='.control.timed_out=true'; expected=TIMEOUT; failure=prompt_timeout ;;
        tool-timeout) filter='.summary.status="FAIL"|.summary.failure="tool_timeout"'; expected=TIMEOUT; failure=tool_timeout ;;
        interrupt) filter='.control.interrupted=15'; expected=INTERRUPTED; failure=interrupted ;;
        cleanup-failure) filter='.control.cleanup_confirmed=false'; failure=cleanup_failure ;;
        leak) filter='.control.leaked_processes=1'; failure=cleanup_failure ;;
        precedence) filter='.summary.status="FAIL"|.summary.failure="attempt_limit"|.control.interrupted=2|.control.timed_out=true'; expected=INTERRUPTED; failure=interrupted ;;
        failed-check) filter='.summary.status="FAIL"|.summary.failure="check_failed"|.checks.status="FAIL"|.checks.checks[0].status="FAIL"'; failure=check_failed ;;
        missing-check) filter='.checks=null' ;;
        wrong-check-order) filter='.checks.checks|=reverse' ;;
        wrong-task) filter='.summary.task_id="other"' ;;
        wrong-variant) filter='.summary.variant="candidate"' ;;
        wrong-binding) filter='.summary.bindings_sha256=("0"*64)' ;;
        wrong-artifact) filter='.summary.artifact_sha256=("0"*64)' ;;
        wrong-fixture) filter='.summary.fixture_sha256=("0"*64)' ;;
        wrong-config) filter='.summary.config_sha256=("0"*64)' ;;
        wrong-runner) filter='.summary.runner_sha256=("0"*64)' ;;
        wrong-elapsed) filter='.summary.elapsed_ms=99' ;;
        controller-exit) filter='.control.exit_code=1' ;;
        invalid-limit) filter='.control.invalid_limit=true' ;;
        output-limit) filter='.control.output_limit_exceeded=true' ;;
        unsupported) filter='.summary.status="NOT_RUN"|.summary.failure="unsupported_features"|.evidence=[]'; expected=NOT_RUN; failure=unsupported_features ;;
        unsupported-evidence) filter='.summary.status="NOT_RUN"|.summary.failure="unsupported_features"'; expected=reject ;;
        missing-canonical) filter='.evidence|=map(select(.path!="requests.jsonl"))' ;;
        bad-evidence) filter='.evidence[0].path="../escape"'; expected=reject ;;
        duplicate-evidence) filter='.evidence+=[.evidence[0]]'; expected=reject ;;
        bad-controller) filter='.control.interrupted="15"'; expected=reject ;;
        unknown-id) id=unknown:baseline:1; expected=reject ;;
    esac
    jq "${filter:-.}" "$report/base.json" > "$report/$mode.json"
    code=0
    jq -e -L "$root/scripts/evaluation" --slurpfile manifest "$manifest" --slurpfile bindings "$report/bindings.json" \
      --arg manifest_sha "$manifest_sha" --arg binding_sha "$binding_sha" --arg collection 11111111111111111111111111111111 \
      --arg id "$id" -f "$root/scripts/evaluation/assemble-sample.jq" "$report/$mode.json" > "$report/$mode.result" 2> "$report/$mode.err" || code=$?
    if [[ $expected == reject ]]; then
        [[ $code != 0 && ! -s $report/$mode.result ]] || { echo "unexpected acceptance: $mode" >&2; exit 1; }
    else
        [[ $code == 0 ]] || { echo "unexpected refusal: $mode" >&2; cat "$report/$mode.err" >&2; exit 1; }
        jq -e --arg status "$expected" --arg failure "$failure" '.scope=="evaluation-sample-result" and
          .sample.status==$status and .sample.failure==(if $failure=="null" then null else $failure end)' "$report/$mode.result" >/dev/null
        case $mode in
            missing-metrics|unsafe-counter|negative-counter|extra-metric|unsupported) jq -e 'all(.sample.metrics[];.==null)' "$report/$mode.result" >/dev/null ;;
            missing-control) jq -e '.sample.elapsed_ms==null and .sample.cleanup=={leaked_processes:null,remaining_processes:null}' "$report/$mode.result" >/dev/null ;;
            partial-metrics) jq -e '.sample.metrics.logical_turns==null' "$report/$mode.result" >/dev/null ;;
        esac
    fi
    passed=$((passed+1))
done
printf 'Evaluation sample assembly checks passed: %s\n' "$passed"
