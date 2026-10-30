#!/usr/bin/env bash
set -euo pipefail
umask 077
source /input/family-common.sh
[[ $# == 1 && ( $1 == repetitive-failure || $1 == output-only-overflow ) ]]
task=$1
cd /world/work/work
start_provider 64
configure_family /world/work/work false
code=0
NERV_LOG="$EVAL_EVIDENCE/family.log" run_magi "$EVAL_EVIDENCE/magi.stdout" "$EVAL_EVIDENCE/magi.stderr" \
    -p "$(cat /input/prompt.txt)" || code=$?
printf '%s\n' "$code" > "$EVAL_EVIDENCE/magi.exit"
stop_provider
replay_family
if [[ $task == repetitive-failure ]]; then [[ $code == 1 ]]; else [[ $code == 0 ]]; fi
