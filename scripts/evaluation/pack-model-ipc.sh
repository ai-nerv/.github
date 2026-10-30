#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 5 && $5 =~ ^[1-9][0-9]{0,6}$ && $5 -le 9437184 ]] || {
    echo 'usage: pack-model-ipc.sh ROOT RELATIVE NEW_OUTPUT INPUT_HELPER ARCHIVE_LIMIT_BYTES' >&2; exit 2;
}
input=$1 relative=$2 output=$3 helper=$4 limit=$5
mkdir -- "$output"
mkdir "$output/work"
bytes=0 digest=
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson limit "$limit" --argjson bytes "$bytes" --arg digest "$digest" \
      '{schema:1,scope:"evaluation-model-ipc-package",status:(if $code==0 then "IPC_PACKED" else "FAIL" end),
        exit_code:$code,archive_limit_bytes:$limit,archive_bytes:$bytes,
        archive_sha256:(if $code==0 then $digest else null end),complete_run:false}' > "$output/summary.json"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
"$helper" tree "$input" "$relative" "$output/raw" 9437184 195 > "$output/work/counts.json"
raw="$output/raw"
same() { [[ $(sha256sum < "$1") == "$(sha256sum < "$2")" ]]; }
"$helper" json "$raw" summary.json 131072 > /dev/null
jq -e '.schema==1 and .scope=="evaluation-model-ipc" and .sealed==true and
    (.calls|type=="number" and .>=0 and .<=64 and .==floor) and
    (.bytes|type=="number" and .>=0 and .<=8388608 and .==floor) and
    (.limit_exhausted|type=="boolean") and (.capture_complete|type=="boolean") and
    .complete_run==false and .helper_attribution==null' "$raw/summary.json" > /dev/null
printf 'sealed\n' > "$output/work/gate"
same "$output/work/gate" "$raw/gate"
jq -r '"\(.calls) \(.bytes) \(if .limit_exhausted then 1 else 0 end)"' "$raw/summary.json" > "$output/work/budget"
same "$output/work/budget" "$raw/budget"
[[ $(find "$raw" -mindepth 1 -type d | wc -l) == 0 ]]
calls=$(jq -r .calls "$raw/summary.json")
total=0
while IFS= read -r name; do
    size=$(wc -c < "$raw/$name")
    case $name in
        gate|budget|summary.json) [[ $size -le 512 ]] ;;
        *)
            [[ $name =~ ^([0-9]{3})-(request.json|response.jsonl|receipt.json)$ ]]
            id=$((10#${BASH_REMATCH[1]}))
            [[ $id -lt $calls ]]
            if [[ $name == *-receipt.json ]]; then
                [[ $size -le 512 ]]
            else
                [[ $size -le 1048576 ]]
                total=$((total+size))
                [[ $total -le 8388608 ]]
            fi ;;
    esac
done < <(find "$raw" -mindepth 1 -maxdepth 1 -type f -printf '%f\n')
[[ $total -le $(jq -r .bytes "$raw/summary.json") ]]
identity() (cd -- "$1"; find . -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum --)
identity "$raw" > "$output/work/before.sha256"
tar=$(type -P tar)
[[ $tar == /* ]]
env -i LC_ALL=C TZ=UTC "$tar" --create --file=- --directory="$raw" \
    --format=ustar --blocking-factor=1 --sort=name --mtime=@0 --owner=0 --group=0 --numeric-owner -- . |
    head -c "$((limit+1))" > "$output/work/archive.partial"
bytes=$(wc -c < "$output/work/archive.partial")
(( bytes <= limit )) || { echo 'model IPC archive exceeds byte limit' >&2; exit 1; }
"$helper" ipc-unpack "$output/work" archive.partial "$output/work/restored" > "$output/work/unpacked.json"
identity "$output/work/restored" > "$output/work/restored.sha256"
identity "$raw" > "$output/work/after.sha256"
same "$output/work/before.sha256" "$output/work/restored.sha256"
same "$output/work/before.sha256" "$output/work/after.sha256"
digest=$(sha256sum < "$output/work/archive.partial"); digest=${digest%% *}
mv "$output/work/archive.partial" "$output/raw.tar"
