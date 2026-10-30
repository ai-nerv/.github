#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
capture=${1:?capture required}
evidence=${2:?evidence required}
mkdir -p "$evidence"
jq -e -f "$root/scripts/cache-rules.jq" "$capture" > "$evidence/positive.json"
mutations=(
    '.requests |= map(.messages |= map(.content |= map(if .type=="text" and (.text|startswith("Verified project rules:")) then .text="different rule" else . end)))'
    '.requests |= map(.messages |= map(if any(.content[];.type=="text" and (.text|startswith("Verified project rules:"))) then .role="assistant" else . end))'
    '.requests |= map(.messages |= map(.content |= map(if .type=="thinking" then .signature="changed" else . end)))'
    '.events |= map(if .event=="cache_frame" then .reasons=[] else . end)'
    '.events |= map(select(.event!="context_laid"))'
    '.note.result[0].text="different rule"'
    '.note.result[0].pinned=false'
    '.note.result[0].evidence.sources[0].eligible=false'
    '.note.result[0].evidence.sources[0].role="assistant"'
    '.note.result[0].evidence.sources[0].quote="different directive"'
    '.replay.result |= .[:4]'
)
for index in "${!mutations[@]}"; do
    jq "${mutations[$index]}" "$capture" > "$evidence/mutation-$index.json"
    if jq -e -f "$root/scripts/cache-rules.jq" "$evidence/mutation-$index.json" > "$evidence/mutation-$index.log" 2>&1; then
        echo "cache rules mutation $index was accepted" >&2; exit 1
    fi
done
jq -n --argjson count "${#mutations[@]}" '{status:"PASS",source:"actual-family-rules",refused_mutations:$count}' > "$evidence/summary.json"
