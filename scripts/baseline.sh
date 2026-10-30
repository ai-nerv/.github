#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
cd "$root"
for program in oslo jq timeout sha256sum git find sort xargs cp chmod head wc realpath; do
    command -v "$program" >/dev/null || { echo "missing baseline prerequisite: $program" >&2; exit 2; }
done
mkdir -p target/roadmap/00
report=$(mktemp -d "$root/target/roadmap/00/run-XXXXXXXX")
backend='null'
if command -v bwrap >/dev/null; then
    mkdir "$report/backend"
    cp -- "$(command -v bwrap)" "$report/backend/bwrap"
    chmod 555 "$report/backend/bwrap"
    backend_digest=$(sha256sum "$report/backend/bwrap"); backend_digest=${backend_digest%% *}
    backend=$(jq -n --arg path "$report/backend/bwrap" --arg sha256 "$backend_digest" \
        '{path:$path,sha256:$sha256}')
    export PATH="$report/backend:$PATH"
fi
members='[]'
for member in magi casper melchior balthasar; do
    commit=$(git -C "$member" rev-parse HEAD)
    dirty=$(git -C "$member" status --porcelain)
    members=$(jq --arg name "$member" --arg commit "$commit" --arg dirty "$dirty" \
        '. + [{name:$name, commit:$commit, dirty:($dirty != "")}]' <<< "$members")
done
configuration_hash() {
    local digest
    digest=$({
        sha256sum .make.lua scripts/{baseline.sh,receipt.jq,family.sh,acceptance.sh,acceptance-receipt.jq,cache-contract.jq,cache-policy.jq,scenarios/cache-contract.sh,tests/cache-contract.sh,tests/cache-policy.sh,prepare-advisories.sh,advisory-db.lock,select-binary.sh,run-family.sh} \
            magi/.make.lua casper/.make.lua melchior/.make.lua balthasar/.make.lua \
            casper/scripts/{test-cargo.sh,test-launcher-fixture.sh,gate-hermetic.sh}
        sha256sum scripts/preserve-binary.sh scripts/tests/preserve-binary.sh
        sha256sum scripts/cache-resume.jq scripts/scenarios/cache-resume.sh scripts/tests/cache-resume.sh
        sha256sum scripts/cache-discovery.jq scripts/scenarios/cache-discovery.sh scripts/tests/cache-discovery.sh
        sha256sum scripts/cache-layout.jq scripts/scenarios/cache-layout.sh scripts/tests/cache-layout.sh
        sha256sum scripts/cache-rules.jq scripts/scenarios/cache-rules.sh scripts/tests/cache-rules.sh
        sha256sum scripts/cache-mask.jq scripts/scenarios/cache-mask.sh scripts/tests/cache-mask.sh
        sha256sum scripts/overflow-routing.jq scripts/scenarios/overflow-routing.sh scripts/tests/overflow-routing.sh
        sha256sum melchior/examples/fake-provider.rs magi/crates/magi-testkit/examples/session-client.rs
        find melchior/examples/fake-provider -type f -print0 | sort -z | xargs -0 -r sha256sum
        find magi/config casper/config melchior/config balthasar/config -type f -print0 |
            sort -z | xargs -0 -r sha256sum
    } | sha256sum)
    printf '%s\n' "${digest%% *}"
}
configuration_digest=$(configuration_hash)
advisory_state() {
    if [[ ${CARGO_HOME:-} != "$root/target/advisories/"*/cargo ]]; then printf 'null\n'; return; fi
    local receipt="${CARGO_HOME%/cargo}/receipt.json" revision database
    revision=$(jq -er --arg home "$CARGO_HOME" \
        'select(.cargo_home == $home and .private_cache_copy == true) | .revision' "$receipt") || return 1
    [[ $revision == "$(jq -r .revision scripts/advisory-db.lock)" ]] || return 1
    database=$(jq -er .deny_database "$receipt") || return 1
    [[ $database == "$CARGO_HOME/advisory-dbs/"* ]] || return 1
    for database in "$CARGO_HOME/advisory-db" "$database"; do
        [[ $(git -C "$database" rev-parse HEAD) == "$revision" && -z $(git -C "$database" status --porcelain) ]] || return 1
    done
    jq -c '{url,revision,cargo_home,deny_database}' "$receipt"
}
advisories=$(advisory_state) || { echo 'prepared advisory input is missing, changed or unpinned' >&2; exit 2; }
toolchain=$(rustc -Vv 2>/dev/null || echo unavailable)
host=$(sed -n 's/^host: //p' <<< "$toolchain")
jq -n --arg started "$(date -u +%FT%TZ)" --arg commit "$(git rev-parse HEAD)" \
    --arg dirty "$(git status --porcelain)" --argjson members "$members" \
    --argjson backend "$backend" --argjson advisories "$advisories" \
    --arg configuration_digest "$configuration_digest" --arg toolchain "$toolchain" \
    '{schema:1, phase:"00", status:"NOT_RUN", started_at:$started, finished_at:null,
      root_commit:$commit, root_dirty:($dirty != ""), members:$members,
      configuration_digest:$configuration_digest,
      environment:{fixture_version:3, toolchain:$toolchain, profile:"owner recipe defaults",
                   required_backends:["bubblewrap","landlock"], selected_launcher:$backend,
                   advisory_snapshot:$advisories},
      commands:[], required_cases:(["runner","family","acceptance","verify"] |
          map({id:.,status:"NOT_RUN"})), skipped_cases:[], unexpected_processes:[],
      paid_requests:0, limitations:[]}' > "$report/receipt.json"
jq -e -f scripts/receipt.jq "$report/receipt.json" >/dev/null

finish() {
    local code=$?
    trap - EXIT
    if (( ${signal_code:-0} != 0 )); then code=$signal_code; fi
    if [[ $(configuration_hash) != "$configuration_digest" ]]; then
        code=1
        jq '.limitations += ["Configuration changed during baseline execution"]' \
            "$report/receipt.json" > "$report/next.json"
        mv "$report/next.json" "$report/receipt.json"
    fi
    if ! current_advisories=$(advisory_state) || [[ $current_advisories != "$advisories" ]]; then
        code=1
        jq '.limitations += ["Advisory snapshot changed during baseline execution"]' \
            "$report/receipt.json" > "$report/next.json"
        mv "$report/next.json" "$report/receipt.json"
    fi
    jq --arg finished "$(date -u +%FT%TZ)" --argjson code "$code" \
        '.finished_at = $finished | .active_command = null |
         .status = (if $code == 0 then "PASS" else "FAIL" end) |
         if $code == 130 or $code == 143 then .limitations += ["Baseline interrupted"] else . end' \
        "$report/receipt.json" > "$report/next.json"
    mv "$report/next.json" "$report/receipt.json"
    if ! jq -e -f scripts/receipt.jq "$report/receipt.json" >/dev/null; then
        code=1
        jq '.status = "FAIL" | .limitations += ["Receipt validation failed; inspect retained command logs"]' \
            "$report/receipt.json" > "$report/next.json"
        mv "$report/next.json" "$report/receipt.json"
    fi
    printf 'baseline: exit %s; evidence: %s\n' "$code" "$report"
    exit "$code"
}
trap finish EXIT
signal_code=0
active=
interrupt() {
    signal_code=$1
    if [[ -n $active ]]; then kill -TERM "$active" 2>/dev/null || true; fi
}
trap 'interrupt 130' INT
trap 'interrupt 143' TERM

gate_evidence() {
    local id=$1 code=$2 prefix directory mode evidence
    if [[ $id == acceptance ]]; then
        prefix="acceptance: exit $code; evidence: "
        directory=acceptance
    else
        mode=test
        [[ $id != verify ]] || mode=verify
        prefix="family $mode: exit $code; evidence: "
        directory=family
    fi
    evidence=$(sed -n "s|^$prefix||p" "$report/$id.log")
    [[ -n $evidence && $evidence != *$'\n'* ]] || return 1
    evidence=$(realpath -e -- "$evidence/summary.json") || return 1
    [[ $evidence == "$root/target/$directory/"* && $(wc -c < "$evidence") -le 16777216 ]] || return 1
    printf '%s\n' "$evidence"
}

retain_evidence() {
    local id=$1 evidence=$2
    jq --arg id "$id" --arg evidence "$evidence" '.evidence[$id] = $evidence' \
        "$report/receipt.json" > "$report/next.json"
    mv "$report/next.json" "$report/receipt.json"
    if [[ $id == family ]] && jq -e '.members | type == "array"' "$evidence" >/dev/null; then
        jq --arg host "$host" --slurpfile summary "$evidence" '
            .members |= map(. as $member | . +
                ([$summary[0].members[] | select(.name == $member.name)][0] // {}) |
                if .path then
                    ((.source_path // .path) | split("/target/") | last | split("/")) as $parts |
                    .profile = $parts[-2] | .target = (if ($parts | length) == 2 then $host else $parts[0] end)
                else . end) |
            .unexpected_processes += (if ($summary[0].leaked_processes // 0) > 0 then
                [{source:"family",count:$summary[0].leaked_processes}] else [] end)' \
            "$report/receipt.json" > "$report/next.json"
        mv "$report/next.json" "$report/receipt.json"
    fi
}
if [[ -n ${NERV_ONLY:-} ]]; then
    jq '.limitations += ["Focused acceptance selection cannot establish a complete baseline"] |
        (.required_cases[] | select(.id == "acceptance")) |=
            (.status = "BLOCKED" | .detail = "Unset NERV_ONLY for a complete baseline")' \
        "$report/receipt.json" > "$report/next.json"
    mv "$report/next.json" "$report/receipt.json"
    exit 2
fi

ids=(runner family acceptance verify)
recipes=(test-family-runner test-family acceptance verify)
for index in "${!ids[@]}"; do
    if (( signal_code != 0 )); then exit "$signal_code"; fi
    id=${ids[$index]}
    recipe=${recipes[$index]}
    jq --arg id "$id" '.status = "RUNNING" | .active_command = $id' \
        "$report/receipt.json" > "$report/next.json"
    mv "$report/next.json" "$report/receipt.json"
    started=$(date +%s%3N)
    set +e
    timeout --kill-after=30s 4h "$BASH" -c '
        oslo make "$1" 2>&1 | {
            head -c 33554432 > "$2"
            wc -c > "$3"
        }
        exit "${PIPESTATUS[0]}"
    ' bash "$recipe" "$report/$id.log" "$report/$id.discarded" &
    active=$!
    while :; do
        wait "$active"
        code=$?
        if ! kill -0 "$active" 2>/dev/null; then break; fi
    done
    active=
    if (( signal_code != 0 )); then code=$signal_code; fi
    set -e
    elapsed=$(( $(date +%s%3N) - started ))
    jq --arg id "$id" --arg recipe "$recipe" --arg log "$report/$id.log" \
        --argjson code "$code" --argjson elapsed "$elapsed" \
        '($code == 124 or $code == 130 or $code == 137 or $code == 143) as $interrupted |
         (if $code == 0 then "PASS" else "FAIL" end) as $status |
         .commands += [{id:$id, argv:["oslo","make",$recipe], log:$log,
             exit_code:$code, elapsed_ms:$elapsed, interrupted:$interrupted, status:$status}] |
         (.required_cases[] | select(.id == $id)).status = $status | .active_command = null' \
        "$report/receipt.json" > "$report/next.json"
    mv "$report/next.json" "$report/receipt.json"
    if (( code != 0 )); then
        if [[ $id != runner ]] && evidence=$(gate_evidence "$id" "$code"); then
            retain_evidence "$id" "$evidence"
        fi
        tail -40 "$report/$id.log"
        exit "$code"
    fi
    read -r discarded < "$report/$id.discarded"
    if (( discarded != 0 )); then
        jq --arg id "$id" '.limitations += [("Log exceeded 32 MiB for " + $id)]' \
            "$report/receipt.json" > "$report/next.json"
        mv "$report/next.json" "$report/receipt.json"
        exit 1
    fi
    if [[ $id != runner ]]; then
        evidence=$(gate_evidence "$id" "$code") || exit 1
        retain_evidence "$id" "$evidence"
        if ! jq -e -L "$root/scripts" --arg id "$id" 'include "acceptance-receipt";
            .status == "PASS" and .exit_code == 0 and (.members | length == 4) and
            (if $id == "acceptance" then
                current_acceptance_receipt
             else .leaked_processes == 0 and (.tests | length > 0) and
                .mode == (if $id == "family" then "test" else "verify" end) end)' \
            "$evidence" >/dev/null; then
            jq --arg id "$id" '.limitations += [("Rejected " + $id + " evidence; inspect referenced summary")]' \
                "$report/receipt.json" > "$report/next.json"
            mv "$report/next.json" "$report/receipt.json"
            exit 1
        fi
        jq --arg id "$id" --arg evidence "$evidence" \
            --slurpfile summary "$evidence" '
            .evidence[$id] = $evidence |
            if $id == "family" then .
            elif ([.members[] | {name,sha256}] | sort_by(.name)) !=
                 ([$summary[0].members[] | {name,sha256}] | sort_by(.name)) then
                error("selected family changed between baseline gates")
            else . end' "$report/receipt.json" > "$report/next.json"
        mv "$report/next.json" "$report/receipt.json"
        if [[ $id == verify ]]; then
            for member in magi casper melchior balthasar; do
                jq -Rn --arg member "$member" --arg log "${evidence%/*}/$member-verify.log" \
                    '[inputs | select(test("^cargo (audit|deny) is not installed; skipped$")) |
                      {id:($member + "::" + (split(" ")[1])), required:false, reason:., log:$log}]' \
                    < "${evidence%/*}/$member-verify.log" > "$report/skipped.json"
                jq --slurpfile skipped "$report/skipped.json" '.skipped_cases += $skipped[0]' \
                    "$report/receipt.json" > "$report/next.json"
                mv "$report/next.json" "$report/receipt.json"
            done
        fi
    fi
done
