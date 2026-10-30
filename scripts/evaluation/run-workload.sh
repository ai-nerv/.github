#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 4 && $2 =~ ^[0-9a-f]{64}$ && $3 =~ ^[a-z][a-z0-9-]{0,63}$ && ( $4 == baseline || $4 == candidate ) ]] || {
    echo 'usage: run-workload.sh FROZEN_BINDINGS BINDINGS_SHA TASK VARIANT' >&2; exit 2;
}
supervisor= interrupted=0
forward() {
    interrupted=$1
    if [[ -n $supervisor ]]; then kill -"$1" "$supervisor" 2>/dev/null || true; fi
}
trap 'forward 2' INT
trap 'forward 15' TERM
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
source "$root/scripts/preserve-binary.sh"
mkdir -p "$root/target/evaluation"
report=$(mktemp -d "$root/target/evaluation/execution-XXXXXXXX")
mkdir "$report/bin"
touch "$report/supervisor.sha256"
preserve_binary "$root/target/evaluation/bin/eval-world" "$report/bin/eval-world" "$report/supervisor.sha256" >/dev/null
printf 'Evaluation workload receipt: %s\n' "$report"
launcher=$BASHPID
[[ $interrupted == 0 ]] || exit "$((128+interrupted))"
"$report/bin/eval-world" control "$report" 60000 "$launcher" \
    bash "$root/scripts/evaluation/workload-body.sh" "$@" "$report" > "$report/supervisor.out" 2> "$report/supervisor.err" &
supervisor=$!
[[ $interrupted == 0 ]] || kill -"$interrupted" "$supervisor" 2>/dev/null || true
while :; do
    code=0; wait "$supervisor" || code=$?
    kill -0 "$supervisor" 2>/dev/null || break
done
supervisor=
if (( interrupted != 0 )); then code=$((128+interrupted)); fi
if ! verify_preserved_binaries "$report/supervisor.sha256" > "$report/supervisor-integrity.log" 2>&1; then code=1; fi
control=null
if jq -e '.schema==1 and .scope=="evaluation-controller" and (.elapsed_ms|type)=="number"' "$report/control.json" >/dev/null 2>&1; then
    control=$(cat "$report/control.json")
else code=1; fi
if [[ -f $report/summary.json ]]; then
    mv "$report/summary.json" "$report/body-summary.json"
else
    if (( code == 0 )); then code=1; fi
    jq -n --arg task "$3" --arg variant "$4" --arg binding "$2" \
        '{schema:1,scope:"evaluation-bound-workload",status:"FAIL",failure:"invalid_result",exit_code:1,
          task_id:$task,variant:$variant,bindings_sha256:$binding,runner_sha256:null,artifact_sha256:null,
          fixture_sha256:null,config_sha256:null,world_receipt:null,metrics_status:"NOT_MEASURED",live_requests:0}' > "$report/body-summary.json"
fi
jq --argjson code "$code" --argjson control "$control" --argjson interrupted "$interrupted" '
    .exit_code=$code | .elapsed_ms=$control.elapsed_ms | .control_receipt="control.json" |
    if $code==0 then . else .status="FAIL" | .failure=(
      if $interrupted!=0 or ($control.interrupted//0)!=0 then "interrupted"
      elif $control.timed_out then "prompt_timeout"
      elif $control.invalid_limit then "input_mismatch"
      elif $control!=null and ($control.cleanup_confirmed!=true or $control.leaked_processes>0) then "cleanup_failure"
      else .failure//"invalid_result" end) end' "$report/body-summary.json" > "$report/summary.json"
printf 'Evaluation bound workload: %s\n' "$report"
exit "$code"
