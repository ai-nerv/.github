cache_layout() {
    local dir session i n script="$scratch/cache-layout.json" evidence="$report/cache-contract/layout"
    mkdir -p "$evidence"
    cat > "$script" <<'JSON'
[
  {"dialect":"anthropic-messages","when":{"body":"You keep the running summary"},"events":[{"text":"Cache layout summary. The person asked: read the layout files. The files were inspected."},{"finish":"end_turn"}]},
  {"dialect":"anthropic-messages","when":{"body":"You are given the opening of a conversation"},"events":[{"text":"{\"title\":\"Cache layout inspection\"}"},{"finish":"end_turn"}]},
  {"dialect":"anthropic-messages","events":[{"thinking":"layout reasoning"},{"signature":"layout-signature-v1"},{"tool_call":{"id":"layout-0","name":"read","arguments":"{\"path\":\"missing.rs\"}"}},{"finish":"tool_use"}]},
  {"dialect":"anthropic-messages","events":[{"tool_call":{"id":"layout-1","name":"read","arguments":"{\"path\":\"big1.rs\"}"}},{"finish":"tool_use"}]},
  {"dialect":"anthropic-messages","events":[{"tool_call":{"id":"layout-2","name":"read","arguments":"{\"path\":\"big2.rs\"}"}},{"finish":"tool_use"}]},
  {"dialect":"anthropic-messages","events":[{"tool_call":{"id":"layout-3","name":"read","arguments":"{\"path\":\"big3.rs\"}"}},{"finish":"tool_use"}]},
  {"dialect":"anthropic-messages","events":[{"tool_call":{"id":"layout-4","name":"read","arguments":"{\"path\":\"big4.rs\"}"}},{"finish":"tool_use"}]},
  {"dialect":"anthropic-messages","events":[{"text":"layout answer"},{"finish":"end_turn"}]},
  {"dialect":"anthropic-messages","events":[{"text":"layout continued"},{"finish":"end_turn"}]}
]
JSON
    cp "$script" "$evidence/script.json" || return 1
    dir=$(world cache-layout "$script" 'magi.helpers = { memory = false, summary = "acceptance/echo-1" }' \
        ', reasoning = true' anthropic-messages) || return 1
    sed -i 's/context_window = 200000/context_window = 32000/' "$dir/c/melchior/providers.lua"
    for i in 1 2 3 4; do
        {
            echo "// CACHE-LAYOUT-FILE-$i"
            for n in $(seq 1 250); do
                echo "pub fn f${i}_$n() -> u32 { $n } // padding padding padding"
            done
        } > "$dir/work/big$i.rs"
    done
    headless "$dir" || return 1
    inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --prompt 'read the layout files' \
        --answers 1 --seconds 60 > "$evidence/first.jsonl" 2> "$evidence/first.log" || return 1
    jq -e -s 'any(.[]; .event=="assistant_delta" and .text=="layout answer")' "$evidence/first.jsonl" >/dev/null || {
        cp "$dir/host.out" "$evidence/host.log"; cp "$dir/requests.jsonl" "$evidence/requests.jsonl"
        echo 'layout first prompt failed'; return 1;
    }
    # The helpers the first turn left behind land before the next prompt is laid out.
    for ((i = 0; i < 600; i++)); do
        [[ $(grep -c 'You keep the running summary' "$dir/requests.jsonl") -ge 2 ]] &&
            grep -q 'You are given the opening of a conversation' "$dir/requests.jsonl" && break
        sleep 0.05
    done
    (( i < 600 )) || { cp "$dir/requests.jsonl" "$evidence/requests.jsonl"; echo 'layout helpers did not run'; return 1; }
    sleep 1
    inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --prompt 'continue the layout history' \
        --answers 1 --seconds 60 > "$evidence/second.jsonl" 2> "$evidence/second.log" || return 1
    jq -e -s 'any(.[]; .event=="assistant_delta" and .text=="layout continued")' "$evidence/second.jsonl" >/dev/null || {
        cp "$dir/requests.jsonl" "$evidence/requests.jsonl"; echo 'layout continuation failed'; return 1;
    }
    cp "$dir/requests.jsonl" "$evidence/requests.jsonl" || return 1
    cat "$evidence"/{first,second}.jsonl > "$evidence/events.jsonl" || return 1
    inside "$dir" balthasar sessions --tool magi --json > "$evidence/sessions.json" || return 1
    session=$(jq -er '.result|select(length==1)|.[0].id' "$evidence/sessions.json") || return 1
    inside "$dir" balthasar replay --tool magi "$session" --json > "$evidence/replay.json" || return 1
    jq -n --slurpfile requests "$evidence/requests.jsonl" --slurpfile events "$evidence/events.jsonl" \
        --slurpfile replay "$evidence/replay.json" '{requests:$requests,events:$events,replay:$replay[0]}' > "$evidence/capture.json" || return 1
    jq -e -f "$root/scripts/cache-layout.jq" "$evidence/capture.json" > "$evidence/contract.json" || return 1
    "$BASH" "$root/scripts/tests/cache-layout.sh" "$evidence/capture.json" "$evidence/negative" || return 1
}
