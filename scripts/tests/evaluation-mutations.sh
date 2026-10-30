#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ ( $# == 3 || $# == 5 ) && $2 =~ ^[0-9a-f]{64}$ && ( $3 == baseline || $3 == candidate ) ]] || {
    echo 'usage: evaluation-mutations.sh DESCRIPTOR SHA256 baseline|candidate [GRAMMAR SHA256]' >&2; exit 2;
}
descriptor=$1 artifact_sha=$2 variant=$3
tasks=(small-bug-fix large-file-edit)
grammar_args=()
score_args=()
grammar_sha=
if [[ $# == 5 ]]; then
    [[ -n $4 && $5 =~ ^[0-9a-f]{64}$ ]] || exit 2
    tasks=(read-index-select-edit)
    grammar_args=(--rust-grammar "$4" "$5")
    grammar_sha=$5
    score_args=("$5")
fi
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
mkdir -p "$root/target/evaluation"
report=$(mktemp -d "$root/target/evaluation/mutation-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" --arg artifact "$artifact_sha" --arg variant "$variant" --arg grammar "$grammar_sha" \
        '{schema:1,scope:"evaluation-mutation-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,
          checks:$passed,artifact_sha256:$artifact,variant:$variant,rust_grammar_sha256:(if $grammar=="" then null else $grammar end),live_requests:0}' > "$report/summary.json"
    printf 'Evaluation mutation test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
provider=melchior/target/release/examples/fake-provider
provider_sha=$(sha256sum < "$root/$provider"); provider_sha=${provider_sha%% *}
for task in "${tasks[@]}"; do
    fixture="$report/$task/fixture"
    mkdir -p "$fixture"
    cp -R "$root/scripts/evaluation/fixtures/$task/." "$fixture/"
    cp "$root/scripts/evaluation/family-common.sh" "$fixture/family-common.sh"
    cp "$root/scripts/evaluation/mutation-workload.sh" "$fixture/driver.sh"
    code=0
    bash "$root/scripts/evaluation/world.sh" "$root" "${fixture#"$root/"}" 60000 \
        --provider "$provider" "$provider_sha" \
        --artifact "$descriptor" scripts/evaluation/manifests/offline.json "$variant" "$artifact_sha" \
        "${grammar_args[@]}" \
        /runner/bin/bash /input/driver.sh "$task" > "$report/$task/world.out" 2> "$report/$task/world.err" || code=$?
    world=$(sed -n 's/^Evaluation world evidence: //p' "$report/$task/world.out")
    [[ -n $world ]]
    score=0
    bash "$root/scripts/evaluation/score-mutation.sh" "$task" "$world/input" "$world/receipt" "${score_args[@]}" \
        > "$report/$task/checks.json" 2> "$report/$task/checks.err" || score=$?
    [[ $code == 0 && $score == 0 ]]
    jq -e --arg sha "$artifact_sha" '.status=="WORLD_COMPLETED" and .artifact_sha256==$sha' "$world/summary.json" >/dev/null
    edit_index=4 final_index=5
    modes=(reverted unrelated truncated tool-error usage leak empty-journal missing-proof symlink hardlink)
    if [[ $task == read-index-select-edit ]]; then
        edit_index=6 final_index=7
        jq -e --arg sha "$grammar_sha" '.rust_grammar_sha256==$sha' "$world/summary.json" >/dev/null
        [[ $(cat "$world/receipt/evidence/rust-grammar.sha256") == "$grammar_sha  -" ]]
        modes+=(wrong-symbol false-index wrong-span wrong-grammar missing-grammar wrong-prompt)
    fi
    (cd "$world/receipt/evidence" && sha256sum -c config.sha256) > "$report/$task/config-integrity.log"
    passed=$((passed+1))
    for mode in "${modes[@]}"; do
        corrupt="$report/$task/corrupt-$mode"
        cp -R "$world/receipt" "$corrupt"
        case $mode in
            reverted) cp "$world/input/work/src/lib.rs" "$corrupt/work/work/src/lib.rs" ;;
            unrelated) printf 'corrupt\n' >> "$corrupt/work/work/stable.txt" ;;
            truncated) head -n2 "$world/receipt/work/work/src/lib.rs" > "$corrupt/work/work/src/lib.rs" ;;
            tool-error) jq --argjson i "$edit_index" '.result[$i].raw|=(fromjson|.entry.result.is_error=true|tojson)' "$world/receipt/evidence/replay.json" > "$corrupt/evidence/replay.json" ;;
            usage) jq --argjson i "$final_index" '.result[$i].raw|=(fromjson|.entry.usage.output=0|tojson)' "$world/receipt/evidence/replay.json" > "$corrupt/evidence/replay.json" ;;
            wrong-symbol) sed '6s/attempt.saturating_mul(2)/2_u32.saturating_pow(attempt).min(64)/' "$world/receipt/work/work/src/lib.rs" > "$corrupt/work/work/src/lib.rs" ;;
            false-index) jq '.result[2].raw|=(fromjson|.entry.result.output="no index"|tojson)' "$world/receipt/evidence/replay.json" > "$corrupt/evidence/replay.json" ;;
            wrong-span) jq '.result[4].raw|=(fromjson|.entry.args=({path:"src/lib.rs",offset:5,limit:3}|tojson)|tojson)' "$world/receipt/evidence/replay.json" > "$corrupt/evidence/replay.json" ;;
            wrong-grammar) printf '%064d  -\n' 0 > "$corrupt/evidence/rust-grammar.sha256" ;;
            missing-grammar) rm "$corrupt/evidence/rust-grammar.sha256" ;;
            wrong-prompt) jq '.result[0].raw|=(fromjson|.entry.text="different task"|tojson)' "$world/receipt/evidence/replay.json" > "$corrupt/evidence/replay.json" ;;
            leak) jq '.leaked_processes=1' "$world/receipt/inside.json" > "$corrupt/inside.json" ;;
            empty-journal) jq '.n=0|.result=[]' "$world/receipt/evidence/replay.json" > "$corrupt/evidence/replay.json" ;;
            symlink)
                rm "$corrupt/work/work/src/lib.rs"
                ln -s "$world/receipt/work/work/src/lib.rs" "$corrupt/work/work/src/lib.rs" ;;
            hardlink) ln "$corrupt/work/work/stable.txt" "$corrupt/work/work/alias.txt" ;;
            missing-proof)
                if [[ $task != large-file-edit ]]; then rm "$corrupt/evidence/tests-before.log";
                else printf 'extra\n' > "$corrupt/work/work/unexpected.txt"; fi ;;
        esac
        if bash "$root/scripts/evaluation/score-mutation.sh" "$task" "$world/input" "$corrupt" "${score_args[@]}" \
            > "$report/$task/$mode.json" 2> "$report/$task/$mode.err"; then
            echo "accepted corrupted $task evidence: $mode" >&2; exit 1
        fi
        jq -e '.status=="FAIL" and any(.checks[]; .status=="FAIL")' "$report/$task/$mode.json" >/dev/null
        passed=$((passed+1))
    done
done
if [[ -n $grammar_sha ]]; then
    grammar=$4
    artifact_args=(--artifact "$descriptor" scripts/evaluation/manifests/offline.json "$variant" "$artifact_sha")
    mkdir "$report/grammar-inputs"
    cp "$root/$grammar" "$report/grammar-inputs/hardlink"
    ln "$report/grammar-inputs/hardlink" "$report/grammar-inputs/alias"
    ln -s "$root/$grammar" "$report/grammar-inputs/symlink"
    printf 'not an ELF executable\n' > "$report/grammar-inputs/not-elf"
    non_elf_sha=$(sha256sum < "$report/grammar-inputs/not-elf"); non_elf_sha=${non_elf_sha%% *}
    for mode in wrong-digest symlink hardlink not-elf missing empty duplicate no-artifact bad-digest unselected; do
        selection=(--rust-grammar "$grammar" "$grammar_sha")
        artifacts=("${artifact_args[@]}")
        expected=1
        prelaunch=true
        case $mode in
            wrong-digest) selection=(--rust-grammar "$grammar" "$(printf '%064d' 0)") ;;
            symlink|hardlink|missing) selection=(--rust-grammar "${report#"$root/"}/grammar-inputs/$mode" "$grammar_sha") ;;
            not-elf) selection=(--rust-grammar "${report#"$root/"}/grammar-inputs/not-elf" "$non_elf_sha") ;;
            empty) selection=(--rust-grammar '' "$grammar_sha"); expected=2 ;;
            duplicate) selection+=("${selection[@]}"); expected=2 ;;
            no-artifact) artifacts=(); expected=2 ;;
            bad-digest) selection=(--rust-grammar "$grammar" bad); expected=2 ;;
            unselected) selection=(); prelaunch=false ;;
        esac
        code=0
        bash "$root/scripts/evaluation/world.sh" "$root" "${fixture#"$root/"}" 60000 \
            "${artifacts[@]}" "${selection[@]}" /runner/bin/bash /input/driver.sh read-index-select-edit \
            > "$report/grammar-$mode.out" 2> "$report/grammar-$mode.err" || code=$?
        [[ $code == "$expected" ]]
        refused=$(sed -n 's/^Evaluation world evidence: //p' "$report/grammar-$mode.out")
        if [[ $expected == 2 ]]; then
            [[ -z $refused ]]
        else
            [[ -n $refused ]]
            jq -e '.status=="FAIL" and .rust_grammar_sha256==null' "$refused/summary.json" >/dev/null
            if [[ $prelaunch == true ]]; then
                [[ ! -e $refused/receipt/outer.json && ! -e $refused/receipt/inside.json ]]
            else
                jq -e '.cleanup_confirmed and (.timed_out|not)' "$refused/receipt/outer.json" >/dev/null
                jq -e '.leaked_processes==0 and .remaining_processes==0 and .exported' "$refused/receipt/inside.json" >/dev/null
                [[ ! -e $refused/receipt/evidence/requests.jsonl && ! -e $refused/receipt/evidence/magi.exit ]]
            fi
        fi
        passed=$((passed+1))
    done
fi
printf 'Evaluation mutation checks passed: %s\n' "$passed"
