#!/usr/bin/env bash
set -euo pipefail
umask 077
source /input/family-common.sh
[[ $# == 1 && ( $1 == small-bug-fix || $1 == large-file-edit || $1 == read-index-select-edit ) ]]
task=$1
cd /world/work/work
if [[ $task == read-index-select-edit ]]; then
    [[ ${CASPER_GRAMMARS:-} == /opt/evaluation/grammars ]]
    sha256sum < /opt/evaluation/grammars/bin/rust > "$EVAL_EVIDENCE/rust-grammar.sha256"
    eval-world-probe ancestors
fi
if [[ $task != large-file-edit ]]; then
    red=includes_capacity stable=preserves_saturation
    if [[ $task == read-index-select-edit ]]; then red=retry_delay_is_capped_exponential stable=preserves_other_symbols; fi
    rustc --edition=2024 --test /input/checks.rs -o /tmp/checks-before > "$EVAL_EVIDENCE/compile-before.log" 2>&1
    before=0; /tmp/checks-before --test-threads=1 > "$EVAL_EVIDENCE/tests-before.log" 2>&1 || before=$?
    printf '%s\n' "$before" > "$EVAL_EVIDENCE/tests-before.exit"
    [[ $before == 101 ]]
    grep -Fx "test $red ... FAILED" "$EVAL_EVIDENCE/tests-before.log" >/dev/null
    grep -Fx "test $stable ... ok" "$EVAL_EVIDENCE/tests-before.log" >/dev/null
    rm /tmp/checks-before
fi
start_provider 64
configure_family /world/work/work true
code=0
NERV_LOG="$EVAL_EVIDENCE/family.log" run_magi "$EVAL_EVIDENCE/magi.stdout" "$EVAL_EVIDENCE/magi.stderr" -p "$(cat /input/prompt.txt)" || code=$?
printf '%s\n' "$code" > "$EVAL_EVIDENCE/magi.exit"
stop_provider
[[ $code == 0 ]]
replay_family
if [[ $task != large-file-edit ]]; then
    rustc --edition=2024 --test /input/checks.rs -o /tmp/checks-after > "$EVAL_EVIDENCE/compile-after.log" 2>&1
    after=0; /tmp/checks-after --test-threads=1 > "$EVAL_EVIDENCE/tests-after.log" 2>&1 || after=$?
    printf '%s\n' "$after" > "$EVAL_EVIDENCE/tests-after.exit"
    [[ $after == 0 ]]
    sha256sum src/lib.rs > "$EVAL_EVIDENCE/tested-source.sha256"
fi
