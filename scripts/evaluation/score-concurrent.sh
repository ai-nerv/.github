#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 2 ]] || exit 2
input=$1 receipt=$2
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
scratch=$(mktemp -d)
finish() {
    local code=$?
    trap - EXIT
    jq -n -L "$root/scripts/evaluation" --argjson code "$code" '
      include "contract";
      {schema:1,scope:"evaluation-concurrent-fixture-checks",task_id:"concurrent-disjoint-edits",
       status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,
       checks:[inventory[]|select(.id=="concurrent-disjoint-edits")|.checks[]|
         {id:.,status:(if $code==0 then "PASS" else "FAIL" end)}]}'
    rm -rf -- "$scratch"
    exit "$code"
}
trap finish EXIT
helper="$root/target/evaluation/bin/eval-input"
source "$root/scripts/evaluation/score-common.sh"
attempt_limit=$(score_attempt_limit "$input" "$scratch")
"$helper" tree "$receipt" evidence "$scratch/evidence" 16777216 32 > "$scratch/evidence-counts.json"
"$helper" tree "$receipt" work/work "$scratch/work" 16777216 256 > "$scratch/work-counts.json"
"$helper" tree "$input" work "$scratch/input" 16777216 256 > "$scratch/input-counts.json"
"$helper" file "$input" prompt.txt "$scratch/prompt" 16384 1 > "$scratch/prompt-counts.json"
for name in outer inside; do
    "$helper" file "$receipt" "$name.json" "$scratch/$name" 8192 1 > "$scratch/$name-counts.json"
done
jq -e '.exit_code==0 and .cleanup_confirmed and .timed_out==false and .interrupted==0 and (.output_limit_exceeded|not)' "$scratch/outer/input" >/dev/null
jq -e '.exit_code==0 and .leaked_processes==0 and .remaining_processes==0 and .exported and .streams_complete and (.output_limit_exceeded|not)' "$scratch/inside/input" >/dev/null
evidence="$scratch/evidence"
[[ $(cat "$evidence/left.exit") == 0 && $(cat "$evidence/right.exit") == 0 ]]
jq -ne --argjson attempt_limit "$attempt_limit" --rawfile prompt "$scratch/prompt/input" --rawfile original "$scratch/input/shared.txt" \
    --slurpfile requests "$evidence/requests.jsonl" --slurpfile replay0 "$evidence/replay-0.json" \
    --slurpfile replay1 "$evidence/replay-1.json" --slurpfile sessions "$evidence/sessions.json" \
    --slurpfile meter "$evidence/meter.jsonl" -f "$root/scripts/evaluation/concurrent-journal.jq" > "$scratch/winner.json"
winner=$(jq -er . "$scratch/winner.json")
[[ $winner == left || $winner == right ]]
for lane in left right; do
    log="$evidence/family-$lane.log"
    [[ $(grep -Ec 'casper\[[0-9]+\] run: ' "$log") == 2 ]]
    [[ $(grep -Ec 'casper\[[0-9]+\] run: read with 1 argument jailed=true .* ok in ' "$log") == 1 ]]
    outcome=failed
    [[ $lane != "$winner" ]] || outcome=ok
    [[ $(grep -Ec "casper\[[0-9]+\] run: edit with 3 arguments jailed=true .* $outcome in " "$log") == 1 ]]
done
sed "s/$winner=old/$winner=new/" "$scratch/input/shared.txt" > "$scratch/expected"
cmp "$scratch/expected" "$scratch/work/shared.txt" >&2
(cd "$scratch/input" && find . -type f | LC_ALL=C sort) > "$scratch/before-files"
(cd "$scratch/work" && find . -type f | LC_ALL=C sort) > "$scratch/after-files"
cmp "$scratch/before-files" "$scratch/after-files" >&2
while IFS= read -r file; do
    [[ $file == ./shared.txt ]] || cmp "$scratch/input/$file" "$scratch/work/$file" >&2
done < "$scratch/before-files"
