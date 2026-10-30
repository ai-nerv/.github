cache_contract() {
    local script="$scratch/cache-contract.json" dir evidence="$report/cache-contract" session
    local -a ledgers=()
    mkdir -p "$evidence"
    cat > "$script" <<'JSON'
[
  {"dialect":"anthropic-messages","usage":{"input":10,"output":5,"cache_read":0,"cache_write":100},"events":[
    {"thinking":"cache reasoning\r\n"},{"signature":"cache-signature-v1"},
    {"tool_call":{"id":"cache-read-1","name":"read","arguments":"{\"path\":\"a.rs\"}"}},{"finish":"tool_use"}]},
  {"dialect":"anthropic-messages","usage":{"input":5,"output":6,"cache_read":100,"cache_write":10},
    "events":[{"text":"first cache answer"},{"finish":"end_turn"}]},
  {"dialect":"anthropic-messages","usage":{"input":7,"output":4,"cache_read":110,"cache_write":5},
    "events":[{"text":"second cache answer"},{"finish":"end_turn"}]}
]
JSON
    cp "$script" "$evidence/script.json" || return 1
    dir=$(world cache-contract "$script" 'magi.helpers = { memory = false }' \
        ', reasoning = true, input = { "text", "image" }, cost = { input = 2, output = 8, cache_read = 0.25, cache_write = 2.5 }' \
        anthropic-messages) || return 1
    cp "$dir/c/melchior/providers.lua" "$evidence/provider.lua" || return 1
    printf 'pub fn cache_value() -> u8 { 42 }\n' > "$dir/work/a.rs"
    headless "$dir" || { cp "$dir/host.out" "$evidence/host.log"; return 1; }
    inside "$dir" "$client" --socket "$dir/r/s.sock" --prompt 'inspect a.rs for cache contract' --answers 1 --seconds 30 \
        > "$dir/first-events.jsonl" 2> "$dir/first-client.log" || return 1
    jq -e -s 'any(.[]; .event=="assistant_delta" and .text=="first cache answer") and
        any(.[]; .event=="assistant_ended" and .stop_reason=="end_turn")' "$dir/first-events.jsonl" >/dev/null || {
        cp "$dir/host.out" "$evidence/host.log"; echo 'first cached turn did not complete'; return 1;
    }
    inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --prompt 'continue cache contract' --answers 1 --seconds 30 \
        > "$dir/second-events.jsonl" 2> "$dir/second-client.log" || return 1
    jq -e -s 'any(.[]; .event=="assistant_delta" and .text=="second cache answer") and
        any(.[]; .event=="assistant_ended" and .stop_reason=="end_turn")' "$dir/second-events.jsonl" >/dev/null || {
        cp "$dir/host.out" "$evidence/host.log"; echo 'second cached turn did not complete'; return 1;
    }
    cp "$dir/requests.jsonl" "$evidence/requests.jsonl" || return 1
    cat "$dir/first-events.jsonl" "$dir/second-events.jsonl" > "$evidence/events.jsonl" || return 1
    jq -e -s '[.[] | select(.event=="cache_frame") | .reasons] == [[],[],[]]' \
        "$evidence/events.jsonl" > "$evidence/frame-diagnostics.json" || return 1
    jq -e -s '[.[] | select(.event=="provider_frame") | .reasons] == [[],[],[]]' \
        "$evidence/events.jsonl" > "$evidence/provider-frame-diagnostics.json" || return 1
    jq -e -s -f "$root/scripts/cache-contract.jq" "$dir/requests.jsonl" > "$evidence/contract.json" || return 1
    "$BASH" "$root/scripts/tests/cache-contract.sh" "$dir/requests.jsonl" "$evidence/negative" || return 1
    mapfile -t ledgers < <(find "$dir/r/melchior/.spent" -maxdepth 1 -type f ! -name '*.lock' ! -name '*.next')
    [[ ${#ledgers[@]} == 1 ]] || { echo 'ambiguous cache ledger'; return 1; }
    cp "${ledgers[0]}" "$evidence/ledger.txt" || return 1
    [[ $(cat "${ledgers[0]}") == 504 ]] || { echo 'supplied-counter ledger differs from 504 micros'; return 1; }
    inside "$dir" balthasar sessions --tool magi --json > "$evidence/sessions.json" || return 1
    session=$(jq -er '.result[0].id' "$evidence/sessions.json") || return 1
    inside "$dir" balthasar replay --tool magi "$session" --json > "$evidence/replay.json" || return 1
    jq -e '[.result[] | .raw? // empty | if type=="string" then fromjson else . end] | tostring |
        contains("cache-read-1") and contains("cache-signature-v1") and contains("pub fn cache_value") and
        contains("first cache answer") and contains("second cache answer")' "$evidence/replay.json" >/dev/null || return 1
    jq -e '[.result[].raw | fromjson | .entry] |
        map(.type)==["user","assistant","tool","assistant","user","assistant"] and
        .[0].text=="inspect a.rs for cache contract" and .[1].signatures.thinking=="cache-signature-v1" and
        .[2].id=="cache-read-1" and .[2].result.is_error==false and
        (.[2].result.output|contains("pub fn cache_value")) and
        .[3].text=="first cache answer" and .[4].text=="continue cache contract" and
        .[5].text=="second cache answer"' "$evidence/replay.json" >/dev/null || return 1
    cache_policy_transitions || return 1
    cache_resume || return 1
    cache_discovery || return 1
    cache_layout || return 1
    cache_rules || return 1
    cache_mask
}

cache_policy_transitions() {
    local script="$scratch/cache-policy.json" dir evidence="$report/cache-contract/policy" phase session
    local -a attachment=()
    mkdir -p "$evidence"
    cat > "$script" <<'JSON'
[
  {"dialect":"anthropic-messages","events":[{"thinking":"policy reasoning"},{"signature":"policy-signature-v1"},{"text":"policy answer 1"},{"finish":"end_turn"}]},
  {"dialect":"anthropic-messages","events":[{"text":"policy answer 2"},{"finish":"end_turn"}]},
  {"dialect":"anthropic-messages","events":[{"text":"policy answer 3"},{"finish":"end_turn"}]},
  {"dialect":"anthropic-messages","events":[{"text":"policy answer 4"},{"finish":"end_turn"}]}
]
JSON
    cp "$script" "$evidence/script.json" || return 1
    dir=$(world cache-policy "$script" 'magi.helpers = { memory = false }' \
        ', reasoning = true, input = { "text", "image" }' anthropic-messages) || return 1
    cp "$dir/c/melchior/providers.lua" "$evidence/provider-original.lua" || return 1
    headless "$dir" || { cp "$dir/host.out" "$evidence/host.log"; return 1; }
    for phase in 1 2 3 4; do
        attachment=()
        case "$phase" in
            1) attachment=(--image iVBORw0KGgo=) ;;
            2) sed 's/prompt_cache = "anthropic_ephemeral"/prompt_cache = "none"/' \
                "$evidence/provider-original.lua" > "$dir/c/melchior/providers.lua" ;;
            3) sed -e 's/prompt_cache = "anthropic_ephemeral"/prompt_cache = "none"/' \
                -e 's/input = { "text", "image" }/input = { "text" }/' \
                "$evidence/provider-original.lua" > "$dir/c/melchior/providers.lua" ;;
            4) cp "$evidence/provider-original.lua" "$dir/c/melchior/providers.lua" ;;
        esac
        cp "$dir/c/melchior/providers.lua" "$evidence/provider-$phase.lua" || return 1
        inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --prompt "policy prompt $phase" \
            "${attachment[@]}" --answers 1 --seconds 30 > "$evidence/events-$phase.jsonl" 2> "$evidence/client-$phase.log" || return 1
        jq -e -s --arg text "policy answer $phase" 'any(.[]; .event=="assistant_delta" and .text==$text) and
            any(.[]; .event=="assistant_ended" and .stop_reason=="end_turn")' "$evidence/events-$phase.jsonl" >/dev/null || return 1
    done
    cp "$dir/requests.jsonl" "$evidence/requests.jsonl" || return 1
    cat "$evidence"/events-{1,2,3,4}.jsonl > "$evidence/events.jsonl" || return 1
    jq -n --slurpfile requests "$evidence/requests.jsonl" --slurpfile events "$evidence/events.jsonl" \
        '{requests:$requests,events:$events}' > "$evidence/capture.json" || return 1
    jq -e -f "$root/scripts/cache-policy.jq" "$evidence/capture.json" > "$evidence/contract.json" || return 1
    "$BASH" "$root/scripts/tests/cache-policy.sh" "$evidence/capture.json" "$evidence/negative" || return 1
    inside "$dir" balthasar sessions --tool magi --json > "$evidence/sessions.json" || return 1
    session=$(jq -er '.result[0].id' "$evidence/sessions.json") || return 1
    inside "$dir" balthasar replay --tool magi "$session" --json > "$evidence/replay.json" || return 1
    jq -e '[.result[].raw|fromjson|.entry] | map(.type)==["user","assistant","user","assistant","user","assistant","user","assistant"] and
        .[0].images==[{data:"iVBORw0KGgo=",media_type:"image/png"}] and .[1].signatures.thinking=="policy-signature-v1" and
        .[7].text=="policy answer 4" and (tostring|contains("request_frame")|not)' "$evidence/replay.json" >/dev/null || return 1
}
