cache_mask() {
    local dir session n script="$scratch/cache-mask.json" evidence="$report/cache-contract/mask"
    mkdir -p "$evidence"
    cat > "$script" <<'JSON'
[
  {"dialect":"anthropic-messages","when":{"body":"You are given the opening of a conversation"},"events":[{"text":"{\"title\":\"Masked native read\"}"},{"finish":"end_turn"}]},
  {"dialect":"anthropic-messages","events":[{"thinking":"mask reasoning"},{"signature":"mask-signature-v1"},{"tool_call":{"id":"mask-read-1","name":"read","arguments":"{\"path\":\"mask.rs\"}"}},{"finish":"tool_use"}]},
  {"dialect":"anthropic-messages","refuse":{"status":400,"message":"prompt is too long: 250000 tokens > 200000 maximum"}},
  {"dialect":"anthropic-messages","events":[{"text":"masked answer"},{"finish":"end_turn"}]},
  {"dialect":"anthropic-messages","events":[{"text":"mask retained"},{"finish":"end_turn"}]},
  {"dialect":"anthropic-messages","events":[{"text":"mask stable"},{"finish":"end_turn"}]}
]
JSON
    cp "$script" "$evidence/script.json" || return 1
    dir=$(world cache-mask "$script" 'magi.helpers = { memory = false }' ', reasoning = true' anthropic-messages) || return 1
    {
        echo '// CACHE-MASK-FILE'
        for n in $(seq 1 400); do echo "pub fn f_$n() -> u32 { $n } // padding padding padding"; done
    } > "$dir/work/mask.rs"
    headless "$dir" || return 1
    inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --prompt 'read mask.rs' \
        --successful-answers --answers 1 --seconds 30 > "$evidence/first.jsonl" 2> "$evidence/first.log" || return 1
    inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --prompt 'continue with the selected mask' \
        --answers 1 --seconds 30 > "$evidence/second.jsonl" 2> "$evidence/second.log" || return 1
    inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --prompt 'keep the same mask' \
        --successful-answers --answers 1 --seconds 30 > "$evidence/third.jsonl" 2> "$evidence/third.log" || return 1
    cp "$dir/requests.jsonl" "$evidence/before-timeout.jsonl" || return 1
    if inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --successful-answers \
        --answers 1 --seconds 1 > "$evidence/timeout.jsonl" 2> "$evidence/timeout.log"; then
        echo 'successful-answer waiter accepted an idle timeout'; return 1
    fi
    grep -q 'Elapsed' "$evidence/timeout.log" || return 1
    jq -e -s 'any(.[];.event=="session_snapshot") and all(.[];.event!="assistant_ended")' "$evidence/timeout.jsonl" >/dev/null || return 1
    cmp "$evidence/before-timeout.jsonl" "$dir/requests.jsonl" || return 1
    cp "$dir/requests.jsonl" "$evidence/requests.jsonl" || return 1
    cat "$evidence"/{first,second,third}.jsonl > "$evidence/events.jsonl" || return 1
    jq -e -s 'any(.[];.event=="assistant_delta" and .text=="masked answer") and any(.[];.event=="assistant_delta" and .text=="mask retained")' "$evidence/events.jsonl" >/dev/null || return 1
    inside "$dir" balthasar sessions --tool magi --json > "$evidence/sessions.json" || return 1
    session=$(jq -er '.result|select(length==1)|.[0].id' "$evidence/sessions.json") || return 1
    inside "$dir" balthasar replay --tool magi "$session" --json > "$evidence/replay.json" || return 1
    jq -n --slurpfile requests "$evidence/requests.jsonl" --slurpfile events "$evidence/events.jsonl" \
        --slurpfile replay "$evidence/replay.json" '{requests:$requests,events:$events,replay:$replay[0]}' > "$evidence/capture.json" || return 1
    jq -e -f "$root/scripts/cache-mask.jq" "$evidence/capture.json" > "$evidence/contract.json" || return 1
    "$BASH" "$root/scripts/tests/cache-mask.sh" "$evidence/capture.json" "$evidence/negative" || return 1
}
