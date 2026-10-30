#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 3 && $2 =~ ^[0-9a-f]{64}$ && ( $3 == baseline || $3 == candidate ) ]] || exit 2
descriptor=$1 artifact_sha=$2 variant=$3
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/pressure-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" --arg artifact "$artifact_sha" --arg variant "$variant" \
        '{schema:1,scope:"evaluation-pressure-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,
          checks:$passed,artifact_sha256:$artifact,variant:$variant,live_requests:0}' > "$report/summary.json"
    printf 'Evaluation pressure test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fixture="$report/fixture"
mkdir -p "$fixture"
cp -R "$root/scripts/evaluation/fixtures/input-pressure/." "$fixture/"
cp "$root/scripts/evaluation/family-common.sh" "$fixture/family-common.sh"
cp "$root/scripts/evaluation/pressure-workload.sh" "$fixture/driver.sh"
provider=melchior/target/release/examples/fake-provider
sha=$(sha256sum < "$root/$provider"); sha=${sha%% *}
code=0
bash "$root/scripts/evaluation/world.sh" "$root" "${fixture#"$root/"}" 60000 \
    --provider "$provider" "$sha" \
    --artifact "$descriptor" scripts/evaluation/manifests/offline.json "$variant" "$artifact_sha" \
    /runner/bin/bash /input/driver.sh > "$report/world.out" 2> "$report/world.err" || code=$?
world=$(sed -n 's/^Evaluation world evidence: //p' "$report/world.out")
[[ -n $world && $code == 0 ]]
bash "$root/scripts/evaluation/score-pressure.sh" "$world/input" "$world/receipt" > "$report/checks.json" 2> "$report/checks.err"
jq -e --arg sha "$artifact_sha" '.status=="WORLD_COMPLETED" and .artifact_sha256==$sha' "$world/summary.json" >/dev/null
(cd "$world/receipt/evidence" && sha256sum -c config.sha256) > "$report/config-integrity.log"
passed=$((passed+1))
for mode in wrong-fact lost-failure lost-instruction orphan-result orphan-call reordered-pair wrong-arguments missing-journal wrong-usage wrong-budget unchanged-request fake-recovery corrupted-recovery wrong-helper phantom-usage changed-result wrong-window extra-request incomplete missing-trace missing-overflow extra-dispatch leak mutation symlink hardlink; do
    corrupt="$report/corrupt-$mode"
    cp -R "$world/receipt" "$corrupt"
    case $mode in
        wrong-fact) jq '.result[4].raw|=(fromjson|.entry.result.output="no fact"|tojson)' "$world/receipt/evidence/replay.json" > "$corrupt/evidence/replay.json" ;;
        lost-failure) jq -c '.messages|=map(if .role=="tool" and .tool_call_id=="pressure-0" then .content="lost diagnostic" else . end)' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        lost-instruction) jq -c '.messages|=map(select(.role!="user"))' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        orphan-result) jq -c '.messages|=map(if .role=="assistant" then del(.tool_calls) else . end)' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        orphan-call) jq -c '.messages|=map(select(.role!="tool"))' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        reordered-pair) jq -c '.messages|=reverse' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        wrong-arguments) jq -c '(.messages[]|select(.role=="assistant")|.tool_calls[]?|select(.id=="pressure-0")|.function.arguments)="{}"' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        missing-journal) jq '.result|=.[1:]' "$world/receipt/evidence/replay.json" > "$corrupt/evidence/replay.json" ;;
        wrong-usage) jq '.result[-1].raw|=(fromjson|.entry.usage.input=0|tojson)' "$world/receipt/evidence/replay.json" > "$corrupt/evidence/replay.json" ;;
        wrong-budget) jq -c 'if (.tools|length)>0 then .max_tokens=512 else . end' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        unchanged-request) jq -sc '[to_entries[]|select((.value.tools|length)>0)|.key] as $i|.[$i[5]]=.[$i[4]]|.[]' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        fake-recovery) jq -c '.messages|=map(if .role=="tool" and .tool_call_id=="recover-fact" then .content="WREN-7429" else . end)' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        corrupted-recovery)
            forged=$(jq -r '.result[11].raw|fromjson|.entry.result.output|fromjson|.turns[0].text+="changed tail"|tojson' "$world/receipt/evidence/replay.json")
            jq --arg forged "$forged" '.result[11].raw|=(fromjson|.entry.result.output=$forged|tojson)' "$world/receipt/evidence/replay.json" > "$corrupt/evidence/replay.json"
            jq -c --arg forged "$forged" '.messages|=map(if .role=="tool" and .tool_call_id=="recover-fact" then .content=$forged else . end)' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        wrong-helper) jq -c 'if (.tools|length)==0 then .messages[0].content="unknown helper" else . end' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        phantom-usage) jq '.result[9].raw|=(fromjson|.entry.usage.input=1|tojson)' "$world/receipt/evidence/replay.json" > "$corrupt/evidence/replay.json" ;;
        changed-result) jq -c '.messages|=map(if .role=="tool" and .tool_call_id=="pressure-2" then .content="changed source bytes" else . end)' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        wrong-window) sed 's/context_window = 32000/context_window = 200000/' "$world/receipt/evidence/config/4.lua" > "$corrupt/evidence/config/4.lua" ;;
        extra-request) jq -sc '.+.[-1:]|.[]' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        incomplete) jq -c 'if .event=="terminal" then .incomplete=1 else . end' "$world/receipt/evidence/meter.jsonl" > "$corrupt/evidence/meter.jsonl" ;;
        missing-trace) : > "$corrupt/evidence/family.log" ;;
        missing-overflow) sed '/verb: overflowed /d' "$world/receipt/evidence/family.log" > "$corrupt/evidence/family.log" ;;
        extra-dispatch) grep -E 'casper\[[0-9]+\] run: read ' "$world/receipt/evidence/family.log" >> "$corrupt/evidence/family.log" ;;
        leak) jq '.leaked_processes=1' "$world/receipt/inside.json" > "$corrupt/inside.json" ;;
        mutation) printf 'changed\n' >> "$corrupt/work/work/stable.txt" ;;
        symlink) rm "$corrupt/work/work/stable.txt"; ln -s "$world/receipt/work/work/stable.txt" "$corrupt/work/work/stable.txt" ;;
        hardlink) ln "$corrupt/work/work/stable.txt" "$corrupt/work/work/alias.txt" ;;
    esac
    if bash "$root/scripts/evaluation/score-pressure.sh" "$world/input" "$corrupt" > "$report/$mode.json" 2> "$report/$mode.err"; then
        echo "accepted corrupted pressure evidence: $mode" >&2; exit 1
    fi
    jq -e '.status=="FAIL" and all(.checks[]; .status=="FAIL")' "$report/$mode.json" >/dev/null
    passed=$((passed+1))
done
printf 'Evaluation pressure checks passed: %s\n' "$passed"
