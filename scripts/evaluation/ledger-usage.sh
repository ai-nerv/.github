#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 3 ]] || { echo 'usage: ledger-usage.sh TASK EVIDENCE OUTPUT' >&2; exit 2; }
task=$1 input=$2 output=$3
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
source "$root/scripts/preserve-binary.sh"
files=(sessions.json)
case $task in
    resume) files+=(phases.jsonl ledger-initial.txt ledger-distractor.txt ledger-latest.txt ledger-named.txt) ;;
    cache-accounting) files+=(ledger-runs.json chat.exit anthropic.exit ledger-0.txt ledger-1.txt) ;;
    child-work) files+=(identities.json magi.exit ledger.txt) ;;
    *) echo 'no captured spending ledger for this workload' >&2; exit 2 ;;
esac
mkdir "$output"
mkdir "$output/bin" "$output/lib" "$output/inputs" "$output/work"
touch "$output/binaries.sha256" "$output/rows.jsonl"
preserve_binary "$root/target/evaluation/bin/eval-input" "$output/bin/eval-input" "$output/binaries.sha256" >/dev/null
helper="$output/bin/eval-input"
for name in lexical json contract ledger-usage; do
    "$helper" file "$root/scripts/evaluation" "$name.jq" "$output/work/filter-$name" 131072 1 >/dev/null
    cp "$output/work/filter-$name/input" "$output/lib/$name.jq"
done
check() {
    jq -Rse --argjson safe_integers true -f "$output/lib/lexical.jq" "$1" >/dev/null
    jq --stream --slurp -e -f "$output/lib/json.jq" "$1" >/dev/null
}
for file in "${files[@]}"; do
    bound=131072
    if [[ $file == *.txt || $file == *.exit ]]; then bound=17; fi
    "$helper" file "$input" "$file" "$output/inputs/$file" "$bound" 1 > "$output/work/$file-counts.json"
    raw="$output/inputs/$file/input"
    if [[ $file == *.txt || $file == *.exit ]]; then
        jq -nc --arg name "$file" --rawfile value "$raw" '{key:$name,value:$value}' >> "$output/rows.jsonl"
        continue
    elif [[ $file == phases.jsonl ]]; then
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
    else check "$raw"; fi
    jq -nc --arg name "$file" --slurpfile value "$raw" '{key:$name,value:$value[0]}' >> "$output/rows.jsonl"
done
find "$output/lib" "$output/inputs" -type f -exec sha256sum -- {} + > "$output/inputs.sha256"
jq -s 'from_entries' "$output/rows.jsonl" > "$output/files.json"
jq -n -L "$output/lib" --arg task "$task" --slurpfile files "$output/files.json" \
    -f "$output/lib/ledger-usage.jq" > "$output/work/result.json"
sha256sum -c "$output/inputs.sha256" > "$output/input-integrity.log"
verify_preserved_binaries "$output/binaries.sha256" > "$output/binary-integrity.log"
mv "$output/work/result.json" "$output/result.json"
