#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 2 && $2 =~ ^[0-9a-f]{64}$ ]] || exit 2
binding_root=$(cd -- "$1" && pwd -P) binding_sha=$2
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
source "$root/scripts/evaluation/tree-identity.sh"
source "$root/scripts/evaluation/runner-common.sh"
report=$(mktemp -d "$root/target/evaluation/execution-tests-XXXXXXXX")
passed=0 running=
: > "$report/workload-failures.jsonl"
finish() {
    local code=$?
    trap - EXIT
    if [[ -n $running ]]; then kill -TERM "$running" 2>/dev/null || true; wait "$running" 2>/dev/null || true; fi
    jq -n --argjson code "$code" --argjson passed "$passed" --arg sha "$binding_sha" \
        --slurpfile failures "$report/workload-failures.jsonl" \
        '{schema:1,scope:"evaluation-execution-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$passed,workload_failures:$failures,bindings_sha256:$sha,live_requests:0}' > "$report/summary.json"
    printf 'Evaluation execution test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
run_path() { sed -n 's/^Evaluation bound workload: //p' "$1"; }
while read -r task; do
    code=0
    bash "$root/scripts/evaluation/run-workload.sh" "$binding_root" "$binding_sha" "$task" baseline > "$report/$task.out" 2> "$report/$task.err" || code=$?
    run=$(run_path "$report/$task.out")
    if (( code != 0 )); then
        jq -e --arg task "$task" '.status=="FAIL" and .task_id==$task and .variant=="baseline"' "$run/summary.json" >/dev/null
        jq -nc --arg task "$task" --arg run "$run" --argjson code "$code" \
            '{task_id:$task,variant:"baseline",exit_code:$code,receipt:$run}' >> "$report/workload-failures.jsonl"
        continue
    fi
    jq -e --arg task "$task" '.status=="WORKLOAD_CHECKED" and .task_id==$task and .variant=="baseline" and .failure==null and .metrics_status=="MEASURED"' "$run/summary.json" >/dev/null
    jq -e -L "$root/scripts/evaluation" 'include "sample"; metrics and all(.[];.!=null)' "$run/metrics.json" >/dev/null
    jq -e -L "$root/scripts/evaluation" -f "$root/scripts/evaluation/metrics.jq" "$run/metric-input.json" > "$report/expected-metrics.json"
    cmp "$report/expected-metrics.json" "$run/metrics.json"
    jq -e '.status=="PREFIX_MEASURED" and .complete_run==false and .provider_attempts==null and .cached_tokens==null and
        .request_bytes>0 and .stable_prefix_bytes<=.normalized_bytes and .stable_prefix_bytes<=.request_bytes and
        (.bodies|length)>0 and .bodies[0].shared_bytes==0' "$run/normalized-prefix.json" >/dev/null
    jq -e --slurpfile prefix "$run/normalized-prefix.json" '.status=="ATTEMPTS_MEASURED" and
        .provider_attempts==($prefix[0].bodies|length) and .provider_attempts<=.limit' "$run/client-attempts.json" >/dev/null
    usage="$run/transcript-usage/result.json"
    jq -e '.status=="ACTIVITY_OBSERVED" and .complete_run==false and .observations.accepted_user_entries>0 and
      .observations.completed_layout_decisions>0 and .observations.failed_executed_tool_results<=.observations.executed_tool_results and
      .observations.completed_tool_results==(.observations.executed_tool_results+.observations.guard_suppressed_calls)' "$run/activity.json" >/dev/null
    case $task in
        input-pressure) jq -e '.observations.summary_model_calls==2 and .observations.title_model_calls==1 and .observations.failed_executed_tool_results==1' "$run/activity.json" >/dev/null ;;
        repetitive-failure) jq -e '.observations.executed_tool_results==2 and .observations.guard_suppressed_calls==2 and .observations.failed_executed_tool_results==2' "$run/activity.json" >/dev/null ;;
        resume) jq -e '.observations.accepted_user_entries==4' "$run/activity.json" >/dev/null ;;
        child-work|concurrent-disjoint-edits|cache-accounting) jq -e '.observations.accepted_user_entries==2' "$run/activity.json" >/dev/null ;;
        output-only-overflow) jq -e '.observations.output_reductions==1 and .observations.transport_retries==0 and .observations.executed_tool_results==0' "$run/activity.json" >/dev/null ;;
    esac
    passed=$((passed+1))
    jq -e '.status=="USAGE_RECONCILED" and .helper_attribution and .real_billing_verified==false and
      .totals.charged_micros==(.totals.reported_micros+.totals.estimated_micros)' "$run/reconciled-usage.json" >/dev/null
    case $task in
        input-pressure) jq -e '.totals.input_tokens==79 and .totals.output_tokens==24 and
          ([.calls[]|select(.role=="summary")]|length)==2 and ([.calls[]|select(.role=="title")]|length)==1 and
          ([.calls[]|select(.usage_basis=="scripted-nonstreaming-rejection")]|length)==1' "$run/reconciled-usage.json" >/dev/null ;;
        repetitive-failure) jq -e '.totals.input_tokens==40 and (.synthetic_assistant_rows|length)==1' "$run/reconciled-usage.json" >/dev/null ;;
        *) jq -e --slurpfile usage "$usage" '.totals==$usage[0].totals' "$run/reconciled-usage.json" >/dev/null ;;
    esac
    passed=$((passed+1))
    jq -e '.status=="USAGE_EXTRACTED" and .complete_run==false and .coverage=="durable-assistant-entries-only" and
        .known_totals.charged_micros==(.known_totals.reported_micros+.known_totals.estimated_micros)' "$usage" >/dev/null
    case $task in
        cache-accounting) jq -e '.unknown_usage_records==0 and .totals=={input_tokens:112,output_tokens:30,cache_read_tokens:540,cache_write_tokens:115,reported_micros:200,estimated_micros:751,charged_micros:951}' "$usage" >/dev/null ;;
        resume) jq -e '.unknown_usage_records==0 and .totals.charged_micros==804 and .totals.input_tokens==210 and .totals.output_tokens==48 and [.transcripts[].assistant_records]==[4,2]' "$usage" >/dev/null ;;
        child-work)
            measured_world="$run/$(jq -er .world_receipt "$run/summary.json")"
            jq -e --rawfile ledger "$measured_world/receipt/evidence/ledger.txt" '.unknown_usage_records==0 and (.transcripts|length)==2 and .totals.charged_micros==($ledger|rtrimstr("\n")|tonumber)' "$usage" >/dev/null ;;
        input-pressure) jq -e '.unknown_usage_records==1 and .known_totals.input_tokens==60 and .known_totals.output_tokens==18 and all(.totals[];.==null)' "$usage" >/dev/null ;;
        repetitive-failure) jq -e '.unknown_usage_records==1 and .known_totals.input_tokens==40 and all(.totals[];.==null)' "$usage" >/dev/null ;;
        *) jq -e '.unknown_usage_records==0 and .totals==.known_totals' "$usage" >/dev/null ;;
    esac
    passed=$((passed+1))
    jq -e '.status=="USAGE_EXTRACTED" and .coverage=="recorded-model-asks-only" and
        .complete_run==false and .helper_attribution==null and .provider_attempts==null and .settlement_verified==false and
        .capture_complete==true and (.calls|length)>0' "$run/model-ipc-usage.json" >/dev/null
    case $task in
        cache-accounting|resume|child-work)
            jq -e --slurpfile transcript "$usage" '.totals==$transcript[0].totals' "$run/model-ipc-usage.json" >/dev/null ;;
        input-pressure)
            jq -e '.known_totals.input_tokens==79 and .known_totals.output_tokens==24 and .unknown_calls.input_tokens==1 and all(.totals[];.==null)' "$run/model-ipc-usage.json" >/dev/null ;;
    esac
    passed=$((passed+1))
    jq -e '.scope=="evaluation-controller" and .cleanup_confirmed and .timed_out==false and .leaked_processes==0 and .limit_ms==60000' "$run/control.json" >/dev/null
    jq -e '.status=="PASS" and all(.checks[]; .status=="PASS")' "$run/checks.json" >/dev/null
    [[ -s $run/after-integrity.log ]]
    passed=$((passed+1))
    world=$(jq -er .world_receipt "$run/summary.json")
    bash "$run/selected/runner/scripts/evaluation/pack-raw.sh" "$run" "$world/receipt" 0 \
        > "$report/$task-pack.out" 2> "$report/$task-pack.err"
    packed=$(sed -n 's/^Evaluation raw package: //p' "$report/$task-pack.out")
    jq -e '.status=="RAW_PACKED" and .workers_started==0 and .archive_bytes<=16777216' "$packed/summary.json" >/dev/null
    mkdir "$report/$task-restored"
    env -i LC_ALL=C "$packed/bin/tar" -xf "$packed/evidence/raw.tar" -C "$report/$task-restored"
    tree_identity "$report/$task-restored" > "$report/$task-restored.tree"
    cmp "$packed/source-before.tree" "$report/$task-restored.tree"
    passed=$((passed+1))
done < <(jq -r '.tasks[].id' "$binding_root/bindings.json")
bash "$root/scripts/evaluation/run-workload.sh" "$binding_root" "$binding_sha" output-only-overflow candidate > "$report/candidate.out" 2> "$report/candidate.err"
run=$(run_path "$report/candidate.out")
jq -e --slurpfile binding "$binding_root/bindings.json" '.status=="WORKLOAD_CHECKED" and .variant=="candidate" and
    .artifact_sha256==$binding[0].artifacts.candidate' "$run/summary.json" >/dev/null
passed=$((passed+1))
corrupt="$report/corrupt"
cp -R --reflink=auto "$binding_root" "$corrupt"
observer_modes=()
if jq -e 'has("event_observer")' "$binding_root/bindings.json" >/dev/null; then
    observer_modes=(observer observer-helper observer-policy)
fi
for mode in binding manifest runner extra-runner tool-helper provider grammar tools fixture ipc-wrapper ipc-extractor prefix-filter client-guard client-selection client-limit config selection fixture-symlink fixture-hardlink "${observer_modes[@]}"; do
    case $mode in
        binding) file=bindings.json; printf '\n' >> "$corrupt/$file" ;;
        manifest) file=manifest/input; printf '\n' >> "$corrupt/$file" ;;
        runner) file=runner/scripts/evaluation/world.sh; printf '\nexit 0\n' >> "$corrupt/$file" ;;
        extra-runner) file=runner/scripts/evaluation/extra.sh; : > "$corrupt/$file" ;;
        tool-helper) file=runner/target/evaluation/bin/eval-world; chmod u+w "$corrupt/$file"; printf 'changed\n' >> "$corrupt/$file" ;;
        provider) file=runner/provider/input; chmod u+w "$corrupt/$file"; printf 'changed\n' >> "$corrupt/$file" ;;
        grammar) file=runner/rust-grammar/input; chmod u+w "$corrupt/$file"; printf 'changed\n' >> "$corrupt/$file" ;;
        observer) file=runner/event-observer/input; chmod u+w "$corrupt/$file"; printf 'changed\n' >> "$corrupt/$file" ;;
        observer-helper) file=fixtures/output-only-overflow/event-observer.sh; printf 'changed\n' >> "$corrupt/$file" ;;
        observer-policy) file=bindings.json; jq '.event_observer.modes.baseline="stall"' "$binding_root/$file" > "$corrupt/$file" ;;
        tools) file=runner/tools.tsv; printf 'extra\n' >> "$corrupt/$file" ;;
        fixture) file=fixtures/output-only-overflow/prompt.txt; printf 'changed\n' >> "$corrupt/$file" ;;
        ipc-wrapper) file=fixtures/output-only-overflow/ipc-recorder-melchior.sh; printf 'changed\n' >> "$corrupt/$file" ;;
        ipc-extractor) file=runner/scripts/evaluation/ipc-usage.sh; printf 'changed\n' >> "$corrupt/$file" ;;
        prefix-filter) file=runner/scripts/evaluation/normalized-prefix.jq; printf 'changed\n' >> "$corrupt/$file" ;;
        client-guard) file=fixtures/output-only-overflow/client-admission.lua; printf 'changed\n' >> "$corrupt/$file" ;;
        client-selection) file=fixtures/output-only-overflow/client-providers.lua; printf 'changed\n' >> "$corrupt/$file" ;;
        client-limit) file=fixtures/output-only-overflow/client-attempt-limit.txt; printf '1\n' > "$corrupt/$file" ;;
        config) file=configs/baseline/output-only-overflow/0.lua; printf '\nmagi.allow = {}\n' >> "$corrupt/$file" ;;
        selection) file=selections/baseline.json; jq '.members[0].sha256=("0"*64)' "$binding_root/$file" > "$corrupt/$file" ;;
        fixture-symlink) file=fixtures/output-only-overflow/prompt.txt; rm "$corrupt/$file"; ln -s "$binding_root/$file" "$corrupt/$file" ;;
        fixture-hardlink) file=fixtures/output-only-overflow/prompt.txt; ln "$corrupt/$file" "$corrupt/alias" ;;
    esac
    if bash "$root/scripts/evaluation/run-workload.sh" "$corrupt" "$binding_sha" output-only-overflow baseline > "$report/refuse-$mode.out" 2> "$report/refuse-$mode.err"; then
        echo "accepted corrupted execution input: $mode" >&2; exit 1
    fi
    run=$(run_path "$report/refuse-$mode.out")
    jq -e '.status=="FAIL" and .world_receipt==null' "$run/summary.json" >/dev/null
    [[ ! -e $run/world.out ]]
    if [[ $mode == extra-runner ]]; then rm "$corrupt/$file"; else cp -p --remove-destination "$binding_root/$file" "$corrupt/$file"; fi
    if [[ $mode == fixture-hardlink ]]; then rm "$corrupt/alias"; fi
    passed=$((passed+1))
done
for mode in script helper; do
    if [[ $mode == script ]]; then
        file=runner/scripts/evaluation/world.sh
        printf '#!/bin/sh\ntouch "%s"\nexit 0\n' "$report/unreviewed-executed" > "$corrupt/$file"
    else
        file=runner/target/evaluation/bin/eval-world
        chmod u+w "$corrupt/$file"
        printf 'unreviewed helper\n' >> "$corrupt/$file"
    fi
    runner_identity "$corrupt/runner" > "$report/unreviewed-$mode.sha256"
    runner_sha=$(sha256sum < "$report/unreviewed-$mode.sha256"); runner_sha=${runner_sha%% *}
    jq --arg sha "$runner_sha" '.runner_sha256=$sha' "$binding_root/bindings.json" > "$corrupt/bindings.json"
    unreviewed_sha=$(sha256sum < "$corrupt/bindings.json"); unreviewed_sha=${unreviewed_sha%% *}
    if bash "$root/scripts/evaluation/run-workload.sh" "$corrupt" "$unreviewed_sha" output-only-overflow baseline > "$report/unreviewed-$mode.out" 2> "$report/unreviewed-$mode.err"; then
        echo "executed a self-consistent but unreviewed controller: $mode" >&2; exit 1
    fi
    run=$(run_path "$report/unreviewed-$mode.out")
    jq -e '.status=="FAIL" and .world_receipt==null' "$run/summary.json" >/dev/null
    [[ ! -e $report/unreviewed-executed && ! -e $run/world.out ]]
    cp -p --remove-destination "$binding_root/$file" "$corrupt/$file"
    cp "$binding_root/bindings.json" "$corrupt/bindings.json"
    passed=$((passed+1))
done
for variant in baseline candidate; do
    jq '.features=[]' "$binding_root/selections/$variant.json" > "$corrupt/selections/$variant.json"
    artifact_sha=$(jq -Sc '.members|=map(del(.path))|.assets|=map(del(.path))' "$corrupt/selections/$variant.json" | sha256sum | cut -d' ' -f1)
    jq --arg variant "$variant" --arg sha "$artifact_sha" '.artifacts[$variant]=$sha' "$binding_root/bindings.json" > "$corrupt/bindings.json"
    if (( ${#observer_modes[@]} )); then
        for paired in baseline candidate; do
            jq '.features=[]' "$binding_root/selections/$paired.json" > "$corrupt/selections/$paired.json"
        done
        jq --arg sha "$artifact_sha" '.artifacts={baseline:$sha,candidate:$sha}' "$binding_root/bindings.json" > "$corrupt/bindings.json"
    fi
    missing_sha=$(sha256sum < "$corrupt/bindings.json"); missing_sha=${missing_sha%% *}
    code=0
    bash "$root/scripts/evaluation/run-workload.sh" "$corrupt" "$missing_sha" output-only-overflow "$variant" > "$report/missing-$variant.out" 2> "$report/missing-$variant.err" || code=$?
    run=$(run_path "$report/missing-$variant.out")
    if [[ $variant == baseline ]]; then
        [[ $code == 0 ]]
        jq -e '.status=="NOT_RUN" and .failure=="unsupported_features" and .world_receipt==null' "$run/summary.json" >/dev/null
    else
        [[ $code != 0 ]]
        jq -e '.status=="FAIL" and .world_receipt==null' "$run/summary.json" >/dev/null
    fi
    [[ ! -e $run/world.out ]]
    cp "$binding_root/selections/$variant.json" "$corrupt/selections/$variant.json"
    if (( ${#observer_modes[@]} )); then
        for paired in baseline candidate; do cp "$binding_root/selections/$paired.json" "$corrupt/selections/$paired.json"; done
    fi
    cp "$binding_root/bindings.json" "$corrupt/bindings.json"
    passed=$((passed+1))
done
jq '(.tasks[]|select(.id=="output-only-overflow")|.max_provider_attempts)=2' "$binding_root/manifest/input" > "$corrupt/manifest/input"
printf '2\n' > "$corrupt/fixtures/output-only-overflow/provider-attempt-limit.txt"
printf '2\n' > "$corrupt/fixtures/output-only-overflow/client-attempt-limit.txt"
manifest_sha=$(sha256sum < "$corrupt/manifest/input"); manifest_sha=${manifest_sha%% *}
tree_identity "$corrupt/fixtures/output-only-overflow" > "$report/limited-fixture.tree"
fixture_sha=$(sha256sum < "$report/limited-fixture.tree"); fixture_sha=${fixture_sha%% *}
jq --arg manifest "$manifest_sha" --arg fixture "$fixture_sha" '.manifest_sha256=$manifest|
    (.tasks[]|select(.id=="output-only-overflow")|.fixture_sha256)=$fixture' "$binding_root/bindings.json" > "$corrupt/bindings.json"
limited_sha=$(sha256sum < "$corrupt/bindings.json"); limited_sha=${limited_sha%% *}
bash "$root/scripts/evaluation/run-workload.sh" "$corrupt" "$limited_sha" output-only-overflow baseline > "$report/limited.out" 2> "$report/limited.err"
run=$(run_path "$report/limited.out")
jq -e '.status=="WORKLOAD_CHECKED"' "$run/summary.json" >/dev/null
world="$run/$(jq -er .world_receipt "$run/summary.json")"
jq -se '.[0].limit==2 and .[-1].admitted==2 and .[-1].responses==2' "$world/receipt/evidence/meter.jsonl" >/dev/null
passed=$((passed+1))
jq '(.tasks[]|select(.id=="output-only-overflow")|.max_provider_attempts)=1' "$binding_root/manifest/input" > "$corrupt/manifest/input"
printf '1\n' > "$corrupt/fixtures/output-only-overflow/provider-attempt-limit.txt"
printf '1\n' > "$corrupt/fixtures/output-only-overflow/client-attempt-limit.txt"
manifest_sha=$(sha256sum < "$corrupt/manifest/input"); manifest_sha=${manifest_sha%% *}
tree_identity "$corrupt/fixtures/output-only-overflow" > "$report/capped-fixture.tree"
fixture_sha=$(sha256sum < "$report/capped-fixture.tree"); fixture_sha=${fixture_sha%% *}
jq --arg manifest "$manifest_sha" --arg fixture "$fixture_sha" '.manifest_sha256=$manifest|
    (.tasks[]|select(.id=="output-only-overflow")|.fixture_sha256)=$fixture' "$binding_root/bindings.json" > "$corrupt/bindings.json"
capped_sha=$(sha256sum < "$corrupt/bindings.json"); capped_sha=${capped_sha%% *}
for variant in baseline candidate; do
    if bash "$root/scripts/evaluation/run-workload.sh" "$corrupt" "$capped_sha" output-only-overflow "$variant" > "$report/capped-$variant.out" 2> "$report/capped-$variant.err"; then
        echo 'accepted a workload requiring more than its attempt cap' >&2; exit 1
    fi
    run=$(run_path "$report/capped-$variant.out")
    jq -e '.status=="FAIL" and .failure=="attempt_limit" and .exit_code!=0' "$run/summary.json" >/dev/null
    jq -e '.status=="ATTEMPT_LIMIT_CONFIRMED" and .provider_attempts==1 and .rejected_reservations==1 and .limit==1' "$run/client-limit.json" >/dev/null
    jq -e '.cleanup_confirmed and .leaked_processes==0 and .timed_out==false' "$run/control.json" >/dev/null
    world="$run/$(jq -er .world_receipt "$run/summary.json")"
    jq -se '[.[]|select(.event=="admit")|.attempt]==[1]' "$world/receipt/evidence/meter.jsonl" >/dev/null
    passed=$((passed+1))
done
jq '(.tasks[]|select(.id=="child-work")|.timeout_seconds)=1' "$binding_root/manifest/input" > "$corrupt/manifest/input"
manifest_sha=$(sha256sum < "$corrupt/manifest/input"); manifest_sha=${manifest_sha%% *}
jq --arg manifest "$manifest_sha" '.manifest_sha256=$manifest' "$binding_root/bindings.json" > "$corrupt/bindings.json"
timeout_sha=$(sha256sum < "$corrupt/bindings.json"); timeout_sha=${timeout_sha%% *}
if bash "$root/scripts/evaluation/run-workload.sh" "$corrupt" "$timeout_sha" child-work baseline > "$report/timeout.out" 2> "$report/timeout.err"; then
    echo 'accepted a timed-out bound workload' >&2; exit 1
fi
run=$(run_path "$report/timeout.out")
jq -e '.status=="FAIL" and .failure=="prompt_timeout"' "$run/summary.json" >/dev/null
jq -e '.timed_out and .cleanup_confirmed and .limit_ms==1000' "$run/control.json" >/dev/null
if jq -e '.world_receipt!=null' "$run/summary.json" >/dev/null; then
    world="$run/$(jq -er .world_receipt "$run/summary.json")"
    jq -e '.cleanup_confirmed' "$world/receipt/outer.json" >/dev/null
fi
passed=$((passed+1))
for mode in interrupt changed-after-launch; do
    bash "$root/scripts/evaluation/run-workload.sh" "$binding_root" "$binding_sha" child-work baseline > "$report/$mode.out" 2> "$report/$mode.err" &
    running=$!
    ready= run=
    for _ in {1..1000}; do
        kill -0 "$running"
        run=$(sed -n 's/^Evaluation workload receipt: //p' "$report/$mode.out")
        if [[ -n $run ]]; then
            for path in "$run"/selected/runner/target/evaluation/world-*/receipt/bwrap-info.json; do
                if [[ -s $path ]] && jq -e '.["child-pid"]>0' "$path" >/dev/null 2>&1; then ready=${path%/bwrap-info.json}; break; fi
            done
        fi
        [[ -z $ready ]] || break
        sleep 0.02
    done
    [[ -n $ready ]]
    if [[ $mode == interrupt ]]; then kill -TERM "$running";
    else printf 'changed after launch\n' >> "$run/selected/fixtures/child-work/prompt.txt"; fi
    code=0; wait "$running" || code=$?
    running=
    [[ $code != 0 ]]
    if [[ $mode == interrupt ]]; then
        [[ $code == 143 ]]
        jq -e '.status=="FAIL" and .failure=="interrupted" and .world_receipt!=null' "$run/summary.json" >/dev/null
        jq -e '.interrupted==15 and .cleanup_confirmed' "$ready/outer.json" >/dev/null
    else
        jq -e '.status=="FAIL" and .failure=="input_mismatch"' "$run/summary.json" >/dev/null
        [[ -s $run/after-integrity.log ]]
    fi
    passed=$((passed+1))
done
sha256sum -c "$binding_root/inputs.sha256" > "$report/original-integrity.log"
printf 'Evaluation execution checks passed: %s\n' "$passed"
[[ ! -s $report/workload-failures.jsonl ]]
