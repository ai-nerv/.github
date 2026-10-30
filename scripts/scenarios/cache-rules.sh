cache_rules() {
    local dir session note attempt script="$scratch/cache-rules.json" evidence="$report/cache-contract/rules"
    mkdir -p "$evidence"
    cat > "$script" <<'JSON'
[
  {"dialect":"anthropic-messages","when":{"body":"Extract project notes as JSON","once":true},"events":[{"text":"{\"ops\":[{\"op\":\"add\",\"title\":\"Diagnostics\",\"text\":\"Always keep diagnostics private.\",\"description\":\"Synthetic standing directive\",\"pinned\":true,\"evidence\":[{\"cursor\":1,\"quote\":\"Always keep diagnostics private.\"}]}]}"},{"finish":"end_turn"}]},
  {"dialect":"anthropic-messages","when":{"body":"Extract project notes as JSON"},"events":[{"text":"{\"ops\":[]}"},{"finish":"end_turn"}]},
  {"dialect":"anthropic-messages","when":{"body":"You are given the opening of a conversation"},"events":[{"text":"{\"title\":\"Private diagnostics rule\"}"},{"finish":"end_turn"}]},
  {"dialect":"anthropic-messages","events":[{"thinking":"rules reasoning"},{"signature":"rules-signature-v1"},{"text":"rule recorded"},{"finish":"end_turn"}]},
  {"dialect":"anthropic-messages","events":[{"text":"rule applied"},{"finish":"end_turn"}]},
  {"dialect":"anthropic-messages","events":[{"text":"rule retained"},{"finish":"end_turn"}]}
]
JSON
    cp "$script" "$evidence/script.json" || return 1
    dir=$(world cache-rules "$script" 'magi.helpers = { memory = false, notes = "acceptance/echo-1" }' ', reasoning = true' anthropic-messages) || return 1
    headless "$dir" || return 1
    inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --prompt 'Always keep diagnostics private.' \
        --answers 1 --seconds 30 > "$evidence/first.jsonl" 2> "$evidence/first.log" || return 1
    jq -e -s 'any(.[];.event=="assistant_delta" and .text=="rule recorded")' "$evidence/first.jsonl" >/dev/null || return 1
    inside "$dir" balthasar sessions --tool magi --json > "$evidence/sessions.json" || return 1
    session=$(jq -er '.result|select(length==1)|.[0].id' "$evidence/sessions.json") || return 1
    for attempt in $(seq 1 100); do
        inside "$dir" balthasar api --tool magi notes "\"$session\"" > "$evidence/notes.json" || return 1
        note=$(jq -r '.result[0].pinned[]?|select(.text=="Always keep diagnostics private.")|.id' "$evidence/notes.json")
        [[ -z $note ]] || break
        sleep 0.05
    done
    [[ -n $note ]] || { cp "$dir/requests.jsonl" "$evidence/requests.jsonl"; echo 'verified rule never reached the store'; return 1; }
    inside "$dir" balthasar api --tool magi note_open "\"$session\"" "$(jq -n --arg id "$note" '{id:$id}')" > "$evidence/note.json" || return 1
    inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --prompt 'apply the standing rule' \
        --answers 1 --seconds 30 > "$evidence/second.jsonl" 2> "$evidence/second.log" || return 1
    inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --prompt 'continue with the same rule' \
        --answers 1 --seconds 30 > "$evidence/third.jsonl" 2> "$evidence/third.log" || return 1
    cp "$dir/requests.jsonl" "$evidence/requests.jsonl" || return 1
    cat "$evidence"/{first,second,third}.jsonl > "$evidence/events.jsonl" || return 1
    inside "$dir" balthasar replay --tool magi "$session" --json > "$evidence/replay.json" || return 1
    jq -n --slurpfile requests "$evidence/requests.jsonl" --slurpfile events "$evidence/events.jsonl" \
        --slurpfile replay "$evidence/replay.json" --slurpfile note "$evidence/note.json" \
        '{requests:$requests,events:$events,replay:$replay[0],note:$note[0]}' > "$evidence/capture.json" || return 1
    jq -e -f "$root/scripts/cache-rules.jq" "$evidence/capture.json" > "$evidence/contract.json" || return 1
    "$BASH" "$root/scripts/tests/cache-rules.sh" "$evidence/capture.json" "$evidence/negative" || return 1
}
