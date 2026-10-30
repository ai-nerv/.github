#!/usr/bin/env bash
set -euo pipefail
[[ $# == 2 || $# == 3 ]] || { echo 'usage: selected-tools.sh SOURCE SELECTED [SCOPE]' >&2; exit 2; }
source=$1
selected=$2
scope=${3:-family}
for file in "$source" "$selected"; do
    [[ -f $file && ! -L $file ]] || { echo 'selected tool declarations require regular non-symlink files' >&2; exit 1; }
done
source_sha=$(sha256sum < "$source"); source_sha=${source_sha%% *}
selected_sha=$(sha256sum < "$selected"); selected_sha=${selected_sha%% *}
[[ $source_sha =~ ^[a-f0-9]{64}$ && $selected_sha == "$source_sha" ]] || {
    echo 'selected tool declarations differ from the declared source' >&2; exit 1;
}
jq -n --arg scope "$scope" --arg sha256 "$selected_sha" \
    '{scope:$scope,owner:"casper",asset:"tools.lua",sha256:$sha256}'
