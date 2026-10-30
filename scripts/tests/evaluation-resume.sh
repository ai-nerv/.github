#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ ( $# == 3 || $# == 5 ) && $2 =~ ^[0-9a-f]{64}$ && ( $3 == baseline || $3 == candidate ) ]] || exit 2
if [[ $# == 5 ]]; then [[ $3 == candidate && $5 =~ ^[0-9a-f]{64}$ ]]; fi
descriptor=$1 artifact_sha=$2 variant=$3
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/resume-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" --arg artifact "$artifact_sha" --arg variant "$variant" \
        '{schema:1,scope:"evaluation-resume-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,
          checks:$passed,artifact_sha256:$artifact,variant:$variant,live_requests:0}' > "$report/summary.json"
    printf 'Evaluation resume test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fixture="$report/fixture"
mkdir -p "$fixture"
cp -R "$root/scripts/evaluation/fixtures/resume/." "$fixture/"
cp "$root/scripts/evaluation/family-common.sh" "$fixture/family-common.sh"
cp "$root/scripts/evaluation/resume-workload.sh" "$fixture/driver.sh"
if [[ $# == 5 ]]; then
    "$root/target/evaluation/bin/eval-input" binary "$root" "$4" "$report/legacy" > "$report/legacy-counts.json"
    legacy_sha=$(sha256sum < "$report/legacy/input")
    [[ ${legacy_sha%% *} == "$5" ]]
    cp "$report/legacy/input" "$fixture/legacy-melchior"
    cp "$root/scripts/evaluation/resume-workload.sh" "$fixture/resume-workload.sh"
    cp "$root/scripts/evaluation/resume-legacy-workload.sh" "$fixture/driver.sh"
fi
provider=melchior/target/release/examples/fake-provider
sha=$(sha256sum < "$root/$provider"); sha=${sha%% *}
code=0
bash "$root/scripts/evaluation/world.sh" "$root" "${fixture#"$root/"}" 60000 \
    --provider "$provider" "$sha" \
    --artifact "$descriptor" scripts/evaluation/manifests/offline.json "$variant" "$artifact_sha" \
    /runner/bin/bash /input/driver.sh > "$report/world.out" 2> "$report/world.err" || code=$?
world=$(sed -n 's/^Evaluation world evidence: //p' "$report/world.out")
[[ -n $world && $code == 0 ]]
bash "$root/scripts/evaluation/score-resume.sh" "$world/input" "$world/receipt" > "$report/checks.json" 2> "$report/checks.err"
jq -e --arg sha "$artifact_sha" '.status=="WORLD_COMPLETED" and .artifact_sha256==$sha' "$world/summary.json" >/dev/null
(cd "$world/receipt/evidence" && sha256sum -c config.sha256) > "$report/config-integrity.log"
passed=$((passed+1))
if [[ $# == 5 ]]; then
    jq -se 'all(.[0:2][]; (.coordination_run|split("-")|last|length)<=20) and
        all(.[2:4][]; (.coordination_run|split("-")|last|length)==39) and
        .[2].transcript==.[1].transcript and .[3].transcript==.[0].transcript' \
        "$world/receipt/evidence/phases.jsonl" >/dev/null
    actual=$(sha256sum < "$world/input/legacy-melchior")
    [[ ${actual%% *} == "$5" ]]
    passed=$((passed+1))
fi
for mode in wrong-history changed-prefix replayed-tool missing-record wrong-prompt wrong-usage recount undercharge wrong-run reused-run wrong-agent wrong-session-log missing-session-log missing-ledger \
    wrong-model wrong-request-history extra-request incomplete missing-refusal wrong-rates missing-trace extra-dispatch leak reverted duplicate mutation symlink hardlink; do
    corrupt="$report/corrupt-$mode"
    cp -R "$world/receipt" "$corrupt"
    case $mode in
        wrong-history) cp "$corrupt/evidence/replay-latest.json" "$corrupt/evidence/replay-named.json" ;;
        changed-prefix) jq '.result[0].raw|=(fromjson|.entry.text="changed history"|tojson)' "$world/receipt/evidence/replay-named.json" > "$corrupt/evidence/replay-named.json" ;;
        replayed-tool) jq '.result+=.result[4:5]|.n+=1' "$world/receipt/evidence/replay-named.json" > "$corrupt/evidence/replay-named.json" ;;
        missing-record) jq '.result|=.[1:]' "$world/receipt/evidence/replay-initial.json" > "$corrupt/evidence/replay-initial.json" ;;
        wrong-prompt) jq '.result[2].raw|=(fromjson|.entry.text="different prompt"|tojson)' "$world/receipt/evidence/replay-latest.json" > "$corrupt/evidence/replay-latest.json" ;;
        wrong-usage) jq '.result[7].raw|=(fromjson|.entry.usage.input=0|tojson)' "$world/receipt/evidence/replay-named.json" > "$corrupt/evidence/replay-named.json" ;;
        recount) printf '464\n' > "$corrupt/evidence/ledger-named.txt" ;;
        undercharge) printf '0\n' > "$corrupt/evidence/ledger-latest.txt" ;;
        wrong-run) jq -sc '.[3].transcript=.[1].transcript|.[]' "$world/receipt/evidence/phases.jsonl" > "$corrupt/evidence/phases.jsonl" ;;
        reused-run) jq -sc '.[3].coordination_run=.[0].coordination_run|.[]' "$world/receipt/evidence/phases.jsonl" > "$corrupt/evidence/phases.jsonl" ;;
        wrong-agent) jq -sc '.[3].coordination_run="wrong-agent-1234567890"|.[]' "$world/receipt/evidence/phases.jsonl" > "$corrupt/evidence/phases.jsonl" ;;
        wrong-session-log) sed -E 's/(session: )[^ ]+/\1invented-run/' "$world/receipt/evidence/family.log" > "$corrupt/evidence/family.log" ;;
        missing-session-log) sed '/magi\[[0-9]*\] session: /d' "$world/receipt/evidence/family.log" > "$corrupt/evidence/family.log" ;;
        missing-ledger) rm "$corrupt/evidence/ledger-initial.txt" ;;
        wrong-model) jq -c '.model="wrong-model"' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        wrong-request-history) jq -sc '.[5].messages=.[4].messages|.[]' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        extra-request) jq -sc '.+.[-1:]|.[]' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        incomplete) jq -c 'if .event=="terminal" then .incomplete=1 else . end' "$world/receipt/evidence/meter.jsonl" > "$corrupt/evidence/meter.jsonl" ;;
        missing-refusal) printf '0\n' > "$corrupt/evidence/missing.exit" ;;
        wrong-rates) sed 's/input = 2/input = 0/' "$world/receipt/evidence/config/4.lua" > "$corrupt/evidence/config/4.lua" ;;
        missing-trace) : > "$corrupt/evidence/family.log" ;;
        extra-dispatch) grep -E 'casper\[[0-9]+\] run: edit ' "$world/receipt/evidence/family.log" >> "$corrupt/evidence/family.log" ;;
        leak) jq '.leaked_processes=1' "$world/receipt/inside.json" > "$corrupt/inside.json" ;;
        reverted) cp "$world/input/work/counter.txt" "$corrupt/work/work/counter.txt" ;;
        duplicate) sed 's/count=1/count=2/' "$world/receipt/work/work/counter.txt" > "$corrupt/work/work/counter.txt" ;;
        mutation) printf 'changed\n' >> "$corrupt/work/work/stable.txt" ;;
        symlink) rm "$corrupt/work/work/stable.txt"; ln -s "$world/receipt/work/work/stable.txt" "$corrupt/work/work/stable.txt" ;;
        hardlink) ln "$corrupt/work/work/stable.txt" "$corrupt/work/work/alias.txt" ;;
    esac
    if bash "$root/scripts/evaluation/score-resume.sh" "$world/input" "$corrupt" > "$report/$mode.json" 2> "$report/$mode.err"; then
        echo "accepted corrupted resume evidence: $mode" >&2; exit 1
    fi
    jq -e '.status=="FAIL" and all(.checks[]; .status=="FAIL")' "$report/$mode.json" >/dev/null
    passed=$((passed+1))
done
printf 'Evaluation resume checks passed: %s\n' "$passed"
