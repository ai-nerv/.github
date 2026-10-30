#!/usr/bin/env bash
set -euo pipefail
umask 077
source /input/family-common.sh
cd /world/work/work
start_provider 64
configure_family /world/work/work false
sed "s/@PORT@/$port/g" /input/providers.lua > "$XDG_CONFIG_HOME/melchior/providers.lua"
cp "$XDG_CONFIG_HOME/melchior/providers.lua" "$EVAL_EVIDENCE/config/4.lua"
index=0 previous=
ids=()
for dialect in chat anthropic; do
    printf '\nmagi.model = "evaluation-%s/%s-1"\n' "$dialect" "$dialect" >> "$XDG_CONFIG_HOME/magi/init.lua"
    config=0.lua
    [[ $dialect == chat ]] || config=anthropic-init.lua
    cp "$XDG_CONFIG_HOME/magi/init.lua" "$EVAL_EVIDENCE/config/$config"
    NERV_LOG="$EVAL_EVIDENCE/family-$dialect.log" start_magi "$EVAL_EVIDENCE/$dialect.stdout" "$EVAL_EVIDENCE/$dialect.stderr" \
        --headless "$(cat /input/prompt.txt)"
    host=$magi_pid host_wait=$magi_wait_pid
    ready=false session=
    for _ in {1..200}; do
        kill -0 "$host"
        balthasar sessions --tool magi --json > "$EVAL_EVIDENCE/sessions.json" 2> "$EVAL_EVIDENCE/sessions.stderr"
        session=$(jq -r --arg previous "$previous" '[.result[]?|select(.id!=$previous)|.id]|if length==1 then .[0] else "" end' "$EVAL_EVIDENCE/sessions.json")
        if [[ $session =~ ^[a-zA-Z0-9_-]+$ ]]; then
            balthasar replay --tool magi "$session" --json > "$EVAL_EVIDENCE/replay-$index.json" 2> "$EVAL_EVIDENCE/replay-$index.stderr"
            if jq -e '.ok and .n==6 and (.result[-1].raw|fromjson|.entry|.type=="assistant" and .stop_reason=="end_turn" and .error==null)' \
                "$EVAL_EVIDENCE/replay-$index.json" >/dev/null; then ready=true; break; fi
        fi
        sleep 0.05
    done
    [[ $ready == true ]]
    mapfile -t ledgers < <(find "$XDG_RUNTIME_DIR/melchior/.spent" -maxdepth 1 -type f ! -name '*.lock' ! -name '*.next')
    [[ ${#ledgers[@]} == 1 && ${ledgers[0]} == "$XDG_RUNTIME_DIR/melchior/.spent/$session" ]]
    cp "${ledgers[0]}" "$EVAL_EVIDENCE/ledger-$index.txt"
    signal_magi "$host" TERM
    code=0; wait_magi "$host_wait" || code=$?
    printf '%s\n' "$code" > "$EVAL_EVIDENCE/$dialect.exit"
    [[ $code == 0 ]]
    [[ ! -e $XDG_RUNTIME_DIR/melchior/.spent/$session ]]
    balthasar replay --tool magi "$session" --json > /tmp/replay-after.json
    [[ $(sha256sum < "$EVAL_EVIDENCE/replay-$index.json") == $(sha256sum < /tmp/replay-after.json) ]]
    ids+=("$session")
    previous=$session
    index=$((index+1))
done
(cd "$EVAL_EVIDENCE" && sha256sum config/*.lua > config.sha256)
stop_provider
balthasar sessions --tool magi --json > "$EVAL_EVIDENCE/sessions.json" 2> "$EVAL_EVIDENCE/sessions.stderr"
jq -e '.ok and .n==2 and (.result|length)==2' "$EVAL_EVIDENCE/sessions.json" >/dev/null
jq -n --arg chat "${ids[0]}" --arg anthropic "${ids[1]}" '{chat:$chat,anthropic:$anthropic}' > "$EVAL_EVIDENCE/ledger-runs.json"
