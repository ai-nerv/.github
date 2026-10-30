#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 3 && $2 =~ ^[0-9a-f]{64}$ && ( $3 == baseline || $3 == candidate ) ]] || exit 2
descriptor=$1 artifact_sha=$2 variant=$3
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/child-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" --arg artifact "$artifact_sha" --arg variant "$variant" \
        '{schema:1,scope:"evaluation-child-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,
          checks:$passed,artifact_sha256:$artifact,variant:$variant,live_requests:0}' > "$report/summary.json"
    printf 'Evaluation child test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fixture="$report/fixture"
mkdir -p "$fixture"
cp -R "$root/scripts/evaluation/fixtures/child-work/." "$fixture/"
cp "$root/scripts/evaluation/family-common.sh" "$fixture/family-common.sh"
cp "$root/scripts/evaluation/child-workload.sh" "$fixture/driver.sh"
provider=melchior/target/release/examples/fake-provider
sha=$(sha256sum < "$root/$provider"); sha=${sha%% *}
code=0
bash "$root/scripts/evaluation/world.sh" "$root" "${fixture#"$root/"}" 60000 \
    --provider "$provider" "$sha" \
    --artifact "$descriptor" scripts/evaluation/manifests/offline.json "$variant" "$artifact_sha" \
    /runner/bin/bash /input/driver.sh > "$report/world.out" 2> "$report/world.err" || code=$?
world=$(sed -n 's/^Evaluation world evidence: //p' "$report/world.out")
[[ -n $world && $code == 0 ]]
bash "$root/scripts/evaluation/score-child.sh" "$world/input" "$world/receipt" > "$report/checks.json" 2> "$report/checks.err"
jq -e --arg sha "$artifact_sha" '.status=="WORLD_COMPLETED" and .artifact_sha256==$sha' "$world/summary.json" >/dev/null
(cd "$world/receipt/evidence" && sha256sum -c config.sha256) > "$report/config-integrity.log"
passed=$((passed+1))
for mode in blind-allowed stale-allowed wrong-child-read wrong-parent-read wrong-spawn wrong-child-prompt wrong-owner wrong-session wrong-revision wrong-digest missing-report missing-delivery wrong-sender \
    undercharge omit-child doublecharge wrong-usage provider-cost wrong-agent wrong-pid child-cross-history parent-request-prompt child-request-prompt orphan-result changed-result missing-barrier early-response extra-request incomplete wrong-session-log wrong-agent-log missing-trace extra-dispatch leak reverted parent-overwrite mutation symlink hardlink; do
    corrupt="$report/corrupt-$mode"
    cp -R "$world/receipt" "$corrupt"
    case $mode in
        blind-allowed) jq '.result[2].raw|=(fromjson|.entry.result.is_error=false|tojson)' "$world/receipt/evidence/replay-child.json" > "$corrupt/evidence/replay-child.json" ;;
        stale-allowed) jq '(.result[].raw)|=(fromjson|if .entry.id=="parent-stale" then .entry.result.is_error=false else . end|tojson)' "$world/receipt/evidence/replay-parent.json" > "$corrupt/evidence/replay-parent.json" ;;
        wrong-child-read) jq '.result[4].raw|=(fromjson|.entry.result.output="parent=old\nchild=new\ntail=unchanged"|tojson)' "$world/receipt/evidence/replay-child.json" > "$corrupt/evidence/replay-child.json" ;;
        wrong-parent-read) jq '(.result[].raw)|=(fromjson|if .entry.id=="parent-verify" then .entry.result.output="old result" else . end|tojson)' "$world/receipt/evidence/replay-parent.json" > "$corrupt/evidence/replay-parent.json" ;;
        wrong-spawn) jq '(.result[].raw)|=(fromjson|if .entry.id=="start-child" then .entry.args|=(fromjson|.delegate=true|tojson) else . end|tojson)' "$world/receipt/evidence/replay-parent.json" > "$corrupt/evidence/replay-parent.json" ;;
        wrong-child-prompt) jq '.result[0].raw|=(fromjson|.entry.text="inherited parent prompt"|tojson)' "$world/receipt/evidence/replay-child.json" > "$corrupt/evidence/replay-child.json" ;;
        wrong-owner) jq '.parent="unrelated-owner"' "$world/receipt/evidence/report.json" > "$corrupt/evidence/report.json" ;;
        wrong-session) jq '.session="unrelated-run"' "$world/receipt/evidence/report.json" > "$corrupt/evidence/report.json" ;;
        wrong-revision) jq '.revision=("0"*64)' "$world/receipt/evidence/report.json" > "$corrupt/evidence/report.json" ;;
        wrong-digest) jq '.digest=("0"*64)' "$world/receipt/evidence/report.json" > "$corrupt/evidence/report.json" ;;
        missing-report) rm "$corrupt/evidence/report.json" ;;
        missing-delivery) jq '(.result[].raw)|=(fromjson|if .entry.sort=="report_body" then .entry.text="missing report body" else . end|tojson)' "$world/receipt/evidence/replay-parent.json" > "$corrupt/evidence/replay-parent.json" ;;
        wrong-sender) jq '(.result[].raw)|=(fromjson|if .entry.sort=="report_body" then .entry.who="work/worker/unrelated" else . end|tojson)' "$world/receipt/evidence/replay-parent.json" > "$corrupt/evidence/replay-parent.json" ;;
        undercharge) printf '0\n' > "$corrupt/evidence/ledger.txt" ;;
        omit-child) total=$(cat "$world/receipt/evidence/ledger.txt"); printf '%s\n' "$((total-590))" > "$corrupt/evidence/ledger.txt" ;;
        doublecharge) total=$(cat "$world/receipt/evidence/ledger.txt"); printf '%s\n' "$((total+590))" > "$corrupt/evidence/ledger.txt" ;;
        wrong-usage) jq '.result[1].raw|=(fromjson|.entry.usage.input=0|tojson)' "$world/receipt/evidence/replay-child.json" > "$corrupt/evidence/replay-child.json" ;;
        provider-cost) jq '.result[1].raw|=(fromjson|.entry.usage.cost_micros=1|tojson)' "$world/receipt/evidence/replay-child.json" > "$corrupt/evidence/replay-child.json" ;;
        wrong-agent) jq '.child="unrelated-agent"' "$world/receipt/evidence/identities.json" > "$corrupt/evidence/identities.json" ;;
        wrong-pid) jq '.child_pid=99999' "$world/receipt/evidence/identities.json" > "$corrupt/evidence/identities.json" ;;
        child-cross-history) jq -c 'if any(.messages[]; .role=="system" and (.content|contains("# Working as a subagent"))) then .messages+=[{role:"user",content:"PARENT_WORK: inherited history"}] else . end' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        parent-request-prompt) jq -c '.messages|=map(if .role=="user" and (.content|startswith("PARENT_WORK:")) then .content="wrong parent task" else . end)' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        child-request-prompt) jq -c '.messages|=map(if .role=="user" and (.content|startswith("CHILD_WORK:")) then .content="wrong child task" else . end)' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        orphan-result) jq -c '.messages|=map(if .role=="assistant" then del(.tool_calls) else . end)' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        changed-result) jq -c '.messages|=map(if .role=="tool" and .tool_call_id=="child-blind" then .content="no error" else . end)' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        missing-barrier) jq -c 'select(.event|startswith("rendezvous_")|not)' "$world/receipt/evidence/meter.jsonl" > "$corrupt/evidence/meter.jsonl" ;;
        early-response) jq -sc '[.[]|select(.event=="response" and (.turn==4 or .turn==7))] as $early|map(select(.event!="response" or (.turn!=4 and .turn!=7)))|.[0:1]+$early+.[1:]|.[]' "$world/receipt/evidence/meter.jsonl" > "$corrupt/evidence/meter.jsonl" ;;
        extra-request) jq -sc '.+.[-1:]|.[]' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        incomplete) jq -c 'if .event=="terminal" then .incomplete=1 else . end' "$world/receipt/evidence/meter.jsonl" > "$corrupt/evidence/meter.jsonl" ;;
        missing-trace) : > "$corrupt/evidence/family.log" ;;
        wrong-session-log) sed -E 's/(session: )[^ ]+/\1r/' "$world/receipt/evidence/family.log" > "$corrupt/evidence/family.log" ;;
        wrong-agent-log) sed -E 's/(as agent )[^ ]+/\1unrelated-agent/' "$world/receipt/evidence/family.log" > "$corrupt/evidence/family.log" ;;
        extra-dispatch) grep -E 'casper\[[0-9]+\] run: edit ' "$world/receipt/evidence/family.log" >> "$corrupt/evidence/family.log" ;;
        leak) jq '.leaked_processes=3' "$world/receipt/inside.json" > "$corrupt/inside.json" ;;
        reverted) cp "$world/input/work/shared.txt" "$corrupt/work/work/shared.txt" ;;
        parent-overwrite) sed 's/parent=old/parent=new/' "$world/receipt/work/work/shared.txt" > "$corrupt/work/work/shared.txt" ;;
        mutation) printf 'changed\n' >> "$corrupt/work/work/stable.txt" ;;
        symlink) rm "$corrupt/work/work/stable.txt"; ln -s "$world/receipt/work/work/stable.txt" "$corrupt/work/work/stable.txt" ;;
        hardlink) ln "$corrupt/work/work/stable.txt" "$corrupt/work/work/alias.txt" ;;
    esac
    if bash "$root/scripts/evaluation/score-child.sh" "$world/input" "$corrupt" > "$report/$mode.json" 2> "$report/$mode.err"; then
        echo "accepted corrupted child evidence: $mode" >&2; exit 1
    fi
    jq -e '.status=="FAIL" and all(.checks[]; .status=="FAIL")' "$report/$mode.json" >/dev/null
    passed=$((passed+1))
done
printf 'Evaluation child checks passed: %s\n' "$passed"
