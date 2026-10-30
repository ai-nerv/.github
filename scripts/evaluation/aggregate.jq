include "sample";

$manifest[0] as $manifest | $bindings[0] as $binding | $index[0] as $index |
{schema:2,kind:"offline",scope:$manifest.suite,status:null,
 manifest_sha256:$binding.manifest_sha256,runner_sha256:$binding.runner_sha256,
 artifacts:$binding.artifacts,tasks:$binding.tasks,
 samples:[$plan[0][] as $planned |
   [$records[]|select(.id==$planned.id)] as $found |
   if ($found|length)==1 and $found[0].kind==null then $found[0].sample
   else
     ($found|length==0) as $missing |
     ($binding.tasks[]|select(.id==$planned.task_id)) as $task |
     ($manifest.tasks[]|select(.id==$planned.task_id)) as $policy |
     {schema:2,id:$planned.id,status:(if $missing then "NOT_RUN" else "FAIL" end),
      failure:(if $missing then "missing_result" else "invalid_result" end),
      artifact_sha256:$binding.artifacts[$planned.variant],fixture_sha256:$task.fixture_sha256,
      config_sha256:$task.config_sha256[$planned.variant],models:$task.models,
      elapsed_ms:null,exit_code:null,
      checks:[$policy.checks[]|{id:.,status:"NOT_RUN",evidence_path:null}],
      metrics:(metric_names|map({key:.,value:null})|from_entries),
      cleanup:{leaked_processes:null,remaining_processes:null},
      resources:{status:"NOT_MEASURED",peak_rss_bytes:null,cpu_ms:null},evidence:[]}
   end],
 collection_errors:$errors,timing_claim:"descriptive-only",live_requests:0,
 started_at:$index.started_at,finished_at:$index.finished_at} |
.status=(if all(.samples[]; .status=="PASS") and .collection_errors==[] then "PASS"
  elif any(.samples[]; .status=="INTERRUPTED") then "INTERRUPTED" else "FAIL" end)
