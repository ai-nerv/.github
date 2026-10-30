#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
mkdir -p "$root/target/evaluation"
report=$(mktemp -d "$root/target/evaluation/schema-XXXXXXXX")
chmod 700 "$report"
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" \
        '{schema:1,scope:"evaluation-manifest-validator",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$passed}' > "$report/summary.json"
    printf 'Evaluation validator evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
validate() {
    jq -Rse --argjson safe_integers true -f "$root/scripts/evaluation/lexical.jq" "$1" >/dev/null && json "$1" &&
        jq -L "$root/scripts/evaluation" -e -f "$root/scripts/evaluation/manifest.jq" "$1" >/dev/null
}
json() {
    jq --raw-input --slurp -e -f "$root/scripts/evaluation/lexical.jq" "$1" >/dev/null &&
        jq --stream --slurp -e -f "$root/scripts/evaluation/json.jq" "$1" >/dev/null
}
cat > "$report/valid.json" <<'JSON'
{"schema":1,"id":"schema-fixture","kind":"offline","suite":"transaction","fixture_revision":1,
 "samples_per_variant":3,"warmups":0,"order":"alternating","startup":"fresh-world",
 "permissions_profile":"fixture-confined","expected_network":"local-fixtures-only","live_authorization":null,
 "limits":{"timeout_seconds":60,"max_provider_attempts":64,"fixture_bytes":16777216,"fixture_files":256},
 "tasks":[{"id":"concurrent-disjoint-edits","fixture":"fixtures/concurrent-disjoint-edits",
 "prompt_fixture":"fixtures/concurrent-disjoint-edits/prompt.txt","seed":1,"timeout_seconds":60,
 "max_provider_attempts":64,"requires_features":["file_transactions"],"checks":["both-edits-or-stale","no-lost-update"]}]}
JSON
validate "$report/valid.json"
passed=$((passed+1))
jq '.event_observer={schema:1,sha256:("a"*64),modes:{baseline:"drain",candidate:"stall"}}' "$report/valid.json" > "$report/observer.json"
validate "$report/observer.json"
passed=$((passed+1))
for change in '.event_observer=null' '.event_observer.schema=2' '.event_observer.extra=true' \
    '.event_observer.sha256="bad"' '.event_observer.sha256+=("\n")' \
    '.event_observer.modes.baseline="stall"' '.event_observer.modes.candidate="drain"' \
    '.event_observer.modes.extra="drain"' 'del(.event_observer.modes)'; do
    jq "$change" "$report/observer.json" > "$report/observer-invalid.json"
    if validate "$report/observer-invalid.json" > "$report/observer-invalid.out" 2> "$report/observer-invalid.err"; then
        echo "accepted invalid observer policy: $change" >&2; exit 1
    fi
    passed=$((passed+1))
done
changes=(
    '.schema=2' '.kind="live"' '.extra=true' 'del(.limits)' '.suite="unreviewed"' '.id="../escape"' '.id="valid\n"'
    '.fixture_revision=0' '.samples_per_variant=0' '.samples_per_variant=4' '.warmups=1'
    '.order="candidate-first"' '.startup="ambient"' '.permissions_profile="unrestricted"'
    '.expected_network="internet"' '.live_authorization={approved:true}' '.limits.timeout_seconds=61'
    '.limits.max_provider_attempts=65' '.limits.fixture_bytes=16777217' '.limits.fixture_files=257'
    '.limits.hidden=1' '.tasks=[]' '.tasks += .tasks' '.tasks[0].id="unknown"'
    '.tasks[0].fixture="/etc"' '.tasks[0].fixture="fixtures/../escape"'
    '.tasks[0].prompt_fixture="fixtures/concurrent-disjoint-edits/other.txt"'
    '.tasks[0].seed=-1' '.tasks[0].seed=1.5' '.tasks[0].seed=2147483648'
    '.tasks[0].timeout_seconds=0' '.tasks[0].timeout_seconds=61' '.tasks[0].timeout_seconds="60"'
    '.tasks[0].max_provider_attempts=0' '.tasks[0].max_provider_attempts=65'
    '.tasks[0].requires_features=[]' '.tasks[0].checks=[]' '.tasks[0].checks=["sh -c true"]'
    '.tasks[0].command="touch escaped"' '.tasks[0].checks += .tasks[0].checks'
)
for index in "${!changes[@]}"; do
    jq "${changes[index]}" "$report/valid.json" > "$report/invalid-$index.json"
    if validate "$report/invalid-$index.json" > "$report/invalid-$index.out" 2> "$report/invalid-$index.err"; then
        echo "accepted invalid manifest: ${changes[index]}" >&2; exit 1
    fi
    passed=$((passed+1))
done
invalid_json=('' '{' '{"a":1,"a":2}' '{"a":{"b":1},"a":{"c":2}}' '{"a":{},"a":[]}' '{} {}' '[] []' '{"a":NaN}' '{"a":Infinity}' '{"a":+1}' '{"a":01}' '{"a":1.}' '{"a":0x1}')
for index in "${!invalid_json[@]}"; do
    printf '%s\n' "${invalid_json[index]}" > "$report/json-$index.json"
    if json "$report/json-$index.json" > "$report/json-$index.out" 2> "$report/json-$index.err"; then
        echo "accepted invalid JSON stream $index" >&2; exit 1
    fi
    passed=$((passed+1))
done
for value in '{}' '[]' '{"a":[1,{"a":null},[],{}],"b":{"a":true}}' '{"a":"quoted \" escaped \\ slash \/ unicode \u00e9","b":-1.25e+2}'; do
    printf '%s\n' "$value" > "$report/positive-json.json"
    json "$report/positive-json.json"
    passed=$((passed+1))
done
printf 'Evaluation manifest checks passed: %s\n' "$passed"
full="$root/scripts/evaluation/manifests/offline.json"
validate "$full"
passed=$((passed+1))
for suite in full core transaction progress cache overflow resume child; do
    case "$suite" in
        full) ids='["small-bug-fix","read-index-select-edit","large-file-edit","concurrent-disjoint-edits","repetitive-failure","output-only-overflow","input-pressure","cache-accounting","resume","child-work"]' ;;
        core) ids='["small-bug-fix","read-index-select-edit","large-file-edit","cache-accounting"]' ;;
        transaction) ids='["concurrent-disjoint-edits"]' ;;
        progress) ids='["repetitive-failure"]' ;;
        cache) ids='["input-pressure","cache-accounting"]' ;;
        overflow) ids='["output-only-overflow"]' ;;
        resume) ids='["resume"]' ;;
        child) ids='["child-work"]' ;;
    esac
    jq --arg suite "$suite" --argjson ids "$ids" '.suite=$suite | .tasks |= map(select(.id as $id|$ids|index($id)))' "$full" > "$report/$suite.json"
    validate "$report/$suite.json"
    jq -L "$root/scripts/evaluation" -f "$root/scripts/evaluation/schedule.jq" "$report/$suite.json" > "$report/$suite-schedule.json"
    jq -e --argjson ids "$ids" '
      .samples as $rows | ($rows|length)==(($ids|length)*6) and
      ([$rows[].id]|unique|length)==($rows|length) and
      (all($rows[]; .seed==1 and (.sample|IN(1,2,3)) and (.variant|IN("baseline","candidate")))) and
      (all($ids[]; . as $id | [$rows[]|select(.task_id==$id)] |
        length==6 and (group_by(.variant)|all(.[]; length==3 and (map(.sample)|sort)==[1,2,3])))) and
      (all(range(0;($ids|length)); . as $task | all(range(0;3); . as $sample |
        [$rows[($task*6+$sample*2):($task*6+$sample*2+2)][].variant] ==
        (if (($task+$sample)%2)==0 then ["baseline","candidate"] else ["candidate","baseline"] end))))
    ' "$report/$suite-schedule.json" >/dev/null
    passed=$((passed+2))
done
jq '.tasks |= reverse' "$full" > "$report/reordered.json"
if validate "$report/reordered.json" > "$report/reordered.out" 2> "$report/reordered.err"; then
    echo 'accepted reordered task inventory' >&2; exit 1
fi
passed=$((passed+1))
for mutation in '"x" * 131073' 'reduce range(0;25) as $n (null; [.])' '[range(0;16385)]'; do
    jq -n "$mutation" > "$report/excessive.json"
    if json "$report/excessive.json" > "$report/excessive.out" 2> "$report/excessive.err"; then
        echo 'accepted excessive document' >&2; exit 1
    fi
    passed=$((passed+1))
done
printf 'Evaluation total schema/schedule checks passed: %s\n' "$passed"
world="$report/preflight-world"
mkdir -p "$world/scripts/evaluation" "$world/target/evaluation/bin"
cp "$root/scripts/preserve-binary.sh" "$world/scripts/"
cp "$root/scripts/evaluation/"{preflight.sh,json.jq,lexical.jq,manifest.jq,schedule.jq,contract.jq} "$world/scripts/evaluation/"
cp -r "$root/scripts/evaluation/manifests" "$world/scripts/evaluation/"
cp "$root/target/evaluation/bin/eval-input" "$world/target/evaluation/bin/"
while IFS= read -r fixture; do
    mkdir -p "$world/scripts/evaluation/$fixture"
    printf 'synthetic preflight fixture\n' > "$world/scripts/evaluation/$fixture/prompt.txt"
done < <(jq -r '.tasks[].fixture' "$full")
"$BASH" "$world/scripts/evaluation/preflight.sh" manifests/offline.json > "$report/preflight-positive.log"
preflight_report=$(find "$world/target/evaluation" -maxdepth 1 -name 'preflight-*' -type d)
jq -e '.status=="INPUTS_VALIDATED" and .workers_started==0 and .exit_code==0' "$preflight_report/summary.json" >/dev/null
sha256sum -c "$preflight_report/inputs.sha256" > "$report/preflight-integrity.log"
cmp "$preflight_report/manifest/input" "$full"
jq -e '.samples|length==60' "$preflight_report/schedule.json" >/dev/null
passed=$((passed+1))
rm "$world/scripts/evaluation/fixtures/child-work/prompt.txt"
ln -s "$full" "$world/scripts/evaluation/fixtures/child-work/prompt.txt"
if "$BASH" "$world/scripts/evaluation/preflight.sh" manifests/offline.json > "$report/preflight-link.out" 2> "$report/preflight-link.err"; then
    echo 'preflight accepted a linked last fixture' >&2; exit 1
fi
passed=$((passed+1))
for path in manifests/../manifest.jq manifests/missing.json /etc/passwd; do
    if "$BASH" "$world/scripts/evaluation/preflight.sh" "$path" > "$report/preflight-path.out" 2> "$report/preflight-path.err"; then
        echo 'preflight accepted unsafe or missing manifest' >&2; exit 1
    fi
    passed=$((passed+1))
done
printf 'Evaluation preflight checks passed: %s\n' "$passed"
