#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
capture=${1:?capture required}
evidence=${2:?evidence required}
mkdir -p "$evidence"
jq -e -f "$root/scripts/cache-resume.jq" "$capture" > "$evidence/positive.json"
mutations=(
    '.requests |= .[:3]'
    '.requests[2].messages[0].content[0].text="rewritten"'
    '.requests[2].messages[0].content[1].source.data="changed"'
    '.requests[2].messages[1].content[0].signature="changed"'
    '.requests[2].messages[1].content[1].id="changed"'
    '.requests[2].model="changed"'
    '.requests[2].messages[0].content[0].cache_control={type:"ephemeral"}'
    '.requests[2].tools[-1].cache_control={type:"unsupported"}'
    '.events |= map(select(.event!="cache_frame"))'
    '.events |= map(if .event=="cache_frame" then .reasons=[] else . end)'
    '.events += [{event:"cache_frame",reasons:["resume_incompatible"]}]'
    '.after.result |= .[:4]'
)
for index in "${!mutations[@]}"; do
    jq "${mutations[$index]}" "$capture" > "$evidence/mutation-$index.json"
    if jq -e -f "$root/scripts/cache-resume.jq" "$evidence/mutation-$index.json" > "$evidence/mutation-$index.log" 2>&1; then
        echo "cache resume mutation $index was accepted" >&2; exit 1
    fi
done
jq -n --argjson count "${#mutations[@]}" '{status:"PASS",source:"actual-family-resume",refused_mutations:$count}' > "$evidence/summary.json"
