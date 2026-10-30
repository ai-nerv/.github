#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 3 && ( $1 == repetitive-failure || $1 == output-only-overflow ) ]] || { echo 'usage: score-control.sh TASK FROZEN_INPUT RECEIPT' >&2; exit 2; }
task=$1 input=$2 receipt=$3
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
scratch=$(mktemp -d)
finish() {
    local code=$?
    trap - EXIT
    jq -n -L "$root/scripts/evaluation" --arg task "$task" --argjson code "$code" '
      include "contract";
      {schema:1,scope:"evaluation-control-fixture-checks",task_id:$task,status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,
       checks:[inventory[]|select(.id==$task)|.checks[]|{id:.,status:(if $code==0 then "PASS" else "FAIL" end)}]}'
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
code=$(cat "$evidence/magi.exit")
[[ $code == 0 || $code == 1 ]]
jq -ne --argjson attempt_limit "$attempt_limit" --arg task "$task" --argjson exit "$code" --rawfile log "$evidence/family.log" --rawfile prompt "$scratch/prompt/input" \
    --slurpfile requests "$evidence/requests.jsonl" --slurpfile replay "$evidence/replay.json" \
    --slurpfile sessions "$evidence/sessions.json" --slurpfile meter "$evidence/meter.jsonl" \
    -f "$root/scripts/evaluation/control-journal.jq" >/dev/null
(cd "$scratch/input" && find . -type f | LC_ALL=C sort) > "$scratch/before-files"
(cd "$scratch/work" && find . -type f | LC_ALL=C sort) > "$scratch/after-files"
cmp "$scratch/before-files" "$scratch/after-files" >&2
while IFS= read -r file; do cmp "$scratch/input/$file" "$scratch/work/$file" >&2; done < "$scratch/before-files"
