#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
capture=${1:?capture required}
evidence=${2:?evidence required}
mkdir -p "$evidence"
jq -e -f "$root/scripts/cache-discovery.jq" "$capture" > "$evidence/positive.json"
mutations=(
    '.requests |= .[:2]'
    '.requests[0].tools += [.requests[1].tools[]|select(.name=="dino")]'
    '.requests[1].tools |= map(select(.name!="dino"))'
    '.requests[1].tools[0].description="rewritten"'
    '.requests[2].messages[0].content[0].text="rewritten"'
    '.requests[2].messages[1].content[0].signature="changed"'
    '.requests[2].messages[1].content[1].id="changed"'
    '.events |= map(if .event=="cache_frame" then .reasons=[] else . end)'
    '.events += [{event:"cache_frame",reasons:["tools_changed"]}]'
    '.replay.result |= .[:4]'
)
for index in "${!mutations[@]}"; do
    jq "${mutations[$index]}" "$capture" > "$evidence/mutation-$index.json"
    if jq -e -f "$root/scripts/cache-discovery.jq" "$evidence/mutation-$index.json" > "$evidence/mutation-$index.log" 2>&1; then
        echo "cache discovery mutation $index was accepted" >&2; exit 1
    fi
done
jq -n --argjson count "${#mutations[@]}" '{status:"PASS",source:"actual-family-discovery",refused_mutations:$count}' > "$evidence/summary.json"
