#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
source "$root/scripts/evaluation/tree-identity.sh"
mkdir -p "$root/target/evaluation"
report=$(mktemp -d "$root/target/evaluation/pack-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" \
        '{schema:1,scope:"evaluation-raw-package-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$passed,workers_started:0}' > "$report/summary.json"
    printf 'Evaluation raw package test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
pack() { bash "$root/scripts/evaluation/pack-raw.sh" "$report" "$1" "$2"; }
package_path() { sed -n 's/^Evaluation raw package: //p' "$1"; }
roundtrip() {
    local receipt=$1 expected=$2 name=$3
    mkdir "$report/$name"
    env -i LC_ALL=C "$receipt/bin/tar" -xf "$receipt/evidence/raw.tar" -C "$report/$name"
    tree_identity "$expected" > "$report/$name-expected.tree"
    tree_identity "$report/$name" > "$report/$name-actual.tree"
    cmp "$report/$name-expected.tree" "$report/$name-actual.tree"
    jq -e '.status=="RAW_PACKED" and .workers_started==0 and (.evidence|length)==1 and
        .evidence[0].path=="raw.tar" and .archive_bytes+.reserved_sample_bytes<=16777216' "$receipt/summary.json" >/dev/null
    sha256sum -c "$receipt/evidence.sha256" > "$report/$name-integrity.log"
    [[ $(stat -c %a "$receipt/evidence/raw.tar") == 600 ]]
}
mkdir -p "$report/raw/empty/nested" "$report/raw/-options"
printf '\000\377\376\r\nbytes\000tail' > "$report/raw/binary"
printf ' spaces\tand backslash\\\n' > "$report/raw/ space and \\name "
printf 'no execution\n' > "$report/raw/-options/--checkpoint-action=exec=touch sentinel"
long=$(printf '%0200d' 1)
printf 'long path\n' > "$report/raw/$long"
for index in {1..40}; do printf '%s\n' "$index" > "$report/raw/$index.json"; done
pack raw 4096 > "$report/first.out" 2> "$report/first.err"
first=$(package_path "$report/first.out")
roundtrip "$first" "$report/raw" first-restored
passed=$((passed+1))
cp -R "$report/raw" "$report/relocated"
find "$report/relocated" -type f -exec chmod 444 {} + -exec touch -m -t 200001010000 {} +
TAR_OPTIONS='--checkpoint=1 --checkpoint-action=exec=false' POSIXLY_CORRECT=1 pack relocated 0 > "$report/relocated.out" 2> "$report/relocated.err"
second=$(package_path "$report/relocated.out")
cmp "$first/evidence/raw.tar" "$second/evidence/raw.tar"
[[ ! -e $report/sentinel ]]
passed=$((passed+1))
bytes=$(jq -er .archive_bytes "$first/summary.json")
pack raw "$((16777216-bytes))" > "$report/exact.out" 2> "$report/exact.err"
exact=$(package_path "$report/exact.out")
jq -e '.status=="RAW_PACKED" and .archive_bytes+.reserved_sample_bytes==16777216' "$exact/summary.json" >/dev/null
passed=$((passed+1))
for reserve in "$((16777217-bytes))" 16777216; do
    if pack raw "$reserve" > "$report/over-$reserve.out" 2> "$report/over-$reserve.err"; then exit 1; fi
    rejected=$(package_path "$report/over-$reserve.out")
    jq -e '.status=="FAIL" and .archive_sha256==null and .evidence==[]' "$rejected/summary.json" >/dev/null
    [[ $(wc -c < "$rejected/evidence/raw.tar") -le $((16777217-reserve)) ]]
    [[ $(jq -er .archive_bytes "$rejected/summary.json") == "$(wc -c < "$rejected/evidence/raw.tar")" ]]
    passed=$((passed+1))
done
for reserve in -1 01 16777217 bad; do
    if pack raw "$reserve" > "$report/invalid-$reserve.out" 2> "$report/invalid-$reserve.err"; then exit 1; fi
    [[ ! -s $report/invalid-$reserve.out ]]
    passed=$((passed+1))
done
mkdir "$report/empty"
pack empty 0 > "$report/empty.out" 2> "$report/empty.err"
roundtrip "$(package_path "$report/empty.out")" "$report/empty" empty-restored
passed=$((passed+1))
mkdir "$report/max-files"
for index in {1..256}; do : > "$report/max-files/$index"; done
pack max-files 0 > "$report/max-files.out" 2> "$report/max-files.err"
roundtrip "$(package_path "$report/max-files.out")" "$report/max-files" max-files-restored
passed=$((passed+1))
: > "$report/max-files/257"
mkdir "$report/oversize"
head -c 16777217 /dev/zero > "$report/oversize/file"
for mode in symlink hardlink fifo newline parent absolute missing files bytes; do
    mkdir "$report/$mode-case"
    relative="$mode-case"
    case $mode in
        symlink) ln -s "$report/raw/binary" "$report/$mode-case/link" ;;
        hardlink) ln "$report/raw/binary" "$report/$mode-case/link" ;;
        fifo) mkfifo "$report/$mode-case/pipe" ;;
        newline) : > "$report/$mode-case/"$'bad\nname' ;;
        parent) relative=../raw ;;
        absolute) relative="$report/raw" ;;
        missing) relative=absent ;;
        files) relative=max-files ;;
        bytes) relative=oversize ;;
    esac
    if pack "$relative" 0 > "$report/$mode.out" 2> "$report/$mode.err"; then
        echo "accepted unsafe or oversized raw tree: $mode" >&2; exit 1
    fi
    rejected=$(package_path "$report/$mode.out")
    jq -e '.status=="FAIL" and .evidence==[]' "$rejected/summary.json" >/dev/null
    [[ ! -e $rejected/evidence/raw.tar ]]
    [[ $mode != hardlink ]] || rm "$report/$mode-case/link"
    passed=$((passed+1))
done
printf 'Evaluation raw package checks passed: %s\n' "$passed"
