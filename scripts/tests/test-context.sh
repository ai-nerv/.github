#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
scratch=$(mktemp -d /tmp/nerv-context-test.XXXXXXXX)
wrapper=
finish() {
    if [[ -n $wrapper ]]; then
        kill -TERM "$wrapper" 2>/dev/null || true
        wait "$wrapper" 2>/dev/null || true
    fi
    rm -rf -- "$scratch"
}
trap finish EXIT
export CONTEXT_TEST_ROOT="$root" CONTEXT_TEST_WORK="$scratch"
export CONTEXT_TEST_MARKER="nerv-context-${scratch##*/}"
cat > "$scratch/probe.sh" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
[[ $# == 2 && $2 == 'spaces "quotes' ]]
"$BASH" "$CONTEXT_TEST_ROOT/scripts/context-proof.sh" > "$CONTEXT_TEST_WORK/proof.json"
printf '%s\n' "$NERV_TEST_ANCHOR" > "$CONTEXT_TEST_WORK/anchor"
touch "/var/tmp/$CONTEXT_TEST_MARKER"
touch "/tmp/$CONTEXT_TEST_MARKER"
[[ $(stat -Lc %u /) == 0 && $(stat -Lc '%u:%a' /tmp) == 0:1777 ]]
[[ -e "$NERV_TEST_ANCHOR/$CONTEXT_TEST_MARKER" ]]
[[ -z $(trap -p INT) && -z $(trap -p QUIT) ]]
case "$1" in
    pass)
        "$BASH" "$CONTEXT_TEST_ROOT/scripts/test-context.sh" "$BASH" -c \
            '[[ -e /var/tmp/$CONTEXT_TEST_MARKER ]]'
        ;;
    fail) exit 37 ;;
    cancel)
        echo $$ > "$CONTEXT_TEST_WORK/pid"
        touch "$CONTEXT_TEST_WORK/ready"
        exec sleep 600
        ;;
    *) exit 99 ;;
esac
SH
for mode in pass fail; do
    code=0
    "$BASH" "$root/scripts/test-context.sh" "$BASH" "$scratch/probe.sh" "$mode" 'spaces "quotes' \
        > "$scratch/$mode.log" 2>&1 || code=$?
    expected=0; [[ $mode != fail ]] || expected=37
    [[ $code == "$expected" ]] || { cat "$scratch/$mode.log"; exit 1; }
    jq -e '.kind == "private-var-tmp" and .uid == 0 and .anchor != .host_anchor' "$scratch/proof.json" >/dev/null
    [[ ! -e $(cat "$scratch/anchor") && ! -e /var/tmp/$CONTEXT_TEST_MARKER && ! -e /tmp/$CONTEXT_TEST_MARKER ]]
done
if NERV_TEST_ANCHOR=/var/tmp NERV_HOST_TMP_ID=$(stat -Lc '%d:%i' /var/tmp) \
    "$BASH" "$root/scripts/test-context.sh" touch "$scratch/unsafe" > "$scratch/refusal.log" 2>&1; then
    echo 'forged context was accepted' >&2; exit 1
fi
[[ ! -e $scratch/unsafe ]]
"$BASH" "$root/scripts/test-context.sh" "$BASH" "$scratch/probe.sh" cancel 'spaces "quotes' \
    > "$scratch/cancel.log" 2>&1 &
wrapper=$!
for ((attempt=0; attempt<400; attempt++)); do
    [[ ! -f $scratch/ready ]] || break
    kill -0 "$wrapper" || { cat "$scratch/cancel.log"; exit 1; }
    sleep 0.01
done
[[ -f $scratch/ready ]]
read -r worker < "$scratch/pid"
kill -TERM "$wrapper"
code=0; wait "$wrapper" || code=$?
wrapper=
[[ $code == 143 && ! -d /proc/$worker ]]
[[ ! -e $(cat "$scratch/anchor") && ! -e /var/tmp/$CONTEXT_TEST_MARKER && ! -e /tmp/$CONTEXT_TEST_MARKER ]]
echo 'private test context: mount, reuse, refusal, argv, status and cancellation PASS'
