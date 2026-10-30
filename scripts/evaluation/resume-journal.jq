def require($ok; $reason): if $ok then . else error($reason) end;
def entries: [.result[].raw|fromjson|.entry];
def counts: {input,output,cache_read,cache_write,cost_micros,estimated_micros};
[$initial[0],$other[0],$resumed_latest[0],$resumed_named[0]] as $replays |
($initial[0]|entries) as $a | ($other[0]|entries) as $b |
($resumed_latest[0]|entries) as $bl | ($resumed_named[0]|entries) as $an |
require($sessions[0].ok and $sessions[0].n==2 and ($sessions[0].result|length)==2 and
  ($sessions[0].result|map(.id)|sort)==([$phases[0,1].transcript]|sort) and
  all($sessions[0].result[]; .project=="/world/work/work"); "selected histories missing or phantom run created") |
require([$phases[].phase]==["initial","distractor","latest","named"] and all($phases[]; .exit_code==0) and
  ($phases|map(.coordination_run)|unique|length)==4 and
  $phases[0].transcript!=$phases[1].transcript and
  $phases[0].coordination_run==$phases[0].transcript and $phases[1].coordination_run==$phases[1].transcript and
  $phases[2].transcript==$phases[1].transcript and $phases[3].transcript==$phases[0].transcript and
  all($phases[2,3]; .coordination_run!=.transcript); "resume must distinguish coordination ledger from selected history") |
require([$replays[].n]==[6,2,4,8] and all($replays[]; .ok and [.result[].cursor]==[range(1;.n+1)] and
  [.result[].role]==[.result[].raw|fromjson|.entry.type]); "unordered or incomplete journal") |
require([$a[].type]==["user","assistant","tool","assistant","tool","assistant"] and
  [$b[].type]==["user","assistant"] and [$bl[].type]==["user","assistant","user","assistant"] and
  [$an[].type]==["user","assistant","tool","assistant","tool","assistant","user","assistant"] and
  $resumed_named[0].result[0:6]==$initial[0].result and $resumed_latest[0].result[0:2]==$other[0].result;
  "resuming rewrote or replayed earlier records") |
require($a[0].text==($prompt|rtrimstr("\n")) and $b[0].text==($distractor|rtrimstr("\n")) and
  $bl[2].text==($latest|rtrimstr("\n")) and $an[6].text==($named|rtrimstr("\n")); "wrong selected prompt") |
require([$a[2,4]|{id,name,args:(.args|fromjson),is_error:.result.is_error}]==[
  {id:"read-once",name:"read",args:{path:"counter.txt"},is_error:false},
  {id:"edit-once",name:"edit",args:{path:"counter.txt",old:"count=0",new:"count=1"},is_error:false}] and
  $a[2].result.output==($original|rtrimstr("\n")) and
  all(($a[1,3,5],$b[1],$bl[3],$an[7]); .error==null) and
  [$a[1,3,5].stop_reason]==["tool_use","tool_use","end_turn"] and
  [$b[1].stop_reason,$bl[3].stop_reason,$an[7].stop_reason]==["end_turn","end_turn","end_turn"];
  "wrong or repeated tool execution") |
require([($a[1,3,5],$b[1],$bl[3],$an[7])|.usage|counts]==[
  {input:10,output:3,cache_read:0,cache_write:0,cost_micros:0,estimated_micros:44},
  {input:20,output:5,cache_read:0,cache_write:0,cost_micros:0,estimated_micros:80},
  {input:30,output:7,cache_read:0,cache_write:0,cost_micros:0,estimated_micros:116},
  {input:40,output:9,cache_read:0,cache_write:0,cost_micros:0,estimated_micros:152},
  {input:50,output:11,cache_read:0,cache_write:0,cost_micros:0,estimated_micros:188},
  {input:60,output:13,cache_read:0,cache_write:0,cost_micros:0,estimated_micros:224}] and
  [$ledger_initial,$ledger_other,$ledger_latest,$ledger_named]==["240\n","152\n","188\n","224\n"] and
  ([$an[],$bl[]|select(.type=="assistant")|.usage.cost_micros+.usage.estimated_micros]|add)==804;
  "restored usage lost or charged again") |
require(($requests|length)==6 and all($requests[]; .model=="echo-1" and .stream==true) and
  any($requests[1].messages[]; .role=="tool" and .tool_call_id=="read-once" and .content==$a[2].result.output) and
  any($requests[2].messages[]; .role=="tool" and .tool_call_id=="edit-once" and .content==$a[4].result.output) and
  ($requests[4].messages|tostring|contains("FACT_BETA") and (contains("FACT_ALPHA")|not)) and
  ($requests[5].messages|tostring|contains("FACT_ALPHA") and (contains("FACT_BETA")|not)) and
  any($requests[4].messages[]; .role=="assistant" and .content==$b[1].text) and
  any($requests[5].messages[]; .role=="tool" and .tool_call_id=="edit-once" and .content==$a[4].result.output) and
  any($requests[5].messages[]; .role=="assistant" and .content==$a[5].text);
  "provider received the wrong restored history") |
require($meter[0]=={schema:2,scope:"offline-provider-admission",event:"start",limit:($ARGS.named.attempt_limit // 64),capture_limit_bytes:8388608,journal_limit_bytes:131072} and
  $meter[-1].event=="terminal" and $meter[-1].status=="STOPPED" and $meter[-1].reason=="stopped" and
  $meter[-1].admitted==6 and $meter[-1].responses==6 and $meter[-1].rejected==0 and $meter[-1].incomplete==0 and
  $meter[-1].captured_bytes==$meter[-1].reserved_bytes and
  [$meter[]|select(.event=="admit")|.attempt]==[1,2,3,4,5,6] and
  [$meter[]|select(.event=="response")|[.attempt,.turn]]==[[1,0],[2,1],[3,2],[4,3],[5,4],[6,5]]; "incomplete provider ledger") |
true
