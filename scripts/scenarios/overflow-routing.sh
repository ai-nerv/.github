overflow_routing() {
    local case dir evidence message shape dialect session settled n
    for case in output input unknown; do
        evidence="$report/context-pressure/overflow/$case"
        mkdir -p "$evidence" || return 1
        dialect=openai-completions
        case "$case" in
            output)
                shape=vllm
                message="'max_tokens' or 'max_completion_tokens' is too large: 77. This model's maximum context length is 64 tokens and your request has 12 input tokens (77 > 64 - 12)."
                ;;
            input)
                shape=anthropic; dialect=anthropic-messages
                message='prompt is too long: 250000 tokens > 200000 maximum'
                ;;
            unknown)
                shape=message
                message='prompt is too long: 250000 tokens > 200000 maximum'
                ;;
        esac
        jq -n --arg shape "$shape" --arg message "$message" --arg dialect "$dialect" \
            '[{dialect:$dialect,refuse:{status:400,shape:$shape,message:$message}}]' > "$evidence/script.json" || return 1
        dir=$(world "overflow-$case" "$evidence/script.json" 'magi.helpers = { memory = false }
magi.melchior = { max_tokens = 77 }' '' "$dialect") || return 1
        cp "$dir/c/magi/init.lua" "$evidence/magi-init.lua" || return 1
        cp "$dir/c/melchior/providers.lua" "$evidence/providers.lua" || return 1
        headless "$dir" env NERV_LOG="$dir/family.log" || return 1
        inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --prompt 'overflow routing probe' \
            --answers 2 --seconds 2 > "$evidence/events.jsonl" 2> "$evidence/client.log" || return 1
        settled=false
        for n in $(seq 1 10); do
            if inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --successful-answers \
                --answers 1 --seconds 1 > "$evidence/settled-$n.jsonl" 2> "$evidence/settled-$n.log"; then
                echo "$case: refusal unexpectedly produced a successful answer"; return 1
            fi
            grep -q 'Elapsed' "$evidence/settled-$n.log" || return 1
            if jq -e -s 'any(.[];.event=="session_snapshot" and .status.kind=="idle") and all(.[];.event!="assistant_ended")' \
                "$evidence/settled-$n.jsonl" >/dev/null; then
                cp "$evidence/settled-$n.jsonl" "$evidence/settled.jsonl" || return 1
                settled=true; break
            fi
        done
        [[ $settled == true ]] || { echo "$case: refusal did not settle"; return 1; }
        cp "$dir/requests.jsonl" "$evidence/requests.jsonl" || return 1
        cp "$dir/family.log" "$evidence/family.log" || return 1
        cp "$dir/host.out" "$evidence/host.out" || return 1
        inside "$dir" balthasar sessions --tool magi --json > "$evidence/sessions.json" || return 1
        session=$(jq -er '.result|select(length==1)|.[0].id' "$evidence/sessions.json") || return 1
        inside "$dir" balthasar replay --tool magi "$session" --json > "$evidence/replay.json" || return 1
        jq -n --arg case "$case" --slurpfile requests "$evidence/requests.jsonl" \
            --slurpfile events "$evidence/events.jsonl" --slurpfile settled "$evidence/settled.jsonl" \
            --slurpfile replay "$evidence/replay.json" --rawfile log "$evidence/family.log" \
            '{case:$case,requests:$requests,events:$events,settled:$settled,replay:$replay[0],log:$log}' > "$evidence/capture.json" || return 1
        jq -e -f "$root/scripts/overflow-routing.jq" "$evidence/capture.json" > "$evidence/contract.json" || return 1
        "$BASH" "$root/scripts/tests/overflow-routing.sh" "$evidence/capture.json" "$evidence/negative" || return 1
    done
}

output_budget_recovery() {
    local dir evidence session settled n
    evidence="$report/context-pressure/overflow/automatic"
    mkdir -p "$evidence" || return 1
    cat > "$evidence/script.json" <<'JSON'
[
  {"refuse":{"status":400,"shape":"vllm","message":"'max_tokens' or 'max_completion_tokens' is too large: 4096. This model's maximum context length is 1024 tokens and your request has 512 input tokens (4096 > 1024 - 512)."}},
  {"events":[{"text":"default recovered"},{"usage":{"input":512,"output":2}},{"finish":"stop"}]}
]
JSON
    dir=$(world overflow-automatic "$evidence/script.json" 'magi.helpers = { memory = false }') || return 1
    headless "$dir" env NERV_LOG="$dir/family.log" || return 1
    inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --prompt 'automatic output probe' \
        --successful-answers --answers 1 --seconds 10 > "$evidence/events.jsonl" 2> "$evidence/client.log" || return 1
    settled=false
    for n in $(seq 1 10); do
        if inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end --successful-answers \
            --answers 1 --seconds 1 > "$evidence/settled-$n.jsonl" 2> "$evidence/settled-$n.log"; then
            echo "automatic output recovery produced an extra answer"; return 1
        fi
        grep -q 'Elapsed' "$evidence/settled-$n.log" || return 1
        if jq -e -s 'any(.[];.event=="session_snapshot" and .status.kind=="idle") and all(.[];.event!="assistant_ended")' \
            "$evidence/settled-$n.jsonl" >/dev/null; then
            cp "$evidence/settled-$n.jsonl" "$evidence/settled.jsonl" || return 1
            settled=true; break
        fi
    done
    [[ $settled == true ]] || { echo "automatic output recovery did not settle"; return 1; }
    cp "$dir/requests.jsonl" "$evidence/requests.jsonl" || return 1
    cp "$dir/family.log" "$evidence/family.log" || return 1
    cp "$dir/host.out" "$evidence/host.out" || return 1
    inside "$dir" balthasar sessions --tool magi --json > "$evidence/sessions.json" || return 1
    session=$(jq -er '.result|select(length==1)|.[0].id' "$evidence/sessions.json") || return 1
    inside "$dir" balthasar replay --tool magi "$session" --json > "$evidence/replay.json" || return 1
    jq -n --slurpfile requests "$evidence/requests.jsonl" --slurpfile events "$evidence/events.jsonl" \
        --slurpfile settled "$evidence/settled.jsonl" --slurpfile replay "$evidence/replay.json" \
        --rawfile log "$evidence/family.log" \
        '{requests:$requests,events:$events,settled:$settled,replay:$replay[0],log:$log}' > "$evidence/capture.json" || return 1
    jq -e -f "$root/scripts/output-recovery.jq" "$evidence/capture.json" > "$evidence/contract.json" || return 1
    "$BASH" "$root/scripts/tests/output-recovery.sh" "$evidence/capture.json" "$evidence/negative" || return 1
}
