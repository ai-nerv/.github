#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/json-tests-XXXXXXXX")
helper="$root/target/evaluation/bin/eval-input"
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson checks "$passed" \
        '{schema:1,scope:"evaluation-native-json-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$checks}' > "$report/summary.json"
    printf 'Evaluation native JSON test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
mkdir "$report/input"
while IFS= read -r line; do
    printf '%s\n' "$line" > "$report/input/value.json"
    reference=0 native=0
    { jq -Rse --argjson safe_integers true -f "$root/scripts/evaluation/lexical.jq" "$report/input/value.json" >/dev/null &&
      jq --stream --slurp -e -f "$root/scripts/evaluation/json.jq" "$report/input/value.json" >/dev/null; } 2> "$report/reference-$passed.err" || reference=$?
    "$helper" json "$report/input" value.json 131072 > "$report/native-$passed.json" 2> "$report/native-$passed.err" || native=$?
    if [[ $reference == 0 ]]; then
        [[ $native == 0 ]]
        events=$(jq --stream --slurp length "$report/input/value.json")
        jq -e --argjson events "$events" --argjson bytes "$(wc -c < "$report/input/value.json")" \
            '.status=="JSON_VALIDATED" and .events==$events and .bytes==$bytes and .safe_integers' "$report/native-$passed.json" >/dev/null
    else [[ $native != 0 && ! -s $report/native-$passed.json ]]; fi
    passed=$((passed+1))
done <<'JSON'
null
true
false
0
9007199254740991
""
[]
{}
{"a":[1,2],"b":[]}
{"a":{"x":0},"b":{"x":1}}
{"a":0,"a":1}
{"a":{},"\u0061":[]}
{"é":1,"\u00e9":2}
{"😀":1,"\ud83d\ude00":2}
{"a\nb":0,"a\u000ab":1}
{"é界":"\"\\\/\b\f\n\r\t\ud83d\ude00"}
[1,]
{"a":0,}
{"a":}
{a:0}
[]{}
null null
NaN
-1
-0
+1
01
1.0
1e0
9007199254740992
"\x01"
"\u123"
JSON
for mode in normal invalid-utf8 nul symlink hardlink directory fifo missing ancestor escaping bad-limit; do
    printf '{}\n' > "$report/input/value.json"
    path=value.json bound=131072 code=0
    case $mode in
        normal) ;;
        invalid-utf8) printf '"\377"\n' > "$report/input/value.json" ;;
        nul) printf '{}\0\n' > "$report/input/value.json" ;;
        symlink) ln -s value.json "$report/input/link.json"; path=link.json ;;
        hardlink) ln "$report/input/value.json" "$report/input/hard.json" ;;
        directory) mkdir "$report/input/directory"; path=directory ;;
        fifo) mkfifo "$report/input/pipe"; path=pipe ;;
        missing) path=missing ;;
        ancestor) ln -s "$report/input" "$report/input/linked"; path=linked/value.json ;;
        escaping) path=../input/value.json ;;
        bad-limit) bound=0131072 ;;
    esac
    timeout --kill-after=1 5 "$helper" json "$report/input" "$path" "$bound" > "$report/$mode.json" 2> "$report/$mode.err" || code=$?
    if [[ $mode == normal ]]; then [[ $code == 0 ]]; else [[ $code != 0 && $code != 124 && ! -s $report/$mode.json ]]; fi
    if [[ $mode == hardlink ]]; then rm "$report/input/hard.json"; fi
    passed=$((passed+1))
done
printf 'Evaluation native JSON checks passed: %s\n' "$passed"
