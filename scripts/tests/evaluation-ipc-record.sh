#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/ipc-record-tests-XXXXXXXX")
recorder="$root/target/evaluation/bin/eval-world"
passed=0 running=
finish() {
    local code=$?
    trap - EXIT
    if [[ -n $running ]]; then kill -TERM "$running" 2>/dev/null || true; wait "$running" 2>/dev/null || true; fi
    jq -n --argjson code "$code" --argjson passed "$passed" \
      '{schema:1,scope:"evaluation-ipc-record-tests",exit_code:$code,status:(if $code==0 then "PASS" else "FAIL" end),checks:$passed,live_requests:0}' > "$report/summary.json"
    printf 'Evaluation IPC recorder test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
cat > "$report/echo" <<SH
#!$(type -P bash)
exec cat
SH
cat > "$report/events" <<SH
#!$(type -P bash)
cat > /dev/null
printf '%s\n' '{"event":"spent","usage":{"input":7,"output":2,"cache_read":3,"cache_write":4,"cost_micros":5,"estimated_micros":6}}' '{"event":"retrying","attempt":1,"of":2,"seconds":0.125}' '{"event":"spent","usage":{"input":14,"output":4,"cache_read":6,"cache_write":8,"cost_micros":10,"estimated_micros":12}}' '{"event":"stop","reason":"end_turn"}'
SH
cat > "$report/fail" <<SH
#!$(type -P bash)
cat > /dev/null
printf '%s\n' '{"event":"failed","why":"transport","message":"fixture"}'
exit 7
SH
cat > "$report/sleeper" <<SH
#!$(type -P bash)
echo \$\$ > "$report/child.pid"
exec sleep 30
SH
chmod 700 "$report/echo" "$report/events" "$report/fail" "$report/sleeper"
refuse() { if timeout 5 "$@" > "$report/refused.out" 2> "$report/refused.err"; then exit 1; else [[ $? != 124 ]]; fi; passed=$((passed+1)); }
init() { "$recorder" record init "$report/$1"; }
ask() { "$recorder" record ask "$report/$1" "$report/$2" ask --json; }
init exact
printf '{"model":"synthetic","context":{"tools":[],"messages":[]},"wants":{}}' > "$report/request"
ask exact events < "$report/request" > "$report/forwarded"
cmp "$report/request" "$report/exact/000-request.json"
cmp "$report/forwarded" "$report/exact/000-response.jsonl"
jq -e '.transport_complete and .exit_code==0 and .complete_run==false' "$report/exact/000-receipt.json" >/dev/null
"$recorder" record seal "$report/exact"
jq -e '.sealed and .capture_complete and .calls==1 and .complete_run==false and .helper_attribution==null' "$report/exact/summary.json" >/dev/null
passed=$((passed+4))
refuse "$recorder" record init "$report/exact"
refuse "$recorder" record ask "$report/exact" "$report/events" ask --json
refuse "$recorder" record seal "$report/exact"
init parallel
pids=()
for _ in {1..8}; do ask parallel events < "$report/request" > /dev/null & pids+=("$!"); done
for pid in "${pids[@]}"; do wait "$pid"; done
"$recorder" record seal "$report/parallel"
jq -e '.calls==8 and .capture_complete' "$report/parallel/summary.json" >/dev/null
[[ $(find "$report/parallel" -name '*receipt.json' | wc -l) == 8 ]]
passed=$((passed+1))
init failed
code=0; ask failed fail < "$report/request" > /dev/null || code=$?
[[ $code == 7 ]]
jq -e '.exit_code==7 and .transport_complete' "$report/failed/000-receipt.json" >/dev/null
passed=$((passed+1))
init killed
"$recorder" record ask "$report/killed" "$report/sleeper" ask --json < "$report/request" > /dev/null & running=$!
for _ in {1..100}; do [[ ! -s $report/child.pid ]] || break; sleep .02; done
[[ -s $report/child.pid ]]
refuse "$recorder" record seal "$report/killed"
kill -KILL "$running"; wait "$running" 2>/dev/null || true; running=
child=$(cat "$report/child.pid")
for _ in {1..100}; do
    if [[ ! -e /proc/$child/stat ]] || [[ $(awk '{print $3}' /proc/$child/stat) == Z ]]; then break; fi
    sleep .02
done
[[ ! -e /proc/$child/stat ]] || [[ $(awk '{print $3}' /proc/$child/stat) == Z ]]
refuse "$recorder" record seal "$report/killed"
jq -e '.capture_complete==false and .calls==1' "$report/killed/summary.json" >/dev/null
passed=$((passed+1))
init invalid-bootstrap
refuse "$recorder" record ask "$report/invalid-bootstrap" "$report/echo" ask --json --event-bootstrap < "$report/request"
refuse "$recorder" record seal "$report/invalid-bootstrap"
jq -e '.calls==1 and .capture_complete==false' "$report/invalid-bootstrap/summary.json" >/dev/null
[[ ! -e $report/invalid-bootstrap/000-receipt.json ]]
passed=$((passed+1))
init calls
for _ in {1..64}; do printf '{}' | ask calls echo > /dev/null; done
refuse "$recorder" record ask "$report/calls" "$report/echo" ask --json
refuse "$recorder" record seal "$report/calls"
jq -e '.calls==64 and .limit_exhausted and .capture_complete==false' "$report/calls/summary.json" >/dev/null
passed=$((passed+1))
init bytes
head -c 1048576 /dev/zero > "$report/megabyte"
for _ in {1..4}; do ask bytes echo < "$report/megabyte" > /dev/null; done
refuse "$recorder" record ask "$report/bytes" "$report/echo" ask --json < "$report/request"
refuse "$recorder" record seal "$report/bytes"
jq -e '.bytes==8388608 and .limit_exhausted' "$report/bytes/summary.json" >/dev/null
passed=$((passed+1))
init oversized
{ cat "$report/megabyte"; printf x; } > "$report/oversized-input"
refuse "$recorder" record ask "$report/oversized" "$report/echo" ask --json < "$report/oversized-input"
refuse "$recorder" record seal "$report/oversized"
ln -s "$report" "$report/alias"
refuse "$recorder" record init "$report/alias/no-create"
[[ ! -e $report/no-create ]]
refuse "$recorder" record ask "$report/alias/exact" "$report/echo" ask --json
init hardlink
ln "$report/hardlink/gate" "$report/gate-alias"
refuse "$recorder" record ask "$report/hardlink" "$report/echo" ask --json
init fifo
rm "$report/fifo/gate"; mkfifo "$report/fifo/gate"
refuse "$recorder" record ask "$report/fifo" "$report/echo" ask --json
printf 'Evaluation IPC recorder checks passed: %s\n' "$passed"
