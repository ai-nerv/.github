include "contract";
def require($ok;$why): if $ok then . else error("IPC usage: "+$why) end;
def count: whole(0;9007199254740991);
def names: ["input_tokens","output_tokens","cache_read_tokens","cache_write_tokens","reported_micros","estimated_micros","charged_micros"];
def unknown: names|map({key:.,value:null})|from_entries;
def zero: names|map({key:.,value:0})|from_entries;
def usage:
  require(type=="object" and (keys-["input","output","cache_read","cache_write","cost_micros","estimated_micros"]|length)==0 and
    all([.input,.output,.cache_read,.cache_write][];count) and
    all([.cost_micros,.estimated_micros][];.==null or count);"invalid usage") |
  require(.cost_micros==null or .estimated_micros==null or .cost_micros<=9007199254740991-.estimated_micros;"charge overflow") |
  {input_tokens:.input,output_tokens:.output,cache_read_tokens:.cache_read,cache_write_tokens:.cache_write,
   reported_micros:.cost_micros,estimated_micros:.estimated_micros,
   charged_micros:(if .cost_micros==null or .estimated_micros==null then null else .cost_micros+.estimated_micros end)};
def stream:
  reduce .[] as $e ({last:null,terminal:null,frames:0,fresh:false};
    require(($e|type)=="object" and ($e.event|IN("spent","retrying","stop","failed","text","thinking","signature","tool_call_start","tool_call_args","served","request_frame"));"unknown event") |
    require(.terminal==null or $e.event=="retrying";"event after terminal") |
    if $e.event=="spent" then
      ($e.usage|usage) as $next | .last as $prev |
      require($prev==null or all(names[]; . as $k|$prev[$k]==null or $next[$k]==null or $next[$k]>=$prev[$k]);"decreasing cumulative usage") |
      .last=$next | .frames+=1 | .fresh=true
    elif $e.event=="retrying" then
      require(($e.attempt|whole(1;64)) and ($e.of|whole(1;64)) and $e.attempt<=$e.of and
        ($e.seconds|type)=="number" and $e.seconds>=0 and $e.seconds<=300;"invalid retry") | .terminal=null | .fresh=false
    elif $e.event=="stop" then
      require($e.reason|IN("end_turn","tool_use","length","error","aborted");"invalid stop") | .terminal="stop"
    elif $e.event=="failed" then
      require(($e.message|type)=="string" and ($e.why|IN("transport","overload","throttle","auth","invalid","overflow","unknown"));"invalid failure") | .terminal="failed"
    else . end);
map(. as $call | (.events|stream) as $stream |
  {call,model,transport_complete,exit_code,terminal:$stream.terminal,usage_frames:$stream.frames,
   last_observed_usage:$stream.last,
   totals:(if .transport_complete and .exit_code==0 and $stream.terminal!=null and $stream.fresh then $stream.last else unknown end)}) as $calls |
(reduce $calls[] as $call ({sum:zero,missing:zero};
  reduce names[] as $k (.;
    if $call.totals[$k]==null then .missing[$k]+=1
    else require(.sum[$k]<=9007199254740991-$call.totals[$k];"aggregate overflow") | .sum[$k]+=$call.totals[$k] end))) as $all |
{schema:1,scope:"evaluation-model-ipc-usage",status:"USAGE_EXTRACTED",coverage:"recorded-model-asks-only",
 complete_run:false,helper_attribution:null,provider_attempts:null,settlement_verified:false,
 capture_complete:$capture_complete,calls:$calls,known_totals:$all.sum,unknown_calls:$all.missing,
 totals:(if $capture_complete then reduce names[] as $k ($all.sum;if $all.missing[$k]>0 then .[$k]=null else . end) else unknown end)}
