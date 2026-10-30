#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
requests=${1:?actual request JSONL required}
evidence=${2:?negative evidence directory required}
mkdir -p "$evidence"
jq -e -s -f "$root/scripts/cache-contract.jq" "$requests" > "$evidence/positive.json"
changes=(
    '.[1:]'
    'map(.messages |= map(.content |= map(del(.cache_control))))'
    '.[1].messages[0].content[0].cache_control={type:"ephemeral"}'
    '.[1].messages[1].content[0].cache_control={type:"ephemeral"}'
    '.[2].system[0].text="changed rules"'
    '.[2].tools[0].description="changed tools"'
    '.[1].messages[1].content[0].signature="changed signature"'
    '.[1].messages[1].content[1].id="changed call"'
    '.[1].messages[2].content[0].tool_use_id="changed result"'
    '.[1].messages[2].content[0].content="MODEL SAID IT READ THE FILE"'
    '.[1].messages[1].content[1].input.cache_control={type:"literal user change"}'
    '.[2].messages[-1].content[-1].cache_control.ttl="1h"'
)
for index in "${!changes[@]}"; do
    jq -s "${changes[index]} | .[]" "$requests" > "$evidence/$index.jsonl"
    if jq -e -s -f "$root/scripts/cache-contract.jq" "$evidence/$index.jsonl" > "$evidence/$index.out" 2> "$evidence/$index.err"; then
        echo "cache verifier accepted mutation$index" >&2
        exit 1
    fi
done
jq -n --argjson refused "${#changes[@]}" '{status:"PASS",source:"actual-family-requests",refused_mutations:$refused}' > "$evidence/summary.json"
