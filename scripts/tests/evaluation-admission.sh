#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 3 && $2 =~ ^[0-9a-f]{64}$ && ( $3 == baseline || $3 == candidate ) ]] || exit 2
descriptor=$1 artifact_sha=$2 variant=$3
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/admission-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" --arg artifact "$artifact_sha" \
        '{schema:1,scope:"evaluation-client-admission-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,
          checks:$passed,artifact_sha256:$artifact,live_requests:0}' > "$report/summary.json"
    printf 'Evaluation client admission test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
provider=melchior/target/release/examples/fake-provider
provider_sha=$(sha256sum < "$root/$provider"); provider_sha=${provider_sha%% *}
for case_name in admitted limit missing callback-error callback-budget anthropic-admitted anthropic-limit anthropic-missing anthropic-callback-error anthropic-callback-budget; do
    mode=$case_name api=openai-completions
    if [[ $mode == anthropic-* ]]; then mode=${mode#anthropic-}; api=anthropic-messages; fi
    fixture="$report/$case_name"
    mkdir "$fixture"
    cp -R "$root/scripts/evaluation/fixtures/output-only-overflow/." "$fixture/"
    printf '%s\n' "$api" > "$fixture/api.txt"
    if [[ $api == anthropic-messages ]]; then
        jq '.[0].refuse={status:503,shape:"vllm",message:"temporary fixture failure"}|.[1].dialect="anthropic-messages"|.[1].usage={input:512,output:2}|.[1].events=[{text:"Recovered after transport retry."},{finish:"end_turn"}]' \
            "$root/scripts/evaluation/fixtures/output-only-overflow/provider.json" > "$fixture/provider.json"
    fi
    cp "$root/scripts/evaluation/family-common.sh" "$fixture/family-common.sh"
    cp "$root/scripts/evaluation/client-admission.lua" "$fixture/client-admission.lua"
    printf '\nmelchior.evaluation_providers = { evaluation = true }\n' > "$fixture/client-providers.lua"
    if [[ $mode != missing ]]; then printf '2\n' > "$fixture/client-attempt-limit.txt"; fi
    if [[ $mode == limit ]]; then printf '1\n' > "$fixture/client-attempt-limit.txt"; fi
    case $mode in
        callback-error) printf '\nmelchior.apis["%s"].endpoint = function() error("evaluation fault") end\n' "$api" >> "$fixture/client-admission.lua" ;;
        callback-budget) printf '\nmelchior.apis["%s"].endpoint = function() while true do end end\n' "$api" >> "$fixture/client-admission.lua" ;;
    esac
    cat > "$fixture/driver.sh" <<'SH'
set -euo pipefail
source /input/family-common.sh
cd /world/work/work
start_provider 64
configure_family /world/work/work false
if [[ $(cat /input/api.txt) == anthropic-messages ]]; then
    sed 's/openai-completions/anthropic-messages/g; s@/v1"@"@g' "$XDG_CONFIG_HOME/melchior/providers.lua" > /tmp/providers.lua
    cp /tmp/providers.lua "$XDG_CONFIG_HOME/melchior/providers.lua"
    cp /tmp/providers.lua "$EVAL_EVIDENCE/config/4.lua"
fi
cp "$XDG_CONFIG_HOME/melchior/apis.lua" "$EVAL_EVIDENCE/config/3.lua"
(cd "$EVAL_EVIDENCE" && sha256sum config/*.lua > config.sha256)
melchior models --json > "$EVAL_EVIDENCE/catalog.json"
jq -e '.ok and .n==1 and (.result|length)==1 and .result[0].provider=="evaluation" and .result[0].id=="evaluation/echo-1"' \
    "$EVAL_EVIDENCE/catalog.json" >/dev/null
code=0
NERV_LOG="$EVAL_EVIDENCE/family.log" magi -p "$(cat /input/prompt.txt)" > "$EVAL_EVIDENCE/magi.stdout" 2> "$EVAL_EVIDENCE/magi.stderr" || code=$?
printf '%s\n' "$code" > "$EVAL_EVIDENCE/magi.exit"
stop_provider
replay_family
SH
    code=0
    bash "$root/scripts/evaluation/world.sh" "$root" "${fixture#"$root/"}" 10000 \
        --provider "$provider" "$provider_sha" --artifact "$descriptor" scripts/evaluation/manifests/offline.json "$variant" "$artifact_sha" \
        /runner/bin/bash /input/driver.sh > "$report/$case_name.out" 2> "$report/$case_name.err" || code=$?
    world=$(sed -n 's/^Evaluation world evidence: //p' "$report/$case_name.out")
    jq -e '.cleanup_confirmed and .timed_out==false' "$world/receipt/outer.json" >/dev/null
    jq -e '.remaining_processes==0 and .exported' "$world/receipt/inside.json" >/dev/null
    if [[ $mode == admitted ]]; then
        [[ $code == 0 && $(cat "$world/receipt/evidence/magi.exit") == 0 ]]
        jq -se '.[-1].status=="STOPPED" and .[-1].admitted==2 and [ .[]|select(.event=="admit")|.attempt ]==[1,2]' "$world/receipt/client-attempts.jsonl" >/dev/null
        if [[ $api == openai-completions ]]; then
            bash "$root/scripts/evaluation/score-control.sh" output-only-overflow "$world/input" "$world/receipt" > "$report/checks.json" 2> "$report/checks.err"
        else
            jq -se 'length==2 and .[0]==.[1] and .[0].max_tokens==4096 and .[0].model=="echo-1"' "$world/receipt/evidence/requests.jsonl" >/dev/null
            jq -e '.ok and .n==2 and (.result[-1].raw|fromjson|.entry|.type=="assistant" and .stop_reason=="end_turn" and
              .error==null and .text=="Recovered after transport retry." and .usage.input==512 and .usage.output==2)' "$world/receipt/evidence/replay.json" >/dev/null
            jq -se '.[-1].status=="STOPPED" and .[-1].admitted==2 and .[-1].responses==2 and .[-1].incomplete==0' "$world/receipt/evidence/meter.jsonl" >/dev/null
        fi
    elif [[ $mode == limit ]]; then
        [[ $code != 0 ]]
        jq -e '.client_admission_failed' "$world/receipt/inside.json" >/dev/null
        jq -se '.[-1].status=="FAIL" and .[-1].admitted==1 and any(.[]; .event=="reject" and .reason=="attempt_limit")' "$world/receipt/client-attempts.jsonl" >/dev/null
        jq -se '[.[]|select(.event=="admit")]|length==1' "$world/receipt/evidence/meter.jsonl" >/dev/null
    else
        [[ $code == 0 && $(cat "$world/receipt/evidence/magi.exit") == 1 ]]
        jq -se '.[-1].status=="STOPPED" and .[-1].admitted==0' "$world/receipt/evidence/meter.jsonl" >/dev/null
        [[ ! -s $world/receipt/evidence/requests.jsonl ]]
        if [[ $mode != missing ]]; then
            jq -se '.[-1].status=="STOPPED" and .[-1].admitted==0' "$world/receipt/client-attempts.jsonl" >/dev/null
        fi
    fi
    passed=$((passed+1))
done
printf 'Evaluation client admission checks passed: %s\n' "$passed"
