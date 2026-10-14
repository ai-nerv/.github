#!/usr/bin/env bash
set -euo pipefail
[[ -z ${CI:-} ]] || { echo 'Live vision acceptance never runs in CI.' >&2; exit 2; }
[[ ${NERV_LIVE_SEND:-} == yes ]] || { echo 'Set NERV_LIVE_SEND=yes to send synthetic images to OpenRouter.' >&2; exit 2; }
[[ -n ${OPENROUTER_API_KEY:-} ]] || { echo 'OPENROUTER_API_KEY is not set.' >&2; exit 2; }
model=${NERV_LIVE_MODEL:?Name a vision model in NERV_LIVE_MODEL.}
cap=${NERV_LIVE_CAP_USD:?Set a finite NERV_LIVE_CAP_USD.}
[[ $cap =~ ^[0-9]+(\.[0-9]+)?$ ]] || exit 2
root=$(cd "$(dirname "$0")/.." && pwd)
mkdir -p "$root/target"
resuming=false
if [[ -n ${NERV_VISION_RESUME_REPORT:-} ]]; then
    report=$(realpath "$NERV_VISION_RESUME_REPORT")
    [[ $report == "$root/target/vision-live-"* && -f $report/expected.json ]] || exit 2
    [[ $(jq -r '.id' "$report/model.json") == "$model" ]] || exit 2
    resuming=true
else
    report=$(mktemp -d "$root/target/vision-live-XXXXXXXX")
fi
echo "Vision evidence: $report"
path=""
for member in magi casper melchior balthasar; do
    output=$(cd "$root/$member" && oslo make family-path)
    relative=$(printf '%s\n' "$output" | sed -n 's/^NERV_BINARY=//p')
    binary=$(realpath -e "$root/$member/$relative" 2>/dev/null || true)
    [[ -n $relative && $binary == "$root/$member/target/"* && -x $binary ]] || { echo "Build $member with oslo make build first" >&2; exit 1; }
    [[ -n $binary ]] || { echo "Build $member first." >&2; exit 2; }
    path+="${binary%/*}:"
done
path+="/usr/bin:/bin"
curl -fsS --max-time 20 https://openrouter.ai/api/v1/models > "$report/catalog.json"
jq -e --arg id "$model" '.data[] | select(.id==$id) | select(.architecture.input_modalities|index("image")) | select(.supported_parameters|index("tools"))' "$report/catalog.json" > "$report/model.json"
input=$(jq -r '.pricing.prompt|tonumber*1e12|ceil' "$report/model.json")
output=$(jq -r '.pricing.completion|tonumber*1e12|ceil' "$report/model.json")
window=$(jq -r '.context_length' "$report/model.json")
cap_micros=$(jq -n --arg cap "$cap" '$cap|tonumber*1000000|floor')
ledger_dir="${XDG_STATE_HOME:-$HOME/.local/state}/nerv/vision-live"
mkdir -p "$ledger_dir"
ledger="$ledger_dir/ledger.jsonl"
touch "$ledger"
mkdir -p "$report"/{config/magi,config/casper,config/melchior,config/balthasar,data/casper/mcp,state,runtime,work,tmp}
chmod 700 "$report/runtime"
if ! $resuming; then
for member in magi casper balthasar; do cp -r "$root/$member/config/." "$report/config/$member/"; done
cp "$root/melchior/config/apis.lua" "$report/config/melchior/"
perl -MCompress::Zlib -MJSON::PP -e '
    my $dir=shift; my @colors=(["red",225,35,35],["blue",35,65,225],["green",30,180,65],["yellow",240,210,20]);
    my @shapes=("circle","square","triangle"); my @frames;
    sub chunk { my ($kind,$data)=@_; return pack("N",length($data)).$kind.$data.pack("N",Compress::Zlib::crc32($kind.$data)); }
    for my $frame (0..2) {
        my @cs=(($frame+int(rand(2)))%4,($frame+2+int(rand(2)))%4);
        my @ss=(($frame+int(rand(2)))%3,($frame+2)%3);
        my $dot=int(rand(2)); my $pixels="";
        for my $y (0..191) { $pixels.="\x00"; for my $x (0..383) {
            my @rgb=(255,255,255);
            for my $side (0..1) {
                my $dx=$x-(96+192*$side); my $dy=$y-96; my $shape=$shapes[$ss[$side]];
                my $inside=$shape eq "circle" ? $dx*$dx+$dy*$dy<=2500 : $shape eq "square" ? abs($dx)<=50 && abs($dy)<=50 : $dy>=-50 && $dy<=50 && abs($dx)<=($dy+50)/2;
                @rgb=@{$colors[$cs[$side]]}[1..3] if $inside;
                @rgb=(0,0,0) if $frame==0 && $side==$dot && $dx*$dx+$dy*$dy<=100;
            }
            $pixels.=pack("CCC",@rgb);
        }}
        my $name="frame-".chr(97+$frame).".png";
        open my $fh,">:raw","$dir/$name" or die $!;
        print $fh "\x89PNG\r\n\x1a\n",chunk("IHDR",pack("NNCCCCC",384,192,8,2,0,0,0)),chunk("IDAT",Compress::Zlib::compress($pixels)),chunk("IEND",""); close $fh;
        push @frames,{path=>$name,objects=>[map {{position=>($_==0?"left":"right"),color=>$colors[$cs[$_]][0],shape=>$shapes[$ss[$_]]}} 0..1],dot_side=>($dot==0?"left":"right")};
    }
    print JSON::PP->new->canonical->encode(\@frames);
' "$report/work" > "$report/expected.json"
fi
proxy="$root/melchior/target/debug/examples/metered-proxy"
"$proxy" --upstream https://openrouter.ai/api/v1 --model "$model" --key-env OPENROUTER_API_KEY --ledger "$ledger" --record "$report/requests.jsonl" --cap-micros "$cap_micros" --input-price "$input" --output-price "$output" --output-bound 512 > "$report/proxy.log" 2>&1 &
proxy_pid=$!
finish() {
    local status=$?
    kill "$proxy_pid" 2>/dev/null || true
    wait "$proxy_pid" 2>/dev/null || true
    if [[ -f "$report/requests.jsonl" ]]; then
        jq -s --argjson status "$status" '{exit_status:$status,model:.[0].outcome.model,requests:length,cost_usd:([.[].outcome.usage.cost // 0]|add),errors:[.[].outcome.error|select(.!=null)]}' "$report/requests.jsonl" > "$report/result.json"
        cat "$report/result.json"
    fi
}
trap finish EXIT
for _ in $(seq 1 100); do
    port=$(sed -n 's/^PORT=//p' "$report/proxy.log")
    [[ -z $port ]] || break
    sleep .05
done
[[ -n $port ]]
cat > "$report/config/melchior/providers.lua" <<LUA
melchior.provider("openrouter", {
  name = "OpenRouter visual acceptance", api = "openai-completions", base_url = "http://127.0.0.1:$port",
  auth = { kind = "none" },
  models = {{ id = "$model", name = "$model", input = {"text", "image"}, context_window = $window, max_tokens = 512 }},
})
LUA
if ! $resuming; then
cat >> "$report/config/magi/init.lua" <<LUA
magi.model = "openrouter/$model"
magi.helpers = { memory = false }
magi.mode = "locked"
magi.allow = {{ verb = "read", directory = "$report/work" }}
magi.system = [[You are a visual test participant. Examine actual image pixels, not filenames. An attached image is already visible: do not call tools to inspect attachments. Only call a tool when the user explicitly requests that tool, once per requested image. Do not delegate, use shell tools, or read any other files. For colored-shape questions return only a JSON array of two objects ordered left then right, each containing exactly position, color, shape. The position value is the STRING "left" or "right", never coordinates. Colors are red, blue, green, yellow. Shapes are circle, square, triangle. Ignore black or white marks when reporting colored shapes.]]
LUA
casper_bin=$(PATH="$path" command -v casper)
cp "$casper_bin" "$report/work/casper-mcp"
mkdir -p "$report/work/mcp-config/casper"
cp "$root/casper/config/tools.lua" "$report/work/mcp-config/casper/tools.lua"
cat > "$report/raster.json" <<JSON
{"command":"$report/work/casper-mcp","args":["mcp","--tools=read"],"env":{"CASPER_CONFIGURE":"{}","XDG_CONFIG_HOME":"$report/work/mcp-config"},"needs":"read"}
JSON
fi
run() {
    (cd "$report/work" && env -i HOME="$report" PATH="$path" XDG_CONFIG_HOME="$report/config" XDG_DATA_HOME="$report/data" XDG_STATE_HOME="$report/state" XDG_CACHE_HOME="$report/cache" XDG_RUNTIME_DIR="$report/runtime" TMPDIR="$report/tmp" TERM=xterm-256color timeout 150 magi "$@")
}
check_shapes() {
    local index=$1 name=$2
    jq -Rs 'capture("(?<answer>\\[[\\s\\S]*\\])").answer|fromjson' "$report/$name.out" > "$report/$name.answer.json"
    jq -e -n --slurpfile want "$report/expected.json" --slurpfile got "$report/$name.answer.json" --argjson index "$index" '$want[0][$index].objects==$got[0]' >/dev/null
    echo "PASS: $name visual interpretation"
}
if ! $resuming; then
mv "$report/config/casper/tools.lua" "$report/native-tools.lua"
: > "$report/config/casper/tools.lua"
run -p 'Inspect the attached @frame-a.png without tools. Return only [{"position":"left","color":"...","shape":"..."},{"position":"right","color":"...","shape":"..."}] with the actual colors and shapes.' > "$report/attachment.out" 2>&1
check_shapes 0 attachment
jq -se '.[0].request | (.tools|map(.function.name)|all(.!="read" and .!="mcp__raster__read")) and any(.messages[]; .role=="user" and (.content|type)=="array" and any(.content[]; .type=="image_url"))' "$report/requests.jsonl" >/dev/null
cp "$report/native-tools.lua" "$report/config/casper/tools.lua"
run --resume -p 'Call the native read tool on frame-b.png. Report only its two colored shapes, not the earlier image.' > "$report/native-read.out" 2>&1
check_shapes 1 native-read
mv "$report/raster.json" "$report/data/casper/mcp/raster.json"
run --resume -p 'Call mcp__raster__read on frame-c.png. Report only its two colored shapes, not earlier images.' > "$report/mcp-read.out" 2>&1
check_shapes 2 mcp-read
jq -se 'any(.[]; any(.request.messages[]?; .role=="tool" and (.content|contains("Read image frame-b.png"))))' "$report/requests.jsonl" >/dev/null
jq -se 'any(.[]; any(.request.messages[]?; .role=="user" and (.content|type)=="array" and any(.content[]; .type=="text" and (.text|contains("mcp__raster__read")))))' "$report/requests.jsonl" >/dev/null
mkdir "$report/assets"
cp "$report/work/"frame-{a,b,c}.png "$report/assets/"
rm "$report/work/"frame-{a,b,c}.png
else
    check_shapes 0 attachment
    check_shapes 1 native-read
    check_shapes 2 mcp-read
    [[ ! -e "$report/work/frame-a.png" && ! -e "$report/work/frame-b.png" && ! -e "$report/work/frame-c.png" ]]
    cp "$report/resume.out" "$report/resume.previous.out"
fi
run --resume -p 'Without calling any tools, re-examine the image originally ATTACHED as frame-a.png at the beginning of this conversation, before all tool calls. NOT frame-b.png or frame-c.png. Which side has the small black dot inside a colored shape? Return only a JSON object with key dot_side and value left or right.' > "$report/resume.out" 2>&1
jq -Rs 'capture("(?<answer>\\{[\\s\\S]*\\})").answer|fromjson' "$report/resume.out" > "$report/resume.answer.json"
jq -e -n --slurpfile want "$report/expected.json" --slurpfile got "$report/resume.answer.json" '$want[0][0].dot_side==$got[0].dot_side' >/dev/null
jq -se '[.[-1].request.messages[]|select((.content|type)=="array")|.content[]|select(.type=="image_url")]|length>=3' "$report/requests.jsonl" >/dev/null
jq -se 'def first_image: [.request.messages[]|select((.content|type)=="array")|.content[]|select(.type=="image_url")|.image_url.url][0]; (.[0]|first_image)==(.[-1]|first_image)' "$report/requests.jsonl" >/dev/null
echo 'PASS: unseen visual detail after Balthasar resume, with original image files removed'
