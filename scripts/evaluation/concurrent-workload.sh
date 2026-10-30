#!/usr/bin/env bash
set -euo pipefail
umask 077
source /input/family-common.sh
cd /world/work/work
start_provider 64
configure_family /world/work/work true
prompt=$(cat /input/prompt.txt)
NERV_LOG="$EVAL_EVIDENCE/family-left.log" start_magi "$EVAL_EVIDENCE/left.stdout" "$EVAL_EVIDENCE/left.stderr" \
    --role left -p "$prompt EVAL_LANE_LEFT: assigned region left."
left=$magi_wait_pid
NERV_LOG="$EVAL_EVIDENCE/family-right.log" start_magi "$EVAL_EVIDENCE/right.stdout" "$EVAL_EVIDENCE/right.stderr" \
    --role right -p "$prompt EVAL_LANE_RIGHT: assigned region right."
right=$magi_wait_pid
left_code=0 right_code=0
wait_magi "$left" || left_code=$?
wait_magi "$right" || right_code=$?
printf '%s\n' "$left_code" > "$EVAL_EVIDENCE/left.exit"
printf '%s\n' "$right_code" > "$EVAL_EVIDENCE/right.exit"
stop_provider
[[ $left_code == 0 && $right_code == 0 ]]
balthasar sessions --tool magi --json > "$EVAL_EVIDENCE/sessions.json" 2> "$EVAL_EVIDENCE/sessions.stderr"
jq -e '.ok and .n==2 and (.result|length)==2' "$EVAL_EVIDENCE/sessions.json" >/dev/null
for index in 0 1; do
    session=$(jq -er --argjson i "$index" '.result[$i].id' "$EVAL_EVIDENCE/sessions.json")
    balthasar replay --tool magi "$session" --json > "$EVAL_EVIDENCE/replay-$index.json" 2> "$EVAL_EVIDENCE/replay-$index.stderr"
done
