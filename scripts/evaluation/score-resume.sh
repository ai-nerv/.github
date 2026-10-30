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
      {schema:1,scope:"evaluation-resume-fixture-checks",task_id:"resume",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,
       checks:[inventory[]|select(.id=="resume")|.checks[]|{id:.,status:(if $code==0 then "PASS" else "FAIL" end)}]}'
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
for name in prompt.txt distractor.txt latest.txt named.txt providers.lua; do
    "$helper" file "$input" "$name" "$scratch/$name" 16384 1 > "$scratch/$name-counts.json"
done
for name in outer inside; do
    "$helper" file "$receipt" "$name.json" "$scratch/$name" 8192 1 > "$scratch/$name-counts.json"
done
jq -e '.exit_code==0 and .cleanup_confirmed and .timed_out==false and .interrupted==0 and (.output_limit_exceeded|not)' "$scratch/outer/input" >/dev/null
jq -e '.exit_code==0 and .leaked_processes==0 and .remaining_processes==0 and .exported and .streams_complete and (.output_limit_exceeded|not)' "$scratch/inside/input" >/dev/null
evidence="$scratch/evidence"
[[ $(cat "$evidence/missing.exit") == 1 ]]
grep -F 'missing-evaluation-run' "$evidence/missing.stderr" >/dev/null
port=$(sed -n 's/^PORT=//p' "$evidence/provider.stdout")
[[ $port =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]]
sed "s/@PORT@/$port/g" "$scratch/providers.lua/input" > "$scratch/expected-provider.lua"
cmp "$scratch/expected-provider.lua" "$evidence/config/4.lua" >&2
jq -ne --argjson attempt_limit "$attempt_limit" --rawfile prompt "$scratch/prompt.txt/input" --rawfile distractor "$scratch/distractor.txt/input" \
    --rawfile latest "$scratch/latest.txt/input" --rawfile named "$scratch/named.txt/input" --rawfile original "$scratch/input/counter.txt" \
    --slurpfile requests "$evidence/requests.jsonl" --slurpfile initial "$evidence/replay-initial.json" \
    --slurpfile other "$evidence/replay-distractor.json" --slurpfile resumed_latest "$evidence/replay-latest.json" \
    --slurpfile resumed_named "$evidence/replay-named.json" --slurpfile phases "$evidence/phases.jsonl" \
    --slurpfile sessions "$evidence/sessions.json" --slurpfile meter "$evidence/meter.jsonl" \
    --rawfile ledger_initial "$evidence/ledger-initial.txt" --rawfile ledger_other "$evidence/ledger-distractor.txt" \
    --rawfile ledger_latest "$evidence/ledger-latest.txt" --rawfile ledger_named "$evidence/ledger-named.txt" \
    -f "$root/scripts/evaluation/resume-journal.jq" >/dev/null
jq -r -L "$root/scripts/evaluation" 'include "log-word";
    (.transcript|magi_log_word)+" as agent "+(.coordination_run|sub("-[0-9]+$";"")|magi_log_word)+" serving in /world/work/work, model evaluation/echo-1, memory reached"' \
    "$evidence/phases.jsonl" > "$scratch/expected-sessions"
sed -nE 's/^.* magi\[[0-9]+\] session: //p' "$evidence/family.log" > "$scratch/actual-sessions"
cmp "$scratch/expected-sessions" "$scratch/actual-sessions" >&2
[[ $(grep -Ec 'casper\[[0-9]+\] run: ' "$evidence/family.log") == 2 ]]
[[ $(grep -Ec 'casper\[[0-9]+\] run: read with 1 argument jailed=true .* ok in ' "$evidence/family.log") == 1 ]]
[[ $(grep -Ec 'casper\[[0-9]+\] run: edit with 3 arguments jailed=true .* ok in ' "$evidence/family.log") == 1 ]]
sed 's/count=0/count=1/' "$scratch/input/counter.txt" > "$scratch/expected"
cmp "$scratch/expected" "$scratch/work/counter.txt" >&2
(cd "$scratch/input" && find . -type f | LC_ALL=C sort) > "$scratch/before-files"
(cd "$scratch/work" && find . -type f | LC_ALL=C sort) > "$scratch/after-files"
cmp "$scratch/before-files" "$scratch/after-files" >&2
while IFS= read -r file; do
    [[ $file == ./counter.txt ]] || cmp "$scratch/input/$file" "$scratch/work/$file" >&2
done < "$scratch/before-files"
