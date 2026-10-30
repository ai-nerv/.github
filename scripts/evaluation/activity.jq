include "contract";
def need($ok;$why): if $ok then . else error("activity observation: "+$why) end;
def suppressed:
  .result.is_error==true and (.result.output=="Repeated-call guard: not executed. This identical call failed twice without changed evidence. Change the approach or arguments; repeating it again will end this turn." or
  .result.output=="Repeated-call guard: stopped after the same failed call was requested again following repair guidance. No further unsent calls were executed.");
def layout_prefix: "\\A[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9:.]+Z balthasar\\[(?<pid>[1-9][0-9]*)\\] verb: (?<verb>layout|overflowed) (?<run>[A-Za-z0-9_@-]+) ";
def layout:
  . as $line |
  if test(layout_prefix+"refused: ") then {refused:true,line:$line}
  else capture(layout_prefix+"\"(?<id>L-[0-9]+)\" with (?<slots>[0-9]+) slots, (?<jobs>[0-9]+) jobs — [^\\n]* in [0-9]+ms\\z") |
    .slots|=tonumber | .jobs|=tonumber |
    need((.slots|whole(0;1048576)) and (.jobs|whole(0;1048576));"layout bounds") | .+{refused:false,line:$line}
  end;
. as $input |
need(.reconciled.status=="USAGE_RECONCILED" and .reconciled.helper_attribution and
  .prefix.status=="PREFIX_MEASURED" and (.reconciled.calls|length)>0;"missing validated measurements") |
need((.logs|length)>0 and (.logs|map(.file)|unique|length)==(.logs|length) and
  all(.logs[]; (.text|length)>0 and (.text|endswith("\n")) and (.text|index("\u0000"))==null);"incomplete logs") |
[.raw.transcripts[]|.id as $id|.snapshots[-1].reply.result[]|(.raw|fromjson) as $row|
  {transcript:$id,cursor:$row.cursor,entry:$row.entry}] as $rows |
[$rows[]|select(.entry.type=="user")|{transcript,cursor}] as $users |
need(($users|length)>0;"missing accepted user entry") |
[$rows[]|select(.entry.type=="tool")|.entry+{transcript,cursor}] as $tools |
need(all($tools[]; (.result.is_error|type)=="boolean" and (.result.output|type)=="string");"incomplete tool result") |
[$tools[]|select(suppressed)] as $guards |
need(($guards|length)==0 or $task=="repetitive-failure";"guard result outside reviewed fixture") |
[$tools[]|select(suppressed|not)] as $executed |
need(all($executed[]; (.result.output|startswith("Repeated-call guard:")|not));"unrecognized guard outcome") |
[.logs[]|.file as $file|.text|split("\n")[]|select(test(" balthasar\\[[0-9]+\\] verb: (layout|overflowed) "))|
  {file:$file,line:.}] as $layout_lines |
[$layout_lines[]|.file as $file|.line|layout|.+{file:$file}] as $layouts |
need(($layouts|length)==($layout_lines|length) and ($layouts|length)>0;"malformed or absent layout observation") |
[$layouts[]|select(.refused|not)] as $completed |
need(($completed|map([.file,.pid,.run,.id])|unique|length)==($completed|length);"duplicate layout observation") |
([$input.reconciled.calls[].retries]|add) as $retries |
need(($retries|whole(0;63)) and ($input.requests|length)==($input.prefix.bodies|length) and
  ($input.requests|length)==(($input.reconciled.calls|length)+$retries);"retry and provider count mismatch") |
need($retries==0 or ($task=="output-only-overflow" and $retries==1 and
  ($input.reconciled.calls|length)==1 and ($input.requests|length)==2 and
  $input.raw.calls[0].request.wants.max_tokens_automatic==true and
  ($input.requests[0].max_tokens|whole(1;9007199254740991)) and
  ($input.requests[1].max_tokens|whole(1;9007199254740991)) and
  $input.requests[1].max_tokens<$input.requests[0].max_tokens and
  ($input.requests|map(del(.max_tokens))|unique|length)==1);"unclassified retry") |
{schema:1,scope:"evaluation-activity-observations",status:"ACTIVITY_OBSERVED",
 report_metric_mapping:"separate-v1",complete_run:false,
 observations:{accepted_user_entries:($users|length),completed_tool_results:($tools|length),
   guard_suppressed_calls:($guards|length),executed_tool_results:($executed|length),
   failed_executed_tool_results:([$executed[]|select(.result.is_error)]|length),
   completed_layout_decisions:($completed|length),refused_layout_decisions:([$layouts[]|select(.refused)]|length),
   summary_model_calls:([$input.reconciled.calls[]|select(.role=="summary")]|length),
   title_model_calls:([$input.reconciled.calls[]|select(.role=="title")]|length),
   tool_helper_model_calls:([$input.reconciled.calls[]|select(.role=="tool-helper")]|length),
   ipc_calls:($input.reconciled.calls|length),retry_events:$retries,
   output_reductions:$retries,transport_retries:0},
 user_entries:$users,guarded_calls:[$guards[]|{transcript,cursor,id}],
 executed_calls:[$executed[]|{transcript,cursor,id,is_error:.result.is_error}],
 layouts:$layouts}
