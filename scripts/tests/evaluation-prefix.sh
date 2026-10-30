#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/prefix-tests-XXXXXXXX")
mkdir "$report/evidence" "$report/native"
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson checks "$passed" \
        '{schema:1,scope:"evaluation-prefix-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$checks}' > "$report/summary.json"
    printf 'Evaluation prefix test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
cat > "$report/base.json" <<'JSON'
{"model":"synthetic","system":[{"type":"text","text":"é界","cache_control":{"type":"ephemeral"}}],"tools":[{"name":"read","input_schema":{"type":"object","properties":{"cache_control":{"type":"string"}}},"cache_control":{"type":"ephemeral"}}],"messages":[{"role":"assistant","content":[{"type":"thinking","thinking":"reason\r\n","signature":"sig1"},{"type":"tool_use","id":"a1","name":"read","input":{"cache_control":"keep","n":9007199254740993},"cache_control":{"type":"ephemeral"}}]}],"max_tokens":1024,"temperature":0.2}
JSON
build() {
    local n m h1 h2
    n=$(wc -c < "$report/first.json"); m=$(wc -c < "$report/second.json")
    h1=$(sha256sum < "$report/first.json"); h1=${h1%% *}
    h2=$(sha256sum < "$report/second.json"); h2=${h2%% *}
    { cat "$report/first.json"; printf '\n'; cat "$report/second.json"; printf '\n'; } > "$report/evidence/requests.jsonl"
    jq -nc --argjson n "$n" --argjson m "$m" --arg h1 "$h1" --arg h2 "$h2" '
      {schema:2,scope:"offline-provider-admission",event:"start",limit:64,capture_limit_bytes:8388608,journal_limit_bytes:131072},
      {event:"admit",attempt:1},{event:"reserve_capture",attempt:1,bytes:$n,reserved_bytes:($n+1)},
      {event:"body",attempt:1,bytes:$n,sha256:$h1},{event:"response",attempt:1,turn:0},
      {event:"admit",attempt:2},{event:"reserve_capture",attempt:2,bytes:$m,reserved_bytes:($n+$m+2)},
      {event:"body",attempt:2,bytes:$m,sha256:$h2},{event:"response",attempt:2,turn:1},
      {event:"terminal",status:"STOPPED",reason:"stopped",admitted:2,rejected:0,responses:2,incomplete:0,
       reserved_bytes:($n+$m+2),captured_bytes:($n+$m+2)}' > "$report/evidence/meter.jsonl"
}
for mode in identical whitespace cache-move parameters signature model shape order output-limit unicode openai large empty invalid-json duplicate-key bad-tools bad-messages no-model tampered; do
    cp "$report/base.json" "$report/first.json"
    cp "$report/base.json" "$report/second.json"
    expected=pass filter=
    case $mode in
        identical) ;;
        whitespace) filter='.' ;;
        cache-move) filter='del(.tools[].cache_control,.system[].cache_control,.messages[].content[].cache_control)|.messages[0].content[0].cache_control={type:"ephemeral"}' ;;
        parameters) filter='.messages[0].content[1].input.cache_control="changed"' ;;
        signature) filter='.messages[0].content[0].signature="sig2"' ;;
        model) filter='.model="other"' ;;
        shape) filter='del(.system)' ;;
        order) filter='.messages[0].content|=reverse' ;;
        output-limit) filter='.max_tokens=512|.temperature=0.1' ;;
        unicode) filter='.system[0].text="é男"' ;;
        openai) jq 'del(.system)|.messages=[{role:"system",content:"hello"},{role:"user",content:"read"}]' "$report/base.json" > "$report/first.json"; cp "$report/first.json" "$report/second.json" ;;
        large) jq '.messages[0].content[0].thinking=("é界\\n"*100000)' "$report/base.json" > "$report/first.json"; cp "$report/first.json" "$report/second.json" ;;
        empty) : > "$report/first.json"; expected=fail ;;
        invalid-json) printf '{"model":\n' > "$report/first.json"; expected=fail ;;
        duplicate-key) printf '{"model":"a","model":"b","messages":[]}\n' > "$report/first.json"; expected=fail ;;
        bad-tools) filter='.tools="wrong"'; expected=fail ;;
        bad-messages) filter='.messages=[null]'; expected=fail ;;
        no-model) filter='del(.model)'; expected=fail ;;
        tampered) expected=fail ;;
    esac
    if [[ -n $filter ]]; then jq "$filter" "$report/base.json" > "$report/second.json"; fi
    build
    if [[ $mode == tampered ]]; then printf x >> "$report/evidence/requests.jsonl"; fi
    code=0
    bash "$root/scripts/evaluation/normalized-prefix.sh" "$report/evidence" > "$report/$mode.out" 2> "$report/$mode.err" || code=$?
    receipt=$(sed -n 's/^Evaluation normalized prefix: //p' "$report/$mode.out")
    [[ -d $receipt ]]
    if [[ $expected == fail ]]; then
        [[ $code != 0 && ! -e $receipt/result.json ]]
        jq -e '.status=="FAIL" and .exit_code!=0' "$receipt/summary.json" >/dev/null
    else
        [[ $code == 0 ]]
        jq -e '.status=="PREFIX_MEASURED" and .complete_run==false and .provider_attempts==null and .cached_tokens==null and
          (.bodies|length)==2 and .bodies[0].shared_bytes==0 and .stable_prefix_bytes==.bodies[1].shared_bytes and
          .stable_prefix_bytes<=.normalized_bytes and .stable_prefix_bytes<=.request_bytes' "$receipt/result.json" >/dev/null
        case $mode in
            identical|whitespace|cache-move|output-limit|openai|large)
                jq -e '.bodies[1].shared_bytes==.bodies[1].normalized_bytes' "$receipt/result.json" >/dev/null ;;
            model|shape) jq -e '.stable_prefix_bytes==0' "$receipt/result.json" >/dev/null ;;
            *) jq -e '.stable_prefix_bytes>0 and .stable_prefix_bytes<.bodies[1].normalized_bytes' "$receipt/result.json" >/dev/null ;;
        esac
        if [[ $mode == identical ]]; then
            cut -f2- "$receipt/work/normalized.tsv" | head -1 > "$report/prompt.json"
            jq -e '.[0][0].input_schema.properties.cache_control.type=="string" and
              .[2][0].content[1].input.cache_control=="keep" and .[2][0].content[0].signature=="sig1" and
              .[2][0].content[0].thinking=="reason\r\n" and .[2][0].content[1].id=="a1" and
              (.[0][0]|has("cache_control")|not) and (.[1][0]|has("cache_control")|not)' "$report/prompt.json" >/dev/null
            grep -q '9007199254740993' "$report/prompt.json"
        fi
    fi
    passed=$((passed+1))
done
helper="$root/target/evaluation/bin/eval-input"
for mode in normal symlink hardlink directory fifo escaping unterminated too-many bad-key oversize; do
    printf '%064d\t[]\n' 0 > "$report/native/value.tsv"
    path=value.tsv
    case $mode in
        normal) ;;
        symlink) ln -s value.tsv "$report/native/link.tsv"; path=link.tsv ;;
        hardlink) ln "$report/native/value.tsv" "$report/native/hard.tsv" ;;
        directory) mkdir "$report/native/dir"; path=dir ;;
        fifo) mkfifo "$report/native/pipe"; path=pipe ;;
        escaping) path=../base.json ;;
        unterminated) truncate -s -1 "$report/native/value.tsv" ;;
        too-many) for _ in {1..65}; do printf '%064d\t[]\n' 0; done > "$report/native/value.tsv" ;;
        bad-key) printf 'bad\t[]\n' > "$report/native/value.tsv" ;;
        oversize) truncate -s 8388609 "$report/native/value.tsv" ;;
    esac
    code=0; "$helper" prefix "$report/native" "$path" > "$report/native-$mode.out" 2> "$report/native-$mode.err" || code=$?
    if [[ $mode == normal ]]; then [[ $code == 0 ]]; else [[ $code != 0 && ! -s $report/native-$mode.out ]]; fi
    rm -f "$report/native/hard.tsv"
    passed=$((passed+1))
done
printf 'Evaluation prefix checks passed: %s\n' "$passed"
