#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 2 && $2 =~ ^[0-9a-f]{64}$ ]] || exit 2
descriptor=$1 artifact_sha=$2
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/ipc-helper-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" --arg artifact "$artifact_sha" \
      '{schema:1,scope:"evaluation-ipc-helper-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$passed,artifact_sha256:$artifact,live_requests:0}' > "$report/summary.json"
    printf 'Evaluation IPC helper test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
provider=melchior/target/release/examples/fake-provider
sha=$(sha256sum < "$root/$provider"); sha=${sha%% *}
for mode in pressure tool; do
    fixture="$report/$mode"
    mkdir -p "$fixture/work"
    if [[ $mode == pressure ]]; then
        cp -R "$root/scripts/evaluation/fixtures/input-pressure/." "$fixture/"
    else
        printf 'Run ipc_helper once, then finish.\n' > "$fixture/prompt.txt"
        cat > "$fixture/provider.json" <<'JSON'
[
 {"when":{"tools":0,"body":"IPC_TOOL_HELPER_ONLY"},"events":[{"text":"IPC_HELPER_ANSWER"},{"usage":{"input":17,"output":6,"cache_read":3,"cache_write":2}},{"finish":"stop"}]},
 {"events":[{"tool_call":{"id":"helper-probe","name":"ipc_helper","arguments":"{\"path\":\"/world/work/work\"}"}},{"usage":{"input":10,"output":3}},{"finish":"tool_calls"}]},
 {"events":[{"text":"IPC_TOOL_DONE"},{"usage":{"input":11,"output":4}},{"finish":"stop"}]}
]
JSON
    fi
    cp "$root/scripts/evaluation/family-common.sh" "$fixture/family-common.sh"
    cp "$root/scripts/evaluation/client-admission.lua" "$fixture/client-admission.lua"
    printf '\nmelchior.evaluation_providers = { evaluation = true }\n' > "$fixture/client-providers.lua"
    printf '64\n' > "$fixture/client-attempt-limit.txt"
    cp "$root/scripts/evaluation/ipc-helper-workload.sh" "$fixture/driver.sh"
    cp "$root/scripts/evaluation/ipc-recorder-melchior.sh" "$fixture/recorder-melchior.sh"
    cp "$root/scripts/evaluation/pack-model-ipc.sh" "$fixture/pack-model-ipc.sh"
    chmod 700 "$fixture/recorder-melchior.sh"
    bash "$root/scripts/evaluation/world.sh" "$root" "${fixture#"$root/"}" 60000 \
      --provider "$provider" "$sha" \
      --artifact "$descriptor" scripts/evaluation/manifests/offline.json baseline "$artifact_sha" \
      /runner/bin/bash /input/driver.sh "$mode" > "$report/$mode.out" 2> "$report/$mode.err"
    world=$(sed -n 's/^Evaluation world evidence: //p' "$report/$mode.out")
    evidence="$world/receipt/evidence"
    capture="$report/$mode-restored"
    jq -e '.status=="IPC_PACKED" and .archive_bytes<=9437184 and .complete_run==false' "$evidence/model-ipc-package.json" >/dev/null
    digest=$(sha256sum < "$evidence/model-ipc.tar"); digest=${digest%% *}
    [[ $digest == $(jq -r .archive_sha256 "$evidence/model-ipc-package.json") ]]
    [[ $(wc -c < "$evidence/model-ipc.tar") == $(jq -r .archive_bytes "$evidence/model-ipc-package.json") ]]
    mkdir "$capture"
    env -i LC_ALL=C "$(type -P tar)" -xf "$evidence/model-ipc.tar" -C "$capture"
    passed=$((passed+1))
    jq -e '.status=="WORLD_COMPLETED"' "$world/summary.json" >/dev/null
    jq -e '.cleanup_confirmed and .timed_out==false' "$world/receipt/outer.json" >/dev/null
    jq -e '.leaked_processes==0 and .remaining_processes==0 and .streams_complete' "$world/receipt/inside.json" >/dev/null
    bash "$root/scripts/evaluation/client-attempts.sh" "$world/receipt" 64 > "$report/$mode-attempts.out" 2> "$report/$mode-attempts.err"
    attempts=$(sed -n 's/^Evaluation client attempts: //p' "$report/$mode-attempts.out")
    jq -e --slurpfile meter "$evidence/meter.jsonl" '.provider_attempts==$meter[-1].admitted and .provider_attempts>0' "$attempts/result.json" >/dev/null
    jq -e '.capture_complete and .sealed and .calls>0 and .complete_run==false' "$capture/summary.json" >/dev/null
    passed=$((passed+4))
    matched=0
    for request in "$capture/"*-request.json; do
        prefix=${request%-request.json}
        jq -e '.transport_complete and .exit_code==0' "$prefix-receipt.json" >/dev/null
        if [[ $mode == pressure ]]; then
            if jq -e '.context.system|startswith("You keep the running summary")' "$request" >/dev/null; then
                jq -se '[.[]|select(.event=="spent")][-1].usage|.input==7 and .output==2' "$prefix-response.jsonl" >/dev/null
                matched=$((matched+1))
            fi
        elif jq -e '.context.system=="IPC_TOOL_HELPER_ONLY"' "$request" >/dev/null; then
            jq -se '[.[]|select(.event=="spent")][-1].usage|.input==17 and .output==6' "$prefix-response.jsonl" >/dev/null
            matched=$((matched+1))
        fi
    done
    [[ $matched -gt 0 ]]
    passed=$((passed+1))
    if [[ $mode == tool ]]; then
        [[ $matched == 1 ]]
        jq -e '[.result[]|.raw|fromjson|.entry|select(.type=="tool" and .name=="ipc_helper")]|length==1 and
            .[0].id=="helper-probe" and (.[0].args|fromjson)=={path:"/world/work/work"}' "$evidence/replay.json" >/dev/null
        grep -q 'IPC_TOOL_DONE' "$evidence/magi.stdout"
        jq -se 'any(.[];.messages|any(.[];.role=="tool" and (.content|contains("IPC_HELPER_ANSWER"))))' "$evidence/requests.jsonl" >/dev/null
        ! grep -q 'job_done' "$evidence/family.log"
    else
        grep -q 'WREN-7429' "$evidence/magi.stdout"
        grep -q 'job_done' "$evidence/family.log"
    fi
    (cd "$evidence" && sha256sum -c config.sha256) > "$report/$mode-config-integrity.log"
    passed=$((passed+1))
    bash "$root/scripts/evaluation/ipc-usage.sh" "$report" "$mode-restored" > "$report/$mode-usage.out" 2> "$report/$mode-usage.err"
    usage="$(sed -n 's/^Evaluation IPC usage: //p' "$report/$mode-usage.out")/result.json"
    if [[ $mode == tool ]]; then
        jq -e '.complete_run==false and .helper_attribution==null and (.calls|length)==3 and
            .totals.input_tokens==38 and .totals.output_tokens==13' "$usage" >/dev/null
    else
        jq -e '.complete_run==false and .helper_attribution==null and (.calls|length)==10 and
            .known_totals.input_tokens==79 and .known_totals.output_tokens==24 and
            .unknown_calls.input_tokens==1 and .totals.input_tokens==null' "$usage" >/dev/null
    fi
    passed=$((passed+1))
done
printf 'Evaluation IPC helper checks passed: %s\n' "$passed"
