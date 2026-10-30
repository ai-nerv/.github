#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
mkdir -p "$root/target/evaluation"
report=$(mktemp -d "$root/target/evaluation/provider-world-tests-XXXXXXXX")
mkdir "$report/fixture"
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" \
        '{schema:1,scope:"evaluation-provider-world-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$passed,live_requests:0}' > "$report/summary.json"
    printf 'Evaluation provider world test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cat > "$report/fixture/provider.json" <<'JSON'
[{"when":{"body":"model"},"events":[{"text":"isolated-fixture-ok"},{"finish":"stop"}]}]
JSON
cat > "$report/fixture/driver.sh" <<'SH'
set -euo pipefail
mode=$1
capture=8388608
[[ $mode != capture ]] || capture=17
: > "$EVAL_EVIDENCE/provider.stdout"
: > "$EVAL_EVIDENCE/provider.stderr"
(
[[ $mode != delayed-start ]] || sleep 0.1
exec /runner/provider/input --script /input/provider.json --port 0 --attempt-limit 2 --capture-limit "$capture" \
    --record "$EVAL_EVIDENCE/requests.jsonl" --meter "$EVAL_EVIDENCE/meter.jsonl" \
    > "$EVAL_EVIDENCE/provider.stdout" 2> "$EVAL_EVIDENCE/provider.stderr"
) &
provider=$!
port=
for _ in {1..100}; do
    IFS= read -r line < "$EVAL_EVIDENCE/provider.stdout" || line=
    if [[ $line == PORT=* ]]; then port=${line#PORT=}; break; fi
    kill -0 "$provider"
    sleep 0.02
done
[[ $port =~ ^[0-9]+$ ]]
jq -se --argjson capture "$capture" '.[0]=={schema:2,scope:"offline-provider-admission",event:"start",limit:2,capture_limit_bytes:$capture,journal_limit_bytes:131072}' "$EVAL_EVIDENCE/meter.jsonl" >/dev/null
if [[ $mode == leak ]]; then exit 0; fi
request() {
    curl --silent --show-error --noproxy '*' --max-time 2 -H 'Content-Type: application/json' \
        --data '{"model":"lead"}' -o "$EVAL_EVIDENCE/response-$1.body" -w '%{http_code}' \
        "http://127.0.0.1:$port/chat/completions" > "$EVAL_EVIDENCE/response-$1.code"
}
request 1
[[ $(cat "$EVAL_EVIDENCE/response-1.code") == 200 ]]
grep -q 'isolated-fixture-ok' "$EVAL_EVIDENCE/response-1.body"
if [[ $mode == success || $mode == delayed-start ]]; then
    kill -TERM "$provider"
    wait "$provider"
    jq -se '.[-1].status=="STOPPED" and .[-1].responses==1 and .[-1].incomplete==0 and .[-1].captured_bytes==17' "$EVAL_EVIDENCE/meter.jsonl" >/dev/null
    exit 0
fi
request 2
if [[ $mode == attempts ]]; then
    [[ $(cat "$EVAL_EVIDENCE/response-2.code") == 200 ]]
    request 3
    [[ $(cat "$EVAL_EVIDENCE/response-3.code") == 429 ]]
    reason=attempt_limit
else
    [[ $mode == capture && $(cat "$EVAL_EVIDENCE/response-2.code") == 413 ]]
    reason=capture_limit
fi
code=0; wait "$provider" || code=$?
[[ $code == 1 ]]
jq -se --arg reason "$reason" '.[-1].status=="FAIL" and .[-1].reason==$reason' "$EVAL_EVIDENCE/meter.jsonl" >/dev/null
exit 1
SH
provider=melchior/target/release/examples/fake-provider
sha=$(sha256sum < "$root/$provider"); sha=${sha%% *}
for mode in success delayed-start attempts capture leak wrong-digest; do
    chosen=$sha
    [[ $mode != wrong-digest ]] || chosen=$(printf '%064d' 0)
    code=0
    bash "$root/scripts/evaluation/world.sh" "$root" "${report#"$root/"}/fixture" 10000 \
        --provider "$provider" "$chosen" /runner/bin/bash /input/driver.sh "$mode" \
        > "$report/$mode.out" 2> "$report/$mode.err" || code=$?
    world=$(sed -n 's/^Evaluation world evidence: //p' "$report/$mode.out")
    [[ -n $world ]]
    if [[ $mode == success || $mode == delayed-start ]]; then
        [[ $code == 0 ]]
        jq -e --arg sha "$sha" '.status=="WORLD_COMPLETED" and .provider_sha256==$sha' "$world/summary.json" >/dev/null
    else
        [[ $code == 1 ]]
        jq -e '.status=="FAIL"' "$world/summary.json" >/dev/null
    fi
    if [[ $mode == wrong-digest ]]; then
        jq -e '.provider_sha256==null' "$world/summary.json" >/dev/null
        [[ ! -e $world/receipt/outer.json && ! -e $world/receipt/inside.json ]]
    else
        jq -e '.cleanup_confirmed and .timed_out==false' "$world/receipt/outer.json" >/dev/null
        jq -e '.remaining_processes==0 and .exported' "$world/receipt/inside.json" >/dev/null
        if [[ $mode == leak ]]; then
            jq -e '.leaked_processes>0' "$world/receipt/inside.json" >/dev/null
        else
            jq -e '.leaked_processes==0' "$world/receipt/inside.json" >/dev/null
            jq -se '.[0].schema==2 and .[-1].event=="terminal"' "$world/receipt/evidence/meter.jsonl" >/dev/null
        fi
        sha256sum -c "$world/binaries.sha256" > "$report/$mode-integrity.log"
    fi
    passed=$((passed+1))
done
code=0
bash "$root/scripts/evaluation/world.sh" "$root" "${report#"$root/"}/fixture" 10000 \
    --provider '' "$sha" /runner/bin/true > "$report/empty-provider.out" 2> "$report/empty-provider.err" || code=$?
[[ $code == 2 ]]
! grep -q '^Evaluation world evidence:' "$report/empty-provider.out"
passed=$((passed+1))
printf 'Evaluation provider world checks passed: %s\n' "$passed"
