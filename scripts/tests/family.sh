#!/usr/bin/env bash
set -euo pipefail
mode=${1:-all}
[[ $mode == all || $mode == --leak-only || $mode == --selection-only ]] || { echo 'usage: family.sh [--leak-only|--selection-only]' >&2; exit 2; }

root=$(cd -- "$(dirname -- "$0")/../.." && pwd -P)
scratch=$(mktemp -d /tmp/nerv-runner-test.XXXXXX)
cleanup() {
    local status=$? pid
    if (( status != 0 )); then
        local evidence="$root/target/roadmap/04/runner-failure-${scratch##*/}"
        mkdir -p "$evidence" || true
        cp "$scratch/output" "$evidence/output.log" 2>/dev/null || true
        if [[ -n ${report:-} && -f $report/summary.json ]]; then
            cp "$report/summary.json" "$evidence/summary.json" || true
        fi
        if [[ -f $scratch/project/leaked-pid ]]; then
            read -r pid < "$scratch/project/leaked-pid"
            { cat "/proc/$pid/stat"; readlink "/proc/$pid/cwd"; } > "$evidence/leaked-process.log" 2>&1 || true
        fi
        echo "runner fixture failure evidence: $evidence" >&2
    fi
    if [[ -f $scratch/project/leaked-pid ]]; then
        read -r pid < "$scratch/project/leaked-pid"
        kill -KILL "$pid" 2>/dev/null || true
    fi
    rm -rf -- "$scratch"
}
trap cleanup EXIT
mkdir -p "$scratch/project/scripts" "$scratch/bin" "$scratch/old"
cp "$root/scripts/family.sh" "$scratch/project/scripts/family.sh"
cp "$root/scripts/preserve-binary.sh" "$scratch/project/scripts/preserve-binary.sh"
cp "$root/scripts/select-binary.sh" "$scratch/project/scripts/select-binary.sh"
cp "$root/scripts/selected-tools.sh" "$scratch/project/scripts/selected-tools.sh"
cp "$root/scripts/context-proof.sh" "$scratch/project/scripts/context-proof.sh"
for member in magi casper melchior balthasar; do
    mkdir -p "$scratch/project/$member/target/release"
    touch "$scratch/project/$member/.make.lua"
    git -C "$scratch/project/$member" init -q
done
mkdir -p "$scratch/project/casper/config"
printf '%s\n' '-- selected fixture declarations' > "$scratch/project/casper/config/tools.lua"

cat > "$scratch/project/native-cases" <<'CASES'
magi native_turn_events_preserve_outcomes_queueing_and_replay
magi native_clients_preserve_transport_admission_and_command_authority
magi actual_policy_provenance_preserves_native_decisions
magi native_worker_authorization_preserves_authority_and_work
magi containment::selected_external_mcp_bubblewrap_cleans_up_after_casper_kill
magi containment::selected_external_mcp_landlock_cleans_up_after_casper_kill
magi containment::selected_external_mcp_bubblewrap_cleans_up_after_casper_termination
magi containment::selected_external_mcp_landlock_cleans_up_after_casper_termination
magi containment::selected_external_mcp_bubblewrap_cleans_up_after_peer_disconnect
magi containment::selected_external_mcp_landlock_cleans_up_after_peer_disconnect
magi containment::selected_external_mcp_bubblewrap_cancels_initialization
magi containment::selected_external_mcp_landlock_cancels_initialization
magi containment::selected_external_mcp_bubblewrap_cancels_discovery
magi containment::selected_external_mcp_landlock_cancels_discovery
magi events::collection::worker::tests::native_child::selected_child_finishes_a_native_turn_with_stalled_full_event_transport
magi events::collection::worker::tests::native_child::selected_child_finishes_a_native_turn_while_root_admission_is_full
magi selected_casper_accepts_native_handoff_without_changing_run_admission_or_daemon_input
magi containment::selected_external_mcp_descendants_exclude_event_descriptors_in_both_jails
magi selected_siblings_preserve_native_input_reexec_signals_and_useful_work
magi normal_broker_streams_and_reaps_selected_native_providers
magi native_supplier_collection_preserves_run_daemon_and_admission
magi normal_launches_opt_in_preserve_old_siblings_and_reap_before_shutdown
magi tools::graceful_shutdown_reaps_native_tool_daemons_and_active_commands
casper explicit_native_login_persists_private_credentials_and_logout_fences_discovery
casper independent_native_processes_refresh_once_before_authenticated_discovery
casper native_tool_response_loss_reports_unknown_effect_without_replay_or_refresh
casper pooling::pooled_shutdown_and_local_external_logout_cancel_owned_work_without_replay
casper mcp_client::http::identifier_tests::sdk::actual_sdk_parallel_resumption_and_cleanup_keep_original_wire_ids
casper mcp_client::http::identifier_tests::sdk::actual_sdk_malformed_stream_stops_without_replay_or_secret_errors
casper mcp_client::http::identifier_tests::rotation::actual_sdk_parallel_resume_refreshes_once_without_reinitializing_or_replaying
casper mcp_client::http::identifier_tests::restored_identifier_headers_are_sensitive_and_reject_invalid_values
casper commit::native_signals_fence_a_blocked_commit_without_persisting_or_late_resurrection
casper commit::native_kernel_store_failures_are_visible_atomic_and_recoverable
casper commit::native_login_deadline_fences_the_actual_post_exchange_commit
casper deadlines::native_login_signal_cancels_a_contended_initial_reader_before_consent
casper deadlines::native_login_deadline_includes_initial_record_lock_and_reaps_the_reader
casper missing_network_grant_refuses_before_consent_or_store_creation
CASES

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
        if [[ -e ../omit-selected-tools ]]; then
            rm -f "$XDG_CONFIG_HOME/casper/tools.lua"
        elif [[ -e ../wrong-selected-tools ]]; then
            printf '%s\n' 'wrong declarations' > "$XDG_CONFIG_HOME/casper/tools.lua"
        else
            cp config/tools.lua "$XDG_CONFIG_HOME/casper/tools.lua"
        fi
        ;;
    test|verify)
        [[ ${MAGI_REQUIRE_LIVE:-} == 1 ]]
        family_bin=${MAGI_TEST_BINARY%/*}
        [[ $family_bin == "$(realpath ../target/family)"/run-*/bin ]]
        [[ ${MAGI_TEST_BINARY:-} == "$family_bin/magi" ]]
        [[ ${CASPER_TEST_BINARY:-} == "$family_bin/casper" ]]
        [[ ${MELCHIOR_TEST_BINARY:-} == "$family_bin/melchior" ]]
        [[ ${BALTHASAR_TEST_BINARY:-} == "$family_bin/balthasar" ]]
        [[ -z ${OPENAI_API_KEY:-}${MAGI_API_SOCKET:-}${BALTHASAR_AGENT:-} ]]
        [[ $HOME == /tmp/nf.* && $XDG_CONFIG_HOME == "$HOME/c" ]]
        [[ -f $XDG_CONFIG_HOME/casper/tools.lua ]]
        [[ $(command -v balthasar) == "$family_bin/balthasar" ]]
        if [[ $name == magi && -e ../replace-build-output ]]; then
            printf '#!/bin/sh\nexit 99\n' > target/release/magi
        fi
        "$MAGI_TEST_BINARY" verbs | jq -e '.ok' >/dev/null
        if [[ $name == balthasar && -e ../corrupt-selected ]]; then
            chmod u+w "$MAGI_TEST_BINARY"
            printf '\n# changed\n' >> "$MAGI_TEST_BINARY"
        fi
        if [[ $name == balthasar && -e ../remove-selected ]]; then
            rm -- "$MAGI_TEST_BINARY"
        fi
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
                lifecycle::containment_children_leave_one_complete_parent_record_on_stdout \
                default_and_missing_stores_and_broad_grants_are_safe \
                socket_commands_keep_the_server_policy \
                jailed_children_die_when_their_parent_is_killed \
                isolation_off_is_explicit_and_failed_backends_do_not_fall_back \
                complete_source_command_landlock \
                complete_source_socket_landlock \
                complete_source_command_bubblewrap \
                complete_source_socket_bubblewrap \
                invalid_utf8_is_not_transformed_lossily \
                edit_limit_is_an_unchanged_refusal \
                a_missing_complete_source_capability_fails_closed \
                cancelled_source_acquisition_reaps_workers_without_mutation \
                worst_case_json_escaping_preserves_the_complete_source \
                edit_io_does_not_depend_on_a_cat_selected_from_path \
                revision_preconditions_are_never_ignored_by_either_execution_door \
                tools::revision::tests::legacy_calls_omit_revision_fields_in_both_formats \
                tools::revision::tests::revision_presence_survives_null_and_invalid_values_in_both_formats \
                tools::revision::tests::complete_guard_remains_outside_model_arguments \
                files::locking::tests::cases::binding_aliases_and_target_replacements_keep_one_key \
                files::locking::tests::cases::distinct_keys_overlap_while_another_process_waits \
                files::locking::tests::cases::killed_waiters_and_holders_release_only_their_own_leases \
                files::locking::tests::cases::cancellation_and_deadlines_leave_the_lock_inode_in_place \
                files::locking::tests::cases::admission_uses_an_independent_open_description_even_in_one_process \
                files::locking::tests::cases::unsafe_registry_objects_and_inheritable_descriptors_are_refused \
                files::locking::tests::cases::capacity_refuses_new_keys_without_evicting_existing_locks \
                files::locking::tests::cases::lease_registry_and_parent_descriptors_do_not_survive_exec \
                files::locking::tests::cases::registry_privacy_drift_while_waiting_refuses_the_lease \
                files::locking::tests::cases::a_replaced_lock_name_never_admits_a_waiter_on_the_old_inode \
                files::locking::tests::cases::cancellation_before_admission_creates_no_lock_entry \
                files::locking::tests::cases::a_deleted_parent_cannot_receive_a_lease_after_waiting \
                files::locking::tests::cases::path_descriptors_are_normalized_and_unknown_registry_entries_refuse_new_keys \
                files::locking::tests::cases::privacy_drift_during_admission_creates_no_lock_entry \
                files::locking::tests::cases::interrupted_lock_attempts_still_obey_deadlines_and_cancellation \
                files::control::tests::cases::queued_and_received_rights_retain_the_lease_after_sender_death \
                files::control::tests::cases::killing_a_receiver_releases_unconsumed_rights_without_a_second_sender \
                files::control::tests::cases::killing_the_worker_releases_received_rights_after_coordinator_death \
                files::control::tests::cases::privacy_drift_before_handoff_refuses_without_queuing_a_descriptor \
                files::control::tests::cases::received_lock_and_private_channel_descriptors_close_on_exec \
                files::control::tests::cases::malformed_truncated_duplicate_and_wrong_binding_packets_drop_all_rights \
                files::control::tests::cases::child_probes_leave_only_the_parent_completion_record_on_stdout \
                files::locking::tests::cases::child_probes_leave_only_the_parent_completion_record_on_stdout \
                files::control::tests::cases::stream_sockets_bad_keys_missing_descriptors_and_closed_channels_refuse \
                files::control::tests::cases::idle_control_waits_are_bounded_without_creating_a_registry_entry \
                jail::native_tests::cases::native_control_passes_a_lease_without_registry_access_in_both_backends \
                jail::native_tests::cases::ordinary_commands_cannot_use_the_native_control_exception_in_either_backend \
                jail::native_tests::cases::native_control_refuses_off_profiles_and_terminal_children \
                files::control::payload::tests::complete_request_payload_exceeds_presentation_and_argv_caps \
                files::control::payload::tests::unsealed_wrong_size_and_digest_payloads_refuse_and_offsets_are_not_shared \
                files::control::payload::tests::oversized_and_empty_requests_do_not_enqueue_a_descriptor \
                files::worker::snapshot::tests::content_changes_revision_with_identical_metadata_and_atime_is_not_a_revision \
                files::worker::snapshot::tests::incomplete_or_unsupported_native_snapshot_envelopes_refuse \
                actual_native_worker_snapshots_complete_bytes_and_revision_in_both_backends \
                actual_native_worker_refuses_unsafe_sources_without_mutation_or_missing_path_leases \
                actual_native_worker_refuses_uncontained_calls_and_unsafe_fixed_registry \
                actual_native_snapshot_preserves_empty_and_worst_case_escaped_source \
                ordinary_and_native_grants_cannot_expose_the_fixed_registry_before_creation \
                jail::native_tests::cases::native_anonymous_stages_publish_without_extra_grants_in_both_backends \
                jail::native_tests::cases::killed_staged_workers_and_coordinators_never_outlive_their_transaction_lease \
                files::worker::tests::incomplete_or_failed_replies_cannot_be_classified_as_safe_mutation_refusals \
                files::worker::tests::mutation_admission_rejects_missing_unknown_and_oversized_guards_before_execution \
                files::worker::transaction::tests::every_precommit_edge_failure_keeps_the_target_and_cleans_owned_stages \
                files::worker::transaction::tests::mutation_during_staging_or_parent_rename_refuses_before_commit \
                files::worker::transaction::tests::postcommit_sync_and_reporting_failures_never_claim_rollback_or_refusal \
                files::worker::transaction::tests::committed_envelopes_require_identity_supported_version_and_explicit_uncertainty \
                files::worker::transaction::tests::a_replaced_stage_name_is_neither_committed_nor_deleted \
                transactions::actual_native_transactions_preserve_complete_content_metadata_and_refresh_receipts \
                transactions::actual_native_mutations_refuse_invalid_guards_stale_bytes_and_overlapping_matches \
                transactions::actual_native_creators_use_kernel_no_replace_and_preserve_caller_umask \
                transactions::actual_native_mutations_refuse_unsupported_metadata_links_and_missing_parents \
                transactions::actual_native_mutation_request_and_result_preserve_worst_case_escaped_content \
                transactions::actual_native_competing_edits_refuse_a_stale_sibling_then_preserve_both_regions \
                admission::parallel::actual_independent_file_workers_overlap_on_both_doors_and_backends \
                admission::parallel::actual_waiting_native_workers_cannot_commit_after_worker_or_coordinator_death_on_both_doors_and_backends \
                admission::metadata::actual_native_acl_sparse_and_staged_timestamp_policies_hold_on_both_doors_and_backends \
                files::worker::staging::tests::source_metadata_policy_refuses_foreign_owners_invalid_groups_and_privileged_modes \
                files::worker::staging::tests::an_actual_unsupported_filesystem_refuses_before_staging_or_publication \
                admission::kernel_failures::actual_native_enospc_preserves_target_cleans_stages_and_releases_leases_on_both_doors_and_backends \
                admission::kernel_failures::actual_native_data_sync_failure_preserves_target_and_releases_leases_on_both_doors_and_backends \
                lua::engine::files::tests::declaration_only_vm_preserves_the_shipped_tool_cards_and_pure_settings \
                lua::engine::files::tests::native_identity_is_keyed_and_ordinary_overrides_revoke_capability \
                lua::engine::files::tests::file_registrars_refuse_operation_callbacks_permission_lies_and_invalid_names \
                lua::engine::files::tests::every_effectful_api_and_global_stream_alias_taints_admission_even_when_caught \
                lua::engine::files::tests::lent_callbacks_are_blocked_and_lua_results_cannot_forge_machine_observations \
                lua::engine::files::tests::native_renderers_have_no_effects_and_no_machine_metadata_authority \
                tools::revision::tests::native_capability_admission_preserves_presence_and_never_ignores_null_or_unknown_versions \
                files::worker::presence::tests::presence_revalidates_parent_and_never_opens_existing_or_special_leaf_objects \
                files::worker::reading::tests::range_scanning_preserves_actual_line_semantics_independently_of_chunk_boundaries \
                files::worker::reading::tests::huge_lines_and_late_ranges_have_bounded_retention_and_explicit_utf8_safe_omissions \
                files::worker::reading::tests::readonly_read_receipts_match_complete_snapshot_and_refuse_unstable_binding_or_source \
                files::worker::reading::tests::invalid_read_ranges_guards_and_mismatched_snapshot_displays_cannot_authorize_mutations \
                admission::reading::native_read_ranges_scan_beyond_edit_and_display_bounds_without_fabricating_receipts \
                admission::reading::native_read_preserves_readonly_links_and_binary_previews_but_only_stable_editable_text_has_receipts \
                admission::shipped::shipped_file_tools_require_native_guards_preserve_presentation_and_never_use_legacy_io \
                tools::revision::tests::recovery_is_read_only_versioned_and_preserves_null_presence_before_configuration \
                admission::recovery::recovery_absence_is_jailed_typed_success_without_text_receipts_and_normal_missing_reads_stay_failed \
                admission::recovery::recovery_null_unknown_and_mutation_requests_refuse_before_declaration_effects_or_worker_access \
                admission::native_declarations_drive_guarded_tools_and_machine_receipts_through_both_doors_and_formats \
                admission::actual_command_admission_precedes_stdin_configuration_and_native_access_in_both_formats \
                admission::guarded_declarations_never_execute_caught_effects_or_legacy_overrides \
                admission::arbitrary_callbacks_and_nested_reads_cannot_refresh_native_observations \
                admission::failed_postcommit_rendering_retains_committed_identity_without_executing_effects \
                admission::native_admission_rejects_capability_remaps_and_model_supplied_guard_fields \
                admission::old_coordinators_cannot_run_unguarded_native_mutations_but_legacy_callbacks_keep_their_shape \
                admission::native_raster_reads_preserve_attachments_without_fabricating_editable_receipts \
                broker::pushed_read_data_is_call_bound_single_use_and_never_acquires_a_registry \
                broker::oversized_unterminated_stdio_requests_close_before_deserialization_or_acquisition \
                broker::broker_preserves_contained_native_ranges_images_and_preview_without_receipts_on_both_backends \
                broker::broker_does_not_acquire_credentials_registry_or_mutation_authority_on_both_backends \
                broker::broker_negotiates_renamed_native_reads_and_runs_only_the_pure_renderer_on_both_backends \
                broker_lifecycle::broker_deadlines_stop_owned_acquisition_workers_without_releasing_another_lease_on_both_backends \
                source_worker::tests::a_configured_jail_cannot_be_bypassed_by_calling_the_write_worker \
                source::tests::an_error_after_a_prefix_never_returns_a_snapshot \
                source::tests::every_truncated_reply_and_inconsistent_snapshot_is_refused \
                source::tests::text_is_complete_at_the_byte_limit_and_strict_about_encoding; do
                if [[ $case == complete_source_command_landlock ]]; then
                    if [[ -e ../omit-edit-source-case ]]; then continue; fi
                    if [[ -e ../ignored-edit-source-case ]]; then echo "test $case ... ignored"; continue; fi
                    if [[ -e ../failed-edit-source-case ]]; then echo "test $case ... FAILED"; continue; fi
                fi
                if [[ $case == revision_preconditions_are_never_ignored_by_either_execution_door ]]; then
                    if [[ -e ../omit-file-revision-case ]]; then continue; fi
                    if [[ -e ../ignored-file-revision-case ]]; then echo "test $case ... ignored"; continue; fi
                    if [[ -e ../failed-file-revision-case ]]; then echo "test $case ... FAILED"; continue; fi
                    if [[ -e ../partial-file-revision-case ]]; then echo "test $case ..."; continue; fi
                fi
                if [[ $case == files::locking::tests::cases::killed_waiters_and_holders_release_only_their_own_leases ]]; then
                    if [[ -e ../omit-file-lease-case ]]; then continue; fi
                    if [[ -e ../ignored-file-lease-case ]]; then echo "test $case ... ignored"; continue; fi
                    if [[ -e ../failed-file-lease-case ]]; then echo "test $case ... FAILED"; continue; fi
                    if [[ -e ../partial-file-lease-case ]]; then echo "test $case ..."; continue; fi
                fi
                if [[ $case == files::control::tests::cases::queued_and_received_rights_retain_the_lease_after_sender_death ]]; then
                    if [[ -e ../omit-file-handoff-case ]]; then continue; fi
                    if [[ -e ../ignored-file-handoff-case ]]; then echo "test $case ... ignored"; continue; fi
                    if [[ -e ../failed-file-handoff-case ]]; then echo "test $case ... FAILED"; continue; fi
                    if [[ -e ../partial-file-handoff-case ]]; then echo "test $case ..."; continue; fi
                fi
                if [[ $case == jail::native_tests::cases::native_control_passes_a_lease_without_registry_access_in_both_backends ]]; then
                    if [[ -e ../omit-native-control-case ]]; then continue; fi
                    if [[ -e ../ignored-native-control-case ]]; then echo "test $case ... ignored"; continue; fi
                    if [[ -e ../failed-native-control-case ]]; then echo "test $case ... FAILED"; continue; fi
                    if [[ -e ../partial-native-control-case ]]; then echo "test $case ..."; continue; fi
                fi
                if [[ $case == actual_native_worker_snapshots_complete_bytes_and_revision_in_both_backends ]]; then
                    if [[ -e ../omit-native-snapshot-case ]]; then continue; fi
                    if [[ -e ../ignored-native-snapshot-case ]]; then echo "test $case ... ignored"; continue; fi
                    if [[ -e ../failed-native-snapshot-case ]]; then echo "test $case ... FAILED"; continue; fi
                    if [[ -e ../partial-native-snapshot-case ]]; then echo "test $case ..."; continue; fi
                fi
                if [[ $case == ordinary_and_native_grants_cannot_expose_the_fixed_registry_before_creation ]]; then
                    if [[ -e ../omit-registry-protection-case ]]; then continue; fi
                    if [[ -e ../ignored-registry-protection-case ]]; then echo "test $case ... ignored"; continue; fi
                    if [[ -e ../failed-registry-protection-case ]]; then echo "test $case ... FAILED"; continue; fi
                    if [[ -e ../partial-registry-protection-case ]]; then echo "test $case ..."; continue; fi
                fi
                if [[ $case == jail::native_tests::cases::killed_staged_workers_and_coordinators_never_outlive_their_transaction_lease ]]; then
                    if [[ -e ../omit-file-commit-lifetime-case ]]; then continue; fi
                    if [[ -e ../ignored-file-commit-lifetime-case ]]; then echo "test $case ... ignored"; continue; fi
                    if [[ -e ../failed-file-commit-lifetime-case ]]; then echo "test $case ... FAILED"; continue; fi
                    if [[ -e ../partial-file-commit-lifetime-case ]]; then echo "test $case ..."; continue; fi
                fi
                if [[ $case == transactions::actual_native_competing_edits_refuse_a_stale_sibling_then_preserve_both_regions ]]; then
                    if [[ -e ../omit-file-atomic-race-case ]]; then continue; fi
                    if [[ -e ../ignored-file-atomic-race-case ]]; then echo "test $case ... ignored"; continue; fi
                    if [[ -e ../failed-file-atomic-race-case ]]; then echo "test $case ... FAILED"; continue; fi
                    if [[ -e ../partial-file-atomic-race-case ]]; then echo "test $case ..."; continue; fi
                fi
                if [[ $case == files::worker::transaction::tests::postcommit_sync_and_reporting_failures_never_claim_rollback_or_refusal ]]; then
                    if [[ -e ../omit-file-commit-outcome-case ]]; then continue; fi
                    if [[ -e ../ignored-file-commit-outcome-case ]]; then echo "test $case ... ignored"; continue; fi
                    if [[ -e ../failed-file-commit-outcome-case ]]; then echo "test $case ... FAILED"; continue; fi
                    if [[ -e ../partial-file-commit-outcome-case ]]; then echo "test $case ..."; continue; fi
                fi
                if [[ $case == admission::guarded_declarations_never_execute_caught_effects_or_legacy_overrides ]]; then
                    if [[ -e ../omit-native-file-admission-case ]]; then continue; fi
                    if [[ -e ../ignored-native-file-admission-case ]]; then echo "test $case ... ignored"; continue; fi
                    if [[ -e ../failed-native-file-admission-case ]]; then echo "test $case ... FAILED"; continue; fi
                    if [[ -e ../partial-native-file-admission-case ]]; then echo "test $case ..."; continue; fi
                fi
                if [[ $case == admission::arbitrary_callbacks_and_nested_reads_cannot_refresh_native_observations ]]; then
                    if [[ -e ../omit-native-file-provenance-case ]]; then continue; fi
                    if [[ -e ../ignored-native-file-provenance-case ]]; then echo "test $case ... ignored"; continue; fi
                    if [[ -e ../failed-native-file-provenance-case ]]; then echo "test $case ... FAILED"; continue; fi
                    if [[ -e ../partial-native-file-provenance-case ]]; then echo "test $case ..."; continue; fi
                fi
                if [[ $case == admission::actual_command_admission_precedes_stdin_configuration_and_native_access_in_both_formats ]]; then
                    if [[ -e ../omit-native-prelude-case ]]; then continue; fi
                    if [[ -e ../ignored-native-prelude-case ]]; then echo "test $case ... ignored"; continue; fi
                    if [[ -e ../failed-native-prelude-case ]]; then echo "test $case ... FAILED"; continue; fi
                    if [[ -e ../partial-native-prelude-case ]]; then echo "test $case ..."; continue; fi
                fi
                if [[ $case == admission::recovery::recovery_absence_is_jailed_typed_success_without_text_receipts_and_normal_missing_reads_stay_failed ]]; then
                    if [[ -e ../omit-jailed-absence-case ]]; then continue; fi
                    if [[ -e ../ignored-jailed-absence-case ]]; then echo "test $case ... ignored"; continue; fi
                    if [[ -e ../failed-jailed-absence-case ]]; then echo "test $case ... FAILED"; continue; fi
                    if [[ -e ../partial-jailed-absence-case ]]; then echo "test $case ..."; continue; fi
                fi
                case "$case" in
                    files::control::tests::cases::child_probes_leave_only_the_parent_completion_record_on_stdout) category=probe-control ;;
                    files::locking::tests::cases::child_probes_leave_only_the_parent_completion_record_on_stdout) category=probe-lease ;;
                    lifecycle::containment_children_leave_one_complete_parent_record_on_stdout) category=containment-record ;;
                    admission::parallel::actual_independent_file_workers_overlap_on_both_doors_and_backends) category=worker-overlap ;;
                    admission::parallel::actual_waiting_native_workers_cannot_commit_after_worker_or_coordinator_death_on_both_doors_and_backends) category=worker-cancel ;;
                    admission::metadata::actual_native_acl_sparse_and_staged_timestamp_policies_hold_on_both_doors_and_backends) category=native-metadata ;;
                    files::worker::staging::tests::source_metadata_policy_refuses_foreign_owners_invalid_groups_and_privileged_modes) category=metadata-policy ;;
                    files::worker::staging::tests::an_actual_unsupported_filesystem_refuses_before_staging_or_publication) category=unsupported-fs ;;
                    admission::kernel_failures::actual_native_enospc_preserves_target_cleans_stages_and_releases_leases_on_both_doors_and_backends) category=kernel-space ;;
                    admission::kernel_failures::actual_native_data_sync_failure_preserves_target_and_releases_leases_on_both_doors_and_backends) category=kernel-sync ;;
                    admission::shipped::shipped_file_tools_require_native_guards_preserve_presentation_and_never_use_legacy_io) category=shipped-files ;;
                    files::worker::reading::tests::huge_lines_and_late_ranges_have_bounded_retention_and_explicit_utf8_safe_omissions) category=read-scanner ;;
                    admission::reading::native_read_ranges_scan_beyond_edit_and_display_bounds_without_fabricating_receipts) category=read-range ;;
                    admission::reading::native_read_preserves_readonly_links_and_binary_previews_but_only_stable_editable_text_has_receipts) category=read-receipt ;;
                    broker::pushed_read_data_is_call_bound_single_use_and_never_acquires_a_registry) category=broker-binding ;;
                    broker::oversized_unterminated_stdio_requests_close_before_deserialization_or_acquisition) category=broker-input ;;
                    broker::broker_preserves_contained_native_ranges_images_and_preview_without_receipts_on_both_backends) category=broker-reading ;;
                    broker::broker_does_not_acquire_credentials_registry_or_mutation_authority_on_both_backends) category=broker-denial ;;
                    broker::broker_negotiates_renamed_native_reads_and_runs_only_the_pure_renderer_on_both_backends) category=broker-render ;;
                    broker_lifecycle::broker_deadlines_stop_owned_acquisition_workers_without_releasing_another_lease_on_both_backends) category=broker-lifecycle ;;
                    *) category= ;;
                esac
                if [[ -n $category ]]; then
                    if [[ -e ../omit-$category-case ]]; then continue; fi
                    if [[ -e ../ignored-$category-case ]]; then echo "test $case ... ignored"; continue; fi
                    if [[ -e ../failed-$category-case ]]; then echo "test $case ... FAILED"; continue; fi
                    if [[ -e ../partial-$category-case ]]; then echo "test $case ..."; continue; fi
                fi
                if [[ -e ../interleave && $case == prepared_grants* ]]; then
                    echo "test contained_child ... test $case ... okok"
                else
                    echo "test $case ... ok"
                fi
            done
        fi
        if [[ ! -e ../omit-case ]]; then
            for name in \
                loading::native_acp_load_replays_before_response_and_continues_without_provider_replay \
                loading::native_acp_load_refuses_duplicate_missing_and_foreign_store_without_losing_owner \
                loading::native_acp_concurrent_loads_admit_exactly_one_writer \
                loading::native_acp_load_cannot_steal_an_ordinary_host_writer \
                loading::native_acp_load_replays_tools_without_execution_and_rebinds_session_mcp \
                tool_lifecycle::native_acp_cancel_during_running_tool_reaps_it_before_recovery \
                tool_lifecycle::native_acp_disconnect_during_running_tool_reaps_it_without_followup \
                children::native_acp_background_automatic_turn_cancels_without_a_prompt_response \
                children::native_acp_background_child_cancel_retires_late_allow \
                children::native_acp_background_child_denial_does_not_run_the_action \
                children::native_acp_background_child_disconnect_reaps_without_action \
                children::native_acp_background_child_permission_reaches_the_idle_parent_session \
                display::native_acp_rewind_and_user_images_remain_visible_without_unsolicited_replies \
                mcp::native_acp_nested_native_read_mcp_preserves_the_real_result \
                mcp::native_acp_stdio_mcp_denial_prevents_the_server_action \
                mcp::native_acp_stdio_mcp_invokes_with_literal_configuration_and_no_session_leakage \
                native_acp_disconnect_does_not_stop_another_adapters_host \
                native_acp_disconnect_during_stalled_startup_reaps_the_child \
                native_acp_mcp_settings_are_private_session_local_and_literal \
                native_acp_parent_death_during_config_load_cannot_orphan_a_host \
                native_acp_refuses_invalid_sessions_before_spawning_and_recovers \
                native_acp_session_limit_does_not_spawn_a_fifth_host \
                native_acp_sessions_keep_distinct_roots_and_cleanup_owned_hosts \
                permissions::native_acp_allow_once_requires_a_fresh_permission_for_the_next_action \
                permissions::native_acp_cancelled_permission_late_allow_cannot_grant_or_affect_the_next_turn \
                permissions::native_acp_permission_allow_once_runs_the_selected_tool_and_preserves_results \
                permissions::native_acp_permission_deny_never_runs_the_action \
                permissions::native_acp_permission_disconnect_cleans_up_without_running_the_action \
                permissions::native_acp_permission_replies_are_correlated_when_sessions_answer_out_of_order \
                permissions::native_acp_unoffered_permission_choice_closes_and_cleans_up_without_effects \
                settings::native_acp_busy_model_change_does_not_block_cancellation_or_other_sessions \
                settings::native_acp_model_refusal_keeps_the_previous_native_worker \
                settings::native_acp_model_selection_is_correlated_session_local_and_used_by_native_turns \
                turns::native_acp_cancellation_remains_live_while_another_session_starts \
                turns::native_acp_disconnect_during_generation_reaps_owned_provider_work \
                turns::native_acp_parent_death_during_generation_stops_owned_provider_work \
                turns::native_acp_prompt_cancels_without_admitting_a_concurrent_prompt \
                turns::native_acp_prompt_uses_native_turns_and_preserves_resource_references \
                turns::native_acp_tool_round_waits_for_native_result_and_followup \
                selected_casper_reads_precedence_and_snapshots_under_bubblewrap \
                skills::client::supervised::tests::stale_waiting_work_never_runs_and_success_error_and_panic_release_capacity \
                skills::client::supervised::tests::cancellation_and_dropped_callers_signal_owned_work_without_releasing_its_slot \
                skills::client::supervised::tests::cleanup_still_owns_capacity_after_result_is_ready_and_deadline_returns \
                skills::client::supervised::tests::timeout_returns_during_blocked_work_but_retains_capacity_until_cleanup \
                skills::client::supervised::tests::integration::blocked_verification_times_out_without_blocking_the_runtime_or_starting_a_late_helper \
                skills::client::supervised::tests::integration::supervised_native_helper_is_reaped_after_cancellation_timeout_and_caller_drop \
                skills::client::supervised::tests::saturation::cancelled_capacity_waiter_is_removed_without_starting_work_after_release \
                skills::client::supervised::tests::saturation::four_stalled_workers_bound_background_work_across_repeated_timeouts \
                supplier::tests::program_fingerprints_stream_bounded_chunks_and_preserve_exact_bytes \
                selected_casper_reads_precedence_and_snapshots_under_landlock \
                missing_roots_are_empty_but_unsafe_roots_and_pin_failures_are_visible \
                permissions::unreadable_workflows_fail_closed_under_landlock \
                permissions::unreadable_workflows_fail_closed_under_bubblewrap \
                workflow_snapshot_survives_native_store_reconnect_without_rereading_source \
                workflow_body_is_not_user_authority_for_pinned_native_memory \
                another_controller_can_cancel_acquisition \
                authority::selected_workflow_never_grants_native_tool_authority \
                authority::selected_workflow_keeps_permissions_and_jail_over_native_socket \
                authority::selected_workflow_keeps_permissions_in_bubblewrap_command_jail \
                authority::selected_workflow_keeps_permissions_in_bubblewrap_socket_jail \
                documented_workflow_parses_with_exact_body_and_source_digest \
                documented_print_prompt_preserves_shell_punctuation_as_data \
                documented_root_order_matches_native_selection \
                documented_byte_limits_match_native_constants \
                models::successful_model_replacement_cancels_preparation_and_preserves_frozen_context \
                branch_invalidates_inflight_preparation \
                catalog_listing_is_lazy_and_contains_metadata_errors_without_journalling \
                catalog_refresh_is_cancelled_without_blocking_interrupt \
                detach_cancels_only_unaccepted_owned_preparation \
                explicit_workspace_selects_only_its_project_roots_and_preserves_user_root \
                interrupt_remains_responsive_during_acquisition \
                lifecycle::detaching_cancels_active_and_queued_owner_work_without_cancelling_another_controller \
                lifecycle::interrupt_allows_fresh_workflow_acquisition_without_reusing_cancelled_state \
                lifecycle::rewind_restores_first_snapshot_after_changed_source_is_deleted \
                lifecycle::successful_policy_change_cancels_old_preparation_and_allows_fresh_selection \
                lifecycle::successful_resume_restores_frozen_workflow_and_rebinds_new_preparation \
                model_change_invalidates_inflight_preparation_even_if_refused \
                resume_invalidates_inflight_preparation_even_if_target_is_missing \
                socket_submission_uses_native_reader_and_replays_frozen_workflow_in_fifo_order \
                unsafe_explicit_workspace_refuses_without_falling_back_to_launch \
                worktrees::explicit_root_selects_real_linked_worktree_without_scanning_git_metadata \
                worktrees::nested_launch_in_real_worktree_does_not_implicitly_select_ancestor_skills \
                tooling::files::tests::recovery_read_presence_and_absence_wire_are_versioned_in_both_formats \
                supplier::failures::only_complete_typed_refusal_frames_are_known_no_effect_not_error_message_text \
                supplier::waiting::tests::refusal_before_payload_and_uncertainty_after_handoff_follow_actual_send_state \
                files::tests::absence_proofs_need_explicit_read_recovery_and_never_authorize_mutations_or_failed_delivery \
                files::tests::only_requested_successful_absence_delivery_resolves_creation_without_an_overwrite_receipt \
                files::missing_target_recovery_needs_explicit_delivered_absence_and_old_providers_cannot_fake_support \
                files::known_no_effect_refusals_are_not_misclassified_as_unknown_creation_outcomes \
                files::tests::unresolved_mutations_cannot_be_evicted_or_retried_as_new_creations_and_failed_reads_do_not_clear_them \
                files::lost_commit_replies_block_new_model_mutations_until_a_delivered_native_reread \
                files::tests::postcommit_presentation_errors_keep_confirmed_identity_before_any_clipping \
                native_revisions_keep_agent_ownership_through_actual_casper_both_doors_and_backends \
                shipped_revisions_keep_agent_ownership_through_actual_casper_both_doors_and_backends \
                native_reply_loss_after_commit_requires_actual_rereads_on_both_doors_and_backends \
                files::tests::native_delivery_is_opaque_session_and_cursor_bound_and_acknowledged_only_once \
                files::tests::native_metadata_rejects_unsupported_receipts_and_mismatched_or_incomplete_mutation_outcomes \
                files::tests::lost_native_outcomes_retain_logical_correlation_without_claiming_refusal_or_replay \
                files::tests::only_delivered_reads_admit_existing_mutations_and_pending_or_abandoned_reads_do_not \
                files::tests::child_sibling_supplier_cwd_and_unobserved_aliases_never_refresh_another_agent \
                files::tests::failed_old_and_duplicate_read_completions_cannot_replace_the_latest_delivered_revision \
                files::tests::committed_mutations_refresh_their_own_receipt_but_unknown_or_mismatched_outcomes_require_reread \
                files::tests::bounded_eviction_never_waives_overwrite_guards_or_resurrects_an_evicted_pending_read \
                files::tests::resume_and_restoration_discard_receipts_and_retire_every_old_pending_delivery_context \
                files::tests::invalid_bounds_and_exhausted_logical_ids_refuse_without_source_access_or_state_changes \
                files::checked_paths_and_exact_journal_delivery_control_guards_even_with_reused_provider_ids \
                files::ordinary_and_failed_results_and_other_agent_reads_never_grant_parent_mutation_receipts \
                files::tests::progress_evidence_is_delivered_scoped_and_stable_across_identical_rereads \
                files::delivered_reread_repairs_a_suppressed_native_edit_in_the_same_batch \
                files::cancelled_unjournalled_and_resumed_native_completions_cannot_refresh_delivered_state \
                files::permission_denial_precedes_native_admission_and_preserves_the_last_delivered_observation \
                files::model_arguments_cannot_supply_guards_or_turn_an_unobserved_write_into_unchecked_overwrite \
                tooling::files::tests::native_file_call_presence_survives_null_unknown_and_partial_guards_in_both_formats \
                tooling::files::tests::native_file_guards_are_outside_model_arguments_and_legacy_calls_remain_unchanged \
                tooling::files::tests::native_file_cards_and_results_decode_independent_wire_without_changing_legacy_readers \
                supplier::admission::tests::native_file_events_are_bounded_typed_and_leave_the_reply_unconsumed \
                supplier::admission::tests::native_machine_metadata_survives_supplier_and_both_registry_paths_but_not_legacy_or_lua_claims \
                supplier::admission::processes::guarded_command_payload_waits_for_the_actual_process_and_old_or_partial_peers_receive_nothing \
                supplier::admission::processes::replacing_a_role_after_positive_cards_cannot_bypass_command_admission_or_replay_a_lost_commit \
                supplier::admission::processes::fresh_cards_never_upgrade_an_old_cached_daemon_and_sent_native_calls_are_not_replayed \
                supplier::admission::processes::cancelled_or_expired_command_admission_never_sends_the_withheld_payload \
                a_running_balthasar_lists_its_verbs \
                broker::overflow::actual_peer_optional_detail_never_loses_terminal_failure_or_changes_request \
                overflowing::typed::output_budget_refusal_preserves_history_policy_and_usage_without_compaction \
                config::settings::ui_tests::an_explicit_sibling_output_limit_is_reserved_and_sent_unchanged \
                ask::tests::output_provenance_is_additive_and_legacy_limits_remain_explicit \
                overflowing::typed::input_unknown_and_malformed_detail_keep_bounded_input_recovery \
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
                helping::retrying::cumulative_retry_usage_from_melchior_is_never_added_twice \
                helping::retrying::estimated_helper_cost_is_preserved_and_stops_the_next_budgeted_job \
                cost::tallying::resolved_estimates_are_displayed_without_being_called_provider_reports \
                crew::tests::roster_totals_keep_estimates_and_saturate_all_counters \
                ask::accounting_compatibility::reported_and_estimated_costs_cross_json_and_cbor_without_changing_old_fields \
                what_a_turn_cost_reaches_the_ui \
                helper_retries::failed_helpers_report_failure_without_applying_their_partial_memory \
                projection::stored_observations_never_acquire_the_rule_channel_after_restart \
                truncated::truncated_calls_are_journalled_with_failed_results_and_never_executed \
                files::ordinary_and_failed_results_and_other_agent_reads_never_grant_parent_mutation_receipts \
                turn::progress::tests::canonical_objects_preserve_arrays_strings_tool_identity_and_repairs \
                turn::progress::tests::completed_failures_suppress_third_and_stop_fourth_without_synthetic_progress \
                turn::progress::tests::changed_results_and_success_reset_only_their_key_empty_output_does_not \
                turn::progress::tests::raw_middle_and_native_revisions_count_but_attempt_ids_do_not \
                turn::progress::tests::record_and_argument_limits_fail_closed_without_evicting_failed_keys \
                progress::repeated_failures_execute_twice_suppress_third_and_end_on_fourth_request \
                progress::duplicate_batch_admission_preserves_unrelated_inflight_results \
                progress::successful_repeats_and_changed_failures_keep_running \
                progress::retry_frames_are_not_tool_completions_and_new_prompts_reset_guard \
                progress::cancellation_drains_sent_calls_and_never_prepares_deferred_duplicates \
                progress::output_spill_paths_do_not_fabricate_changed_results \
                progress::successful_duplicate_batch_and_alternating_failure_keys_have_defined_limits \
                progress::preparation_refusals_are_completed_failures_not_an_unbounded_loop \
                progress::failed_attachment_validation_counts_as_failure_before_text_is_bounded \
                progress::successful_polling_still_obeys_the_coarse_round_limit \
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
                category=
                case "$name" in
                    native_acp_*|*::native_acp_*) category=acp-native ;;
                    skills::client::supervised::*|supplier::tests::program_fingerprints_stream_bounded_chunks_and_preserve_exact_bytes|permissions::unreadable_workflows_*|authority::*|worktrees::*|workflow_*|selected_casper_*|documented_*|models::successful_model_replacement_cancels_preparation_and_preserves_frozen_context|missing_roots_are_empty_but_unsafe_roots_and_pin_failures_are_visible) category=workflow-native ;;
                    files::ordinary_and_failed_results_and_other_agent_reads_never_grant_parent_mutation_receipts|files::tests::progress_evidence_is_delivered_scoped_and_stable_across_identical_rereads|files::delivered_reread_repairs_a_suppressed_native_edit_in_the_same_batch) category=progress-native ;;
                    turn::progress::tests::*) category=progress-policy ;;
                    progress::repeated_failures_execute_twice_suppress_third_and_end_on_fourth_request|progress::duplicate_batch_admission_preserves_unrelated_inflight_results) category=progress-dispatch ;;
                    progress::*) category=progress-lifecycle ;;
                    broker::overflow::actual_peer_optional_detail_never_loses_terminal_failure_or_changes_request) category=overflow-wire ;;
                    overflowing::typed::output_budget_refusal_preserves_history_policy_and_usage_without_compaction) category=overflow-output-routing ;;
                    config::settings::ui_tests::an_explicit_sibling_output_limit_is_reserved_and_sent_unchanged) category=explicit-output-setting ;;
                    ask::tests::output_provenance_is_additive_and_legacy_limits_remain_explicit) category=output-provenance ;;
                    overflowing::typed::input_unknown_and_malformed_detail_keep_bounded_input_recovery) category=overflow-input-routing ;;
                    supplier::failures::only_complete_typed_refusal_frames_are_known_no_effect_not_error_message_text) category=typed-refusal ;;
                    files::missing_target_recovery_needs_explicit_delivered_absence_and_old_providers_cannot_fake_support) category=absence-delivery ;;
                    files::known_no_effect_refusals_are_not_misclassified_as_unknown_creation_outcomes) category=refusal-delivery ;;
                    files::lost_commit_replies_block_new_model_mutations_until_a_delivered_native_reread) category=unknown-delivery ;;
                    native_revisions_keep_agent_ownership_through_actual_casper_both_doors_and_backends) category=native-delivery ;;
                    shipped_revisions_keep_agent_ownership_through_actual_casper_both_doors_and_backends) category=shipped-delivery ;;
                    native_reply_loss_after_commit_requires_actual_rereads_on_both_doors_and_backends) category=committed-loss ;;
                    files::tests::only_delivered_reads_admit_existing_mutations_and_pending_or_abandoned_reads_do_not) category=delivery-state ;;
                    files::checked_paths_and_exact_journal_delivery_control_guards_even_with_reused_provider_ids) category=delivery-provenance ;;
                    files::cancelled_unjournalled_and_resumed_native_completions_cannot_refresh_delivered_state) category=delivery-epoch ;;
                    files::model_arguments_cannot_supply_guards_or_turn_an_unobserved_write_into_unchecked_overwrite) category=delivery-guards ;;
                    supplier::admission::processes::fresh_cards_never_upgrade_an_old_cached_daemon_and_sent_native_calls_are_not_replayed) category=selected-process ;;
                    supplier::admission::tests::native_machine_metadata_survives_supplier_and_both_registry_paths_but_not_legacy_or_lua_claims) category=machine-metadata ;;
                esac
                if [[ -n $category ]]; then
                    if [[ -e ../omit-$category-case ]]; then continue; fi
                    if [[ -e ../ignored-$category-case ]]; then echo "test $name ... ignored"; continue; fi
                    if [[ -e ../failed-$category-case ]]; then echo "test $name ... FAILED"; continue; fi
                    if [[ -e ../partial-$category-case ]]; then echo "test $name ..."; continue; fi
                fi
                if [[ $name == a_running_balthasar_lists_its_verbs && -e ../partial-case ]]; then
                    echo "test $name ... "
                elif [[ $name == a_running_balthasar_lists_its_verbs && -e ../ignored-case ]]; then
                    echo "test $name ... ignored"
                elif [[ $name == a_running_balthasar_lists_its_verbs && -e ../failed-case ]]; then
                    echo "test $name ... FAILED"
                else
                    echo "test $name ... ok"
                fi
            done
        fi
        if [[ ${PWD##*/} == melchior && ! -e ../omit-streaming-case ]]; then
            for name in \
                serving::binding::tests::directory_sweeps_cannot_unlink_a_socket_or_lock_under_a_held_binding_lease \
                serving::binding::tests::a_repeated_release_cannot_remove_a_successors_socket_or_lock \
                serving::binding::tests::replacing_the_lock_cannot_make_an_old_lease_unlink_current_paths \
                serving::binding::tests::a_sibling_sweep_between_bind_and_listen_preserves_the_socket \
                places::locking::tests::a_busy_directory_has_a_bounded_wait_and_can_be_taken_after_release \
                places::locking::tests::a_removed_directory_cannot_authorize_a_lock_in_its_replacement \
                places::locking::tests::links_shared_inodes_and_open_permissions_are_not_socket_locks \
                mind::provider::client::overflow_tests::recovery::cancellation_before_and_during_output_adjustment_closes_without_more_attempts \
                mind::provider::client::overflow_tests::recovery::automatic_output_recovers_without_changing_any_other_request_bytes \
                mind::provider::client::overflow_tests::recovery::explicit_requests_and_session_limits_never_reduce \
                mind::provider::client::overflow_tests::recovery::ordinary_and_output_retries_share_four_total_attempts \
                mind::provider::client::overflow_tests::recovery::repeated_output_rejections_are_strictly_decreasing_and_bounded \
                mind::provider::client::overflow_tests::recovery::missing_invalid_or_inconsistent_budget_metadata_stays_terminal \
                mind::provider::client::overflow_tests::recovery::changed_payload_or_thinking_and_mismatched_reported_counts_never_retry \
                mind::lua::adapter::tests::prepared_output_budgets_follow_lua_fields_and_preserve_thinking \
                mind::wire::tests::output_provenance_is_additive_and_legacy_limits_remain_explicit \
                real_binary_output_recovery_resets_partial_answers_and_retains_paid_usage \
                mind::provider::client::overflow::tests::only_known_http_structure_proves_input_and_never_extracts_prose_counts \
                mind::provider::client::overflow::tests::status_api_and_existing_refusal_class_are_not_overridden_by_body_text \
                mind::provider::client::overflow::vllm::tests::verified_output_template_requires_exact_counts_and_safe_available_room \
                mind::provider::client::overflow::vllm::tests::unverified_output_templates_never_produce_counts_or_output_classification \
                mind::provider::client::overflow::vllm::tests::output_metadata_requires_the_right_protocol_status_and_refusal_class \
                real_binary_preserves_typed_input_unknown_and_auth_terminal_failures; do
                case "$name" in
                    serving::binding::*) category=socket-leases ;;
                    places::locking::*) category=socket-domains ;;
                    *only_known_http*) category=overflow-provider-classification ;;
                    *status_api*) category=overflow-provider-status ;;
                    *::verified_output_template*) category=output-template-counts ;;
                    *::unverified_output_templates*) category=output-template-unknown ;;
                    *::output_metadata_requires*) category=output-template-authority ;;
                    *::recovery::*) category=output-budget-recovery ;;
                    *::prepared_output_budgets*) category=output-budget-lua ;;
                    *::output_provenance*) category=output-budget-wire ;;
                    real_binary_output_recovery*) category=output-budget-paid ;;
                    *) category=overflow-provider-wire ;;
                esac
                if [[ -e ../omit-$category-case ]]; then continue
                elif [[ -e ../ignored-$category-case ]]; then echo "test $name ... ignored"
                elif [[ -e ../failed-$category-case ]]; then echo "test $name ... FAILED"
                elif [[ -e ../partial-$category-case ]]; then echo "test $name ... ok-ish"
                else echo "test $name ... ok"
                fi
            done
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
                if [[ -e ../interleave && $case == *every_byte_split* ]]; then
                    echo "test unrelated_case ... oktest $case ... ok"
                else
                    echo "test $case ... ok"
                fi
            done
        fi
        if [[ ${PWD##*/} == melchior ]]; then
            for case in \
                mind::lua::adapter::usage_tests::nested_and_alternate_cached_counts_are_duplicate_not_additive \
                mind::lua::adapter::usage_tests::malformed_cache_metadata_cannot_drop_valid_content_or_other_counters \
                mind::lua::adapter::usage_tests::a_partial_measurement_does_not_invent_an_inclusive_total \
                mind::lua::adapter::usage_tests::integral_float_tokens_survive_the_actual_lua_conversion \
                mind::lua::adapter::usage_tests::malformed_later_fields_do_not_erase_previous_paid_measurements \
                mind::lua::adapter::usage_tests::responses_and_gemini_bound_inclusive_cache_counts_but_anthropic_is_exclusive \
                mind::lua::adapter::usage_tests::invalid_measurements_have_an_observable_anomaly_without_losing_content \
                mind::model::usage::pricing_tests::absent_cached_rates_use_input_but_explicit_zero_stays_free \
                mind::model::usage::pricing_tests::maximum_prompt_occupancy_saturates_instead_of_overflowing \
                mind::model::usage::pricing_tests::every_counter_accepts_integral_numbers_and_refuses_invalid_ones \
                mind::catalog::price_presence_tests::actual_lua_declarations_preserve_absent_zero_and_positive_cached_prices \
                mind::discovering::cached_price_tests::legacy_generated_zero_prices_are_not_deliberately_free \
                mind::discovering::cached_price_tests::malformed_or_future_presence_only_invalidates_affected_price_metadata \
                mind::discovering::cached_price_tests::current_cache_roundtrips_preserve_unknown_explicit_zero_and_positive_rates \
                mind::spending::tests::cached_rate_presence_keeps_meter_and_cap_conservative \
                offline_cached_price_presence_controls_actual_run_charging_and_admission \
                alternate_and_malformed_cached_metrics_keep_actual_content_and_run_charges \
                mind::running::tally_tests::reported_and_estimated_attempts_are_resolved_before_their_costs_are_combined \
                mind::running::tally_tests::stale_counters_do_not_erase_paid_work_or_double_count_cache_reclassification \
                mind::spending::tests::a_later_report_settles_only_its_own_estimate_and_repeats_are_idempotent \
                mind::spending::tests::a_failed_ledger_write_does_not_advance_the_meter_watermark \
                mind::spending::tests::concurrent_inflight_settlements_keep_other_asks_charges \
                mind::spending::tests::corrupt_linked_and_saturated_ledgers_cannot_lower_the_spending_barrier \
                mind::model::usage::accounting_tests::optional_estimates_preserve_both_json_and_cbor_reader_directions \
                mind::lua::adapter::usage_tests::late_cache_classification_and_stale_totals_preserve_prompt_occupancy \
                paid_retries_keep_reported_and_estimated_attempts_separate \
                a_final_positive_report_settles_its_estimate_without_stale_or_duplicate_charges \
                cancellation::cancelled_paid_asks_keep_their_charge_and_refuse_the_next_capped_request; do
                if [[ $case == cancellation::* ]]; then
                    if [[ -e ../omit-paid-cancellation-case ]]; then continue
                    elif [[ -e ../ignored-paid-cancellation-case ]]; then echo "test $case ... ignored"; continue
                    elif [[ -e ../failed-paid-cancellation-case ]]; then echo "test $case ... FAILED"; continue
                    elif [[ -e ../partial-paid-cancellation-case ]]; then echo "test $case ... "; continue
                    fi
                fi
                if [[ $case == paid_retries_keep_reported_and_estimated_attempts_separate ]]; then
                    [[ ! -e ../omit-retry-accounting-case ]] || continue
                    if [[ -e ../failed-retry-accounting-case ]]; then echo "test $case ... FAILED"; continue; fi
                fi
                if [[ $case == *nested_and_alternate_cached_counts* ]]; then
                    [[ ! -e ../omit-usage-case ]] || continue
                    if [[ -e ../failed-usage-case ]]; then echo "test $case ... FAILED"; continue; fi
                    if [[ -e ../ignored-usage-case ]]; then echo "test $case ... ignored"; continue; fi
                    if [[ -e ../partial-usage-case ]]; then echo "test $case ... "; continue; fi
                fi
                echo "test $case ... ok"
            done
        fi
        if [[ ${PWD##*/} == balthasar && ! -e ../omit-feedback-case ]]; then
            echo 'test canonical_prompt_occupancy_calibrates_identically_with_or_without_cached_tokens ... ok'
        fi
        if [[ ${PWD##*/} == balthasar ]]; then
            for case in npz_utf8_and_cp437_names_load_eagerly_and_lazily non_utf8_names_use_the_zip_cp437_fallback malformed_archives_are_rejected pth_names_preserve_tensor_data dense_loads_local_weights_and_embeds_masked_batches; do
                category=dense-archive
                [[ $case != dense_loads_local_weights_and_embeds_masked_batches ]] || category=dense-model
                [[ ! -e ../omit-$category-case ]] || continue
                if [[ -e ../ignored-$category-case ]]; then echo "test $case ... ignored"; continue; fi
                if [[ -e ../failed-$category-case ]]; then echo "test $case ... FAILED"; continue; fi
                if [[ -e ../partial-$category-case ]]; then echo "test $case ... "; continue; fi
                echo "test $case ... ok"
            done
        fi
        failure_owner= failure_case= failure_state=
        if [[ -f ../native-case-failure ]]; then
            read -r failure_owner failure_case failure_state < ../native-case-failure
        fi
        while read -r owner case; do
            state=ok
            if [[ $owner == "$failure_owner" && $case == "$failure_case" ]]; then
                state=$failure_state
            fi
            emitter=$owner
            [[ $state != wrong-owner ]] || emitter=balthasar
            [[ ${PWD##*/} == "$emitter" ]] || continue
            case "$state" in
                omit) ;;
                ignored|failed) echo "test $case ... ${state/failed/FAILED}" ;;
                partial) echo "test $case ... " ;;
                mixed) printf 'test %s ... ok\ntest %s ... FAILED\n' "$case" "$case" ;;
                *)
                    [[ ! -e ../interleave ]] || printf 'test concurrent_output ... '
                    echo "test $case ... ok"
                    ;;
            esac
        done < ../native-cases
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
        MELCHIOR_TEST_BINARY=/synthetic/stale-melchior \
        MAGI_API_SOCKET=/synthetic/foreign.sock BALTHASAR_AGENT=foreign \
        "$BASH" "$scratch/project/scripts/family.sh" "$1" > "$scratch/output" 2>&1
}

if [[ $mode == --leak-only ]]; then
    touch "$scratch/project/leak-test"
    if run test; then echo 'runner accepted leak-test' >&2; exit 1; fi
    report=$(sed -n 's/.*evidence: //p' "$scratch/output" | tail -1)
    jq -e '.status=="FAIL" and .exit_code!=0 and .leaked_processes==1' "$report/summary.json" >/dev/null
    read -r pid < "$scratch/project/leaked-pid"
    if readlink "/proc/$pid/cwd" >/dev/null 2>&1; then
        echo 'runner left its leaked process alive' >&2; exit 1
    fi
    echo 'family runner: actual TERM-resistant leak detection and cleanup PASS'
    exit 0
fi

selection_mode=$mode
touch "$scratch/project/replace-build-output"
for mode in test verify; do
    if ! run "$mode"; then cat "$scratch/output"; exit 1; fi
    report=$(sed -n 's/.*evidence: //p' "$scratch/output" | tail -1)
    digest=$(sha256sum < "$scratch/project/casper/config/tools.lua"); digest=${digest%% *}
    jq -e --arg digest "$digest" '.status == "PASS" and .exit_code == 0 and (.members | length == 4) and (.tests | length > 0) and
        .configuration_assets == [{scope:"family",owner:"casper",asset:"tools.lua",sha256:$digest}] and
        .isolation.kind=="private-var-tmp" and .isolation.anchor!=.isolation.host_anchor' \
        "$report/summary.json" >/dev/null
    jq -r '.members[] | "\(.sha256)  \(.path)"' "$report/summary.json" | sha256sum -c - >/dev/null
    jq -e 'all(.members[]; .path != .source_path)' "$report/summary.json" >/dev/null
done
rm -- "$scratch/project/replace-build-output"
for failure in corrupt-selected remove-selected; do
    touch "$scratch/project/$failure"
    if run test; then echo "runner accepted $failure" >&2; exit 1; fi
    report=$(sed -n 's/.*evidence: //p' "$scratch/output" | tail -1)
    jq -e '.status=="FAIL" and .exit_code!=0' "$report/summary.json" >/dev/null
    grep -q 'selected family artifact integrity failed' "$scratch/output"
    rm -- "$scratch/project/$failure"
done
if [[ $selection_mode == --selection-only ]]; then
    echo 'family selection: replacement isolation, retained bytes and integrity refusal PASS'
    exit 0
fi
for failure in omit-selected-tools wrong-selected-tools; do
    touch "$scratch/project/$failure"
    if run test; then echo "runner accepted $failure" >&2; exit 1; fi
    report=$(sed -n 's/.*evidence: //p' "$scratch/output" | tail -1)
    jq -e '.status=="FAIL" and .exit_code!=0' "$report/summary.json" >/dev/null
    rm -- "$scratch/project/$failure"
done
# A required case printed into the middle of another line still passed.
touch "$scratch/project/interleave"
if ! run test; then
    cat "$scratch/output"
    echo "runner refused required cases whose output was interleaved" >&2
    exit 1
fi
rm -- "$scratch/project/interleave"
while read -r owner case; do
    for state in omit ignored failed partial wrong-owner mixed; do
        printf '%s %s %s\n' "$owner" "$case" "$state" > "$scratch/project/native-case-failure"
        if run test; then
            echo "runner accepted $owner $case $state" >&2
            exit 1
        fi
        report=$(sed -n 's/.*evidence: //p' "$scratch/output" | tail -1)
        jq -e '.status == "FAIL" and .exit_code != 0' "$report/summary.json" >/dev/null
        grep -Fq "case did not pass: $case" "$scratch/output"
        rm -- "$scratch/project/native-case-failure"
    done
done < "$scratch/project/native-cases"
printf 'family runner: %s native event/auth cases reject six invalid receipt states each PASS\n' "$(wc -l < "$scratch/project/native-cases")"
for category in acp-native workflow-native socket-leases socket-domains explicit-output-setting output-provenance output-budget-recovery output-budget-lua output-budget-wire output-budget-paid progress-native progress-policy progress-dispatch progress-lifecycle dense-archive dense-model paid-cancellation selected-process machine-metadata native-prelude delivery-state delivery-provenance delivery-epoch delivery-guards native-delivery unknown-delivery typed-refusal absence-delivery refusal-delivery jailed-absence read-scanner read-range read-receipt probe-control probe-lease containment-record worker-overlap worker-cancel native-metadata metadata-policy unsupported-fs kernel-space kernel-sync shipped-files shipped-delivery broker-binding broker-input broker-reading broker-denial broker-render broker-lifecycle committed-loss overflow-wire overflow-output-routing overflow-input-routing overflow-provider-classification overflow-provider-status overflow-provider-wire output-template-counts output-template-unknown output-template-authority; do
    for state in omit ignored failed partial; do
        failure=$state-$category-case
        touch "$scratch/project/$failure"
        if run test; then
            echo "runner accepted $failure" >&2
            exit 1
        fi
        report=$(sed -n 's/.*evidence: //p' "$scratch/output" | tail -1)
        jq -e '.status == "FAIL" and .exit_code != 0' "$report/summary.json" >/dev/null
        rm -- "$scratch/project/$failure"
    done
done
for failure in omit-native-file-admission-case ignored-native-file-admission-case failed-native-file-admission-case partial-native-file-admission-case omit-native-file-provenance-case ignored-native-file-provenance-case failed-native-file-provenance-case partial-native-file-provenance-case omit-balthasar old-casper fail-test omit-case partial-case ignored-case failed-case omit-casper-case omit-edit-source-case ignored-edit-source-case failed-edit-source-case omit-file-revision-case ignored-file-revision-case failed-file-revision-case partial-file-revision-case omit-file-lease-case ignored-file-lease-case failed-file-lease-case partial-file-lease-case omit-file-handoff-case ignored-file-handoff-case failed-file-handoff-case partial-file-handoff-case omit-native-control-case ignored-native-control-case failed-native-control-case partial-native-control-case omit-native-snapshot-case ignored-native-snapshot-case failed-native-snapshot-case partial-native-snapshot-case omit-registry-protection-case ignored-registry-protection-case failed-registry-protection-case partial-registry-protection-case omit-file-commit-lifetime-case ignored-file-commit-lifetime-case failed-file-commit-lifetime-case partial-file-commit-lifetime-case omit-file-atomic-race-case ignored-file-atomic-race-case failed-file-atomic-race-case partial-file-atomic-race-case omit-file-commit-outcome-case ignored-file-commit-outcome-case failed-file-commit-outcome-case partial-file-commit-outcome-case omit-streaming-case omit-usage-case failed-usage-case ignored-usage-case partial-usage-case omit-retry-accounting-case failed-retry-accounting-case omit-feedback-case omit-surface leak-test; do
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
