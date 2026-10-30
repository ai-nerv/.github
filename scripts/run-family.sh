#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
source "$root/scripts/preserve-binary.sh"
cache="$root/target/launch"
mkdir -p -- "$root/target"
mkdir -m 700 -- "$cache" 2>/dev/null || [[ -d $cache ]]
[[ ! -L $cache && -O $cache && $(stat -c %a -- "$cache") == 700 ]] || {
    echo 'unsafe family launch directory' >&2; exit 1;
}
scratch=$(mktemp -d "$cache/.prepare.XXXXXXXX")
trap '[[ -z $scratch ]] || rm -rf -- "$scratch"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
members=(magi casper melchior balthasar)
declare -A selected=()
for member in "${members[@]}"; do
    selected[$member]=$("$BASH" "$root/scripts/select-binary.sh" "$member")
    hash=$(sha256sum < "${selected[$member]}")
    printf '%s  %s\n' "${hash%% *}" "$member" >> "$scratch/binaries.sha256"
done
hash=$(sha256sum < "$scratch/binaries.sha256")
snapshot="$cache/${hash%% *}"
expected=$(cat "$scratch/binaries.sha256")
valid_snapshot() {
    local directory=$1 entry name count=0
    [[ -d $directory && ! -L $directory && -O $directory && $(stat -c %a -- "$directory") == 700 ]] || return 1
    shopt -s nullglob dotglob
    for entry in "$directory"/*; do
        name=${entry##*/}
        case "$name" in magi|casper|melchior|balthasar|binaries.sha256) ;; *) return 1 ;; esac
        [[ -f $entry && ! -L $entry && -O $entry && $(stat -c %h -- "$entry") == 1 ]] || return 1
        if [[ $name == binaries.sha256 ]]; then
            [[ $(stat -c %a -- "$entry") == 444 ]] || return 1
        else
            [[ $(stat -c %a -- "$entry") == 555 ]] || return 1
        fi
        count=$((count + 1))
    done
    [[ $count == 5 && $(cat "$directory/binaries.sha256") == "$expected" ]] || return 1
    (cd -- "$directory" && sha256sum -c -- binaries.sha256 >/dev/null)
}
if [[ ! -e $snapshot && ! -L $snapshot ]]; then
    for member in "${members[@]}"; do
        (cd -- "$scratch" && preserve_binary "${selected[$member]}" "$member" copied.sha256 >/dev/null)
    done
    cmp -- "$scratch/binaries.sha256" "$scratch/copied.sha256"
    rm -- "$scratch/copied.sha256"
    chmod 444 -- "$scratch/binaries.sha256"
    valid_snapshot "$scratch" || { echo 'invalid prepared family snapshot' >&2; exit 1; }
    if mv -T -- "$scratch" "$snapshot" 2>/dev/null; then scratch=; fi
fi
valid_snapshot "$snapshot" || { echo 'invalid retained family snapshot' >&2; exit 1; }
if [[ -n $scratch ]]; then rm -rf -- "$scratch"; scratch=; fi
export PATH="$snapshot:$PATH"
exec "$snapshot/magi" "$@"
