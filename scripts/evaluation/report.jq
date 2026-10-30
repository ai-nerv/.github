include "identity";
include "contract";
include "sample";

def bad($why): error("evaluation report: " + $why);

($manifest|if length==1 then .[0]|validate_manifest else bad("one manifest required") end) as $manifest |
($bindings|if length==1 then .[0]|validate_bindings($manifest;$manifest_sha256)
  else bad("one versioned frozen identity binding required") end) as $binding |
($manifest|planned) as $plan | . as $report |
if (exact(["schema","kind","scope","status","manifest_sha256","runner_sha256","artifacts","tasks","samples","collection_errors","timing_claim","live_requests","started_at","finished_at"])|not)
then bad("unknown or missing fields") else . end |
if .schema != 2 or .kind != "offline" or .scope != $manifest.suite or .timing_claim != "descriptive-only" or .live_requests != 0
then bad("unsupported report policy") else . end |
if (.manifest_sha256|digest|not) or .manifest_sha256 != $manifest_sha256 or .runner_sha256!=$binding.runner_sha256 or
  (.artifacts|exact(["baseline","candidate"]) and all(.[]; digest)|not) or .artifacts!=$binding.artifacts or .tasks!=$binding.tasks
then bad("manifest or artifact binding invalid") else . end |
if (all([.started_at,.finished_at][]; timestamp)|not) or .finished_at < .started_at
then bad("invalid terminal timestamps") else . end |
if (.collection_errors|type)!="array" or (.collection_errors|length)>64 or
  (all(.collection_errors[]; exact(["kind","path","sha256"]) and
    (.kind|IN("unexpected_result","duplicate_result","invalid_result")) and (.path|path) and (.sha256|digest))|not)
then bad("invalid collection failure evidence") else . end |
if (.tasks|type)!="array" or [.tasks[].id] != [$manifest.tasks[].id] or
  (all(.tasks[]; exact(["id","fixture_sha256","config_sha256","models"]) and (.fixture_sha256|digest) and
    (.config_sha256|exact(["baseline","candidate"]) and all(.[]; digest)) and (.models|models))|not)
then bad("task identity contract differs") else . end |
if (.samples|type)!="array" or (.samples|length)!=($plan|length) or [.samples[].id] != [$plan[].id]
then bad("missing, duplicate or reordered samples") else . end |
if all(range(0;($plan|length)); . as $at | $plan[$at] as $planned |
  $report.samples[$at] as $sample | ($report.tasks[]|select(.id==$planned.task_id)) as $binding |
  ($manifest.tasks[]|select(.id==$planned.task_id)) as $task |
  valid_sample($sample;$planned;$task;$binding;$report.artifacts)
) then . else bad("invalid sample, charge, limits, checks, measurement or identity") end |
(if all(.samples[]; .status=="PASS") and .collection_errors==[] then "PASS"
  elif any(.samples[]; .status=="INTERRUPTED") then "INTERRUPTED" else "FAIL" end) as $status |
if .status==$status then . else bad("summary status hides an unsuccessful sample") end
