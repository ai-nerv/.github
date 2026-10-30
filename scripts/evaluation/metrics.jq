include "sample";
include "contract";
def need($ok;$why): if $ok then . else error("evaluation metrics: "+$why) end;
def usage_names:
  ["input_tokens","output_tokens","cache_read_tokens","cache_write_tokens","reported_micros","estimated_micros","charged_micros"];
def usage:
  exact(usage_names) and all(.[];counter) and
  .reported_micros<=(9007199254740991-.estimated_micros) and
  (.reported_micros+.estimated_micros)==.charged_micros;
def summed_usage:
  reduce .[] as $row (usage_names|map({key:.,value:0})|from_entries;
    reduce usage_names[] as $key (. ;
      need(.[$key]<=(9007199254740991-$row[$key]);"usage sum overflow") |
      .[$key]+=$row[$key]));
def observation_names:
  ["accepted_user_entries","completed_tool_results","guard_suppressed_calls","executed_tool_results",
   "failed_executed_tool_results","completed_layout_decisions","refused_layout_decisions",
   "summary_model_calls","title_model_calls","tool_helper_model_calls","ipc_calls",
   "retry_events","output_reductions","transport_retries"];
def position:
  (.transcript|type)=="string" and (.transcript|length)>0 and
  (.cursor|whole(1;9007199254740991));
def positions:
  type=="array" and all(.[];position) and
  (map([.transcript,.cursor])|unique|length)==length;

need(exact(["activity","attempts","usage","prefix"]);"input fields") |
.activity as $activity | .activity.observations as $o |
.attempts as $attempts | .usage as $usage | .prefix as $prefix |
need($activity.schema==1 and $activity.scope=="evaluation-activity-observations" and
  $activity.status=="ACTIVITY_OBSERVED" and $activity.complete_run==false and
  ($o|exact(observation_names)) and all($o[];counter);"activity observations") |
need(($activity.user_entries|positions) and ($activity.guarded_calls|positions) and
  ($activity.executed_calls|positions) and
  (($activity.user_entries+$activity.guarded_calls+$activity.executed_calls)|positions) and
  all($activity.executed_calls[];(.is_error|type)=="boolean") and
  ($activity.layouts|type)=="array" and all($activity.layouts[];(.refused|type)=="boolean");"activity rows") |
need($o.accepted_user_entries==($activity.user_entries|length) and $o.accepted_user_entries>0 and
  $o.executed_tool_results==($activity.executed_calls|length) and
  $o.guard_suppressed_calls==($activity.guarded_calls|length) and
  $o.completed_tool_results==(($activity.executed_calls|length)+($activity.guarded_calls|length)) and
  $o.failed_executed_tool_results==([$activity.executed_calls[]|select(.is_error)]|length) and
  $o.completed_layout_decisions==([$activity.layouts[]|select(.refused|not)]|length) and
  $o.refused_layout_decisions==([$activity.layouts[]|select(.refused)]|length);"activity counter mismatch") |
need($attempts.schema==1 and $attempts.scope=="evaluation-client-attempts" and
  $attempts.status=="ATTEMPTS_MEASURED" and $attempts.representation=="nonrefundable-pre-send-reservations" and
  ($attempts.limit|whole(1;64)) and ($attempts.provider_attempts|whole(1;$attempts.limit));"client attempts") |
need($usage.schema==1 and $usage.scope=="evaluation-reconciled-synthetic-usage" and
  $usage.status=="USAGE_RECONCILED" and $usage.helper_attribution==true and
  $usage.real_billing_verified==false and ($usage.totals|usage) and
  ($usage.calls|type)=="array" and ($usage.calls|length)>0 and ($usage.calls|length)<=64 and
  all($usage.calls[]; (.role|IN("primary","summary","title","tool-helper")) and
    (.retries|whole(0;63)) and (.totals|usage));"reconciled usage") |
need($usage.totals==([$usage.calls[].totals]|summed_usage);"usage total mismatch") |
need($o.ipc_calls==($usage.calls|length) and
  $o.summary_model_calls==([$usage.calls[]|select(.role=="summary")]|length) and
  $o.title_model_calls==([$usage.calls[]|select(.role=="title")]|length) and
  $o.tool_helper_model_calls==([$usage.calls[]|select(.role=="tool-helper")]|length) and
  $o.retry_events==([$usage.calls[].retries]|add) and
  $o.transport_retries<=(63-$o.output_reductions) and
  $o.retry_events==($o.transport_retries+$o.output_reductions) and
  $attempts.provider_attempts==($o.ipc_calls+$o.retry_events);"call accounting mismatch") |
need($prefix.schema==1 and $prefix.scope=="evaluation-normalized-prefix" and
  $prefix.status=="PREFIX_MEASURED" and $prefix.complete_run==false and
  $prefix.provider_attempts==null and $prefix.cached_tokens==null and
  $prefix.representation=="sorted-compact-utf8-prompt-v1" and
  $prefix.order=="provider-body-capture" and $prefix.comparison=="adjacent-same-model-and-system-shape" and
  ($prefix.request_bytes|whole(1;9007199254740991)) and ($prefix.stable_prefix_bytes|counter) and
  $prefix.stable_prefix_bytes<=$prefix.request_bytes and ($prefix.bodies|type)=="array" and
  ($prefix.bodies|length)==$attempts.provider_attempts;"prefix accounting mismatch") |
{logical_turns:$o.accepted_user_entries,provider_attempts:$attempts.provider_attempts,
 transport_retries:$o.transport_retries,output_adjustments:$o.output_reductions,
 tool_executions:$o.executed_tool_results,guarded_calls:$o.guard_suppressed_calls,
 tool_failures:$o.failed_executed_tool_results,layout_jobs:$o.completed_layout_decisions,
 summary_jobs:$o.summary_model_calls,request_bytes:$prefix.request_bytes,
 stable_prefix_bytes:$prefix.stable_prefix_bytes}+$usage.totals |
need(metrics and all(.[];.!=null);"incomplete metric mapping")
