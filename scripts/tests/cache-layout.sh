#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
capture=${1:?capture required}
evidence=${2:?evidence required}
mkdir -p "$evidence"
jq -e -f "$root/scripts/cache-layout.jq" "$capture" > "$evidence/positive.json"
mutations=(
    '.requests |= map(select(all(.tools[]?;.name!="read")))'
    '.requests |= map(if any(.tools[]?;.name=="read") then .model="changed" else . end) | .requests[0].model="original"'
    '.requests |= map(.messages |= map(.content |= map(if .type=="tool_result" then .content="rewritten" else . end)))'
    '.requests |= map(.messages |= map(.content |= map(if .type=="tool_use" then .id="rewritten" else . end)))'
    '.requests |= map(.messages |= map(.content |= map(if .type=="thinking" then .signature="rewritten" else . end)))'
    '.requests |= map(.messages |= map(.content |= map(if .type=="text" and (.text|contains("Cache layout summary")) then .text="summary without failed-call guard" else . end)))'
    '.events |= map(select(.event!="context_laid"))'
    '.events |= map(if .event=="context_laid" then .slots |= map(select(.kind!="item")) else . end)'
    '.events |= map(if .event=="cache_frame" then .reasons=[] else . end)'
    '.events |= map(if .event=="cache_frame" then .reasons |= map(select(.!="summary_activated")) else . end)'
    '.events |= map(select(.event!="request_admitted"))'
    '.replay.result |= .[1:]'
)
for index in "${!mutations[@]}"; do
    jq "${mutations[$index]}" "$capture" > "$evidence/mutation-$index.json"
    if jq -e -f "$root/scripts/cache-layout.jq" "$evidence/mutation-$index.json" > "$evidence/mutation-$index.log" 2>&1; then
        echo "cache layout mutation $index was accepted" >&2; exit 1
    fi
done
jq -n --argjson count "${#mutations[@]}" '{status:"PASS",source:"actual-family-layout",refused_mutations:$count}' > "$evidence/summary.json"
