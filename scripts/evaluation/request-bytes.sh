#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 1 ]] || { echo 'usage: request-bytes.sh EVIDENCE_ROOT' >&2; exit 2; }
input=$1
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
source "$root/scripts/preserve-binary.sh"
mkdir -p "$root/target/evaluation"
receipt=$(mktemp -d "$root/target/evaluation/request-bytes-XXXXXXXX")
mkdir "$receipt/bin" "$receipt/lib" "$receipt/work"
touch "$receipt/binaries.sha256"
measured=false request_bytes=null
finish() {
    local code=$?
    trap - EXIT
    if ! verify_preserved_binaries "$receipt/binaries.sha256" > "$receipt/binary-integrity.log" 2>&1; then code=1; fi
    if [[ -f $receipt/inputs.sha256 ]] && ! sha256sum -c "$receipt/inputs.sha256" > "$receipt/input-integrity.log" 2>&1; then code=1; fi
    if [[ $code != 0 ]]; then measured=false; request_bytes=null; rm -f "$receipt/result.json"; fi
    jq -n --argjson code "$code" --argjson measured "$measured" --argjson bytes "$request_bytes" \
        '{schema:1,scope:"evaluation-request-byte-capture",status:(if $measured then "BYTES_MEASURED" else "FAIL" end),
          exit_code:$code,request_bytes:$bytes,complete_run:false,workers_started:0,live_requests:0}' > "$receipt/summary.json"
    printf 'Evaluation request bytes: %s\n' "$receipt"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
preserve_binary "$root/target/evaluation/bin/eval-input" "$receipt/bin/eval-input" "$receipt/binaries.sha256" >/dev/null
for name in jq dd sha256sum; do
    binary=$(readlink -f -- "$(command -v "$name")")
    [[ $binary == /nix/store/* ]]
    preserve_binary "$binary" "$receipt/bin/$name" "$receipt/binaries.sha256" >/dev/null
done
helper="$receipt/bin/eval-input"
parser="$receipt/bin/jq"
for name in lexical json contract request-bytes; do
    "$helper" file "$root/scripts/evaluation" "$name.jq" "$receipt/work/filter-$name" 131072 1 >/dev/null
    cp "$receipt/work/filter-$name/input" "$receipt/lib/$name.jq"
done
"$helper" file "$input" meter.jsonl "$receipt/meter" 131072 1 > "$receipt/work/meter-counts.json"
"$helper" file "$input" requests.jsonl "$receipt/requests" 8388608 1 > "$receipt/work/request-counts.json"
find "$receipt/lib" "$receipt/meter" "$receipt/requests" -type f -exec sha256sum -- {} + > "$receipt/inputs.sha256"
printf '\n' > "$receipt/work/newline"
tail -c 1 "$receipt/meter/input" | cmp - "$receipt/work/newline"
lines=0
touch "$receipt/work/meter-roundtrip.jsonl"
while IFS= read -r line; do
    lines=$((lines+1))
    [[ $lines -le 512 ]]
    printf '%s\n' "$line" > "$receipt/work/event.json"
    cat "$receipt/work/event.json" >> "$receipt/work/meter-roundtrip.jsonl"
    [[ $(wc -c < "$receipt/work/event.json") -le 1024 ]]
    "$parser" -Rse --argjson safe_integers true -f "$receipt/lib/lexical.jq" "$receipt/work/event.json" >/dev/null
    "$parser" --stream --slurp -e -f "$receipt/lib/json.jq" "$receipt/work/event.json" >/dev/null
done < "$receipt/meter/input"
cmp "$receipt/meter/input" "$receipt/work/meter-roundtrip.jsonl"
"$parser" -s -L "$receipt/lib" --argjson capture_bytes "$("$parser" -r .bytes "$receipt/work/request-counts.json")" \
    -f "$receipt/lib/request-bytes.jq" "$receipt/meter/input" > "$receipt/work/result.json"
"$parser" -r '.bodies[]|[.offset,.bytes,.sha256]|@tsv' "$receipt/work/result.json" > "$receipt/work/bodies.tsv"
while IFS=$'\t' read -r offset size expected; do
    actual=$(env -i LC_ALL=C "$receipt/bin/dd" if="$receipt/requests/input" bs=65536 \
        iflag=skip_bytes,count_bytes skip="$offset" count="$size" status=none | env -i LC_ALL=C "$receipt/bin/sha256sum")
    [[ ${actual%% *} == "$expected" ]]
    env -i LC_ALL=C "$receipt/bin/dd" if="$receipt/requests/input" bs=65536 \
        iflag=skip_bytes,count_bytes skip="$((offset+size))" count=1 status=none | cmp - "$receipt/work/newline"
done < "$receipt/work/bodies.tsv"
sha256sum -c "$receipt/inputs.sha256" > "$receipt/input-integrity.log"
verify_preserved_binaries "$receipt/binaries.sha256" > "$receipt/binary-integrity.log"
mv "$receipt/work/result.json" "$receipt/result.json"
request_bytes=$("$parser" -r .request_bytes "$receipt/result.json")
measured=true
