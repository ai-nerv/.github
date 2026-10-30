#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
source "$root/scripts/preserve-binary.sh"
"$BASH" "$root/scripts/context-proof.sh" >/dev/null
source_binary=$("$BASH" "$root/scripts/select-binary.sh" casper)
digest=""
backend=$(command -v bwrap)
reader=$(command -v head)
mkdir -p "$root/target/acceptance"
report=$(mktemp -d "$root/target/acceptance/native-mcp-XXXXXXXX")
mkdir -m 700 "$report/bin"
binary="$report/bin/casper"
touch "$report/binaries.sha256"
scratch=$(mktemp -d /tmp/nerv-selected-mcp.XXXXXXXX)
printf '[]\n' > "$report/cases.json"
finish() {
    local status=$?
    trap - EXIT
    if ! verify_preserved_binaries "$report/binaries.sha256"; then status=1; fi
    jq -n --argjson code "$status" --arg binary "$binary" --arg source_path "$source_binary" --arg digest "$digest" \
        --slurpfile cases "$report/cases.json" --slurpfile asset "$report/asset.json" \
        --slurpfile isolation "$report/isolation.json" \
        '{status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,
          binary:$binary,source_path:$source_path,sha256:$digest,configuration_asset:$asset[0],isolation:$isolation[0],cases:$cases[0]}' > "$report/summary.json"
    rm -rf -- "$scratch"
    echo "selected native MCP: exit $status; evidence: $report"
    exit "$status"
}
printf 'null\n' > "$report/asset.json"
printf 'null\n' > "$report/isolation.json"
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
digest=$(preserve_binary "$source_binary" "$binary" "$report/binaries.sha256")
"$BASH" "$root/scripts/context-proof.sh" > "$report/isolation.json"
mkdir -p "$scratch"/{work/readers,home,config/casper,data,runtime}
cp "$root/casper/config/tools.lua" "$scratch/config/casper/tools.lua"
cp "$root/casper/config/tools.lua" "$scratch/work/server-tools.lua"
"$BASH" "$root/scripts/selected-tools.sh" "$root/casper/config/tools.lua" \
    "$scratch/work/server-tools.lua" selected-native-mcp > "$report/asset.json"
ln -s "$reader" "$scratch/work/readers/head"
printf 'first\nsecond\nthird\n' > "$scratch/work/quoted \"file\".txt"
{ head -c 2097152 /dev/zero | tr '\0' x; printf '\nTAIL\n'; } > "$scratch/work/large.txt"
printf '%s' 'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7' | base64 -d > "$scratch/work/image.gif"
configuration=$(jq -n --arg binary "$binary" --arg source "$scratch/work/server-tools.lua" \
    --arg config "$scratch/server-config" '{mcp_servers:{nested:{command:$binary,args:["mcp","--tools=read"],
      env:{CASPER_JAIL:"1",XDG_CONFIG_HOME:$config,CASPER_CONFIGURE:({load:$source}|tojson)},needs:"read"}}}')
invoke() {
    local args=$1
    (cd "$scratch/work" && env -i PATH="$runtime_path" HOME="$scratch/home" \
        XDG_CONFIG_HOME="$scratch/config" XDG_DATA_HOME="$scratch/data" XDG_RUNTIME_DIR="$scratch/runtime" \
        CASPER_JAIL=1 CASPER_CONFIGURE="$configuration" "$binary" run --json \
        <<< "$(jq -n --argjson args "$args" '{tool:"mcp__nested__read",args:$args}')")
}
for selected_backend in bubblewrap landlock; do
    runtime_path="$scratch/work/readers"
    if [[ $selected_backend == bubblewrap ]]; then runtime_path="${backend%/*}:$runtime_path"; fi
    invoke '{"path":"quoted \"file\".txt","offset":2,"limit":1}' > "$report/$selected_backend-range.json"
    jq -e '.ok and (.result[0].failed!=true) and
        (.result[0]|has("observations")|not) and
        (.result[0].said|fromjson|.content[0].text|contains("second")) and
        (.result[0].said|fromjson|.structuredContent|has("observations")|not)' "$report/$selected_backend-range.json" >/dev/null
    invoke '{"path":"large.txt","offset":2,"limit":1}' > "$report/$selected_backend-preview.json"
    jq -e '.ok and (.result[0].failed!=true) and (.result[0]|has("observations")|not) and
        (.result[0].said|fromjson|.content[0].text|contains("TAIL"))' "$report/$selected_backend-preview.json" >/dev/null
    invoke '{"path":"image.gif"}' > "$report/$selected_backend-image.json"
    jq -e '.ok and (.result[0].failed!=true) and (.result[0].images|length)==1 and
        (.result[0]|has("observations")|not)' "$report/$selected_backend-image.json" >/dev/null
    invoke '{"path":"quoted \"file\".txt","contents":"mutation"}' > "$report/$selected_backend-refusal.json"
    jq -e '.ok and .result[0].failed and (.result[0]|has("observations")|not)' "$report/$selected_backend-refusal.json" >/dev/null
    jq --arg backend "$selected_backend" '.+[{backend:$backend,range:"PASS",preview:"PASS",image:"PASS",mutation_refusal:"PASS"}]' \
        "$report/cases.json" > "$report/next.json"
    mv "$report/next.json" "$report/cases.json"
done
