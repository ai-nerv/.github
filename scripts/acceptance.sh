#!/usr/bin/env bash
# Deterministic acceptance: the whole family as real processes, against answers chosen in advance.
#
# No credentials and no network. A fake provider serves melchior's own chat-completions dialect
# over real HTTP, so the transport, the streaming and the four processes are production code and
# only the source of the events is fake.
#
# Every scenario PLAN.md requires is listed below. One that is not implemented yet is recorded
# NOT VERIFIED and fails the run, because a lane that reports green while a required scenario was
# never exercised is worse than no lane.
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
members=(magi casper melchior balthasar)
for program in oslo jq timeout realpath sha256sum; do
    command -v "$program" >/dev/null || { echo "missing prerequisite: $program" >&2; exit 2; }
done
oslo=$(command -v oslo)

mkdir -p "$root/target/acceptance"
report=$(mktemp -d "$root/target/acceptance/run-XXXXXXXX")
scratch=$(mktemp -d /tmp/na.XXXXXX)
started=$(date -u +%FT%TZ)
printf '[]\n' > "$report/members.json"
printf '[]\n' > "$report/scenarios.json"

finish() {
    local status=$?
    trap - EXIT
    pkill -P $$ >/dev/null 2>&1 || true
    # Whatever a scenario left running: a headless session is started through a wrapper, and
    # ending the wrapper ends neither it nor the siblings it convened. Found by where they
    # are running, which is the one thing every one of them has in common.
    local entry cwd
    for entry in /proc/[0-9]*/cwd; do
        cwd=$(readlink "$entry" 2>/dev/null) || continue
        [[ $cwd == "$scratch"* ]] || continue
        entry=${entry#/proc/}
        kill "${entry%/cwd}" 2>/dev/null || true
    done
    if [[ -f "$scratch/fakes" ]]; then
        while read -r fake_pid; do kill "$fake_pid" 2>/dev/null || true; done < "$scratch/fakes"
    fi
    local failed missing recorded
    recorded=$(jq -r 'length' "$report/scenarios.json")
    failed=$(jq -r '[.[] | select(.verdict != "PASS")] | length' "$report/scenarios.json")
    missing=$(jq -r '[.[] | select(.verdict == "NOT VERIFIED")] | length' "$report/scenarios.json")
    # A required scenario that failed, or was never exercised, is a failed run. A run that
    # recorded nothing at all is a broken harness, not a passing one.
    (( failed == 0 )) || status=1
    if (( recorded == 0 )); then
        status=1
        echo "acceptance: no scenario was recorded; the harness stopped before running any" >&2
    fi
    jq -n --arg started "$started" --arg root_commit "$(git -C "$root" rev-parse --verify HEAD 2>/dev/null || echo uncommitted)" \
        --arg root_dirty "$(git -C "$root" status --porcelain 2>/dev/null)" \
        --argjson exit_code "$status" --argjson not_verified "$missing" \
        --slurpfile members "$report/members.json" --slurpfile scenarios "$report/scenarios.json" \
        '{started:$started, kind:"deterministic", exit_code:$exit_code,
          root:{commit:$root_commit, dirty:($root_dirty != "")},
          status:(if $exit_code == 0 then "PASS" else "FAIL" end),
          not_verified:$not_verified, members:$members[0], scenarios:$scenarios[0]}' \
        > "$report/summary.json"
    {
        echo "# Acceptance $started"
        echo
        echo "- status: $(jq -r .status "$report/summary.json")"
        echo "- not verified: $missing"
        echo
        echo "| scenario | verdict | ms | detail |"
        echo "|---|---|---|---|"
        jq -r '.[] | "| \(.id) | \(.verdict) | \(.ms) | \(.detail) |"' "$report/scenarios.json"
    } > "$report/summary.md"
    printf 'acceptance: exit %s; evidence: %s\n' "$status" "$report"
    rm -rf -- "$scratch"
    exit "$status"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ---- the exact family, built from each member's own recipe ------------------------------------
selected=()
for member in "${members[@]}"; do
    recipe=build
    [[ $member != balthasar ]] || recipe=build-host
    (cd "$root/$member" && "$oslo" make "$recipe") > "$report/$member-build.log" 2>&1
    path=$(cd "$root/$member" && "$oslo" make family-path | sed -n 's/^NERV_BINARY=//p')
    binary=$(realpath -e "$root/$member/$path")
    selected+=("$binary")
    digest=$(sha256sum "$binary"); digest=${digest%% *}
    jq --arg name "$member" --arg path "$binary" --arg sha256 "$digest" \
        --arg commit "$(git -C "$root/$member" rev-parse --verify HEAD 2>/dev/null || echo uncommitted)" \
        --arg dirty "$(git -C "$root/$member" status --porcelain 2>/dev/null)" \
        '. + [{name:$name, path:$path, commit:$commit, dirty:($dirty != ""), sha256:$sha256}]' \
        "$report/members.json" > "$report/next.json"
    mv "$report/next.json" "$report/members.json"
done

(cd "$root/melchior" && cargo build --example fake-provider) > "$report/fake-build.log" 2>&1
fake="$root/melchior/target/debug/examples/fake-provider"
# A screen with nobody at it, for the scenarios that need a session to outlive one prompt.
(cd "$root/magi" && cargo build -p magi-testkit --example session-client) > "$report/client-build.log" 2>&1
client="$root/magi/target/debug/examples/session-client"
family_path=""
for binary in "${selected[@]}"; do family_path+="${binary%/*}:"; done

record() {
    jq --arg id "$1" --arg verdict "$2" --arg ms "$3" --arg detail "$4" \
        '. + [{id:$id, verdict:$verdict, ms:($ms|tonumber), detail:$detail}]' \
        "$report/scenarios.json" > "$report/next.json"
    mv "$report/next.json" "$report/scenarios.json"
}

# ---- one scenario's world ----------------------------------------------------------------------
# A home, a config for each member, a fake on a port it chose, and nothing of the developer's.
world() {
    local id=$1 script=$2 extra=${3:-}
    local dir="$scratch/$id"
    mkdir -p "$dir"/{c/melchior,d,s,r,t,work}
    chmod 700 "$dir/r"
    # Every member's own configuration, because a tool a session can call is a file casper
    # installs: without them the model is offered magi's own verbs and nothing else.
    for member in magi casper balthasar; do
        [[ -d "$root/$member/config" ]] && cp -r "$root/$member/config" "$dir/c/$member"
    done
    cp "$root/melchior/config/apis.lua" "$dir/c/melchior/"
    "$fake" --script "$script" --port 0 --record "$dir/requests.jsonl" > "$dir/fake.out" 2>&1 &
    # Written down, because this runs in a subshell: the fake outlives it, belongs to nobody the
    # script can find by ancestry, and was still running a day later.
    echo $! >> "$scratch/fakes"
    local port=""
    for _ in $(seq 1 200); do
        port=$(sed -n 's/^PORT=//p' "$dir/fake.out" || true)
        [[ -n $port ]] && break
        sleep 0.05
    done
    [[ -n $port ]] || { echo "the fake provider never named its port" >&2; return 1; }
    cat > "$dir/c/melchior/providers.lua" <<LUA
melchior.provider("acceptance", {
  name = "Acceptance Fake", api = "openai-completions",
  base_url = "http://127.0.0.1:$port/v1", auth = { kind = "none" },
  models = { { id = "echo-1", name = "Echo 1", context_window = 200000, max_tokens = 4096 } },
})
LUA
    # Appended, never reassigned: the shipped file already grants `run melchior`, and a second
    # `magi.allow = { .. }` would drop it and leave the session unable to reach a model at all.
    {
        printf '\nmagi.model = "acceptance/echo-1"\n'
        printf 'magi.allow[#magi.allow + 1] = { verb = "read", directory = "%s/work" }\n' "$dir"
        [[ -z $extra ]] || printf '%s\n' "$extra"
    } >> "$dir/c/magi/init.lua"
    echo "$dir"
}

inside() {
    local dir=$1; shift
    (cd "$dir/work" && env -i PATH="$family_path/usr/bin:/bin" HOME="$dir" \
        XDG_CONFIG_HOME="$dir/c" XDG_DATA_HOME="$dir/d" XDG_STATE_HOME="$dir/s" \
        XDG_RUNTIME_DIR="$dir/r" TMPDIR="$dir/t" timeout 180 "$@")
}

# A session with no terminal that stays up, and the socket it answers on. Ended with the fakes.
headless() {
    local dir=$1
    inside "$dir" magi --headless --socket "$dir/r/s.sock" > "$dir/host.out" 2>&1 &
    echo $! >> "$scratch/fakes"
    for _ in $(seq 1 200); do
        [[ -S "$dir/r/s.sock" ]] && return 0
        sleep 0.05
    done
    echo "the headless session never opened its socket" >&2
    return 1
}

# Every pattern appears, and in this order.
in_order() {
    local file=$1; shift
    local at=0 line
    for pattern in "$@"; do
        line=$(grep -n -- "$pattern" "$file" | head -1 | cut -d: -f1 || true)
        [[ -n $line && $line -gt $at ]] || return 1
        at=$line
    done
}

# ---- the scenarios PLAN.md requires ------------------------------------------------------------
# Every id below is required. One with no function yet is recorded NOT VERIFIED and fails the run.
REQUIRED=(
    basic-coding-loop
    multi-client
    resume-and-restart
    memory-process-loss
    memory-absent-at-startup
    tool-containment
    retry-transport-failures
    context-pressure
    helper-modes
    cross-session-memory
    agent-coordination
)

# Prompt, streamed answer, a tool call and its result, a second request, and the final answer --
# all of it recorded in the order it happened.
basic_coding_loop() {
    local dir script session
    script="$scratch/basic-coding-loop.json"
    cat > "$script" <<'JSON'
[
  {"when":{"tools":0},"events":[{"text":"{\"ops\": []}"},{"finish":"stop"}]},
  {"events":[{"text":"Let me read it."},
             {"tool_call":{"id":"call-1","name":"read","arguments":"{\"path\":\"a.rs\"}"}},
             {"finish":"tool_calls"}]},
  {"events":[{"text":"It defines answer()."},{"finish":"stop"}]}
]
JSON
    dir=$(world basic-coding-loop "$script") || return 1
    printf 'pub fn answer() -> u8 { 42 }\n' > "$dir/work/a.rs"
    inside "$dir" magi -p "what is in a.rs" > "$dir/said.txt" 2>&1 || true
    grep -q 'It defines answer()' "$dir/said.txt" || {
        echo "the final answer never arrived: $(tr '\n' ' ' < "$dir/said.txt" | cut -c1-200)"
        return 1
    }
    session=$(inside "$dir" balthasar sessions --tool magi --json 2>/dev/null |
        head -1 | jq -r '.result[0].id // empty')
    [[ -n $session ]] || { echo "balthasar recorded no session"; return 1; }
    inside "$dir" balthasar replay --tool magi "$session" > "$dir/replay.txt" 2>&1 || true
    # The tool has to have run. Matching the word "read" would also match the refusal that says
    # there is no such tool, which is how this passed once while proving nothing.
    if grep -q 'there is no tool called' "$dir/replay.txt"; then
        echo "the tool never existed: $(grep -m1 'there is no tool called' "$dir/replay.txt")"
        return 1
    fi
    if grep -q 'not permitted' "$dir/replay.txt"; then
        echo "the tool was refused: $(grep -m1 'not permitted' "$dir/replay.txt")"
        return 1
    fi
    grep -qE '^ *[0-9]+ +tool ' "$dir/replay.txt" || {
        echo "nothing was recorded as a tool result"
        return 1
    }
    # What the file actually says. A tool that was missing, refused, or never ran cannot produce
    # this, which is the whole point of asserting on it rather than on the model's own words.
    grep -q 'pub fn answer' "$dir/replay.txt" || {
        echo "the tool result never carried the file: $(grep -m1 -E '^ *[0-9]+ +tool ' "$dir/replay.txt")"
        return 1
    }
    in_order "$dir/replay.txt" 'what is in a.rs' 'Let me read it.' 'It defines answer()' || {
        echo "the transcript is not in order: $(tr '\n' ' ' < "$dir/replay.txt" | cut -c1-200)"
        return 1
    }
}

# Helpers off keeps none: the session's turn is the only request the provider ever sees. The
# second turn is a tripwire, so an extra request shows up as a wrong answer rather than silence.
helper_memory_off() {
    local dir script asked
    script="$scratch/helper-modes.json"
    cat > "$script" <<'JSON'
[
  {"events":[{"text":"only the session turn"},{"usage":{"input":10,"output":3}},{"finish":"stop"}]},
  {"events":[{"text":"UNEXPECTED SECOND REQUEST"},{"finish":"stop"}]}
]
JSON
    dir=$(world helper-modes "$script" 'magi.helpers = { memory = false }') || return 1
    inside "$dir" magi -p "say hello" > "$dir/said.txt" 2>&1 || true
    grep -q 'only the session turn' "$dir/said.txt" || {
        echo "the answer never arrived: $(tr '\n' ' ' < "$dir/said.txt" | cut -c1-200)"
        return 1
    }
    asked=$(wc -l < "$dir/requests.jsonl")
    (( asked == 1 )) || { echo "helpers were off and the provider saw $asked requests"; return 1; }
}

# A run, a second run that is its own, and a restart that carries on with the right one. What
# settles it is the request the resumed run sent: the earlier prompt and its answer have to be in
# it, and the other run's must not.
resume_and_restart() {
    local dir script a b sessions resumed before after
    script="$scratch/resume-and-restart.json"
    cat > "$script" <<'JSON'
[
  {"when":{"tools":0},"events":[{"text":"{\"ops\": []}"},{"finish":"stop"}]},
  {"events":[{"text":"Let me read it."},
             {"tool_call":{"id":"call-1","name":"read","arguments":"{\"path\":\"a.rs\"}"}},
             {"finish":"tool_calls"}]},
  {"events":[{"text":"noted the gerbil"},{"finish":"stop"}]},
  {"events":[{"text":"noted separately"},{"finish":"stop"}]},
  {"events":[{"text":"picking up where we left off"},{"finish":"stop"}]}
]
JSON
    dir=$(world resume-and-restart "$script") || return 1
    printf 'pub fn answer() -> u8 { 42 }\n' > "$dir/work/a.rs"

    inside "$dir" magi -p "remember gerbil" > "$dir/a.txt" 2>&1 || true
    grep -q 'noted the gerbil' "$dir/a.txt" || {
        echo "the first run never answered: $(tr '\n' ' ' < "$dir/a.txt" | cut -c1-150)"
        return 1
    }
    inside "$dir" magi -p "start a separate thread" > "$dir/b.txt" 2>&1 || true
    grep -q 'noted separately' "$dir/b.txt" || {
        echo "the second run never answered: $(tr '\n' ' ' < "$dir/b.txt" | cut -c1-150)"
        return 1
    }
    inside "$dir" magi --resume -p "and now?" > "$dir/resumed.txt" 2>&1 || true
    grep -q 'picking up where we left off' "$dir/resumed.txt" || {
        echo "the resumed run never answered: $(tr '\n' ' ' < "$dir/resumed.txt" | cut -c1-150)"
        return 1
    }

    # A restart continues the newest run rather than starting a third.
    sessions=$(inside "$dir" balthasar sessions --tool magi --json 2>/dev/null | head -1)
    if [[ $(jq -r '.result | length' <<<"$sessions") != 2 ]]; then
        echo "expected two runs, saw $(jq -r '.result | length' <<<"$sessions")"
        return 1
    fi
    a=$(jq -r '.result[] | select(.title=="remember gerbil") | .id' <<<"$sessions")
    b=$(jq -r '.result[] | select(.title=="start a separate thread") | .id' <<<"$sessions")
    if [[ -z $a || -z $b ]]; then
        echo "the two runs are not both recorded: $sessions"
        return 1
    fi
    inside "$dir" balthasar replay --tool magi "$a" > "$dir/replay-a.txt" 2>&1 || true
    inside "$dir" balthasar replay --tool magi "$b" > "$dir/replay-b.txt" 2>&1 || true

    # The tool ran once, in the run that called it, and the restart never ran it again.
    if [[ $(grep -c 'pub fn answer' "$dir/replay-a.txt") != 1 ]]; then
        echo "the tool result is not recorded exactly once in the first run"
        return 1
    fi
    if grep -q 'pub fn answer' "$dir/replay-b.txt"; then
        echo "the tool was executed again in the run that never called it"
        return 1
    fi
    if grep -q 'remember gerbil' "$dir/replay-b.txt"; then
        echo "the second run's transcript carries the first run's prompt"
        return 1
    fi
    if ! grep -q 'picking up where we left off' "$dir/replay-b.txt"; then
        echo "the resumed answer did not land in the run it continued"
        return 1
    fi

    # And the resumed request carried the conversation it was continuing.
    resumed=$(jq -c 'select((.tools|length? // 0) > 0)' "$dir/requests.jsonl" | tail -1)
    if ! grep -q 'start a separate thread' <<<"$resumed"; then
        echo "the resumed request lost the earlier prompt"
        return 1
    fi
    if ! grep -q 'noted separately' <<<"$resumed"; then
        echo "the resumed request lost the earlier answer"
        return 1
    fi
    if grep -q 'remember gerbil' <<<"$resumed"; then
        echo "the resumed request carried the other run's conversation"
        return 1
    fi

    # A named run that cannot be read is an error, and the model is never asked.
    before=$(wc -l < "$dir/requests.jsonl")
    if inside "$dir" magi --resume-run no-such-run -p "and now?" > "$dir/gone.txt" 2>&1; then
        echo "a missing run started a fresh session"
        return 1
    fi
    if ! grep -q 'no-such-run' "$dir/gone.txt"; then
        echo "the missing run was not named: $(tr '\n' ' ' < "$dir/gone.txt" | cut -c1-150)"
        return 1
    fi
    after=$(wc -l < "$dir/requests.jsonl")
    (( before == after )) || { echo "the model was asked anyway ($before -> $after)"; return 1; }
}

# Every tool result in a request answers a call made before it in that same request, and every
# call has its result: a layout that split a pair would be refused by a real provider.
coherent() {
    jq -e -s 'all(.[] | select((.tools|length? // 0) > 0);
        . as $r
        | [$r.messages[] | select(.role=="assistant") | (.tool_calls // [])[] | .id] as $calls
        | [$r.messages[] | select(.role=="tool") | .tool_call_id] as $results
        | ($results - $calls | length) == 0 and ($calls - $results | length) == 0)' "$1" >/dev/null
}

# A small window filled by big tool results, then a provider that says the request is too long.
context_pressure() {
    local dir script sizes tightened last
    script="$scratch/context-pressure.json"
    cat > "$script" <<'JSON'
[
  {"when":{"tools":0},"events":[{"text":"{\"ops\": []}"},{"finish":"stop"}]},
  {"events":[{"tool_call":{"id":"c0","name":"read","arguments":"{\"path\":\"missing.rs\"}"}},{"finish":"tool_calls"}]},
  {"events":[{"tool_call":{"id":"c1","name":"read","arguments":"{\"path\":\"big1.rs\"}"}},{"finish":"tool_calls"}]},
  {"events":[{"tool_call":{"id":"c2","name":"read","arguments":"{\"path\":\"big2.rs\"}"}},{"finish":"tool_calls"}]},
  {"events":[{"tool_call":{"id":"c3","name":"read","arguments":"{\"path\":\"big3.rs\"}"}},{"finish":"tool_calls"}]},
  {"refuse":{"status":400,"message":"prompt is too long: 250000 tokens > 32000 maximum"}},
  {"refuse":{"status":400,"message":"prompt is too long: 250000 tokens > 32000 maximum"}},
  {"events":[{"tool_call":{"id":"c4","name":"history","arguments":"{\"want\":\"matching\",\"terms\":[\"FILE-1-MARKER\"],\"tokens\":300}"}},{"finish":"tool_calls"}]},
  {"events":[{"text":"done reading"},{"finish":"stop"}]}
]
JSON
    dir=$(world context-pressure "$script") || return 1
    # The pressure is real: a model that reads 32k and says 4k, as a small local one does.
    sed -i 's|context_window = 200000|context_window = 32000|' "$dir/c/melchior/providers.lua"
    for i in 1 2 3; do
        {
            echo "// FILE-$i-MARKER"
            for n in $(seq 1 400); do
                echo "pub fn f${i}_$n() -> u32 { $n } // padding padding padding"
            done
        } > "$dir/work/big$i.rs"
    done
    if ! inside "$dir" magi -p "read the files" > "$dir/said.txt" 2>&1; then
        echo "the run failed: $(tr '\n' ' ' < "$dir/said.txt" | cut -c1-200)"
        return 1
    fi
    grep -q 'done reading' "$dir/said.txt" || {
        echo "the answer never arrived after the refusals: $(tr '\n' ' ' < "$dir/said.txt" | cut -c1-200)"
        return 1
    }
    jq -c 'select((.tools|length? // 0) > 0)' "$dir/requests.jsonl" > "$dir/session.jsonl"

    coherent "$dir/requests.jsonl" || { echo "a request split a tool call from its result"; return 1; }

    # Refused twice, and each request after a refusal is smaller than the one refused.
    sizes=$(jq -c 'tostring | length' "$dir/session.jsonl" | tr '\n' ' ')
    read -r -a sizes <<<"$sizes"
    if (( ${#sizes[@]} != 8 )); then
        echo "expected eight session requests, saw ${#sizes[@]}: ${sizes[*]}"
        return 1
    fi
    if (( sizes[5] >= sizes[4] || sizes[6] >= sizes[5] )); then
        echo "a layout after a refusal was not tighter: ${sizes[*]}"
        return 1
    fi

    # What was stubbed is the big result, and what failed is still there word for word.
    tightened=$(sed -n '7p' "$dir/session.jsonl")
    if grep -q 'pub fn f1_1()' <<<"$tightened"; then
        echo "the oldest big result was never stubbed"
        return 1
    fi
    if ! grep -q 'missing.rs' <<<"$tightened"; then
        echo "the failed call was dropped under pressure"
        return 1
    fi
    # And what was stubbed can be had back: the last request carries what `history` returned.
    last=$(tail -1 "$dir/session.jsonl")
    if ! jq -e '[.messages[] | select(.role=="tool" and .tool_call_id=="c4") | .content | tostring]
                | any(contains("FILE-1-MARKER"))' <<<"$last" >/dev/null; then
        echo "the stubbed result could not be read back through history"
        return 1
    fi
}

# A provider that never takes the request: the retries are bounded, and the failure is said.
context_pressure_is_bounded() {
    local dir script asked
    script="$scratch/context-pressure-bounded.json"
    cat > "$script" <<'JSON'
[
  {"when":{"tools":0},"events":[{"text":"{\"ops\": []}"},{"finish":"stop"}]},
  {"when":{"body":"never fits"},"refuse":{"status":400,"message":"prompt is too long: 250000 tokens > 32000 maximum"}}
]
JSON
    dir=$(world context-pressure-bounded "$script") || return 1
    if inside "$dir" magi -p "this never fits" > "$dir/said.txt" 2>&1; then
        echo "a request that was always refused was reported as a success"
        return 1
    fi
    asked=$(jq -c 'select((.tools|length? // 0) > 0)' "$dir/requests.jsonl" | wc -l)
    # The first request, and at most three tighter ones.
    if (( asked < 2 || asked > 4 )); then
        echo "expected between two and four requests, saw $asked"
        return 1
    fi
    grep -qi 'overflow\|too long' "$dir/said.txt" || {
        echo "the refusal was not said: $(tr '\n' ' ' < "$dir/said.txt" | cut -c1-200)"
        return 1
    }
}

# A session that cannot record is refused, out loud, before a word is sent to a model: the memory
# layer is the store, and there is no journal to fall back to.
memory_absent_at_startup() {
    local dir script
    script="$scratch/memory-absent.json"
    printf '[{"events":[{"text":"THIS SHOULD NEVER BE ASKED FOR"},{"finish":"stop"}]}]\n' > "$script"
    dir=$(world memory-absent-at-startup "$script" 'magi.memory = "no-such-memory-layer"') || return 1
    if inside "$dir" magi -p "say hello" > "$dir/said.txt" 2>&1; then
        echo "a session with no memory layer started anyway: $(tr '\n' ' ' < "$dir/said.txt" | cut -c1-200)"
        return 1
    fi
    grep -q 'no-such-memory-layer' "$dir/said.txt" || {
        echo "the refusal did not name what was missing: $(tr '\n' ' ' < "$dir/said.txt" | cut -c1-200)"
        return 1
    }
    if [[ -s "$dir/requests.jsonl" ]]; then
        echo "a model was asked by a session that could not record"
        return 1
    fi
}

# One answer through one kind of bad network. `$3` is what must come out, `$4` how many requests
# it may take at most: a retry that never stops is as wrong as an answer that is lost.
transport() {
    local id=$1 script=$2 want=$3 most=$4 dir asked
    dir=$(world "$id" "$script" 'magi.helpers = { memory = false }') || return 1
    inside "$dir" magi -p "say it" > "$dir/said.txt" 2>&1 || true
    keep "$id"
    asked=$(wc -l < "$dir/requests.jsonl" 2>/dev/null || echo 0)
    if (( asked > most )); then
        echo "$id: $asked requests, and at most $most were allowed"
        return 1
    fi
    [[ $(tail -1 "$dir/said.txt") == "$want" ]] || {
        echo "$id: wanted '$want', got '$(tr '\n' ' ' < "$dir/said.txt" | cut -c1-160)'"
        return 1
    }
}

retry_transport_failures() {
    local script dir
    # A character split across two chunks, on CRLF line endings, comes out whole.
    script="$scratch/rt-split.json"
    printf '[{"events":[{"split":"héllo wörld ✓"},{"finish":"stop"}]}]\n' > "$script"
    transport rt-split "$script" 'héllo wörld ✓' 1 || return 1

    # A connection that drops mid-answer is asked again, and the half that arrived is not kept.
    script="$scratch/rt-drop.json"
    cat > "$script" <<'JSON'
[
  {"events":[{"text":"HALF OF AN ANS"},"drop"]},
  {"events":[{"text":"the whole answer"},{"finish":"stop"}]}
]
JSON
    transport rt-drop "$script" 'the whole answer' 2 || return 1

    # A server error is waited out and asked again, a bounded number of times.
    script="$scratch/rt-error.json"
    cat > "$script" <<'JSON'
[
  {"refuse":{"status":500,"message":"upstream exploded"}},
  {"events":[{"text":"after the error"},{"finish":"stop"}]}
]
JSON
    transport rt-error "$script" 'after the error' 2 || return 1

    # An answer cut off at the length limit with a tool call in it: the call parses, and is still
    # never run, because nothing says the arguments were the ones the model meant.
    script="$scratch/rt-truncated.json"
    cat > "$script" <<'JSON'
[
  {"events":[{"tool_call":{"id":"t1","name":"shell","arguments":"{\"command\":\"touch PROOF-IT-RAN\"}"}},{"finish":"length"}]},
  {"events":[{"text":"THE TURN SHOULD HAVE ENDED"},{"finish":"stop"}]}
]
JSON
    dir=$(world rt-truncated "$script" 'magi.helpers = { memory = false }') || return 1
    inside "$dir" magi -p "say it" > "$dir/said.txt" 2>&1 || true
    keep rt-truncated
    if [[ -e "$dir/work/PROOF-IT-RAN" ]]; then
        echo "a tool call from a truncated answer was run"
        return 1
    fi
    # The turn ends there: the call is recorded as failed, and the model is not asked again.
    if [[ $(wc -l < "$dir/requests.jsonl") != 1 ]]; then
        echo "a truncated answer was followed by $(wc -l < "$dir/requests.jsonl") requests, not one"
        return 1
    fi
    local session
    session=$(inside "$dir" balthasar sessions --tool magi --json 2>/dev/null | head -1 | jq -r '.result[0].id // empty')
    inside "$dir" balthasar replay --tool magi "$session" > "$dir/replay.txt" 2>&1 || true
    keep rt-truncated
    grep -qi 'truncated' "$dir/replay.txt" || {
        echo "the cut-off call was not recorded as one: $(tr '\n' ' ' < "$dir/replay.txt" | cut -c1-160)"
        return 1
    }
}

# A model that reaches for a credential and for a file outside the project, through the real tool
# path with the jail on as it ships. It may work in the project; it gets neither of the others.
tool_containment() {
    local dir="$scratch/tool-containment" script="$scratch/tool-containment.json"
    cat > "$script" <<JSON
[
  {"events":[{"tool_call":{"id":"k1","name":"shell","arguments":"{\"command\":\"cat $dir/.ssh/id\"}"}},{"finish":"tool_calls"}]},
  {"events":[{"tool_call":{"id":"k2","name":"shell","arguments":"{\"command\":\"cp a.txt $dir/outside\"}"}},{"finish":"tool_calls"}]},
  {"events":[{"tool_call":{"id":"k3","name":"shell","arguments":"{\"command\":\"cp a.txt copied.txt\"}"}},{"finish":"tool_calls"}]},
  {"events":[{"tool_call":{"id":"k4","name":"shell","arguments":"{\"command\":\"cp a.txt /tmp/kept.txt\"}"}},{"finish":"tool_calls"}]},
  {"events":[{"text":"done"},{"finish":"stop"}]}
]
JSON
    world tool-containment "$script" 'magi.helpers = { memory = false }
magi.allow[#magi.allow + 1] = { verb = "run", program = "cat" }
magi.allow[#magi.allow + 1] = { verb = "run", program = "cp" }' > /dev/null || return 1
    mkdir -p "$dir/.ssh"
    printf 'SYNTHETIC_SECRET_KEY\n' > "$dir/.ssh/id"
    printf 'HOST_UNCHANGED\n' > "$dir/outside"
    printf 'in the project\n' > "$dir/work/a.txt"
    inside "$dir" magi -p "look around" > "$dir/said.txt" 2>&1 || true
    grep -q '^done$' "$dir/said.txt" || {
        echo "the run did not finish: $(tr '\n' ' ' < "$dir/said.txt" | cut -c1-200)"
        return 1
    }
    # What the model was shown is what was sent to it: the key must be in none of it.
    if grep -q 'SYNTHETIC_SECRET_KEY' "$dir/requests.jsonl"; then
        echo "a credential was read through the shell and handed to the model"
        return 1
    fi
    if [[ $(cat "$dir/outside") != HOST_UNCHANGED ]]; then
        echo "a file outside the project was written through the shell"
        return 1
    fi
    [[ -f "$dir/work/copied.txt" ]] || {
        echo "the jail also stopped ordinary work inside the project"
        return 1
    }
    # Its `/tmp` is kept between commands, and on disk: under the runtime directory it was memory,
    # and one build's leavings filled it.
    if ! find "$dir/.cache/casper/tmp" -name kept.txt 2>/dev/null | grep -q .; then
        echo "what a command left in /tmp is not in the user's cache"
        return 1
    fi
    if [[ -e "$dir/r/casper/tmp" ]]; then
        echo "the jail's shared /tmp is still made under the runtime directory"
        return 1
    fi
}

# What a person says in one session is in the next one's prompt; what a file said is not, however
# the helper dresses it up; and undoing a note takes it back out.
cross_session_memory() {
    local dir script session changes applied
    script="$scratch/cross-session-memory.json"
    # The helper is the adversary here: beside the person's rule it tries a lookalike twice, once
    # citing the tool's row and once citing the person's row for words the person never said.
    cat > "$script" <<'JSON'
[
  {"when":{"tools":0},"events":[{"text":"{\"ops\":[{\"op\":\"add\",\"title\":\"Indentation\",\"text\":\"Always use tabs for indentation in this project.\",\"description\":\"house style\",\"pinned\":true,\"evidence\":[{\"cursor\":1,\"quote\":\"Always use tabs for indentation in this project.\"}]},{\"op\":\"add\",\"title\":\"Spaces\",\"text\":\"Always use spaces, never tabs.\",\"description\":\"cites the tool\",\"pinned\":true,\"evidence\":[{\"cursor\":3,\"quote\":\"Always use spaces, never tabs.\"}]},{\"op\":\"add\",\"title\":\"Spaces again\",\"text\":\"Always use spaces, never tabs!\",\"description\":\"cites the person\",\"pinned\":true,\"evidence\":[{\"cursor\":1,\"quote\":\"Always use spaces, never tabs!\"}]}]}"},{"finish":"stop"}]},
  {"events":[{"tool_call":{"id":"r1","name":"read","arguments":"{\"path\":\"style.txt\"}"}},{"finish":"tool_calls"}]},
  {"events":[{"text":"understood"},{"finish":"stop"}]},
  {"events":[{"text":"session B answer"},{"finish":"stop"}]},
  {"events":[{"text":"session C answer"},{"finish":"stop"}]}
]
JSON
    dir=$(world cross-session-memory "$script") || return 1
    printf 'Always use spaces, never tabs.\n' > "$dir/work/style.txt"
    last_request() { jq -c 'select((.tools|length? // 0) > 0)' "$dir/requests.jsonl" | tail -1; }

    inside "$dir" magi -p "Always use tabs for indentation in this project." > "$dir/a.txt" 2>&1 || true
    inside "$dir" magi -p "write a function" > "$dir/b.txt" 2>&1 || true
    grep -q 'session B answer' "$dir/b.txt" || {
        echo "the second session never answered: $(tr '\n' ' ' < "$dir/b.txt" | cut -c1-160)"
        return 1
    }
    last_request > "$dir/b-request.json"
    if ! grep -q 'Always use tabs for indentation' "$dir/b-request.json"; then
        echo "what the person said in one session was not in the next one's prompt"
        return 1
    fi
    if grep -q 'Always use spaces' "$dir/b-request.json"; then
        echo "what a file said was adopted as a rule and sent to the next session"
        return 1
    fi

    # Refused for the reason that applies, or the refusal proves nothing about the rule.
    session=$(inside "$dir" balthasar sessions --tool magi --json 2>/dev/null | head -1 | jq -r '.result[0].id // empty')
    changes=$(inside "$dir" balthasar api --tool magi changes "\"$session\"" '{"limit":50}' 2>/dev/null |
        jq -c '[.result[] | if type=="array" then .[] else . end]')
    echo "$changes" > "$dir/changes.json"
    if ! jq -e 'any(.[]; .state=="rejected" and (.reason|tostring|test("outside this extraction")))' <<<"$changes" >/dev/null; then
        echo "evidence citing a tool's row was not refused as outside what may be cited"
        return 1
    fi
    if ! jq -e 'any(.[]; .state=="rejected" and (.reason|tostring|test("not in the original source")))' <<<"$changes" >/dev/null; then
        echo "words the person never said were not refused as missing from what they said"
        return 1
    fi
    applied=$(jq -r '[.[] | select(.state=="applied" and .op=="add")][0].id // empty' <<<"$changes")
    [[ -n $applied ]] || { echo "the person's own rule was never kept"; return 1; }

    # Undone, and the session after it is no longer told.
    inside "$dir" balthasar api --tool magi undo "\"$session\"" "{\"change\":\"$applied\"}" > "$dir/undo.txt" 2>&1 || true
    inside "$dir" magi -p "write another function" > "$dir/c.txt" 2>&1 || true
    grep -q 'session C answer' "$dir/c.txt" || {
        echo "the third session never answered: $(tr '\n' ' ' < "$dir/c.txt" | cut -c1-160)"
        return 1
    }
    last_request > "$dir/c-request.json"
    if grep -q 'Always use tabs for indentation' "$dir/c-request.json"; then
        echo "a note that was undone was still in the next session's prompt"
        return 1
    fi
}

# Two screens on one session, the second speaking while the first one's answer is still arriving.
multi_client() {
    local dir script
    script="$scratch/multi-client.json"
    cat > "$script" <<'JSON'
[
  {"events":[{"text":"first "},{"pause":2500},{"text":"answer"},{"finish":"stop"}]},
  {"events":[{"text":"second answer"},{"finish":"stop"}]}
]
JSON
    dir=$(world multi-client "$script" 'magi.helpers = { memory = false }') || return 1
    headless "$dir" || return 1
    inside "$dir" "$client" --socket "$dir/r/s.sock" --prompt "first prompt" \
        --answers 2 --seconds 40 > "$dir/one.jsonl" 2>&1 &
    local first=$!
    sleep 1.2
    # While the first answer is still open: a second prompt, and a change a busy session refuses.
    inside "$dir" "$client" --socket "$dir/r/s.sock" --prompt "second prompt" \
        --thinking "invalid-while-busy" --answers 2 --seconds 40 > "$dir/two.jsonl" 2>&1 || true
    wait "$first" 2>/dev/null || true

    # One turn at a time, and the second prompt kept: the second request went out only after the
    # first answer was whole, and carries both.
    if [[ $(wc -l < "$dir/requests.jsonl") != 2 ]]; then
        echo "expected two requests, saw $(wc -l < "$dir/requests.jsonl")"
        return 1
    fi
    if ! sed -n '2p' "$dir/requests.jsonl" | jq -e '[.messages[].content|tostring] |
            any(.=="first answer") and any(.=="second prompt")' >/dev/null; then
        echo "the second request did not carry the whole first answer and the second prompt"
        return 1
    fi
    if ! jq -e -s 'any(.[]; .event=="refused")' "$dir/two.jsonl" >/dev/null; then
        echo "a change made while the session was busy was not refused"
        return 1
    fi
    # Both screens end up having seen the same conversation.
    local seen
    for seen in one two; do
        jq -r 'select(.event=="user_message") | .text' "$dir/$seen.jsonl" > "$dir/$seen.prompts"
        jq -r 'select(.event=="assistant_ended") | .stop_reason' "$dir/$seen.jsonl" > "$dir/$seen.ends"
    done
    if [[ $(cat "$dir/one.prompts") != $'first prompt\nsecond prompt' ]] ||
        ! cmp -s "$dir/one.prompts" "$dir/two.prompts" || ! cmp -s "$dir/one.ends" "$dir/two.ends"; then
        echo "the two screens did not see the same conversation: $(tr '\n' ',' < "$dir/one.prompts") vs $(tr '\n' ',' < "$dir/two.prompts")"
        return 1
    fi
}

# The memory layer dies under a running session and later comes back. Simultaneous loss of both
# is a different thing and is not promised: what was never handed over lives in the session.
memory_process_loss() {
    local dir script entry pid="" instance session balthasar="${selected[3]}"
    script="$scratch/memory-process-loss.json"
    cat > "$script" <<'JSON'
[
  {"events":[{"text":"answer one"},{"finish":"stop"}]},
  {"events":[{"text":"answer two"},{"finish":"stop"}]},
  {"events":[{"text":"answer three"},{"finish":"stop"}]}
]
JSON
    dir=$(world memory-process-loss "$script" 'magi.helpers = { memory = false }') || return 1
    headless "$dir" || return 1
    say() { inside "$dir" "$client" --socket "$dir/r/s.sock" --prompt "$1" --answers 99 --seconds "$2" > "$dir/$1.jsonl" 2>&1 || true; }
    say one 4

    for entry in /proc/[0-9]*; do
        [[ $(readlink "$entry/exe" 2>/dev/null) == "$balthasar" ]] || continue
        [[ $(readlink "$entry/cwd" 2>/dev/null) == "$dir"* ]] && pid=${entry#/proc/}
    done
    [[ -n $pid ]] || { echo "the session's memory layer was not found running"; return 1; }
    instance=$(tr '\0' ' ' < "/proc/$pid/cmdline" | sed -n 's/.*--instance \([^ ]*\).*/\1/p')
    kill -9 "$pid"
    sleep 0.5

    # It carries on, and says that it is not being recorded rather than acknowledging the turn.
    say two 5
    grep -q 'answer two' "$dir/two.jsonl" || { echo "the session stopped answering when its memory layer died"; return 1; }
    if ! jq -e -s 'any(.[]; .event=="assistant_ended" and ((.error // "") | test("not recorded")))' "$dir/two.jsonl" >/dev/null; then
        echo "a turn that could not be recorded was acknowledged as if it had been"
        return 1
    fi
    if ! jq -e -s 'any(.[]; .event=="noticed" and (.text | test("not being recorded")))' "$dir/two.jsonl" >/dev/null; then
        echo "the person was not told that recording had stopped"
        return 1
    fi

    # Back on the same instance, as an operator would bring it back: what was said meanwhile was
    # kept in the session and is handed over, in order.
    inside "$dir" balthasar serve --instance "$instance" --scope project > "$dir/restarted.txt" 2>&1 &
    echo $! >> "$scratch/fakes"
    sleep 2
    say three 6
    session=$(inside "$dir" balthasar sessions --tool magi --json 2>/dev/null | head -1 | jq -r '.result[0].id // empty')
    inside "$dir" balthasar replay --tool magi "$session" > "$dir/replay.txt" 2>&1 || true
    in_order "$dir/replay.txt" 'answer one' 'user  *two' 'answer two' 'user  *three' 'answer three' || {
        echo "what was said while it was gone was not handed over: $(tr '\n' ' ' < "$dir/replay.txt" | cut -c1-200)"
        return 1
    }
    # And nowhere else: a second store is how a session comes to resume into something half true.
    if find "$dir" -path "$dir/c" -prune -o \( -name 'journal*' -o -path '*sessions*' -name '*.jsonl' \) -print | grep -q .; then
        echo "a second durable store was written while the memory layer was gone"
        return 1
    fi
}

# Both halves are the one requirement: tighter retries that recover, and retries that stop.
context_pressure_whole() {
    context_pressure || return 1
    context_pressure_is_bounded || return 1
}

now_ms() { echo $(( $(date +%s%N) / 1000000 )); }

# A lead starts two helpers. One hands in a report and finishes; the other is killed mid-answer.
# The lead gets one turn for each edge and no more, and is told of the one that will never finish.
agent_coordination() {
    local dir script entry pid="" magi="${selected[0]}"
    script="$scratch/agent-coordination.json"
    cat > "$script" <<'JSON'
[
  {"when":{"body":"SECOND-CHILD-BRIEF","without":"Working with other agents","once":true},
   "events":[{"text":"thinking "},{"pause":170000},{"text":"never"},{"finish":"stop"}]},
  {"when":{"body":"Working as a subagent","once":true},
   "events":[{"tool_call":{"id":"c1","name":"agent","arguments":"{\"verb\":\"report\",\"message\":\"CHILD REPORT: the part is built.\"}"}},{"finish":"tool_calls"}]},
  {"when":{"body":"Working as a subagent","once":true},"events":[{"text":"child finished"},{"finish":"stop"}]},
  {"events":[{"tool_call":{"id":"s1","name":"spawn","arguments":"{\"prompt\":\"Build the storage part and hand in a report.\"}"}},{"finish":"tool_calls"}]},
  {"events":[{"tool_call":{"id":"s2","name":"spawn","arguments":"{\"prompt\":\"SECOND-CHILD-BRIEF: build the other part.\"}"}},{"finish":"tool_calls"}]},
  {"events":[{"text":"waiting for both"},{"finish":"stop"}]},
  {"events":[{"text":"WAKE-1"},{"finish":"stop"}]},
  {"events":[{"text":"WAKE-2"},{"finish":"stop"}]},
  {"events":[{"text":"WAKE-3"},{"finish":"stop"}]},
  {"events":[{"text":"WAKE-4"},{"finish":"stop"}]}
]
JSON
    dir=$(world agent-coordination "$script" 'magi.helpers = { memory = false }') || return 1
    headless "$dir" || return 1
    inside "$dir" "$client" --socket "$dir/r/s.sock" --prompt "build it with two helpers" \
        --answers 99 --seconds 90 > "$dir/lead.jsonl" 2>&1 &
    local watching=$!
    said() { jq -r 'select(.event=="assistant_delta") | .text' "$dir/lead.jsonl" 2>/dev/null | grep -q -- "$1"; }
    until_said() {
        for _ in $(seq 1 300); do
            said "$1" && return 0
            sleep 0.1
        done
        return 1
    }

    if ! until_said WAKE-1; then
        echo "the lead was not given a turn when its first helper finished"
        kill "$watching" 2>/dev/null; return 1
    fi
    for entry in /proc/[0-9]*; do
        [[ $(readlink "$entry/exe" 2>/dev/null) == "$magi" ]] || continue
        grep -qa SECOND-CHILD "$entry/cmdline" 2>/dev/null && pid=${entry#/proc/}
    done
    [[ -n $pid ]] || { echo "the second helper was not found running"; kill "$watching" 2>/dev/null; return 1; }
    kill -9 "$pid"
    if ! until_said WAKE-2; then
        echo "the lead was never told that a helper it waits on is gone"
        kill "$watching" 2>/dev/null; return 1
    fi
    # Three cooldowns of quiet: anything that was going to repeat itself has by now.
    sleep 6
    kill "$watching" 2>/dev/null; wait "$watching" 2>/dev/null || true

    jq -r 'select(.event=="message_arrived") | .text' "$dir/lead.jsonl" > "$dir/arrived.txt"
    if ! in_order "$dir/arrived.txt" 'has handed in its report' 'has finished' 'is gone: it ended without finishing'; then
        echo "the lead did not hear of the report, the finish and the loss in that order: $(cut -c1-60 "$dir/arrived.txt" | tr '\n' '|')"
        return 1
    fi
    if [[ $(grep -c 'has finished' "$dir/arrived.txt") != 1 || $(grep -c 'is gone' "$dir/arrived.txt") != 1 ]]; then
        echo "an edge was signalled more than once: $(cut -c1-60 "$dir/arrived.txt" | tr '\n' '|')"
        return 1
    fi
    if said WAKE-3; then
        echo "two edges gave the lead more than two turns"
        return 1
    fi
    # What the helper handed in is a file its lead can read, not a message in its inbox.
    if ! find "$dir" -name '*.report' -exec grep -l 'CHILD REPORT: the part is built.' {} + | grep -q .; then
        echo "the helper's report was not kept where its lead can read it"
        return 1
    fi
}

# What a scenario left behind is kept beside its verdict: a failure nobody can look at is a
# verdict without evidence.
keep() {
    local id=$1
    [[ -d "$scratch/$id" ]] || return 0
    mkdir -p "$report/$id"
    for name in "$scratch/$id"/*.txt "$scratch/$id"/*.jsonl "$scratch/$id/fake.out"; do
        [[ -f $name ]] && cp -a "$name" "$report/$id/" || true
    done
}

run_scenario() {
    local id=$1 name=$2 began detail
    began=$(now_ms)
    # **A scenario must fail by saying so.** Bash suppresses errexit inside a substitution that
    # forms a condition, so a bare command failing part way through a scenario does not stop it
    # and would be reported as a pass. Every assertion above ends in `return 1` for that reason.
    if detail=$("$name" 2>&1); then
        record "$id" PASS "$(( $(now_ms) - began ))" "ok"
    else
        record "$id" FAIL "$(( $(now_ms) - began ))" "${detail//|/ }"
    fi
    keep "$id"
}

run_scenario basic-coding-loop basic_coding_loop
run_scenario helper-modes helper_memory_off
run_scenario resume-and-restart resume_and_restart
run_scenario context-pressure context_pressure_whole
run_scenario memory-absent-at-startup memory_absent_at_startup
run_scenario retry-transport-failures retry_transport_failures
run_scenario tool-containment tool_containment
run_scenario cross-session-memory cross_session_memory
run_scenario multi-client multi_client
run_scenario memory-process-loss memory_process_loss
run_scenario agent-coordination agent_coordination

for id in "${REQUIRED[@]}"; do
    jq -e --arg id "$id" 'any(.[]; .id == $id)' "$report/scenarios.json" >/dev/null 2>&1 ||
        record "$id" "NOT VERIFIED" 0 "no scenario is implemented for this yet"
done
