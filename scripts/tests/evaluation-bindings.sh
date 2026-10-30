#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
report=$(mktemp -d "$root/target/evaluation/binding-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" \
        '{schema:1,scope:"evaluation-binding-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$passed,workers_started:0}' > "$report/summary.json"
    printf 'Evaluation binding test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
jq -ne -L "$root/scripts/evaluation" 'include "log-word";
    [{text:("a"+("1"*30)),expected:("a"+("1"*30))},
     {text:("a"+("1"*31)),expected:"[redacted]"},
     {text:("a"*40),expected:("a"*40)}, {text:("1"*40),expected:("1"*40)},
     {text:"alpha-rho-1700000000",expected:"alpha-rho-1700000000"},
     {text:("alpha-rho-"+("0"*39)),expected:"[redacted]"}] |
    all(.[];(.text|magi_log_word)==.expected) as $words |
    (("alpha-rho-"+("0"*39))|magi_log_pattern) as $pattern |
    $words and ("[redacted]"|test("^"+$pattern+"$")) and ("r"|test("^"+$pattern+"$")|not)' >/dev/null
passed=$((passed+1))
bundle="$report/bundle"
mkdir -p "$bundle/bin" "$bundle/config" "$bundle/scripts/evaluation"
cp -R "$root/scripts/evaluation/fixtures" "$bundle/scripts/evaluation/fixtures"
cp "$root/scripts/evaluation/manifests/offline.json" "$bundle/manifest.json"
for name in magi casper melchior balthasar provider grammar; do cp "$root/target/evaluation/bin/eval-input" "$bundle/bin/$name"; done
for index in {0..7}; do printf 'error("synthetic config must never execute")\n' > "$bundle/config/$index.lua"; done
binary_sha=$(sha256sum < "$bundle/bin/magi"); binary_sha=${binary_sha%% *}
config_sha=$(sha256sum < "$bundle/config/0.lua"); config_sha=${config_sha%% *}
jq -n -L "$root/scripts/evaluation" --arg binary "$binary_sha" --arg config "$config_sha" '
  include "contract";
  {schema:1,kind:"offline-artifact",platform:"linux-x86_64",source:{commit:("a"*40),dirty:true},
   features:(inventory|map(.features[])|unique),
   members:["magi","casper","melchior","balthasar"]|map({name:.,path:("bin/"+.),sha256:$binary,
     source:{commit:("b"*40),dirty:true},build:{status:"NOT_RECORDED",profile:null,rustc:null,target:null}}),
   assets:[{owner:"magi",name:"init.lua"},{owner:"magi",name:"tools.lua"},
     {owner:"casper",name:"tools.lua"},{owner:"melchior",name:"apis.lua"},
     {owner:"melchior",name:"providers.lua"},{owner:"balthasar",name:"init.lua"},
     {owner:"balthasar",name:"sections.lua"},{owner:"balthasar",name:"sources/magi.lua"}]|
     to_entries|map(.value+{path:("config/"+(.key|tostring)+".lua"),sha256:$config})}
' > "$bundle/artifact.json"
artifact_digest() {
    jq -Sc '.members|=map(del(.path))|.assets|=map(del(.path))' "$1" | sha256sum | cut -d' ' -f1
}
base_sha=$(artifact_digest "$bundle/artifact.json")
cp "$bundle/artifact.json" "$bundle/candidate.json"
candidate_sha=$base_sha
provider_sha=$binary_sha grammar_sha=$binary_sha
observer_args=()
make_binding() {
    bash "$root/scripts/evaluation/bindings.sh" "$bundle" manifest.json artifact.json "$base_sha" candidate.json "$candidate_sha" \
        bin/provider "$provider_sha" bin/grammar "$grammar_sha" "${observer_args[@]}"
}
binding_path() { sed -n 's/^Evaluation frozen bindings: //p' "$1"; }
make_binding > "$report/first.out" 2> "$report/first.err"
first=$(binding_path "$report/first.out")
binding_sha=$(jq -er '.bindings_sha256' "$first/summary.json")
jq -e '.status=="BINDINGS_VALIDATED" and .workers_started==0' "$first/summary.json" >/dev/null
jq -e '.schema==2 and (.tasks|length)==10 and (.tasks[7].models|length)==2 and
    .tasks[7].models[0].api=="anthropic-messages" and .tasks[7].models[1].api=="openai-completions" and
    all(.tasks[]; .config_sha256.baseline==.config_sha256.candidate)' "$first/bindings.json" >/dev/null
sha256sum -c "$first/inputs.sha256" > "$report/first-integrity.log"
passed=$((passed+1))
make_binding > "$report/second.out" 2> "$report/second.err"
second=$(binding_path "$report/second.out")
cmp "$first/bindings.json" "$second/bindings.json"
passed=$((passed+1))
printf '\nmagi.model = "unexpected/model"\n' > "$bundle/config/changed.lua"
changed=$(sha256sum < "$bundle/config/changed.lua"); changed=${changed%% *}
jq --arg sha "$changed" '.assets[0].path="config/changed.lua"|.assets[0].sha256=$sha' "$bundle/artifact.json" > "$bundle/candidate.json"
candidate_sha=$(artifact_digest "$bundle/candidate.json")
make_binding > "$report/candidate.out" 2> "$report/candidate.err"
candidate=$(binding_path "$report/candidate.out")
jq -e --slurpfile before "$first/bindings.json" '.runner_sha256==$before[0].runner_sha256 and
    .artifacts.baseline==$before[0].artifacts.baseline and .artifacts.candidate!=$before[0].artifacts.candidate' "$candidate/bindings.json" >/dev/null
jq -ne --slurpfile before "$first/bindings.json" --slurpfile after "$candidate/bindings.json" \
    'all(range(0;10); . as $i|$before[0].tasks[$i] as $old|$after[0].tasks[$i] as $new|
      $old.fixture_sha256==$new.fixture_sha256 and $old.config_sha256.baseline==$new.config_sha256.baseline and
      $old.config_sha256.candidate!=$new.config_sha256.candidate)' >/dev/null
passed=$((passed+1))
cp "$bundle/artifact.json" "$bundle/candidate.json"; candidate_sha=$base_sha
printf '\nfixture revision\n' >> "$bundle/scripts/evaluation/fixtures/small-bug-fix/prompt.txt"
make_binding > "$report/fixture.out" 2> "$report/fixture.err"
changed_fixture=$(binding_path "$report/fixture.out")
jq -e --slurpfile before "$first/bindings.json" \
    '.tasks[0].fixture_sha256!=$before[0].tasks[0].fixture_sha256 and
     .tasks[0].config_sha256==$before[0].tasks[0].config_sha256 and .tasks[1:]==$before[0].tasks[1:]' "$changed_fixture/bindings.json" >/dev/null
cp "$root/scripts/evaluation/fixtures/small-bug-fix/prompt.txt" "$bundle/scripts/evaluation/fixtures/small-bug-fix/prompt.txt"
passed=$((passed+1))
printf 'changed synthetic helper\n' >> "$bundle/bin/provider"
provider_sha=$(sha256sum < "$bundle/bin/provider"); provider_sha=${provider_sha%% *}
make_binding > "$report/helper.out" 2> "$report/helper.err"
changed_helper=$(binding_path "$report/helper.out")
jq -e --slurpfile before "$first/bindings.json" '.runner_sha256!=$before[0].runner_sha256 and
    .tasks==$before[0].tasks and .artifacts==$before[0].artifacts' "$changed_helper/bindings.json" >/dev/null
cp "$bundle/bin/magi" "$bundle/bin/provider"; provider_sha=$binary_sha
passed=$((passed+1))
refuse_binding() {
    if make_binding > "$report/refuse-$1.out" 2> "$report/refuse-$1.err"; then echo "accepted invalid binding: $1" >&2; exit 1; fi
    local result
    result=$(binding_path "$report/refuse-$1.out")
    jq -e '.status=="FAIL" and .bindings_sha256==null and .workers_started==0' "$result/summary.json" >/dev/null
    passed=$((passed+1))
}
base_sha=$(printf '%064d' 0); refuse_binding baseline; base_sha=$(artifact_digest "$bundle/artifact.json")
candidate_sha=$(printf '%064d' 0); refuse_binding candidate; candidate_sha=$base_sha
provider_sha=$(printf '%064d' 0); refuse_binding provider; provider_sha=$binary_sha
grammar_sha=$(printf '%064d' 0); refuse_binding grammar; grammar_sha=$binary_sha
printf 'not reviewed\n' > "$bundle/scripts/evaluation/fixtures/small-bug-fix/driver.sh"
refuse_binding reserved-driver
rm "$bundle/scripts/evaluation/fixtures/small-bug-fix/driver.sh"
printf '1\n' > "$bundle/scripts/evaluation/fixtures/small-bug-fix/provider-attempt-limit.txt"
refuse_binding reserved-attempt-limit
rm "$bundle/scripts/evaluation/fixtures/small-bug-fix/provider-attempt-limit.txt"
for name in ipc-recorder-melchior.sh pack-model-ipc.sh event-observer.sh client-admission.lua client-providers.lua client-attempt-limit.txt; do
    printf 'not reviewed\n' > "$bundle/scripts/evaluation/fixtures/small-bug-fix/$name"
    refuse_binding "reserved-$name"
    rm "$bundle/scripts/evaluation/fixtures/small-bug-fix/$name"
done
ln -s "$bundle/config/0.lua" "$bundle/scripts/evaluation/fixtures/small-bug-fix/escape"
refuse_binding fixture-symlink
rm "$bundle/scripts/evaluation/fixtures/small-bug-fix/escape"
mkdir "$bundle/scripts/evaluation/fixtures/small-bug-fix/padding"
count=$(find "$bundle/scripts/evaluation/fixtures/small-bug-fix" -type f -printf x | wc -c)
for ((i=count; i<255; i++)); do : > "$bundle/scripts/evaluation/fixtures/small-bug-fix/padding/$i"; done
refuse_binding staged-file-limit
rm -rf "$bundle/scripts/evaluation/fixtures/small-bug-fix/padding"
cp "$bundle/manifest.json" "$report/manifest-original.json"
printf '{"schema":1,"schema":1}\n' > "$bundle/manifest.json"
refuse_binding duplicate-manifest
cp "$report/manifest-original.json" "$bundle/manifest.json"
artifact="$first/$(cat "$first/selections/baseline-receipt.txt")"
while read -r task; do
    for port in 12345 65535; do
        world="$report/config-$task-$port"
        mkdir -p "$world/evidence"
        bash "$root/scripts/evaluation/render-config.sh" "$task" "$artifact/assets" "$first/fixtures/$task" "$world/evidence/config" "$port"
        printf 'PORT=%s\n' "$port" > "$world/evidence/provider.stdout"
        bash "$root/scripts/evaluation/check-config.sh" "$first" "$binding_sha" "$task" baseline "$world" > "$world/result.json" 2> "$world/result.err"
        jq -e '.status=="CONFIG_VALIDATED" and .workers_started==0' "$world/result.json" >/dev/null
        passed=$((passed+1))
    done
done < <(jq -r '.tasks[].id' "$first/bindings.json")
for mode in changed-grant changed-tool changed-provider wrong-port missing extra directory symlink hardlink port-extra port-zero port-range template binding; do
    world="$report/corrupt-$mode"
    cp -R "$report/config-cache-accounting-12345" "$world"
    case $mode in
        changed-grant) printf '\nmagi.allow = { { verb = "run" } }\n' >> "$world/evidence/config/0.lua" ;;
        changed-tool) printf '\nchanged\n' >> "$world/evidence/config/1.lua" ;;
        changed-provider) sed 's/127.0.0.1/127.0.0.2/g' "$report/config-cache-accounting-12345/evidence/config/4.lua" > "$world/evidence/config/4.lua" ;;
        wrong-port) printf 'PORT=54321\n' > "$world/evidence/provider.stdout" ;;
        missing) rm "$world/evidence/config/anthropic-init.lua" ;;
        extra) : > "$world/evidence/config/extra.lua" ;;
        directory) mkdir "$world/evidence/config/extra" ;;
        symlink) rm "$world/evidence/config/0.lua"; ln -s "$report/config-cache-accounting-12345/evidence/config/0.lua" "$world/evidence/config/0.lua" ;;
        hardlink) ln "$world/evidence/config/0.lua" "$world/alias.lua" ;;
        port-extra) printf 'PORT=12345\nextra\n' > "$world/evidence/provider.stdout" ;;
        port-zero) printf 'PORT=012345\n' > "$world/evidence/provider.stdout" ;;
        port-range) printf 'PORT=65536\n' > "$world/evidence/provider.stdout" ;;
        template) printf '\nchanged\n' >> "$first/configs/baseline/cache-accounting/0.lua" ;;
        binding) printf '\n' >> "$first/bindings.json" ;;
    esac
    if bash "$root/scripts/evaluation/check-config.sh" "$first" "$binding_sha" cache-accounting baseline "$world" > "$world/result.json" 2> "$world/result.err"; then
        echo "accepted changed effective config: $mode" >&2; exit 1
    fi
    jq -e '.status=="FAIL" and .config_sha256==null' "$world/result.json" >/dev/null
    if [[ $mode == template ]]; then cp "$second/configs/baseline/cache-accounting/0.lua" "$first/configs/baseline/cache-accounting/0.lua"; fi
    if [[ $mode == binding ]]; then cp "$second/bindings.json" "$first/bindings.json"; fi
    passed=$((passed+1))
done
sha256sum -c "$first/inputs.sha256" > "$report/final-integrity.log"
cp "$bundle/bin/magi" "$bundle/bin/observer"
jq --arg sha "$binary_sha" '.event_observer={schema:1,sha256:$sha,modes:{baseline:"drain",candidate:"stall"}}' \
    "$report/manifest-original.json" > "$bundle/manifest.json"
refuse_binding missing-observer
observer_args=(bin/observer)
make_binding > "$report/observer.out" 2> "$report/observer.err"
observed=$(binding_path "$report/observer.out")
jq -e --slurpfile before "$second/bindings.json" --slurpfile policy "$bundle/manifest.json" \
    '.event_observer==$policy[0].event_observer and .artifacts==$before[0].artifacts and .tasks==$before[0].tasks and
    .runner_sha256!=$before[0].runner_sha256' "$observed/bindings.json" >/dev/null
cmp "$bundle/bin/observer" "$observed/runner/event-observer/input"
sha256sum -c "$observed/inputs.sha256" > "$report/observer-integrity.log"
passed=$((passed+1))
printf 'changed\n' >> "$bundle/bin/observer"
refuse_binding observer-digest
cp "$bundle/bin/magi" "$bundle/bin/observer"
candidate_sha=$(printf '%064d' 0); refuse_binding unequal-observer-artifacts; candidate_sha=$base_sha
for change in 'del(.event_observer)' '.event_observer.modes.candidate="drain"' \
    '.event_observer.sha256=("0"*64)' '.tasks[0].config_sha256.candidate=("0"*64)'; do
    jq "$change" "$observed/bindings.json" > "$report/invalid-observer-binding.json"
    manifest_sha=$(sha256sum < "$bundle/manifest.json"); manifest_sha=${manifest_sha%% *}
    if jq -e -L "$root/scripts/evaluation" --slurpfile manifest "$bundle/manifest.json" --arg sha "$manifest_sha" \
        'include "identity"; validate_bindings($manifest[0];$sha)' "$report/invalid-observer-binding.json" \
        > "$report/invalid-observer-binding.out" 2> "$report/invalid-observer-binding.err"; then
        echo "accepted invalid observer binding: $change" >&2; exit 1
    fi
    passed=$((passed+1))
done
cp "$report/manifest-original.json" "$bundle/manifest.json"
refuse_binding observer-without-policy
printf 'Evaluation binding checks passed: %s\n' "$passed"
