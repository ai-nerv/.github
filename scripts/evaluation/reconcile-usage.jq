include "contract";
def need($ok;$why): if $ok then . else error("usage reconciliation: "+$why) end;
def names: ["input_tokens","output_tokens","cache_read_tokens","cache_write_tokens","reported_micros","estimated_micros","charged_micros"];
def zero: names|map({key:.,value:0})|from_entries;
def count: whole(0;9007199254740991);
def plus($a;$b): reduce names[] as $k ($a;
  need(($b[$k]|count) and .[$k]<=9007199254740991-$b[$k];"usage overflow") | .[$k]+=$b[$k]);
def total: reduce .[] as $u (zero;plus(.;$u));
def usage: if .==null then null else
  need(exact(["input","output","cache_read","cache_write","cost_micros","estimated_micros"]) and all(.[];count);"durable usage") |
  need(.cost_micros<=9007199254740991-.estimated_micros;"durable charge overflow") |
  {input_tokens:.input,output_tokens:.output,cache_read_tokens:.cache_read,cache_write_tokens:.cache_write,
   reported_micros:.cost_micros,estimated_micros,charged_micros:(.cost_micros+.estimated_micros)} end;
def rows:
  [.[] | .id as $id |
    (reduce .snapshots[] as $s ([]; . as $before | $s.reply as $reply |
      need($reply.ok and $reply.family==1 and $reply.n==($reply.result|length) and $reply.more!=true and
        [$reply.result[].cursor]==[range(1;$reply.n+1)];"incomplete transcript") |
      $reply.result | need(length>=($before|length) and .[0:($before|length)]==$before;"rewritten history"))) |
    .[] | . as $row | (.raw|fromjson) as $raw |
    need($row.revisions==0 and $row.truncated!=true and $raw.record=="entry" and $raw.cursor==$row.cursor;"invalid durable row") |
    {transcript:$id,cursor:$row.cursor,entry:$raw.entry}];
def tool:
  {id,name,args:(.args|fromjson)};
def durable($all):
  [.[]|select(.entry.type=="assistant")|. as $row |
    {transcript,cursor,key:(.transcript+":"+(.cursor|tostring)),
      signature:{text:.entry.text,thinking:.entry.thinking,stop:.entry.stop_reason,error:.entry.error,
        usage:(.entry.usage|usage),tools:([
          $all[]|select(.transcript==$row.transcript and .cursor>$row.cursor)] |
          reduce .[] as $next ({active:true,items:[]};
            if .active and $next.entry.type=="tool" then .items+=[($next.entry|tool)] else .active=false end)|.items)}}];
def response:
  reduce .[] as $e ({text:"",thinking:"",stop:null,error:null,tools:[],retries:0};
    if $e.event=="retrying" then
      {text:"",thinking:"",stop:null,error:null,tools:[],retries:(.retries+1)}
    elif $e.event=="text" then .text+=$e.text
    elif $e.event=="thinking" then .thinking+=$e.text
    elif $e.event=="tool_call_start" then .tools+=[{id:$e.id,name:$e.name,args:""}]
    elif $e.event=="tool_call_args" then
      need((.tools|length)>0;"tool args without start") | .tools[-1].args+=$e.args
    elif $e.event=="stop" then .stop=$e.reason
    elif $e.event=="failed" then .stop="error" | .error=$e.message
    elif $e.event|IN("spent","request_frame","served") then .
    else error("usage reconciliation: unsupported stream event") end) |
  .tools|=map(.args|=fromjson);
def role:
  if (.context.tools|length)>0 and (.context.system|startswith("You are magi, a coding agent")) then "primary"
  elif (.context.tools|length)==0 and (.context.system|startswith("You keep the running summary of a coding session")) then "summary"
  elif (.context.tools|length)==0 and (.context.system|startswith("You are given the opening of a conversation")) then "title"
  elif (.context.tools|length)==0 and .context.system=="IPC_TOOL_HELPER_ONLY" then "tool-helper"
  else error("usage reconciliation: unattributed model call") end;

. as $input |
need(.ipc.status=="USAGE_EXTRACTED" and .durable_usage.status=="USAGE_EXTRACTED" and .attempts.status=="ATTEMPTS_MEASURED" and
  .ipc.capture_complete and .ipc.coverage=="recorded-model-asks-only" and
  (.calls|length)>0 and (.calls|length)<=64 and (.calls|length)==(.ipc.calls|length) and
  [.calls[].call]==[range(0;(.calls|length))] and [.ipc.calls[].call]==[range(0;(.calls|length))];"incomplete IPC capture") |
need((.transcripts|length)>0 and (.transcripts|length)<=16 and
  (.transcripts|map(.id)|unique|length)==(.transcripts|length) and
  all(.transcripts[]; (.snapshots|length)>0 and (.snapshots|length)<=8);"transcript identities") |
(.transcripts|rows) as $rows |
($rows|durable($rows)) as $durable |
(.calls|map(. as $call | ($input.ipc.calls[]|select(.call==$call.call)) as $u |
  need($u.transport_complete and $u.exit_code==0 and $u.model==$call.request.model;"incomplete model call") |
  (.events|response) as $response |
  {call,model:$u.model,role:(.request|role),child:(.request.context.system|contains("# Working as a subagent")),
   signature:($response|del(.retries)|.+{usage:$u.last_observed_usage}),retries:$response.retries,
   totals:$u.totals,usage_frames:$u.usage_frames,terminal:$u.terminal})) as $calls |
(reduce $calls[] as $call ({seen:[],attributed:[]};
  if $call.role=="primary" then
    .seen as $seen |
    [$durable[]|select(.signature==$call.signature and (.key as $k|$seen|index($k)|not))] as $matches |
    need(($matches|length)>0 and ($matches|map(.transcript)|unique|length)==1;"missing or ambiguous durable match") |
    ($matches|sort_by(.cursor)|.[0]) as $matched |
    need($task!="child-work" or $call.child==($matched.transcript|contains("@"));"child attribution mismatch") |
    .seen+=[$matched.key] | .attributed+=[$call+{transcript:$matched.transcript,cursor:$matched.cursor}]
  else
    need(($input.transcripts|length)==1;"ambiguous helper owner") |
    .attributed+=[$call+{transcript:$input.transcripts[0].id,cursor:null}]
  end)) as $matched |
[$durable[]|select(.key as $k|$matched.seen|index($k)|not)] as $unmatched |
need(all($unmatched[]; $task=="repetitive-failure" and .signature.usage==null and .signature.stop=="error" and
  (.signature.error|startswith("Repeated-call guard: stopped")) and .signature.tools==[]);"unaccounted durable assistant") |
need(all($input.meter[]|select(.event=="response"); .turn|whole(0;($input.script|length)-1));"unknown provider script turn") |
[$input.meter[]|select(.event=="response")|.turn as $turn|$input.script[$turn]|select(.refuse!=null)] as $refusals |
need(all($refusals[]; (.refuse.status|whole(400;599)) and (.events//[]|length)==0 and .usage==null);"ambiguous synthetic refusal") |
[$matched.attributed[]|select(any(.totals[];.==null))] as $missing |
need(all($missing[]; .terminal=="failed" and .usage_frames==0 and .signature.usage==null and
  all(.totals[];.==null) and .signature.text=="" and .signature.thinking=="" and .signature.tools==[] and .retries==0 and
  (.signature.error as $error|any($refusals[]; (.refuse.message|type)=="string" and
    (.refuse.message|length)>0 and (.refuse.message as $message|$error|contains($message))))) and
  (($missing|length)+([$calls[].retries]|add//0))==($refusals|length);"usage absent without scripted rejection proof") |
need($input.attempts.provider_attempts==([$input.meter[]|select(.event=="response")]|length) and
  $input.attempts.provider_attempts==(($calls|length)+([$calls[].retries]|add//0));"unaccounted provider attempt") |
($matched.attributed|map(if any(.totals[];.==null) then
  .totals=zero|.usage_basis="scripted-nonstreaming-rejection" else .usage_basis="model-spent" end)) as $attributed |
need(([$attributed[]|select(.role=="primary" and .usage_basis=="model-spent")|.totals]|total)==$input.durable_usage.known_totals;
  "primary usage differs from durable transcript") |
{schema:1,scope:"evaluation-reconciled-synthetic-usage",status:"USAGE_RECONCILED",
 usage_source:"synthetic",real_billing_verified:false,helper_attribution:true,
 totals:([$attributed[].totals]|total),calls:$attributed,
 synthetic_assistant_rows:[$unmatched[]|{transcript,cursor}],
 groups:($attributed|group_by([.transcript,.role])|map({transcript:.[0].transcript,role:.[0].role,
   calls:[.[].call],totals:([.[].totals]|total)}))}
