#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 3 && $2 =~ ^[0-9a-f]{64}$ && ( $3 == baseline || $3 == candidate ) ]] || {
    echo 'usage: evaluation-controls.sh DESCRIPTOR SHA256 baseline|candidate' >&2; exit 2;
}
descriptor=$1 artifact_sha=$2 variant=$3
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
mkdir -p "$root/target/evaluation"
report=$(mktemp -d "$root/target/evaluation/control-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" --arg artifact "$artifact_sha" --arg variant "$variant" \
        '{schema:1,scope:"evaluation-control-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,
          checks:$passed,artifact_sha256:$artifact,variant:$variant,live_requests:0}' > "$report/summary.json"
    printf 'Evaluation control test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
provider=melchior/target/release/examples/fake-provider
provider_sha=$(sha256sum < "$root/$provider"); provider_sha=${provider_sha%% *}
for task in repetitive-failure output-only-overflow; do
    fixture="$report/$task/fixture"
    mkdir -p "$fixture"
    cp -R "$root/scripts/evaluation/fixtures/$task/." "$fixture/"
    cp "$root/scripts/evaluation/family-common.sh" "$fixture/family-common.sh"
    cp "$root/scripts/evaluation/control-workload.sh" "$fixture/driver.sh"
    code=0
    bash "$root/scripts/evaluation/world.sh" "$root" "${fixture#"$root/"}" 60000 \
        --provider "$provider" "$provider_sha" \
        --artifact "$descriptor" scripts/evaluation/manifests/offline.json "$variant" "$artifact_sha" \
        /runner/bin/bash /input/driver.sh "$task" > "$report/$task/world.out" 2> "$report/$task/world.err" || code=$?
    world=$(sed -n 's/^Evaluation world evidence: //p' "$report/$task/world.out")
    [[ -n $world ]]
    score=0
    bash "$root/scripts/evaluation/score-control.sh" "$task" "$world/input" "$world/receipt" \
        > "$report/$task/checks.json" 2> "$report/$task/checks.err" || score=$?
    [[ $code == 0 && $score == 0 ]]
    jq -e --arg sha "$artifact_sha" '.status=="WORLD_COMPLETED" and .artifact_sha256==$sha' "$world/summary.json" >/dev/null
    (cd "$world/receipt/evidence" && sha256sum -c config.sha256) > "$report/$task/config-integrity.log"
    passed=$((passed+1))
    for mode in provider-count usage journal trace leak mutation symlink terminal incomplete changed-input extra-effect wrong-stage invalid-arguments wrong-budget; do
        corrupt="$report/$task/corrupt-$mode"
        cp -R "$world/receipt" "$corrupt"
        case $mode in
            provider-count) jq -sc '.+.[-1:]|.[]' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
            usage) jq '.result[1].raw|=(fromjson|.entry.usage.output=999|tojson)' "$world/receipt/evidence/replay.json" > "$corrupt/evidence/replay.json" ;;
            journal) jq '.result[1].raw|=(fromjson|.entry.type="tool"|tojson)' "$world/receipt/evidence/replay.json" > "$corrupt/evidence/replay.json" ;;
            trace) : > "$corrupt/evidence/family.log" ;;
            leak) jq '.leaked_processes=1' "$world/receipt/inside.json" > "$corrupt/inside.json" ;;
            mutation) printf 'changed\n' >> "$corrupt/work/work/stable.txt" ;;
            symlink)
                rm "$corrupt/work/work/stable.txt"
                ln -s "$world/receipt/work/work/stable.txt" "$corrupt/work/work/stable.txt" ;;
            terminal) jq '.result[-1].raw|=(fromjson|.entry.stop_reason="tool_use"|tojson)' "$world/receipt/evidence/replay.json" > "$corrupt/evidence/replay.json" ;;
            incomplete) jq -c 'if .event=="terminal" then .incomplete=1 else . end' "$world/receipt/evidence/meter.jsonl" > "$corrupt/evidence/meter.jsonl" ;;
            extra-effect)
                if [[ $task == repetitive-failure ]]; then
                    printf '2026-10-22T00:00:00Z casper[999] run: read with 1 argument jailed=true → failed in 1ms\n' >> "$corrupt/evidence/family.log"
                else
                    printf '2026-10-22T00:00:00Z balthasar[999] verb: job_done unexpected summary\n' >> "$corrupt/evidence/family.log"
                fi ;;
            wrong-stage)
                if [[ $task == repetitive-failure ]]; then
                    jq '.result[6].raw|=(fromjson|.entry.result.output="read ran again"|tojson)' "$world/receipt/evidence/replay.json" > "$corrupt/evidence/replay.json"
                else
                    sed 's/slots, 0 jobs/slots, 1 jobs/' "$world/receipt/evidence/family.log" > "$corrupt/evidence/family.log"
                fi ;;
            invalid-arguments)
                if [[ $task == repetitive-failure ]]; then
                    jq '.result[2].raw|=(fromjson|.entry.args="{}"|tojson)' "$world/receipt/evidence/replay.json" > "$corrupt/evidence/replay.json"
                else
                    jq -c '.+{__budget:{source:"automatic"}}' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl"
                fi ;;
            wrong-budget)
                if [[ $task == repetitive-failure ]]; then
                    jq '.result[-1].raw|=(fromjson|.entry.usage.output=1|tojson)' "$world/receipt/evidence/replay.json" > "$corrupt/evidence/replay.json"
                else
                    jq -sc '.[1].max_tokens=4096|.[]' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl"
                fi ;;
            changed-input)
                if [[ $task == repetitive-failure ]]; then
                    jq -c '.messages|=map(if .role=="tool" and .tool_call_id=="read-3" then .content="no repair guidance" else . end)' \
                        "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl"
                else
                    jq -sc '.[1].messages+=[{role:"user",content:"changed input"}]|.[]' \
                        "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl"
                fi ;;
        esac
        if bash "$root/scripts/evaluation/score-control.sh" "$task" "$world/input" "$corrupt" \
            > "$report/$task/$mode.json" 2> "$report/$task/$mode.err"; then
            echo "accepted corrupted $task evidence: $mode" >&2; exit 1
        fi
        jq -e '.status=="FAIL" and all(.checks[]; .status=="FAIL")' "$report/$task/$mode.json" >/dev/null
        passed=$((passed+1))
    done
done
printf 'Evaluation control checks passed: %s\n' "$passed"
