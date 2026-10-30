cache_discovery() {
    local dir session script="$scratch/cache-discovery.json" evidence="$report/cache-contract/discovery"
    mkdir -p "$evidence"
    cat > "$script" <<'JSON'
[
  {"dialect":"anthropic-messages","events":[{"thinking":"discovery reasoning"},{"signature":"discovery-signature-v1"},{"tool_call":{"id":"discover-1","name":"tools","arguments":"{\"path\":\"games/dino\"}"}},{"finish":"tool_use"}]},
  {"dialect":"anthropic-messages","events":[{"text":"manual discovered"},{"finish":"end_turn"}]},
  {"dialect":"anthropic-messages","events":[{"text":"tool frame retained"},{"finish":"end_turn"}]}
]
JSON
    cp "$script" "$evidence/script.json" || return 1
    dir=$(world cache-discovery "$script" 'magi.helpers = { memory = false }' ', reasoning = true' anthropic-messages) || return 1
    headless "$dir" || return 1
    inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --prompt 'look up the dino manual without running it' \
        --answers 1 --seconds 30 > "$evidence/first.jsonl" 2> "$evidence/first.log" || return 1
    inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --prompt 'keep the discovered tool without running it' \
        --answers 1 --seconds 30 > "$evidence/second.jsonl" 2> "$evidence/second.log" || return 1
    jq -e -s 'any(.[]; .event=="assistant_delta" and .text=="manual discovered")' "$evidence/first.jsonl" >/dev/null || return 1
    jq -e -s 'any(.[]; .event=="assistant_delta" and .text=="tool frame retained")' "$evidence/second.jsonl" >/dev/null || return 1
    cp "$dir/requests.jsonl" "$evidence/requests.jsonl" || return 1
    cat "$evidence"/{first,second}.jsonl > "$evidence/events.jsonl" || return 1
    inside "$dir" balthasar sessions --tool magi --json > "$evidence/sessions.json" || return 1
    session=$(jq -er '.result|select(length==1)|.[0].id' "$evidence/sessions.json") || return 1
    inside "$dir" balthasar replay --tool magi "$session" --json > "$evidence/replay.json" || return 1
    jq -n --slurpfile requests "$evidence/requests.jsonl" --slurpfile events "$evidence/events.jsonl" \
        --slurpfile replay "$evidence/replay.json" '{requests:$requests,events:$events,replay:$replay[0]}' > "$evidence/capture.json" || return 1
    jq -e -f "$root/scripts/cache-discovery.jq" "$evidence/capture.json" > "$evidence/contract.json" || return 1
    "$BASH" "$root/scripts/tests/cache-discovery.sh" "$evidence/capture.json" "$evidence/negative" || return 1
}
