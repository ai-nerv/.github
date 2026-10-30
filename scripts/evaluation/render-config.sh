#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 5 ]] || { echo 'usage: render-config.sh TASK FROZEN_ASSETS FROZEN_FIXTURE NEW_OUTPUT PORT' >&2; exit 2; }
task=$1 assets=$2 fixture=$3 output=$4 port=$5
[[ $port == @PORT@ || ( $port =~ ^[1-9][0-9]{0,4}$ && $port -le 65535 ) ]] || exit 2
case $task in
    small-bug-fix|read-index-select-edit|large-file-edit|concurrent-disjoint-edits|resume|child-work) writable=true ;;
    repetitive-failure|output-only-overflow|input-pressure|cache-accounting) writable=false ;;
    *) exit 2 ;;
esac
mkdir -- "$output"
for index in {0..7}; do cp -- "$assets/$index/input" "$output/$index.lua"; done
if [[ $task == cache-accounting ]]; then
    printf '\nmelchior.evaluation_providers = { ["evaluation-anthropic"] = true, ["evaluation-chat"] = true }\n' >> "$output/3.lua"
else
    printf '\nmelchior.evaluation_providers = { ["evaluation"] = true }\n' >> "$output/3.lua"
fi
cat "$fixture/client-admission.lua" >> "$output/3.lua"
cat > "$output/4.lua" <<LUA
melchior.provider("evaluation", {
  name = "Evaluation Fake", api = "openai-completions",
  base_url = "http://127.0.0.1:$port/v1", auth = { kind = "none" },
  models = { { id = "echo-1", name = "Echo 1", context_window = 200000, max_tokens = 4096 } },
})
LUA
cat >> "$output/0.lua" <<'LUA'

magi.model = "evaluation/echo-1"
magi.helpers = { memory = false }
magi.allow[#magi.allow + 1] = { verb = "read", directory = "/world/work/work" }
LUA
if [[ $writable == true ]]; then
    printf 'magi.allow[#magi.allow + 1] = { verb = "write", directory = "/world/work/work" }\n' >> "$output/0.lua"
fi
case $task in
    cache-accounting|resume|input-pressure|child-work)
        sed "s/@PORT@/$port/g" "$fixture/providers.lua" > "$output/4.lua" ;;
esac
case $task in
    cache-accounting)
        printf '\nmagi.model = "evaluation-chat/chat-1"\n' >> "$output/0.lua"
        cp "$output/0.lua" "$output/anthropic-init.lua"
        printf '\nmagi.model = "evaluation-anthropic/anthropic-1"\n' >> "$output/anthropic-init.lua" ;;
    input-pressure)
        printf '\nmagi.helpers = { memory = false, summary = "evaluation/echo-1" }\n' >> "$output/0.lua" ;;
    child-work)
        printf '\nmagi.allow[#magi.allow + 1] = { verb = "run", program = "/opt/evaluation/bin/magi" }\n' >> "$output/0.lua" ;;
esac
