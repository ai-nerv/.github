#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 3 ]] || { echo 'usage: transcript-usage.sh TASK EVIDENCE OUTPUT' >&2; exit 2; }
task=$1 input=$2 output=$3
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
source "$root/scripts/preserve-binary.sh"
files=(sessions.json)
case $task in
    resume) files+=(phases.jsonl replay-initial.json replay-distractor.json replay-latest.json replay-named.json) ;;
    child-work) files+=(identities.json replay-parent.json replay-child.json) ;;
    cache-accounting) files+=(ledger-runs.json replay-0.json replay-1.json) ;;
    concurrent-disjoint-edits) files+=(replay-0.json replay-1.json) ;;
    small-bug-fix|large-file-edit|read-index-select-edit|repetitive-failure|output-only-overflow|input-pressure) files+=(replay.json) ;;
    *) echo 'unknown usage workload' >&2; exit 2 ;;
esac
mkdir "$output"
mkdir "$output/bin" "$output/lib" "$output/inputs" "$output/work"
touch "$output/binaries.sha256" "$output/rows.jsonl"
preserve_binary "$root/target/evaluation/bin/eval-input" "$output/bin/eval-input" "$output/binaries.sha256" >/dev/null
helper="$output/bin/eval-input"
for name in contract usage usage-input; do
    "$helper" file "$root/scripts/evaluation" "$name.jq" "$output/work/filter-$name" 131072 1 >/dev/null
    cp "$output/work/filter-$name/input" "$output/lib/$name.jq"
done
check() {
    "$helper" json "$(dirname -- "$1")" "$(basename -- "$1")" "${2:-1048576}" >/dev/null
}
remaining=16777216
for file in "${files[@]}"; do
    "$helper" file "$input" "$file" "$output/inputs/$file" "$remaining" 1 > "$output/work/$file-counts.json"
    remaining=$((remaining-$(jq -r .bytes "$output/work/$file-counts.json")))
    raw="$output/inputs/$file/input"
    if [[ $file == phases.jsonl ]]; then
        [[ $(wc -l < "$raw") == 4 ]]
        touch "$output/work/phases-roundtrip.jsonl"
        while IFS= read -r line; do
            printf '%s\n' "$line" > "$output/work/phase.json"
            cat "$output/work/phase.json" >> "$output/work/phases-roundtrip.jsonl"
            check "$output/work/phase.json"
        done < "$raw"
        cmp "$raw" "$output/work/phases-roundtrip.jsonl"
        jq -s . "$raw" > "$output/work/phases.json"
        raw="$output/work/phases.json"
    else check "$raw" 16777216; fi
    jq -nc --arg name "$file" --slurpfile value "$raw" '{key:$name,value:$value[0]}' >> "$output/rows.jsonl"
    if [[ $file == replay*.json ]]; then
        jq -e '.result|type=="array" and length<=256' "$raw" >/dev/null
        jq -c '.result[].raw' "$raw" > "$output/work/raw-entries.jsonl"
        while IFS= read -r line; do
            printf '%s\n' "$line" | jq -erj . > "$output/work/entry.json"
            check "$output/work/entry.json" 16777216
        done < "$output/work/raw-entries.jsonl"
    fi
done
find "$output/lib" "$output/inputs" -type f -exec sha256sum -- {} + > "$output/inputs.sha256"
jq -s 'from_entries' "$output/rows.jsonl" > "$output/files.json"
jq -n -L "$output/lib" --arg task "$task" --slurpfile files "$output/files.json" \
    -f "$output/lib/usage-input.jq" > "$output/transcripts.json"
jq -L "$output/lib" -f "$output/lib/usage.jq" "$output/transcripts.json" > "$output/work/result.json"
sha256sum -c "$output/inputs.sha256" > "$output/input-integrity.log"
verify_preserved_binaries "$output/binaries.sha256" > "$output/binary-integrity.log"
mv "$output/work/result.json" "$output/result.json"
