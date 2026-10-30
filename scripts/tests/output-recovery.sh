#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
capture=${1:?capture required}
evidence=${2:?evidence required}
mkdir -p "$evidence"
jq -e -f "$root/scripts/output-recovery.jq" "$capture" > "$evidence/positive.json"
mutations=(
    '.requests += [.requests[1]]'
    '.requests[1].max_tokens=4096'
    '.requests[0].max_tokens=77'
    '.requests[1].messages=[]'
    '.requests[1].thinking="off"'
    '.requests |= map(.__budget={})'
    '.log=""'
    '.log += "\nbalthasar[1] verb: overflowed extra\n"'
    '.replay.result[0].raw |= (fromjson|.entry.text="changed"|tojson)'
    '.replay.result[1].raw |= (fromjson|.entry.stop_reason="error"|tojson)'
    '.events |= map(select(.event!="assistant_ended"))'
    '.settled |= map(.status.kind="busy")'
)
for index in "${!mutations[@]}"; do
    jq "${mutations[$index]}" "$capture" > "$evidence/mutation-$index.json"
    if jq -e -f "$root/scripts/output-recovery.jq" "$evidence/mutation-$index.json" > "$evidence/mutation-$index.log" 2>&1; then
        echo "output recovery mutation $index was accepted" >&2; exit 1
    fi
done
jq -n --argjson count "${#mutations[@]}" '{status:"PASS",source:"actual-family-output-recovery",refused_mutations:$count}' > "$evidence/summary.json"
