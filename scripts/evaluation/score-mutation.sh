#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ ( $# == 3 && ( $1 == small-bug-fix || $1 == large-file-edit ) ) ||
   ( $# == 4 && $1 == read-index-select-edit && $4 =~ ^[0-9a-f]{64}$ ) ]] || {
    echo 'usage: score-mutation.sh TASK FROZEN_INPUT RECEIPT [RUST_GRAMMAR_SHA256]' >&2; exit 2;
}
task=$1 input=$2 receipt=$3
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
scratch=$(mktemp -d)
first=false second=false
finish() {
    local code=$?
    trap - EXIT
    jq -n -L "$root/scripts/evaluation" --arg task "$task" --argjson code "$code" --argjson first "$first" --argjson second "$second" '
      include "contract";
      {schema:1,scope:"evaluation-mutation-fixture-checks",task_id:$task,status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,
       checks:[inventory[]|select(.id==$task)|.checks|to_entries[]|
         {id:.value,status:(if (if .key==0 then $first else $second end) then "PASS" else "FAIL" end)}]}'
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
evidence="$scratch/evidence"
jq -e '.exit_code==0 and .cleanup_confirmed and .timed_out==false and .interrupted==0 and (.output_limit_exceeded|not)' "$scratch/outer/input" >/dev/null
jq -e '.exit_code==0 and .leaked_processes==0 and .remaining_processes==0 and .exported and .streams_complete and (.output_limit_exceeded|not)' "$scratch/inside/input" >/dev/null
[[ $(cat "$evidence/magi.exit") == 0 ]]
if [[ $task == read-index-select-edit ]]; then [[ $(cat "$evidence/rust-grammar.sha256") == "$4  -" ]]; fi
journal=mutation-journal.jq
case $task in
    small-bug-fix)
        old='value < capacity' new='value <= capacity'
        sed 's/value < capacity/value <= capacity/' "$scratch/input/src/lib.rs" > "$scratch/expected.rs" ;;
    read-index-select-edit)
        old=$'pub fn retry_delay(attempt: u32) -> u32 {\n    attempt.saturating_mul(2)\n}'
        new=$'pub fn retry_delay(attempt: u32) -> u32 {\n    2_u32.saturating_pow(attempt).min(64)\n}'
        sed '2s/attempt.saturating_mul(2)/2_u32.saturating_pow(attempt).min(64)/' "$scratch/input/src/lib.rs" > "$scratch/expected.rs"
        journal=index-journal.jq ;;
    large-file-edit)
        old='pub const MODE: u8 = 0;' new='pub const MODE: u8 = 1;'
        [[ $(wc -c < "$scratch/input/src/lib.rs") -gt 262144 ]]
        sed 's/pub const MODE: u8 = 0;/pub const MODE: u8 = 1;/' "$scratch/input/src/lib.rs" > "$scratch/expected.rs" ;;
esac
if [[ $task != read-index-select-edit ]]; then [[ $(grep -Fc "$old" "$scratch/input/src/lib.rs") == 1 ]]; fi
jq -ne --argjson attempt_limit "$attempt_limit" --arg old "$old" --arg new "$new" --rawfile prompt "$scratch/prompt/input" --slurpfile requests "$evidence/requests.jsonl" \
    --slurpfile replay "$evidence/replay.json" --slurpfile sessions "$evidence/sessions.json" --slurpfile meter "$evidence/meter.jsonl" \
    -f "$root/scripts/evaluation/$journal" >/dev/null
if [[ $task != large-file-edit ]]; then
    red=includes_capacity stable=preserves_saturation
    if [[ $task == read-index-select-edit ]]; then red=retry_delay_is_capped_exponential stable=preserves_other_symbols; fi
    [[ $(cat "$evidence/tests-before.exit") == 101 && $(cat "$evidence/tests-after.exit") == 0 ]]
    grep -Fx "test $red ... FAILED" "$evidence/tests-before.log" >/dev/null
    grep -Fx "test $stable ... ok" "$evidence/tests-before.log" >/dev/null
    grep -Fx "test $red ... ok" "$evidence/tests-after.log" >/dev/null
    grep -F 'test result: ok. 3 passed; 0 failed;' "$evidence/tests-after.log" >/dev/null
    tested=$(sha256sum < "$scratch/work/src/lib.rs"); tested=${tested%% *}
    [[ $(cat "$evidence/tested-source.sha256") == "$tested  src/lib.rs" ]]
    cmp "$scratch/expected.rs" "$scratch/work/src/lib.rs" >&2
    first=true
else
    cmp "$scratch/expected.rs" "$scratch/work/src/lib.rs" >&2
    jq -e '(.result[2].raw|fromjson|.entry.result.output|contains("TAIL_SENTINEL")|not)' "$evidence/replay.json" >/dev/null
    first=true
    tail -n1 "$scratch/work/src/lib.rs" | grep -Fx 'pub const TAIL_SENTINEL: &str = "END-OF-COMPLETE-FIXTURE";' >/dev/null
fi
cmp "$scratch/expected.rs" "$scratch/work/src/lib.rs" >&2
(cd "$scratch/input" && find . -type f | LC_ALL=C sort) > "$scratch/before-files"
(cd "$scratch/work" && find . -type f | LC_ALL=C sort) > "$scratch/after-files"
cmp "$scratch/before-files" "$scratch/after-files" >&2
while IFS= read -r file; do
    [[ $file == ./src/lib.rs ]] || cmp "$scratch/input/$file" "$scratch/work/$file" >&2
done < "$scratch/before-files"
second=true
