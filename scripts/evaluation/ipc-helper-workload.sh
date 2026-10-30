#!/usr/bin/env bash
set -euo pipefail
umask 077
source /input/family-common.sh
cd /world/work/work
start_provider 64
configure_family /world/work/work false
/runner/bin/eval-world record init "$XDG_RUNTIME_DIR/model-ipc"
mkdir "$XDG_RUNTIME_DIR/recorder-bin"
cp /input/recorder-melchior.sh "$XDG_RUNTIME_DIR/recorder-bin/melchior"
chmod 700 "$XDG_RUNTIME_DIR/recorder-bin/melchior"
export PATH="$XDG_RUNTIME_DIR/recorder-bin:$PATH"
if [[ $1 == pressure ]]; then
    printf '\nmagi.helpers = { memory = false, summary = "evaluation/echo-1" }\n' >> "$XDG_CONFIG_HOME/magi/init.lua"
    sed "s/@PORT@/$port/g" /input/providers.lua > "$XDG_CONFIG_HOME/melchior/providers.lua"
else
    [[ $1 == tool ]]
    printf '\nmagi.helpers = { memory = false, search = "evaluation/echo-1" }\n' >> "$XDG_CONFIG_HOME/magi/init.lua"
    cat >> "$XDG_CONFIG_HOME/casper/tools.lua" <<'LUA'
casper.tool("ipc_helper", {
  description = "Ask the offline fixture helper",
  parameters = {
    type = "object", properties = { path = { type = "string" } }, required = { "path" },
  },
  needs = "read",
  run = function(args)
    assert(args.path == "/world/work/work", "unexpected fixture read path")
    if args.answered then return { said = args.answered } end
    return casper.wonder("helper", {
      role = "search", instruction = "IPC_TOOL_HELPER_ONLY", input = "fixture", max_tokens = 64,
    }, "offline recorder fixture")
  end,
})
LUA
fi
cp "$XDG_CONFIG_HOME/magi/init.lua" "$EVAL_EVIDENCE/config/0.lua"
cp "$XDG_CONFIG_HOME/casper/tools.lua" "$EVAL_EVIDENCE/config/2.lua"
cp "$XDG_CONFIG_HOME/melchior/providers.lua" "$EVAL_EVIDENCE/config/4.lua"
(cd "$EVAL_EVIDENCE" && sha256sum config/*.lua > config.sha256)
code=0
NERV_LOG="$EVAL_EVIDENCE/family.log" magi -p "$(cat /input/prompt.txt)" \
    > "$EVAL_EVIDENCE/magi.stdout" 2> "$EVAL_EVIDENCE/magi.stderr" || code=$?
printf '%s\n' "$code" > "$EVAL_EVIDENCE/magi.exit"
sealed=0
/runner/bin/eval-world record seal "$XDG_RUNTIME_DIR/model-ipc" || sealed=$?
bash /input/pack-model-ipc.sh "$XDG_RUNTIME_DIR" model-ipc "$XDG_RUNTIME_DIR/ipc-package" /runner/bin/eval-input 9437184
cp "$XDG_RUNTIME_DIR/ipc-package/raw.tar" "$EVAL_EVIDENCE/model-ipc.tar"
cp "$XDG_RUNTIME_DIR/ipc-package/summary.json" "$EVAL_EVIDENCE/model-ipc-package.json"
provider_code=0
stop_provider || provider_code=$?
printf '%s\n' "$provider_code" > "$EVAL_EVIDENCE/provider.exit"
replay_family
[[ $code == 0 && $provider_code == 0 && $sealed == 0 ]]
