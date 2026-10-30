#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
[[ $# -ge 4 ]] || { echo 'usage: world.sh ROOT FIXTURE TIMEOUT_MS [--provider RELATIVE SHA256] [--artifact DESCRIPTOR MANIFEST VARIANT SHA256] [--rust-grammar RELATIVE SHA256] [--event-observer RELATIVE SHA256 drain|stall] COMMAND [ARGS]' >&2; exit 2; }
input_root=$1 fixture=$2 millis=$3
shift 3
provider_source=
provider_sha=
provider_verified=false
artifact_descriptor= artifact_manifest= artifact_variant= artifact_sha= artifact_receipt=
artifact_verified=false
grammar_source= grammar_sha=
grammar_verified=false
observer_source= observer_sha= observer_mode=
observer_verified=false
while (( $# > 0 )); do
    case $1 in
        --provider)
            [[ $# -ge 4 && -z $provider_source && -n $2 && $3 =~ ^[0-9a-f]{64}$ ]] || { echo 'invalid provider selection' >&2; exit 2; }
            provider_source=$2 provider_sha=$3
            shift 3 ;;
        --artifact)
            [[ $# -ge 6 && -z $artifact_descriptor && -n $2 && -n $3 && ( $4 == baseline || $4 == candidate ) && $5 =~ ^[0-9a-f]{64}$ ]] || {
                echo 'invalid family artifact selection' >&2; exit 2;
            }
            artifact_descriptor=$2 artifact_manifest=$3 artifact_variant=$4 artifact_sha=$5
            shift 5 ;;
        --rust-grammar)
            [[ $# -ge 4 && -z $grammar_source && -n $2 && $3 =~ ^[0-9a-f]{64}$ ]] || { echo 'invalid Rust grammar selection' >&2; exit 2; }
            grammar_source=$2 grammar_sha=$3
            shift 3 ;;
        --event-observer)
            [[ $# -ge 5 && -z $observer_source && -n $2 && $3 =~ ^[0-9a-f]{64}$ && ( $4 == drain || $4 == stall ) ]] || {
                echo 'invalid event observer selection' >&2; exit 2;
            }
            observer_source=$2 observer_sha=$3 observer_mode=$4
            shift 4 ;;
        *) break ;;
    esac
done
[[ -z $grammar_source || -n $artifact_descriptor ]] || { echo 'Rust grammar requires a family artifact' >&2; exit 2; }
[[ -z $observer_source || -n $artifact_descriptor ]] || { echo 'event observer requires a family artifact' >&2; exit 2; }
[[ $millis =~ ^[1-9][0-9]{0,4}$ && $millis -le 60000 && $# -ge 1 && $# -le 64 ]] || { echo 'invalid deadline or argv' >&2; exit 2; }
source "$root/scripts/preserve-binary.sh"
mkdir -p "$root/target/evaluation"
report=$(mktemp -d "$root/target/evaluation/world-XXXXXXXX")
mkdir -p "$report/runner/bin" "$report/receipt"
touch "$report/binaries.sha256"
supervisor=
stop_signal=TERM
input_identity() (
    cd -- "$report" || exit 1
    find input -type f -print0 | LC_ALL=C sort -z | xargs -0 -r sha256sum -- || exit 1
    sha256sum -- runner/closure runner/tool-path || exit 1
    find runner/bin -type l -printf '%p -> %l\0' | LC_ALL=C sort -z | sha256sum
)
finish() {
    local code=$?
    trap - EXIT
    if [[ -n $supervisor ]]; then
        kill -"$stop_signal" "$supervisor" 2>/dev/null || true
        for _ in {1..100}; do kill -0 "$supervisor" 2>/dev/null || break; sleep 0.05; done
        kill -KILL "$supervisor" 2>/dev/null || true
        wait "$supervisor" 2>/dev/null || true
    fi
    if [[ -s $report/binaries.sha256 ]] && ! verify_preserved_binaries "$report/binaries.sha256" > "$report/integrity.log" 2>&1; then code=1; fi
    if [[ -s $report/inputs.sha256 ]]; then
        if ! input_identity > "$report/inputs-after.sha256" || ! cmp -s "$report/inputs.sha256" "$report/inputs-after.sha256"; then code=1; fi
    fi
    if [[ $artifact_verified == true ]]; then
        if ! verify_preserved_binaries "$artifact_receipt/binaries.sha256" > "$report/family-binaries-integrity.log" 2>&1 ||
           ! sha256sum -c "$artifact_receipt/inputs.sha256" > "$report/family-inputs-integrity.log" 2>&1; then code=1; fi
    fi
    jq -n --argjson code "$code" --arg provider "$provider_sha" --argjson verified "$provider_verified" \
        --arg artifact "$artifact_sha" --argjson artifact_verified "$artifact_verified" --arg variant "$artifact_variant" \
        --arg grammar "$grammar_sha" --argjson grammar_verified "$grammar_verified" \
        --arg observer "$observer_sha" --arg mode "$observer_mode" --argjson observer_verified "$observer_verified" \
        '{schema:1,scope:"evaluation-isolated-world",status:(if $code==0 then "WORLD_COMPLETED" else "FAIL" end),exit_code:$code,
          provider_sha256:(if $verified then $provider else null end),
          artifact_sha256:(if $artifact_verified then $artifact else null end),
          rust_grammar_sha256:(if $grammar_verified then $grammar else null end),
          variant:(if $artifact_verified then $variant else null end)} +
          (if $observer_verified then {event_observer:{schema:1,sha256:$observer,mode:$mode}} else {} end)' > "$report/summary.json"
    printf 'Evaluation world evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
trap 'stop_signal=INT; exit 130' INT
trap 'exit 143' TERM
for helper in eval-input eval-world eval-world-probe; do
    preserve_binary "$root/target/evaluation/bin/$helper" "$report/runner/bin/$helper" "$report/binaries.sha256" > "$report/$helper.sha256"
done
if [[ -n $provider_source ]]; then
    "$report/runner/bin/eval-input" build-binary "$input_root" "$provider_source" "$report/runner/provider" > "$report/provider-counts.json"
    actual=$(sha256sum < "$report/runner/provider/input"); actual=${actual%% *}
    [[ $actual == "$provider_sha" ]] || { echo 'provider artifact digest mismatch' >&2; exit 1; }
    sha256sum "$report/runner/provider/input" >> "$report/binaries.sha256"
    provider_verified=true
fi
family_mounts=()
if [[ -n $artifact_descriptor ]]; then
    bash "$root/scripts/evaluation/artifact.sh" "$input_root" "$artifact_descriptor" "$artifact_manifest" "$artifact_variant" \
        > "$report/artifact.out" 2> "$report/artifact.err"
    artifact_receipt=$(sed -n 's/^Evaluation artifact evidence: //p' "$report/artifact.out")
    [[ -n $artifact_receipt ]]
    jq -e --arg sha "$artifact_sha" --arg variant "$artifact_variant" \
        '.status=="ARTIFACT_VALIDATED" and .artifact_sha256==$sha and .variant==$variant and .workers_started==0' "$artifact_receipt/summary.json" >/dev/null
    verify_preserved_binaries "$artifact_receipt/binaries.sha256" > "$report/family-binaries-before.log"
    sha256sum -c "$artifact_receipt/inputs.sha256" > "$report/family-inputs-before.log"
    artifact_verified=true
    family_mounts=(--ro-bind "$artifact_receipt" /family)
    for name in magi casper melchior balthasar; do
        family_mounts+=(--ro-bind "$artifact_receipt/members/$name/input" "/opt/evaluation/bin/$name")
        ln -s "/opt/evaluation/bin/$name" "$report/runner/bin/$name"
    done
fi
if [[ -n $grammar_source ]]; then
    "$report/runner/bin/eval-input" binary "$input_root" "$grammar_source" "$report/runner/rust-grammar" > "$report/grammar-counts.json"
    actual=$(sha256sum < "$report/runner/rust-grammar/input"); actual=${actual%% *}
    [[ $actual == "$grammar_sha" ]] || { echo 'Rust grammar digest mismatch' >&2; exit 1; }
    header=$(od -An -v -tx1 -N20 "$report/runner/rust-grammar/input" | tr -d ' \n')
    [[ $header == 7f454c46020101* && ( ${header:14:2} == 00 || ${header:14:2} == 03 ) &&
       ( ${header:32:4} == 0200 || ${header:32:4} == 0300 ) && ${header:36:4} == 3e00 ]] || {
        echo 'Rust grammar must be a Linux x86_64 ELF executable' >&2; exit 1;
    }
    sha256sum "$report/runner/rust-grammar/input" >> "$report/binaries.sha256"
    family_mounts+=(--ro-bind "$report/runner/rust-grammar/input" /opt/evaluation/grammars/bin/rust)
    grammar_verified=true
fi
if [[ -n $observer_source ]]; then
    "$report/runner/bin/eval-input" binary "$input_root" "$observer_source" "$report/runner/event-observer" > "$report/observer-counts.json"
    actual=$(sha256sum < "$report/runner/event-observer/input"); actual=${actual%% *}
    [[ $actual == "$observer_sha" ]] || { echo 'event observer digest mismatch' >&2; exit 1; }
    header=$(od -An -v -tx1 -N20 "$report/runner/event-observer/input" | tr -d ' \n')
    [[ $header == 7f454c46020101* && ( ${header:14:2} == 00 || ${header:14:2} == 03 ) &&
       ( ${header:32:4} == 0200 || ${header:32:4} == 0300 ) && ${header:36:4} == 3e00 ]] || {
        echo 'event observer must be a Linux x86_64 ELF executable' >&2; exit 1;
    }
    sha256sum "$report/runner/event-observer/input" >> "$report/binaries.sha256"
    jq -n --arg sha "$observer_sha" --arg mode "$observer_mode" --argjson timeout "$millis" \
        '{schema:1,sha256:$sha,mode:$mode,timeout_ms:$timeout}' > "$report/runner/event-observer-selection.json"
    sha256sum "$report/runner/event-observer-selection.json" >> "$report/binaries.sha256"
    observer_verified=true
fi
tools=(bash sh bwrap cat cp chmod id readlink sha256sum sleep setsid head wc env mkdir touch rm ls grep dd true ln curl jq sed awk tail sort cut tr stat find timeout cc tar)
stores=()
tool_paths=()
for name in "${tools[@]}" rustc; do
    path=$(realpath -e -- "$(type -P "$name")")
    [[ $path == /nix/store/*/* ]] || { echo "world tool must come from the selected Nix shell: $name" >&2; exit 1; }
    item=${path#/nix/store/}; item=${item%%/*}
    stores+=("/nix/store/$item")
    tool_paths+=("${path%/*}")
    if [[ $name == bwrap ]]; then
        preserve_binary "$path" "$report/runner/bin/bwrap" "$report/binaries.sha256" > "$report/bwrap.sha256"
    else
        ln -s "$path" "$report/runner/bin/$name"
    fi
done
printf '/runner/bin' > "$report/runner/tool-path"
if [[ $artifact_verified == true ]]; then printf ':/opt/evaluation/bin' >> "$report/runner/tool-path"; fi
while read -r path; do printf ':%s' "$path" >> "$report/runner/tool-path"; done < <(printf '%s\n' "${tool_paths[@]}" | LC_ALL=C sort -u)
printf '\n' >> "$report/runner/tool-path"
nix-store --query --requisites "${stores[@]}" | LC_ALL=C sort -u > "$report/runner/closure"
[[ $(wc -l < "$report/runner/closure") -le 512 ]]
mounts=()
while read -r path; do
    [[ $path == /nix/store/* && ${path#/nix/store/} != */* && ! -L $path && ( -d $path || -f $path ) ]] || {
        echo 'invalid runtime closure path' >&2; exit 1;
    }
    mounts+=(--ro-bind "$path" "$path")
done < "$report/runner/closure"
"$report/runner/bin/eval-input" tree "$input_root" "$fixture" "$report/input" 16777216 256 > "$report/input-counts.json"
input_identity > "$report/inputs.sha256"
launcher=$BASHPID
"$report/runner/bin/eval-world" outer "$report/receipt" "$millis" "$launcher" "$report/runner/bin/bwrap" \
    --unshare-user --uid 0 --gid 0 --unshare-pid --as-pid-1 --unshare-net --unshare-ipc --unshare-uts --hostname nerv-evaluation \
    --die-with-parent --new-session --cap-add ALL --info-fd 1 \
    --ro-bind "$report/runner" /runner --ro-bind "$report/input" /input --bind "$report/receipt" /receipt \
    "${family_mounts[@]}" \
    --size 134217728 --tmpfs /world --size 16777216 --tmpfs /tmp --chmod 1777 /tmp \
    --dir /var --size 16777216 --tmpfs /var/tmp --chmod 1777 /var/tmp --dev /dev --proc /proc \
    "${mounts[@]}" --remount-ro / --clearenv -- /runner/bin/eval-world inside "$@" &
supervisor=$!
code=0
wait "$supervisor" || code=$?
supervisor=
(( code == 0 )) || exit "$code"
jq -e '.exit_code==0 and .timed_out==false and .interrupted==0 and .cleanup_confirmed and (.output_limit_exceeded|not)' "$report/receipt/outer.json" >/dev/null
jq -e '.exit_code==0 and .leaked_processes==0 and .remaining_processes==0 and (.output_limit_exceeded|not) and .streams_complete and .exported' "$report/receipt/inside.json" >/dev/null
