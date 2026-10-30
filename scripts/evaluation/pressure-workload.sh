#!/usr/bin/env bash
set -euo pipefail
umask 077
source /input/family-common.sh
cd /world/work/work
start_provider 64
configure_family /world/work/work false
printf '\nmagi.helpers = { memory = false, summary = "evaluation/echo-1" }\n' >> "$XDG_CONFIG_HOME/magi/init.lua"
cp "$XDG_CONFIG_HOME/magi/init.lua" "$EVAL_EVIDENCE/config/0.lua"
sed "s/@PORT@/$port/g" /input/providers.lua > "$XDG_CONFIG_HOME/melchior/providers.lua"
cp "$XDG_CONFIG_HOME/melchior/providers.lua" "$EVAL_EVIDENCE/config/4.lua"
(cd "$EVAL_EVIDENCE" && sha256sum config/*.lua > config.sha256)
code=0
NERV_LOG="$EVAL_EVIDENCE/family.log" run_magi "$EVAL_EVIDENCE/magi.stdout" "$EVAL_EVIDENCE/magi.stderr" \
    -p "$(cat /input/prompt.txt)" || code=$?
printf '%s\n' "$code" > "$EVAL_EVIDENCE/magi.exit"
provider_code=0
stop_provider || provider_code=$?
printf '%s\n' "$provider_code" > "$EVAL_EVIDENCE/provider.exit"
replay_family
[[ $code == 0 && $provider_code == 0 ]]
