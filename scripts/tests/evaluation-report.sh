#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
mkdir -p "$root/target/evaluation"
report=$(mktemp -d "$root/target/evaluation/reports-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" \
        '{schema:1,scope:"evaluation-report-validator",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$passed}' > "$report/summary.json"
    printf 'Evaluation report-validator evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
manifest="$root/scripts/evaluation/manifests/offline.json"
manifest_sha=$(sha256sum < "$manifest"); manifest_sha=${manifest_sha%% *}
jq -L "$root/scripts/evaluation" -f "$root/scripts/evaluation/schedule.jq" "$manifest" > "$report/schedule.json"
jq -n --slurpfile m "$manifest" --slurpfile schedule "$report/schedule.json" --arg manifest_sha "$manifest_sha" '
  def models($id): if $id=="cache-accounting" then
    [{provider:"evaluation-anthropic",id:"anthropic-1",api:"anthropic-messages"},
     {provider:"evaluation-chat",id:"chat-1",api:"openai-completions"}]
    else [{provider:"evaluation",id:"echo-1",api:"openai-completions"}] end;
  {schema:2,kind:"offline",scope:"full",status:"PASS",manifest_sha256:$manifest_sha,runner_sha256:("a"*64),
   artifacts:{baseline:("b"*64),candidate:("c"*64)},collection_errors:[],timing_claim:"descriptive-only",live_requests:0,
   started_at:"2026-10-21T12:00:00Z",finished_at:"2026-10-21T12:01:00Z",
   tasks:[$m[0].tasks[]|{id,fixture_sha256:("d"*64),config_sha256:{baseline:("e"*64),candidate:("f"*64)},
     models:models(.id)}],
   samples:[$schedule[0].samples[] as $sample|($m[0].tasks[]|select(.id==$sample.task_id)) as $task|
     {schema:2,id:$sample.id,status:"PASS",failure:null,
      artifact_sha256:(if $sample.variant=="baseline" then "b"*64 else "c"*64 end),fixture_sha256:("d"*64),
      config_sha256:(if $sample.variant=="baseline" then "e"*64 else "f"*64 end),
      models:models($sample.task_id),elapsed_ms:100,exit_code:0,
      checks:[$task.checks[]|{id:.,status:"PASS",evidence_path:"checks.json"}],
      metrics:{logical_turns:1,provider_attempts:1,transport_retries:0,output_adjustments:0,
        tool_executions:1,guarded_calls:0,tool_failures:0,layout_jobs:1,summary_jobs:0,
        input_tokens:2,output_tokens:1,cache_read_tokens:0,cache_write_tokens:0,
        reported_micros:1,estimated_micros:2,charged_micros:3,request_bytes:100,stable_prefix_bytes:0},
      cleanup:{leaked_processes:0,remaining_processes:0},resources:{status:"NOT_MEASURED",peak_rss_bytes:null,cpu_ms:null},
      evidence:["requests.jsonl","events.jsonl","checks.json","cleanup.json"]|map({path:.,sha256:("1"*64)})}]}
' > "$report/valid.json"
jq '{schema,manifest_sha256,runner_sha256,artifacts,tasks}' "$report/valid.json" > "$report/bindings.json"
validate() {
    jq -Rse --argjson max_json_bytes 1048576 --argjson safe_integers true -f "$root/scripts/evaluation/lexical.jq" "$1" >/dev/null &&
        jq --stream --slurp -e -f "$root/scripts/evaluation/json.jq" "$1" >/dev/null &&
        jq -L "$root/scripts/evaluation" -e --slurpfile manifest "$manifest" --slurpfile bindings "$report/bindings.json" --arg manifest_sha256 "$manifest_sha" \
            -f "$root/scripts/evaluation/report.jq" "$1" >/dev/null
}
validate "$report/valid.json"
passed=$((passed+1))
changes=(
    '.schema=1' '.kind="live"' '.scope="core"' '.extra=true' '.live_requests=1'
    '.timing_claim="cost-saving"' '.manifest_sha256=("a"*64)' '.artifacts.baseline="wrong"'
    '.tasks=[]' '.tasks[0].fixture_sha256=("0"*64)' '.tasks[0].config_sha256.baseline=("0"*64)'
    '.tasks[0].models[0].id="changed"' '.tasks[0].extra=1' '.samples=[]' '.samples|=.[0:-1]'
    '.samples|=reverse' '.samples[1]=.samples[0]' '.samples[0].schema=1' '.samples[0].extra=1'
    '.samples[0].artifact_sha256=("c"*64)' '.samples[0].fixture_sha256=("a"*64)'
    '.samples[0].config_sha256=("f"*64)' '.samples[0].models[0].api="unknown"'
    '.runner_sha256=("0"*64)' 'del(.runner_sha256)'
    '.tasks[7].models|=reverse' '.samples[42].models|=reverse'
    '.samples[42].models|=.[0:1]' '.samples[42].models+=.samples[42].models'
    '.samples[0]|=. + {model:.models[0]}|del(.samples[0].models)'
    '.samples[0].elapsed_ms=null' '.samples[0].elapsed_ms=-1' '.samples[0].elapsed_ms=60001'
    '.samples[0].exit_code=1' '.samples[0].checks=[]' '.samples[0].checks[0].id="model-said-done"'
    '.samples[0].checks[0].status="FAIL"' '.samples[0].checks[0].evidence_path="missing.json"'
    '.samples[0].checks[0].status="NOT_RUN"|.samples[0].checks[0].evidence_path=null'
    '.samples[0].metrics.provider_attempts=65' '.samples[0].metrics.provider_attempts=0'
    '.samples[0].metrics.logical_turns=0' '.samples[0].metrics.input_tokens=null'
    '.samples[0].metrics.output_tokens=-1' '.samples[0].metrics.output_tokens=1.5'
    '.samples[0].metrics.output_tokens=9007199254740992' '.samples[0].metrics.transport_retries=1'
    '.samples[0].metrics.tool_failures=2' '.samples[0].metrics.charged_micros=2'
    '.samples[0].metrics.reported_micros=9007199254740991'
    '.samples[0].metrics.stable_prefix_bytes=101' '.samples[0].metrics.extra=0'
    '.samples[0].cleanup.leaked_processes=1' '.samples[0].cleanup.remaining_processes=1'
    '.samples[0].cleanup.leaked_processes=null' '.samples[0].resources.peak_rss_bytes=0'
    '.samples[0].resources.status="MEASURED"' '.samples[0].evidence=[]'
    '.samples[0].evidence[0].path="../outside"' '.samples[0].evidence[0].path="/absolute"'
    '.samples[0].evidence[0].sha256="bad"' '.samples[0].evidence += [.samples[0].evidence[0]]'
    '.samples[0].failure="check_failed"' '.samples[0].status="UNKNOWN"'
    '.samples[0].status="FAIL"|.samples[0].failure="check_failed"'
    '.samples[0].status="TIMEOUT"|.samples[0].failure="prompt_timeout"'
    '.samples[0].status="INTERRUPTED"|.samples[0].failure="interrupted"'
    '.finished_at="2026-10-21T11:00:00Z"' '.started_at="yesterday"'
    '.finished_at="2026-13-21T12:01:00Z"' '.finished_at="2026-02-31T12:01:00Z"'
    '.artifacts.baseline=("0"*64)|.samples|=map(if (.id|contains(":baseline:")) then .artifact_sha256=("0"*64) else . end)'
    '.tasks[0].fixture_sha256=("0"*64)|.samples|=map(if (.id|startswith("small-bug-fix:")) then .fixture_sha256=("0"*64) else . end)'
    '.collection_errors=[{kind:"unexpected_result",path:"raw/extra.json",sha256:("a"*64)}]'
    '.status="FAIL"|.collection_errors=[{kind:"ignored",path:"raw/extra.json",sha256:("a"*64)}]'
)
for index in "${!changes[@]}"; do
    jq "${changes[index]}" "$report/valid.json" > "$report/invalid-$index.json"
    if validate "$report/invalid-$index.json" > "$report/invalid-$index.out" 2> "$report/invalid-$index.err"; then
        echo "accepted invalid report: ${changes[index]}" >&2; exit 1
    fi
    passed=$((passed+1))
done
cp "$report/bindings.json" "$report/original-bindings.json"
model_changes=(
    '[]' '.[0]' '.+.' 'reverse' '.[0].api="unknown"'
    '.[0].provider="../provider"' '.[0].id=""' '.[0].extra=true'
    '[.[0],(.[0]+{api:"openai-completions"})]'
    '[range(0;17)|{provider:"evaluation",id:("model-"+tostring),api:"openai-completions"}]|sort_by(.id)'
)
for index in "${!model_changes[@]}"; do
    jq ".tasks[7].models |= (${model_changes[index]}) | .tasks[7].models as \$models |
        .samples|=map(if (.id|startswith(\"cache-accounting:\")) then .models=\$models else . end)" \
        "$report/valid.json" > "$report/models-$index.json"
    jq '{schema,manifest_sha256,runner_sha256,artifacts,tasks}' "$report/models-$index.json" > "$report/bindings.json"
    if validate "$report/models-$index.json" > "$report/models-$index.out" 2> "$report/models-$index.err"; then
        echo "accepted invalid model binding: ${model_changes[index]}" >&2; exit 1
    fi
    passed=$((passed+1))
done
for change in '.schema=1' 'del(.schema)' '.manifest_sha256=("0"*64)' 'del(.runner_sha256)' '.extra=1'; do
    jq "$change" "$report/original-bindings.json" > "$report/bindings.json"
    if validate "$report/valid.json" > "$report/binding.out" 2> "$report/binding.err"; then
        echo "accepted invalid frozen binding: $change" >&2; exit 1
    fi
    passed=$((passed+1))
done
cp "$report/original-bindings.json" "$report/bindings.json"
for failure in provider_failure check_failed attempt_limit cleanup_failure; do
    jq --arg failure "$failure" '.status="FAIL"|.samples[0].status="FAIL"|.samples[0].failure=$failure|
        .samples[0].metrics.provider_attempts=65|.samples[0].cleanup.leaked_processes=1' "$report/valid.json" > "$report/$failure.json"
    validate "$report/$failure.json"
    passed=$((passed+1))
done
jq '.status="FAIL"|.samples[0] |= (.status="NOT_RUN"|.failure="missing_result"|.elapsed_ms=null|.exit_code=null|
    .metrics |= map_values(null)|.checks |= map(.status="NOT_RUN"|.evidence_path=null)|.evidence=[]|
    .cleanup={leaked_processes:null,remaining_processes:null})' "$report/valid.json" > "$report/missing.json"
validate "$report/missing.json"
passed=$((passed+1))
jq '.samples[0].cleanup={leaked_processes:0,remaining_processes:0}' "$report/missing.json" > "$report/missing-cleanup.json"
if validate "$report/missing-cleanup.json" > "$report/missing-cleanup.out" 2> "$report/missing-cleanup.err"; then exit 1; fi
passed=$((passed+1))
jq '.samples[0].failure="not_run"' "$report/missing-cleanup.json" > "$report/not-run.json"
validate "$report/not-run.json"
passed=$((passed+1))
jq '.status="INTERRUPTED"|.samples[0].status="INTERRUPTED"|.samples[0].failure="interrupted"|.samples[0].exit_code=130' "$report/valid.json" > "$report/interrupted.json"
validate "$report/interrupted.json"
passed=$((passed+1))
jq '.status="FAIL"|.samples[0].status="TIMEOUT"|.samples[0].failure="prompt_timeout"|.samples[0].elapsed_ms=65000' "$report/valid.json" > "$report/timeout.json"
validate "$report/timeout.json"
passed=$((passed+1))
printf 'Evaluation report checks passed: %s\n' "$passed"
jq '.status="FAIL"|.collection_errors=[{kind:"unexpected_result",path:"raw/extra.json",sha256:("a"*64)}]' "$report/valid.json" > "$report/extra.json"
validate "$report/extra.json"
passed=$((passed+1))
printf 'Evaluation bound report checks passed: %s\n' "$passed"

for number in 9007199254740990.5 1.0 1e0 -0 9007199254740992; do
    sed "s/\"output_tokens\": 1,/\"output_tokens\": $number,/" "$report/valid.json" > "$report/raw-number.json"
    ! cmp -s "$report/valid.json" "$report/raw-number.json"
    if validate "$report/raw-number.json" > "$report/raw-number-$number.out" 2> "$report/raw-number-$number.err"; then
        echo "accepted noncanonical counter: $number" >&2; exit 1
    fi
    passed=$((passed+1))
done

bundle="$report/evidence-fixture"
mkdir -p "$bundle/samples" "$bundle/collection/raw"
cp "$manifest" "$bundle/manifest.json"
cp "$report/bindings.json" "$bundle/bindings.json"
printf '{"synthetic":true}\n' > "$report/evidence-content"
digest=$(sha256sum < "$report/evidence-content"); digest=${digest%% *}
jq --arg digest "$digest" '.samples[].evidence[].sha256=$digest' "$report/valid.json" > "$bundle/report.json"
jq -r '.samples[].id' "$bundle/report.json" > "$report/evidence-ids"
while read -r id; do
    mkdir "$bundle/samples/$id"
    for name in requests.jsonl events.jsonl checks.json cleanup.json; do
        cp "$report/evidence-content" "$bundle/samples/$id/$name"
    done
done < "$report/evidence-ids"
first=$(head -n1 "$report/evidence-ids")
evidence_check() {
    bash "$root/scripts/evaluation/evidence.sh" "$bundle" report.json manifest.json bindings.json
}
evidence_check > "$report/evidence-valid.out" 2> "$report/evidence-valid.err"
receipt=$(sed -n 's/^Evaluation evidence integrity: //p' "$report/evidence-valid.out")
jq -e '.status=="EVIDENCE_VALIDATED" and .evaluation_status=="PASS" and .verified_files==240 and .workers_started==0' "$receipt/summary.json" >/dev/null
passed=$((passed+1))
refuse_evidence() {
    if evidence_check > "$report/evidence-$1.out" 2> "$report/evidence-$1.err"; then
        echo "accepted invalid retained evidence: $1" >&2; exit 1
    fi
    local result
    result=$(sed -n 's/^Evaluation evidence integrity: //p' "$report/evidence-$1.out")
    jq -e '.status=="FAIL" and .evaluation_status=="UNKNOWN" and .workers_started==0' "$result/summary.json" >/dev/null
    passed=$((passed+1))
}
printf 'altered\n' > "$bundle/samples/$first/checks.json"
refuse_evidence changed
cp "$report/evidence-content" "$bundle/samples/$first/checks.json"
rm "$bundle/samples/$first/checks.json"
refuse_evidence missing
ln -s "$report/evidence-content" "$bundle/samples/$first/checks.json"
refuse_evidence symlink
rm "$bundle/samples/$first/checks.json"
ln "$report/evidence-content" "$bundle/samples/$first/checks.json"
refuse_evidence hardlink
rm "$bundle/samples/$first/checks.json"
mkfifo "$bundle/samples/$first/checks.json"
refuse_evidence fifo
rm "$bundle/samples/$first/checks.json"
cp "$report/evidence-content" "$bundle/samples/$first/checks.json"
cp "$report/evidence-content" "$bundle/samples/$first/unlisted.json"
refuse_evidence unlisted
rm "$bundle/samples/$first/unlisted.json"
cp "$bundle/report.json" "$report/evidence-original.json"
jq '.artifacts.baseline=("0"*64)|.samples|=map(if (.id|contains(":baseline:")) then .artifact_sha256=("0"*64) else . end)' \
    "$report/evidence-original.json" > "$bundle/report.json"
refuse_evidence rewritten-binding
printf '{"schema":1,"schema":1}\n' > "$bundle/report.json"
refuse_evidence duplicate-key
truncate -s 1048577 "$bundle/report.json"
refuse_evidence oversized-report
cp "$report/evidence-content" "$bundle/collection/raw/extra.json"
jq --arg digest "$digest" '.status="FAIL"|.collection_errors=[{kind:"unexpected_result",path:"raw/extra.json",sha256:$digest}]' \
    "$report/evidence-original.json" > "$bundle/report.json"
evidence_check > "$report/evidence-failed-run.out" 2> "$report/evidence-failed-run.err"
receipt=$(sed -n 's/^Evaluation evidence integrity: //p' "$report/evidence-failed-run.out")
jq -e '.status=="EVIDENCE_VALIDATED" and .evaluation_status=="FAIL" and .verified_files==241' "$receipt/summary.json" >/dev/null
passed=$((passed+1))
printf 'altered\n' > "$bundle/collection/raw/extra.json"
refuse_evidence changed-collection
mkdir "$report/raw-package"
for index in {1..40}; do cp "$report/evidence-content" "$report/raw-package/$index.json"; done
reserved=$((4*$(wc -c < "$report/evidence-content")))
bash "$root/scripts/evaluation/pack-raw.sh" "$report" raw-package "$reserved" > "$report/package.out" 2> "$report/package.err"
packed=$(sed -n 's/^Evaluation raw package: //p' "$report/package.out")
cp "$packed/evidence/raw.tar" "$bundle/samples/$first/raw.tar"
archive_sha=$(jq -er .archive_sha256 "$packed/summary.json")
jq --arg sha "$archive_sha" '.samples[0].evidence += [{path:"raw.tar",sha256:$sha}]' \
    "$report/evidence-original.json" > "$report/packaged-report.json"
cp "$report/packaged-report.json" "$bundle/report.json"
evidence_check > "$report/evidence-packaged.out" 2> "$report/evidence-packaged.err"
receipt=$(sed -n 's/^Evaluation evidence integrity: //p' "$report/evidence-packaged.out")
jq -e '.status=="EVIDENCE_VALIDATED" and .evaluation_status=="PASS" and .verified_files==241' "$receipt/summary.json" >/dev/null
passed=$((passed+1))
printf 'changed archive\n' >> "$bundle/samples/$first/raw.tar"
refuse_evidence changed-archive
cp "$packed/evidence/raw.tar" "$bundle/samples/$first/raw.tar"
other=$((3*$(wc -c < "$report/evidence-content")+$(wc -c < "$packed/evidence/raw.tar")))
for total in 16777216 16777217; do
    truncate -s "$((total-other))" "$bundle/samples/$first/requests.jsonl"
    request_sha=$(sha256sum < "$bundle/samples/$first/requests.jsonl"); request_sha=${request_sha%% *}
    jq --arg sha "$request_sha" '(.samples[0].evidence[]|select(.path=="requests.jsonl")|.sha256)=$sha' \
        "$report/packaged-report.json" > "$bundle/report.json"
    if [[ $total == 16777217 ]]; then refuse_evidence aggregate-byte-limit;
    else
        evidence_check > "$report/evidence-exact-budget.out" 2> "$report/evidence-exact-budget.err"
        receipt=$(sed -n 's/^Evaluation evidence integrity: //p' "$report/evidence-exact-budget.out")
        jq -e '.status=="EVIDENCE_VALIDATED" and .verified_files==241' "$receipt/summary.json" >/dev/null
        passed=$((passed+1))
    fi
done
printf 'Evaluation retained-evidence checks passed: %s\n' "$passed"
