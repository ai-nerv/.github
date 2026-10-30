#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
scratch=$(mktemp -d /tmp/nerv-tool-assets.XXXXXX)
trap 'rm -rf -- "$scratch"' EXIT
mkdir "$scratch/source space" "$scratch/selected space"
source="$scratch/source space/tools.lua"
selected="$scratch/selected space/tools.lua"
printf '%s\n' 'casper.file_tool("read", {operation="read"})' > "$source"
cp -- "$source" "$selected"
"$BASH" "$root/scripts/selected-tools.sh" "$source" "$selected" 'scenario "quotes"' > "$scratch/asset.json"
digest=$(sha256sum < "$source"); digest=${digest%% *}
jq -e --arg digest "$digest" '.scope=="scenario \"quotes\"" and .owner=="casper" and .asset=="tools.lua" and .sha256==$digest' "$scratch/asset.json" >/dev/null
refuses() {
    if "$BASH" "$root/scripts/selected-tools.sh" "$@" > "$scratch/refused.out" 2> "$scratch/refused.err"; then
        echo 'tool asset mismatch or unsafe input was accepted' >&2; exit 1
    fi
    [[ ! -s $scratch/refused.out && -s $scratch/refused.err ]]
}
printf '%s\n' 'different declarations' > "$selected"
refuses "$source" "$selected"
rm -- "$selected"
refuses "$source" "$selected"
mkdir "$selected"
refuses "$source" "$selected"
rmdir "$selected"
ln -s "$source" "$selected"
refuses "$source" "$selected"
rm -- "$selected"
mkfifo "$selected"
refuses "$source" "$selected"
rm -- "$selected"
cp -- "$source" "$selected"
ln -s "$source" "$scratch/source-link"
refuses "$scratch/source-link" "$selected"
refuses "$scratch/missing" "$selected"
echo 'tool assets: actual digest, spaces, mismatch, missing, links and nonregular inputs PASS'
