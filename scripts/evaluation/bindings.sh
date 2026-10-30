#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ ( $# == 10 || $# == 11 ) && $4 =~ ^[0-9a-f]{64}$ && $6 =~ ^[0-9a-f]{64}$ &&
   $8 =~ ^[0-9a-f]{64}$ && ${10} =~ ^[0-9a-f]{64}$ ]] || {
    echo 'usage: bindings.sh ROOT MANIFEST BASELINE BASELINE_SHA CANDIDATE CANDIDATE_SHA PROVIDER PROVIDER_SHA GRAMMAR GRAMMAR_SHA [OBSERVER]' >&2; exit 2;
}
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
input_root=$1 manifest_source=$2 baseline=$3 baseline_sha=$4 candidate=$5 candidate_sha=$6
provider=$7 provider_sha=$8 grammar=$9 grammar_sha=${10}
observer=${11:-}
source "$root/scripts/preserve-binary.sh"
mkdir -p "$root/target/evaluation"
receipt=$(mktemp -d "$root/target/evaluation/bindings-XXXXXXXX")
mkdir -p "$receipt/runner/scripts/evaluation" "$receipt/runner/target/evaluation/bin" \
    "$receipt/fixtures" "$receipt/staging" "$receipt/configs" "$receipt/selections" "$receipt/identities" "$receipt/captures"
touch "$receipt/binaries.sha256"
binding_sha=
finish() {
    local code=$?
    trap - EXIT
    if ! verify_preserved_binaries "$receipt/binaries.sha256" > "$receipt/integrity.log" 2>&1; then code=1; fi
    if [[ -s $receipt/inputs.sha256 ]] && ! sha256sum -c "$receipt/inputs.sha256" > "$receipt/input-integrity.log" 2>&1; then code=1; fi
    jq -n --argjson code "$code" --arg sha "$binding_sha" \
        '{schema:1,scope:"evaluation-frozen-bindings",status:(if $code==0 then "BINDINGS_VALIDATED" else "FAIL" end),
          exit_code:$code,bindings_sha256:(if $code==0 then $sha else null end),workers_started:0}' > "$receipt/summary.json"
    printf 'Evaluation frozen bindings: %s\n' "$receipt"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
for name in eval-input eval-world eval-world-probe; do
    preserve_binary "$root/target/evaluation/bin/$name" "$receipt/runner/target/evaluation/bin/$name" "$receipt/binaries.sha256" >/dev/null
done
helper="$receipt/runner/target/evaluation/bin/eval-input"
files=(bindings.sh artifact.sh artifact.jq world.sh lexical.jq json.jq contract.jq identity.jq workloads.jq
       manifest.jq schedule.jq report.jq sample.jq evidence.sh render-config.sh check-config.sh tree-identity.sh family-common.sh
       runner-common.sh event-observer.sh score-common.sh run-workload.sh workload-body.sh pack-raw.sh aggregate.sh collection.jq aggregate.jq
       transcript-usage.sh usage.jq usage-input.jq
       request-bytes.sh request-bytes.jq normalized-prefix.sh normalized-prefix.jq
       client-admission.lua client-attempts.sh client-attempts.jq client-limit.jq
       reconcile-usage.sh reconcile-usage.jq
       activity.sh activity.jq metrics.jq
       run-sample.sh sample-body.sh assemble-sample.jq run-suite.sh
       ipc-recorder-melchior.sh pack-model-ipc.sh unpack-model-ipc.sh ipc-usage.sh ipc-usage.jq log-word.jq
       mutation-workload.sh control-workload.sh concurrent-workload.sh accounting-workload.sh
       pressure-workload.sh resume-workload.sh child-workload.sh
       score-mutation.sh score-control.sh score-concurrent.sh score-accounting.sh score-pressure.sh score-resume.sh score-child.sh
       mutation-journal.jq index-journal.jq control-journal.jq concurrent-journal.jq accounting-journal.jq
       pressure-journal.jq resume-journal.jq child-journal.jq)
for file in "${files[@]}"; do
    "$helper" file "$root/scripts/evaluation" "$file" "$receipt/captures/$file" 131072 1 > "$receipt/captures/$file-counts.json"
    cp "$receipt/captures/$file/input" "$receipt/runner/scripts/evaluation/$file"
done
for file in preserve-binary.sh evaluate.sh; do
    "$helper" file "$root/scripts" "$file" "$receipt/captures/$file" 131072 1 >/dev/null
    cp "$receipt/captures/$file/input" "$receipt/runner/scripts/$file"
done
lib="$receipt/runner/scripts/evaluation"
source "$lib/tree-identity.sh"
source "$lib/runner-common.sh"
"$helper" file "$input_root" "$manifest_source" "$receipt/manifest" 131072 1 > "$receipt/manifest-counts.json"
manifest="$receipt/manifest/input"
jq -Rse --argjson safe_integers true -f "$lib/lexical.jq" "$manifest" >/dev/null
jq --stream --slurp -e -f "$lib/json.jq" "$manifest" >/dev/null
jq -L "$lib" -e -f "$lib/manifest.jq" "$manifest" > "$receipt/validated-manifest.json"
jq -L "$lib" -f "$lib/schedule.jq" "$manifest" > "$receipt/schedule.json"
if jq -e 'has("event_observer")' "$manifest" >/dev/null; then
    [[ -n $observer && $baseline_sha == "$candidate_sha" ]]
    "$helper" binary "$input_root" "$observer" "$receipt/runner/event-observer" > "$receipt/observer-counts.json"
    actual=$(sha256sum < "$receipt/runner/event-observer/input")
    [[ ${actual%% *} == "$(jq -er .event_observer.sha256 "$manifest")" ]]
    sha256sum "$receipt/runner/event-observer/input" >> "$receipt/binaries.sha256"
else
    [[ -z $observer ]]
fi
for variant in baseline candidate; do
    selected=$baseline expected=$baseline_sha
    if [[ $variant == candidate ]]; then selected=$candidate expected=$candidate_sha; fi
    bash "$lib/artifact.sh" "$input_root" "$selected" "$manifest_source" "$variant" > "$receipt/$variant.out" 2> "$receipt/$variant.err"
    artifact=$(sed -n 's/^Evaluation artifact evidence: //p' "$receipt/$variant.out")
    [[ -n $artifact && $artifact == "$receipt/runner/target/evaluation/artifact-"* ]]
    jq -e --arg sha "$expected" --arg variant "$variant" \
        '.status=="ARTIFACT_VALIDATED" and .artifact_sha256==$sha and .variant==$variant and .workers_started==0' "$artifact/summary.json" >/dev/null
    cmp "$manifest" "$artifact/manifest/input"
    relative=${artifact#"$receipt/"}
    printf '%s\n' "$relative" > "$receipt/selections/$variant-receipt.txt"
    jq --arg prefix "$relative" '.members|=map(.path=($prefix+"/members/"+.name+"/input"))|
        .assets|=to_entries|.assets|=map(.value+{path:($prefix+"/assets/"+(.key|tostring)+"/input")})' \
        "$artifact/validated.json" > "$receipt/selections/$variant.json"
    cat "$artifact/binaries.sha256" >> "$receipt/binaries.sha256"
done
for name in provider rust-grammar; do
    selected=$provider expected=$provider_sha mode=build-binary
    if [[ $name == rust-grammar ]]; then selected=$grammar expected=$grammar_sha mode=binary; fi
    "$helper" "$mode" "$input_root" "$selected" "$receipt/runner/$name" > "$receipt/$name-counts.json"
    file="$receipt/runner/$name/input"
    actual=$(sha256sum < "$file"); [[ ${actual%% *} == "$expected" ]]
    header=$(od -An -v -tx1 -N20 "$file" | tr -d ' \n')
    [[ $header == 7f454c46020101* && ( ${header:14:2} == 00 || ${header:14:2} == 03 ) &&
       ( ${header:32:4} == 0200 || ${header:32:4} == 0300 ) && ${header:36:4} == 3e00 ]]
    sha256sum "$file" >> "$receipt/binaries.sha256"
done
snapshot_world_tools "$receipt/runner"
runner_identity "$receipt/runner" > "$receipt/identities/runner.sha256"
runner_sha=$(sha256sum < "$receipt/identities/runner.sha256"); runner_sha=${runner_sha%% *}
jq -r '.tasks[]|[.id,.fixture]|@tsv' "$manifest" > "$receipt/tasks.tsv"
while IFS=$'\t' read -r task fixture; do
    "$helper" tree "$input_root" "scripts/evaluation/$fixture" "$receipt/staging/$task" 16777216 256 > "$receipt/$task-input-counts.json"
    stage="$receipt/staging/$task"
    [[ -f $stage/prompt.txt && ! -e $stage/driver.sh && ! -e $stage/family-common.sh && ! -e $stage/provider-attempt-limit.txt ]]
    jq -n -L "$lib" --arg id "$task" 'include "workloads"; workload($id)' > "$receipt/identities/$task-workload.json"
    driver=$(jq -er .driver "$receipt/identities/$task-workload.json")
    cp "$lib/$driver" "$stage/driver.sh"
    cp "$lib/family-common.sh" "$stage/family-common.sh"
    for file in ipc-recorder-melchior.sh pack-model-ipc.sh event-observer.sh; do
        [[ ! -e $stage/$file ]]
        cp "$lib/$file" "$stage/$file"
    done
    for file in client-admission.lua client-providers.lua client-attempt-limit.txt; do
        [[ ! -e $stage/$file ]]
    done
    cp "$lib/client-admission.lua" "$stage/client-admission.lua"
    jq -r '"\nmelchior.evaluation_providers = { " +
        ([.models[].provider]|unique|map("["+tojson+"] = true")|join(", ")) + " }"' \
        "$receipt/identities/$task-workload.json" > "$stage/client-providers.lua"
    jq -r --arg task "$task" '.tasks[]|select(.id==$task)|.max_provider_attempts' "$manifest" > "$stage/provider-attempt-limit.txt"
    cp "$stage/provider-attempt-limit.txt" "$stage/client-attempt-limit.txt"
    "$helper" tree "$receipt/staging" "$task" "$receipt/fixtures/$task" 16777216 256 > "$receipt/$task-staged-counts.json"
    tree_identity "$receipt/fixtures/$task" > "$receipt/identities/$task-fixture.tree"
    fixture_sha=$(sha256sum < "$receipt/identities/$task-fixture.tree"); fixture_sha=${fixture_sha%% *}
    for variant in baseline candidate; do
        artifact="$receipt/$(cat "$receipt/selections/$variant-receipt.txt")"
        mkdir -p "$receipt/configs/$variant"
        bash "$lib/render-config.sh" "$task" "$artifact/assets" "$receipt/fixtures/$task" "$receipt/staging/$task-$variant-config" @PORT@
        "$helper" tree "$receipt/staging" "$task-$variant-config" "$receipt/configs/$variant/$task" 1048576 16 > "$receipt/$task-$variant-config-counts.json"
        tree_identity "$receipt/configs/$variant/$task" > "$receipt/identities/$task-$variant-config.tree"
        sha=$(sha256sum < "$receipt/identities/$task-$variant-config.tree")
        if [[ $variant == baseline ]]; then base_config=${sha%% *}; else candidate_config=${sha%% *}; fi
    done
    jq -nc --arg id "$task" --arg fixture "$fixture_sha" --arg base "$base_config" --arg candidate "$candidate_config" \
        --slurpfile workload "$receipt/identities/$task-workload.json" \
        '{id:$id,fixture_sha256:$fixture,config_sha256:{baseline:$base,candidate:$candidate},models:$workload[0].models}' >> "$receipt/task-bindings.jsonl"
done < "$receipt/tasks.tsv"
manifest_sha=$(sha256sum < "$manifest"); manifest_sha=${manifest_sha%% *}
jq -n --arg manifest "$manifest_sha" --arg runner "$runner_sha" --arg baseline "$baseline_sha" --arg candidate "$candidate_sha" \
    --slurpfile policy "$manifest" \
    --slurpfile tasks "$receipt/task-bindings.jsonl" \
    '{schema:2,manifest_sha256:$manifest,runner_sha256:$runner,artifacts:{baseline:$baseline,candidate:$candidate},tasks:$tasks} +
     (if $policy[0]|has("event_observer") then {event_observer:$policy[0].event_observer} else {} end)' > "$receipt/bindings.json"
jq -L "$lib" -e --slurpfile manifest "$manifest" --arg sha "$manifest_sha" \
    'include "identity"; validate_bindings($manifest[0];$sha)' "$receipt/bindings.json" >/dev/null
binding_sha=$(sha256sum < "$receipt/bindings.json"); binding_sha=${binding_sha%% *}
find "$receipt/runner" "$receipt/fixtures" "$receipt/configs" "$receipt/manifest" "$receipt/identities" "$receipt/selections" \
    -type f -exec sha256sum -- {} + > "$receipt/inputs.sha256"
sha256sum "$receipt/bindings.json" "$receipt/validated-manifest.json" "$receipt/schedule.json" >> "$receipt/inputs.sha256"
