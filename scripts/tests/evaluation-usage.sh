#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# -le 1 ]]
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/usage-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson checks "$passed" \
        '{schema:1,scope:"evaluation-transcript-usage-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$checks}' > "$report/summary.json"
    printf 'Evaluation transcript usage test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
jq -n '
 def row($n;$entry): {cursor:$n,role:$entry.type,text:($entry.text//""),revisions:0,raw:({record:"entry",cursor:$n,entry:$entry}|tojson)};
 [{id:"alpha",snapshots:[{source:"replay.json",reply:{family:1,ok:true,n:2,result:[
 row(1;{type:"user",text:"fixture"}),row(2;{type:"assistant",id:"a2",text:"done",error:null,
 usage:{input:10,output:2,cache_read:3,cache_write:4,cost_micros:7,estimated_micros:3}})]}}]}]' > "$report/base.json"
run() {
    local name=$1 expected=$2 code=0
    jq -L "$root/scripts/evaluation" -f "$root/scripts/evaluation/usage.jq" "$report/case.json" > "$report/$name.json" 2> "$report/$name.err" || code=$?
    if [[ $expected == pass ]]; then [[ $code == 0 ]]; else [[ $code != 0 ]]; fi
    passed=$((passed+1))
}
for mode in normal independent resumed from-user from-other missing null failed duplicate-id duplicate-source bad-counter partial extra fractional overflow summed-overflow cursor revision role truncated shortened changed; do
    cp "$report/base.json" "$report/case.json"
    expected=fail
    case $mode in
        normal) expected=pass ;;
        from-user|from-other)
            role=${mode#from-}
            jq --arg role "$role" '.[0].snapshots[0].reply.result[0]|=(.role=$role|.raw|=(fromjson|.entry.type="from"|tojson))' "$report/base.json" > "$report/case.json"; expected=pass ;;
        independent) jq '.+[.[0]|.id="beta"|.snapshots[0].source="child.json"]' "$report/base.json" > "$report/case.json"; expected=pass ;;
        resumed)
            jq '.[0].snapshots += [.[0].snapshots[0]|.source="resumed.json"|.reply.n=3|
              .reply.result += [.reply.result[1]|.cursor=3|.raw|=(fromjson|.cursor=3|.entry.id="a3"|tojson)]]' "$report/base.json" > "$report/case.json"; expected=pass ;;
        missing|null|failed|bad-counter|partial|extra|fractional|overflow)
            case $mode in
                missing) filter='del(.entry.usage)'; expected=pass ;;
                null) filter='.entry.usage=null'; expected=pass ;;
                failed) filter='.entry.error="failed after usage"'; expected=pass ;;
                bad-counter) filter='.entry.usage.input=-1' ;;
                partial) filter='del(.entry.usage.input)' ;;
                extra) filter='.entry.usage.extra=1' ;;
                fractional) filter='.entry.usage.input=1.5' ;;
                overflow) filter='.entry.usage.cost_micros=9007199254740991' ;;
            esac
            jq ".[0].snapshots[0].reply.result[1].raw|=(fromjson|$filter|tojson)" "$report/base.json" > "$report/case.json" ;;
        duplicate-id) jq '.+.' "$report/base.json" > "$report/case.json" ;;
        duplicate-source) jq '.+[.[0]|.id="beta"]' "$report/base.json" > "$report/case.json" ;;
        summed-overflow) jq '.[0].snapshots[0].reply.result[1].raw|=(fromjson|.entry.usage.input=9007199254740991|tojson)|.+[.[0]|.id="beta"|.snapshots[0].source="beta.json"]' "$report/base.json" > "$report/case.json" ;;
        cursor) jq '.[0].snapshots[0].reply.result[1].cursor=3' "$report/base.json" > "$report/case.json" ;;
        revision) jq '.[0].snapshots[0].reply.result[1].revisions=1' "$report/base.json" > "$report/case.json" ;;
        truncated) jq '.[0].snapshots[0].reply.result[1].truncated=true' "$report/base.json" > "$report/case.json" ;;
        role) jq '.[0].snapshots[0].reply.result[1].role="tool"' "$report/base.json" > "$report/case.json" ;;
        shortened) jq '.[0].snapshots += [.[0].snapshots[0]|.source="short.json"|.reply.n=1|.reply.result|=.[0:1]]' "$report/base.json" > "$report/case.json" ;;
        changed) jq '.[0].snapshots += [.[0].snapshots[0]|.source="changed.json"|.reply.result[1].raw|=(fromjson|.entry.usage.input=20|tojson)]' "$report/base.json" > "$report/case.json" ;;
    esac
    run "$mode" "$expected"
    case $mode in
        normal|failed) jq -e --arg ledger $'10\n' '.totals.charged_micros==($ledger|rtrimstr("\n")|tonumber) and .totals.input_tokens==10 and .complete_run==false' "$report/$mode.json" >/dev/null ;;
        independent|resumed) jq -e '.totals.charged_micros==20 and .totals.input_tokens==20' "$report/$mode.json" >/dev/null ;;
        missing|null) jq -e '.unknown_usage_records==1 and all(.totals[];.==null) and .known_totals.charged_micros==0' "$report/$mode.json" >/dev/null ;;
    esac
done
mkdir "$report/evidence"
jq '.[0].snapshots[0].reply' "$report/base.json" > "$report/original-replay.json"
printf '{"family":1,"ok":true,"n":1,"result":[{"id":"alpha"}]}\n' > "$report/evidence/sessions.json"
for mode in captured retained-large duplicate-inner duplicate-outer unsafe wrong-sessions missing-file; do
    cp "$report/original-replay.json" "$report/evidence/replay.json"
    case $mode in
        retained-large) jq '.result[0]|=(.text=("x"*600000)|.raw|=(fromjson|.entry.text=("x"*600000)|tojson))' "$report/original-replay.json" > "$report/evidence/replay.json" ;;
        duplicate-inner) jq '.result[1].raw|=sub("\\\"input\\\":10";"\"input\":10,\"input\":20")' "$report/original-replay.json" > "$report/evidence/replay.json" ;;
        duplicate-outer) printf '{"family":1,"family":1}\n' > "$report/evidence/replay.json" ;;
        unsafe) rm "$report/evidence/replay.json"; ln -s "$report/original-replay.json" "$report/evidence/replay.json" ;;
        wrong-sessions) printf '{"family":1,"ok":true,"n":2,"result":[{"id":"alpha"}]}\n' > "$report/evidence/sessions.json" ;;
        missing-file) rm "$report/evidence/replay.json" ;;
    esac
    code=0
    bash "$root/scripts/evaluation/transcript-usage.sh" small-bug-fix "$report/evidence" "$report/$mode" > "$report/$mode.out" 2> "$report/$mode.err" || code=$?
    if [[ $mode == captured || $mode == retained-large ]]; then
        [[ $code == 0 ]]; jq -e '.totals.charged_micros==10 and .complete_run==false' "$report/$mode/result.json" >/dev/null
        cmp "$report/evidence/replay.json" "$report/$mode/inputs/replay.json/input"
    else [[ $code != 0 ]]; fi
    rm -f "$report/evidence/replay.json"
    printf '{"family":1,"ok":true,"n":1,"result":[{"id":"alpha"}]}\n' > "$report/evidence/sessions.json"
    passed=$((passed+1))
done
if [[ $# == 1 ]]; then
    mkdir "$report/retained-evidence"
    for file in sessions replay; do
        "$root/target/evaluation/bin/eval-input" file "$1" "inputs/$file.json/input" "$report/retained-$file" 16777216 1 >/dev/null
        cp "$report/retained-$file/input" "$report/retained-evidence/$file.json"
    done
    began=$(date +%s%3N)
    timeout --signal=TERM --kill-after=2 60 bash "$root/scripts/evaluation/transcript-usage.sh" large-file-edit \
        "$report/retained-evidence" "$report/retained-escaped" > "$report/retained-escaped.out" 2> "$report/retained-escaped.err"
    elapsed=$(($(date +%s%3N)-began))
    jq -e '.unknown_usage_records==0 and .totals.input_tokens==60 and .totals.output_tokens==15 and .complete_run==false' \
        "$report/retained-escaped/result.json" >/dev/null
    jq -n --argjson elapsed "$elapsed" '{scope:"retained-escaped-transcript-extraction",elapsed_ms:$elapsed,limit_ms:60000,complete_run:false}' \
        > "$report/retained-escaped-timing.json"
    passed=$((passed+1))
fi
printf 'Evaluation transcript usage checks passed: %s\n' "$passed"
