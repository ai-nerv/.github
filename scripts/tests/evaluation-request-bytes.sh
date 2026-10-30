#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# -le 1 ]]
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/request-byte-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson checks "$passed" \
        '{schema:1,scope:"evaluation-request-byte-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$checks}' > "$report/summary.json"
    printf 'Evaluation request byte test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
mkdir "$report/base" "$report/evidence"
printf '{\n "message": "é\\n界", "value": 1\n}\n' > "$report/first"
printf '{ "second": "escaped \\\" quote" }' > "$report/second"
build() {
    local n m h1 h2
    n=$(wc -c < "$report/first"); m=$(wc -c < "$report/second")
    h1=$(sha256sum < "$report/first"); h1=${h1%% *}
    h2=$(sha256sum < "$report/second"); h2=${h2%% *}
    { cat "$report/second"; printf '\n'; cat "$report/first"; printf '\n'; } > "$report/base/requests.jsonl"
    jq -nc --argjson n "$n" --argjson m "$m" --arg h1 "$h1" --arg h2 "$h2" '
      {schema:2,scope:"offline-provider-admission",event:"start",limit:64,capture_limit_bytes:8388608,journal_limit_bytes:131072},
      {event:"admit",attempt:1},{event:"admit",attempt:2},
      {event:"reserve_capture",attempt:1,bytes:$n,reserved_bytes:($n+1)},
      {event:"reserve_capture",attempt:2,bytes:$m,reserved_bytes:($n+$m+2)},
      {event:"body",attempt:2,bytes:$m,sha256:$h2},{event:"body",attempt:1,bytes:$n,sha256:$h1},
      {event:"response",attempt:1,turn:0},{event:"response",attempt:2,turn:0},
      {event:"terminal",status:"STOPPED",reason:"stopped",admitted:2,rejected:0,responses:2,incomplete:0,
       reserved_bytes:($n+$m+2),captured_bytes:($n+$m+2)}' > "$report/base/meter.jsonl"
}
run() {
    local name=$1 expected=$2 evidence=$3 code=0 receipt
    bash "$root/scripts/evaluation/request-bytes.sh" "$evidence" > "$report/$name.out" 2> "$report/$name.err" || code=$?
    receipt=$(sed -n 's/^Evaluation request bytes: //p' "$report/$name.out")
    [[ -d $receipt ]]
    if [[ $expected == pass ]]; then
        [[ $code == 0 ]]
        jq -e '.status=="BYTES_MEASURED" and .exit_code==0 and .complete_run==false and .workers_started==0 and .live_requests==0' "$receipt/summary.json" >/dev/null
        jq -e '.provider_attempts==null and .stable_prefix_bytes==null and .complete_run==false and
          .captured_bytes==(.request_bytes+.delimiter_bytes) and .delimiter_bytes==.provider_received' "$receipt/result.json" >/dev/null
        cmp "$evidence/requests.jsonl" "$receipt/requests/input"
    else
        [[ $code != 0 && ! -e $receipt/result.json ]]
        jq -e '.status=="FAIL" and .exit_code!=0 and .request_bytes==null' "$receipt/summary.json" >/dev/null
    fi
    passed=$((passed+1))
    last_receipt=$receipt
}
build
for mode in normal barrier empty-capture empty-body large tampered delimiter appended short hash length counters duplicate-body missing-body missing-response early-response admission reservation unknown failed incomplete cap limit turn extra fractional unsafe-integer duplicate-key unterminated nul blank missing-meter symlink barrier-unreleased barrier-name release-first duplicate-response duplicate-reservation empty-meter journal-cap capture-cap event-cap; do
    cp "$report/base/"* "$report/evidence/"
    expected=fail filter=
    case $mode in
        normal) expected=pass ;;
        barrier|barrier-unreleased|barrier-name|release-first)
            filter='.[0:7]+[{event:"rendezvous_arrive",attempt:1,turn:0,group:"pair"},{event:"rendezvous_arrive",attempt:2,turn:0,group:"pair"},{event:"rendezvous_release",attempt:2,turn:0,group:"pair"},{event:"rendezvous_release",attempt:1,turn:0,group:"pair"}]+.[7:]'
            case $mode in
                barrier) expected=pass ;;
                barrier-unreleased) filter="$filter|map(select(.event!=\"rendezvous_release\"))" ;;
                barrier-name) filter="$filter|map(if has(\"group\") then .group=\"INVALID\" else . end)" ;;
                release-first) filter="$filter|map(select(.event!=\"rendezvous_arrive\"))" ;;
            esac ;;
        empty-capture)
            : > "$report/evidence/requests.jsonl"
            filter='[.[0],.[-1]|if .event=="terminal" then .admitted=0|.responses=0|.reserved_bytes=0|.captured_bytes=0 else . end]'; expected=pass ;;
        empty-body|large)
            cp "$report/first" "$report/first.saved"
            if [[ $mode == empty-body ]]; then : > "$report/first"
            else jq -nrj '"{\n\"content\":\""+("escaped\\n\\\"é界"*70000)+"\"\n}"' > "$report/first"; fi
            build; cp "$report/base/"* "$report/evidence/"; mv "$report/first.saved" "$report/first"; build; expected=pass ;;
        tampered) printf X | dd of="$report/evidence/requests.jsonl" bs=1 seek=0 conv=notrunc status=none ;;
        delimiter) printf X | dd of="$report/evidence/requests.jsonl" bs=1 seek="$(wc -c < "$report/second")" conv=notrunc status=none ;;
        appended) printf x >> "$report/evidence/requests.jsonl" ;;
        short) truncate -s -1 "$report/evidence/requests.jsonl" ;;
        hash) filter='.[5].sha256=("0"*64)' ;;
        length) filter='.[5].bytes+=1' ;;
        counters) filter='.[-1].captured_bytes+=1' ;;
        duplicate-body) filter='.[0:7]+[.[5]]+.[7:]' ;;
        duplicate-response) filter='.[0:8]+[.[7]]+.[8:]' ;;
        duplicate-reservation) filter='.[0:4]+[.[3]]+.[4:]' ;;
        missing-body) filter='del(.[5])' ;;
        missing-response) filter='del(.[7])' ;;
        early-response) filter='.[0:5]+[.[7]]+.[5:7]+.[8:]' ;;
        admission) filter='.[1].attempt=2' ;;
        reservation) filter='.[3].reserved_bytes+=1' ;;
        unknown) filter='.[5].event="unknown"' ;;
        failed) filter='.[-1].status="FAIL"|.[-1].reason="capture_limit"' ;;
        incomplete) filter='.[-1].incomplete=1' ;;
        cap) filter='.[0].capture_limit_bytes=1' ;;
        limit) filter='.[0].limit=65' ;;
        turn) filter='.[7].turn=-1' ;;
        extra) filter='.[5].extra=0' ;;
        fractional) filter='.[5].bytes=0.5' ;;
        unsafe-integer) sed 's/"limit":64/"limit":9007199254740993/' "$report/base/meter.jsonl" > "$report/evidence/meter.jsonl" ;;
        duplicate-key) sed 's/"limit":64/"limit":64,"limit":64/' "$report/base/meter.jsonl" > "$report/evidence/meter.jsonl" ;;
        unterminated) truncate -s -1 "$report/evidence/meter.jsonl" ;;
        nul) { printf '\0'; cat "$report/base/meter.jsonl"; } > "$report/evidence/meter.jsonl" ;;
        blank) printf '\n' >> "$report/evidence/meter.jsonl" ;;
        missing-meter) rm "$report/evidence/meter.jsonl" ;;
        empty-meter) : > "$report/evidence/meter.jsonl" ;;
        journal-cap) truncate -s 131073 "$report/evidence/meter.jsonl" ;;
        capture-cap) truncate -s 8388609 "$report/evidence/requests.jsonl" ;;
        event-cap) filter='.[0].extra=("x"*1024)' ;;
        symlink) rm "$report/evidence/requests.jsonl"; ln -s "$report/base/requests.jsonl" "$report/evidence/requests.jsonl" ;;
    esac
    if [[ -n $filter ]]; then jq -sc "$filter|.[]" "$report/base/meter.jsonl" > "$report/evidence/meter.jsonl"; fi
    run "$mode" "$expected" "$report/evidence"
    if [[ $mode == normal ]]; then
        jq -e --argjson n "$(wc -c < "$report/first")" --argjson m "$(wc -c < "$report/second")" \
            '.request_bytes==($n+$m) and [.bodies[].attempt]==[2,1] and .bodies[1].offset==($m+1)' "$last_receipt/result.json" >/dev/null
    fi
    if [[ $mode == tampered || $mode == failed ]]; then cmp "$report/evidence/requests.jsonl" "$last_receipt/requests/input"; fi
    rm -f "$report/evidence/"*
done
if [[ $# == 1 ]]; then
    for task in small-bug-fix read-index-select-edit large-file-edit concurrent-disjoint-edits repetitive-failure output-only-overflow input-pressure cache-accounting resume child-work; do
        run_path=$(sed -n 's/^Evaluation bound workload: //p' "$1/$task.out")
        [[ -d $run_path ]]
        world=$(jq -er .world_receipt "$run_path/summary.json")
        run "retained-$task" pass "$run_path/$world/receipt/evidence"
    done
fi
printf 'Evaluation request byte checks passed: %s\n' "$passed"
