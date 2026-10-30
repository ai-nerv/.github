#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
mkdir -p "$root/target/evaluation"
report=$(mktemp -d "$root/target/evaluation/world-tests-XXXXXXXX")
mkdir "$report/case"
passed=0
listener=
running=
finish() {
    local code=$?
    trap - EXIT
    if [[ -n $running ]]; then kill -TERM "$running" 2>/dev/null || true; wait "$running" 2>/dev/null || true; fi
    if [[ -n $listener ]]; then kill "$listener" 2>/dev/null || true; wait "$listener" 2>/dev/null || true; fi
    jq -n --argjson code "$code" --argjson passed "$passed" \
        '{schema:1,scope:"evaluation-world-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$passed}' > "$report/summary.json"
    printf 'Evaluation world test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
printf 'host-canary-preserved\n' > "$report/host-canary"
"$root/target/evaluation/bin/eval-world-probe" listen "$report/port" &
listener=$!
for _ in {1..100}; do [[ ! -s $report/port ]] || break; sleep 0.02; done
port=$(cat "$report/port")
exec {host_connection}<>"/dev/tcp/127.0.0.1/$port"
exec {host_connection}>&-
run_case() {
    local name=$1 expected=$2 timeout=${3:-10000} code=0
    EVALUATION_HOST_SECRET=must-not-enter-world bash "$root/scripts/evaluation/world.sh" "$report" case "$timeout" \
        /runner/bin/bash /input/driver.sh "$report/host-canary" "$port" > "$report/$name.out" 2> "$report/$name.err" || code=$?
    [[ $code == "$expected" ]] || { cat "$report/$name.out" "$report/$name.err" >&2; echo "world $name exited $code instead of $expected" >&2; return 1; }
    world=$(sed -n 's/^Evaluation world evidence: //p' "$report/$name.out")
    [[ -n $world ]]
    [[ $(cat "$report/host-canary") == host-canary-preserved ]]
    kill -0 "$listener"
}
cat > "$report/case/driver.sh" <<'SH'
set -euo pipefail
[[ ! -v EVALUATION_HOST_SECRET && ! -v OPENAI_API_KEY && ! -v HOME_FROM_HOST ]]
[[ $HOME == /world/home && $XDG_RUNTIME_DIR == /world/runtime && $(id -u) == 0 ]]
[[ ! -e $1 && ! -e /receipt ]]
printf 'discarded\n' > /dev/null
cat < /dev/null
! touch /input/changed
! touch /runner/changed
! touch /outside-world
eval-world-probe ancestors
eval-world-probe network "$2"
bwrap --unshare-pid --ro-bind / / --proc /proc --die-with-parent -- /runner/bin/true
printf 'world-result\n' > result.txt
printf '{"checked":true}\n' > "$EVAL_EVIDENCE/check.json"
SH
run_case isolated 0
jq -e '.status=="WORLD_COMPLETED"' "$world/summary.json" >/dev/null
jq -e '.cleanup_confirmed and .timed_out==false' "$world/receipt/outer.json" >/dev/null
[[ $(cat "$world/receipt/work/result.txt") == world-result ]]
jq -e '.checked' "$world/receipt/evidence/check.json" >/dev/null
grep -Fx 'protected-supervisor-ok' "$world/receipt/worker.stdout" >/dev/null
grep -Fx 'private-loopback-ok' "$world/receipt/worker.stdout" >/dev/null
passed=$((passed+1))
printf 'exit 7\n' > "$report/case/driver.sh"
run_case failed 1
jq -e '.exit_code==7 and .leaked_processes==0 and .remaining_processes==0' "$world/receipt/inside.json" >/dev/null
passed=$((passed+1))
printf 'eval-world-probe orphan\n' > "$report/case/driver.sh"
run_case leaked 1
jq -e '.exit_code==0 and .leaked_processes>0 and .remaining_processes==0' "$world/receipt/inside.json" >/dev/null
jq -e '.cleanup_confirmed' "$world/receipt/outer.json" >/dev/null
passed=$((passed+1))
printf 'sleep 0.8\nsleep 0.8\nsleep 0.8\n' > "$report/case/driver.sh"
run_case deadline 124 1500
jq -e '.timed_out and .cleanup_confirmed and .elapsed_ms>=1500 and .elapsed_ms<5000' "$world/receipt/outer.json" >/dev/null
passed=$((passed+1))
printf 'eval-world-probe flood\n' > "$report/case/driver.sh"
run_case flooded 1
jq -e '.output_limit_exceeded and .remaining_processes==0' "$world/receipt/inside.json" >/dev/null
[[ $(wc -c < "$world/receipt/worker.stdout") -le 1048576 ]]
passed=$((passed+1))
printf 'ln -s /proc/1/fd/1 unsafe\n' > "$report/case/driver.sh"
run_case unsafe-export 1
jq -e '.exported==false' "$world/receipt/inside.json" >/dev/null
passed=$((passed+1))
printf 'eval-world-probe nested-orphan\n' > "$report/case/driver.sh"
run_case nested-leak 1
jq -e '.exit_code==0 and .leaked_processes>0 and .remaining_processes==0' "$world/receipt/inside.json" >/dev/null
jq -e '.cleanup_confirmed' "$world/receipt/outer.json" >/dev/null
passed=$((passed+1))
printf 'echo retained > "$EVAL_EVIDENCE/interrupted.txt"\necho ready\nsleep 30\n' > "$report/case/driver.sh"
for signal in TERM KILL; do
    bash "$root/scripts/evaluation/world.sh" "$report" case 10000 /runner/bin/bash /input/driver.sh \
        > "$report/interrupted-$signal.out" 2> "$report/interrupted-$signal.err" &
    running=$!
    ready=
    for _ in {1..200}; do
        for child in $(ps -o pid= --ppid "$running"); do
            [[ -r /proc/$child/cmdline ]] || continue
            mapfile -d '' -t arguments < "/proc/$child/cmdline"
            if [[ ${arguments[1]:-} == outer && -s ${arguments[2]:-}/worker.stdout ]]; then
                ready=${arguments[2]}
                break
            fi
        done
        [[ -z $ready ]] || break
        sleep 0.02
    done
    [[ -n $ready ]]
    kill -"$signal" "$running"
    code=0; wait "$running" || code=$?
    running=
    if [[ $signal == TERM ]]; then [[ $code == 143 ]]; else [[ $code == 137 ]]; fi
    for _ in {1..250}; do [[ ! -s $ready/outer.json ]] || break; sleep 0.02; done
    jq -e '.interrupted==15 and .cleanup_confirmed and .timed_out==false' "$ready/outer.json" >/dev/null
    [[ $(cat "$ready/evidence/interrupted.txt") == retained ]]
    jq -e '.remaining_processes==0 and .exported' "$ready/inside.json" >/dev/null
    kill -0 "$listener"
    passed=$((passed+1))
done
code=0
printf '4\n' > "$report/case/client-attempt-limit.txt"
cat > "$report/case/driver.sh" <<'SH'
set -euo pipefail
eval-world-probe reserve 2 &
one=$!
eval-world-probe reserve 2 &
two=$!
wait "$one"
wait "$two"
SH
run_case admission-shared 0
jq -se '.[0].limit==4 and .[-1].status=="STOPPED" and .[-1].admitted==4 and
    [ .[]|select(.event=="admit")|.attempt ]==[1,2,3,4] and
    ([.[]|select(.event=="admit")|.peer_pid]|unique|length)==2' "$world/receipt/client-attempts.jsonl" >/dev/null
passed=$((passed+1))
printf 'eval-world-probe reserve 5\n' > "$report/case/driver.sh"
run_case admission-limit 1
jq -se '.[-1].status=="FAIL" and .[-1].admitted==4 and any(.[]; .event=="reject" and .reason=="attempt_limit")' \
    "$world/receipt/client-attempts.jsonl" >/dev/null
jq -e '.client_admission_failed and .remaining_processes==0' "$world/receipt/inside.json" >/dev/null
passed=$((passed+1))
printf 'eval-world-probe admission-partial\n' > "$report/case/driver.sh"
run_case admission-partial 1
jq -e '.client_admission_failed and .remaining_processes==0' "$world/receipt/inside.json" >/dev/null
jq -se '.[-1].status=="FAIL" and .[-1].admitted==0' "$world/receipt/client-attempts.jsonl" >/dev/null
passed=$((passed+1))
code=0
"$root/target/evaluation/bin/eval-world" inside /runner/bin/true > "$report/not-init.out" 2> "$report/not-init.err" || code=$?
[[ $code != 0 ]]
passed=$((passed+1))
printf 'Evaluation world checks passed: %s\n' "$passed"
