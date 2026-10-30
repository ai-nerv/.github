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
      {schema:1,scope:"evaluation-accounting-fixture-checks",task_id:"cache-accounting",
       status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,usage_source:"synthetic",real_cache_hits_verified:false,
       checks:[inventory[]|select(.id=="cache-accounting")|.checks[]|
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
"$helper" file "$input" providers.lua "$scratch/providers" 16384 1 > "$scratch/provider-counts.json"
for name in outer inside; do
    "$helper" file "$receipt" "$name.json" "$scratch/$name" 8192 1 > "$scratch/$name-counts.json"
done
jq -e '.exit_code==0 and .cleanup_confirmed and .timed_out==false and .interrupted==0 and (.output_limit_exceeded|not)' "$scratch/outer/input" >/dev/null
jq -e '.exit_code==0 and .leaked_processes==0 and .remaining_processes==0 and .exported and .streams_complete and (.output_limit_exceeded|not)' "$scratch/inside/input" >/dev/null
evidence="$scratch/evidence"
[[ $(cat "$evidence/chat.exit") == 0 && $(cat "$evidence/anthropic.exit") == 0 ]]
port=$(sed -n 's/^PORT=//p' "$evidence/provider.stdout")
[[ $port =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]]
sed "s/@PORT@/$port/g" "$scratch/providers/input" > "$scratch/expected-provider.lua"
cmp "$scratch/expected-provider.lua" "$evidence/config/4.lua" >&2
grep -Fx 'magi.model = "evaluation-chat/chat-1"' "$evidence/config/0.lua" >/dev/null
{ cat "$evidence/config/0.lua"; printf '\nmagi.model = "evaluation-anthropic/anthropic-1"\n'; } > "$scratch/expected-anthropic.lua"
cmp "$scratch/expected-anthropic.lua" "$evidence/config/anthropic-init.lua" >&2
jq -ne --argjson attempt_limit "$attempt_limit" --rawfile prompt "$scratch/prompt/input" --rawfile rates "$scratch/input/rates.txt" --rawfile stable "$scratch/input/stable.txt" \
    --slurpfile requests "$evidence/requests.jsonl" --slurpfile replay0 "$evidence/replay-0.json" --slurpfile replay1 "$evidence/replay-1.json" \
    --slurpfile sessions "$evidence/sessions.json" --slurpfile meter "$evidence/meter.jsonl" \
    --slurpfile runs "$evidence/ledger-runs.json" \
    --rawfile ledger0 "$evidence/ledger-0.txt" --rawfile ledger1 "$evidence/ledger-1.txt" \
    -f "$root/scripts/evaluation/accounting-journal.jq" >/dev/null
for dialect in chat anthropic; do
    run=$(jq -er --arg dialect "$dialect" '.[$dialect]' "$evidence/ledger-runs.json")
    [[ $run =~ ^[a-zA-Z0-9_-]+$ ]]
    logged=$(jq -nr -L "$root/scripts/evaluation" --arg run "$run" 'include "log-word"; $run|magi_log_word')
    agent=$(jq -nr -L "$root/scripts/evaluation" --arg run "$run" 'include "log-word"; $run|sub("-[0-9]+$";"")|magi_log_word')
    [[ $(grep -Fc "session: $logged as agent $agent serving in /world/work/work, model evaluation-$dialect/$dialect-1, memory reached" "$evidence/family-$dialect.log") == 1 ]]
    [[ $(grep -Ec 'casper\[[0-9]+\] run: ' "$evidence/family-$dialect.log") == 2 ]]
    [[ $(grep -Ec 'casper\[[0-9]+\] run: read with 1 argument jailed=true .* ok in ' "$evidence/family-$dialect.log") == 2 ]]
done
(cd "$scratch/input" && find . -type f | LC_ALL=C sort) > "$scratch/before-files"
(cd "$scratch/work" && find . -type f | LC_ALL=C sort) > "$scratch/after-files"
cmp "$scratch/before-files" "$scratch/after-files" >&2
while IFS= read -r file; do cmp "$scratch/input/$file" "$scratch/work/$file" >&2; done < "$scratch/before-files"
