#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/target"
report=$(mktemp -d "$root/target/mcp-live-XXXXXXXX")
path=""
for member in magi casper melchior balthasar; do
    output=$(cd "$root/$member" && oslo make family-path)
    relative=$(printf '%s\n' "$output" | sed -n 's/^NERV_BINARY=//p')
    binary=$(realpath -e "$root/$member/$relative" 2>/dev/null || true)
    [[ -n $relative && $binary == "$root/$member/target/"* && -x $binary ]] || { echo "Build $member with oslo make build first" >&2; exit 1; }
    path+="${binary%/*}:"
done
path+="/usr/bin:/bin"
fake="$root/melchior/target/debug/examples/fake-provider"
[[ -x "$fake" ]] || { echo "Run cd melchior && oslo make build-fake-provider" >&2; exit 1; }
command -v uv >/dev/null
command -v jq >/dev/null
mkdir -p "$report"/{config/magi,config/casper,config/melchior,config/balthasar,data/casper/mcp,state,runtime,work,tmp}
chmod 700 "$report/runtime"
for member in magi casper balthasar; do cp -r "$root/$member/config/." "$report/config/$member/"; done
cp "$root/melchior/config/apis.lua" "$report/config/melchior/"
uv venv --python /usr/bin/python3 "$report/work/.venv" > "$report/provision.log" 2>&1
uv pip install --python "$report/work/.venv/bin/python" --require-hashes \
    -r "$root/scripts/mcp-for-blender.lock" >> "$report/provision.log" 2>&1
cat > "$report/script.json" <<'JSON'
[
 {"events":[{"tool_call":{"id":"mcp-manual","name":"tools","arguments":"{\"path\":\"mcp\"}"}},{"finish":"tool_calls"}]},
 {"events":[{"tool_call":{"id":"scene-proof","name":"mcp__blender__get_scene_info","arguments":"{\"user_prompt\":\"Inspect the open scene without changing anything.\"}"}},{"finish":"tool_calls"}]},
 {"events":[{"text":"MCP round-trip received."},{"finish":"stop"}]}
]
JSON
"$fake" --script "$report/script.json" --port 0 --record "$report/requests.jsonl" > "$report/fake.log" 2>&1 &
fake_pid=$!
trap 'kill "$fake_pid" 2>/dev/null || true; wait "$fake_pid" 2>/dev/null || true; echo "MCP evidence: $report"' EXIT
for _ in $(seq 1 100); do
    port=$(sed -n 's/^PORT=//p' "$report/fake.log")
    [[ -z "$port" ]] || break
    sleep .05
done
[[ -n "$port" ]]
cat > "$report/config/melchior/providers.lua" <<LUA
melchior.provider("acceptance", {
  name = "Local MCP proof", api = "openai-completions",
  base_url = "http://127.0.0.1:$port/v1", auth = { kind = "none" },
  models = {{ id = "echo-1", name = "Echo 1", context_window = 200000, max_tokens = 4096 }},
})
LUA
cat >> "$report/config/magi/init.lua" <<LUA
magi.model = "acceptance/echo-1"
magi.helpers = { memory = false }
magi.mode = "locked"
magi.allow[#magi.allow + 1] = { verb = "reach", anything = true }
LUA
cat > "$report/data/casper/mcp/blender.json" <<JSON
{
  "command": "$report/work/.venv/bin/mcp-for-blender",
  "tools": ["get_scene_info", "get_object_info", "get_addon_status"],
  "needs": "reach", "network": true, "timeout_secs": 30,
  "env": {"DISABLE_TELEMETRY":"true", "BLENDER_MCP_SAFE_MODE":"1", "BLENDER_HOST":"127.0.0.1", "BLENDER_PORT":"9876"}
}
JSON
(cd "$report/work" && env -i PATH="$path" HOME="$report" XDG_CONFIG_HOME="$report/config" XDG_DATA_HOME="$report/data" XDG_STATE_HOME="$report/state" XDG_RUNTIME_DIR="$report/runtime" TMPDIR="$report/tmp" MAGI_DEBUG_LOG="$report/debug.log" timeout 90 magi -p "Read the open Blender scene using the MCP inspection tool. Do not change anything." > "$report/magi.out" 2>&1)
jq -se 'any(.[]; any(.tools[]?; .function.name == "mcp__blender__get_scene_info"))' "$report/requests.jsonl" >/dev/null
jq -se 'any(.[]; any(.messages[]?; .role == "tool" and (.content | contains("mcp/blender -- 3 tools discovered at session startup")) and (.content | contains("mcp__blender__get_scene_info"))))' "$report/requests.jsonl" >/dev/null
jq -se 'any(.[]; any(.messages[]?; .role == "tool" and (.content | contains("object_count")) and ((.content | fromjson).isError == false)))' "$report/requests.jsonl" >/dev/null
echo "PASS: Casper MCP directory discovery -> tools mcp -> Magi -> Casper -> generic MCP client -> external Blender MCP server -> existing addon -> model tool result"
