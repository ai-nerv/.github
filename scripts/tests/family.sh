#!/usr/bin/env bash
set -euo pipefail

root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
scratch=$(mktemp -d /tmp/nerv-runner-test.XXXXXX)
cleanup() {
    if [[ -f $scratch/project/leaked-pid ]]; then
        local pid
        read -r pid < "$scratch/project/leaked-pid"
        kill -KILL "$pid" 2>/dev/null || true
    fi
    rm -rf -- "$scratch"
}
trap cleanup EXIT
mkdir -p "$scratch/project/scripts" "$scratch/bin" "$scratch/old"
cp "$root/scripts/family.sh" "$scratch/project/scripts/family.sh"
for member in magi casper melchior balthasar; do
    mkdir -p "$scratch/project/$member/target/release"
    touch "$scratch/project/$member/.make.lua"
    git -C "$scratch/project/$member" init -q
done

printf '#!%s\n' "$BASH" > "$scratch/bin/oslo"
cat >> "$scratch/bin/oslo" <<'SH'
set -euo pipefail
name=${PWD##*/}
case "$2" in
    build|build-host)
        [[ ! -e ../omit-$name ]] || exit 0
        cat > "target/release/$name" <<'BIN'
#!/bin/sh
printf '%s\n' '{"ok":true,"family":1,"n":11,"result":[{"verb":"verbs"},{"verb":"client"},{"verb":"lua-api"},{"verb":"tools"},{"verb":"run"},{"verb":"surface"},{"verb":"models"},{"verb":"ask"},{"verb":"observe"},{"verb":"replay"},{"verb":"sessions"}]}'
BIN
        if [[ -e ../old-$name ]]; then
            printf '#!/bin/sh\necho "{\"ok\":false}"\n' > "target/release/$name"
        fi
        chmod +x "target/release/$name"
        ;;
    family-path) echo NERV_BINARY=target/release/$name ;;
    configs)
        [[ $name == casper && $XDG_CONFIG_HOME == /tmp/nf.*/c ]]
        mkdir -p "$XDG_CONFIG_HOME/casper"
        touch "$XDG_CONFIG_HOME/casper/tools.lua"
        ;;
    test|verify)
        [[ ${MAGI_REQUIRE_LIVE:-} == 1 ]]
        [[ ${MAGI_TEST_BINARY:-} == "$(realpath ../magi/target/release/magi)" ]]
        [[ -z ${OPENAI_API_KEY:-}${MAGI_API_SOCKET:-}${BALTHASAR_AGENT:-} ]]
        [[ $HOME == /tmp/nf.* && $XDG_CONFIG_HOME == "$HOME/c" ]]
        [[ -f $XDG_CONFIG_HOME/casper/tools.lua ]]
        [[ $(command -v balthasar) == "$PWD/../balthasar/target/release/balthasar" || $(realpath "$(command -v balthasar)") == "$(realpath ../balthasar/target/release/balthasar)" ]]
        [[ ! -e ../fail-test ]] || exit 37
        if [[ $name == magi && -e ../leak-test ]]; then
            (cd "$HOME"; trap '' TERM; exec sleep 600) >/dev/null 2>&1 &
            echo "$!" > ../leaked-pid
        fi
        echo 'test synthetic_family_case ... ok'
        if [[ $name == casper ]]; then
            mkdir -p target/surface
            rm -f target/surface/bubblewrap.jsonl target/surface/landlock.jsonl
            if [[ ! -e ../omit-surface ]]; then
                for backend in bubblewrap landlock; do
                    for stage in opened typed resized interrupted exited; do
                        printf '{"stage":"%s"}\n' "$stage" >> "target/surface/$backend.jsonl"
                    done
                done
            fi
        fi
        if [[ $name == casper && ! -e ../omit-casper-case ]]; then
            for case in pty::exiting::a_program_that_closes_its_pty_is_not_done_before_its_exit \
                actual_interactive_surfaces_preserve_prompt_input_resize_and_exit \
                writable_or_hardlinked_sandbox_launchers_are_refused \
                captured_launcher_ignores_a_retargeted_path_symlink \
                hardlinked_credentials_refuse_all_execution_doors \
                nested_credential_symlinks_cannot_alias_a_granted_workspace \
                safe_nested_credential_targets_and_directory_cycles_remain_usable \
                credentials_created_after_spawn_remain_unreadable \
                prepared_grants_cannot_be_retargeted_to_credentials \
                jail_setup_descriptors_do_not_reach_commands_or_screens \
                jailed_screens_preserve_input_resize_and_clean_exit \
                jailed_commands_and_screens_can_compile_workspace_sources \
                jailed_commands_and_screens_cannot_reach_host_unix_sockets \
                default_and_missing_stores_and_broad_grants_are_safe \
                socket_commands_keep_the_server_policy \
                jailed_children_die_when_their_parent_is_killed \
                isolation_off_is_explicit_and_failed_backends_do_not_fall_back; do
                echo "test $case ... ok"
            done
        fi
        if [[ ! -e ../omit-case ]]; then
            for name in a_running_balthasar_lists_its_verbs \
                a_second_run_picks_up_the_conversation_balthasar_kept \
                a_headless_magi_publishes_the_screen_a_peer_attaches_to \
                a_forked_child_belongs_to_the_run_that_forked_it \
                a_forked_child_files_its_scratch_beside_its_parents_and_not_in_it \
                agents_of_one_run_do_not_overwrite_each_others_transcript \
                a_session_runs_against_a_memory_layer_that_is_not_balthasar \
                every_request_is_one_balthasar_laid_out \
                an_entry_survives_the_round_trip_unaltered \
                every_sibling_declares_what_it_takes_in_a_shape_magi_can_read \
                the_memory_tools_register_and_answer_when_balthasar_is_running \
                the_agent_tool_reaches_another_session_through_melchior \
                helper_retries::only_the_final_helper_attempt_reaches_durable_memory \
                helper_retries::failed_helpers_report_failure_without_applying_their_partial_memory \
                projection::stored_observations_never_acquire_the_rule_channel_after_restart \
                truncated::truncated_calls_are_journalled_with_failed_results_and_never_executed \
                two_clients_keep_each_prompt_and_answer_in_order \
                interrupt_does_not_cancel_the_queued_replacement \
                busy_reconfiguration_is_refused_and_disconnect_keeps_accepted_work \
                a_stopped_worker_reports_each_accepted_prompt_instead_of_stranding_the_queue \
                arrivals_and_declarations_share_the_prompt_boundary \
                ownership::streaming_owns_its_entry_even_when_another_entry_arrives_later \
                ownership::tool_results_amend_their_own_calls_after_later_entries_arrive \
                in_process_resume_writes_only_to_the_selected_transcript \
                in_process_resume_preserves_sparse_cursors_and_child_ownership \
                resumed_lua_tools_and_watchers_use_the_selected_session \
                resuming::tests::durable::late_helper_is_durable_only_in_a_before_b_is_published \
                resuming::tests::pending_storage_failure_leaves_a_selected_and_every_unsent_row_pending \
                resuming::tests::empty_or_refused_replay_preserves_the_original_binding_and_subscriptions \
                resuming::tests::cancelling_a_flush_keeps_pending_entries_until_a_later_acknowledgment; do
                echo "test $name ... ok"
            done
        fi
        if [[ ${PWD##*/} == melchior && ! -e ../omit-streaming-case ]]; then
            for case in \
                mind::provider::sse::partitions::every_byte_split_preserves_unicode_fields_and_mixed_terminators \
                mind::provider::client::streaming::every_http_byte_split_preserves_text_tool_arguments_usage_and_order \
                mind::provider::client::streaming::malformed_tail_preserves_completed_events_and_usage_at_every_http_split \
                mind::provider::client::streaming::malformed_utf8_retries_with_a_fresh_parser_and_adapter_state \
                mind::provider::client::streaming::bounded_error_bodies_keep_status_retry_policy_and_hide_echoed_credentials \
                mind::provider::client::streaming::stalled_and_oversized_errors_are_bounded_and_retry_only_when_appropriate \
                mind::provider::client::streaming::successful_streams_outlive_control_deadlines_and_cancellation_closes_them \
                mind::provider::control::tests::compressed_control_bodies_are_limited_after_decompression \
                mind::provider::oauth::flow::bounded::oauth_control_reads_bound_headers_bodies_and_total_drip_time \
                mind::provider::oauth::flow::bounded::oauth_oversized_invalid_and_error_responses_never_echo_secrets \
                mind::provider::oauth::flow::bounded::cancelling_an_oauth_exchange_closes_its_connection; do
                echo "test $case ... ok"
            done
        fi
        echo 'test result: ok. 1 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out'
        ;;
    *) exit 98 ;;
esac
SH
chmod +x "$scratch/bin/oslo"
printf '#!/bin/sh\nexit 99\n' > "$scratch/old/balthasar"
chmod +x "$scratch/old/balthasar"

run() {
    env PATH="$scratch/bin:$scratch/old:$PATH" OPENAI_API_KEY=synthetic-secret \
        MAGI_API_SOCKET=/synthetic/foreign.sock BALTHASAR_AGENT=foreign \
        "$BASH" "$scratch/project/scripts/family.sh" "$1" > "$scratch/output" 2>&1
}

for mode in test verify; do
    if ! run "$mode"; then cat "$scratch/output"; exit 1; fi
    report=$(sed -n 's/.*evidence: //p' "$scratch/output" | tail -1)
    jq -e '.status == "PASS" and .exit_code == 0 and (.members | length == 4) and (.tests | length > 0)' \
        "$report/summary.json" >/dev/null
done
for failure in omit-balthasar old-casper fail-test omit-case omit-casper-case omit-streaming-case omit-surface leak-test; do
    touch "$scratch/project/$failure"
    if [[ $failure == omit-balthasar ]]; then
        rm -- "$scratch/project/balthasar/target/release/balthasar"
    fi
    if run test; then
        echo "runner accepted $failure" >&2
        exit 1
    fi
    report=$(sed -n 's/.*evidence: //p' "$scratch/output" | tail -1)
    jq -e '.status == "FAIL" and .exit_code != 0' "$report/summary.json" >/dev/null
    if [[ $failure == leak-test ]]; then
        read -r pid < "$scratch/project/leaked-pid"
        if readlink "/proc/$pid/cwd" >/dev/null 2>&1; then
            echo 'runner left its leaked process alive' >&2
            exit 1
        fi
        jq -e '.leaked_processes == 1' "$report/summary.json" >/dev/null
        rm -- "$scratch/project/leaked-pid"
    fi
    rm -- "$scratch/project/$failure"
done
echo 'family runner: isolation, stale PATH, missing/incompatible binary, failed/missing cases, reports: PASS'
