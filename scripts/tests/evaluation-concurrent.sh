#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 3 && $2 =~ ^[0-9a-f]{64}$ && ( $3 == baseline || $3 == candidate ) ]] || exit 2
descriptor=$1 artifact_sha=$2 variant=$3
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/concurrent-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" --arg artifact "$artifact_sha" --arg variant "$variant" \
        '{schema:1,scope:"evaluation-concurrent-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,
          checks:$passed,artifact_sha256:$artifact,variant:$variant,live_requests:0}' > "$report/summary.json"
    printf 'Evaluation concurrent test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
fixture="$report/fixture"
mkdir -p "$fixture"
cp -R "$root/scripts/evaluation/fixtures/concurrent-disjoint-edits/." "$fixture/"
cp "$root/scripts/evaluation/family-common.sh" "$fixture/family-common.sh"
cp "$root/scripts/evaluation/concurrent-workload.sh" "$fixture/driver.sh"
provider=melchior/target/release/examples/fake-provider
sha=$(sha256sum < "$root/$provider"); sha=${sha%% *}
code=0
bash "$root/scripts/evaluation/world.sh" "$root" "${fixture#"$root/"}" 60000 \
    --provider "$provider" "$sha" \
    --artifact "$descriptor" scripts/evaluation/manifests/offline.json "$variant" "$artifact_sha" \
    /runner/bin/bash /input/driver.sh > "$report/world.out" 2> "$report/world.err" || code=$?
world=$(sed -n 's/^Evaluation world evidence: //p' "$report/world.out")
[[ -n $world && $code == 0 ]]
bash "$root/scripts/evaluation/score-concurrent.sh" "$world/input" "$world/receipt" > "$report/checks.json" 2> "$report/checks.err"
jq -e --arg sha "$artifact_sha" '.status=="WORLD_COMPLETED" and .artifact_sha256==$sha' "$world/summary.json" >/dev/null
(cd "$world/receipt/evidence" && sha256sum -c config.sha256) > "$report/config-integrity.log"
passed=$((passed+1))
for mode in lost-update unrelated truncated duplicate-journal wrong-usage no-stale both-success neither-success \
    wrong-read wrong-prompt missing-barrier reversed-barrier early-response extra-request incomplete leak missing-trace symlink hardlink extra-file; do
    corrupt="$report/corrupt-$mode"
    cp -R "$world/receipt" "$corrupt"
    case $mode in
        lost-update) cp "$world/input/work/shared.txt" "$corrupt/work/work/shared.txt" ;;
        unrelated) printf 'changed\n' >> "$corrupt/work/work/stable.txt" ;;
        truncated) head -n2 "$world/receipt/work/work/shared.txt" > "$corrupt/work/work/shared.txt" ;;
        duplicate-journal) cp "$corrupt/evidence/replay-0.json" "$corrupt/evidence/replay-1.json" ;;
        wrong-usage) jq '.result[5].raw|=(fromjson|.entry.usage.output=0|tojson)' "$world/receipt/evidence/replay-0.json" > "$corrupt/evidence/replay-0.json" ;;
        no-stale|both-success|neither-success)
            for i in 0 1; do
                jq --arg mode "$mode" '.result[4].raw|=(fromjson|
                  if $mode=="no-stale" and .entry.result.is_error then .entry.result.output="unknown failure"
                  elif $mode=="both-success" then .entry.result.is_error=false
                  elif $mode=="neither-success" then .entry.result.is_error=true|.entry.result.output="stale"
                  else . end|tojson)' "$world/receipt/evidence/replay-$i.json" > "$corrupt/evidence/replay-$i.json"
            done ;;
        wrong-read) jq '.result[2].raw|=(fromjson|.entry.result.output="left=new\nright=old\ntail=unchanged"|tojson)' "$world/receipt/evidence/replay-0.json" > "$corrupt/evidence/replay-0.json" ;;
        wrong-prompt) jq '.result[0].raw|=(fromjson|.entry.text="other task"|tojson)' "$world/receipt/evidence/replay-0.json" > "$corrupt/evidence/replay-0.json" ;;
        missing-barrier) jq -c 'select(.event|startswith("rendezvous_")|not)' "$world/receipt/evidence/meter.jsonl" > "$corrupt/evidence/meter.jsonl" ;;
        reversed-barrier) jq -c 'if .event=="rendezvous_arrive" then .event="rendezvous_release" elif .event=="rendezvous_release" then .event="rendezvous_arrive" else . end' "$world/receipt/evidence/meter.jsonl" > "$corrupt/evidence/meter.jsonl" ;;
        early-response) jq -sc '
            ([.[]|select(.event=="rendezvous_release")][0]) as $release |
            ([.[]|select(.event=="response" and .attempt==$release.attempt)][0]) as $response |
            [.[]|select(.!=$response)] | .[:index($release)]+[$response]+.[index($release):] | .[]' \
            "$world/receipt/evidence/meter.jsonl" > "$corrupt/evidence/meter.jsonl" ;;
        extra-request) jq -sc '.+.[-1:]|.[]' "$world/receipt/evidence/requests.jsonl" > "$corrupt/evidence/requests.jsonl" ;;
        incomplete) jq -c 'if .event=="terminal" then .incomplete=1 else . end' "$world/receipt/evidence/meter.jsonl" > "$corrupt/evidence/meter.jsonl" ;;
        leak) jq '.leaked_processes=1' "$world/receipt/inside.json" > "$corrupt/inside.json" ;;
        missing-trace) : > "$corrupt/evidence/family-left.log" ;;
        symlink) rm "$corrupt/work/work/shared.txt"; ln -s "$world/receipt/work/work/shared.txt" "$corrupt/work/work/shared.txt" ;;
        hardlink) ln "$corrupt/work/work/stable.txt" "$corrupt/work/work/alias.txt" ;;
        extra-file) printf 'extra\n' > "$corrupt/work/work/extra.txt" ;;
    esac
    if bash "$root/scripts/evaluation/score-concurrent.sh" "$world/input" "$corrupt" > "$report/$mode.json" 2> "$report/$mode.err"; then
        echo "accepted corrupted concurrent evidence: $mode" >&2; exit 1
    fi
    jq -e '.status=="FAIL" and all(.checks[]; .status=="FAIL")' "$report/$mode.json" >/dev/null
    passed=$((passed+1))
done
printf 'Evaluation concurrent checks passed: %s\n' "$passed"
