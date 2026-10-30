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
      {schema:1,scope:"evaluation-pressure-fixture-checks",task_id:"input-pressure",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,
       checks:[inventory[]|select(.id=="input-pressure")|.checks[]|{id:.,status:(if $code==0 then "PASS" else "FAIL" end)}]}'
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
for name in prompt.txt providers.lua; do
    "$helper" file "$input" "$name" "$scratch/$name" 16384 1 > "$scratch/$name-counts.json"
done
for name in outer inside; do
    "$helper" file "$receipt" "$name.json" "$scratch/$name" 8192 1 > "$scratch/$name-counts.json"
done
jq -e '.exit_code==0 and .cleanup_confirmed and .timed_out==false and .interrupted==0 and (.output_limit_exceeded|not)' "$scratch/outer/input" >/dev/null
jq -e '.exit_code==0 and .leaked_processes==0 and .remaining_processes==0 and .exported and .streams_complete and (.output_limit_exceeded|not)' "$scratch/inside/input" >/dev/null
evidence="$scratch/evidence"
[[ $(cat "$evidence/magi.exit") == 0 && $(cat "$evidence/provider.exit") == 0 ]]
port=$(sed -n 's/^PORT=//p' "$evidence/provider.stdout")
[[ $port =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]]
sed "s/@PORT@/$port/g" "$scratch/providers.lua/input" > "$scratch/expected-provider.lua"
cmp "$scratch/expected-provider.lua" "$evidence/config/4.lua" >&2
grep -Fx 'magi.helpers = { memory = false, summary = "evaluation/echo-1" }' "$evidence/config/0.lua" >/dev/null
jq -ne --argjson attempt_limit "$attempt_limit" --rawfile prompt "$scratch/prompt.txt/input" --rawfile facts "$scratch/input/facts.txt" \
    --rawfile noise_b "$scratch/input/noise-b.txt" --rawfile noise_c "$scratch/input/noise-c.txt" \
    --rawfile log "$evidence/family.log" --slurpfile requests "$evidence/requests.jsonl" \
    --slurpfile replay "$evidence/replay.json" --slurpfile sessions "$evidence/sessions.json" --slurpfile meter "$evidence/meter.jsonl" \
    -f "$root/scripts/evaluation/pressure-journal.jq" >/dev/null
(cd "$scratch/input" && find . -type f | LC_ALL=C sort) > "$scratch/before-files"
(cd "$scratch/work" && find . -type f | LC_ALL=C sort) > "$scratch/after-files"
cmp "$scratch/before-files" "$scratch/after-files" >&2
while IFS= read -r file; do cmp "$scratch/input/$file" "$scratch/work/$file" >&2; done < "$scratch/before-files"
