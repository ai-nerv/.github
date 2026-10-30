#!/usr/bin/env bash
set -euo pipefail
root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
scratch=$(mktemp -d /tmp/nerv-receipt-test.XXXXXX)
trap 'rm -rf -- "$scratch"' EXIT
trap 'echo "receipt: line $LINENO failed: $BASH_COMMAND" >&2; [[ -f $scratch/out ]] && cat "$scratch/out" >&2' ERR
jq -n '{schema:1, phase:"00", status:"PASS", started_at:"2026-10-17T00:00:00Z",
    finished_at:"2026-10-17T00:01:00Z", root_commit:"fixture", root_dirty:false,
    configuration_digest:("a" * 64),
    environment:{fixture_version:1, toolchain:"fixture", profile:"release",
                 selected_launcher:{path:"/fixture/bwrap",sha256:("b" * 64)},
                 required_backends:["bubblewrap","landlock"]},
    members:(["magi","casper","melchior","balthasar"] |
        map({name:.,commit:"fixture",dirty:false,path:("/fixture/target/release/" + .),
            sha256:("b" * 64),profile:"release",target:"fixture-linux"})),
    commands:(["runner","family","acceptance","verify"] | map({id:.,argv:["oslo","make",
        ({runner:"test-family-runner",family:"test-family",acceptance:"acceptance",verify:"verify"}[.])],
        log:(. + ".log"),exit_code:0,elapsed_ms:1,interrupted:false,status:"PASS"})),
    required_cases:(["runner","family","acceptance","verify"] | map({id:.,status:"PASS"})),
    skipped_cases:[],unexpected_processes:[],paid_requests:0,limitations:[]}' > "$scratch/pass.json"
validate() { jq -e -f "$root/scripts/receipt.jq" "$1" >/dev/null 2>&1; }
validate "$scratch/pass.json"
jq '.environment.fixture_version = 2' "$scratch/pass.json" > "$scratch/v2.json"
validate "$scratch/v2.json"
jq '.environment.fixture_version = 3' "$scratch/pass.json" > "$scratch/v3.json"
validate "$scratch/v3.json"
jq -n -L "$root/scripts" 'include "acceptance-receipt";
    {kind:"deterministic",fixture_version:2,not_verified:0} | .scenarios=(acceptance_cases|map({id:.,verdict:"PASS"}))' > "$scratch/acceptance-v2.json"
jq -e -L "$root/scripts" 'include "acceptance-receipt"; valid_acceptance_receipt' "$scratch/acceptance-v2.json" >/dev/null
if jq -e -L "$root/scripts" 'include "acceptance-receipt"; current_acceptance_receipt' "$scratch/acceptance-v2.json" >/dev/null; then
    echo 'legacy evidence substituted for current acceptance' >&2; exit 1
fi
jq '.fixture_version=3 | .scope="full" | .selected_scenario="" | .scenarios += [{id:"cache-contract",verdict:"PASS"}]' \
    "$scratch/acceptance-v2.json" > "$scratch/acceptance-v3.json"
jq -e -L "$root/scripts" 'include "acceptance-receipt"; current_acceptance_receipt' "$scratch/acceptance-v3.json" >/dev/null
for change in '.scenarios |= .[:-1]' '.scope="scenario"' '.fixture_version=4'; do
    jq "$change" "$scratch/acceptance-v3.json" > "$scratch/acceptance-bad.json"
    if jq -e -L "$root/scripts" 'include "acceptance-receipt"; valid_acceptance_receipt' "$scratch/acceptance-bad.json" >/dev/null; then
        echo "invalid acceptance accepted: $change" >&2; exit 1
    fi
done
for change in \
    'del(.required_cases)' \
    '.required_cases = []' \
    '.required_cases |= .[:-1]' \
    '.required_cases[1] = .required_cases[0]' \
    '.commands[1] = .commands[0]' \
    '.commands = []' \
    '.commands[0].argv = ["oslo","make","install"]' \
    '.commands[0].exit_code = 37' \
    '.commands[0].interrupted = true' \
    '.commands[0].status = "FAIL"' \
    '.commands[0].exit_code = 130 | .commands[0].status = "FAIL" | .commands[0].interrupted = true | .required_cases[0].status = "FAIL"' \
    '.required_cases[0].status = "NOT_RUN"' \
    '.schema = 2' \
    '.environment.fixture_version = 999' \
    '.phase = "01"' \
    '.finished_at = null' \
    '.active_command = "family"' \
    '.members[0].sha256 = "missing"' \
    '.members[1] = .members[0]' \
    '.environment.selected_launcher = null' \
    '.skipped_cases = ["required"]' \
    '.skipped_cases = [{id:"required",required:true,reason:"missing",log:"fixture.log"}]' \
    '.unexpected_processes = [123]' \
    '.paid_requests = 1'; do
    jq "$change" "$scratch/pass.json" > "$scratch/bad.json"
    if validate "$scratch/bad.json"; then echo "receipt accepted: $change" >&2; exit 1; fi
done
printf '{"schema":1,' > "$scratch/partial.json"
if validate "$scratch/partial.json" || validate "$scratch/missing.json"; then exit 1; fi
jq '.status = "NOT_RUN" | .finished_at = null | .commands = [] |
    .required_cases[].status = "NOT_RUN"' "$scratch/pass.json" > "$scratch/pending.json"
validate "$scratch/pending.json"
jq '.status = "RUNNING" | .active_command = "runner"' "$scratch/pending.json" > "$scratch/running.json"
validate "$scratch/running.json"
jq '.status = "FAIL" | .commands[0].exit_code = 143 | .commands[0].interrupted = true |
    .commands[0].status = "FAIL" | .required_cases[0].status = "FAIL"' \
    "$scratch/pass.json" > "$scratch/failed.json"
validate "$scratch/failed.json"
jq '.skipped_cases = [{id:"magi::audit",required:false,reason:"not installed",log:"fixture.log"}]' \
    "$scratch/pass.json" > "$scratch/optional.json"
validate "$scratch/optional.json"
mkdir -p "$scratch/project/scripts" "$scratch/bin"
mkdir -p "$scratch/project/casper/scripts"
touch "$scratch/project/casper/scripts/"{test-cargo.sh,test-launcher-fixture.sh,gate-hermetic.sh}
cp "$root/scripts/baseline.sh" "$root/scripts/receipt.jq" "$root/scripts/acceptance-receipt.jq" "$scratch/project/scripts/"
for file in .make.lua scripts/family.sh scripts/acceptance.sh scripts/prepare-advisories.sh scripts/advisory-db.lock scripts/select-binary.sh scripts/run-family.sh magi/.make.lua casper/.make.lua melchior/.make.lua balthasar/.make.lua melchior/examples/fake-provider.rs magi/crates/magi-testkit/examples/session-client.rs; do
    mkdir -p "$(dirname "$scratch/project/$file")"
    touch "$scratch/project/$file"
done
for file in scripts/preserve-binary.sh scripts/tests/preserve-binary.sh scripts/cache-contract.jq scripts/cache-policy.jq scripts/scenarios/cache-contract.sh scripts/tests/cache-contract.sh scripts/tests/cache-policy.sh melchior/examples/fake-provider/anthropic.rs melchior/examples/fake-provider/anthropic/tests.rs; do
    mkdir -p "$(dirname "$scratch/project/$file")"
    touch "$scratch/project/$file"
done
for member in magi casper melchior balthasar; do mkdir -p "$scratch/project/$member/config"; done
mkdir -p "$scratch/project/scripts/scenarios" "$scratch/project/scripts/tests"
touch "$scratch/project/scripts/cache-resume.jq" "$scratch/project/scripts/scenarios/cache-resume.sh" "$scratch/project/scripts/tests/cache-resume.sh"
touch "$scratch/project/scripts/cache-discovery.jq" "$scratch/project/scripts/scenarios/cache-discovery.sh" "$scratch/project/scripts/tests/cache-discovery.sh"
touch "$scratch/project/scripts/cache-layout.jq" "$scratch/project/scripts/scenarios/cache-layout.sh" "$scratch/project/scripts/tests/cache-layout.sh"
touch "$scratch/project/scripts/cache-rules.jq" "$scratch/project/scripts/scenarios/cache-rules.sh" "$scratch/project/scripts/tests/cache-rules.sh"
touch "$scratch/project/scripts/cache-mask.jq" "$scratch/project/scripts/scenarios/cache-mask.sh" "$scratch/project/scripts/tests/cache-mask.sh"
touch "$scratch/project/scripts/overflow-routing.jq" "$scratch/project/scripts/scenarios/overflow-routing.sh" "$scratch/project/scripts/tests/overflow-routing.sh"
touch "$scratch/project/melchior/examples/fake-provider/refusal.rs"
jq '.members' "$scratch/pass.json" > "$scratch/project/selected.json"
printf '#!/bin/sh\ncase "$*" in *rev-parse*) echo fixture ;; esac\n' > "$scratch/bin/git"
printf '#!/bin/sh\necho rustc-fixture\necho "host: fixture-linux"\n' > "$scratch/bin/rustc"
printf '#!/bin/sh\nexit 0\n' > "$scratch/bin/bwrap"
ln "$scratch/bin/bwrap" "$scratch/bin/aliased-bwrap"
printf '#!%s\n' "$BASH" > "$scratch/bin/oslo"
cat >> "$scratch/bin/oslo" <<'SH'
set -euo pipefail
if [[ $2 == test-family-runner && -f fail ]]; then exit 37; fi
if [[ $2 == test-family-runner && -f interrupt ]]; then exit 143; fi
if [[ $2 == test-family-runner && -f oversized-log ]]; then
    head -c 33554433 /dev/zero
    exit 0
fi
if [[ $2 == test-family-runner && -f signal ]]; then
    echo "$BASHPID" > worker-pid
    echo ready > ready
    exec sleep 5
fi
if [[ $2 == test-family-runner ]]; then exit 0; fi
directory=family
mode=test
[[ $2 != verify ]] || mode=verify
if [[ $2 == acceptance ]]; then directory=acceptance; fi
evidence="$PWD/target/$directory/fixture-$2"
mkdir -p "$evidence"
jq -n --arg mode "$mode" --slurpfile members selected.json \
    '{status:"PASS",exit_code:0,leaked_processes:0,mode:$mode,members:$members[0],
      tests:[{result:"test fixture ... ok"}],kind:"deterministic",fixture_version:3,scope:"full",selected_scenario:"",not_verified:0,
      scenarios:(["basic-coding-loop","multi-client","resume-and-restart","memory-process-loss",
        "memory-absent-at-startup","tool-containment","retry-transport-failures","context-pressure",
        "helper-modes","cross-session-memory","agent-coordination","safety-modes","contradictions","usage-accounting","cache-contract"] |
        map({id:.,verdict:"PASS"}))}' > "$evidence/summary.json"
if [[ -f preserved || -f preserved-target || -f preserved-debug ]]; then
    jq --arg evidence "$evidence" '.members |= map(.source_path = .path |
        .path = ($evidence + "/bin/" + .name))' "$evidence/summary.json" > "$evidence/next.json"
    mv "$evidence/next.json" "$evidence/summary.json"
    if [[ -f preserved-target ]]; then
        jq '.members[].source_path |= sub("/target/release/"; "/target/custom-linux/release/")' \
            "$evidence/summary.json" > "$evidence/next.json"
        mv "$evidence/next.json" "$evidence/summary.json"
    elif [[ -f preserved-debug ]]; then
        jq '.members[].source_path |= sub("/release/"; "/debug/")' \
            "$evidence/summary.json" > "$evidence/next.json"
        mv "$evidence/next.json" "$evidence/summary.json"
    fi
fi
if [[ $2 == test-family && -f incompatible ]]; then echo '{}' > "$evidence/summary.json"; fi
if [[ $2 == test-family && -f missing-evidence ]]; then rm -- "$evidence/summary.json"; fi
if [[ $2 == test-family && -f escaped-evidence ]]; then
    cp "$evidence/summary.json" external-summary.json
    rm -- "$evidence/summary.json"
    ln -s "$PWD/external-summary.json" "$evidence/summary.json"
fi
if [[ $2 == test-family && -f oversized-evidence ]]; then
    jq '.padding = ("x" * 16777216)' "$evidence/summary.json" > "$evidence/next.json"
    mv "$evidence/next.json" "$evidence/summary.json"
fi
if [[ $2 == acceptance && -f omitted-scenario ]]; then
    jq '.scenarios |= .[:-1]' "$evidence/summary.json" > "$evidence/next.json"
    mv "$evidence/next.json" "$evidence/summary.json"
fi
if [[ $2 == acceptance && -f legacy-acceptance ]]; then
    jq '.fixture_version=2 | del(.scope,.selected_scenario) | .scenarios |= map(select(.id!="cache-contract"))' "$evidence/summary.json" > "$evidence/next.json"
    mv "$evidence/next.json" "$evidence/summary.json"
fi
if [[ $2 == acceptance && -f scoped-acceptance ]]; then
    jq '.scope="scenario" | .selected_scenario="cache-contract"' "$evidence/summary.json" > "$evidence/next.json"
    mv "$evidence/next.json" "$evidence/summary.json"
fi
if [[ $2 == verify && -f drift ]]; then
    jq '.members[0].sha256 = ("c" * 64)' "$evidence/summary.json" > "$evidence/next.json"
    mv "$evidence/next.json" "$evidence/summary.json"
fi
if [[ $2 == verify && -f config-drift ]]; then echo changed > casper/config/fixture.lua; fi
if [[ $2 == verify && -f launcher-drift ]]; then echo changed > casper/scripts/test-cargo.sh; fi
if [[ $2 == verify && -f family-launch-drift ]]; then echo changed > scripts/run-family.sh; fi
if [[ $2 == verify && -f codec-drift ]]; then echo changed > melchior/examples/fake-provider/anthropic.rs; fi
if [[ $2 == verify && -f cache-verifier-drift ]]; then echo changed > scripts/cache-contract.jq; fi
if [[ $2 == verify ]]; then
    for member in magi casper melchior balthasar; do
        echo 'cargo audit is not installed; skipped' > "$evidence/$member-verify.log"
    done
fi
if [[ $2 == test-family && -f failed-family ]]; then
    jq '.status = "FAIL" | .exit_code = 37 | .leaked_processes = 1 | .members |= .[:2]' \
        "$evidence/summary.json" > "$evidence/next.json"
    mv "$evidence/next.json" "$evidence/summary.json"
    echo "family test: exit 37; evidence: $evidence"
    exit 37
fi
if [[ $2 == acceptance ]]; then echo "acceptance: exit 0; evidence: $evidence"
else echo "family $mode: exit 0; evidence: $evidence"; fi
SH
chmod +x "$scratch/bin/"*
for mode in pass preserved preserved-target preserved-debug fail interrupt failed-family oversized-log incompatible missing-evidence escaped-evidence oversized-evidence omitted-scenario legacy-acceptance scoped-acceptance drift config-drift launcher-drift family-launch-drift codec-drift cache-verifier-drift; do
    if [[ $mode != pass ]]; then touch "$scratch/project/$mode"; fi
    code=0
    env -u NERV_ONLY PATH="$scratch/bin:$PATH" "$BASH" "$scratch/project/scripts/baseline.sh" > "$scratch/out" 2>&1 || code=$?
    evidence=$(sed -n 's/^baseline: exit .*; evidence: //p' "$scratch/out")
    if [[ -z $evidence ]]; then cat "$scratch/out"; exit 1; fi
    validate "$evidence/receipt.json"
    if [[ $mode == pass || $mode == preserved || $mode == preserved-target ]]; then
        if (( code != 0 )); then cat "$scratch/out"; cat "$evidence/receipt.json"; exit 1; fi
        [[ $code == 0 ]]
        jq -e '.status == "PASS" and (.evidence | length == 3) and
            (.skipped_cases | length == 4 and all(.[]; .required == false))' "$evidence/receipt.json" >/dev/null
        launcher=$(jq -r '.environment.selected_launcher.path' "$evidence/receipt.json")
        [[ $(stat -c %h "$launcher") == 1 && -x $launcher ]]
        digest=$(sha256sum "$launcher"); digest=${digest%% *}
        jq -e --arg digest "$digest" '.environment.selected_launcher.sha256 == $digest' \
            "$evidence/receipt.json" >/dev/null
        if [[ $mode != pass ]]; then
            target=fixture-linux
            [[ $mode != preserved-target ]] || target=custom-linux
            jq -e --arg target "$target" 'all(.members[];
                (.path | contains("/bin/")) and (.source_path | contains("/target/")) and
                .profile == "release" and .target == $target and .sha256 == ("b" * 64))' \
                "$evidence/receipt.json" >/dev/null
            rm -- "$scratch/project/$mode"
        fi
    else
        [[ $code != 0 ]]
        jq -e '.status == "FAIL"' "$evidence/receipt.json" >/dev/null
        if [[ $mode == preserved-debug ]]; then
            jq -e 'all(.members[]; .profile == "debug") and
                any(.limitations[]; contains("Receipt validation failed"))' \
                "$evidence/receipt.json" >/dev/null
        fi
        if [[ $mode == oversized-log ]]; then
            [[ $(stat -c %s "$evidence/runner.log") == 33554432 ]]
            jq -e '.commands[0].exit_code == 0 and
                any(.limitations[]; contains("Log exceeded 32 MiB"))' "$evidence/receipt.json" >/dev/null
        fi
        if [[ $mode == failed-family ]]; then
            [[ $code == 37 ]]
            jq -e '(.members | length == 4) and ([.members[] | select(.sha256 != null)] | length == 2) and
                .unexpected_processes == [{source:"family",count:1}] and .commands[1].exit_code == 37 and
                (.evidence.family | endswith("summary.json"))' "$evidence/receipt.json" >/dev/null
        fi
        if [[ $mode == escaped-evidence || $mode == missing-evidence || $mode == oversized-evidence ]]; then
            jq -e '.commands[1].exit_code == 0 and .evidence.family == null' \
                "$evidence/receipt.json" >/dev/null
        fi
        if [[ $mode == escaped-evidence ]]; then
            rm -- "$scratch/project/target/family/fixture-test-family/summary.json"
        fi
        if [[ $mode == fail || $mode == interrupt ]]; then
            expected=37
            [[ $mode != interrupt ]] || expected=143
            jq -e --argjson expected "$expected" '.commands[0].exit_code == $expected and
                (.required_cases | map(select(.status == "NOT_RUN")) | length == 3)' \
                "$evidence/receipt.json" >/dev/null
        fi
        if [[ $mode == launcher-drift || $mode == family-launch-drift || $mode == config-drift || $mode == codec-drift || $mode == cache-verifier-drift ]]; then
            jq -e 'any(.limitations[]; . == "Configuration changed during baseline execution")' \
                "$evidence/receipt.json" >/dev/null
        fi
        rm -- "$scratch/project/$mode"
    fi
done
code=0
PATH="$scratch/bin:$PATH" NERV_ONLY=synthetic "$BASH" "$scratch/project/scripts/baseline.sh" \
    > "$scratch/out" 2>&1 || code=$?
[[ $code == 2 ]]
evidence=$(sed -n 's/^baseline: exit .*; evidence: //p' "$scratch/out")
validate "$evidence/receipt.json"
jq -e '.status == "FAIL" and (.commands | length == 0) and
    any(.required_cases[]; .id == "acceptance" and .status == "BLOCKED")' \
    "$evidence/receipt.json" >/dev/null
touch "$scratch/project/signal"
mkfifo "$scratch/project/ready"
code=0
env -u NERV_ONLY PATH="$scratch/bin:$PATH" timeout --kill-after=2s 20s "$BASH" -euc '
    "$BASH" "$1/scripts/baseline.sh" &
    supervisor=$!
    IFS= read -r -t 10 ready < "$1/ready"
    kill -TERM "$supervisor"
    wait "$supervisor"
' bash "$scratch/project" > "$scratch/out" 2>&1 || code=$?
[[ $code == 143 ]]
evidence=$(sed -n 's/^baseline: exit .*; evidence: //p' "$scratch/out")
validate "$evidence/receipt.json"
jq -e '.status == "FAIL" and .commands[0].exit_code == 143 and
    .commands[0].interrupted == true' "$evidence/receipt.json" >/dev/null
read -r worker < "$scratch/project/worker-pid"
if readlink "/proc/$worker/cwd" >/dev/null 2>&1; then
    kill -KILL "$worker" 2>/dev/null || true
    echo 'interrupted baseline left its worker alive' >&2
    exit 1
fi
echo 'receipt: missing, empty, duplicate, partial, incompatible, interrupted and failed results: PASS'
