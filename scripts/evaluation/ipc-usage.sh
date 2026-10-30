#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 2 ]] || { echo 'usage: ipc-usage.sh ROOT RELATIVE_CAPTURE_DIRECTORY' >&2; exit 2; }
input=$1 relative=$2
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
source "$root/scripts/preserve-binary.sh"
receipt=$(mktemp -d "$root/target/evaluation/ipc-usage-XXXXXXXX")
mkdir "$receipt/bin" "$receipt/lib" "$receipt/work"
touch "$receipt/binaries.sha256"
finish() {
    local code=$?
    trap - EXIT
    if ! verify_preserved_binaries "$receipt/binaries.sha256" > "$receipt/binary-integrity.log" 2>&1; then code=1; fi
    if [[ -f $receipt/inputs.sha256 ]] && ! sha256sum -c "$receipt/inputs.sha256" > "$receipt/input-integrity.log" 2>&1; then code=1; fi
    if [[ $code != 0 ]]; then rm -f "$receipt/result.json"; fi
    jq -n --argjson code "$code" '{schema:1,scope:"evaluation-model-ipc-usage-capture",status:(if $code==0 then "USAGE_EXTRACTED" else "FAIL" end),exit_code:$code,complete_run:false,workers_started:0}' > "$receipt/summary.json"
    printf 'Evaluation IPC usage: %s\n' "$receipt"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
preserve_binary "$root/target/evaluation/bin/eval-input" "$receipt/bin/eval-input" "$receipt/binaries.sha256" >/dev/null
preserve_binary "$(type -P jq)" "$receipt/bin/jq" "$receipt/binaries.sha256" >/dev/null
helper="$receipt/bin/eval-input" parser="$receipt/bin/jq"
for name in contract ipc-usage; do
    "$helper" file "$root/scripts/evaluation" "$name.jq" "$receipt/work/filter-$name" 131072 1 >/dev/null
    cp "$receipt/work/filter-$name/input" "$receipt/lib/$name.jq"
done
"$helper" tree "$input" "$relative" "$receipt/capture" 9437184 195 > "$receipt/work/counts.json"
raw="$receipt/capture"
find "$raw" "$receipt/lib" -type f -exec sha256sum -- {} + > "$receipt/inputs.sha256"
"$helper" json "$raw" summary.json 131072 >/dev/null
"$parser" -e -L "$receipt/lib" 'include "contract";
    exact(["schema","scope","sealed","calls","bytes","limit_exhausted","capture_complete","complete_run","helper_attribution"]) and
    .schema==1 and .scope=="evaluation-model-ipc" and .sealed==true and (.calls|whole(0;64)) and (.bytes|whole(0;8388608)) and
    (.limit_exhausted|type)=="boolean" and (.capture_complete|type)=="boolean" and
    (.capture_complete==false or .limit_exhausted==false) and .complete_run==false and .helper_attribution==null' "$raw/summary.json" >/dev/null
printf 'sealed\n' > "$receipt/work/gate"
cmp "$receipt/work/gate" "$raw/gate"
"$parser" -r '"\(.calls) \(.bytes) \(if .limit_exhausted then 1 else 0 end)"' "$raw/summary.json" > "$receipt/work/budget"
cmp "$receipt/work/budget" "$raw/budget"
calls=$("$parser" -r .calls "$raw/summary.json")
complete=$("$parser" -r .capture_complete "$raw/summary.json")
[[ $(find "$raw" -mindepth 1 -type d | wc -l) == 0 ]]
total=0
while IFS= read -r name; do
    size=$(wc -c < "$raw/$name")
    case $name in
        gate|budget|summary.json) [[ $size -le 512 ]] ;;
        *)
            [[ $name =~ ^([0-9]{3})-(request.json|response.jsonl|receipt.json)$ ]]
            [[ $((10#${BASH_REMATCH[1]})) -lt $calls ]]
            if [[ $name == *-receipt.json ]]; then [[ $size -le 512 ]];
            else [[ $size -le 1048576 ]]; total=$((total+size)); fi ;;
    esac
done < <(find "$raw" -type f -printf '%f\n')
reserved=$("$parser" -r .bytes "$raw/summary.json")
[[ $total -le $reserved && ( $complete == false || $total == "$reserved" ) ]]
: > "$receipt/work/calls.jsonl"
frames=0
for ((id=0;id<calls;id++)); do
    printf -v prefix '%03d' "$id"
    if [[ ! -f $raw/$prefix-receipt.json ]]; then
        [[ $complete == false ]]
        "$parser" -nc --argjson id "$id" '{call:$id,model:null,transport_complete:false,exit_code:null,events:[]}' >> "$receipt/work/calls.jsonl"
        continue
    fi
    "$helper" json "$raw" "$prefix-receipt.json" 131072 >/dev/null
    "$parser" -e -L "$receipt/lib" --argjson id "$id" 'include "contract";
        exact(["schema","call","request_bytes","response_bytes","exit_code","transport_complete","complete_run"]) and
        .schema==1 and .call==$id and (.request_bytes|whole(0;1048576)) and (.response_bytes|whole(0;1048576)) and
        (.exit_code|whole(0;255)) and .transport_complete==true and .complete_run==false' "$raw/$prefix-receipt.json" >/dev/null
    [[ $(wc -c < "$raw/$prefix-request.json") == $("$parser" -r .request_bytes "$raw/$prefix-receipt.json") ]]
    [[ $(wc -c < "$raw/$prefix-response.jsonl") == $("$parser" -r .response_bytes "$raw/$prefix-receipt.json") ]]
    "$helper" json-wire "$raw" "$prefix-request.json" 1048576 >/dev/null
    "$parser" -e 'type=="object" and (.model|type)=="string" and (.model|length)>0 and (.model|length)<=256 and
        (.context|type)=="object" and (.wants|type)=="object"' "$raw/$prefix-request.json" >/dev/null
    : > "$receipt/work/roundtrip.jsonl"
    while IFS= read -r line; do
        frames=$((frames+1)); [[ $frames -le 4096 ]]
        printf '%s\n' "$line" > "$receipt/work/frame.json"
        cat "$receipt/work/frame.json" >> "$receipt/work/roundtrip.jsonl"
        "$helper" json-wire "$receipt/work" frame.json 1048576 >/dev/null
        if [[ $("$parser" -r .event "$receipt/work/frame.json") == spent ]]; then
            "$helper" json "$receipt/work" frame.json 1048576 >/dev/null
        fi
    done < "$raw/$prefix-response.jsonl"
    cmp "$raw/$prefix-response.jsonl" "$receipt/work/roundtrip.jsonl"
    "$parser" -nc --argjson id "$id" --slurpfile request "$raw/$prefix-request.json" \
        --slurpfile receipt "$raw/$prefix-receipt.json" --slurpfile events "$raw/$prefix-response.jsonl" \
        '{call:$id,model:$request[0].model,transport_complete:true,exit_code:$receipt[0].exit_code,events:$events}' >> "$receipt/work/calls.jsonl"
done
"$parser" -s -L "$receipt/lib" --argjson capture_complete "$complete" -f "$receipt/lib/ipc-usage.jq" "$receipt/work/calls.jsonl" > "$receipt/work/result.json"
sha256sum -c "$receipt/inputs.sha256" > "$receipt/input-integrity.log"
verify_preserved_binaries "$receipt/binaries.sha256" > "$receipt/binary-integrity.log"
mv "$receipt/work/result.json" "$receipt/result.json"
