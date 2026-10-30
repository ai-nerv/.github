#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 3 ]] || { echo 'usage: activity.sh TASK EXECUTION_ROOT WORLD_RELATIVE' >&2; exit 2; }
task=$1 input=$2 world=$3
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
source "$root/scripts/preserve-binary.sh"
receipt=$(mktemp -d "$root/target/evaluation/activity-XXXXXXXX")
mkdir "$receipt/bin" "$receipt/lib" "$receipt/inputs" "$receipt/work"
touch "$receipt/binaries.sha256"
finish() {
    local code=$?
    trap - EXIT
    if ! verify_preserved_binaries "$receipt/binaries.sha256" > "$receipt/binary-integrity.log" 2>&1; then code=1; fi
    if [[ -f $receipt/inputs.sha256 ]] && ! sha256sum -c "$receipt/inputs.sha256" > "$receipt/input-integrity.log" 2>&1; then code=1; fi
    if (( code != 0 )); then rm -f "$receipt/result.json"; fi
    jq -n --argjson code "$code" '{schema:1,scope:"evaluation-activity-observations",status:(if $code==0 then "ACTIVITY_OBSERVED" else "FAIL" end),exit_code:$code,workers_started:0}' > "$receipt/summary.json"
    printf 'Evaluation activity observations: %s\n' "$receipt"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
preserve_binary "$root/target/evaluation/bin/eval-input" "$receipt/bin/eval-input" "$receipt/binaries.sha256" >/dev/null
preserve_binary "$(type -P jq)" "$receipt/bin/jq" "$receipt/binaries.sha256" >/dev/null
helper="$receipt/bin/eval-input" parser="$receipt/bin/jq"
for name in contract activity; do
    "$helper" file "$root/scripts/evaluation" "$name.jq" "$receipt/work/filter-$name" 131072 1 >/dev/null
    cp "$receipt/work/filter-$name/input" "$receipt/lib/$name.jq"
done
bash "$root/scripts/evaluation/reconcile-usage.sh" "$task" "$input" "$world" > "$receipt/reconcile.out" 2> "$receipt/reconcile.err"
reconciled=$(sed -n 's/^Evaluation reconciled usage: //p' "$receipt/reconcile.out")
[[ $reconciled == "$root/target/evaluation/reconciled-usage-"* ]]
bash "$root/scripts/evaluation/normalized-prefix.sh" "$input/$world/receipt/evidence" > "$receipt/prefix.out" 2> "$receipt/prefix.err"
prefix=$(sed -n 's/^Evaluation normalized prefix: //p' "$receipt/prefix.out")
[[ $prefix == "$root/target/evaluation/prefix-"* ]]
"$helper" file "$reconciled" result.json "$receipt/inputs/reconciled" 16777216 1 >/dev/null
"$helper" file "$reconciled" work/input.json "$receipt/inputs/raw" 16777216 1 >/dev/null
"$helper" file "$prefix" result.json "$receipt/inputs/prefix" 131072 1 >/dev/null
"$helper" file "$prefix" requests/input "$receipt/inputs/requests" 8388608 1 >/dev/null
logs=(family.log)
case $task in
    concurrent-disjoint-edits) logs=(family-left.log family-right.log) ;;
    cache-accounting) logs=(family-chat.log family-anthropic.log) ;;
esac
: > "$receipt/work/logs.jsonl"
remaining=4194304
for file in "${logs[@]}"; do
    "$helper" file "$input" "$world/receipt/evidence/$file" "$receipt/inputs/$file" "$remaining" 1 > "$receipt/work/$file-counts.json"
    remaining=$((remaining-$("$parser" -r .bytes "$receipt/work/$file-counts.json")))
    "$parser" -nc --arg file "$file" --rawfile text "$receipt/inputs/$file/input" '{file:$file,text:$text}' > "$receipt/work/log.json"
    "$parser" -jr .text "$receipt/work/log.json" | cmp - "$receipt/inputs/$file/input"
    cat "$receipt/work/log.json" >> "$receipt/work/logs.jsonl"
done
find "$receipt/inputs" "$receipt/lib" -type f -exec sha256sum -- {} + > "$receipt/inputs.sha256"
"$parser" -n --slurpfile raw "$receipt/inputs/raw/input" --slurpfile reconciled "$receipt/inputs/reconciled/input" \
    --slurpfile prefix "$receipt/inputs/prefix/input" --slurpfile requests "$receipt/inputs/requests/input" \
    --slurpfile logs "$receipt/work/logs.jsonl" \
    '{raw:$raw[0],reconciled:$reconciled[0],prefix:$prefix[0],requests:$requests,logs:$logs}' > "$receipt/work/input.json"
"$parser" -e -L "$receipt/lib" --arg task "$task" -f "$receipt/lib/activity.jq" "$receipt/work/input.json" > "$receipt/result.json"
"$helper" json "$receipt" result.json 16777216 >/dev/null
