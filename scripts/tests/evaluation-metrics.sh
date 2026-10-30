#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# -le 1 ]]
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/metric-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" \
      '{schema:1,scope:"evaluation-metric-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,
        checks:$passed,mapping_approved:true,workers_started:0}' > "$report/summary.json"
    printf 'Evaluation metric test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
jq -n '
 def cost: {input_tokens:10,output_tokens:2,cache_read_tokens:1,cache_write_tokens:0,
   reported_micros:3,estimated_micros:2,charged_micros:5};
 {activity:{schema:1,scope:"evaluation-activity-observations",status:"ACTIVITY_OBSERVED",complete_run:false,
   observations:{accepted_user_entries:3,completed_tool_results:5,guard_suppressed_calls:2,
     executed_tool_results:3,failed_executed_tool_results:1,completed_layout_decisions:4,
     refused_layout_decisions:1,summary_model_calls:1,title_model_calls:1,tool_helper_model_calls:1,
     ipc_calls:5,retry_events:1,output_reductions:1,transport_retries:0},
   user_entries:[{transcript:"parent",cursor:1},{transcript:"parent",cursor:9},{transcript:"parent@child",cursor:1}],
   guarded_calls:[{transcript:"parent",cursor:7},{transcript:"parent",cursor:8}],
   executed_calls:[{transcript:"parent",cursor:3,is_error:false},{transcript:"parent",cursor:5,is_error:true},
     {transcript:"parent@child",cursor:3,is_error:false}],
   layouts:[{refused:false},{refused:false},{refused:false},{refused:false},{refused:true}]},
  attempts:{schema:1,scope:"evaluation-client-attempts",status:"ATTEMPTS_MEASURED",
    representation:"nonrefundable-pre-send-reservations",limit:64,provider_attempts:6},
  usage:{schema:1,scope:"evaluation-reconciled-synthetic-usage",status:"USAGE_RECONCILED",
    helper_attribution:true,real_billing_verified:false,totals:(cost|map_values(.*5)),
    calls:([{role:"primary",retries:1},{role:"primary",retries:0},{role:"summary",retries:0},
      {role:"title",retries:0},{role:"tool-helper",retries:0}]|map(.+{totals:cost}))},
  prefix:{schema:1,scope:"evaluation-normalized-prefix",status:"PREFIX_MEASURED",complete_run:false,
    provider_attempts:null,cached_tokens:null,representation:"sorted-compact-utf8-prompt-v1",
    order:"provider-body-capture",comparison:"adjacent-same-model-and-system-shape",
    request_bytes:9000,stable_prefix_bytes:4000,bodies:[{},{},{},{},{},{}]}}' > "$report/base.json"
check() {
    local name=$1 expected=$2 filter=$3 code=0
    jq "$filter" "$report/base.json" > "$report/$name.json"
    jq -e -L "$root/scripts/evaluation" -f "$root/scripts/evaluation/metrics.jq" \
      "$report/$name.json" > "$report/$name.result" 2> "$report/$name.err" || code=$?
    if [[ $expected == pass ]]; then
        [[ $code == 0 ]] || { cat "$report/$name.err" >&2; exit 1; }
        jq -e -L "$root/scripts/evaluation" 'include "sample"; metrics and all(.[];.!=null)' "$report/$name.result" >/dev/null
    else
        [[ $code != 0 && ! -s $report/$name.result ]] || { echo "unexpected metric acceptance: $name" >&2; exit 1; }
    fi
    passed=$((passed+1))
}
check normal pass '.'
jq -e '.=={logical_turns:3,provider_attempts:6,transport_retries:0,output_adjustments:1,
 tool_executions:3,guarded_calls:2,tool_failures:1,layout_jobs:4,summary_jobs:1,
 input_tokens:50,output_tokens:10,cache_read_tokens:5,cache_write_tokens:0,
 reported_micros:15,estimated_micros:10,charged_micros:25,request_bytes:9000,stable_prefix_bytes:4000}' "$report/normal.result" >/dev/null
check no-tools pass '.activity|=(.executed_calls=[]|.guarded_calls=[]|
 .observations|=(.completed_tool_results=0|.executed_tool_results=0|.guard_suppressed_calls=0|.failed_executed_tool_results=0))'
check maximum-token pass '.usage.calls|=map(.totals.input_tokens=0)|.usage.calls[0].totals.input_tokens=9007199254740991|
 .usage.totals.input_tokens=9007199254740991'
check estimated-only pass '.usage.calls|=map(.totals|=(.estimated_micros=.charged_micros|.reported_micros=0))|
 .usage.totals|=(.estimated_micros=.charged_micros|.reported_micros=0)'
for field in activity attempts usage prefix; do
    check "missing-$field" fail "del(.$field)"
    check "version-$field" fail ".$field.schema=2"
    check "status-$field" fail ".$field.status=\"FAIL\""
    check "scope-$field" fail ".$field.scope=\"unknown\""
done
for field in $(jq -r '.activity.observations|keys[]' "$report/base.json"); do
    for value in null -1 0.5 9007199254740992 true '"1"'; do
        check "observation-$field-$passed" fail ".activity.observations.$field=$value"
    done
    check "mismatch-$field" fail ".activity.observations.$field+=1"
done
for field in $(jq -r '.usage.totals|keys[]' "$report/base.json"); do
    check "missing-total-$field" fail "del(.usage.totals.$field)"
    check "null-total-$field" fail ".usage.totals.$field=null"
    check "mismatch-total-$field" fail ".usage.totals.$field+=1"
    check "missing-call-$field" fail "del(.usage.calls[0].totals.$field)"
    check "null-call-$field" fail ".usage.calls[0].totals.$field=null"
done
check duplicate-user fail '.activity.user_entries[1]=.activity.user_entries[0]'
check duplicate-tool fail '.activity.executed_calls[1]=.activity.executed_calls[0]'
check shared-position fail '.activity.guarded_calls[0]=.activity.user_entries[0]'
check missing-layout-state fail 'del(.activity.layouts[0].refused)'
check missing-error-state fail 'del(.activity.executed_calls[0].is_error)'
check unknown-observation fail '.activity.observations.unknown=0'
check missing-helper fail '.usage.helper_attribution=false'
check billing-claim fail '.usage.real_billing_verified=true'
check unknown-role fail '.usage.calls[0].role="unknown"'
check no-calls fail '.usage.calls=[]'
check unknown-total fail '.usage.totals.extra=0'
check sum-overflow fail '.usage.calls[0].totals.input_tokens=9007199254740991|.usage.totals.input_tokens=9007199254740991'
check charge-overflow fail '.usage.totals|=(.reported_micros=9007199254740991|.estimated_micros=1|.charged_micros=9007199254740991)'
check call-charge-overflow fail '.usage.calls[0].totals|=(.reported_micros=9007199254740991|.estimated_micros=1|.charged_micros=9007199254740991)'
check over-cap fail '.attempts.limit=5'
check attempt-mismatch fail '.attempts.provider_attempts=5'
check zero-attempts fail '.attempts.provider_attempts=0'
check wrong-attempt-basis fail '.attempts.representation="received-requests"'
check missing-body fail '.prefix.bodies|=.[1:]'
check too-long-prefix fail '.prefix.stable_prefix_bytes=9001'
check invented-cache fail '.prefix.cached_tokens=0'
check invented-attempts fail '.prefix.provider_attempts=6'
check wrong-normalization fail '.prefix.representation="raw-bytes"'
check wrong-order fail '.prefix.order="sorted"'
check wrong-comparison fail '.prefix.comparison="unrelated-bodies"'
check empty-request fail '.prefix.request_bytes=0'
check unknown-input fail '.extra={}'
if [[ $# == 1 ]]; then
    mkdir "$report/retained"
    for name in activity client-attempts reconciled-usage normalized-prefix; do
        "$root/target/evaluation/bin/eval-input" file "$1" "$name.json" "$report/retained/$name" 16777216 1 >/dev/null
        "$root/target/evaluation/bin/eval-input" json "$report/retained/$name" input 16777216 >/dev/null
    done
    jq -n --slurpfile activity "$report/retained/activity/input" --slurpfile attempts "$report/retained/client-attempts/input" \
      --slurpfile usage "$report/retained/reconciled-usage/input" --slurpfile prefix "$report/retained/normalized-prefix/input" \
      '{activity:$activity[0],attempts:$attempts[0],usage:$usage[0],prefix:$prefix[0]}' > "$report/retained.json"
    jq -e -L "$root/scripts/evaluation" -f "$root/scripts/evaluation/metrics.jq" "$report/retained.json" > "$report/retained.result"
    passed=$((passed+1))
fi
printf 'Evaluation proposed metric checks passed: %s\n' "$passed"
