#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/client-attempt-tests-XXXXXXXX")
mkdir "$report/input"
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" \
      '{schema:1,scope:"evaluation-client-attempt-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$passed,workers_started:0}' > "$report/summary.json"
    printf 'Evaluation client attempt test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
jq -nc '{schema:1,scope:"offline-client-admission",event:"start",limit:2,max_peers:8,max_frame_bytes:128,max_calls:128,frame_timeout_ms:250},
 {event:"admit",attempt:1,peer_pid:10},{event:"admit",attempt:2,peer_pid:11},
 {event:"terminal",status:"STOPPED",admitted:2,calls:2}' > "$report/base.jsonl"
for mode in normal empty shared-pid unknown missing-terminal extra-terminal failed cap sequence duplicate-event extra-field pid fractional unsafe duplicate-key nul blank unterminated symlink hardlink oversized; do
    cp "$report/base.jsonl" "$report/input/client-attempts.jsonl"
    filter= expected=fail
    case $mode in
        normal) expected=pass ;;
        empty) filter='[.[0],(.[-1]|.admitted=0|.calls=0)]'; expected=pass ;;
        shared-pid) filter='.[2].peer_pid=10'; expected=pass ;;
        unknown) filter='.[1].event="verbs"' ;;
        missing-terminal) filter='.[0:-1]' ;;
        extra-terminal) filter='.+[.[-1]]' ;;
        failed) filter='.[-1].status="FAIL"' ;;
        cap) filter='.[0].limit=1' ;;
        sequence) filter='.[2].attempt=3' ;;
        duplicate-event) filter='.[2]=.[1]' ;;
        extra-field) filter='.[1].extra=true' ;;
        pid) filter='.[1].peer_pid=0' ;;
        fractional) filter='.[1].attempt=1.5' ;;
        unsafe) sed 's/"attempt":1/"attempt":9007199254740993/' "$report/base.jsonl" > "$report/input/client-attempts.jsonl" ;;
        duplicate-key) sed 's/"attempt":1/"attempt":1,"attempt":1/' "$report/base.jsonl" > "$report/input/client-attempts.jsonl" ;;
        nul) printf '\0' >> "$report/input/client-attempts.jsonl" ;;
        blank) printf '\n' >> "$report/input/client-attempts.jsonl" ;;
        unterminated) truncate -s -1 "$report/input/client-attempts.jsonl" ;;
        symlink) rm "$report/input/client-attempts.jsonl"; ln -s "$report/base.jsonl" "$report/input/client-attempts.jsonl" ;;
        hardlink) ln "$report/input/client-attempts.jsonl" "$report/input/alias" ;;
        oversized) truncate -s 65537 "$report/input/client-attempts.jsonl" ;;
    esac
    if [[ -n $filter ]]; then jq -sc "$filter|.[]" "$report/base.jsonl" > "$report/input/client-attempts.jsonl"; fi
    code=0
    bash "$root/scripts/evaluation/client-attempts.sh" "$report/input" 2 > "$report/$mode.out" 2> "$report/$mode.err" || code=$?
    receipt=$(sed -n 's/^Evaluation client attempts: //p' "$report/$mode.out")
    [[ -d $receipt ]]
    if [[ $expected == pass ]]; then
        [[ $code == 0 ]]
        jq -e '.status=="ATTEMPTS_MEASURED" and .provider_attempts<=.limit' "$receipt/result.json" >/dev/null
        if [[ $mode == empty ]]; then jq -e '.provider_attempts==0 and .peer_pids==[]' "$receipt/result.json" >/dev/null
        else jq -e '.provider_attempts==2' "$receipt/result.json" >/dev/null; fi
    else
        [[ $code != 0 && ! -e $receipt/result.json ]]
        jq -e '.status=="FAIL" and .exit_code!=0' "$receipt/summary.json" >/dev/null
    fi
    rm -f "$report/input/client-attempts.jsonl" "$report/input/alias"
    passed=$((passed+1))
done
jq -sc '.[0:-1]+[{event:"reject",reason:"attempt_limit",peer_pid:12},(.[-1]|.status="FAIL"|.calls=3)]|.[]' \
    "$report/base.jsonl" > "$report/limited.jsonl"
for mode in confirmed maximum success missing-terminal wrong-status wrong-reason premature reversed duplicate-reject \
    admit-after-reject calls mismatch-limit extra-field zero-pid fractional duplicate-key symlink hardlink; do
    cp "$report/limited.jsonl" "$report/input/client-attempts.jsonl"
    filter= limit=2 expected=fail
    case $mode in
        confirmed) expected=pass ;;
        maximum)
            jq -nc '{schema:1,scope:"offline-client-admission",event:"start",limit:64,max_peers:8,max_frame_bytes:128,max_calls:128,frame_timeout_ms:250},
              (range(1;65)|{event:"admit",attempt:.,peer_pid:10}),{event:"reject",reason:"attempt_limit",peer_pid:12},
              {event:"terminal",status:"FAIL",admitted:64,calls:65}' > "$report/input/client-attempts.jsonl"
            limit=64; expected=pass ;;
        success) cp "$report/base.jsonl" "$report/input/client-attempts.jsonl" ;;
        missing-terminal) filter='.[0:-1]' ;;
        wrong-status) filter='.[-1].status="STOPPED"' ;;
        wrong-reason) filter='.[-2].reason="transport"' ;;
        premature) filter='del(.[2])' ;;
        reversed) filter='.[1:4]|=reverse' ;;
        duplicate-reject) filter='.[0:-1]+[.[-2],.[-1]]' ;;
        admit-after-reject) filter='.[2:4]|=reverse' ;;
        calls) filter='.[-1].calls=4' ;;
        mismatch-limit) limit=1 ;;
        extra-field) filter='.[-2].extra=true' ;;
        zero-pid) filter='.[-2].peer_pid=0' ;;
        fractional) filter='.[1].attempt=1.5' ;;
        duplicate-key) sed 's/"reason":"attempt_limit"/"reason":"attempt_limit","reason":"attempt_limit"/' "$report/limited.jsonl" > "$report/input/client-attempts.jsonl" ;;
        symlink) rm "$report/input/client-attempts.jsonl"; ln -s "$report/limited.jsonl" "$report/input/client-attempts.jsonl" ;;
        hardlink) ln "$report/input/client-attempts.jsonl" "$report/input/alias" ;;
    esac
    if [[ -n $filter ]]; then jq -sc "$filter|.[]" "$report/limited.jsonl" > "$report/input/client-attempts.jsonl"; fi
    code=0
    bash "$root/scripts/evaluation/client-attempts.sh" "$report/input" "$limit" limit-failure \
      > "$report/limit-$mode.out" 2> "$report/limit-$mode.err" || code=$?
    receipt=$(sed -n 's/^Evaluation client attempts: //p' "$report/limit-$mode.out")
    [[ -d $receipt ]]
    if [[ $expected == pass ]]; then
        [[ $code == 0 ]]
        jq -e --argjson limit "$limit" '.status=="ATTEMPT_LIMIT_CONFIRMED" and .failure=="attempt_limit" and
          .provider_attempts==$limit and .limit==$limit and .rejected_reservations==1 and .complete_run==false' "$receipt/result.json" >/dev/null
        if bash "$root/scripts/evaluation/client-attempts.sh" "$report/input" "$limit" > "$report/limit-$mode-success.out" 2>&1; then
            echo 'limit rejection accepted as successful measurement' >&2; exit 1
        fi
    else
        [[ $code != 0 && ! -e $receipt/result.json ]]
        jq -e '.status=="FAIL"' "$receipt/summary.json" >/dev/null
    fi
    rm -f "$report/input/client-attempts.jsonl" "$report/input/alias"
    passed=$((passed+1))
done
printf 'Evaluation client attempt checks passed: %s\n' "$passed"
