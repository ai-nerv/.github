#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 1 ]] || { echo 'usage: normalized-prefix.sh EVIDENCE_ROOT' >&2; exit 2; }
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
source "$root/scripts/preserve-binary.sh"
mkdir -p "$root/target/evaluation"
receipt=$(mktemp -d "$root/target/evaluation/prefix-XXXXXXXX")
mkdir "$receipt/bin" "$receipt/work"
touch "$receipt/binaries.sha256"
measured=false
finish() {
    local code=$?
    trap - EXIT
    if ! verify_preserved_binaries "$receipt/binaries.sha256" > "$receipt/binary-integrity.log" 2>&1; then code=1; fi
    if [[ -f $receipt/inputs.sha256 ]] && ! sha256sum -c "$receipt/inputs.sha256" > "$receipt/input-integrity.log" 2>&1; then code=1; fi
    if (( code != 0 )); then measured=false; rm -f "$receipt/result.json"; fi
    jq -n --argjson code "$code" --argjson measured "$measured" \
        '{schema:1,scope:"evaluation-normalized-prefix",status:(if $measured then "PREFIX_MEASURED" else "FAIL" end),
          exit_code:$code,complete_run:false,workers_started:0,live_requests:0}' > "$receipt/summary.json"
    printf 'Evaluation normalized prefix: %s\n' "$receipt"
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
"$helper" file "$root/scripts/evaluation" normalized-prefix.jq "$receipt/filter" 131072 1 >/dev/null
bash "$root/scripts/evaluation/request-bytes.sh" "$1" > "$receipt/request-bytes.out" 2> "$receipt/request-bytes.err"
capture=$(sed -n 's/^Evaluation request bytes: //p' "$receipt/request-bytes.out")
[[ $capture == "$root/target/evaluation/request-bytes-"* && -d $capture ]]
"$helper" file "$capture" result.json "$receipt/capture" 131072 1 >/dev/null
"$helper" file "$capture" requests/input "$receipt/requests" 8388608 1 >/dev/null
sha256sum "$receipt/filter/input" "$receipt/capture/input" "$receipt/requests/input" > "$receipt/inputs.sha256"
"$parser" -r '.bodies[]|[.attempt,.offset,.bytes,.sha256]|@tsv' "$receipt/capture/input" > "$receipt/work/bodies.tsv"
: > "$receipt/work/normalized.tsv"
while IFS=$'\t' read -r attempt offset size expected; do
    env -i LC_ALL=C "$receipt/bin/dd" if="$receipt/requests/input" of="$receipt/work/body.json" bs=65536 \
        iflag=skip_bytes,count_bytes skip="$offset" count="$size" status=none
    actual=$("$receipt/bin/sha256sum" < "$receipt/work/body.json"); [[ ${actual%% *} == "$expected" ]]
    "$helper" json-wire "$receipt/work" body.json 16777216 > "$receipt/work/validation.json"
    "$parser" -cS -f "$receipt/filter/input" "$receipt/work/body.json" > "$receipt/work/normalized.json"
    key=$("$parser" -cS .identity "$receipt/work/normalized.json" | "$receipt/bin/sha256sum"); key=${key%% *}
    printf '%s\t' "$key" >> "$receipt/work/normalized.tsv"
    "$parser" -cS .prompt "$receipt/work/normalized.json" >> "$receipt/work/normalized.tsv"
    [[ $(wc -c < "$receipt/work/normalized.tsv") -le 8388608 ]]
done < "$receipt/work/bodies.tsv"
sha256sum "$receipt/work/normalized.tsv" >> "$receipt/inputs.sha256"
"$helper" prefix "$receipt/work" normalized.tsv > "$receipt/work/prefix.json"
"$parser" -n --slurpfile measured "$receipt/work/prefix.json" --slurpfile capture "$receipt/capture/input" '
    $capture[0] as $capture | $measured[0] as $measured |
    if ($measured.bodies|length)!=$capture.provider_received then error("prefix capture count differs") else
    {schema:1,scope:"evaluation-normalized-prefix",status:"PREFIX_MEASURED",complete_run:false,
      representation:"sorted-compact-utf8-prompt-v1",order:"provider-body-capture",comparison:"adjacent-same-model-and-system-shape",
      normalization:"tools-system-messages; structural cache_control removed; object keys sorted; arrays preserved",
      request_bytes:$capture.request_bytes,normalized_bytes:$measured.normalized_bytes,
      stable_prefix_bytes:$measured.stable_prefix_bytes,provider_attempts:null,cached_tokens:null,
      bodies:[$measured.bodies[]|. + {attempt:$capture.bodies[.index].attempt}]} end' > "$receipt/result.json"
measured=true
