#!/usr/bin/env bash
set -euo pipefail
umask 077
source /input/family-common.sh
cd /world/work/work
start_provider 64
configure_family /world/work/work true
sed "s/@PORT@/$port/g" /input/providers.lua > "$XDG_CONFIG_HOME/melchior/providers.lua"
cp "$XDG_CONFIG_HOME/melchior/providers.lua" "$EVAL_EVIDENCE/config/4.lua"
(cd "$EVAL_EVIDENCE" && sha256sum config/*.lua > config.sha256)
alpha= beta=
for phase in initial distractor latest named; do
    args=()
    case $phase in
        initial) prompt=prompt.txt marker=FACT_ALPHA entries=6 ;;
        distractor) prompt=distractor.txt marker=FACT_BETA entries=2 ;;
        latest) prompt=latest.txt marker=FACT_BETA entries=4; args=(--resume) ;;
        named) prompt=named.txt marker=FACT_ALPHA entries=8; args=(--resume-run "$alpha") ;;
    esac
    NERV_LOG="$EVAL_EVIDENCE/family.log" start_magi "$EVAL_EVIDENCE/hosts.stdout" "$EVAL_EVIDENCE/hosts.stderr" \
        --headless "${args[@]}" "$(cat "/input/$prompt")"
    host=$magi_pid host_wait=$magi_wait_pid
    ready=false session=
    for _ in {1..200}; do
        kill -0 "$host"
        balthasar sessions --tool magi --json > "$EVAL_EVIDENCE/sessions.json" 2> "$EVAL_EVIDENCE/sessions.stderr"
        session=$(jq -r --arg marker "$marker" '[.result[]?|select((.title//"")|startswith($marker))|.id]|if length==1 then .[0] else "" end' "$EVAL_EVIDENCE/sessions.json")
        if [[ $session =~ ^[a-zA-Z0-9_-]+$ ]]; then
            balthasar replay --tool magi "$session" --json > "$EVAL_EVIDENCE/replay-$phase.json" 2> /tmp/replay.stderr
            if jq -e --argjson n "$entries" '.ok and .n==$n and (.result[-1].raw|fromjson|.entry|.type=="assistant" and .stop_reason=="end_turn" and .error==null)' \
                "$EVAL_EVIDENCE/replay-$phase.json" >/dev/null; then ready=true; break; fi
        fi
        sleep 0.05
    done
    [[ $ready == true ]]
    case $phase in initial) alpha=$session;; distractor) beta=$session;; latest) [[ $session == "$beta" ]];; named) [[ $session == "$alpha" ]];; esac
    mapfile -t ledgers < <(find "$XDG_RUNTIME_DIR/melchior/.spent" -maxdepth 1 -type f ! -name '*.lock' ! -name '*.next')
    [[ ${#ledgers[@]} == 1 ]]
    run=${ledgers[0]##*/}
    [[ $run =~ ^[a-zA-Z0-9_-]+$ ]]
    cp "${ledgers[0]}" "$EVAL_EVIDENCE/ledger-$phase.txt"
    signal_magi "$host" TERM
    code=0; wait_magi "$host_wait" || code=$?
    [[ $code == 0 && ! -e ${ledgers[0]} ]]
    balthasar replay --tool magi "$session" --json > /tmp/replay-after.json
    [[ $(sha256sum < "$EVAL_EVIDENCE/replay-$phase.json") == $(sha256sum < /tmp/replay-after.json) ]]
    jq -nc --arg phase "$phase" --arg transcript "$session" --arg run "$run" --argjson code "$code" \
        '{phase:$phase,transcript:$transcript,coordination_run:$run,exit_code:$code}' >> "$EVAL_EVIDENCE/phases.jsonl"
done
before=$(wc -l < "$EVAL_EVIDENCE/requests.jsonl")
code=0
NERV_LOG="$EVAL_EVIDENCE/family.log" run_magi "$EVAL_EVIDENCE/missing.stdout" "$EVAL_EVIDENCE/missing.stderr" \
    --resume-run missing-evaluation-run -p 'This missing history must never reach the provider.' || code=$?
[[ $code == 1 && $before == 6 && $(wc -l < "$EVAL_EVIDENCE/requests.jsonl") == "$before" ]]
printf '%s\n' "$code" > "$EVAL_EVIDENCE/missing.exit"
stop_provider
balthasar sessions --tool magi --json > "$EVAL_EVIDENCE/sessions.json" 2> "$EVAL_EVIDENCE/sessions.stderr"
jq -e '.ok and .n==2 and (.result|length)==2' "$EVAL_EVIDENCE/sessions.json" >/dev/null
balthasar replay --tool magi "$alpha" --json > /tmp/alpha-final.json
balthasar replay --tool magi "$beta" --json > /tmp/beta-final.json
[[ $(sha256sum < "$EVAL_EVIDENCE/replay-named.json") == $(sha256sum < /tmp/alpha-final.json) ]]
[[ $(sha256sum < "$EVAL_EVIDENCE/replay-latest.json") == $(sha256sum < /tmp/beta-final.json) ]]
