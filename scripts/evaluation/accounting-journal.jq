def require($ok; $reason): if $ok then . else error($reason) end;
def counts: {input,output,cache_read,cache_write,cost_micros,estimated_micros};
[$replay0[0],$replay1[0]] as $replays |
[$ledger0,$ledger1] as $ledgers |
[$replays[]|[.result[].raw|fromjson|.entry]] as $entries |
require($sessions[0].ok and $sessions[0].n==2 and ($sessions[0].result|length)==2 and
  ($sessions[0].result|map(.id)|unique|length)==2 and
  all($sessions[0].result[]; .project=="/world/work/work"); "two independent sessions missing") |
require(($runs[0]|keys)==["anthropic","chat"] and ($runs[0]|[.chat,.anthropic]|sort)==($sessions[0].result|map(.id)|sort) and
  [$entries[][2].id]==["chat-read-1","anthropic-read-1"]; "ledgers must bind to the two selected runs in execution order") |
require(all($replays[]; .ok and .n==6 and [.result[].cursor]==[1,2,3,4,5,6] and
  [.result[].role]==["user","assistant","tool","assistant","tool","assistant"]); "unpaired journal") |
require(([$entries[][2].id]|sort)==["anthropic-read-1","chat-read-1"]; "both usage dialects required") |
require(all(range(0;2); . as $i | $entries[$i] as $e |
  ($e[2].id|rtrimstr("-read-1")) as $dialect |
  [$e[].type]==["user","assistant","tool","assistant","tool","assistant"] and
  $e[0].text==($prompt|rtrimstr("\n")) and
  [$e[2,4]|{name,args:(.args|fromjson),is_error:.result.is_error}]==
    [{name:"read",args:{path:"rates.txt"},is_error:false},{name:"read",args:{path:"stable.txt"},is_error:false}] and
  $e[4].id==$dialect+"-read-2" and
  $e[2].result.output==($rates|rtrimstr("\n")) and $e[4].result.output==($stable|rtrimstr("\n")) and
  [$e[1,3,5].stop_reason]==["tool_use","tool_use","end_turn"] and all($e[1,3,5]; .error==null) and
  (if $dialect=="chat" then
    [$e[1,3,5].usage|counts]==[
      {input:20,output:5,cache_read:100,cache_write:0,cost_micros:0,estimated_micros:105},
      {input:30,output:6,cache_read:110,cache_write:0,cost_micros:200,estimated_micros:0},
      {input:40,output:4,cache_read:120,cache_write:0,cost_micros:0,estimated_micros:142}] and $ledgers[$i]=="447\n"
   else
    [$e[1,3,5].usage|counts]==[
      {input:10,output:5,cache_read:0,cache_write:100,cost_micros:0,estimated_micros:310},
      {input:5,output:6,cache_read:100,cache_write:10,cost_micros:0,estimated_micros:108},
      {input:7,output:4,cache_read:110,cache_write:5,cost_micros:0,estimated_micros:86}] and $ledgers[$i]=="504\n"
   end) and
   ([$e[1,3,5].usage|.cost_micros+.estimated_micros]|add)==($ledgers[$i]|rtrimstr("\n")|tonumber)
); "incorrect usage normalization, charge, ledger or tool history") |
require(($requests|length)==6 and [$requests[].model]==["chat-1","chat-1","chat-1","anthropic-1","anthropic-1","anthropic-1"] and
  all($requests[]; .stream==true); "wrong provider requests") |
require(any($requests[1].messages[]; .role=="tool" and .tool_call_id=="chat-read-1" and .content==($rates|rtrimstr("\n"))) and
  any($requests[2].messages[]; .role=="tool" and .tool_call_id=="chat-read-2" and .content==($stable|rtrimstr("\n"))) and
  any($requests[4].messages[].content[]; .type=="tool_result" and .tool_use_id=="anthropic-read-1" and .is_error==false and (.content|tostring|contains($rates|rtrimstr("\n")))) and
  any($requests[5].messages[].content[]; .type=="tool_result" and .tool_use_id=="anthropic-read-2" and .is_error==false and (.content|tostring|contains($stable|rtrimstr("\n"))));
  "actual tool results missing from either dialect") |
require($meter[0]=={schema:2,scope:"offline-provider-admission",event:"start",limit:($ARGS.named.attempt_limit // 64),capture_limit_bytes:8388608,journal_limit_bytes:131072} and
  $meter[-1].event=="terminal" and $meter[-1].status=="STOPPED" and $meter[-1].reason=="stopped" and
  $meter[-1].admitted==6 and $meter[-1].responses==6 and $meter[-1].rejected==0 and $meter[-1].incomplete==0 and
  $meter[-1].captured_bytes==$meter[-1].reserved_bytes and
  [$meter[]|select(.event=="admit")|.attempt]==[1,2,3,4,5,6] and
  [$meter[]|select(.event=="response")|[.attempt,.turn]]==[[1,0],[2,1],[3,2],[4,3],[5,4],[6,5]]; "incomplete provider ledger") |
true
