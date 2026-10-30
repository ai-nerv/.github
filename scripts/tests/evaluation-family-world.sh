#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 3 && $2 =~ ^[0-9a-f]{64}$ && ( $3 == baseline || $3 == candidate ) ]] || {
    echo 'usage: evaluation-family-world.sh DESCRIPTOR SHA256 baseline|candidate' >&2; exit 2;
}
descriptor=$1 artifact_sha=$2 variant=$3
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
mkdir -p "$root/target/evaluation"
report=$(mktemp -d "$root/target/evaluation/family-world-tests-XXXXXXXX")
mkdir "$report/fixture"
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" --arg artifact "$artifact_sha" --arg variant "$variant" \
        '{schema:1,scope:"evaluation-family-world-tests",status:(if $code==0 then "PASS" else "FAIL" end),
          exit_code:$code,checks:$passed,artifact_sha256:$artifact,variant:$variant,live_requests:0}' > "$report/summary.json"
    printf 'Evaluation family world test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
cp "$root/scripts/evaluation/family-smoke.sh" "$report/fixture/driver.sh"
cp "$root/scripts/evaluation/family-common.sh" "$report/fixture/family-common.sh"
printf 'pub fn answer() -> u8 { 42 }\n' > "$report/fixture/sample.rs"
cat > "$report/fixture/provider.json" <<'JSON'
[
  {"events":[{"tool_call":{"id":"call-1","name":"read","arguments":"{\"path\":\"sample.rs\"}"}},
             {"usage":{"input":10,"output":3}},{"finish":"tool_calls"}]},
  {"events":[{"text":"family-world-complete"},{"usage":{"input":20,"output":5}},{"finish":"stop"}]}
]
JSON
provider=melchior/target/release/examples/fake-provider
provider_sha=$(sha256sum < "$root/$provider"); provider_sha=${provider_sha%% *}
score() {
    jq -ne --slurpfile requests "$1/requests.jsonl" --slurpfile replay "$1/replay.json" \
        --slurpfile sessions "$1/sessions.json" --slurpfile meter "$1/meter.jsonl" \
        -f "$root/scripts/evaluation/family-smoke.jq"
}
for mode in success wrong-digest; do
    chosen=$artifact_sha
    [[ $mode != wrong-digest ]] || chosen=$(printf '%064d' 0)
    code=0
    bash "$root/scripts/evaluation/world.sh" "$root" "${report#"$root/"}/fixture" 60000 \
        --provider "$provider" "$provider_sha" \
        --artifact "$descriptor" scripts/evaluation/manifests/offline.json "$variant" "$chosen" \
        /runner/bin/bash /input/driver.sh > "$report/$mode.out" 2> "$report/$mode.err" || code=$?
    world=$(sed -n 's/^Evaluation world evidence: //p' "$report/$mode.out")
    [[ -n $world ]]
    if [[ $mode == wrong-digest ]]; then
        [[ $code == 1 ]]
        jq -e '.status=="FAIL" and .artifact_sha256==null' "$world/summary.json" >/dev/null
        [[ ! -e $world/receipt/outer.json && ! -e $world/receipt/inside.json ]]
    else
        [[ $code == 0 ]]
        jq -e --arg sha "$artifact_sha" --arg variant "$variant" \
            '.status=="WORLD_COMPLETED" and .artifact_sha256==$sha and .variant==$variant' "$world/summary.json" >/dev/null
        jq -e '.cleanup_confirmed and .timed_out==false' "$world/receipt/outer.json" >/dev/null
        jq -e '.leaked_processes==0 and .remaining_processes==0 and .exported' "$world/receipt/inside.json" >/dev/null
        evidence="$world/receipt/evidence"
        score "$evidence" > "$report/score.json"
        grep -Fx 'protected-supervisor-ok' "$world/receipt/worker.stdout" >/dev/null
        cmp "$report/fixture/sample.rs" "$world/receipt/work/sample.rs"
        (cd "$evidence" && sha256sum -c config.sha256) > "$report/config-integrity.log"
        sha256sum -c "$world/binaries.sha256" > "$report/binary-integrity.log"
    fi
    passed=$((passed+1))
done
files=(requests.jsonl replay.json replay.json replay.json replay.json sessions.json meter.jsonl meter.jsonl)
changes=(
    'if .messages then .messages|=map(if .role=="tool" then .content="read refused" else . end) else . end'
    '.result[2].raw|=(fromjson|.entry.result.is_error=true|tojson)'
    '.result[2].raw|=(fromjson|.entry.result.output="wrong file"|tojson)'
    '.result[3].raw|=(fromjson|.entry.usage.output=0|tojson)'
    '.result|=reverse'
    '.n=0|.result=[]'
    'if .event=="terminal" then .incomplete=1 else . end'
    'if .event=="terminal" then .status="FAIL" else . end'
)
mkdir "$report/corrupt"
for index in "${!changes[@]}"; do
    for file in requests.jsonl replay.json sessions.json meter.jsonl; do cp "$evidence/$file" "$report/corrupt/$file"; done
    jq -c "${changes[index]}" "$evidence/${files[index]}" > "$report/corrupt/${files[index]}"
    if score "$report/corrupt" > "$report/corrupt-$index.out" 2> "$report/corrupt-$index.err"; then
        echo "accepted corrupted family evidence: $index" >&2; exit 1
    fi
    passed=$((passed+1))
done
printf 'Evaluation family world checks passed: %s\n' "$passed"
