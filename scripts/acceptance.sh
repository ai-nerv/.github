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

# Both halves are the one requirement: tighter retries that recover, and retries that stop.
context_pressure_whole() {
    context_pressure || return 1
    context_pressure_is_bounded || return 1
}

now_ms() { echo $(( $(date +%s%N) / 1000000 )); }

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

for id in "${REQUIRED[@]}"; do
    jq -e --arg id "$id" 'any(.[]; .id == $id)' "$report/scenarios.json" >/dev/null 2>&1 ||
        record "$id" "NOT VERIFIED" 0 "no scenario is implemented for this yet"
done
