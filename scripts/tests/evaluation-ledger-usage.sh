#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# -le 1 ]]
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/ledger-usage-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson checks "$passed" \
        '{schema:1,scope:"evaluation-ledger-usage-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$checks}' > "$report/summary.json"
    printf 'Evaluation ledger usage test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
mkdir "$report/base" "$report/evidence"
printf '{"family":1,"ok":true,"n":2,"result":[{"id":"alpha"},{"id":"beta"}]}\n' > "$report/base/sessions.json"
printf '{"chat":"alpha","anthropic":"beta"}\n' > "$report/base/ledger-runs.json"
printf '7\n' > "$report/base/ledger-0.txt"
printf '9\n' > "$report/base/ledger-1.txt"
printf '0\n' > "$report/base/chat.exit"
printf '0\n' > "$report/base/anthropic.exit"
run() {
    local name=$1 task=$2 evidence=$3 expected=$4 charge=${5:-0} code=0
    bash "$root/scripts/evaluation/ledger-usage.sh" "$task" "$evidence" "$report/$name" > "$report/$name.out" 2> "$report/$name.err" || code=$?
    if [[ $expected == pass ]]; then
        [[ $code == 0 ]]
        jq -e --argjson charge "$charge" '.status=="LEDGERS_EXTRACTED" and .charged_micros==$charge and
          .complete_run==false and .settlement_verified==false and .reported_micros==null and
          .estimated_micros==null and .input_tokens==null and .output_tokens==null and
          .cache_read_tokens==null and .cache_write_tokens==null' "$report/$name/result.json" >/dev/null
    else [[ $code != 0 && ! -e $report/$name/result.json ]]; fi
    passed=$((passed+1))
}
for mode in normal zero maximum leading-zero negative decimal exponent spaces extra-line missing-newline carriage-return nul overflow sum-overflow empty missing symlink collision wrong-session duplicate-session session-count failed-exit bad-exit duplicate-key extra-key unsafe-identity; do
    cp "$report/base/"* "$report/evidence/"
    expected=fail charge=16
    case $mode in
        normal) expected=pass ;;
        zero) printf '0\n' > "$report/evidence/ledger-0.txt"; expected=pass; charge=9 ;;
        maximum) printf '9007199254740991\n' > "$report/evidence/ledger-0.txt"; printf '0\n' > "$report/evidence/ledger-1.txt"; expected=pass; charge=9007199254740991 ;;
        leading-zero) printf '07\n' > "$report/evidence/ledger-0.txt" ;;
        negative) printf '%s\n' -7 > "$report/evidence/ledger-0.txt" ;;
        decimal) printf '7.0\n' > "$report/evidence/ledger-0.txt" ;;
        exponent) printf '7e0\n' > "$report/evidence/ledger-0.txt" ;;
        spaces) printf ' 7\n' > "$report/evidence/ledger-0.txt" ;;
        extra-line) printf '7\n\n' > "$report/evidence/ledger-0.txt" ;;
        missing-newline) printf '7' > "$report/evidence/ledger-0.txt" ;;
        carriage-return) printf '7\r\n' > "$report/evidence/ledger-0.txt" ;;
        nul) printf '7\0\n' > "$report/evidence/ledger-0.txt" ;;
        overflow) printf '9007199254740992\n' > "$report/evidence/ledger-0.txt" ;;
        sum-overflow) printf '9007199254740991\n' > "$report/evidence/ledger-0.txt" ;;
        empty) : > "$report/evidence/ledger-0.txt" ;;
        missing) rm "$report/evidence/ledger-0.txt" ;;
        symlink) rm "$report/evidence/ledger-0.txt"; ln -s "$report/base/ledger-0.txt" "$report/evidence/ledger-0.txt" ;;
        collision) printf '{"chat":"alpha","anthropic":"alpha"}\n' > "$report/evidence/ledger-runs.json" ;;
        wrong-session) sed s/beta/gamma/ "$report/base/sessions.json" > "$report/evidence/sessions.json" ;;
        duplicate-session) sed s/beta/alpha/ "$report/base/sessions.json" > "$report/evidence/sessions.json" ;;
        session-count) jq '.n=1' "$report/base/sessions.json" > "$report/evidence/sessions.json" ;;
        failed-exit) printf '1\n' > "$report/evidence/chat.exit" ;;
        bad-exit) printf '00\n' > "$report/evidence/chat.exit" ;;
        duplicate-key) printf '{"chat":"alpha","chat":"alpha","anthropic":"beta"}\n' > "$report/evidence/ledger-runs.json" ;;
        extra-key) jq '.extra=1' "$report/base/ledger-runs.json" > "$report/evidence/ledger-runs.json" ;;
        unsafe-identity) printf '{"chat":"../alpha","anthropic":"beta"}\n' > "$report/evidence/ledger-runs.json" ;;
    esac
    run "$mode" cache-accounting "$report/evidence" "$expected" "$charge"
    if [[ $mode == normal ]]; then cmp "$report/base/ledger-0.txt" "$report/$mode/inputs/ledger-0.txt/input"; fi
    rm -f "$report/evidence/"*
done
mkdir "$report/resume-base"
cp "$report/base/sessions.json" "$report/resume-base/sessions.json"
jq -nc '[{phase:"initial",transcript:"alpha",coordination_run:"alpha",exit_code:0},
  {phase:"distractor",transcript:"beta",coordination_run:"beta",exit_code:0},
  {phase:"latest",transcript:"beta",coordination_run:"gamma",exit_code:0},
  {phase:"named",transcript:"alpha",coordination_run:"delta",exit_code:0}][]' > "$report/resume-base/phases.jsonl"
number=0
for phase in initial distractor latest named; do number=$((number+1)); printf '%s\n' "$number" > "$report/resume-base/ledger-$phase.txt"; done
for mode in resumed reversed reused-run wrong-history failed-phase missing-phase unterminated-phase nul-phase; do
    cp "$report/resume-base/"* "$report/evidence/"
    expected=fail filter=
    case $mode in
        resumed) expected=pass ;;
        reversed) filter='reverse' ;;
        reused-run) filter='.[3].coordination_run="alpha"' ;;
        wrong-history) filter='.[3].transcript="beta"' ;;
        failed-phase) filter='.[3].exit_code=1' ;;
        missing-phase) filter='.[0:3]' ;;
        unterminated-phase) truncate -s -1 "$report/evidence/phases.jsonl" ;;
        nul-phase) { printf '\0'; cat "$report/resume-base/phases.jsonl"; } > "$report/evidence/phases.jsonl" ;;
    esac
    if [[ -n $filter ]]; then jq -sc "$filter|.[]" "$report/resume-base/phases.jsonl" > "$report/evidence/phases.jsonl"; fi
    run "$mode" resume "$report/evidence" "$expected" 10
    rm -f "$report/evidence/"*
done
mkdir "$report/child-base"
printf '{"family":1,"ok":true,"n":2,"result":[{"id":"alpha"},{"id":"alpha@child"}]}\n' > "$report/child-base/sessions.json"
printf '{"run":"alpha","parent":"parent","child":"child","child_transcript":"alpha@child","child_pid":123,"report_file":"child.report"}\n' > "$report/child-base/identities.json"
printf '7\n' > "$report/child-base/ledger.txt"
printf '0\n' > "$report/child-base/magi.exit"
for mode in child shared-charge wrong-child failed-owner; do
    cp "$report/child-base/"* "$report/evidence/"
    expected=fail
    case $mode in
        child|shared-charge) expected=pass ;;
        wrong-child) jq '.child_transcript="alpha@other"' "$report/child-base/identities.json" > "$report/evidence/identities.json" ;;
        failed-owner) printf '1\n' > "$report/evidence/magi.exit" ;;
    esac
    run "$mode" child-work "$report/evidence" "$expected" 7
    if [[ $mode == shared-charge ]]; then jq -e '(.captures|length)==1 and (.captures[0].transcripts|length)==2' "$report/$mode/result.json" >/dev/null; fi
    rm -f "$report/evidence/"*
done
run unsupported small-bug-fix "$report/base" fail
if [[ $# == 1 ]]; then
    for task in cache-accounting resume child-work; do
        run_path=$(sed -n 's/^Evaluation bound workload: //p' "$1/$task.out")
        [[ -d $run_path ]]
        world=$(jq -er .world_receipt "$run_path/summary.json")
        case $task in cache-accounting) charge=951;; resume) charge=804;; child-work) charge=1546;; esac
        run "retained-$task" "$task" "$run_path/$world/receipt/evidence" pass "$charge"
    done
fi
printf 'Evaluation ledger usage checks passed: %s\n' "$passed"
