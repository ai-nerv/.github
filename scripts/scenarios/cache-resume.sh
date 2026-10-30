cache_resume() {
    local dir session script="$scratch/cache-resume.json" evidence="$report/cache-contract/resume"
    mkdir -p "$evidence"
    cat > "$script" <<'JSON'
[
  {"dialect":"anthropic-messages","events":[{"thinking":"resume reasoning"},{"signature":"resume-signature-v1"},{"tool_call":{"id":"resume-read-1","name":"read","arguments":"{\"path\":\"resume.rs\"}"}},{"finish":"tool_use"}]},
  {"dialect":"anthropic-messages","events":[{"text":"before resume"},{"finish":"end_turn"}]},
  {"dialect":"anthropic-messages","events":[{"text":"after resume"},{"finish":"end_turn"}]},
  {"dialect":"anthropic-messages","events":[{"text":"continued after resume"},{"finish":"end_turn"}]}
]
JSON
    cp "$script" "$evidence/script.json" || return 1
    dir=$(world cache-resume "$script" 'magi.helpers = { memory = false }' \
        ', reasoning = true, input = { "text", "image" }' anthropic-messages) || return 1
    printf 'pub fn resume_value() -> u8 { 42 }\n' > "$dir/work/resume.rs"
    headless "$dir" || return 1
    inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --prompt 'read resume.rs' --image iVBORw0KGgo= \
        --answers 1 --seconds 30 > "$evidence/before.jsonl" 2> "$evidence/before.log" || return 1
    jq -e -s 'any(.[]; .event=="assistant_delta" and .text=="before resume")' "$evidence/before.jsonl" >/dev/null || return 1
    inside "$dir" balthasar sessions --tool magi --json > "$evidence/sessions.json" || return 1
    session=$(jq -er '.result | select(length==1) | .[0].id' "$evidence/sessions.json") || return 1
    inside "$dir" balthasar replay --tool magi "$session" --json > "$evidence/replay-before.json" || return 1
    if inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --resume missing-cache-session \
        --prompt 'must not be sent' --seconds 5 > "$evidence/refused.jsonl" 2> "$evidence/refused.log"; then
        echo 'unknown resume unexpectedly succeeded'; return 1
    fi
    jq -e -s 'any(.[]; .event=="refused")' "$evidence/refused.jsonl" >/dev/null || return 1
    [[ $(wc -l < "$dir/requests.jsonl") == 2 ]] || { echo 'refused resume sent a provider request'; return 1; }
    inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --resume "$session" \
        --prompt 'continue restored history' --answers 1 --seconds 30 > "$evidence/resumed.jsonl" 2> "$evidence/resumed.log" || return 1
    inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --prompt 'continue once more' \
        --answers 1 --seconds 30 > "$evidence/continued.jsonl" 2> "$evidence/continued.log" || return 1
    jq -e -s 'any(.[]; .event=="assistant_delta" and .text=="after resume")' "$evidence/resumed.jsonl" >/dev/null || return 1
    jq -e -s 'any(.[]; .event=="assistant_delta" and .text=="continued after resume")' "$evidence/continued.jsonl" >/dev/null || return 1
    cp "$dir/requests.jsonl" "$evidence/requests.jsonl" || return 1
    cat "$evidence"/{before,resumed,continued}.jsonl > "$evidence/events.jsonl" || return 1
    inside "$dir" balthasar replay --tool magi "$session" --json > "$evidence/replay-after.json" || return 1
    jq -n --slurpfile requests "$evidence/requests.jsonl" --slurpfile events "$evidence/events.jsonl" \
        --slurpfile before "$evidence/replay-before.json" --slurpfile after "$evidence/replay-after.json" \
        '{requests:$requests,events:$events,before:$before[0],after:$after[0]}' > "$evidence/capture.json" || return 1
    jq -e -f "$root/scripts/cache-resume.jq" "$evidence/capture.json" > "$evidence/contract.json" || return 1
    "$BASH" "$root/scripts/tests/cache-resume.sh" "$evidence/capture.json" "$evidence/negative" || return 1
}
