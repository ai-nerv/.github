#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/deadline-tests-XXXXXXXX")
helper="$root/target/evaluation/bin/eval-world"
passed=0 running= canary=
finish() {
    local code=$?
    trap - EXIT
    if [[ -n $running ]]; then kill -TERM "$running" 2>/dev/null || true; wait "$running" 2>/dev/null || true; fi
    if [[ -n $canary ]]; then kill "$canary" 2>/dev/null || true; wait "$canary" 2>/dev/null || true; fi
    jq -n --argjson code "$code" --argjson checks "$passed" \
        '{schema:1,scope:"evaluation-controller-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$checks}' > "$report/summary.json"
    printf 'Evaluation controller test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
sleep 120 & canary=$!
run_case() {
    local name=$1 expected=$2 millis=$3 code=0
    case_dir="$report/$name"; mkdir "$case_dir"
    "$helper" control "$case_dir" "$millis" "$BASHPID" bash "$report/driver.sh" "$case_dir" \
        > "$report/$name.out" 2> "$report/$name.err" || code=$?
    [[ $code == "$expected" ]] || { cat "$report/$name.err" >&2; echo "$name: $code != $expected" >&2; return 1; }
    jq -e '.cleanup_confirmed and .elapsed_ms<7000' "$case_dir/control.json" >/dev/null
    kill -0 "$canary"
    passed=$((passed+1))
}
printf 'printf "ready\\n"\n' > "$report/driver.sh"
run_case normal 0 5000
jq -e '.exit_code==0 and .leaked_processes==0 and .timed_out==false' "$case_dir/control.json" >/dev/null
printf 'exit 7\n' > "$report/driver.sh"
run_case failed 1 5000
jq -e '.exit_code==7 and .timed_out==false' "$case_dir/control.json" >/dev/null
for stage in preparation scoring; do
    cat > "$report/driver.sh" <<'SH'
printf 'stage-entered\n' > "$1/stage"
sleep 30
SH
    run_case "$stage" 124 100
    [[ -s $case_dir/stage ]]
    jq -e '.timed_out and .limit_ms==100' "$case_dir/control.json" >/dev/null
done
cat > "$report/driver.sh" <<'SH'
sleep 0.15
printf '100\n' > "$1/limit.tmp"
mv "$1/limit.tmp" "$1/deadline-ms"
sleep 30
SH
run_case late-limit 124 5000
jq -e '.timed_out and .limit_ms==100 and .elapsed_ms<3000' "$case_dir/control.json" >/dev/null
cat > "$report/driver.sh" <<'SH'
printf '4000\n' > "$1/limit.tmp"
mv "$1/limit.tmp" "$1/deadline-ms"
sleep 0.1
printf '5000\n' > "$1/limit.tmp"
mv "$1/limit.tmp" "$1/deadline-ms"
sleep 30
SH
run_case changed-limit 1 5000
jq -e '.invalid_limit and .limit_ms==4000' "$case_dir/control.json" >/dev/null
cat > "$report/driver.sh" <<'SH'
ln -s /dev/zero "$1/deadline-ms"
sleep 30
SH
run_case unsafe-limit 1 5000
jq -e '.invalid_limit' "$case_dir/control.json" >/dev/null
cat > "$report/driver.sh" <<'SH'
setsid bash -c 'sleep 30 & echo "$!" > "$1/descendant"; wait' bash "$1" &
echo "$!" > "$1/detached"
while [[ ! -s $1/descendant ]]; do sleep 0.01; done
SH
run_case detached 1 5000
jq -e '.exit_code==0 and .leaked_processes>0' "$case_dir/control.json" >/dev/null
for name in detached descendant; do ! kill -0 "$(cat "$case_dir/$name")" 2>/dev/null; done
cat > "$report/driver.sh" <<'SH'
head -c 1048577 /dev/zero
sleep 30
SH
run_case output-cap 1 5000
jq -e '.output_limit_exceeded' "$case_dir/control.json" >/dev/null
[[ $(wc -c < "$case_dir/controller.stdout") == 1048576 ]]
cat > "$report/driver.sh" <<'SH'
printf 'ready\n' > "$1/ready"
sleep 30
SH
case_dir="$report/interrupt"; mkdir "$case_dir"
launcher=$BASHPID
"$helper" control "$case_dir" 5000 "$launcher" bash "$report/driver.sh" "$case_dir" > "$report/interrupt.out" 2> "$report/interrupt.err" &
running=$!
for _ in {1..200}; do [[ ! -s $case_dir/ready ]] || break; sleep 0.01; done
[[ -s $case_dir/ready ]]
kill -TERM "$running"
code=0; wait "$running" || code=$?; running=
[[ $code == 143 ]]
jq -e '.interrupted==15 and .cleanup_confirmed and .timed_out==false' "$case_dir/control.json" >/dev/null
kill -0 "$canary"
passed=$((passed+1))
cat > "$report/launcher.sh" <<'SH'
parent=$BASHPID
"$1" control "$2" 5000 "$parent" bash "$3" "$2" &
supervisor=$!
printf '%s\n' "$supervisor" > "$2/supervisor.pid"
wait "$supervisor"
SH
case_dir="$report/parent-death"; mkdir "$case_dir"
bash "$report/launcher.sh" "$helper" "$case_dir" "$report/driver.sh" > "$report/parent-death.out" 2> "$report/parent-death.err" &
running=$!
for _ in {1..200}; do [[ ! -s $case_dir/ready ]] || break; sleep 0.01; done
[[ -s $case_dir/ready ]]
kill -KILL "$running"
wait "$running" 2>/dev/null || true
running=$(cat "$case_dir/supervisor.pid")
for _ in {1..500}; do
    if jq -e '.interrupted==15 and .cleanup_confirmed' "$case_dir/control.json" >/dev/null 2>&1; then break; fi
    sleep 0.01
done
jq -e '.interrupted==15 and .cleanup_confirmed and .timed_out==false' "$case_dir/control.json" >/dev/null
running=
kill -0 "$canary"
passed=$((passed+1))
cat > "$report/driver.sh" <<'SH'
trap '' TERM
exec sleep 30
SH
run_case resistant 124 100
jq -e '.timed_out and .exit_code==137 and .cleanup_confirmed' "$case_dir/control.json" >/dev/null
case_dir="$report/existing"; mkdir "$case_dir"
printf 'retained\n' > "$case_dir/control.json"
if "$helper" control "$case_dir" 5000 "$BASHPID" touch "$case_dir/executed" > "$report/existing.out" 2> "$report/existing.err"; then exit 1; fi
[[ $(cat "$case_dir/control.json") == retained && ! -e $case_dir/executed ]]
passed=$((passed+1))
mkdir "$report/shim"
printf '#!%s\nexit 0\n' "$BASH" > "$report/shim/bash"
chmod 700 "$report/shim/bash"
code=0
PATH="$report/shim:$PATH" "$BASH" "$root/scripts/evaluation/run-workload.sh" "$report" \
    "$(printf '%064d' 0)" output-only-overflow baseline > "$report/missing-body.out" 2> "$report/missing-body.err" || code=$?
[[ $code == 1 ]]
missing=$(sed -n 's/^Evaluation bound workload: //p' "$report/missing-body.out")
jq -e '.status=="FAIL" and .failure=="invalid_result" and .exit_code==1' "$missing/summary.json" >/dev/null
jq -e '.exit_code==0 and .cleanup_confirmed' "$missing/control.json" >/dev/null
passed=$((passed+1))
for owner in 1 "$canary"; do
    case_dir="$report/unrelated-owner-$owner"; mkdir "$case_dir"
    if "$helper" control-owned "$case_dir" 5000 "$BASHPID" "$owner" touch "$case_dir/executed" \
        > "$case_dir/out" 2> "$case_dir/err"; then exit 1; fi
    [[ ! -e $case_dir/executed && ! -e $case_dir/control.json ]]
    kill -0 "$canary"
    passed=$((passed+1))
done
cat > "$report/owned-launcher.sh" <<'SH'
parent=$BASHPID
"$1" control-owned "$2" 5000 "$parent" "$3" touch "$2/executed"
SH
case_dir="$report/owned"; mkdir "$case_dir"
bash "$report/owned-launcher.sh" "$helper" "$case_dir" "$BASHPID" > "$case_dir/out" 2> "$case_dir/err"
[[ -e $case_dir/executed ]]
jq -e '.exit_code==0 and .interrupted==0 and .cleanup_confirmed and .leaked_processes==0' "$case_dir/control.json" >/dev/null
passed=$((passed+1))
printf 'Evaluation controller checks passed: %s\n' "$passed"
