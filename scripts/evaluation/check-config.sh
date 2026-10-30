#!/usr/bin/env bash
set -euo pipefail
umask 077
[[ $# == 5 && $2 =~ ^[0-9a-f]{64}$ && $3 =~ ^[a-z][a-z0-9-]{0,63}$ && ( $4 == baseline || $4 == candidate ) ]] || {
    echo 'usage: check-config.sh FROZEN_BINDINGS BINDINGS_SHA TASK VARIANT WORLD_RECEIPT' >&2; exit 2;
}
binding_root=$1 binding_sha=$2 task=$3 variant=$4 world=$5
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
source "$root/scripts/evaluation/tree-identity.sh"
scratch=$(mktemp -d)
config_sha=
finish() {
    local code=$?
    trap - EXIT
    jq -n --argjson code "$code" --arg task "$task" --arg variant "$variant" --arg sha "$config_sha" \
        '{schema:1,scope:"evaluation-effective-config",task_id:$task,variant:$variant,
          status:(if $code==0 then "CONFIG_VALIDATED" else "FAIL" end),exit_code:$code,
          config_sha256:(if $code==0 then $sha else null end),workers_started:0}'
    rm -rf -- "$scratch"
    exit "$code"
}
trap finish EXIT
helper="$root/target/evaluation/bin/eval-input"
"$helper" file "$binding_root" bindings.json "$scratch/bindings" 131072 1 >/dev/null
actual=$(sha256sum < "$scratch/bindings/input"); [[ ${actual%% *} == "$binding_sha" ]]
"$helper" file "$binding_root" manifest/input "$scratch/manifest" 131072 1 >/dev/null
for name in bindings manifest; do
    jq -Rse --argjson safe_integers true -f "$root/scripts/evaluation/lexical.jq" "$scratch/$name/input" >/dev/null
    jq --stream --slurp -e -f "$root/scripts/evaluation/json.jq" "$scratch/$name/input" >/dev/null
done
manifest_sha=$(sha256sum < "$scratch/manifest/input"); manifest_sha=${manifest_sha%% *}
jq -L "$root/scripts/evaluation" -e --slurpfile manifest "$scratch/manifest/input" --arg sha "$manifest_sha" \
    'include "identity"; include "contract"; validate_bindings(($manifest[0]|validate_manifest);$sha)' "$scratch/bindings/input" >/dev/null
config_sha=$(jq -er --arg task "$task" --arg variant "$variant" '.tasks[]|select(.id==$task)|.config_sha256[$variant]' "$scratch/bindings/input")
"$helper" tree "$binding_root" "configs/$variant/$task" "$scratch/template" 1048576 16 >/dev/null
tree_identity "$scratch/template" > "$scratch/template.tree"
actual=$(sha256sum < "$scratch/template.tree"); [[ ${actual%% *} == "$config_sha" ]]
"$helper" tree "$world" evidence/config "$scratch/actual" 1048576 16 >/dev/null
"$helper" file "$world" evidence/provider.stdout "$scratch/provider" 128 1 >/dev/null
IFS= read -r port < "$scratch/provider/input"
[[ $port =~ ^PORT=([1-9][0-9]{0,4})$ && ${BASH_REMATCH[1]} -le 65535 ]]
port=${port#PORT=}
printf 'PORT=%s\n' "$port" > "$scratch/port"
cmp "$scratch/port" "$scratch/provider/input" >&2
sed "s/@PORT@/$port/g" "$scratch/template/4.lua" > "$scratch/expanded-provider"
mv "$scratch/expanded-provider" "$scratch/template/4.lua"
tree_identity "$scratch/template" > "$scratch/expected.tree"
tree_identity "$scratch/actual" > "$scratch/actual.tree"
cmp "$scratch/expected.tree" "$scratch/actual.tree" >&2
