#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
[[ $# -gt 0 ]] || { echo 'test-context.sh requires a command' >&2; exit 2; }
# Descriptors the caller left open end here; 255 is the script bash is reading.
for descriptor in /proc/self/fd/*; do
    descriptor=${descriptor##*/}
    if ((descriptor > 2 && descriptor != 255)); then exec {descriptor}>&-; fi
done
if [[ -n ${NERV_TEST_ANCHOR:-} ]]; then
    "$BASH" "$root/scripts/context-proof.sh" >/dev/null
    exec "$@"
fi
backend=$(command -v bwrap) || { echo 'missing test prerequisite: bubblewrap' >&2; exit 2; }
command -v setsid >/dev/null || { echo 'missing test prerequisite: setsid' >&2; exit 2; }
scratch=$(mktemp -d /tmp/nerv-native-context.XXXXXXXX)
child=
finish() {
    local code=$?
    trap - EXIT INT TERM
    if [[ -n $child ]]; then
        kill -TERM -- "-$child" 2>/dev/null || true
        for ((attempt=0; attempt<20; attempt++)); do
            kill -0 -- "-$child" 2>/dev/null || break
            sleep 0.1
        done
        kill -KILL -- "-$child" 2>/dev/null || true
        wait "$child" 2>/dev/null || true
    fi
    rm -rf -- "$scratch" || code=1
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
mkdir -p "$scratch/bin" "$scratch/var-tmp" "$scratch/root"/{home,tmp,var}
chmod 755 "$scratch/root" "$scratch/root/home" "$scratch/root/var"
chmod 1777 "$scratch/root/tmp"
chmod 1777 "$scratch/var-tmp"
cp -- "$backend" "$scratch/bin/bwrap"
chmod 555 "$scratch/bin/bwrap"
[[ $(stat -c %h "$scratch/bin/bwrap") == 1 ]]
export NERV_HOST_TMP_ID
NERV_HOST_TMP_ID=$(stat -Lc '%d:%i' /var/tmp)
export NERV_TEST_ANCHOR="$scratch/var-tmp"
export PATH="$scratch/bin:$PATH"
mounts=(--bind "$scratch/root" /)
mount_entry() {
    local source=$1 destination=$2
    if [[ -L $source ]]; then
        mounts+=(--symlink "$(readlink -- "$source")" "$destination")
    else
        mounts+=(--bind-try "$source" "$destination")
    fi
}
shopt -s dotglob nullglob
for entry in /*; do
    case "$entry" in /home|/tmp|/var|/proc|/dev) continue ;; esac
    mount_entry "$entry" "$entry"
done
for parent in home var; do
    for entry in /"$parent"/*; do
        [[ $entry != /var/tmp && $entry != "$scratch" ]] || continue
        mount_entry "$entry" "$entry"
    done
done
declare -A temporary_roots=()
keep_temporary_root() {
    local value=$1 leaf
    [[ $value == /tmp/* ]] || return 0
    leaf=${value#/tmp/}; leaf=${leaf%%/*}
    [[ -n $leaf && /tmp/$leaf != "$scratch" ]] || return 0
    temporary_roots["$leaf"]=1
}
keep_temporary_root "$PWD"
for argument in "$@"; do keep_temporary_root "$argument"; done
while IFS= read -r -d '' setting; do
    value=${setting#*=}
    keep_temporary_root "$value"
    case "${setting%%=*}" in
        PATH|LD_LIBRARY_PATH|LIBRARY_PATH|CPATH|PKG_CONFIG_PATH)
            IFS=: read -r -a paths <<< "$value"
            for path in "${paths[@]}"; do keep_temporary_root "$path"; done
            ;;
    esac
done < <(env -0)
(( ${#temporary_roots[@]} <= 256 )) || { echo 'too many inherited temporary roots' >&2; exit 2; }
for leaf in "${!temporary_roots[@]}"; do mount_entry "/tmp/$leaf" "/tmp/$leaf"; done
mounts+=(--bind "$scratch/bin" "$scratch/bin" --bind "$scratch/var-tmp" "$scratch/var-tmp")
env --default-signal=INT,QUIT setsid --wait "$scratch/bin/bwrap" \
    --unshare-user --uid 0 --gid 0 "${mounts[@]}" --dev /dev --proc /proc \
    --cap-add ALL --bind "$scratch/var-tmp" /var/tmp --die-with-parent \
    "$BASH" -c '"$1" "$2" >/dev/null || exit $?; shift 2; exec "$@"' \
    context "$BASH" "$root/scripts/context-proof.sh" "$@" &
child=$!
set +e
wait "$child"
code=$?
child=
exit "$code"
