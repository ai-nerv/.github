#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 3 && $2 =~ ^[0-9a-f]{64}$ && ( $3 == baseline || $3 == candidate ) ]] || exit 2
descriptor=$1 artifact_sha=$2 variant=$3
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/accounting-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" --arg artifact "$artifact_sha" --arg variant "$variant" \
        '{schema:1,scope:"evaluation-accounting-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,
          checks:$passed,artifact_sha256:$artifact,variant:$variant,live_requests:0}' > "$report/summary.json"
    printf 'Evaluation accounting test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fixture="$report/fixture"
mkdir -p "$fixture"
cp -R "$root/scripts/evaluation/fixtures/cache-accounting/." "$fixture/"
cp "$root/scripts/evaluation/family-common.sh" "$fixture/family-common.sh"
cp "$root/scripts/evaluation/accounting-workload.sh" "$fixture/driver.sh"
provider=melchior/target/release/examples/fake-provider
sha=$(sha256sum < "$root/$provider"); sha=${sha%% *}
code=0
bash "$root/scripts/evaluation/world.sh" "$root" "${fixture#"$root/"}" 60000 \
    --provider "$provider" "$sha" \
    --artifact "$descriptor" scripts/evaluation/manifests/offline.json "$variant" "$artifact_sha" \
    /runner/bin/bash /input/driver.sh > "$report/world.out" 2> "$report/world.err" || code=$?
world=$(sed -n 's/^Evaluation world evidence: //p' "$report/world.out")
[[ -n $world && $code == 0 ]]
bash "$root/scripts/evaluation/score-accounting.sh" "$world/input" "$world/receipt" > "$report/checks.json" 2> "$report/checks.err"
jq -e --arg sha "$artifact_sha" '.status=="WORLD_COMPLETED" and .artifact_sha256==$sha' "$world/summary.json" >/dev/null
(cd "$world/receipt/evidence" && sha256sum -c config.sha256) > "$report/config-integrity.log"
passed=$((passed+1))
for mode in undercharge overcharge duplicate-ledger missing-ledger cache-read cache-write inclusive-input provider-cost estimate dropped-provider-cost priced-provider-cost zero-cost-free wrong-run swapped-runs \
    missing-dialect wrong-model wrong-history wrong-prompt wrong-rates wrong-config wrong-session-log wrong-agent-log missing-trace extra-request incomplete leak mutation symlink hardlink; do
    corrupt="$report/corrupt-$mode"
    cp -R "$world/receipt" "$corrupt"
    case $mode in
        undercharge) printf '1\n' > "$corrupt/evidence/ledger-0.txt" ;;
        overcharge) printf '9999\n' > "$corrupt/evidence/ledger-0.txt" ;;
        duplicate-ledger) cp "$corrupt/evidence/ledger-0.txt" "$corrupt/evidence/ledger-1.txt" ;;
        missing-ledger) rm "$corrupt/evidence/ledger-0.txt" ;;
        dropped-provider-cost) jq '.result[3].raw|=(fromjson|.entry.usage.cost_micros=0|tojson)' "$world/receipt/evidence/replay-0.json" > "$corrupt/evidence/replay-0.json" ;;
        priced-provider-cost) jq '.result[3].raw|=(fromjson|.entry.usage.estimated_micros=136|tojson)' "$world/receipt/evidence/replay-0.json" > "$corrupt/evidence/replay-0.json" ;;
        zero-cost-free) jq '.result[5].raw|=(fromjson|.entry.usage.estimated_micros=0|tojson)' "$world/receipt/evidence/replay-0.json" > "$corrupt/evidence/replay-0.json" ;;
        wrong-run) jq '.chat="unknown-run"' "$world/receipt/evidence/ledger-runs.json" > "$corrupt/evidence/ledger-runs.json" ;;
        swapped-runs) jq '{chat:.anthropic,anthropic:.chat}' "$world/receipt/evidence/ledger-runs.json" > "$corrupt/evidence/ledger-runs.json" ;;
        cache-read|cache-write|inclusive-input|provider-cost|estimate)
            field=cache_read value=0
            case $mode in cache-write) field=cache_write;; inclusive-input) field=input value=120;; provider-cost) field=cost_micros value=200;; estimate) field=estimated_micros;; esac
            for i in 0 1; do
                jq --arg field "$field" --argjson value "$value" '.result[1].raw|=(fromjson|.entry.usage[$field]=$value|tojson)' \
                    "$world/receipt/evidence/replay-$i.json" > "$corrupt/evidence/replay-$i.json"
            done ;;
        missing-dialect) cp "$corrupt/evidence/replay-0.json" "$corrupt/evidence/replay-1.json" ;;
        wrong-model) jq -c '.model="chat-1"' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        wrong-history) jq -sc '.[1].messages|=map(select(.role!="tool"))|.[]' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        wrong-prompt) jq '.result[0].raw|=(fromjson|.entry.text="different task"|tojson)' "$world/receipt/evidence/replay-0.json" > "$corrupt/evidence/replay-0.json" ;;
        wrong-rates) sed 's/cache_read = 0.25/cache_read = 0/' "$world/receipt/evidence/config/4.lua" > "$corrupt/evidence/config/4.lua" ;;
        wrong-config) printf '\nmagi.model = "evaluation-chat/chat-1"\n' >> "$corrupt/evidence/config/anthropic-init.lua" ;;
        missing-trace) : > "$corrupt/evidence/family-chat.log" ;;
        wrong-session-log) sed -E 's/(session: )[^ ]+/\1r/' "$world/receipt/evidence/family-chat.log" > "$corrupt/evidence/family-chat.log" ;;
        wrong-agent-log) sed -E 's/(as agent )[^ ]+/\1unrelated-agent/' "$world/receipt/evidence/family-chat.log" > "$corrupt/evidence/family-chat.log" ;;
        extra-request) jq -sc '.+.[-1:]|.[]' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        incomplete) jq -c 'if .event=="terminal" then .incomplete=1 else . end' "$world/receipt/evidence/meter.jsonl" > "$corrupt/evidence/meter.jsonl" ;;
        leak) jq '.leaked_processes=1' "$world/receipt/inside.json" > "$corrupt/inside.json" ;;
        mutation) printf 'changed\n' >> "$corrupt/work/work/stable.txt" ;;
        symlink) rm "$corrupt/work/work/stable.txt"; ln -s "$world/receipt/work/work/stable.txt" "$corrupt/work/work/stable.txt" ;;
        hardlink) ln "$corrupt/work/work/stable.txt" "$corrupt/work/work/alias.txt" ;;
    esac
    if bash "$root/scripts/evaluation/score-accounting.sh" "$world/input" "$corrupt" > "$report/$mode.json" 2> "$report/$mode.err"; then
        echo "accepted corrupted accounting evidence: $mode" >&2; exit 1
    fi
    jq -e '.status=="FAIL" and all(.checks[]; .status=="FAIL")' "$report/$mode.json" >/dev/null
    passed=$((passed+1))
done
printf 'Evaluation accounting checks passed: %s\n' "$passed"
