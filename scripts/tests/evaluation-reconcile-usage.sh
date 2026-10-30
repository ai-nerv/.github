#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/reconcile-usage-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" \
      '{schema:1,scope:"evaluation-reconcile-usage-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$passed,workers_started:0}' > "$report/summary.json"
    printf 'Evaluation reconciliation test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
cat > "$report/fixture.jq" <<'JQ'
def usage: {input:7,output:2,cache_read:3,cache_write:4,cost_micros:5,estimated_micros:6};
def totals: {input_tokens:7,output_tokens:2,cache_read_tokens:3,cache_write_tokens:4,reported_micros:5,estimated_micros:6,charged_micros:11};
def row($cursor;$entry): {cursor:$cursor,revisions:0,raw:({record:"entry",cursor:$cursor,entry:$entry}|tojson)};
def history: [row(1;{type:"user",text:"fixture"}),row(2;{type:"assistant",text:"done",thinking:"thought",stop_reason:"end_turn",error:null,usage:usage})];
{calls:[{call:0,request:{model:"evaluation/echo-1",context:{system:"You are magi, a coding agent",tools:[{name:"read"}]}},
 events:[{event:"thinking",text:"thought"},{event:"text",text:"done"},{event:"spent",usage:usage},{event:"stop",reason:"end_turn"}]}],
 ipc:{status:"USAGE_EXTRACTED",capture_complete:true,coverage:"recorded-model-asks-only",calls:[{call:0,model:"evaluation/echo-1",transport_complete:true,exit_code:0,terminal:"stop",usage_frames:1,last_observed_usage:totals,totals:totals}]},
 transcripts:[{id:"fixture-1",snapshots:[{reply:{ok:true,family:1,n:2,result:history}}]}],
 durable_usage:{status:"USAGE_EXTRACTED",known_totals:totals},
 attempts:{status:"ATTEMPTS_MEASURED",provider_attempts:1},script:[{events:[{text:"done"}]}],meter:[{event:"response",attempt:1,turn:0}]}
JQ
jq -n -f "$report/fixture.jq" > "$report/base.json"
cat > "$report/mutate.jq" <<'JQ'
def raw(f): .transcripts[0].snapshots[-1].reply.result[1].raw |= (fromjson|f|tojson);
def duplicate:
 .calls += [(.calls[0]|.call=1)] | .ipc.calls += [(.ipc.calls[0]|.call=1)] |
 .transcripts[0].snapshots[-1].reply |= (.n=3 | .result += [(.result[1]|.cursor=3|.raw|=(fromjson|.cursor=3|tojson))]) |
 .durable_usage.known_totals |= with_entries(.value*=2) |
 .attempts.provider_attempts=2 | .meter += [(.meter[0]|.attempt=2)];
def helper($system): duplicate | .calls[1].request.context={system:$system,tools:[]} |
 .transcripts[0].snapshots[-1].reply |= (.n=2|.result=.result[0:2]) |
 .durable_usage.known_totals |= with_entries(.value/=2);
def refusal:
 .calls[0].events=[{event:"failed",message:"evaluation returned 400: fixture refusal",why:"overflow"}] |
 .ipc.calls[0] |= (.terminal="failed"|.usage_frames=0|.last_observed_usage=null|.totals|=with_entries(.value=null)) |
 raw(.entry|=(.text=""|.thinking=""|.usage=null|.stop_reason="error"|.error="evaluation returned 400: fixture refusal")) |
 .durable_usage.known_totals |= with_entries(.value=0) |
 .script=[{refuse:{status:400,message:"fixture refusal"}}];
if $mode=="normal" then .
elif $mode=="repeat" then duplicate
elif $mode=="resume" then .transcripts[0].snapshots += .transcripts[0].snapshots
elif $mode=="summary" then helper("You keep the running summary of a coding session")
elif $mode=="title" then helper("You are given the opening of a conversation")
elif $mode=="tool-helper" then helper("IPC_TOOL_HELPER_ONLY")
elif $mode=="refusal" then refusal
elif $mode=="retry" then .calls[0].events=([{event:"text",text:"discarded"},{event:"failed",message:"fixture refusal"},{event:"retrying"}]+.calls[0].events) |
 .attempts.provider_attempts=2 | .script += [{refuse:{status:503,message:"fixture refusal"}}] | .meter += [{event:"response",attempt:2,turn:1}]
elif $mode=="tools" then .calls[0].events=([{event:"tool_call_start",id:"r1",name:"read"},{event:"tool_call_args",args:"{\"path\":\"a\"}"}]+.calls[0].events) |
 .transcripts[0].snapshots[0].reply |= (.n=3|.result += [{cursor:3,revisions:0,raw:({record:"entry",cursor:3,entry:{type:"tool",id:"r1",name:"read",args:"{\"path\":\"a\"}"}}|tojson)}])
elif $mode=="missing-call" then .calls=[]
elif $mode=="duplicate-id" then duplicate | .calls[1].call=0
elif $mode=="duplicate-ipc-id" then duplicate | .ipc.calls[1].call=0
elif $mode=="partial" then .ipc.capture_complete=false
elif $mode=="transport" then .ipc.calls[0].transport_complete=false
elif $mode=="model" then .calls[0].request.model="other"
elif $mode=="duplicate-transcript" then .transcripts += .transcripts
elif $mode=="ambiguous" then .transcripts += [(.transcripts[0]|.id="fixture-2")]
elif $mode=="rewritten" then .transcripts[0].snapshots += .transcripts[0].snapshots | raw(.entry.text="changed")
elif $mode=="truncated" then .transcripts[0].snapshots[0].reply.more=true
elif $mode=="revised" then .transcripts[0].snapshots[0].reply.result[1].revisions=1
elif $mode=="missing-row" then .transcripts[0].snapshots[0].reply |= (.n=1|.result=.result[0:1])
elif $mode=="extra-row" then duplicate | .calls=.calls[0:1] | .ipc.calls=.ipc.calls[0:1]
elif $mode=="text" then .calls[0].events[1].text="other"
elif $mode=="thinking" then .calls[0].events[0].text="other"
elif $mode=="unknown-helper" then helper("Unknown helper")
elif $mode=="ambiguous-helper" then helper("IPC_TOOL_HELPER_ONLY") | .transcripts += [(.transcripts[0]|.id="other"|.snapshots[0].reply|=(.n=1|.result=.result[0:1]))]
elif $mode=="unknown-usage" then refusal | .script=[{events:[]}]
elif $mode=="wrong-refusal" then refusal | .script[0].refuse.message="different refusal"
elif $mode=="streaming-refusal" then refusal | .script[0].events=[{text:"partial"}]
elif $mode=="refusal-status" then refusal | .script[0].refuse.status=200
elif $mode=="unknown-turn" then .meter[0].turn=1
elif $mode=="missing-attempt" then .attempts.provider_attempts=0
elif $mode=="fractional" then .ipc.calls[0].totals.input_tokens=0.5
elif $mode=="overflow" then .ipc.calls[0].totals.charged_micros=9007199254740992
elif $mode=="charge" then .durable_usage.known_totals.charged_micros=12
elif $mode=="child-owner" then .calls[0].request.context.system+=" # Working as a subagent"
elif $mode=="unsupported-event" then .calls[0].events += [{event:"unknown"}]
elif $mode=="orphan-args" then .calls[0].events=[{event:"tool_call_args",args:"{}"}]+.calls[0].events
else error("unknown test mode") end
JQ
for mode in normal repeat resume summary title tool-helper refusal retry tools \
    missing-call duplicate-id duplicate-ipc-id partial transport model duplicate-transcript ambiguous rewritten \
    truncated revised missing-row extra-row text thinking unknown-helper ambiguous-helper unknown-usage \
    wrong-refusal streaming-refusal refusal-status unknown-turn missing-attempt fractional overflow charge \
    child-owner unsupported-event orphan-args; do
    jq --arg mode "$mode" -f "$report/mutate.jq" "$report/base.json" > "$report/$mode.json"
    task=small-bug-fix
    [[ $mode != child-owner ]] || task=child-work
    code=0
    jq -L "$root/scripts/evaluation" --arg task "$task" -f "$root/scripts/evaluation/reconcile-usage.jq" \
      "$report/$mode.json" > "$report/$mode.result" 2> "$report/$mode.err" || code=$?
    case $mode in
        normal|resume|tools) expected=7 ;;
        repeat|summary|title|tool-helper|retry) expected=14; [[ $mode != retry ]] || expected=7 ;;
        refusal) expected=0 ;;
        *) expected=fail ;;
    esac
    if [[ $expected == fail ]]; then
        [[ $code != 0 && ! -s $report/$mode.result ]] || { echo "unexpected acceptance: $mode" >&2; exit 1; }
    else
        [[ $code == 0 ]] || { echo "unexpected refusal: $mode" >&2; cat "$report/$mode.err" >&2; exit 1; }
        jq -e --argjson expected "$expected" '.status=="USAGE_RECONCILED" and .totals.input_tokens==$expected and .real_billing_verified==false' "$report/$mode.result" >/dev/null
    fi
    passed=$((passed+1))
done
printf 'Evaluation reconciliation checks passed: %s\n' "$passed"
