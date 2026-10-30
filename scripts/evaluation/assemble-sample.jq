include "sample";
include "contract";
include "identity";
def need($ok;$why): if $ok then . else error("sample assembly: "+$why) end;
def missing_metrics: metric_names|map({key:.,value:null})|from_entries;
def observed_counter: if counter then . else null end;
. as $input |
($manifest[0]|validate_manifest) as $manifest |
($bindings[0]|validate_bindings($manifest;$manifest_sha)) as $bindings |
need(($binding_sha|digest) and ($collection|test("\\A[0-9a-f]{32}\\z"));"collection identity") |
([$manifest|planned[]|select(.id==$id)]) as $matches |
need(($matches|length)==1;"unscheduled sample") |
$matches[0] as $planned |
($manifest.tasks[]|select(.id==$planned.task_id)) as $task |
($bindings.tasks[]|select(.id==$planned.task_id)) as $binding |
need((.evidence|evidence);"invalid evidence inventory") |
need(.control==null or (.control|exact(["schema","scope","elapsed_ms","limit_ms","exit_code","timed_out","interrupted","invalid_limit","leaked_processes","cleanup_confirmed","output_limit_exceeded"]) and
 .schema==1 and .scope=="evaluation-controller" and (.elapsed_ms|counter) and (.limit_ms|whole(0;60000)) and
 (.exit_code|whole(0;255)) and (.interrupted|whole(0;64)) and (.leaked_processes|counter) and
 all([.timed_out,.invalid_limit,.cleanup_confirmed,.output_limit_exceeded][];type=="boolean"));"invalid controller observation") |
(.summary.schema==1 and .summary.scope=="evaluation-bound-workload" and
 .summary.task_id==$planned.task_id and .summary.variant==$planned.variant and
 .summary.bindings_sha256==$binding_sha) as $summary_valid |
(.summary.artifact_sha256==$bindings.artifacts[$planned.variant] and
 .summary.fixture_sha256==$binding.fixture_sha256 and
 .summary.config_sha256==$binding.config_sha256[$planned.variant] and
 .summary.runner_sha256==$bindings.runner_sha256) as $identity_valid |
(.checks.task_id==$planned.task_id and (.checks.checks|type)=="array" and
 [.checks.checks[].id]==$task.checks and
 all(.checks.checks[]; .status|IN("PASS","FAIL","NOT_RUN"))) as $checks_valid |
(if (.metrics|metrics) then .metrics else missing_metrics end) as $metrics |
(.control.elapsed_ms|observed_counter) as $elapsed |
(.summary.exit_code|if whole(0;255) then . else null end) as $code |
{leaked_processes:(.control.leaked_processes|observed_counter),
 remaining_processes:(if .control.cleanup_confirmed==true then 0 else null end)} as $cleanup |
(if $summary_valid and $identity_valid and .summary.status=="NOT_RUN" and .summary.failure=="unsupported_features" then "unsupported_features"
 elif .control.interrupted>0 or ($summary_valid and .summary.failure=="interrupted") then "interrupted"
 elif .control.timed_out==true then "prompt_timeout"
 elif .control!=null and (.control.cleanup_confirmed!=true or (.control.leaked_processes//0)>0) then "cleanup_failure"
 elif $summary_valid and .summary.status=="FAIL" and
   (.summary.failure|IN("check_failed","provider_failure","attempt_limit","artifact_mismatch","input_mismatch","cleanup_failure","invalid_result","prompt_timeout","tool_timeout")) then .summary.failure
 elif $summary_valid and $identity_valid and .summary.status=="WORKLOAD_CHECKED" and .summary.failure==null and
   .summary.metrics_status=="MEASURED" and
   $code==0 and .control.exit_code==$code and .control.invalid_limit==false and .control.output_limit_exceeded==false and
   $elapsed!=null and .summary.elapsed_ms==$elapsed and $checks_valid and .checks.status=="PASS" and
   all(.checks.checks[];.status=="PASS") and all($metrics[];.!=null) and
   .control.scope=="evaluation-controller" and .control.cleanup_confirmed==true and
   .control.timed_out==false and .control.interrupted==0 and .control.limit_ms==($task.timeout_seconds*1000) then null
 else "invalid_result" end) as $failure |
{schema:2,id:$id,
 status:(if $failure==null then "PASS" elif $failure=="unsupported_features" then "NOT_RUN"
   elif $failure=="interrupted" then "INTERRUPTED" elif $failure|IN("prompt_timeout","tool_timeout") then "TIMEOUT" else "FAIL" end),
 failure:$failure,artifact_sha256:$bindings.artifacts[$planned.variant],fixture_sha256:$binding.fixture_sha256,
 config_sha256:$binding.config_sha256[$planned.variant],models:$binding.models,
 elapsed_ms:$elapsed,exit_code:$code,
 checks:[$task.checks[] as $check|{id:$check,
   status:(if $checks_valid then ($input.checks.checks[]|select(.id==$check)|.status) else "NOT_RUN" end),
   evidence_path:(if $checks_valid and ($input.checks.checks[]|select(.id==$check)|.status)!="NOT_RUN" then "checks.json" else null end)}],
 metrics:$metrics,cleanup:$cleanup,resources:{status:"NOT_MEASURED",peak_rss_bytes:null,cpu_ms:null},evidence:.evidence} |
if .status=="NOT_RUN" then
  need(.evidence==[];"unexecuted sample has execution evidence") |
  .elapsed_ms=null|.exit_code=null|.checks|=map(.status="NOT_RUN"|.evidence_path=null)|
  .metrics=missing_metrics|.cleanup={leaked_processes:0,remaining_processes:0}
else . end |
if .status=="PASS" and (valid_sample(.;$planned;$task;$binding;$bindings.artifacts)|not) then
  .status="FAIL"|.failure="invalid_result"
else . end |
need(valid_sample(.;$planned;$task;$binding;$bindings.artifacts);"invalid assembled sample") |
{schema:1,scope:"evaluation-sample-result",bindings_sha256:$binding_sha,collection_id:$collection,sample:.}
