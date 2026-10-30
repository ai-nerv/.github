#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/activity-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" '{schema:1,scope:"evaluation-activity-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$passed,workers_started:0}' > "$report/summary.json"
    printf 'Evaluation activity test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
jq -n '
 def row($cursor;$entry): {raw:({cursor:$cursor,entry:$entry}|tojson)};
 {raw:{calls:[{request:{wants:{max_tokens_automatic:true}}}],transcripts:[{id:"fixture",snapshots:[{reply:{result:[
   row(1;{type:"user",text:"fixture"}),row(2;{type:"tool",id:"read-1",result:{output:"missing",is_error:true}})]}}]}]},
 reconciled:{status:"USAGE_RECONCILED",helper_attribution:true,calls:[{role:"primary",retries:0}]},
 prefix:{status:"PREFIX_MEASURED",bodies:[{}]},requests:[{model:"fixture",max_tokens:4096,messages:[]}],
 logs:[{file:"family.log",text:"2026-10-23T12:34:56.789Z balthasar[82] verb: layout fixture \"L-1\" with 1 slots, 0 jobs — all retained in 0ms\n"}]}' > "$report/base.json"
cat > "$report/mutate.jq" <<'JQ'
def tool(f): .raw.transcripts[0].snapshots[-1].reply.result[1].raw|=(fromjson|.entry|=f|tojson);
def retry: .reconciled.calls[0].retries=1|.requests += [(.requests[0]|.max_tokens=512)]|.prefix.bodies += [{}];
if $mode=="normal" then .
elif $mode=="resume" then .raw.transcripts[0].snapshots += .raw.transcripts[0].snapshots
elif $mode=="child" then .raw.transcripts += [(.raw.transcripts[0]|.id="fixture@child")]
elif $mode=="summary" then .reconciled.calls[0].role="summary"
elif $mode=="title" then .reconciled.calls[0].role="title"
elif $mode=="tool-helper" then .reconciled.calls[0].role="tool-helper"
elif $mode=="success" then tool(.result.is_error=false)
elif $mode=="guard" or $mode=="unexpected-guard" then tool(.result.output="Repeated-call guard: not executed. This identical call failed twice without changed evidence. Change the approach or arguments; repeating it again will end this turn.")
elif $mode=="unknown-guard" then tool(.result.output="Repeated-call guard: unknown")
elif $mode=="overflow-layout" then .logs[0].text|=sub("verb: layout";"verb: overflowed")
elif $mode=="refused-layout" then .logs[0].text += "2026-10-23T12:34:56.790Z balthasar[82] verb: layout fixture refused: missing in 0ms\n"
elif $mode=="retry" then retry
elif $mode=="transport-unknown" then retry|.requests[1].max_tokens=4096
elif $mode=="changed-input" then retry|.requests[1].messages=[{role:"user",content:"changed"}]
elif $mode=="explicit-limit" then retry|.raw.calls[0].request.wants.max_tokens_automatic=false
elif $mode=="missing-prefix" then .prefix.status="FAIL"
elif $mode=="missing-usage" then .reconciled.status="FAIL"
elif $mode=="missing-log" then .logs=[]
elif $mode=="empty-log" then .logs[0].text=""
elif $mode=="unterminated" then .logs[0].text|=rtrimstr("\n")
elif $mode=="nul" then .logs[0].text+="\u0000\n"
elif $mode=="duplicate-log" then .logs+=.logs
elif $mode=="duplicate-layout" then .logs[0].text+=.logs[0].text
elif $mode=="malformed-layout" then .logs[0].text|=sub("1 slots";"unknown slots")
elif $mode=="oversized-layout" then .logs[0].text|=sub("1 slots";"9007199254740993 slots")
elif $mode=="missing-user" then .raw.transcripts[0].snapshots[0].reply.result|=.[1:]
elif $mode=="missing-tool-result" then tool(del(.result))
elif $mode=="missing-provider" then .requests=[]
else error("unknown test") end
JQ
for mode in normal resume child summary title tool-helper success guard unexpected-guard unknown-guard \
    overflow-layout refused-layout retry transport-unknown changed-input explicit-limit missing-prefix \
    missing-usage missing-log empty-log unterminated nul duplicate-log duplicate-layout malformed-layout \
    oversized-layout missing-user missing-tool-result missing-provider; do
    jq --arg mode "$mode" -f "$report/mutate.jq" "$report/base.json" > "$report/$mode.json"
    task=small-bug-fix expected=fail
    case $mode in
        normal|resume|child|summary|title|tool-helper|success|overflow-layout|refused-layout) expected=pass ;;
        guard) task=repetitive-failure; expected=pass ;;
        retry) task=output-only-overflow; expected=pass ;;
        transport-unknown|changed-input|explicit-limit) task=output-only-overflow ;;
    esac
    code=0
    jq -e -L "$root/scripts/evaluation" --arg task "$task" -f "$root/scripts/evaluation/activity.jq" \
      "$report/$mode.json" > "$report/$mode.result" 2> "$report/$mode.err" || code=$?
    if [[ $expected == pass ]]; then
        [[ $code == 0 ]] || { echo "unexpected refusal: $mode" >&2; cat "$report/$mode.err" >&2; exit 1; }
        jq -e '.status=="ACTIVITY_OBSERVED" and .complete_run==false and .report_metric_mapping=="separate-v1" and
          .observations.completed_layout_decisions==1 and .observations.transport_retries==0' "$report/$mode.result" >/dev/null
        case $mode in
            child) jq -e '.observations.accepted_user_entries==2 and .observations.executed_tool_results==2' "$report/$mode.result" >/dev/null ;;
            guard) jq -e '.observations.guard_suppressed_calls==1 and .observations.executed_tool_results==0 and .observations.failed_executed_tool_results==0' "$report/$mode.result" >/dev/null ;;
            retry) jq -e '.observations.retry_events==1 and .observations.output_reductions==1' "$report/$mode.result" >/dev/null ;;
            summary) jq -e '.observations.summary_model_calls==1 and .observations.title_model_calls==0' "$report/$mode.result" >/dev/null ;;
            title) jq -e '.observations.summary_model_calls==0 and .observations.title_model_calls==1' "$report/$mode.result" >/dev/null ;;
            *) jq -e '.observations.accepted_user_entries==1 and .observations.retry_events==0' "$report/$mode.result" >/dev/null ;;
        esac
    else
        [[ $code != 0 && ! -s $report/$mode.result ]] || { echo "unexpected acceptance: $mode" >&2; exit 1; }
    fi
    passed=$((passed+1))
done
printf 'Evaluation activity checks passed: %s\n' "$passed"
