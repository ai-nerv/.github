#!/usr/bin/env bash
set -euo pipefail

mode=${1:-test}
[[ $mode == test || $mode == verify ]] || { echo 'usage: family.sh test|verify' >&2; exit 2; }
root=$(cd -- "$(dirname -- "$0")/.." && pwd -P)
members=(magi casper melchior balthasar)
[[ -z ${CARGO_TARGET_DIR:-}${CARGO_BUILD_TARGET:-} ]] || {
    echo 'family builds require the member recipes default target directories and targets' >&2
    exit 2
}
for program in oslo jq timeout realpath sha256sum; do
    command -v "$program" >/dev/null || { echo "missing runner prerequisite: $program" >&2; exit 2; }
done
oslo=$(command -v oslo)
mkdir -p "$root/target/family"
report=$(mktemp -d "$root/target/family/run-XXXXXXXX")
scratch=$(mktemp -d /tmp/nf.XXXXXX)
started=$(date -u +%FT%TZ)
root_commit=$(git -C "$root" rev-parse --verify HEAD 2>/dev/null || echo uncommitted)
root_dirty=$(git -C "$root" status --porcelain 2>/dev/null || echo unavailable)
printf '[]\n' > "$report/members.json"
printf '[]\n' > "$report/tests.json"

finish() {
    local status=$? pid cwd leaked=0 attempt
    local -a remaining=() alive=()
    trap - EXIT
    for entry in /proc/[0-9]*/cwd; do
        cwd=$(readlink "$entry" 2>/dev/null) || continue
        [[ $cwd == "$scratch" || $cwd == "$scratch/"* ]] || continue
        pid=${entry#/proc/}; pid=${pid%/cwd}
        echo "leaked test process: $pid" >&2
        kill -TERM "$pid" 2>/dev/null || true
        remaining+=("$pid")
        leaked=$((leaked + 1))
    done
    for ((attempt = 0; attempt < 30 && ${#remaining[@]} > 0; attempt++)); do
        alive=()
        for pid in "${remaining[@]}"; do
            cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null) || continue
            [[ $cwd == "$scratch" || $cwd == "$scratch/"* ]] || continue
            alive+=("$pid")
            if (( attempt >= 20 )); then kill -KILL "$pid" 2>/dev/null || true; fi
        done
        remaining=("${alive[@]}")
        if (( ${#remaining[@]} > 0 )); then sleep 0.1; fi
    done
    if (( leaked )); then status=1; fi
    jq -n --arg started "$started" --arg mode "$mode" --argjson exit_code "$status" \
        --arg root_commit "$root_commit" --arg root_dirty "$root_dirty" \
        --argjson leaked_processes "$leaked" \
        --slurpfile members "$report/members.json" --slurpfile tests "$report/tests.json" \
        '{started:$started, mode:$mode, exit_code:$exit_code, leaked_processes:$leaked_processes,
          root:{commit:$root_commit, dirty:($root_dirty != "")},
          status:(if $exit_code == 0 then "PASS" else "FAIL" end),
          members:$members[0], tests:$tests[0]}' > "$report/summary.json"
    printf 'family %s: exit %s; evidence: %s\n' "$mode" "$status" "$report"
    rm -rf -- "$scratch"
    exit "$status"
}
trap finish EXIT
trap 'exit 130' INT
trap 'exit 143' TERM

selected=()
for member in "${members[@]}"; do
    [[ -f $root/$member/.make.lua ]] || { echo "missing checkout: $member" >&2; exit 1; }
    recipe=build
    [[ $member != balthasar ]] || recipe=build-host
    (cd "$root/$member" && "$oslo" make "$recipe") 2>&1 | tee "$report/$member-build.log"
    output=$(cd "$root/$member" && "$oslo" make family-path)
    path=$(printf '%s\n' "$output" | sed -n 's/^NERV_BINARY=//p')
    [[ -n $path && $path != *$'\n'* && $path == target/* ]] || {
        echo "invalid build path for $member: $output" >&2; exit 1;
    }
    binary=$(realpath -e "$root/$member/$path")
    [[ $binary == "$root/$member/target/"* && -x $binary ]] || {
        echo "missing or out-of-tree binary: $member" >&2; exit 1;
    }
    selected+=("$binary")
    sha=$(git -C "$root/$member" rev-parse --verify HEAD 2>/dev/null || echo uncommitted)
    dirty=$(git -C "$root/$member" status --porcelain)
    digest=$(sha256sum "$binary"); digest=${digest%% *}
    jq --arg name "$member" --arg path "$binary" --arg commit "$sha" \
        --arg dirty "$dirty" --arg sha256 "$digest" \
        '. + [{name:$name, path:$path, commit:$commit, dirty:($dirty != ""), sha256:$sha256}]' \
        "$report/members.json" > "$report/next.json"
    mv "$report/next.json" "$report/members.json"
done

family_path=
for binary in "${selected[@]}"; do family_path+="${binary%/*}:"; done
mkdir -p "$scratch"/{c,d,r,s,t,cache}
chmod 700 "$scratch/r"
clean=(env -i "PATH=$family_path$PATH" "HOME=$scratch" "XDG_CONFIG_HOME=$scratch/c"
    "XDG_DATA_HOME=$scratch/d" "XDG_RUNTIME_DIR=$scratch/r" "XDG_STATE_HOME=$scratch/s"
    "XDG_CACHE_HOME=$scratch/cache" "TMPDIR=$scratch/t" "MAGI_REQUIRE_LIVE=1"
    "MAGI_TEST_BINARY=${selected[0]}" "CASPER_REQUIRE_CONTAINMENT=1"
    "CARGO_HOME=${CARGO_HOME:-$HOME/.cargo}" "RUSTUP_HOME=${RUSTUP_HOME:-$HOME/.rustup}"
    "CARGO_TERM_COLOR=never" "CARGO_NET_OFFLINE=true" "RUST_BACKTRACE=1" "LC_ALL=C")
while IFS= read -r variable; do
    case "$variable" in
        NIX_*|CC|CXX|AR|LD|PKG_CONFIG*|MUSL_CC|CARGO_BUILD_JOBS|CARGO_TARGET_*_LINKER|SSL_CERT_FILE|TERM)
            clean+=("$variable=${!variable}") ;;
    esac
done < <(env | sed -n 's/^\([A-Za-z_][A-Za-z_0-9]*\)=.*/\1/p')

(cd "$root/casper" && "${clean[@]}" "$oslo" make configs) 2>&1 | tee "$report/casper-configs.log"

for i in "${!members[@]}"; do
    member=${members[$i]}
    "${clean[@]}" timeout 30 "${selected[$i]}" verbs > "$report/$member-verbs.json"
    required='["verbs","client"]'
    case "$member" in
        magi) required='["verbs","lua-api"]' ;;
        casper) required='["verbs","client","tools","run","surface"]' ;;
        melchior) required='["verbs","client","models","ask"]' ;;
        balthasar) required='["verbs","client","observe","replay","sessions"]' ;;
    esac
    jq -e --argjson required "$required" '. as $reply |
        .ok == true and .family == 1 and (.result | type == "array") and
        .n == (.result | length) and
        all($required[]; . as $verb | any($reply.result[]; .verb == $verb))' \
        "$report/$member-verbs.json" >/dev/null
done

for member in "${members[@]}"; do
    set +e
    (cd "$root/$member" && "${clean[@]}" timeout --kill-after=15s 30m "$oslo" make "$mode") 2>&1 | tee "$report/$member-$mode.log"
    result=${PIPESTATUS[0]}
    set -e
    jq -Rn --arg member "$member" '[inputs |
        select(test("^test .+ \\.\\.\\. (ok|FAILED|ignored)")) |
        {member:$member, result:.}]' < "$report/$member-$mode.log" > "$report/current-tests.json"
    jq -s '.[0] + .[1]' "$report/tests.json" "$report/current-tests.json" > "$report/next.json"
    mv "$report/next.json" "$report/tests.json"
    (( result == 0 )) || exit "$result"
    grep -q '^test result: ok\.' "$report/$member-$mode.log" || {
        echo "no test execution recorded for $member" >&2; exit 1;
    }
done

required_cases=(
    a_running_balthasar_lists_its_verbs
    a_second_run_picks_up_the_conversation_balthasar_kept
    a_headless_magi_publishes_the_screen_a_peer_attaches_to
    a_forked_child_belongs_to_the_run_that_forked_it
    a_forked_child_files_its_scratch_beside_its_parents_and_not_in_it
    agents_of_one_run_do_not_overwrite_each_others_transcript
    a_session_runs_against_a_memory_layer_that_is_not_balthasar
    every_request_is_one_balthasar_laid_out
    an_entry_survives_the_round_trip_unaltered
    every_sibling_declares_what_it_takes_in_a_shape_magi_can_read
    the_memory_tools_register_and_answer_when_balthasar_is_running
    the_agent_tool_reaches_another_session_through_melchior
    helper_retries::only_the_final_helper_attempt_reaches_durable_memory
    helper_retries::failed_helpers_report_failure_without_applying_their_partial_memory
    projection::stored_observations_never_acquire_the_rule_channel_after_restart
    truncated::truncated_calls_are_journalled_with_failed_results_and_never_executed
    two_clients_keep_each_prompt_and_answer_in_order
    interrupt_does_not_cancel_the_queued_replacement
    busy_reconfiguration_is_refused_and_disconnect_keeps_accepted_work
    a_stopped_worker_reports_each_accepted_prompt_instead_of_stranding_the_queue
    arrivals_and_declarations_share_the_prompt_boundary
    ownership::streaming_owns_its_entry_even_when_another_entry_arrives_later
    ownership::tool_results_amend_their_own_calls_after_later_entries_arrive
    in_process_resume_writes_only_to_the_selected_transcript
    in_process_resume_preserves_sparse_cursors_and_child_ownership
    resumed_lua_tools_and_watchers_use_the_selected_session
    resuming::tests::durable::late_helper_is_durable_only_in_a_before_b_is_published
    resuming::tests::pending_storage_failure_leaves_a_selected_and_every_unsent_row_pending
    resuming::tests::empty_or_refused_replay_preserves_the_original_binding_and_subscriptions
    resuming::tests::cancelling_a_flush_keeps_pending_entries_until_a_later_acknowledgment
)
for name in "${required_cases[@]}"; do
    grep -q "^test $name \.\.\. ok$" "$report/magi-$mode.log" || {
        echo "required family case did not pass: $name" >&2; exit 1;
    }
done

required_streaming=(
    mind::provider::sse::partitions::every_byte_split_preserves_unicode_fields_and_mixed_terminators
    mind::provider::client::streaming::every_http_byte_split_preserves_text_tool_arguments_usage_and_order
    mind::provider::client::streaming::malformed_tail_preserves_completed_events_and_usage_at_every_http_split
    mind::provider::client::streaming::malformed_utf8_retries_with_a_fresh_parser_and_adapter_state
    mind::provider::client::streaming::bounded_error_bodies_keep_status_retry_policy_and_hide_echoed_credentials
    mind::provider::client::streaming::stalled_and_oversized_errors_are_bounded_and_retry_only_when_appropriate
    mind::provider::client::streaming::successful_streams_outlive_control_deadlines_and_cancellation_closes_them
    mind::provider::control::tests::compressed_control_bodies_are_limited_after_decompression
    mind::provider::oauth::flow::bounded::oauth_control_reads_bound_headers_bodies_and_total_drip_time
    mind::provider::oauth::flow::bounded::oauth_oversized_invalid_and_error_responses_never_echo_secrets
    mind::provider::oauth::flow::bounded::cancelling_an_oauth_exchange_closes_its_connection
)
for name in "${required_streaming[@]}"; do
    grep -q "^test $name \.\.\. ok$" "$report/melchior-$mode.log" || {
        echo "required streaming case did not pass: $name" >&2; exit 1;
    }
done

required_containment=(
    pty::exiting::a_program_that_closes_its_pty_is_not_done_before_its_exit
    actual_interactive_surfaces_preserve_prompt_input_resize_and_exit
    writable_or_hardlinked_sandbox_launchers_are_refused
    captured_launcher_ignores_a_retargeted_path_symlink
    hardlinked_credentials_refuse_all_execution_doors
    nested_credential_symlinks_cannot_alias_a_granted_workspace
    safe_nested_credential_targets_and_directory_cycles_remain_usable
    credentials_created_after_spawn_remain_unreadable
    prepared_grants_cannot_be_retargeted_to_credentials
    jail_setup_descriptors_do_not_reach_commands_or_screens
    jailed_screens_preserve_input_resize_and_clean_exit
    jailed_commands_and_screens_can_compile_workspace_sources
    jailed_commands_and_screens_cannot_reach_host_unix_sockets
    default_and_missing_stores_and_broad_grants_are_safe
    socket_commands_keep_the_server_policy
    jailed_children_die_when_their_parent_is_killed
    isolation_off_is_explicit_and_failed_backends_do_not_fall_back
)
for name in "${required_containment[@]}"; do
    grep -q "^test $name \.\.\. ok$" "$report/casper-$mode.log" || {
        echo "required containment case did not pass: $name" >&2; exit 1;
    }
done

mkdir -p "$report/surface"
for backend in bubblewrap landlock; do
    capture="$root/casper/target/surface/$backend.jsonl"
    jq -e -s 'map(.stage) == ["opened", "typed", "resized", "interrupted", "exited"]' "$capture" >/dev/null
    cp -- "$capture" "$report/surface/$backend.jsonl"
done
