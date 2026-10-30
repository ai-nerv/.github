#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
mkdir -p "$root/target/evaluation"
report=$(mktemp -d "$root/target/evaluation/artifact-tests-XXXXXXXX")
passed=0
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --argjson passed "$passed" \
        '{schema:1,scope:"evaluation-artifact-tests",status:(if $code==0 then "PASS" else "FAIL" end),exit_code:$code,checks:$passed}' > "$report/summary.json"
    printf 'Evaluation artifact test evidence: %s\n' "$report"
    exit "$code"
}
trap finish EXIT
bundle="$report/bundle"
mkdir -p "$bundle/bin" "$bundle/config"
cp "$root/scripts/evaluation/manifests/offline.json" "$bundle/manifest.json"
for name in magi casper melchior balthasar; do
    cp "$root/target/evaluation/bin/eval-input" "$bundle/bin/$name"
done
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
' > "$report/valid.json"
cp "$report/valid.json" "$bundle/artifact.json"
validate() {
    jq -Rse --argjson safe_integers true -f "$root/scripts/evaluation/lexical.jq" "$1" >/dev/null &&
    jq --stream --slurp -e -f "$root/scripts/evaluation/json.jq" "$1" >/dev/null &&
    jq -L "$root/scripts/evaluation" -e -f "$root/scripts/evaluation/artifact.jq" "$1" >/dev/null
}
validate "$report/valid.json"
passed=$((passed+1))
changes=(
    '.schema=2' '.kind="live"' '.platform="linux-aarch64"' '.extra=1'
    '.source.commit="unknown"' '.source.dirty="true"' '.source.extra=1'
    '.features=["unknown"]' '.features+=.features' '.features|=reverse'
    '.members=[]' '.members|=reverse' '.members[1]=.members[0]'
    '.members[0].path="/bin/true"' '.members[0].path="../bin/true"'
    '.members[0].path="bin/./magi"' '.members[0].path="bin//magi"'
    '.members[0].path="bin/magi\n"' '.members[0].sha256="unknown"'
    '.members[0].source=null' '.members[0].build.status="UNKNOWN"'
    '.members[0].build.profile="release"' '.members[0].build.extra=true'
    '.assets=[]' '.assets|=reverse' '.assets[0].name="credentials.json"'
    '.assets|=.[0:7]'
    '.assets[0].path="config/../credentials"' '.assets[0].sha256="wrong"'
    '.assets[1].path=.assets[0].path' '.members[0].path=.assets[0].path'
)
for index in "${!changes[@]}"; do
    jq "${changes[index]}" "$report/valid.json" > "$report/invalid-$index.json"
    if validate "$report/invalid-$index.json" > "$report/invalid-$index.out" 2> "$report/invalid-$index.err"; then
        echo "accepted invalid artifact: ${changes[index]}" >&2; exit 1
    fi
    passed=$((passed+1))
done
jq '.members[].build={status:"RECORDED",profile:"release",rustc:"rustc 1.90.0 (synthetic)",target:"x86_64-unknown-linux-gnu"}' \
    "$report/valid.json" > "$report/recorded.json"
validate "$report/recorded.json"
passed=$((passed+1))
check_artifact() {
    bash "$root/scripts/evaluation/artifact.sh" "$bundle" artifact.json manifest.json "${1:-candidate}" "${2:-retained}"
}
receipt_path() { sed -n 's/^Evaluation artifact evidence: //p' "$1"; }
refuse() {
    if check_artifact candidate "${2:-retained}" > "$report/$1.out" 2> "$report/$1.err"; then
        echo "accepted unsafe artifact: $1" >&2; exit 1
    fi
    local receipt
    receipt=$(receipt_path "$report/$1.out")
    jq -e '.status=="FAIL" and .workers_started==0 and .artifact_sha256==null' "$receipt/summary.json" >/dev/null
    passed=$((passed+1))
}
check_artifact > "$report/positive.out" 2> "$report/positive.err"
positive=$(receipt_path "$report/positive.out")
jq -e '.status=="ARTIFACT_VALIDATED" and .workers_started==0' "$positive/summary.json" >/dev/null
jq -e 'all(.[]; .eligible)' "$positive/eligibility.json" >/dev/null
sha256sum -c "$positive/inputs.sha256" > "$report/positive-integrity.log"
[[ $(stat -c %a "$positive/members/magi/input") == 555 && $(stat -c %a "$positive/assets/0/input") == 600 ]]
passed=$((passed+1))
cp -R "$bundle/bin" "$bundle/other bin"
cp -R "$bundle/config" "$bundle/other-config"
jq '.members[].path|="other "+.|.assets[].path|="other-"+.' "$report/valid.json" > "$bundle/artifact.json"
check_artifact > "$report/relocated.out" 2> "$report/relocated.err"
relocated=$(receipt_path "$report/relocated.out")
cmp "$positive/identity.json" "$relocated/identity.json"
passed=$((passed+1))
jq '.features=[]' "$report/valid.json" > "$bundle/artifact.json"
refuse missing-features
missing=$(receipt_path "$report/missing-features.out")
[[ $(find "$missing/members" -type f | wc -l) == 0 ]]
check_artifact baseline > "$report/old-baseline.out" 2> "$report/old-baseline.err"
baseline=$(receipt_path "$report/old-baseline.out")
jq -e 'all(.[]; .eligible==false and (.missing_features|length)>0)' "$baseline/eligibility.json" >/dev/null
jq -e '.status=="ARTIFACT_VALIDATED" and .variant=="baseline"' "$baseline/summary.json" >/dev/null
passed=$((passed+1))
cp "$report/valid.json" "$bundle/artifact.json"
printf 'changed\n' >> "$bundle/bin/magi"
refuse wrong-binary
cp "$root/target/evaluation/bin/eval-input" "$bundle/bin/magi"
chmod 600 "$bundle/bin/magi"
refuse nonexecutable
chmod 755 "$bundle/bin/magi"
rm "$bundle/bin/magi"
ln -s "$root/target/evaluation/bin/eval-input" "$bundle/bin/magi"
refuse symlink-binary
rm "$bundle/bin/magi"
cp "$root/target/evaluation/bin/eval-input" "$bundle/bin/magi"
ln "$bundle/bin/magi" "$bundle/hardlink"
refuse hardlink-binary
check_artifact candidate build-output > "$report/build-output.out" 2> "$report/build-output.err"
built=$(receipt_path "$report/build-output.out")
jq -e '.status=="ARTIFACT_VALIDATED" and .source_mode=="build-output" and .workers_started==0' "$built/summary.json" >/dev/null
cmp "$positive/identity.json" "$built/identity.json"
[[ $(stat -c %h "$built/members/magi/input") == 1 && $(stat -c %a "$built/members/magi/input") == 555 ]]
passed=$((passed+1))
printf 'changed through alias\n' >> "$bundle/hardlink"
refuse build-output-digest build-output
sha256sum -c "$built/binaries.sha256" > "$report/build-output-integrity.log"
cp "$root/target/evaluation/bin/eval-input" "$bundle/bin/magi"
ln "$bundle/config/0.lua" "$bundle/config-alias"
refuse build-output-linked-config build-output
rm "$bundle/config-alias"
rm "$bundle/hardlink"
printf '#!/bin/sh\ntouch "%s"\n' "$report/executed" > "$bundle/bin/magi"
changed=$(sha256sum < "$bundle/bin/magi"); changed=${changed%% *}
jq --arg sha "$changed" '.members[0].sha256=$sha' "$report/valid.json" > "$bundle/artifact.json"
refuse script-binary
[[ ! -e $report/executed ]]
cp "$root/target/evaluation/bin/eval-input" "$bundle/bin/magi"
printf '\267\000' | dd of="$bundle/bin/magi" bs=1 seek=18 conv=notrunc status=none
changed=$(sha256sum < "$bundle/bin/magi"); changed=${changed%% *}
jq --arg sha "$changed" '.members[0].sha256=$sha' "$report/valid.json" > "$bundle/artifact.json"
refuse wrong-architecture
cp "$root/target/evaluation/bin/eval-input" "$bundle/bin/magi"
cp "$report/valid.json" "$bundle/artifact.json"
printf 'changed\n' > "$bundle/config/7.lua"
refuse wrong-config
rm "$bundle/config/7.lua"
refuse missing-config
ln -s "$bundle/config/0.lua" "$bundle/config/7.lua"
refuse symlink-config
rm "$bundle/config/7.lua"
cp "$bundle/config/0.lua" "$bundle/config/7.lua"
printf '{"schema":1,"schema":1}\n' > "$bundle/artifact.json"
refuse duplicate-json
truncate -s 131073 "$bundle/artifact.json"
refuse oversized-descriptor
printf 'Evaluation artifact checks passed: %s\n' "$passed"
