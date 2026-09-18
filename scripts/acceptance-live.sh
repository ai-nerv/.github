#!/usr/bin/env bash
# Live acceptance: the whole family against a real provider, through a proxy that meters it.
#
# Opt-in, and never part of `verify` or CI. It needs a provider and a model named on the command
# line, a finite cap, and a yes to sending the synthetic workload. The proxy is the only process
# that holds the key; it admits one model, reserves each request's worst case against a ledger
# that outlives the run, and records every outgoing request without its headers.
#
#   scripts/acceptance-live.sh --provider openrouter --model deepseek/deepseek-v4-flash-0731 \
#       --cap-usd 5 --send-synthetic yes
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
members=(magi casper melchior balthasar)
provider="" model="" cap_usd="" send="" key_env=OPENROUTER_API_KEY
while (( $# )); do
    case $1 in
        --provider) provider=$2 ;; --model) model=$2 ;; --cap-usd) cap_usd=$2 ;;
        --send-synthetic) send=$2 ;; --key-env) key_env=$2 ;;
        *) echo "unknown argument: $1" >&2; exit 2 ;;
    esac
    shift 2
done
[[ -z ${CI:-} ]] || { echo "acceptance-live never runs in CI" >&2; exit 2; }
[[ $provider == openrouter ]] || { echo "--provider openrouter is the one provider this lane knows" >&2; exit 2; }
[[ -n $model ]] || { echo "--model <provider's id> is required; none is assumed" >&2; exit 2; }
[[ $cap_usd =~ ^[0-9]+(\.[0-9]+)?$ ]] || { echo "--cap-usd <finite number> is required" >&2; exit 2; }
[[ $send == yes ]] || { echo "--send-synthetic yes is required: the workload is synthetic, and it is sent to a third party" >&2; exit 2; }
[[ -n ${!key_env:-} ]] || { echo "\$$key_env is not set; source the credentials in this shell" >&2; exit 2; }
for program in oslo jq curl timeout realpath sha256sum; do
    command -v "$program" >/dev/null || { echo "missing prerequisite: $program" >&2; exit 2; }
done
oslo=$(command -v oslo)
upstream=https://openrouter.ai/api/v1
cap_micros=$(jq -n --arg usd "$cap_usd" '$usd | tonumber * 1000000 | floor')

# The allowance is cumulative, so its ledger lives outside anything a clean would remove.
ledger_dir="${XDG_STATE_HOME:-$HOME/.local/state}/nerv/acceptance-live"
mkdir -p "$ledger_dir"
ledger="$ledger_dir/ledger.jsonl"
touch "$ledger"

mkdir -p "$root/target/acceptance-live"
report=$(mktemp -d "$root/target/acceptance-live/run-XXXXXXXX")
scratch=$(mktemp -d /tmp/nl.XXXXXX)
started=$(date -u +%FT%TZ)
printf '[]\n' > "$report/members.json"
printf '[]\n' > "$report/scenarios.json"
printf '{}\n' > "$report/measured.json"

spent_micros() {
    jq -s '(map(select(.kind=="settled")) | map(.micros) | add // 0) as $done
        | (map(select(.kind=="settled") | .id)) as $closed
        | $done + (map(select(.kind=="reserved" and (.id | IN($closed[]) | not)) | .micros) | add // 0)' "$1"
}

finish() {
    local status=$?
    trap - EXIT
    pkill -P $$ >/dev/null 2>&1 || true
    local entry cwd
    for entry in /proc/[0-9]*/cwd; do
        cwd=$(readlink "$entry" 2>/dev/null) || continue
        [[ $cwd == "$scratch"* ]] || continue
        entry=${entry#/proc/}
        kill "${entry%/cwd}" 2>/dev/null || true
    done
    if [[ -f "$scratch/pids" ]]; then
        while read -r pid; do kill "$pid" 2>/dev/null || true; done < "$scratch/pids"
    fi
    local failed missing recorded
    recorded=$(jq -r 'length' "$report/scenarios.json")
    failed=$(jq -r '[.[] | select(.verdict == "FAIL")] | length' "$report/scenarios.json")
    missing=$(jq -r '[.[] | select(.verdict == "NOT VERIFIED")] | length' "$report/scenarios.json")
    (( failed == 0 && missing == 0 && recorded > 0 )) || status=1
    jq -n --arg started "$started" --arg model "$model" --arg provider "$provider" \
        --arg root_commit "$(git -C "$root" rev-parse --verify HEAD 2>/dev/null || echo uncommitted)" \
        --arg root_dirty "$(git -C "$root" status --porcelain 2>/dev/null)" \
        --argjson exit_code "$status" --argjson not_verified "$missing" \
        --argjson cap "$cap_micros" --argjson spent "$(spent_micros "$ledger")" \
        --slurpfile members "$report/members.json" --slurpfile scenarios "$report/scenarios.json" \
        --slurpfile measured "$report/measured.json" \
        '{started:$started, kind:"live", provider:$provider, model:$model, exit_code:$exit_code,
          root:{commit:$root_commit, dirty:($root_dirty != "")},
          status:(if $exit_code == 0 then "PASS" else "FAIL" end), not_verified:$not_verified,
          spend:{cap_micros:$cap, cumulative_micros:$spent},
          members:$members[0], scenarios:$scenarios[0], measured:$measured[0]}' > "$report/summary.json"
    {
        echo "# Live acceptance $started"
        echo
        echo "- model: \`$provider/$model\`"
        echo "- status: $(jq -r .status "$report/summary.json"), not verified: $missing"
        echo "- cumulative spend: \$$(jq -r '.spend.cumulative_micros / 1000000' "$report/summary.json") of \$$cap_usd"
        echo
        echo "| scenario | verdict | ms | detail |"
        echo "|---|---|---|---|"
        jq -r '.[] | "| \(.id) | \(.verdict) | \(.ms) | \(.detail) |"' "$report/scenarios.json"
    } > "$report/summary.md"
    printf 'acceptance-live: exit %s; evidence: %s\n' "$status" "$report"
    rm -rf -- "$scratch"
    exit "$status"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

# ---- the exact family, and the three tools of this lane ----------------------------------------
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
family_path=""
for binary in "${selected[@]}"; do family_path+="$(dirname "$binary"):"; done
(cd "$root/melchior" && cargo build --example fake-provider --example metered-proxy) > "$report/tools-build.log" 2>&1
(cd "$root/magi" && cargo build -p magi-testkit --example session-client) > "$report/client-build.log" 2>&1
fake="$root/melchior/target/debug/examples/fake-provider"
proxy="$root/melchior/target/debug/examples/metered-proxy"
client="$root/magi/target/debug/examples/session-client"

now_ms() { echo $(( $(date +%s%N) / 1000000 )); }
record() {
    jq --arg id "$1" --arg verdict "$2" --arg ms "$3" --arg detail "$4" \
        '. + [{id:$id, verdict:$verdict, ms:($ms|tonumber), detail:$detail}]' \
        "$report/scenarios.json" > "$report/next.json"
    mv "$report/next.json" "$report/scenarios.json"
}
measure() {
    jq --arg key "$1" --argjson value "$2" '.[$key] = $value' "$report/measured.json" > "$report/next.json"
    mv "$report/next.json" "$report/measured.json"
}
# A scenario fails by `return 1`, passes by `return 0`, and says it could not be measured here by
# `return 3`: that is NOT VERIFIED, which is neither.
run_scenario() {
    local id=$1 name=$2 began detail verdict
    began=$(now_ms)
    if detail=$("$name" 2>&1); then verdict=PASS; else
        [[ $? == 3 ]] && verdict="NOT VERIFIED" || verdict=FAIL
    fi
    [[ $verdict != PASS ]] || detail=${detail:-ok}
    record "$id" "$verdict" "$(( $(now_ms) - began ))" "$(tr '\n|' '  ' <<<"$detail" | cut -c1-400)"
}
port_of() {
    local out=$1 port=""
    for _ in $(seq 1 200); do
        port=$(sed -n 's/^PORT=//p' "$out" || true)
        [[ -n $port ]] && { echo "$port"; return 0; }
        sleep 0.05
    done
    return 1
}
# A proxy of this lane: where it sends, its ledger, its cap. Prints its port.
metered() {
    local name=$1 to=$2 book=$3 cap=$4
    "$proxy" --upstream "$to" --model "$model" --key-env "$key_env" --ledger "$book" \
        --record "$scratch/$name.requests.jsonl" --cap-micros "$cap" \
        --input-price "$input_price" --output-price "$output_price" --output-bound 8192 \
        > "$scratch/$name.proxy.out" 2>&1 &
    echo $! >> "$scratch/pids"
    port_of "$scratch/$name.proxy.out"
}
ask() {
    curl -s -o "$2" -w '%{http_code}' "http://127.0.0.1:$1/chat/completions" \
        -H 'Content-Type: application/json' -d "$3"
}

# ---- what the model costs today, from the provider, not from memory ---------------------------
card=$(curl -s "$upstream/models" | jq --arg id "$model" '.data[] | select(.id == $id)')
[[ -n $card ]] || { echo "the provider does not list \`$model\`; nothing is substituted" >&2; exit 2; }
input_price=$(jq -r '.pricing.prompt | tonumber * 1e12 | ceil' <<<"$card")
output_price=$(jq -r '.pricing.completion | tonumber * 1e12 | ceil' <<<"$card")
window=$(jq -r '.context_length' <<<"$card")
measure card "$(jq '{id, context_length, pricing, max_completion_tokens:.top_provider.max_completion_tokens}' <<<"$card")"

# ---- the meter itself, against the fake: no request leaves the machine -------------------------
metering() {
    local script="$scratch/meter.json" book="$scratch/meter.ledger" fport port code
    cat > "$script" <<'JSON'
[
  {"when":{"body":"SLOW","once":true},"events":[{"text":"slow "},{"pause":1500},{"text":"done"},{"finish":"stop"},{"usage":{"input":40,"output":10}}]},
  {"when":{"body":"hello"},"events":[{"text":"hi"},{"finish":"stop"},{"usage":{"input":40,"output":10}}]}
]
JSON
    "$fake" --script "$script" --port 0 > "$scratch/meter.fake.out" 2>&1 &
    echo $! >> "$scratch/pids"
    fport=$(port_of "$scratch/meter.fake.out") || { echo "the fake never started"; return 1; }
    touch "$book"
    local body="{\"model\":\"$model\",\"max_tokens\":100,\"messages\":[{\"role\":\"user\",\"content\":\"hello\"}]}"
    local one; one=$(( (${#body} * input_price + 100 * output_price + 999999) / 1000000 ))

    # Another model is refused before anything is reserved.
    port=$(metered meter-a "http://127.0.0.1:$fport/v1" "$book" 1000000) || return 1
    code=$(ask "$port" "$scratch/meter.other" '{"model":"somebody/else","messages":[]}')
    [[ $code == 403 && ! -s $book ]] || { echo "another model was not refused cleanly: $code"; return 1; }
    code=$(ask "$port" "$scratch/meter.ok" "$body")
    [[ $code == 200 ]] || { echo "an affordable request was refused: $code"; return 1; }
    local after; after=$(spent_micros "$book")
    (( after > 0 && after <= one )) || { echo "a settled request was charged $after, reserved $one"; return 1; }

    # A cap with room for one reservation: while one is in flight, a second is refused, and the
    # refusal reserves nothing. The same ledger under a new proxy is not a new allowance.
    local slow=${body/hello/hello SLOW}
    local tight=$(( after + one + 1 ))
    port=$(metered meter-b "http://127.0.0.1:$fport/v1" "$book" "$tight") || return 1
    ask "$port" "$scratch/meter.slow" "$slow" > "$scratch/meter.slow.code" &
    local waiting=$!
    sleep 0.5
    code=$(ask "$port" "$scratch/meter.second" "$body")
    wait "$waiting"
    [[ $code == 402 ]] || { echo "a request past the cap while another was in flight got $code"; return 1; }
    [[ $(cat "$scratch/meter.slow.code") == 200 ]] || { echo "the request in flight was cut off"; return 1; }
    port=$(metered meter-c "http://127.0.0.1:$fport/v1" "$book" "$after") || return 1
    code=$(ask "$port" "$scratch/meter.rerun" "$body")
    [[ $code == 402 ]] || { echo "a rerun was given a fresh allowance: $code"; return 1; }
    cp "$book" "$report/metering-ledger.jsonl"
    echo "403 other model; 402 past the cap in flight; 402 on rerun; one request cost $after of $one reserved"
}

# ---- a scratch world whose only provider is the proxy ------------------------------------------
world() {
    local id=$1 extra=${2:-} dir="$scratch/$1" port
    mkdir -p "$dir"/{c/melchior,d,s,r,t,work}
    chmod 700 "$dir/r"
    for member in magi casper balthasar; do
        [[ -d "$root/$member/config" ]] && cp -r "$root/$member/config" "$dir/c/$member"
    done
    cp "$root/melchior/config/apis.lua" "$dir/c/melchior/"
    port=$(metered "$id" "$upstream" "$ledger" "$cap_micros") || return 1
    cat > "$dir/c/melchior/providers.lua" <<LUA
melchior.provider("openrouter", {
  name = "OpenRouter (metered)", api = "openai-completions",
  base_url = "http://127.0.0.1:$port", auth = { kind = "none" },
  compat = { supports_reasoning_effort = true, thinking_format = "openrouter" },
  models = { { id = "$model", name = "live", context_window = $window, max_tokens = 8192 } },
})
LUA
    {
        printf '\nmagi.model = "openrouter/%s"\n' "$model"
        printf 'magi.allow[#magi.allow + 1] = { verb = "read", directory = "%s/work" }\n' "$dir"
        printf 'magi.allow[#magi.allow + 1] = { verb = "write", directory = "%s/work" }\n' "$dir"
        for program in ls cat grep wc head tail sed sort find; do
            printf 'magi.allow[#magi.allow + 1] = { verb = "run", program = "%s" }\n' "$program"
        done
        [[ -z $extra ]] || printf '%s\n' "$extra"
    } >> "$dir/c/magi/init.lua"
    echo "$dir"
}
inside() {
    local dir=$1; shift
    (cd "$dir/work" && env -i PATH="$family_path/usr/bin:/bin" HOME="$dir" \
        XDG_CONFIG_HOME="$dir/c" XDG_DATA_HOME="$dir/d" XDG_STATE_HOME="$dir/s" \
        XDG_RUNTIME_DIR="$dir/r" TMPDIR="$dir/t" timeout 900 "$@")
}
headless() {
    local dir=$1
    inside "$dir" magi --headless --socket "$dir/r/s.sock" > "$dir/host.out" 2>&1 &
    echo $! >> "$scratch/pids"
    for _ in $(seq 1 200); do
        [[ -S "$dir/r/s.sock" ]] && return 0
        sleep 0.05
    done
    echo "the headless session never opened its socket" >&2
    return 1
}

# A synthetic project: nothing in it came from a repository.
synthetic() {
    local work=$1 n
    for n in 1 2 3 4 5 6; do
        {
            echo "// module $n of a synthetic inventory service"
            for line in $(seq 1 120); do
                echo "pub fn item_${n}_${line}(stock: u32) -> u32 { stock.saturating_add($(( n * 1000 + line ))) }"
            done
            echo "pub const LIMIT_$n: u32 = $(( n * 7919 ));"
        } > "$work/mod$n.rs"
    done
}

# One long tool-heavy session. The three scenarios below read what it left behind.
long_session() {
    local dir n
    dir=$(world long 'magi.helpers = { memory = false }') || return 1
    synthetic "$dir/work"
    headless "$dir" || return 1
    for n in 1 2 3 4 5 6 1 2 3 4; do
        inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end yes --answers 1 --seconds 240 \
            --prompt "Read mod$n.rs with the read tool and tell me the value of LIMIT_$n and nothing else." \
            >> "$dir/session.jsonl" 2>&1 || true
    done
    mkdir -p "$report/long"
    cp "$dir/session.jsonl" "$scratch/long.requests.jsonl" "$report/long/" 2>/dev/null || true
    echo "$dir"
}

estimates() {
    local rows="$report/long/estimates.json"
    # Each layout is followed by the answer it was laid out for; the estimate is the one made
    # before the request, against what the provider then said the prompt was.
    jq -s 'reduce .[] as $e ({est:null, rows:[]};
            if $e.event == "context_laid" then .est = $e.budget.estimated_input
            elif $e.event == "assistant_ended" and .est != null
                 and (($e.usage.input + $e.usage.cache_read + $e.usage.cache_write) > 0) then
                (($e.usage.input + $e.usage.cache_read + $e.usage.cache_write)) as $real
                | .rows += [{estimated:.est, reported:$real,
                             error:((.est - $real) | fabs / $real)}] | .est = null
            else . end) | .rows' "$report/long/session.jsonl" > "$rows"
    local count worst
    count=$(jq 'length' "$rows")
    (( count > 3 )) || { echo "only $count requests reported usage; three calibrate and the rest are measured"; return 3; }
    worst=$(jq '.[3:] | map(.error) | max' "$rows")
    measure token_estimates "$(jq '{requests:., calibration:3, worst_error_after_calibration:(.[3:] | map(.error) | max)}' "$rows")"
    if jq -e '.[3:] | map(.error) | max <= 0.10' "$rows" >/dev/null; then
        echo "worst error after three calibration requests: $worst over $(( count - 3 )) measured"
    else
        echo "worst error after calibration is $worst, over the 10% target ($count requests)"
        return 1
    fi
}

caching() {
    local rows="$report/long/usage.json"
    jq -s '[.[] | select(.event == "assistant_ended") | .usage
            | select((.input + .cache_read + .cache_write) > 0)]' "$report/long/session.jsonl" > "$rows"
    local count; count=$(jq 'length' "$rows")
    (( count > 3 )) || { echo "only $count requests reported usage"; return 3; }
    if jq -e '.[3:] | map(.cache_read) | add == 0' "$rows" >/dev/null; then
        echo "the provider reported no cache reads at all on this model; unsupported is not 0%"
        return 3
    fi
    # What the family controls is the prefix: each request should extend the one before it byte
    # for byte. Whether the provider then serves it from cache is the provider's.
    local stable misses
    stable=$(jq -s '[.[] | select((.request.tools // []) | length > 0) | .request.messages] as $m
        | [range(1; $m | length) | ($m[.][0:($m[. - 1] | length)] == $m[. - 1])]
        | {extended:(map(select(.)) | length), of:length}' "$report/long/long.requests.jsonl")
    misses=$(jq '.[3:] | map(select(.cache_read == 0)) | length' "$rows")
    local ratio
    ratio=$(jq '.[3:] | (map(.cache_read) | add) / (map(.input + .cache_read + .cache_write) | add)' "$rows")
    measure prompt_caching "$(jq --argjson ratio "$ratio" --argjson stable "$stable" --argjson misses "$misses" '{prefix:$stable, requests_with_no_cache_read_after_warm_up:$misses, warm_up_requests:3, denominator:"input + cache_read + cache_write, after warm-up", ratio:$ratio, requests:.}' "$rows")"
    if jq -n -e --argjson r "$ratio" '$r > 0.80' >/dev/null; then
        echo "cache-read ratio after a three-request warm-up: $ratio; $(jq -r '"\(.extended) of \(.of)"' <<<"$stable") requests extended the previous prefix"
    else
        echo "cache-read ratio after warm-up is $ratio, under the 80% target; $(jq -r '"\(.extended) of \(.of)"' <<<"$stable") requests extended the previous prefix byte for byte, and $misses were served with no cache read at all"
        return 1
    fi
}

cost_and_latency() {
    local file="$report/long/long.requests.jsonl"
    [[ -s $file ]] || { echo "the proxy recorded nothing"; return 1; }
    local table
    table=$(jq -s 'group_by(if (.request.tools // [] | length) == 0 then "helper" else "main" end)
        | map({who:(if (.[0].request.tools // [] | length) == 0 then "helper" else "main" end),
               requests:length, failed:(map(select(.outcome.status != 200)) | length),
               input:(map(.outcome.usage.prompt_tokens // 0) | add),
               cached:(map(.outcome.usage.prompt_tokens_details.cached_tokens // 0) | add),
               output:(map(.outcome.usage.completion_tokens // 0) | add),
               micros:(map(.outcome.micros) | add),
               ms_median:(map(.outcome.ms) | sort | .[length / 2 | floor]),
               ms_max:(map(.outcome.ms) | max)})' "$file")
    measure cost_and_latency "$table"
    measure spend_cap_accounting '"each request reserves (request bytes as tokens x input price + max_tokens x output price) under a lock on the ledger before it leaves; a request in flight counts at its reservation until settled at the provider-reported cost; a reservation never settled stays counted"'
    echo "$(jq -c 'map({who, requests, micros, ms_median})' <<<"$table")"
}

run_scenario metering metering
if jq -e 'any(.[]; .id == "metering" and .verdict == "PASS")' "$report/scenarios.json" >/dev/null; then
    long_session > "$scratch/long.dir" 2> "$report/long-session.log" || true
    run_scenario token-estimates estimates
    run_scenario prompt-caching caching
    run_scenario cost-and-latency cost_and_latency
else
    echo "acceptance-live: the meter did not pass its own test; nothing was sent" >&2
fi
record window-handling "NOT VERIFIED" 0 "one model is authorized (window $window); a small- and large-window comparison needs a second, and none is substituted"
for id in retained-context cross-session-learning control-arm; do
    record "$id" "NOT VERIFIED" 0 "no live scenario is implemented for this yet"
done
