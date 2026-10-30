#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
capture=${1:?capture required}
evidence=${2:?evidence required}
mkdir -p "$evidence"
jq -e -f "$root/scripts/cache-policy.jq" "$capture" > "$evidence/positive.json"
mutations=(
    '.requests |= .[0:3]'
    '.requests[2].messages[0].content[0].text = "rewritten"'
    '.requests[2].messages[0].content[1].text = "different omission"'
    '.requests[3].messages[0].content[1].source.data = "different image"'
    '.requests[1].messages[1].content[0].signature = "different signature"'
    '.requests[1].tools[-1].cache_control = {type:"ephemeral"}'
    '.requests[2].model = "different-model"'
    '.events |= map(select(.event != "provider_frame"))'
    '.events |= map(if .event=="provider_frame" then .reasons=[] else . end)'
    '.events |= map(if .event=="provider_frame" then .policy=[0] else . end)'
)
for index in "${!mutations[@]}"; do
    jq "${mutations[$index]}" "$capture" > "$evidence/mutation-$index.json"
    if jq -e -f "$root/scripts/cache-policy.jq" "$evidence/mutation-$index.json" > "$evidence/mutation-$index.log" 2>&1; then
        echo "cache policy mutation $index was accepted" >&2; exit 1
    fi
done
jq -n --argjson count "${#mutations[@]}" '{status:"PASS",source:"actual-family-policy-requests",refused_mutations:$count}' > "$evidence/summary.json"
