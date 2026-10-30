#!/usr/bin/env bash
set -euo pipefail
umask 077
source /input/family-common.sh
for path in /family/unexpected /opt/evaluation/bin/unexpected; do
    if touch "$path"; then echo 'family artifact is writable' >&2; exit 1; fi
done
eval-world-probe ancestors
start_provider 2
configure_family /world/work false
code=0
magi -p "read sample.rs and report" > "$EVAL_EVIDENCE/magi.stdout" 2> "$EVAL_EVIDENCE/magi.stderr" || code=$?
printf '%s\n' "$code" > "$EVAL_EVIDENCE/magi.exit"
stop_provider
[[ $code == 0 ]]
grep -q 'family-world-complete' "$EVAL_EVIDENCE/magi.stdout"
jq -se 'length==2 and any(.[1].messages[]; .role=="tool" and (.content|contains("pub fn answer() -> u8 { 42 }")))' \
    "$EVAL_EVIDENCE/requests.jsonl" >/dev/null
replay_family
jq -se '.[-1].status=="STOPPED" and .[-1].responses==2 and .[-1].admitted==2 and .[-1].incomplete==0' \
    "$EVAL_EVIDENCE/meter.jsonl" >/dev/null
