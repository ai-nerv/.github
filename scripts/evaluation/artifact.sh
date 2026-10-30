#!/usr/bin/env bash
set -euo pipefail
umask 077
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
[[ ( $# == 4 || $# == 5 ) && ( $4 == baseline || $4 == candidate ) &&
   ( ${5:-retained} == retained || ${5:-retained} == build-output ) ]] || {
    echo 'usage: artifact.sh ROOT DESCRIPTOR MANIFEST baseline|candidate [retained|build-output]' >&2; exit 2;
}
input_root=$1
variant=$4
source_mode=${5:-retained}
source "$root/scripts/preserve-binary.sh"
mkdir -p "$root/target/evaluation"
receipt=$(mktemp -d "$root/target/evaluation/artifact-XXXXXXXX")
mkdir "$receipt/bin" "$receipt/lib" "$receipt/members" "$receipt/assets"
touch "$receipt/binaries.sha256"
artifact_sha=
finish() {
    local code=$?
    trap - EXIT
    if [[ -s $receipt/binaries.sha256 ]] && ! verify_preserved_binaries "$receipt/binaries.sha256" > "$receipt/integrity.log" 2>&1; then code=1; fi
    jq -n --argjson code "$code" --arg variant "$variant" --arg identity "$artifact_sha" --arg source_mode "$source_mode" \
        '{schema:1,scope:"evaluation-artifact-preflight",variant:$variant,source_mode:$source_mode,
          status:(if $code==0 then "ARTIFACT_VALIDATED" else "FAIL" end),exit_code:$code,
          artifact_sha256:(if $code==0 then $identity else null end),workers_started:0}' > "$receipt/summary.json"
    printf 'Evaluation artifact evidence: %s\n' "$receipt"
    exit "$code"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
preserve_binary "$root/target/evaluation/bin/eval-input" "$receipt/bin/eval-input" "$receipt/binaries.sha256" > "$receipt/helper.sha256"
helper="$receipt/bin/eval-input"
for filter in lexical json artifact manifest contract; do
    "$helper" file "$root/scripts/evaluation" "$filter.jq" "$receipt/filter-$filter" 131072 1 > "$receipt/filter-$filter-counts.json"
done
cp "$receipt/filter-contract/input" "$receipt/lib/contract.jq"
snapshot_json() {
    "$helper" file "$input_root" "$1" "$receipt/$2" 131072 1 > "$receipt/$2-counts.json"
    jq -Rse --argjson safe_integers true -f "$receipt/filter-lexical/input" "$receipt/$2/input" >/dev/null
    jq --stream --slurp -e -f "$receipt/filter-json/input" "$receipt/$2/input" >/dev/null
}
snapshot_json "$2" descriptor
snapshot_json "$3" manifest
jq -L "$receipt/lib" -e -f "$receipt/filter-artifact/input" "$receipt/descriptor/input" > "$receipt/validated.json"
jq -L "$receipt/lib" -e -f "$receipt/filter-manifest/input" "$receipt/manifest/input" > "$receipt/validated-manifest.json"
jq --slurpfile artifact "$receipt/validated.json" '[.tasks[]|
    {id,missing_features:(.requires_features-$artifact[0].features)}|.+{eligible:(.missing_features==[])}]' \
    "$receipt/validated-manifest.json" > "$receipt/eligibility.json"
if [[ $variant == candidate ]] && ! jq -e 'all(.[]; .eligible)' "$receipt/eligibility.json" >/dev/null; then
    echo 'candidate is missing required declared features' >&2; exit 1
fi
jq -r '.members[]|[.name,.path,.sha256]|@tsv' "$receipt/validated.json" > "$receipt/members.tsv"
while IFS=$'\t' read -r name path expected; do
    mode=binary
    if [[ $source_mode == build-output ]]; then mode=build-binary; fi
    "$helper" "$mode" "$input_root" "$path" "$receipt/members/$name" > "$receipt/$name-counts.json"
    file="$receipt/members/$name/input"
    actual=$(sha256sum < "$file"); actual=${actual%% *}
    [[ $actual == "$expected" ]] || { echo "selected binary digest mismatch: $name" >&2; exit 1; }
    header=$(od -An -v -tx1 -N20 "$file" | tr -d ' \n')
    [[ $header == 7f454c46020101* && ( ${header:14:2} == 00 || ${header:14:2} == 03 ) &&
       ( ${header:32:4} == 0200 || ${header:32:4} == 0300 ) && ${header:36:4} == 3e00 ]] || {
        echo "selected binary must be a Linux x86_64 ELF executable: $name" >&2; exit 1;
    }
    sha256sum "$file" >> "$receipt/binaries.sha256"
done < "$receipt/members.tsv"
jq -r '.assets[]|[.owner,.name,.path,.sha256]|@tsv' "$receipt/validated.json" > "$receipt/assets.tsv"
index=0
while IFS=$'\t' read -r owner name path expected; do
    "$helper" file "$input_root" "$path" "$receipt/assets/$index" 131072 1 > "$receipt/asset-$index-counts.json"
    actual=$(sha256sum < "$receipt/assets/$index/input"); actual=${actual%% *}
    [[ $actual == "$expected" ]] || { echo "selected config digest mismatch: $owner/$name" >&2; exit 1; }
    index=$((index+1))
done < "$receipt/assets.tsv"
jq -Sc '.members|=map(del(.path))|.assets|=map(del(.path))' "$receipt/validated.json" > "$receipt/identity.json"
artifact_sha=$(sha256sum < "$receipt/identity.json"); artifact_sha=${artifact_sha%% *}
jq --arg sha "$artifact_sha" --arg variant "$variant" \
    '{schema:1,variant:$variant,artifact_sha256:$sha,
      members:[.members[]|{name,path:("members/"+.name+"/input"),sha256}],
      assets:[.assets|to_entries[]|{owner:.value.owner,name:.value.name,path:("assets/"+(.key|tostring)+"/input"),sha256:.value.sha256}]}' \
    "$receipt/validated.json" > "$receipt/selection.json"
find "$receipt/members" "$receipt/assets" "$receipt/descriptor" "$receipt/manifest" "$receipt/lib" \
    "$receipt"/filter-* -type f -exec sha256sum -- {} + > "$receipt/inputs.sha256"
sha256sum "$receipt/identity.json" "$receipt/selection.json" "$receipt/validated.json" \
    "$receipt/validated-manifest.json" "$receipt/eligibility.json" >> "$receipt/inputs.sha256"
