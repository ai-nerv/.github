#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 5 && $2 =~ ^[0-9a-f]{64}$ && $3 =~ ^[a-z][a-z0-9-]{0,63}$ && ( $4 == baseline || $4 == candidate ) ]] || {
    echo 'usage: workload-body.sh FROZEN_BINDINGS BINDINGS_SHA TASK VARIANT RECEIPT' >&2; exit 2;
}
binding_root=$1 binding_sha=$2 task=$3 variant=$4
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
source "$root/scripts/evaluation/runner-common.sh"
source "$root/scripts/evaluation/tree-identity.sh"
report=$5
selected="$report/selected"
mkdir -p "$selected/runner/target/evaluation/bin" "$selected/fixtures" "$selected/configs/$variant" \
    "$selected/selections" "$report/captures" "$report/tools-before" "$report/tools-after"
status=FAIL failure=input_mismatch world= world_pid= runner_sha= fixture_sha= config_sha= artifact_sha=
ready=false
metrics_status=NOT_MEASURED
verify_selected() {
    runner_identity "$selected/runner" > "$report/runner-after.sha256" || return 1
    cmp "$report/runner-before.sha256" "$report/runner-after.sha256" || return 1
    tree_identity "$selected/fixtures/$task" > "$report/fixture-after.tree" || return 1
    cmp "$report/fixture-before.tree" "$report/fixture-after.tree" || return 1
    tree_identity "$selected/configs/$variant/$task" > "$report/config-after.tree" || return 1
    cmp "$report/config-before.tree" "$report/config-after.tree" || return 1
    sha256sum -c "$report/control.sha256" || return 1
    snapshot_world_tools "$report/tools-after" || return 1
    cmp "$selected/runner/tools.tsv" "$report/tools-after/tools.tsv" || return 1
    cmp "$selected/runner/closure" "$report/tools-after/closure"
}
finish() {
    local code=$?
    trap - EXIT
    if [[ -n $world_pid ]]; then
        kill -TERM "$world_pid" 2>/dev/null || true
        for _ in {1..200}; do kill -0 "$world_pid" 2>/dev/null || break; sleep 0.05; done
        kill -KILL "$world_pid" 2>/dev/null || true
        wait "$world_pid" 2>/dev/null || true
    fi
    if [[ -z $world && -f $report/world.out ]]; then
        local found
        found=$(sed -n 's/^Evaluation world evidence: //p' "$report/world.out")
        if [[ $found == "$selected/runner/target/evaluation/world-"* ]]; then world=$found; fi
    fi
    if [[ $ready == true ]] && ! verify_selected > "$report/after-integrity.log" 2>&1; then
        code=1; failure=input_mismatch
    fi
    if (( code != 0 )); then status=FAIL; fi
    jq -n --argjson code "$code" --arg status "$status" --arg failure "$failure" \
        --arg task "$task" --arg variant "$variant" --arg binding "$binding_sha" --arg runner "$runner_sha" \
        --arg artifact "$artifact_sha" --arg fixture "$fixture_sha" --arg config "$config_sha" --arg world "${world#"$report/"}" --arg metrics "$metrics_status" \
        '{schema:1,scope:"evaluation-bound-workload",status:$status,exit_code:$code,task_id:$task,variant:$variant,
          failure:(if $failure=="" then null else $failure end),bindings_sha256:$binding,
          runner_sha256:($runner|if .=="" then null else . end),artifact_sha256:($artifact|if .=="" then null else . end),
          fixture_sha256:($fixture|if .=="" then null else . end),config_sha256:($config|if .=="" then null else . end),
          world_receipt:($world|if .=="" then null else . end),metrics_status:$metrics,live_requests:0}' > "$report/summary.json"
    printf 'Evaluation bound workload: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
trap 'failure=interrupted; exit 130' INT
trap 'failure=interrupted; exit 143' TERM
printf 'Evaluation workload receipt: %s\n' "$report"
helper="$root/target/evaluation/bin/eval-input"
"$helper" file "$binding_root" bindings.json "$report/captures/bindings" 131072 1 >/dev/null
actual=$(sha256sum < "$report/captures/bindings/input"); [[ ${actual%% *} == "$binding_sha" ]]
cp "$report/captures/bindings/input" "$selected/bindings.json"
"$helper" file "$binding_root" manifest/input "$selected/manifest" 131072 1 >/dev/null
for file in "$selected/bindings.json" "$selected/manifest/input"; do
    jq -Rse --argjson safe_integers true -f "$root/scripts/evaluation/lexical.jq" "$file" >/dev/null
    jq --stream --slurp -e -f "$root/scripts/evaluation/json.jq" "$file" >/dev/null
done
manifest_sha=$(sha256sum < "$selected/manifest/input"); manifest_sha=${manifest_sha%% *}
jq -L "$root/scripts/evaluation" -e --slurpfile manifest "$selected/manifest/input" --arg sha "$manifest_sha" \
    'include "identity"; include "contract"; validate_bindings(($manifest[0]|validate_manifest);$sha)' "$selected/bindings.json" >/dev/null
jq -e --arg task "$task" '.tasks[]|select(.id==$task)' "$selected/manifest/input" > "$report/task-manifest.json"
jq '.timeout_seconds*1000' "$report/task-manifest.json" > "$report/deadline-ms.tmp"
mv "$report/deadline-ms.tmp" "$report/deadline-ms"
jq -e --arg task "$task" '.tasks[]|select(.id==$task)' "$selected/bindings.json" > "$report/task-binding.json"
runner_sha=$(jq -er .runner_sha256 "$selected/bindings.json")
artifact_sha=$(jq -er --arg variant "$variant" '.artifacts[$variant]' "$selected/bindings.json")
fixture_sha=$(jq -er .fixture_sha256 "$report/task-binding.json")
config_sha=$(jq -er --arg variant "$variant" '.config_sha256[$variant]' "$report/task-binding.json")
"$helper" tree "$binding_root" runner/scripts "$selected/runner/scripts" 4194304 128 >/dev/null
for name in eval-input eval-world eval-world-probe; do
    "$helper" binary "$binding_root" "runner/target/evaluation/bin/$name" "$report/captures/$name" >/dev/null
    mv "$report/captures/$name/input" "$selected/runner/target/evaluation/bin/$name"
done
for name in provider rust-grammar; do
    "$helper" binary "$binding_root" "runner/$name/input" "$selected/runner/$name" >/dev/null
done
if jq -e 'has("event_observer")' "$selected/bindings.json" >/dev/null; then
    "$helper" binary "$binding_root" runner/event-observer/input "$selected/runner/event-observer" >/dev/null
    actual=$(sha256sum < "$selected/runner/event-observer/input")
    [[ ${actual%% *} == "$(jq -er .event_observer.sha256 "$selected/bindings.json")" ]]
fi
for name in tools.tsv closure; do
    "$helper" file "$binding_root" "runner/$name" "$report/captures/$name" 131072 1 >/dev/null
    cp "$report/captures/$name/input" "$selected/runner/$name"
done
runner_identity "$selected/runner" > "$report/runner-before.sha256"
actual=$(sha256sum < "$report/runner-before.sha256"); [[ ${actual%% *} == "$runner_sha" ]]
lib="$selected/runner/scripts/evaluation"
while IFS= read -r -d '' name; do
    cmp "$root/${name#"$selected/runner/"}" "$name"
done < <(find "$selected/runner/scripts" -type f -print0)
for name in eval-input eval-world eval-world-probe; do
    cmp "$root/target/evaluation/bin/$name" "$selected/runner/target/evaluation/bin/$name"
done
snapshot_world_tools "$report/tools-before"
cmp "$selected/runner/tools.tsv" "$report/tools-before/tools.tsv"
cmp "$selected/runner/closure" "$report/tools-before/closure"
"$helper" tree "$binding_root" "fixtures/$task" "$selected/fixtures/$task" 16777216 256 >/dev/null
tree_identity "$selected/fixtures/$task" > "$report/fixture-before.tree"
actual=$(sha256sum < "$report/fixture-before.tree"); [[ ${actual%% *} == "$fixture_sha" ]]
"$helper" tree "$binding_root" "configs/$variant/$task" "$selected/configs/$variant/$task" 1048576 16 >/dev/null
tree_identity "$selected/configs/$variant/$task" > "$report/config-before.tree"
actual=$(sha256sum < "$report/config-before.tree"); [[ ${actual%% *} == "$config_sha" ]]
jq -n -L "$lib" --arg task "$task" 'include "workloads"; workload($task)' > "$report/workload.json"
jq -e --slurpfile task "$report/task-binding.json" '.models==$task[0].models' "$report/workload.json" >/dev/null
jq -r '.max_provider_attempts' "$report/task-manifest.json" > "$report/expected-limit.txt"
cmp "$report/expected-limit.txt" "$selected/fixtures/$task/provider-attempt-limit.txt"
cmp "$report/expected-limit.txt" "$selected/fixtures/$task/client-attempt-limit.txt"
sha256sum "$selected/bindings.json" "$selected/manifest/input" "$report/task-binding.json" "$report/task-manifest.json" \
    "$report/workload.json" > "$report/control.sha256"
ready=true
failure=artifact_mismatch
bash "$lib/artifact.sh" "$binding_root" "selections/$variant.json" manifest/input "$variant" > "$report/artifact.out" 2> "$report/artifact.err"
artifact=$(sed -n 's/^Evaluation artifact evidence: //p' "$report/artifact.out")
[[ $artifact == "$selected/runner/target/evaluation/artifact-"* ]]
jq -e --arg sha "$artifact_sha" '.status=="ARTIFACT_VALIDATED" and .artifact_sha256==$sha' "$artifact/summary.json" >/dev/null
cmp "$selected/manifest/input" "$artifact/manifest/input"
if ! jq -e --arg task "$task" '.[]|select(.id==$task)|.eligible' "$artifact/eligibility.json" >/dev/null; then
    status=NOT_RUN failure=unsupported_features
    exit 0
fi
relative=${artifact#"$selected/"}
jq --arg prefix "$relative" '.members|=map(.path=($prefix+"/members/"+.name+"/input"))|
    .assets|=to_entries|.assets|=map(.value+{path:($prefix+"/assets/"+(.key|tostring)+"/input")})' \
    "$artifact/validated.json" > "$selected/selections/$variant.json"
sha256sum "$selected/selections/$variant.json" >> "$report/control.sha256"
millis=$(jq '.timeout_seconds*1000' "$report/task-manifest.json")
provider_sha=$(sha256sum < "$selected/runner/provider/input"); provider_sha=${provider_sha%% *}
grammar_sha=$(sha256sum < "$selected/runner/rust-grammar/input"); grammar_sha=${grammar_sha%% *}
grammar=()
observer=()
if jq -e 'has("event_observer")' "$selected/bindings.json" >/dev/null; then
    observer=(--event-observer runner/event-observer/input
        "$(jq -er .event_observer.sha256 "$selected/bindings.json")"
        "$(jq -er --arg variant "$variant" '.event_observer.modes[$variant]' "$selected/bindings.json")")
fi
if jq -e .rust_grammar "$report/workload.json" >/dev/null; then grammar=(--rust-grammar runner/rust-grammar/input "$grammar_sha"); fi
mapfile -t driver_args < <(jq -r '.args[]' "$report/workload.json")
failure=invalid_result
bash "$lib/world.sh" "$selected" "fixtures/$task" "$millis" \
    --provider runner/provider/input "$provider_sha" \
    --artifact "selections/$variant.json" manifest/input "$variant" "$artifact_sha" "${grammar[@]}" "${observer[@]}" \
    /runner/bin/bash /input/driver.sh "${driver_args[@]}" > "$report/world.out" 2> "$report/world.err" &
world_pid=$!
code=0; wait "$world_pid" || code=$?
world_pid=
world=$(sed -n 's/^Evaluation world evidence: //p' "$report/world.out")
[[ $world == "$selected/runner/target/evaluation/world-"* ]]
if (( code != 0 )); then
    if [[ -f $world/receipt/outer.json ]] && jq -e .timed_out "$world/receipt/outer.json" >/dev/null; then
        failure=prompt_timeout
    elif bash "$lib/client-attempts.sh" "$world/receipt" "$(cat "$report/expected-limit.txt")" limit-failure \
        > "$report/client-limit.out" 2> "$report/client-limit.err"; then
        limited=$(sed -n 's/^Evaluation client attempts: //p' "$report/client-limit.out")
        [[ $limited == "$selected/runner/target/evaluation/client-attempts-"* ]]
        jq -e '.status=="ATTEMPT_LIMIT_CONFIRMED" and .failure=="attempt_limit"' "$limited/result.json" >/dev/null
        cp "$limited/result.json" "$report/client-limit.json"
        failure=attempt_limit
    fi
    exit "$code"
fi
jq -e --arg sha "$artifact_sha" --arg variant "$variant" \
    '.status=="WORLD_COMPLETED" and .artifact_sha256==$sha and .variant==$variant' "$world/summary.json" >/dev/null
if (( ${#observer[@]} )); then
    jq -e --arg sha "${observer[2]}" --arg mode "${observer[3]}" \
        '.event_observer=={schema:1,sha256:$sha,mode:$mode}' "$world/summary.json" >/dev/null
    observed="$report/observer-receipts.jsonl"
    sed -n 's/^Evaluation event observer: //p' "$world/receipt/worker.stdout" > "$observed"
    [[ -s $observed && $(wc -c < "$observed") -le 524288 ]]
    launches=1
    case $task in resume) launches=5;; cache-accounting|concurrent-disjoint-edits) launches=2;; esac
    native_sha=$(jq -er '.members[]|select(.name=="magi")|.sha256' "$selected/selections/$variant.json")
    jq -se --arg sha "${observer[2]}" --arg mode "${observer[3]}" --arg native "$native_sha" --argjson count "$launches" \
        'length==$count and (unique_by([.receipt.native.pid,.receipt.native.start_time])|length)==$count and
         all(.[]; .schema==1 and .observer_sha256==$sha and .observer_pid!=.receipt.native.pid and
           (.receipt|.schema==1 and .scope=="evaluation-event-observer" and .status=="PASS" and .mode==$mode and
            .native.executable_sha256==$native and .child_reaped and .adopted_children_complete and (.timed_out|not) and
            (if $mode=="stall" then .before_release.counts.accepted==0 and .before_release.counts.statuses==0 else true end)))' \
        "$observed" >/dev/null
else
    jq -e 'has("event_observer")|not' "$world/summary.json" >/dev/null
fi
cmp "$selected/runner/closure" "$world/runner/closure"
tree_identity "$world/input" > "$report/world-fixture.tree"
cmp "$report/fixture-before.tree" "$report/world-fixture.tree"
failure=input_mismatch
bash "$lib/check-config.sh" "$selected" "$binding_sha" "$task" "$variant" "$world/receipt" > "$report/config-check.json" 2> "$report/config-check.err"
limit=$(cat "$report/expected-limit.txt")
jq -se --argjson limit "$limit" '.[0].limit==$limit and .[-1].event=="terminal" and .[-1].admitted<=$limit' "$world/receipt/evidence/meter.jsonl" >/dev/null
mapfile -t scorer_args < <(jq -r '.scorer_args[]' "$report/workload.json")
scorer=$(jq -er .scorer "$report/workload.json")
scorer_args+=("$world/input" "$world/receipt")
if (( ${#grammar[@]} )); then scorer_args+=("$grammar_sha"); fi
failure=check_failed
bash "$lib/$scorer" "${scorer_args[@]}" > "$report/checks.json" 2> "$report/checks.err"
jq -e --slurpfile task "$report/task-manifest.json" '.status=="PASS" and .task_id==$task[0].id and
    [.checks[].id]==$task[0].checks and all(.checks[]; .status=="PASS")' "$report/checks.json" >/dev/null
failure=invalid_result
bash "$lib/transcript-usage.sh" "$task" "$world/receipt/evidence" "$report/transcript-usage" \
    > "$report/usage.out" 2> "$report/usage.err"
bash "$lib/unpack-model-ipc.sh" "$world/receipt" "$report/model-ipc" "$selected/runner/target/evaluation/bin/eval-input" "$lib" \
    > "$report/ipc-unpack.out" 2> "$report/ipc-unpack.err"
bash "$lib/ipc-usage.sh" "$report/model-ipc" raw > "$report/ipc-usage.out" 2> "$report/ipc-usage.err"
ipc_usage=$(sed -n 's/^Evaluation IPC usage: //p' "$report/ipc-usage.out")
[[ $ipc_usage == "$selected/runner/target/evaluation/ipc-usage-"* ]]
jq -e '.status=="USAGE_EXTRACTED" and .complete_run==false' "$ipc_usage/summary.json" >/dev/null
cp "$ipc_usage/result.json" "$report/model-ipc-usage.json"
bash "$lib/normalized-prefix.sh" "$world/receipt/evidence" > "$report/prefix.out" 2> "$report/prefix.err"
prefix=$(sed -n 's/^Evaluation normalized prefix: //p' "$report/prefix.out")
[[ $prefix == "$selected/runner/target/evaluation/prefix-"* ]]
jq -e '.status=="PREFIX_MEASURED" and .complete_run==false and .provider_attempts==null and .cached_tokens==null' \
    "$prefix/result.json" >/dev/null
cp "$prefix/result.json" "$report/normalized-prefix.json"
bash "$lib/client-attempts.sh" "$world/receipt" "$limit" > "$report/client-attempts.out" 2> "$report/client-attempts.err"
attempts=$(sed -n 's/^Evaluation client attempts: //p' "$report/client-attempts.out")
[[ $attempts == "$selected/runner/target/evaluation/client-attempts-"* ]]
jq -e --slurpfile prefix "$report/normalized-prefix.json" \
    '.status=="ATTEMPTS_MEASURED" and .provider_attempts==($prefix[0].bodies|length)' "$attempts/result.json" >/dev/null
cp "$attempts/result.json" "$report/client-attempts.json"
bash "$lib/reconcile-usage.sh" "$task" "$report" "${world#"$report/"}" > "$report/reconcile-usage.out" 2> "$report/reconcile-usage.err"
reconciled=$(sed -n 's/^Evaluation reconciled usage: //p' "$report/reconcile-usage.out")
[[ $reconciled == "$selected/runner/target/evaluation/reconciled-usage-"* ]]
jq -e '.status=="USAGE_RECONCILED" and .helper_attribution and .real_billing_verified==false' "$reconciled/result.json" >/dev/null
cp "$reconciled/result.json" "$report/reconciled-usage.json"
bash "$lib/activity.sh" "$task" "$report" "${world#"$report/"}" > "$report/activity.out" 2> "$report/activity.err"
activity=$(sed -n 's/^Evaluation activity observations: //p' "$report/activity.out")
[[ $activity == "$selected/runner/target/evaluation/activity-"* ]]
jq -e '.status=="ACTIVITY_OBSERVED" and .report_metric_mapping=="separate-v1"' "$activity/result.json" >/dev/null
cp "$activity/result.json" "$report/activity.json"
metrics_status=PARTIAL
jq -n --slurpfile activity "$report/activity.json" --slurpfile attempts "$report/client-attempts.json" \
    --slurpfile usage "$report/reconciled-usage.json" --slurpfile prefix "$report/normalized-prefix.json" \
    '{activity:$activity[0],attempts:$attempts[0],usage:$usage[0],prefix:$prefix[0]}' > "$report/metric-input.json"
jq -e -L "$lib" -f "$lib/metrics.jq" "$report/metric-input.json" > "$report/metrics.tmp"
[[ $(wc -c < "$report/metrics.tmp") -le 65536 ]]
"$helper" json "$report" metrics.tmp 131072 >/dev/null
mv "$report/metrics.tmp" "$report/metrics.json"
metrics_status=MEASURED
status=WORKLOAD_CHECKED failure=
