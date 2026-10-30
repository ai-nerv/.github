#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
capture=${1:?capture required}
evidence=${2:?evidence required}
mkdir -p "$evidence"
jq -e -f "$root/scripts/overflow-routing.jq" "$capture" > "$evidence/positive.json"
mutations=(
    '.requests += [.requests[0]]'
    '.requests[0].max_tokens=76'
    '.requests[0].messages |= map(select(.role!="user"))'
    '.log=""'
    '.log += "\nbalthasar[1] verb: overflowed extra\n"'
    '.log += "\nbalthasar[1] verb: job_done extra\n"'
    '.log |= gsub(", 0 jobs ";", 1 jobs ")'
    '.replay.result[0].raw |= (fromjson|.entry.text="changed"|tojson)'
    '.replay.result[1].raw |= (fromjson|.entry.error="changed"|tojson)'
    '.replay.result[1].raw |= (fromjson|.entry.stop_reason="end_turn"|tojson)'
    '.replay.result[2].raw |= (fromjson|.entry.error="changed"|tojson)'
    '.replay.result |= .[:1]'
    '.events |= map(select(.event!="assistant_ended"))'
    '.settled |= map(.status.kind="busy")'
    '.settled |= map(.entries=[])'
)
for index in "${!mutations[@]}"; do
    jq "${mutations[$index]}" "$capture" > "$evidence/mutation-$index.json"
    if jq -e -f "$root/scripts/overflow-routing.jq" "$evidence/mutation-$index.json" > "$evidence/mutation-$index.log" 2>&1; then
        echo "overflow routing mutation $index was accepted" >&2; exit 1
    fi
done
jq -n --argjson count "${#mutations[@]}" '{status:"PASS",source:"actual-family-overflow",refused_mutations:$count}' > "$evidence/summary.json"
