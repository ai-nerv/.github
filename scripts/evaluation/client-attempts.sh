#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ ( $# == 2 || $# == 3 ) && $2 =~ ^[1-9][0-9]?$ && $2 -le 64 ]] || exit 2
mode=${3:-measure}
filter=client-attempts result_status=ATTEMPTS_MEASURED max_lines=66
case $mode in
    measure) ;;
    limit-failure) filter=client-limit; result_status=ATTEMPT_LIMIT_CONFIRMED; max_lines=67 ;;
    *) exit 2 ;;
esac
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
source "$root/scripts/preserve-binary.sh"
mkdir -p "$root/target/evaluation"
receipt=$(mktemp -d "$root/target/evaluation/client-attempts-XXXXXXXX")
mkdir "$receipt/bin" "$receipt/lib" "$receipt/work"
touch "$receipt/binaries.sha256"
measured=false
finish() {
    local code=$?
    trap - EXIT
    if ! verify_preserved_binaries "$receipt/binaries.sha256" > "$receipt/integrity.log" 2>&1; then code=1; fi
    if [[ -f $receipt/inputs.sha256 ]] && ! sha256sum -c "$receipt/inputs.sha256" > "$receipt/input-integrity.log" 2>&1; then code=1; fi
    if (( code != 0 )); then measured=false; rm -f "$receipt/result.json"; fi
    jq -n --argjson code "$code" --argjson measured "$measured" --arg status "$result_status" \
      '{schema:1,scope:"evaluation-client-attempts",status:(if $measured then $status else "FAIL" end),exit_code:$code,workers_started:0}' \
      > "$receipt/summary.json"
    printf 'Evaluation client attempts: %s\n' "$receipt"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
preserve_binary "$root/target/evaluation/bin/eval-input" "$receipt/bin/eval-input" "$receipt/binaries.sha256" >/dev/null
parser=$(readlink -f -- "$(command -v jq)"); [[ $parser == /nix/store/* ]]
preserve_binary "$parser" "$receipt/bin/jq" "$receipt/binaries.sha256" >/dev/null
helper="$receipt/bin/eval-input" parser="$receipt/bin/jq"
for name in contract "$filter"; do
    "$helper" file "$root/scripts/evaluation" "$name.jq" "$receipt/work/$name" 131072 1 >/dev/null
    cp "$receipt/work/$name/input" "$receipt/lib/$name.jq"
done
"$helper" file "$1" client-attempts.jsonl "$receipt/ledger" 65536 1 >/dev/null
sha256sum "$receipt/lib/"*.jq "$receipt/ledger/input" > "$receipt/inputs.sha256"
lines=0
: > "$receipt/work/roundtrip.jsonl"
while IFS= read -r line; do
    lines=$((lines+1)); [[ $lines -le $max_lines ]]
    printf '%s\n' "$line" > "$receipt/work/event.json"
    cat "$receipt/work/event.json" >> "$receipt/work/roundtrip.jsonl"
    "$helper" json "$receipt/work" event.json 131072 >/dev/null
done < "$receipt/ledger/input"
cmp "$receipt/ledger/input" "$receipt/work/roundtrip.jsonl"
"$parser" -e -s -L "$receipt/lib" --argjson limit "$2" -f "$receipt/lib/$filter.jq" \
    "$receipt/ledger/input" > "$receipt/result.json"
measured=true
