#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 3 ]] || { echo 'usage: reconcile-usage.sh TASK EXECUTION_ROOT WORLD_RELATIVE' >&2; exit 2; }
task=$1 input=$2 world=$3
case $task in
    small-bug-fix|read-index-select-edit|large-file-edit|concurrent-disjoint-edits|repetitive-failure|output-only-overflow|input-pressure|cache-accounting|resume|child-work) ;;
    *) exit 2 ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
source "$root/scripts/preserve-binary.sh"
receipt=$(mktemp -d "$root/target/evaluation/reconciled-usage-XXXXXXXX")
mkdir "$receipt/bin" "$receipt/lib" "$receipt/work" "$receipt/inputs"
touch "$receipt/binaries.sha256"
finish() {
    local code=$?
    trap - EXIT
    if ! verify_preserved_binaries "$receipt/binaries.sha256" > "$receipt/integrity.log" 2>&1; then code=1; fi
    if [[ -f $receipt/inputs.sha256 ]] && ! sha256sum -c "$receipt/inputs.sha256" > "$receipt/input-integrity.log" 2>&1; then code=1; fi
    if (( code != 0 )); then rm -f "$receipt/result.json"; fi
    jq -n --argjson code "$code" '{schema:1,scope:"evaluation-reconciled-synthetic-usage",status:(if $code==0 then "USAGE_RECONCILED" else "FAIL" end),exit_code:$code,workers_started:0,real_billing_verified:false}' > "$receipt/summary.json"
    printf 'Evaluation reconciled usage: %s\n' "$receipt"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
preserve_binary "$root/target/evaluation/bin/eval-input" "$receipt/bin/eval-input" "$receipt/binaries.sha256" >/dev/null
preserve_binary "$(type -P jq)" "$receipt/bin/jq" "$receipt/binaries.sha256" >/dev/null
helper="$receipt/bin/eval-input" parser="$receipt/bin/jq"
for name in contract reconcile-usage; do
    "$helper" file "$root/scripts/evaluation" "$name.jq" "$receipt/work/filter-$name" 131072 1 >/dev/null
    cp "$receipt/work/filter-$name/input" "$receipt/lib/$name.jq"
done
for spec in "transcripts:transcript-usage/transcripts.json" "durable:transcript-usage/result.json" \
    "attempts:client-attempts.json" "script:selected/fixtures/$task/provider.json" "meter:$world/receipt/evidence/meter.jsonl"; do
    name=${spec%%:*} path=${spec#*:}
    "$helper" file "$input" "$path" "$receipt/inputs/$name" 16777216 1 >/dev/null
    if [[ $name == script ]]; then "$helper" json-wire "$receipt/inputs/$name" input 16777216 >/dev/null
    elif [[ $name != meter ]]; then "$helper" json "$receipt/inputs/$name" input 16777216 >/dev/null; fi
done
bash "$root/scripts/evaluation/request-bytes.sh" "$input/$world/receipt/evidence" > "$receipt/provider.out" 2> "$receipt/provider.err"
provider=$(sed -n 's/^Evaluation request bytes: //p' "$receipt/provider.out")
[[ $provider == "$root/target/evaluation/request-bytes-"* ]]
cmp "$receipt/inputs/meter/input" "$provider/meter/input"
bash "$root/scripts/evaluation/ipc-usage.sh" "$input/model-ipc" raw > "$receipt/ipc.out" 2> "$receipt/ipc.err"
ipc=$(sed -n 's/^Evaluation IPC usage: //p' "$receipt/ipc.out")
[[ $ipc == "$root/target/evaluation/ipc-usage-"* ]]
: > "$receipt/work/calls.jsonl"
count=$("$parser" -r .calls "$ipc/capture/summary.json")
for ((id=0;id<count;id++)); do
    printf -v prefix '%03d' "$id"
    "$parser" -nc --argjson id "$id" --slurpfile calls "$ipc/work/calls.jsonl" \
        --slurpfile request "$ipc/capture/$prefix-request.json" \
        '$calls[]|select(.call==$id)|.+{request:$request[0]}' >> "$receipt/work/calls.jsonl"
done
lines=0
: > "$receipt/work/meter.jsonl"
while IFS= read -r line; do
    lines=$((lines+1)); [[ $lines -le 512 ]]
    printf '%s\n' "$line" > "$receipt/work/event.json"
    cat "$receipt/work/event.json" >> "$receipt/work/meter.jsonl"
    "$helper" json "$receipt/work" event.json 131072 >/dev/null
done < "$receipt/inputs/meter/input"
cmp "$receipt/work/meter.jsonl" "$receipt/inputs/meter/input"
find "$receipt/inputs" "$receipt/lib" -type f -exec sha256sum -- {} + > "$receipt/inputs.sha256"
"$parser" -n --slurpfile calls "$receipt/work/calls.jsonl" --slurpfile ipc "$ipc/result.json" \
    --slurpfile transcripts "$receipt/inputs/transcripts/input" --slurpfile durable "$receipt/inputs/durable/input" \
    --slurpfile attempts "$receipt/inputs/attempts/input" --slurpfile script "$receipt/inputs/script/input" \
    --slurpfile meter "$receipt/inputs/meter/input" \
    '{calls:$calls,ipc:$ipc[0],transcripts:$transcripts[0],durable_usage:$durable[0],attempts:$attempts[0],script:$script[0],meter:$meter}' > "$receipt/work/input.json"
"$parser" -e -L "$receipt/lib" --arg task "$task" -f "$receipt/lib/reconcile-usage.jq" "$receipt/work/input.json" > "$receipt/result.json"
"$helper" json "$receipt" result.json 16777216 >/dev/null
