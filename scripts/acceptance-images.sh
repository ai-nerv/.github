#!/usr/bin/env bash
set -euo pipefail
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/target"
report=$(mktemp -d "$root/target/images-live-XXXXXXXX")
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
command -v jq >/dev/null
command -v perl >/dev/null
if [[ ${1:-} == --blender ]]; then
    if ! timeout 3 "$BASH" -c 'exec 3<>/dev/tcp/127.0.0.1/9876' 2>/dev/null; then
        echo "Blender MCP addon is not listening on 127.0.0.1:9876; start its server in Blender first." >&2
        exit 1
    fi
fi
mkdir -p "$report"/{config/magi,config/casper,config/melchior,config/balthasar,data/casper/mcp,state,runtime,work,tmp}
chmod 700 "$report/runtime"
for member in magi casper balthasar; do cp -r "$root/$member/config/." "$report/config/$member/"; done
cp "$root/melchior/config/apis.lua" "$report/config/melchior/"
perl -MCompress::Zlib -e '
    sub chunk { my ($kind,$data)=@_; return pack("N",length($data)).$kind.$data.pack("N",Compress::Zlib::crc32($kind.$data)); }
    print "\x89PNG\r\n\x1a\n", chunk("IHDR",pack("NNCCCCC",2,1,8,6,0,0,0)),
        chunk("IDAT",Compress::Zlib::compress("\x00\xff\x00\x00\xff\x00\xff\x00\xff")), chunk("IEND","");
' > "$report/work/photo.png"
cat > "$report/script.json" <<'JSON'
[
 {"events":[{"tool_call":{"id":"read-image","name":"read","arguments":"{\"path\":\"photo.png\"}"}},{"finish":"tool_calls"}]},
 {"events":[{"tool_call":{"id":"mcp-image","name":"mcp__raster__read","arguments":"{\"path\":\"photo.png\"}"}},{"finish":"tool_calls"}]},
 {"events":[{"text":"Image attachments received."},{"finish":"stop"}]},
 {"events":[{"text":"Stored image attachments received after resume."},{"finish":"stop"}]}
]
JSON
if [[ ${1:-} == --blender ]]; then
    command -v uv >/dev/null
    uv venv --python /usr/bin/python3 "$report/work/.venv" > "$report/provision.log" 2>&1
    uv pip install --python "$report/work/.venv/bin/python" --require-hashes \
        -r "$root/scripts/mcp-for-blender.lock" >> "$report/provision.log" 2>&1
    jq '.[0:2] + [{"events":[{"tool_call":{"id":"blender-image","name":"mcp__blender__get_viewport_screenshot","arguments":"{\"max_size\":800}"}},{"finish":"tool_calls"}]}] + .[2:]' "$report/script.json" > "$report/blender-script.json"
    mv "$report/blender-script.json" "$report/script.json"
    # Blender writes the screenshot where the server asks: a directory both sides see at one path.
    mkdir -p "$report/work/blender-tmp"
    cat > "$report/data/casper/mcp/blender.json" <<JSON
{"command":"$report/work/.venv/bin/mcp-for-blender","tools":["get_viewport_screenshot"],"needs":"reach","network":true,"timeout_secs":120,"env":{"DISABLE_TELEMETRY":"true","BLENDER_MCP_SAFE_MODE":"1","BLENDER_HOST":"127.0.0.1","BLENDER_PORT":"9876","TMPDIR":"$report/work/blender-tmp"}}
JSON
fi
"$fake" --script "$report/script.json" --port 0 --record "$report/requests.jsonl" > "$report/fake.log" 2>&1 &
fake_pid=$!
trap 'kill "$fake_pid" 2>/dev/null || true; wait "$fake_pid" 2>/dev/null || true; echo "Image evidence: $report"' EXIT
for _ in $(seq 1 100); do
    port=$(sed -n 's/^PORT=//p' "$report/fake.log")
    [[ -z "$port" ]] || break
    sleep .05
done
[[ -n "$port" ]]
cat > "$report/config/melchior/providers.lua" <<LUA
melchior.provider("acceptance", {
  name = "Local image proof", api = "openai-completions",
  base_url = "http://127.0.0.1:$port/v1", auth = { kind = "none" },
  models = {{ id = "vision", name = "Vision fixture", input = {"text", "image"}, context_window = 200000, max_tokens = 4096 }},
})
LUA
cat >> "$report/config/magi/init.lua" <<LUA
magi.model = "acceptance/vision"
magi.helpers = { memory = false }
magi.mode = "locked"
magi.allow[#magi.allow + 1] = { verb = "read", directory = "$report/work" }
magi.allow[#magi.allow + 1] = { verb = "run", program = "mcp__raster__read" }
LUA
if [[ ${1:-} == --blender ]]; then
    printf '\nmagi.allow[#magi.allow + 1] = { verb = "reach", anything = true }\n' >> "$report/config/magi/init.lua"
fi
casper_bin=$(PATH="$path" command -v casper)
cp "$casper_bin" "$report/work/casper-mcp"
mkdir -p "$report/work/mcp-config/casper"
cp "$root/casper/config/tools.lua" "$report/work/mcp-config/casper/tools.lua"
cat > "$report/data/casper/mcp/raster.json" <<JSON
{"command":"$report/work/casper-mcp","args":["mcp","--tools=read"],"env":{"CASPER_CONFIGURE":"{}","CASPER_JAIL":"","XDG_CONFIG_HOME":"$report/work/mcp-config"},"needs":"read"}
JSON
run() {
    (cd "$report/work" && env -i HOME="$report" PATH="$path" XDG_CONFIG_HOME="$report/config" XDG_DATA_HOME="$report/data" XDG_STATE_HOME="$report/state" XDG_CACHE_HOME="$report/cache" XDG_RUNTIME_DIR="$report/runtime" TMPDIR="$report/tmp" TERM=xterm-256color NERV_LOG="$report/family.log" timeout 180 magi "$@")
}
run -p 'Inspect @photo.png, then read it through native read and MCP.' > "$report/magi.out" 2>&1
run --resume -p 'Inspect the stored images again without re-reading files.' > "$report/resume.out" 2>&1
jq -se '.[0].messages | any(.[]; .role == "user" and (.content|type) == "array" and any(.content[]; .type == "image_url"))' "$report/requests.jsonl" >/dev/null
jq -se 'any(.[]; any(.messages[]?; .role == "tool" and .tool_call_id == "read-image" and (.content|contains("Read image"))))' "$report/requests.jsonl" >/dev/null
jq -se 'any(.[]; any(.messages[]?; .role == "tool" and .tool_call_id == "mcp-image" and (.content|contains("Image attachment"))))' "$report/requests.jsonl" >/dev/null
jq -se '[.[-1].messages[] | select((.content|type) == "array") | .content[] | select(.type == "image_url")] | length >= 3' "$report/requests.jsonl" >/dev/null
jq -se 'any(.[]; any(.messages[]?; .role == "tool" and (.content|contains("base64")))) | not' "$report/requests.jsonl" >/dev/null
jq -sr '.[0].messages[] | select((.content|type)=="array") | .content[] | select(.type=="image_url") | .image_url.url | split(",")[1]' "$report/requests.jsonl" | head -1 | base64 -d > "$report/delivered.png"
env -i HOME="$report" PATH="$path" casper image "$report/delivered.png" | jq -e '.ok and .result[0].media_type == "image/png"' >/dev/null
if [[ ${1:-} == --blender ]]; then
    jq -se '.[-1].messages | any(.[]; .role == "user" and (.content|type)=="array" and any(.content[]; .type=="text" and (.text|contains("get_viewport_screenshot"))))' "$report/requests.jsonl" >/dev/null
    jq -se '[.[-1].messages[] | select((.content|type)=="array") | .content[] | select(.type=="image_url")] | length >= 4' "$report/requests.jsonl" >/dev/null
    jq -sr '.[-1].messages[] | select((.content|type)=="array") | .content as $parts | select(any($parts[]; .type=="text" and (.text|contains("get_viewport_screenshot")))) | $parts[] | select(.type=="image_url") | .image_url.url | split(",")[1]' "$report/requests.jsonl" | base64 -d > "$report/blender-screenshot"
    env -i HOME="$report" PATH="$path" casper image "$report/blender-screenshot" | jq -e '.ok and (.result[0].media_type|startswith("image/"))' >/dev/null
    echo "PASS: real Blender viewport screenshot delivered and preserved after resume."
fi
echo "PASS: @image -> Magi -> provider image parts; native read -> image; generic MCP -> image; Balthasar -> resume -> images. No paid inference."
