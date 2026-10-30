#!/usr/bin/env bash

runner_identity() (
    cd -- "$1" || exit 1
    local optional=()
    if [[ -d event-observer ]]; then optional=(event-observer); fi
    find scripts target/evaluation/bin provider rust-grammar "${optional[@]}" -type f -print0 |
        LC_ALL=C sort -z | xargs -0 -r sha256sum -- || exit 1
    sha256sum tools.tsv closure
)

snapshot_world_tools() (
    local output=$1 name path item sha
    local tools=(bash sh bwrap cat cp chmod id readlink sha256sum sleep setsid head wc env mkdir touch rm ls grep dd true ln curl jq sed awk tail sort cut tr stat find timeout cc rustc tar)
    local stores=()
    for name in "${tools[@]}"; do
        path=$(realpath -e -- "$(type -P "$name")") || exit 1
        [[ $path == /nix/store/*/* ]] || { echo "world tool must come from the selected Nix shell: $name" >&2; exit 1; }
        item=${path#/nix/store/}; stores+=("/nix/store/${item%%/*}")
        sha=$(sha256sum < "$path") || exit 1
        printf '%s\t%s\t%s\n' "$name" "$path" "${sha%% *}"
    done > "$output/tools.tsv"
    nix-store --query --requisites "${stores[@]}" | LC_ALL=C sort -u > "$output/closure" || exit 1
    [[ $(wc -l < "$output/closure") -le 512 ]]
)
