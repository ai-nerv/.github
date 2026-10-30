#!/usr/bin/env bash

start_magi() {
    local stdout=$1 stderr=$2
    shift 2
    magi "$@" >> "$stdout" 2>> "$stderr" &
    magi_pid=$! magi_wait_pid=$!
}

signal_magi() { kill -"$2" "$1"; }
wait_magi() { wait "$1"; }
run_magi() { start_magi "$@" && wait_magi "$magi_wait_pid"; }

if [[ -f /input/event-observer.sh ]]; then
    source /input/event-observer.sh
elif [[ -e /runner/event-observer-selection.json ]]; then
    echo 'selected event observer requires the explicit workload helper' >&2
    exit 125
fi

start_provider() {
    local limit=$1 line
    [[ $limit =~ ^[1-9][0-9]?$ && $limit -le 64 ]]
    if [[ -f /input/provider-attempt-limit.txt ]]; then
        IFS= read -r line < /input/provider-attempt-limit.txt
        [[ $line =~ ^[1-9][0-9]?$ && $line -le $limit && $(wc -c < /input/provider-attempt-limit.txt) == $((${#line}+1)) ]]
        limit=$line
    fi
    : > "$EVAL_EVIDENCE/provider.stdout"
    : > "$EVAL_EVIDENCE/provider.stderr"
    /runner/provider/input --script /input/provider.json --port 0 --attempt-limit "$limit" --capture-limit 8388608 \
        --record "$EVAL_EVIDENCE/requests.jsonl" --meter "$EVAL_EVIDENCE/meter.jsonl" \
        > "$EVAL_EVIDENCE/provider.stdout" 2> "$EVAL_EVIDENCE/provider.stderr" &
    provider=$!
    port=
    for _ in {1..100}; do
        IFS= read -r line < "$EVAL_EVIDENCE/provider.stdout" || line=
        if [[ $line == PORT=* ]]; then port=${line#PORT=}; break; fi
        kill -0 "$provider"
        sleep 0.02
    done
    [[ $port =~ ^[0-9]+$ && $port -ge 1 && $port -le 65535 ]]
    jq -se --argjson limit "$limit" \
        '.[0]=={schema:2,scope:"offline-provider-admission",event:"start",limit:$limit,capture_limit_bytes:8388608,journal_limit_bytes:131072}' \
        "$EVAL_EVIDENCE/meter.jsonl" >/dev/null
}

configure_family() {
    local work=$1 writable=$2 index name
    [[ ( $work == /world/work || $work == /world/work/work ) && ( $writable == true || $writable == false ) ]]
    local assets=(magi/init.lua magi/tools.lua casper/tools.lua melchior/apis.lua melchior/providers.lua
                  balthasar/init.lua balthasar/sections.lua balthasar/sources/magi.lua)
    mkdir -p "$XDG_CONFIG_HOME"/{magi,casper,melchior,balthasar/sources} "$EVAL_EVIDENCE/config"
    for index in "${!assets[@]}"; do
        cp "/family/assets/$index/input" "$XDG_CONFIG_HOME/${assets[index]}"
    done
    mkdir -p "$XDG_CACHE_HOME/melchior/models"
    for name in openrouter ollama; do printf '[]\n' > "$XDG_CACHE_HOME/melchior/models/$name.json"; done
    cat > "$XDG_CONFIG_HOME/melchior/providers.lua" <<LUA
melchior.provider("evaluation", {
  name = "Evaluation Fake", api = "openai-completions",
  base_url = "http://127.0.0.1:$port/v1", auth = { kind = "none" },
  models = { { id = "echo-1", name = "Echo 1", context_window = 200000, max_tokens = 4096 } },
})
LUA
    cat >> "$XDG_CONFIG_HOME/magi/init.lua" <<LUA

magi.model = "evaluation/echo-1"
magi.helpers = { memory = false }
magi.allow[#magi.allow + 1] = { verb = "read", directory = "$work" }
LUA
    if [[ $writable == true ]]; then
        printf 'magi.allow[#magi.allow + 1] = { verb = "write", directory = "%s" }\n' "$work" >> "$XDG_CONFIG_HOME/magi/init.lua"
    fi
    if [[ -f /input/client-admission.lua ]]; then
        cat /input/client-providers.lua /input/client-admission.lua >> "$XDG_CONFIG_HOME/melchior/apis.lua"
    fi
    for index in "${!assets[@]}"; do cp "$XDG_CONFIG_HOME/${assets[index]}" "$EVAL_EVIDENCE/config/$index.lua"; done
    (cd "$EVAL_EVIDENCE" && sha256sum config/*.lua > config.sha256)
    if [[ -f /input/ipc-recorder-melchior.sh ]]; then
        /runner/bin/eval-world record init "$XDG_RUNTIME_DIR/model-ipc"
        mkdir "$XDG_RUNTIME_DIR/recorder-bin"
        cp /input/ipc-recorder-melchior.sh "$XDG_RUNTIME_DIR/recorder-bin/melchior"
        chmod 700 "$XDG_RUNTIME_DIR/recorder-bin/melchior"
        export PATH="$XDG_RUNTIME_DIR/recorder-bin:$PATH"
    fi
}

stop_provider() {
    kill -TERM "$provider" || return "$?"
    wait "$provider" || return "$?"
    if [[ -f /input/ipc-recorder-melchior.sh ]]; then
        /runner/bin/eval-world record seal "$XDG_RUNTIME_DIR/model-ipc" || true
        bash /input/pack-model-ipc.sh "$XDG_RUNTIME_DIR" model-ipc "$XDG_RUNTIME_DIR/ipc-package" /runner/bin/eval-input 9437184 || return "$?"
        cp "$XDG_RUNTIME_DIR/ipc-package/raw.tar" "$EVAL_EVIDENCE/model-ipc.tar" || return "$?"
        printf 'Evaluation IPC package: '
        jq -c . "$XDG_RUNTIME_DIR/ipc-package/summary.json"
    fi
}

replay_family() {
    local session
    balthasar sessions --tool magi --json > "$EVAL_EVIDENCE/sessions.json" 2> "$EVAL_EVIDENCE/sessions.stderr"
    session=$(jq -er '.result[0].id' "$EVAL_EVIDENCE/sessions.json")
    balthasar replay --tool magi "$session" --json > "$EVAL_EVIDENCE/replay.json" 2> "$EVAL_EVIDENCE/replay.stderr"
}
