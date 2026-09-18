#!/usr/bin/env bash
# Live acceptance: the whole family against a real provider, through a proxy that meters it.
#
# Opt-in, and never part of `verify` or CI. It needs a provider and a model named on the command
# line, a finite cap, and a yes to sending the synthetic workload. The proxy is the only process
# that holds the key; it admits one model, reserves each request's worst case against a ledger
# that outlives the run, and records every outgoing request without its headers.
#
#   NERV_LIVE_MODEL=deepseek/deepseek-v4-flash-0731 NERV_LIVE_CAP_USD=5 NERV_LIVE_SEND=yes \
#       oslo make acceptance-live      (NERV_LIVE_ONLY=learning runs that part alone)
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
members=(magi casper melchior balthasar)
provider="" model="" small_model="" cap_usd="" send="" key_env=OPENROUTER_API_KEY
while (( $# )); do
    case $1 in
        --provider) provider=$2 ;; --model) model=$2 ;; --cap-usd) cap_usd=$2 ;;
        --send-synthetic) send=$2 ;; --key-env) key_env=$2 ;; --small-model) small_model=$2 ;;
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

# The ledger as the proxy adds it up: settled, plus reserved and never settled, with a
# `corrected` line replacing what its request was last settled at.
spent_micros() {
    jq -s 'reduce .[] as $r ({open:{}, last:{}, total:0};
        if $r.kind == "reserved" then .open[$r.id] = $r.micros
        elif $r.kind == "settled" then del(.open[$r.id]) | .total += $r.micros | .last[$r.id] = $r.micros
        elif $r.kind == "corrected" then .total += $r.micros - (.last[$r.id] // 0) | .last[$r.id] = $r.micros
        else . end) | .total + ([.open[]] | add // 0)' "$1"
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
# The second model is for window handling alone, and as much the caller's choice as the first.
small_card=""
if [[ -n $small_model ]]; then
    small_card=$(curl -s "$upstream/models" | jq --arg id "$small_model" '.data[] | select(.id == $id)')
    [[ -n $small_card ]] || { echo "the provider does not list \`$small_model\`; nothing is substituted" >&2; exit 2; }
    measure small_card "$(jq '{id, context_length, pricing, max_completion_tokens:.top_provider.max_completion_tokens}' <<<"$small_card")"
fi

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
    local id=$1 extra=${2:-} memory=${3:-} advertised=${4:-$window} dir="$scratch/$1" port
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
  models = { { id = "$model", name = "live", context_window = $advertised, max_tokens = 8192 } },
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
    [[ -z $memory ]] || printf '\n%s\n' "$memory" >> "$dir/c/balthasar/init.lua"
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
    for n in 1 2 3 4 5 6 7 8 9 10 11 12; do
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
    local file="$report/all-requests.jsonl" each
    for each in "$scratch"/*.requests.jsonl; do
        [[ $(basename "$each") == meter-* ]] || cat "$each"
    done > "$file"
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

# ---- what survives pressure, and what memory carries between sessions -------------------------
say() {
    local dir=$1 text=$2
    inside "$dir" "$client" --socket "$dir/r/s.sock" --from-end yes --answers 1 --seconds 300 \
        --prompt "$text" >> "$dir/session.jsonl" 2>&1 || true
}
last_answer() {
    jq -rs '[.[] | select(.event == "assistant_delta")] as $d
        | ([.[] | select(.event == "assistant_started")] | last | .id) as $id
        | [$d[] | select(.id == $id) | .text] | join("")' "$1"
}
# The proxy writes a request down after its answer has gone, so the session that asked can be
# over first: read only once every line of the record is whole.
whole() {
    for _ in $(seq 1 50); do
        jq -e . "$1" >/dev/null 2>&1 && return 0
        sleep 0.1
    done
    return 1
}
main_requests() { whole "$1" || true; jq -c 'select((.request.tools // []) | length > 0) | .request' "$1"; }

# The manifest: a fact said early, a call that failed, a recent instruction, and a value only a
# file holds. One session is squeezed into a small advertised window with helpers on; the other
# carries the same history whole with extraction off. Same prompts, same model, same settings.
MANIFEST_PROMPTS=(
    "The deploy token for this project is named HARBOR-7719. Keep it in mind; I will ask for it much later."
    "Read missing.rs with the read tool and tell me in one line what happened."
    "Read mod1.rs with the read tool and tell me only the value of LIMIT_1."
    "Read mod2.rs with the read tool and tell me only the value of LIMIT_2."
    "Read mod3.rs with the read tool and tell me only the value of LIMIT_3."
    "Read mod4.rs with the read tool and tell me only the value of LIMIT_4."
    "Read mod5.rs with the read tool and tell me only the value of LIMIT_5."
    "From now on, end every answer with the word OVER on a line of its own."
    "Three things: the name of the deploy token, the name of the file that could not be read, and the value of LIMIT_2. Look anything up again if you need to."
)
manifest_session() {
    local id=$1 extra=$2 advertised=$3 dir prompt
    dir=$(world "$id" "$extra" "" "$advertised") || return 1
    synthetic "$dir/work"
    headless "$dir" || return 1
    for prompt in "${MANIFEST_PROMPTS[@]}"; do say "$dir" "$prompt"; done
    mkdir -p "$report/$id"
    cp "$dir/session.jsonl" "$report/$id/"
    cp "$scratch/$id.requests.jsonl" "$report/$id/requests.jsonl"
    last_answer "$dir/session.jsonl" > "$report/$id/final.txt"
}
# What the last answer got right, out of four.
scored() {
    local file=$1 got=0
    grep -q 'HARBOR-7719' "$file" && got=$(( got + 1 ))
    grep -q 'missing\.rs' "$file" && got=$(( got + 1 ))
    grep -q '15838' "$file" && got=$(( got + 1 ))
    [[ $(grep -v '^[[:space:]]*$' "$file" | tail -1 | tr -d '[:space:]') == OVER ]] && got=$(( got + 1 ))
    echo "$got"
}

retained_context() {
    manifest_session retained '' 20000 || { echo "the squeezed session could not be run"; return 1; }
    local at="$report/retained" pressed orphans last got
    pressed=$(jq -s '[.[] | select(.event == "context_laid") | .counts | (.stubs + .dropped + .summary)] | max // 0' "$at/session.jsonl")
    (( pressed > 0 )) || { echo "the 20k window was never under pressure, so nothing was retained against anything"; return 3; }
    # In every request that went out: each call has its result and each result its call.
    orphans=$(main_requests "$at/requests.jsonl" | jq -s '[.[] | ([.messages[] | .tool_calls // [] | .[].id]) as $calls
        | ([.messages[] | select(.role == "tool") | .tool_call_id]) as $results
        | (($calls - $results) + ($results - $calls)) | length] | add // 0')
    (( orphans == 0 )) || { echo "$orphans tool calls or results went out without their other half"; return 1; }
    last=$(main_requests "$at/requests.jsonl" | tail -1)
    grep -q 'end every answer with the word OVER' <<<"$last" || { echo "the recent instruction was not in the last request word for word"; return 1; }
    grep -q 'HARBOR-7719' <<<"$last" || { echo "the early fact was in no part of the last request"; return 1; }
    grep -q 'missing\.rs' <<<"$last" || { echo "the failed call was in no part of the last request"; return 1; }
    got=$(scored "$at/final.txt")
    measure retained_context "$(jq -n --argjson pressed "$pressed" --argjson got "$got" --rawfile final "$at/final.txt" \
        '{advertised_window:20000, most_slots_reduced_in_one_layout:$pressed, orphaned_calls:0, outcome_of_4:$got, final_answer:$final}')"
    (( got == 4 )) || { echo "the last answer got $got of 4 (token, failed file, LIMIT_2, the OVER instruction): $(tr '\n' ' ' < "$at/final.txt" | cut -c1-200)"; return 1; }
    echo "under pressure ($pressed slots reduced at most), pairs intact, fact, failure and instruction sent; outcome 4 of 4"
}

control_arm() {
    [[ -s "$report/retained/final.txt" ]] || { echo "there is no squeezed session to compare with"; return 3; }
    manifest_session control 'magi.helpers = { memory = false }' "$window" || { echo "the control session could not be run"; return 1; }
    local arm cost tokens table='[]'
    for arm in retained control; do
        cost=$(jq -s 'map(.outcome.micros) | add' "$report/$arm/requests.jsonl")
        tokens=$(jq -s 'map(.outcome.usage.prompt_tokens // 0) | add' "$report/$arm/requests.jsonl")
        table=$(jq --arg arm "$arm" --argjson got "$(scored "$report/$arm/final.txt")" --argjson cost "$cost" --argjson tokens "$tokens" \
            --argjson requests "$(wc -l < "$report/$arm/requests.jsonl")" \
            '. + [{arm:$arm, outcome_of_4:$got, requests:$requests, prompt_tokens:$tokens, micros:$cost}]' <<<"$table")
    done
    measure control_arm "$table"
    # Measured, not won: a tie or a loss is reported as what it is, and only a worse outcome fails.
    local ours theirs
    ours=$(jq '.[0].outcome_of_4' <<<"$table"); theirs=$(jq '.[1].outcome_of_4' <<<"$table")
    if (( ours < theirs )); then
        echo "the squeezed session scored $ours of 4 where the whole history scored $theirs: $(jq -c . <<<"$table")"
        return 1
    fi
    echo "$(jq -c 'map({arm, outcome_of_4, prompt_tokens, micros})' <<<"$table")"
}

RULE="Always start every function name in this project with the prefix zq_."
# The same rule as a person might put it, without an opening word the notes recognise a rule by.
PLAIN="In this project every function name must start with the prefix zq_ and that is a standing rule for all future work."
TASK="Write a Rust function that adds two i32 values. Reply with only the code."
changes_of() {
    local dir=$1 session
    session=$(inside "$dir" balthasar sessions --tool magi --json 2>/dev/null | head -1 | jq -r '.result[0].id // empty')
    echo "$session" > "$dir/session.id"
    inside "$dir" balthasar api --tool magi changes "\"$session\"" '{"limit":50}' 2>/dev/null |
        jq -c '[.result[] | if type=="array" then .[] else . end]'
}
# One prompt in a session of its own; what was sent for it and what came back.
session_of() {
    local dir=$1 name=$2 text=$3
    inside "$dir" magi -p "$text" > "$dir/$name.txt" 2>&1 || true
    # The last request is written down a moment after its answer ends, which is when this returns.
    sleep 0.5
    main_requests "$scratch/$(basename "$dir").requests.jsonl" | tail -1 > "$dir/$name.request.json"
}
told() { grep -qF "${RULE%.}" "$1/$2.request.json"; }
mentioned() { grep -q 'zq_' "$1/$2.request.json"; }

cross_session_learning() {
    local dir changes applied staged sid rows='[]' note attempt retried=0
    add_row() { rows=$(jq --arg step "$1" --argjson told "$2" --argjson obeyed "$3" '. + [{step:$step, rule_in_prompt:$told, answer_uses_prefix:$obeyed}]' <<<"$rows"); }
    flag() { if "$@"; then echo true; else echo false; fi; }

    # Review off: said in A, never repeated, in B's prompt as a note and in what B writes.
    dir=$(world learn) || return 1
    session_of "$dir" a "$RULE"
    session_of "$dir" b "$TASK"
    add_row "B after A" "$(flag told "$dir" b)" "$(flag grep -q 'fn zq_' "$dir/b.txt")"
    changes=$(changes_of "$dir"); echo "$changes" > "$report/learn-changes.json"
    told "$dir" b || { echo "what was said in A was not in B's prompt; the changes were $(jq -c 'map([.state, .reason])' <<<"$changes")"; return 1; }
    # Attributable: it arrives as a note, and the change that made it cites the person's own words.
    applied=$(jq -r '[.[] | select(.state=="applied" and .op=="add" and (tostring | test("zq_")))][0].id // empty' <<<"$changes")
    [[ -n $applied ]] || { echo "no applied change carries the rule, so its place in B's prompt is not attributable"; return 1; }
    grep -q 'fn zq_' "$dir/b.txt" || { echo "B was told the rule and did not follow it: $(tr '\n' ' ' < "$dir/b.txt" | cut -c1-160)"; return 1; }
    sid=$(cat "$dir/session.id")
    inside "$dir" balthasar api --tool magi undo "\"$sid\"" "{\"change\":\"$applied\"}" > "$dir/undo.txt" 2>&1 || true
    session_of "$dir" c "$TASK"
    add_row "C after undo" "$(flag told "$dir" c)" "$(flag grep -q 'fn zq_' "$dir/c.txt")"
    if told "$dir" c; then echo "a note that was undone was still in the next session's prompt"; return 1; fi
    # Nor by any other road: what the session itself tried to keep of the rule is not a way back.
    if mentioned "$dir" c; then echo "after the undo the rule still reached the next session, by a road the undo does not cover: $(grep -o '[^"]\{0,80\}zq_[^"]\{0,60\}' "$dir/c.request.json" | head -1)"; return 1; fi

    # The same rule as a person would put it, with no opening word that marks a rule: kept as one.
    dir=$(world learn-plain) || return 1
    session_of "$dir" a "$PLAIN"
    session_of "$dir" b "$TASK"
    changes=$(changes_of "$dir"); echo "$changes" > "$report/learn-plain-changes.json"
    add_row "B after A, plainly worded" "$(flag mentioned "$dir" b)" "$(flag grep -q 'fn zq_' "$dir/b.txt")"
    measure plainly_worded_rule "$(jq -c 'map({op, state, reason})' <<<"$changes")"
    if ! grep -qF "${PLAIN%.}" "$dir/b.request.json"; then
        echo "a rule said in plain words was not in the next session's prompt: $(jq -c 'map([.state, .reason])' <<<"$changes")"
        return 1
    fi

    # Review on: a change waits. Rejected, it never reaches a prompt; approved, it does.
    # The reviewer is the main model, in the same run; a helper budget the extraction alone spends
    # leaves the change staged, so that the decision made here is one a person made.
    for note in reject approve; do
        # A live helper sometimes proposes nothing at all. That is no verdict on review, so the
        # arm is given one more fresh world, and the report says that it was.
        for attempt in 1 2; do
            dir=$(world "learn-$note-$attempt" 'magi.helpers = { budget = { per_prompt = 0.000001 } }' 'balthasar.memory = { review = true }') || return 1
            session_of "$dir" a "$RULE"
            changes=$(changes_of "$dir"); echo "$changes" > "$report/learn-$note-changes.json"
            [[ $(jq 'length' <<<"$changes") == 0 ]] || break
            retried=$(( retried + 1 ))
        done
        sid=$(cat "$dir/session.id")
        staged=$(jq -c '[.[] | select(.state=="staged") | .id]' <<<"$changes")
        if [[ $(jq 'length' <<<"$staged") == 0 ]]; then
            echo "with review on nothing was left staged to $note (states: $(jq -c 'map(.state)' <<<"$changes")); the model's own review had already decided"
            measure cross_session_learning "$(jq --argjson retried "$retried" '{arms:., review_arms_retried_for_an_empty_extraction:$retried}' <<<"$rows")"
            return 3
        fi
        inside "$dir" balthasar api --tool magi "$note" "\"$sid\"" "{\"changes\":$staged}" > "$dir/$note.txt" 2>&1 || true
        session_of "$dir" b "$TASK"
        add_row "B after $note" "$(flag told "$dir" b)" "$(flag grep -q 'fn zq_' "$dir/b.txt")"
        if [[ $note == reject ]] && mentioned "$dir" b; then echo "after the rejection the rule still reached the next session: $(grep -o '[^"]\{0,80\}zq_[^"]\{0,60\}' "$dir/b.request.json" | head -1)"; return 1; fi
        if [[ $note == reject ]] && told "$dir" b; then echo "a rejected change was in the next session's prompt"; return 1; fi
        if [[ $note == approve ]] && ! told "$dir" b; then echo "an approved change was not in the next session's prompt"; return 1; fi
    done
    measure cross_session_learning "$(jq --argjson retried "$retried" '{arms:., review_arms_retried_for_an_empty_extraction:$retried}' <<<"$rows")"
    echo "$(jq -c 'map([.step, .rule_in_prompt, .answer_uses_prefix])' <<<"$rows")"
}

# ---- a small real window and a large one ------------------------------------------------------
# How many times in a row the provider may refuse one prompt before the session has to have
# recovered: the first refusal and three tighter layouts, as the deterministic lane holds it to.
RETRY_BOUND=4

# A session of reads on the model and window the caller's locals name. Leaves its evidence in
# the report under `id`.
reading_session() {
    local id=$1 advertised=$2 reads=$3 dir n=0
    dir=$(world "$id" 'magi.helpers = { memory = false }' '' "$advertised") || return 1
    synthetic "$dir/work"
    headless "$dir" || return 1
    while (( n < reads )); do
        n=$(( n + 1 ))
        say "$dir" "Read mod$n.rs with the read tool and tell me only the value of LIMIT_$n."
    done
    mkdir -p "$report/$id"
    cp "$dir/session.jsonl" "$report/$id/"
    cp "$scratch/$id.requests.jsonl" "$report/$id/requests.jsonl"
    last_answer "$dir/session.jsonl" > "$report/$id/final.txt"
}
# What one session's layouts and requests say about its window. A refusal for length is told from
# an upstream that merely failed, which is the provider's trouble and not the window's; and it is
# looked for inside a stream answered 200 as well, which is where a router puts its upstream's.
LENGTH='length|too long|too many tokens|context|exceeds'
windowed() {
    local id=$1
    jq -s --arg id "$id" --arg length "$LENGTH" --slurpfile sent "$report/$id/requests.jsonl" \
        '[.[] | select(.event == "context_laid")] as $laid
        | [$sent[] | select(.outcome.status != 200 or .outcome.error != null)] as $failed
        | {session:$id, advertised_window:($laid[0].budget.window), reply_reserved:($laid[0].budget.reply),
           largest_estimate:([$laid[].budget.estimated_input] | max),
           largest_prompt_reported:([$sent[].outcome.usage.prompt_tokens // 0] | max),
           most_slots_reduced:([$laid[].counts | (.stubs + .dropped + .summary)] | max),
           requests:($sent | length),
           refused_for_length:([$failed[] | select((.outcome.error // "") | test($length; "i"))] | length),
           failed_otherwise:([$failed[] | select((.outcome.error // "") | test($length; "i") | not)] | length),
           said:([$failed[] | .outcome.error // ("status " + (.outcome.status | tostring))] | unique | map(.[0:120])) }' "$report/$id/session.jsonl"
}
# The longest run of refusals for length with no answer between them.
longest_refused_run() {
    jq -s --arg length "$LENGTH" 'reduce .[] as $r ({run:0, worst:0};
        if (($r.outcome.error // "") | test($length; "i")) then .run += 1 | .worst = ([.worst, .run] | max)
        elif $r.outcome.status == 200 and $r.outcome.error == null then .run = 0 else . end) | .worst' "$1"
}

window_handling() {
    [[ -n $small_model ]] || { echo "one model is authorized (window $window); name a small-window one with --small-model to compare, none is substituted"; return 3; }
    [[ -s "$report/long/long.requests.jsonl" ]] || { echo "the large-window session was not run"; return 3; }
    local large small forced real table
    mkdir -p "$report/long-window"
    cp "$report/long/session.jsonl" "$report/long-window/session.jsonl"
    cp "$report/long/long.requests.jsonl" "$report/long-window/requests.jsonl"
    large=$(windowed long-window)

    # From here the locals name the small model, and `world` and `metered` read them.
    local model=$small_model
    local window input_price output_price
    window=$(jq -r '.context_length' <<<"$small_card")
    input_price=$(jq -r '.pricing.prompt | tonumber * 1e12 | ceil' <<<"$small_card")
    output_price=$(jq -r '.pricing.completion | tonumber * 1e12 | ceil' <<<"$small_card")
    real=$window

    # Told the truth about its window, it is never refused for length, and it is under pressure.
    reading_session small-window "$real" 9 || { echo "the small-window session could not be run"; return 1; }
    small=$(windowed small-window)
    # Told a window it does not have, the provider refuses for real, and the session recovers.
    reading_session forced-overflow 200000 12 || { echo "the forced-overflow session could not be run"; return 1; }
    forced=$(windowed forced-overflow)
    table=$(jq -n --argjson a "$large" --argjson b "$small" --argjson c "$forced" \
        --argjson run "$(longest_refused_run "$report/forced-overflow/requests.jsonl")" --argjson bound "$RETRY_BOUND" \
        '{sessions:[$a, $b, $c], forced_overflow:{longest_run_of_refusals:$run, retry_bound:$bound}}')
    measure window_handling "$table"

    if [[ $(jq '.refused_for_length' <<<"$large") != 0 || $(jq '.refused_for_length' <<<"$small") != 0 ]]; then
        echo "a session told its true window was refused by the provider: $(jq -c '.sessions[0:2] | map({session, refused_for_length, said})' <<<"$table")"
        return 1
    fi
    (( $(jq '.most_slots_reduced' <<<"$small") > 0 )) || { echo "the small window was never under pressure, so not overflowing it shows nothing: $(jq -c . <<<"$small")"; return 3; }
    grep -q '[0-9]' "$report/small-window/final.txt" || { echo "the small-window session did not answer its last prompt"; return 1; }
    (( $(jq '.refused_for_length' <<<"$forced") > 0 )) || { echo "the overflow was never forced: nothing was refused for length in $(jq '.requests' <<<"$forced") requests, largest prompt $(jq '.largest_prompt_reported' <<<"$forced") of $real"; return 3; }
    if (( $(jq '.forced_overflow.longest_run_of_refusals' <<<"$table") > RETRY_BOUND )); then
        echo "a forced overflow was refused $(jq '.forced_overflow.longest_run_of_refusals' <<<"$table") times running, over the bound of $RETRY_BOUND"
        return 1
    fi
    jq -e -s 'last | .outcome.status == 200 and .outcome.error == null' "$report/forced-overflow/requests.jsonl" >/dev/null || { echo "the session never recovered: its last request was refused"; return 1; }
    grep -q '[0-9]' "$report/forced-overflow/final.txt" || { echo "after the overflow the last prompt got no answer"; return 1; }
    echo "$(jq -c '.sessions | map({session, advertised_window, reply_reserved, largest_prompt_reported, refused_for_length, failed_otherwise})' <<<"$table"); refusals in a row at most $(jq '.forced_overflow.longest_run_of_refusals' <<<"$table") of $RETRY_BOUND"
}

run_scenario metering metering
if jq -e 'any(.[]; .id == "metering" and .verdict == "PASS")' "$report/scenarios.json" >/dev/null; then
    # One part alone while it is being worked on; a run that skips any is not a whole run.
    only=${NERV_LIVE_ONLY:-}
    [[ -z $only ]] || record partial-run "NOT VERIFIED" 0 "only $only was run"
    if [[ -z $only || $only == window ]]; then
        long_session > "$scratch/long.dir" 2> "$report/long-session.log" || true
    fi
    if [[ -z $only ]]; then
        run_scenario token-estimates estimates
        run_scenario prompt-caching caching
        run_scenario retained-context retained_context
        run_scenario control-arm control_arm
    fi
    [[ -n $only && $only != window ]] || run_scenario window-handling window_handling
    [[ -n $only && $only != learning ]] || run_scenario cross-session-learning cross_session_learning
    run_scenario cost-and-latency cost_and_latency
    for kept in learn learn-plain learn-reject-1 learn-reject-2 learn-approve-1 learn-approve-2; do
        [[ -d "$scratch/$kept" ]] || continue
        mkdir -p "$report/$kept"
        cp "$scratch/$kept.requests.jsonl" "$scratch/$kept"/*.txt "$scratch/$kept"/*.request.json "$report/$kept/" 2>/dev/null || true
    done
else
    echo "acceptance-live: the meter did not pass its own test; nothing was sent" >&2
fi
