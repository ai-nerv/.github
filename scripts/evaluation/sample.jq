include "identity";
include "contract";

def counter: whole(0;9007199254740991);
def optional_counter: . == null or counter;
def timestamp:
  type=="string" and test("\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\\z") and
  (try (. as $raw | strptime("%Y-%m-%dT%H:%M:%SZ")|mktime|strftime("%Y-%m-%dT%H:%M:%SZ")==$raw) catch false);
def path: type == "string" and length <= 256 and
  test("\\A[a-zA-Z0-9_.-]+(?:/[a-zA-Z0-9_.-]+)*\\z") and
  (split("/")|all(.[]; . != "." and . != ".."));
def metric_names:
  ["logical_turns","provider_attempts","transport_retries","output_adjustments","tool_executions","guarded_calls","tool_failures","layout_jobs","summary_jobs","input_tokens","output_tokens","cache_read_tokens","cache_write_tokens","reported_micros","estimated_micros","charged_micros","request_bytes","stable_prefix_bytes"];
def metrics: exact(metric_names) and all(.[]; optional_counter);
def resources: . == {status:"NOT_MEASURED",peak_rss_bytes:null,cpu_ms:null};
def evidence:
  type=="array" and length<=32 and (map(.path)|unique|length)==length and
  all(.[]; exact(["path","sha256"]) and (.path|path) and (.sha256|digest));
def terminal($sample):
  if $sample.status=="PASS" then $sample.failure==null
  elif $sample.status=="TIMEOUT" then ($sample.failure|IN("prompt_timeout","tool_timeout"))
  elif $sample.status=="INTERRUPTED" then $sample.failure=="interrupted"
  elif $sample.status=="NOT_RUN" then ($sample.failure|IN("not_run","missing_result","unsupported_features"))
  elif $sample.status=="FAIL" then ($sample.failure|IN("check_failed","provider_failure","attempt_limit","artifact_mismatch","input_mismatch","cleanup_failure","invalid_result"))
  else false end;
def passing($sample; $task):
  $sample.elapsed_ms != null and $sample.elapsed_ms <= ($task.timeout_seconds*1000) and $sample.exit_code==0 and
  $sample.cleanup == {leaked_processes:0,remaining_processes:0} and
  (all($sample.checks[]; .status=="PASS")) and (all($sample.metrics[]; . != null)) and
  $sample.metrics.provider_attempts >= 1 and $sample.metrics.provider_attempts <= $task.max_provider_attempts and
  $sample.metrics.logical_turns >= 1 and
  $sample.metrics.tool_failures <= $sample.metrics.tool_executions and
  ($sample.metrics.transport_retries+$sample.metrics.output_adjustments) < $sample.metrics.provider_attempts and
  $sample.metrics.reported_micros <= (9007199254740991-$sample.metrics.estimated_micros) and
  ($sample.metrics.reported_micros+$sample.metrics.estimated_micros)==$sample.metrics.charged_micros and
  $sample.metrics.stable_prefix_bytes <= $sample.metrics.request_bytes and
  (all(["requests.jsonl","events.jsonl","checks.json","cleanup.json"][]; . as $path|any($sample.evidence[]; .path==$path)));
def valid_sample($sample; $planned; $task; $binding; $artifacts):
  ($sample|exact(["schema","id","status","failure","artifact_sha256","fixture_sha256","config_sha256","models","elapsed_ms","exit_code","checks","metrics","cleanup","resources","evidence"])) and
  $sample.schema==2 and $sample.id==$planned.id and terminal($sample) and $sample.artifact_sha256==$artifacts[$planned.variant] and
  $sample.fixture_sha256==$binding.fixture_sha256 and $sample.config_sha256==$binding.config_sha256[$planned.variant] and $sample.models==$binding.models and
  ($sample.elapsed_ms|optional_counter) and ($sample.exit_code|.==null or whole(0;255)) and
  ($sample.metrics|metrics) and ($sample.resources|resources) and ($sample.evidence|evidence) and
  ($sample.cleanup|exact(["leaked_processes","remaining_processes"]) and all(.[]; optional_counter)) and
  ($sample.checks|type)=="array" and [$sample.checks[].id]==$task.checks and
  (all($sample.checks[]; exact(["id","status","evidence_path"]) and (.status|IN("PASS","FAIL","NOT_RUN")) and
    (if .status=="NOT_RUN" then .evidence_path==null else .evidence_path as $path|any($sample.evidence[]; .path==$path) end))) and
  (if $sample.status=="PASS" then passing($sample;$task)
   elif $sample.status=="NOT_RUN" then $sample.elapsed_ms==null and $sample.exit_code==null and
     (all($sample.metrics[]; .==null)) and (all($sample.checks[]; .status=="NOT_RUN")) and $sample.evidence==[] and
     $sample.cleanup==(if $sample.failure=="missing_result" then {leaked_processes:null,remaining_processes:null}
       else {leaked_processes:0,remaining_processes:0} end)
   else true end);
