#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
capture=${1:?capture required}
evidence=${2:?evidence required}
mkdir -p "$evidence"
jq -e -f "$root/scripts/cache-mask.jq" "$capture" > "$evidence/positive.json"
mutations=(
    '.requests |= map(.messages |= map(.content |= map(if .type=="tool_result" then .content="changed" else . end)))'
    '.requests |= map(.messages |= map(.content |= map(if .type=="tool_result" then .tool_use_id="wrong" else . end)))'
    '.requests |= map(.messages |= map(.content |= map(if .type=="tool_use" then .input.path="other.rs" else . end)))'
    '.requests |= map(.messages |= map(.content |= map(if .type=="thinking" then .signature="changed" else . end)))'
    '.requests |= map(.messages |= map(.content |= map(if .type=="thinking" then .cache_control={type:"ephemeral"} else . end)))'
    '.requests |= map(.messages |= map(.content |= map(if .type=="text" and (.text|startswith("(this conversation")) then .text="changed warning" else . end)))'
    '.requests |= map(.messages |= map(.content |= map(if .type=="text" and .text=="keep the same mask" then .text="changed prompt" else . end)))'
    '.events |= map(if .event=="cache_frame" then .reasons=[] else . end)'
    '.events |= map(if .event=="cache_frame" then .reasons=["layout_changed"] else . end)'
    '.events |= map(select(.event!="context_laid"))'
    '.events |= map(if .event=="context_laid" then .slots |= map(if .kind=="stub" then .cursor=2 else . end) else . end)'
    '.events |= map(if .event=="context_laid" then .slots |= map(if .kind=="stub" then .text="changed" else . end) else . end)'
    '.replay.result[2].raw |= (fromjson|.entry.result.output="read mask.rs (401 lines)"|tojson)'
    '.replay.result |= .[:7]'
)
for index in "${!mutations[@]}"; do
    jq "${mutations[$index]}" "$capture" > "$evidence/mutation-$index.json"
    if jq -e -f "$root/scripts/cache-mask.jq" "$evidence/mutation-$index.json" > "$evidence/mutation-$index.log" 2>&1; then
        echo "cache mask mutation $index was accepted" >&2; exit 1
    fi
done
jq -n --argjson count "${#mutations[@]}" '{status:"PASS",source:"actual-family-mask",refused_mutations:$count}' > "$evidence/summary.json"
