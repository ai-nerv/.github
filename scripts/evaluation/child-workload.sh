#!/usr/bin/env bash
set -euo pipefail
umask 077
source /input/family-common.sh
cd /world/work/work
start_provider 64
configure_family /world/work/work true
printf '\nmagi.allow[#magi.allow + 1] = { verb = "run", program = "/opt/evaluation/bin/magi" }\n' >> "$XDG_CONFIG_HOME/magi/init.lua"
sed "s/@PORT@/$port/g" /input/providers.lua > "$XDG_CONFIG_HOME/melchior/providers.lua"
cp "$XDG_CONFIG_HOME/magi/init.lua" "$EVAL_EVIDENCE/config/0.lua"
cp "$XDG_CONFIG_HOME/melchior/providers.lua" "$EVAL_EVIDENCE/config/4.lua"
(cd "$EVAL_EVIDENCE" && sha256sum config/*.lua > config.sha256)
NERV_LOG="$EVAL_EVIDENCE/family.log" start_magi "$EVAL_EVIDENCE/magi.stdout" "$EVAL_EVIDENCE/magi.stderr" \
    --headless "$(cat /input/prompt.txt)"
host=$magi_pid host_wait=$magi_wait_pid
ready=false
for _ in {1..400}; do
    kill -0 "$host"
    balthasar sessions --tool magi --json > "$EVAL_EVIDENCE/sessions.json" 2> "$EVAL_EVIDENCE/sessions.stderr"
    run=$(jq -r '[.result[]?|select(.id|contains("@")|not)|.id]|if length==1 then .[0] else "" end' "$EVAL_EVIDENCE/sessions.json")
    child_run=$(jq -r '[.result[]?|select(.id|contains("@"))|.id]|if length==1 then .[0] else "" end' "$EVAL_EVIDENCE/sessions.json")
    if [[ $run =~ ^[a-zA-Z0-9_-]+$ && $child_run == "$run@"* ]]; then
        child=${child_run#*@}
        [[ $child =~ ^[a-zA-Z0-9_-]+$ ]]
        balthasar replay --tool magi "$run" --json > "$EVAL_EVIDENCE/replay-parent.json" 2> /tmp/replay-parent.err
        balthasar replay --tool magi "$child_run" --json > "$EVAL_EVIDENCE/replay-child.json" 2> /tmp/replay-child.err
        report="$XDG_RUNTIME_DIR/melchior/work/$child.report"
        if [[ -f $report ]]; then
            cp "$report" "$EVAL_EVIDENCE/report.json"
            revision=$(jq -er .revision "$EVAL_EVIDENCE/report.json")
            if jq -e --arg revision "$revision" '.ok and
                (.result[-1].raw|fromjson|.entry|.type=="assistant" and .stop_reason=="end_turn" and .error==null and (.text|startswith("PARENT_FINAL:"))) and
                any(.result[].raw|fromjson|.entry; .type=="from" and .sort=="attention" and (.text|contains("reported a finished turn"))) and
                any(.result[].raw|fromjson|.entry; .type=="from" and .sort=="report_body" and (.text|contains($revision)) and (.text|contains("CHILD_FINAL:")))' \
                "$EVAL_EVIDENCE/replay-parent.json" >/dev/null &&
              jq -e '.ok and (.result[-1].raw|fromjson|.entry|.type=="assistant" and .stop_reason=="end_turn" and .error==null and (.text|startswith("CHILD_FINAL:")))' \
                "$EVAL_EVIDENCE/replay-child.json" >/dev/null; then ready=true; break; fi
        fi
    fi
    sleep 0.05
done
[[ $ready == true ]]
mapfile -t ledgers < <(find "$XDG_RUNTIME_DIR/melchior/.spent" -maxdepth 1 -type f ! -name '*.lock' ! -name '*.next')
[[ ${#ledgers[@]} == 1 && ${ledgers[0]##*/} == "$run" ]]
cp "${ledgers[0]}" "$EVAL_EVIDENCE/ledger.txt"
parent=${run%-*}
child_pid=$(sed -nE 's/^.* magi\[([0-9]+)\] session: .* as agent '"$child"' serving .*$/\1/p' "$EVAL_EVIDENCE/family.log")
[[ $child_pid =~ ^[1-9][0-9]*$ && $child_pid != "$host" ]]
jq -nc --arg run "$run" --arg parent "$parent" --arg child "$child" --arg child_run "$child_run" --argjson child_pid "$child_pid" \
    '{run:$run,parent:$parent,child:$child,child_transcript:$child_run,child_pid:$child_pid,report_file:($child+".report")}' > "$EVAL_EVIDENCE/identities.json"
signal_magi "$host" TERM
code=0; wait_magi "$host_wait" || code=$?
printf '%s\n' "$code" > "$EVAL_EVIDENCE/magi.exit"
[[ $code == 0 && ! -e ${ledgers[0]} ]]
for _ in {1..100}; do
    if ! kill -0 "$child_pid" 2>/dev/null; then break; fi
    sleep 0.05
done
! kill -0 "$child_pid" 2>/dev/null
stop_provider
for lane in parent child; do
    session=$run
    [[ $lane == parent ]] || session=$child_run
    balthasar replay --tool magi "$session" --json > "/tmp/final-$lane.json"
    [[ $(sha256sum < "$EVAL_EVIDENCE/replay-$lane.json") == $(sha256sum < "/tmp/final-$lane.json") ]]
done
