#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/ipc-pack-tests-XXXXXXXX")
helper="$root/target/evaluation/bin/eval-input"
recorder="$root/target/evaluation/bin/eval-world"
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" \
      '{schema:1,scope:"evaluation-ipc-pack-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$passed,live_requests:0}' > "$report/summary.json"
    printf 'Evaluation IPC package test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
pack() { bash "$root/scripts/evaluation/pack-model-ipc.sh" "$report" "$1" "$report/$2" "$helper" "$3"; }
"$recorder" record init "$report/raw"
cat > "$report/echo" <<SH
#!$(type -P bash)
exec cat
SH
chmod 700 "$report/echo"
for _ in {1..64}; do
    printf '\000\377\r\nexact bytes' | "$recorder" record ask "$report/raw" "$report/echo" ask --json > /dev/null
done
"$recorder" record seal "$report/raw"
pack raw packed 9437184
[[ $(find "$report/packed/raw" -type f | wc -l) == 195 ]]
jq -e '.status=="IPC_PACKED" and .complete_run==false' "$report/packed/summary.json" >/dev/null
passed=$((passed+1))
mkdir -p "$report/exported/evidence"
cp "$report/packed/raw.tar" "$report/exported/evidence/model-ipc.tar"
cp "$report/packed/summary.json" "$report/exported/model-ipc-package.json"
worker_output() {
    printf 'Evaluation IPC package: ' > "$report/exported/worker.stdout"
    tr -d '\n' < "$report/exported/model-ipc-package.json" >> "$report/exported/worker.stdout"
    printf '\n' >> "$report/exported/worker.stdout"
}
unpack() { bash "$root/scripts/evaluation/unpack-model-ipc.sh" "$report/exported" "$report/$1" "$helper" "$root/scripts/evaluation"; }
worker_output
unpack unpacked
cmp "$report/unpacked/raw/000-request.json" "$report/raw/000-request.json"
[[ $(find "$report/unpacked/raw" -type f | wc -l) == 195 ]]
passed=$((passed+1))
for mode in digest bytes limit duplicate invalid-archive missing-receipt repeated-receipt; do
    cp "$report/packed/summary.json" "$report/exported/model-ipc-package.json"
    cp "$report/packed/raw.tar" "$report/exported/evidence/model-ipc.tar"
    case $mode in
        digest) jq '.archive_sha256=("0"*64)' "$report/packed/summary.json" > "$report/exported/model-ipc-package.json" ;;
        bytes) jq '.archive_bytes+=1' "$report/packed/summary.json" > "$report/exported/model-ipc-package.json" ;;
        limit) jq '.archive_limit_bytes=1' "$report/packed/summary.json" > "$report/exported/model-ipc-package.json" ;;
        duplicate) sed 's/"schema": 1/"schema": 1, "schema": 1/' "$report/packed/summary.json" > "$report/exported/model-ipc-package.json" ;;
        invalid-archive)
            printf X | dd of="$report/exported/evidence/model-ipc.tar" bs=1 seek=0 conv=notrunc status=none
            digest=$(sha256sum < "$report/exported/evidence/model-ipc.tar"); digest=${digest%% *}
            jq --arg digest "$digest" '.archive_sha256=$digest' "$report/packed/summary.json" > "$report/exported/model-ipc-package.json" ;;
    esac
    worker_output
    if [[ $mode == missing-receipt ]]; then : > "$report/exported/worker.stdout"; fi
    if [[ $mode == repeated-receipt ]]; then
        cp "$report/exported/worker.stdout" "$report/repeated-receipt.txt"
        cat "$report/repeated-receipt.txt" >> "$report/exported/worker.stdout"
    fi
    if unpack "unpack-$mode"; then echo "accepted invalid IPC package: $mode" >&2; exit 1; fi
    [[ ! -e $report/unpack-$mode/raw ]]
    passed=$((passed+1))
done
bytes=$(wc -c < "$report/packed/raw.tar")
TAR_OPTIONS='--checkpoint=1 --checkpoint-action=exec=false' pack raw exact "$bytes"
cmp "$report/packed/raw.tar" "$report/exact/raw.tar"
passed=$((passed+1))
for limit in "$((bytes-1))" 1; do
    if pack raw "small-$limit" "$limit"; then exit 1; fi
    [[ ! -e $report/small-$limit/raw.tar ]]
    jq -e '.status=="FAIL" and .archive_sha256==null' "$report/small-$limit/summary.json" >/dev/null
    [[ $(wc -c < "$report/small-$limit/work/archive.partial") -le $((limit+1)) ]]
    passed=$((passed+1))
done
for mode in open missing-summary symlink hardlink fifo extra-name directory too-many oversize changed-budget; do
    cp -R "$report/raw" "$report/$mode"
    case $mode in
        open) printf 'open\n' > "$report/$mode/gate" ;;
        missing-summary) rm "$report/$mode/summary.json" ;;
        symlink) rm "$report/$mode/000-request.json"; ln -s "$report/raw/000-request.json" "$report/$mode/000-request.json" ;;
        hardlink) rm "$report/$mode/000-request.json"; ln "$report/raw/000-request.json" "$report/$mode/000-request.json" ;;
        fifo) rm "$report/$mode/000-request.json"; mkfifo "$report/$mode/000-request.json" ;;
        extra-name) mv "$report/$mode/000-request.json" "$report/$mode/unexpected" ;;
        directory) mkdir "$report/$mode/empty" ;;
        too-many) : > "$report/$mode/extra" ;;
        oversize) head -c 1048577 /dev/zero > "$report/$mode/000-request.json" ;;
        changed-budget) printf '64 0 0\n' > "$report/$mode/budget" ;;
    esac
    if timeout 10 bash "$root/scripts/evaluation/pack-model-ipc.sh" "$report" "$mode" "$report/reject-$mode" "$helper" 9437184; then
        echo "accepted $mode" >&2; exit 1
    else [[ $? != 124 ]]; fi
    [[ ! -e $report/reject-$mode/raw.tar ]]
    passed=$((passed+1))
    [[ $mode != hardlink ]] || rm "$report/$mode/000-request.json"
done
"$recorder" record init "$report/incomplete"
if "$recorder" record ask "$report/incomplete" /does-not-exist ask --json <<< '{}'; then exit 1; fi
if "$recorder" record seal "$report/incomplete"; then exit 1; fi
pack incomplete partial 9437184
jq -e '.capture_complete==false and .complete_run==false' "$report/partial/work/restored/summary.json" >/dev/null
passed=$((passed+1))
printf 'Evaluation IPC package checks passed: %s\n' "$passed"
