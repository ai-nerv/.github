#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
oslo=$(command -v oslo)
scratch=$(mktemp -d /tmp/nerv-launch.XXXXXX)
workers=()
cleanup() {
    local pid
    for pid in "${workers[@]}"; do kill -TERM "$pid" 2>/dev/null || true; done
    for pid in "${workers[@]}"; do wait "$pid" 2>/dev/null || true; done
    rm -rf -- "$scratch"
}
trap cleanup EXIT
project="$scratch/project with spaces"
mkdir -p "$project/scripts" "$scratch/bin" "$scratch/home"
cp "$root/.make.lua" "$project/.make.lua"
[[ ! -f $root/scripts/select-binary.sh ]] || cp "$root/scripts/select-binary.sh" "$project/scripts/"
for file in run-family.sh preserve-binary.sh; do
    [[ ! -f $root/scripts/$file ]] || cp "$root/scripts/$file" "$project/scripts/"
done
for member in magi casper melchior balthasar; do
    mkdir -p "$project/$member/target/chosen target/release" "$project/$member/target/stray/release"
    touch "$project/$member/.make.lua"
    printf '#!/bin/sh\nexit 99\n' > "$scratch/bin/$member"
    chmod +x "$scratch/bin/$member"
done
printf '#!%s\n' "$BASH" > "$scratch/bin/oslo"
cat >> "$scratch/bin/oslo" <<'SH'
set -euo pipefail
member=${PWD##*/}
mode=$(cat ../mode)
selected="target/chosen target/release/$member"
case "$2" in
    build|build-host)
        printf '#!%s\n' "$BASH" > "$selected"
        cat >> "$selected" <<'BIN'
set -euo pipefail
jq -n --args '$ARGS.positional' -- "$0" "$@" > "$NERV_LAUNCH_RECORD"
for member in magi casper melchior balthasar; do command -v "$member"; done > "$NERV_LAUNCH_RECORD.paths"
BIN
        if [[ $mode == changed-build ]]; then printf ':\n' >> "$selected"; fi
        printf '#!/bin/sh\necho WRONG_BINARY >&2\nexit 97\n' > "target/stray/release/$member"
        chmod +x "$selected" "target/stray/release/$member"
        if [[ $member == magi ]]; then
            printf '#!/bin/sh\nexit 96\n' > "target/chosen target/release/casper"
            chmod +x "target/chosen target/release/casper"
        fi
        touch -t 202601010000 "$selected"
        touch -t 202601020000 "target/stray/release/$member"
        if [[ $member == magi ]]; then
            case "$mode" in
                missing) rm -- "$selected" ;;
                not-executable) chmod 644 "$selected" ;;
                escape) cp "$selected" ../outside; rm -- "$selected"; ln -s "$PWD/../outside" "$selected" ;;
                directory) rm -- "$selected"; mkdir "$selected" ;;
            esac
        fi
        ;;
    family-path)
        if [[ $member == magi ]]; then
            case "$mode" in
                duplicate) echo "NERV_BINARY=$selected"; echo "NERV_BINARY=$selected"; exit ;;
                empty) exit ;;
                absolute) echo "NERV_BINARY=$PWD/$selected"; exit ;;
                invalid) echo 'NERV_BINARY=../outside'; exit ;;
                traversal) echo 'NERV_BINARY=target/../../outside'; exit ;;
                oversized) head -c 65537 /dev/zero; exit ;;
                nul-selection) printf 'NERV_BINARY=target/chosen target/release/ma\0gi\n'; exit ;;
                failed-selector) exit 37 ;;
            esac
        fi
        printf 'NERV_BINARY=%s\n' "$selected"
        ;;
    *) echo "unexpected fixture recipe: $*" >&2; exit 99 ;;
esac
SH
chmod +x "$scratch/bin/oslo"
run() {
    (cd "$project" && env -i PATH="$scratch/bin:$PATH" HOME="$scratch/home" \
        XDG_CONFIG_HOME="$scratch/home/config" NERV_BASH="$BASH" \
        NERV_LAUNCH_RECORD="$scratch/argv.json" timeout --kill-after=2s 45s \
        "$oslo" make run --args="alpha 'two words' 'a\"b' --flag -x ''") > "$scratch/out" 2>&1
}
echo pass > "$project/mode"
if ! run; then cat "$scratch/out"; echo 'authoritative older artifact was not launched' >&2; exit 1; fi
binary=$(jq -r '.[0]' "$scratch/argv.json")
snapshot=${binary%/*}
[[ $snapshot == "$project/target/launch/"* && ${snapshot##*/} =~ ^[a-f0-9]{64}$ ]]
jq -e --arg binary "$snapshot/magi" \
    '. == [$binary,"alpha","two words","a\"b","--flag","-x",""]' "$scratch/argv.json" >/dev/null
for member in magi casper melchior balthasar; do
    cmp -- "$project/$member/target/chosen target/release/$member" "$snapshot/$member"
    grep -Fx "$snapshot/$member" "$scratch/argv.json.paths" >/dev/null || {
        cat "$scratch/argv.json.paths" >&2
        echo "selected sibling path was shadowed: $member" >&2
        exit 1
    }
done
run
[[ $(jq -r '.[0]' "$scratch/argv.json") == "$snapshot/magi" ]]
echo changed-build > "$project/mode"
run
next=$(dirname -- "$(jq -r '.[0]' "$scratch/argv.json")")
[[ $next != "$snapshot" ]]
(cd -- "$snapshot" && sha256sum -c binaries.sha256) >/dev/null
(cd -- "$next" && sha256sum -c binaries.sha256) >/dev/null
echo pass > "$project/mode"
for member in magi casper melchior balthasar; do
    printf '#!/bin/sh\nexit 95\n' > "$project/$member/target/chosen target/release/$member"
done
(cd -- "$snapshot" && sha256sum -c binaries.sha256) >/dev/null
NERV_LAUNCH_RECORD="$scratch/later.json" PATH="$snapshot:$PATH" "$snapshot/casper" 'after detach'
jq -e --arg binary "$snapshot/casper" '. == [$binary,"after detach"]' "$scratch/later.json" >/dev/null
chmod u+w "$snapshot/casper"
printf '#!/bin/sh\nexit 94\n' > "$snapshot/casper"
chmod 555 "$snapshot/casper"
rm -- "$scratch/argv.json"
if run; then echo 'corrupt retained family snapshot was accepted' >&2; exit 1; fi
[[ ! -e $scratch/argv.json ]]
rm -rf -- "$project/target/launch"
for mode in missing not-executable escape directory duplicate empty absolute invalid traversal oversized nul-selection failed-selector; do
    rm -f "$scratch/argv.json"
    echo "$mode" > "$project/mode"
    code=0; run || code=$?
    [[ $code != 0 && $code != 124 && $code != 137 ]] || {
        echo "invalid selection was accepted or timed out: $mode" >&2; exit 1;
    }
    [[ ! -e $scratch/argv.json ]] || { echo "invalid selection launched: $mode" >&2; exit 1; }
    [[ -z $(find "$project/target/launch" -maxdepth 1 -name '.prepare.*' -print) ]]
    if [[ -d $project/magi/target/chosen\ target/release/magi ]]; then
        rmdir "$project/magi/target/chosen target/release/magi"
    fi
done
echo pass > "$project/mode"
mkdir -p "$scratch/race-bin"
mv=$(command -v mv)
printf '#!%s\n' "$BASH" > "$scratch/race-bin/mv"
cat >> "$scratch/race-bin/mv" <<'SH'
set -euo pipefail
touch "$NERV_LAUNCH_RECORD.ready"
for ((attempt=0; attempt<500; attempt++)); do
    if [[ -f $NERV_RACE/one.json.ready && -f $NERV_RACE/two.json.ready ]]; then
        exec "$NERV_REAL_MV" "$@"
    fi
    sleep 0.01
done
echo 'concurrent snapshot publication barrier timed out' >&2
exit 98
SH
chmod +x "$scratch/race-bin/mv"
for name in one two; do
    env -i PATH="$scratch/race-bin:$scratch/bin:$PATH" HOME="$scratch/home" \
        NERV_LAUNCH_RECORD="$scratch/$name.json" NERV_RACE="$scratch" NERV_REAL_MV="$mv" \
        timeout --kill-after=2s 30s "$BASH" "$project/scripts/run-family.sh" "$name" > "$scratch/$name.out" 2>&1 &
    workers+=("$!")
done
wait "${workers[0]}" || { workers=("${workers[1]}"); cat "$scratch/one.out"; exit 1; }
workers=("${workers[1]}")
wait "${workers[0]}" || { workers=(); cat "$scratch/two.out"; exit 1; }
workers=()
[[ $(jq -r '.[0]' "$scratch/one.json") == $(jq -r '.[0]' "$scratch/two.json") ]]
[[ $(find "$project/target/launch" -mindepth 1 -maxdepth 1 -type d | wc -l) == 1 ]]
snapshot=$(dirname -- "$(jq -r '.[0]' "$scratch/one.json")")
for unsafe in permissions symlink hardlink; do
    case "$unsafe" in
        permissions) chmod 755 "$project/target/launch" ;;
        symlink) mv "$snapshot/casper" "$scratch/held-casper"; ln -s "$scratch/held-casper" "$snapshot/casper" ;;
        hardlink) ln "$snapshot/casper" "$scratch/held-casper" ;;
    esac
    rm -f "$scratch/argv.json"
    if run; then echo "unsafe snapshot accepted: $unsafe" >&2; exit 1; fi
    [[ ! -e $scratch/argv.json ]]
    case "$unsafe" in
        permissions) chmod 700 "$project/target/launch" ;;
        symlink) rm "$snapshot/casper"; mv "$scratch/held-casper" "$snapshot/casper" ;;
        hardlink) rm "$scratch/held-casper" ;;
    esac
done
echo 'launch selection: isolated names, retained bytes, atomic publication, argv and rejection cases PASS'
