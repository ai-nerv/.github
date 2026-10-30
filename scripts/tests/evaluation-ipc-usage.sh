#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# -le 1 ]] || exit 2
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/ipc-usage-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" '{schema:1,scope:"evaluation-ipc-usage-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$passed,workers_started:0}' > "$report/summary.json"
    printf 'Evaluation IPC usage test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
mkdir "$report/base"
printf 'sealed\n' > "$report/base/gate"
printf '%s\n' '{"model":"evaluation/fixture","context":{},"wants":{"temperature":0.125}}' > "$report/base/000-request.json"
cat > "$report/base/000-response.jsonl" <<'JSON'
{"event":"spent","usage":{"input":7,"output":2,"cache_read":3,"cache_write":4,"cost_micros":5,"estimated_micros":6}}
{"event":"failed","why":"throttle","message":"fixture"}
{"event":"retrying","attempt":1,"of":2,"seconds":0.125,"why":"fixture"}
{"event":"spent","usage":{"input":14,"output":4,"cache_read":6,"cache_write":8,"cost_micros":10,"estimated_micros":12}}
{"event":"stop","reason":"end_turn"}
JSON
sync_capture() {
    local path=$1 count=$2 total=0 prefix request response
    for ((i=0;i<count;i++)); do
        printf -v prefix '%03d' "$i"
        request=$(wc -c < "$path/$prefix-request.json")
        response=$(wc -c < "$path/$prefix-response.jsonl")
        total=$((total+request+response))
        jq -n --argjson id "$i" --argjson request "$request" --argjson response "$response" \
          '{schema:1,call:$id,request_bytes:$request,response_bytes:$response,exit_code:0,transport_complete:true,complete_run:false}' > "$path/$prefix-receipt.json"
    done
    printf '%s %s 0\n' "$count" "$total" > "$path/budget"
    jq -nc --argjson calls "$count" --argjson bytes "$total" \
      '{schema:1,scope:"evaluation-model-ipc",sealed:true,calls:$calls,bytes:$bytes,limit_exhausted:false,capture_complete:true,complete_run:false,helper_attribution:null}' > "$path/summary.json"
}
measure() {
    local mode=$1
    bash "$root/scripts/evaluation/ipc-usage.sh" "$report" "$mode" > "$report/$mode.out" 2> "$report/$mode.err"
    result="$(sed -n 's/^Evaluation IPC usage: //p' "$report/$mode.out")/result.json"
}
sync_capture "$report/base" 1
measure base
jq -e '.complete_run==false and .helper_attribution==null and .provider_attempts==null and
    .totals=={input_tokens:14,output_tokens:4,cache_read_tokens:6,cache_write_tokens:8,reported_micros:10,estimated_micros:12,charged_micros:22} and .calls[0].usage_frames==2' "$result" >/dev/null
passed=$((passed+1))
for mode in legacy missing-usage no-terminal interrupted failed-terminal missing-receipt two-calls retry-unmeasured repeated-spent; do
    cp -R "$report/base" "$report/$mode"
    case $mode in
        legacy) jq -c 'if .event=="spent" then del(.usage.estimated_micros) else . end' "$report/base/000-response.jsonl" > "$report/$mode/000-response.jsonl" ;;
        missing-usage) printf '%s\n' '{"event":"stop","reason":"end_turn"}' > "$report/$mode/000-response.jsonl" ;;
        no-terminal) head -n 4 "$report/base/000-response.jsonl" > "$report/$mode/000-response.jsonl" ;;
        failed-terminal) head -n 2 "$report/base/000-response.jsonl" > "$report/$mode/000-response.jsonl" ;;
        retry-unmeasured) head -n 3 "$report/base/000-response.jsonl" > "$report/$mode/000-response.jsonl"; printf '%s\n' '{"event":"failed","why":"transport","message":"fixture"}' >> "$report/$mode/000-response.jsonl" ;;
        repeated-spent) head -n 4 "$report/base/000-response.jsonl" > "$report/$mode/000-response.jsonl"; tail -n 2 "$report/base/000-response.jsonl" >> "$report/$mode/000-response.jsonl" ;;
        two-calls) cp "$report/base/000-request.json" "$report/$mode/001-request.json"; cp "$report/base/000-response.jsonl" "$report/$mode/001-response.jsonl" ;;
    esac
    count=1; [[ $mode != two-calls ]] || count=2
    sync_capture "$report/$mode" "$count"
    if [[ $mode == missing-receipt ]]; then
        rm "$report/$mode/000-receipt.json"
        jq '.capture_complete=false' "$report/$mode/summary.json" > "$report/tmp"; mv "$report/tmp" "$report/$mode/summary.json"
    elif [[ $mode == interrupted ]]; then
        jq '.exit_code=137' "$report/$mode/000-receipt.json" > "$report/tmp"; mv "$report/tmp" "$report/$mode/000-receipt.json"
    fi
    measure "$mode"
    case $mode in
        legacy) jq -e '.totals.input_tokens==14 and .totals.estimated_micros==null and .totals.charged_micros==null and .totals.reported_micros==10' "$result" >/dev/null ;;
        failed-terminal) jq -e '.totals.input_tokens==7 and .calls[0].terminal=="failed"' "$result" >/dev/null ;;
        two-calls) jq -e '.totals.input_tokens==28 and .totals.charged_micros==44 and (.calls|length)==2' "$result" >/dev/null ;;
        repeated-spent) jq -e '.totals.input_tokens==14 and .totals.charged_micros==22 and .calls[0].usage_frames==3' "$result" >/dev/null ;;
        *) jq -e 'all(.totals[];.==null)' "$result" >/dev/null ;;
    esac
    passed=$((passed+1))
done
for mode in fractional exponent negative unsafe duplicate escaped-duplicate invalid-utf8 nul no-newline multi-json decreasing charge-overflow aggregate-overflow event-after-stop unknown-event wrong-identity wrong-size unsealed missing-receipt-complete symlink hardlink fifo extra-file; do
    cp -R "$report/base" "$report/$mode"
    case $mode in
        fractional) sed 's/"input":14/"input":14.5/' "$report/base/000-response.jsonl" > "$report/$mode/000-response.jsonl" ;;
        exponent) sed 's/"input":14/"input":14e0/' "$report/base/000-response.jsonl" > "$report/$mode/000-response.jsonl" ;;
        negative) sed 's/"input":14/"input":-1/' "$report/base/000-response.jsonl" > "$report/$mode/000-response.jsonl" ;;
        unsafe) sed 's/"input":14/"input":9007199254740992/' "$report/base/000-response.jsonl" > "$report/$mode/000-response.jsonl" ;;
        duplicate) printf '%s\n' '{"event":"stop","event":"stop","reason":"end_turn"}' >> "$report/$mode/000-response.jsonl" ;;
        escaped-duplicate) printf '%s\n' '{"event":"stop","\u0065vent":"stop","reason":"end_turn"}' >> "$report/$mode/000-response.jsonl" ;;
        invalid-utf8) printf '{"event":"text","text":"\377"}\n' >> "$report/$mode/000-response.jsonl" ;;
        nul) printf '\000\n' >> "$report/$mode/000-response.jsonl" ;;
        no-newline) printf '{}' >> "$report/$mode/000-response.jsonl" ;;
        multi-json) printf '{}{}\n' >> "$report/$mode/000-response.jsonl" ;;
        decreasing) sed 's/"input":14/"input":1/' "$report/base/000-response.jsonl" > "$report/$mode/000-response.jsonl" ;;
        charge-overflow) sed 's/"cost_micros":10/"cost_micros":9007199254740991/' "$report/base/000-response.jsonl" > "$report/$mode/000-response.jsonl" ;;
        aggregate-overflow) sed 's/"input":14/"input":9007199254740991/' "$report/base/000-response.jsonl" > "$report/$mode/000-response.jsonl"; cp "$report/base/000-request.json" "$report/$mode/001-request.json"; cp "$report/base/000-response.jsonl" "$report/$mode/001-response.jsonl" ;;
        event-after-stop) printf '%s\n' '{"event":"text","text":"late"}' >> "$report/$mode/000-response.jsonl" ;;
        unknown-event) printf '%s\n' '{"event":"future_counter","usage":{}}' > "$report/$mode/000-response.jsonl" ;;
    esac
    count=1; [[ $mode != aggregate-overflow ]] || count=2
    sync_capture "$report/$mode" "$count"
    case $mode in
        wrong-identity) jq '.call=1' "$report/$mode/000-receipt.json" > "$report/tmp"; mv "$report/tmp" "$report/$mode/000-receipt.json" ;;
        wrong-size) printf ' ' >> "$report/$mode/000-request.json" ;;
        unsealed) printf 'open\n' > "$report/$mode/gate" ;;
        missing-receipt-complete) rm "$report/$mode/000-receipt.json" ;;
        symlink) rm "$report/$mode/000-request.json"; ln -s "$report/base/000-request.json" "$report/$mode/000-request.json" ;;
        hardlink) rm "$report/$mode/000-request.json"; ln "$report/base/000-request.json" "$report/$mode/000-request.json" ;;
        fifo) rm "$report/$mode/000-request.json"; mkfifo "$report/$mode/000-request.json" ;;
        extra-file) : > "$report/$mode/other" ;;
    esac
    if timeout 15 bash "$root/scripts/evaluation/ipc-usage.sh" "$report" "$mode" > "$report/$mode.out" 2> "$report/$mode.err"; then
        echo "accepted $mode" >&2; exit 1
    else [[ $? != 124 ]]; fi
    failed=$(sed -n 's/^Evaluation IPC usage: //p' "$report/$mode.out")
    jq -e '.status=="FAIL" and .complete_run==false' "$failed/summary.json" >/dev/null
    [[ ! -e $failed/result.json ]]
    [[ $mode != hardlink ]] || rm "$report/$mode/000-request.json"
    passed=$((passed+1))
done
if [[ $# == 1 ]]; then
    for mode in pressure tool; do
        timeout 60 bash "$root/scripts/evaluation/ipc-usage.sh" "$1" "$mode-restored" > "$report/retained-$mode.out" 2> "$report/retained-$mode.err"
        result="$(sed -n 's/^Evaluation IPC usage: //p' "$report/retained-$mode.out")/result.json"
        if [[ $mode == tool ]]; then
            jq -e '.complete_run==false and (.calls|length)==3 and .totals.input_tokens==38 and .totals.output_tokens==13' "$result" >/dev/null
        else
            jq -e '.complete_run==false and (.calls|length)==10 and .known_totals.input_tokens==79 and .known_totals.output_tokens==24 and
                .unknown_calls.input_tokens==1 and .totals.input_tokens==null' "$result" >/dev/null
        fi
        passed=$((passed+1))
    done
fi
printf 'Evaluation IPC usage checks passed: %s\n' "$passed"
