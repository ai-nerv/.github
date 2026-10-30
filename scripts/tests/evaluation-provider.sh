#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
[[ $# -le 1 && ( ${1:-debug} == debug || ${1:-debug} == release ) ]] || {
    echo 'usage: evaluation-provider.sh [debug|release]' >&2; exit 2;
}
profile=${1:-debug}
provider_sha=
source "$root/scripts/preserve-binary.sh"
mkdir -p "$root/target/evaluation"
report=$(mktemp -d "$root/target/evaluation/provider-tests-XXXXXXXX")
mkdir "$report/bin" "$report/home"
passed=0
pid=
finish() {
    local code=$?
    trap - EXIT
    if [[ -n $pid ]]; then kill -TERM "$pid" 2>/dev/null || true; wait "$pid" 2>/dev/null || true; fi
    if [[ -s $report/binaries.sha256 ]] && ! verify_preserved_binaries "$report/binaries.sha256" > "$report/integrity.log" 2>&1; then code=1; fi
    jq -n --argjson code "$code" --argjson passed "$passed" --arg profile "$profile" --arg sha "$provider_sha" \
        '{schema:1,scope:"evaluation-provider-process-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$passed,live_requests:0,
          provider_profile:$profile,provider_sha256:(if $sha=="" then null else $sha end)}' > "$report/summary.json"
    printf 'Evaluation provider process evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
if [[ $profile == release ]]; then
    preserve_binary "$root/target/evaluation/bin/eval-input" "$report/bin/eval-input" "$report/binaries.sha256" > "$report/input-helper.sha256"
    "$report/bin/eval-input" build-binary "$root" melchior/target/release/examples/fake-provider "$report/provider-artifact" > "$report/provider-counts.json"
    binary="$report/provider-artifact/input"
    sha256sum "$binary" >> "$report/binaries.sha256"
    provider_sha=$(sha256sum < "$binary"); provider_sha=${provider_sha%% *}
    printf '%s\n' "$provider_sha" > "$report/helper.sha256"
else
    preserve_binary "$root/melchior/target/debug/examples/fake-provider" "$report/bin/fake-provider" "$report/binaries.sha256" > "$report/helper.sha256"
    binary="$report/bin/fake-provider"
    provider_sha=$(cat "$report/helper.sha256")
fi
curl=$(command -v curl)
cat > "$report/script.json" <<'JSON'
[{"when":{"body":"model"},"events":[{"text":"fixture-ok"},{"finish":"stop"}]}]
JSON
start() {
    label=$1; shift
    : > "$report/$label.out"
    : > "$report/$label.err"
    env -i PATH="$PATH" HOME="$report/home" "$binary" --script "$report/script.json" --port 0 "$@" > "$report/$label.out" 2> "$report/$label.err" &
    pid=$!
    for _ in {1..100}; do
        port=$(sed -n 's/^PORT=//p' "$report/$label.out")
        if [[ $port =~ ^[0-9]+$ ]]; then return; fi
        kill -0 "$pid" 2>/dev/null || { wait "$pid" || true; pid=; echo 'provider exited before readiness' >&2; return 1; }
        sleep 0.05
    done
    echo 'provider readiness timeout' >&2; return 1
}
request() {
    env -i PATH="$PATH" HOME="$report/home" "$curl" --silent --show-error --noproxy '*' --max-time 3 \
        -H 'Content-Type: application/json' --data "$2" -o "$report/$1.body" -w '%{http_code}' \
        "http://127.0.0.1:$port/chat/completions" > "$report/$1.code"
}
reap() {
    local code=0
    for _ in {1..100}; do
        if ! kill -0 "$pid" 2>/dev/null; then break; fi
        sleep 0.05
    done
    if kill -0 "$pid" 2>/dev/null; then echo 'provider termination timeout' >&2; return 1; fi
    wait "$pid" || code=$?
    pid=
    [[ $code == "$1" ]] || { echo "provider exit $code instead of $1" >&2; return 1; }
}
start bounded --record "$report/requests.jsonl" --attempt-limit 2 --meter "$report/meter.jsonl"
request lead '{"model":"lead","tools":[{}]}'
request child '{"model":"child","tools":[]}'
request excess '{"model":"retry","tools":[]}'
[[ $(cat "$report/lead.code") == 200 && $(cat "$report/child.code") == 200 && $(cat "$report/excess.code") == 429 ]]
jq -e '.error.type=="evaluation_attempt_limit"' "$report/excess.body" >/dev/null
reap 1
jq -se '.[-1] | .event=="terminal" and .status=="FAIL" and .reason=="attempt_limit" and .admitted==2 and .rejected==1 and .responses==2 and .incomplete==0 and .captured_bytes==.reserved_bytes' "$report/meter.jsonl" >/dev/null
jq -se '.[0]=={schema:2,scope:"offline-provider-admission",event:"start",limit:2,capture_limit_bytes:8388608,journal_limit_bytes:131072}' "$report/meter.jsonl" >/dev/null
[[ $(wc -l < "$report/requests.jsonl") == 2 && $(stat -c %a "$report/meter.jsonl") == 600 && $(stat -c %a "$report/requests.jsonl") == 600 ]]
passed=$((passed+1))
start stopped --record "$report/stopped-requests.jsonl" --attempt-limit 1 --meter "$report/stopped-meter.jsonl"
request stopped '{"model":"lead"}'
kill -TERM "$pid"
reap 0
jq -se '.[-1]=={event:"terminal",status:"STOPPED",reason:"stopped",admitted:1,rejected:0,responses:1,incomplete:0,reserved_bytes:17,captured_bytes:17}' "$report/stopped-meter.jsonl" >/dev/null
passed=$((passed+1))
start capture --record "$report/capture-requests.jsonl" --attempt-limit 3 --capture-limit 34 --meter "$report/capture-meter.jsonl"
for index in 1 2; do request "capture-$index" '{"model":"lead"}'; [[ $(cat "$report/capture-$index.code") == 200 ]]; done
request capture-excess '{"model":"lead"}'
[[ $(cat "$report/capture-excess.code") == 413 ]]
jq -e '.error.type=="evaluation_capture_limit"' "$report/capture-excess.body" >/dev/null
reap 1
jq -se '.[0].capture_limit_bytes==34 and .[-1].status=="FAIL" and .[-1].reason=="capture_limit" and .[-1].responses==2 and .[-1].incomplete==1 and .[-1].reserved_bytes==34 and .[-1].captured_bytes==34' "$report/capture-meter.jsonl" >/dev/null
printf '{"model":"lead"}\n{"model":"lead"}\n' > "$report/capture-expected.jsonl"
cmp "$report/capture-expected.jsonl" "$report/capture-requests.jsonl"
[[ $(wc -c < "$report/capture-meter.jsonl") -le 131072 ]]
passed=$((passed+1))
start partial --record "$report/partial-requests.jsonl" --attempt-limit 1 --meter "$report/partial-meter.jsonl"
exec {socket}<>"/dev/tcp/127.0.0.1/$port"
printf P >&"$socket"
for _ in {1..100}; do
    if jq -se 'any(.[]; .event=="admit")' "$report/partial-meter.jsonl" >/dev/null; then break; fi
    sleep 0.05
done
jq -se 'any(.[]; .event=="admit")' "$report/partial-meter.jsonl" >/dev/null
kill -TERM "$pid"
reap 1
exec {socket}>&-
jq -se '.[-1].status=="FAIL" and .[-1].admitted==1 and .[-1].incomplete==1' "$report/partial-meter.jsonl" >/dev/null
passed=$((passed+1))
printf 'legacy-prefix\n' > "$report/legacy-requests.jsonl"
start legacy --record "$report/legacy-requests.jsonl"
for index in {1..4}; do request "legacy-$index" '{"model":"lead"}'; [[ $(cat "$report/legacy-$index.code") == 200 ]]; done
kill -TERM "$pid"
reap 143
[[ $(wc -l < "$report/legacy-requests.jsonl") == 5 && $(head -n1 "$report/legacy-requests.jsonl") == legacy-prefix ]]
passed=$((passed+1))
refuse_flags() {
    local name=$1 code=0; shift
    env -i PATH="$PATH" HOME="$report/home" timeout --kill-after=1s 3s "$binary" --script "$report/script.json" "$@" > "$report/$name.out" 2> "$report/$name.err" || code=$?
    [[ $code != 0 && $code != 124 && $code != 137 ]]
    ! grep -q '^PORT=' "$report/$name.out"
    passed=$((passed+1))
}
refuse_flags typo --record "$report/unused" --attempt-limt 1 --meter "$report/unused-meter"
refuse_flags missing-record --attempt-limit 1 --meter "$report/unused-meter"
refuse_flags missing-meter --attempt-limit 1 --record "$report/unused"
refuse_flags too-large --attempt-limit 65 --record "$report/unused" --meter "$report/unused-meter"
refuse_flags duplicate --attempt-limit 1 --attempt-limit 2 --record "$report/unused" --meter "$report/unused-meter"
refuse_flags existing-record --attempt-limit 1 --record "$report/legacy-requests.jsonl" --meter "$report/unused-meter"
refuse_flags capture-without-bounded --capture-limit 1
refuse_flags capture-noncanonical --attempt-limit 1 --record "$report/unused" --meter "$report/unused-meter" --capture-limit 01
refuse_flags capture-too-large --attempt-limit 1 --record "$report/unused" --meter "$report/unused-meter" --capture-limit 8388609
[[ ! -e $report/unused && ! -e $report/unused-meter && $(head -n1 "$report/legacy-requests.jsonl") == legacy-prefix ]]
cat > "$report/script.json" <<'JSON'
[{"rendezvous":"pair"},{"rendezvous":"pair"}]
JSON
refuse_flags unbounded-rendezvous
cat > "$report/script.json" <<'JSON'
[{"rendezvous":"pair"}]
JSON
refuse_flags unmatched-rendezvous --attempt-limit 1 --record "$report/unused" --meter "$report/unused-meter"
[[ ! -e $report/unused && ! -e $report/unused-meter ]]
printf 'Evaluation provider process checks passed: %s\n' "$passed"
