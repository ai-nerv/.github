def require($ok; $reason): if $ok then . else error($reason) end;
def logs($pattern): [$log|split("\n")[]|select(test($pattern))];
def verb($name): logs("balthasar\\[[0-9]+\\].*verb: "+$name+" ");
def coherent:
  reduce .messages[] as $m ({pending:[],seen:[],ok:true};
    if $m.role=="assistant" then
      .ok=(.ok and (.pending|length)==0) | .pending=[$m.tool_calls[]?.id] |
      .ok=(.ok and (.pending|unique|length)==(.pending|length) and ([.pending[]]-.seen|length)==(.pending|length)) |
      .seen+=.pending
    elif $m.role=="tool" then
      .ok=(.ok and .pending[0]==$m.tool_call_id) | .pending=.pending[1:]
    else .ok=(.ok and (.pending|length)==0) end) | .ok and (.pending|length)==0;
($replay[0].result|map(.raw|fromjson|.entry)) as $e |
[$e[]|select(.type=="tool")] as $tools |
[$requests[]|select((.tools|length)>0)] as $main |
[$requests[]|select((.tools|length)==0)] as $helpers |
[$helpers[]|select(any(.messages[]; .role=="system" and (.content|startswith("You keep the running summary"))))] as $summaries |
[$helpers[]|select(any(.messages[]; .role=="system" and (.content|startswith("You are given the opening of a conversation"))))] as $titles |
($requests|length) as $attempts |
require($sessions[0].ok and $sessions[0].n==1 and ($sessions[0].result|length)==1 and
  $sessions[0].result[0].project=="/world/work/work" and $replay[0].ok and $replay[0].n==13 and
  [$replay[0].result[].cursor]==[range(1;14)] and
  [$e[].type]==["user","assistant","tool","assistant","tool","assistant","tool","assistant","tool","assistant","assistant","tool","assistant"];
  "incomplete or unpaired durable history") |
require($e[0].text==($prompt|rtrimstr("\n")) and
  [$tools[]|{id,name,args:(.args|fromjson)}]==[
  {id:"pressure-0",name:"read",args:{path:"missing.txt"}},
  {id:"pressure-1",name:"read",args:{path:"facts.txt"}},
  {id:"pressure-2",name:"read",args:{path:"noise-b.txt"}},
  {id:"pressure-3",name:"read",args:{path:"noise-c.txt"}},
  {id:"recover-fact",name:"history",args:{want:"matching",terms:["REPAIR_RECORD"],tokens:300}}]; "wrong prompt or tool arguments") |
require($tools[0].result.is_error and ($tools[0].result.output|contains("No such file or directory")) and
  all($tools[1:][]; .result.is_error==false) and
  [$tools[1:4][].result.output]==([$facts,$noise_b,$noise_c]|map(rtrimstr("\n"))) and
  ($tools[4].result.output|fromjson|
    .complete and .omitted==0 and (.turns|length)==1 and .turns[0].cursor==5 and
    .turns[0].role=="tool" and .turns[0].tool=="read" and .turns[0].kind=="tool_result" and
    (.turns[0].args|fromjson)=={path:"facts.txt"} and .turns[0].text==($facts|rtrimstr("\n")));
  "required source or recovered fact missing") |
require(all($e[]|select(.type=="assistant" and .error==null);
  .usage=={input:10,output:3,cache_read:0,cache_write:0,cost_micros:0,estimated_micros:0}) and
  ([$e[]|select(.type=="assistant" and .error==null)]|length)==6 and ($e[9]|has("usage")|not) and
  [$e[]|select(.type=="assistant")|.stop_reason]==["tool_use","tool_use","tool_use","tool_use","error","tool_use","end_turn"] and
  ($e[9].error|contains("prompt is too long: 250000 tokens > 32000 maximum")) and
  $e[-1].text=="The repair code is WREN-7429. The missing-file diagnostic remains available; no files were modified.";
  "wrong final answer or usage") |
require(($main|length)==7 and ($summaries|length)>0 and ($titles|length)==1 and
  ($helpers|length)==(($summaries|length)+1) and $attempts<=64 and
  all($requests[]; .model=="echo-1" and .stream and coherent) and all($main[]; .max_tokens==4096) and
  all($helpers[]; .max_tokens>0 and .max_tokens<=4096 and any(.messages[];
    .role=="system" and (.content|startswith("You keep the running summary") or startswith("You are given the opening of a conversation")))) and
  all($main[]; any(.messages[]; .role=="user" and .content==($prompt|rtrimstr("\n")))) and
  all($main[]; .tools==$main[0].tools and [.messages[]|select(.role=="system")]==[$main[0].messages[]|select(.role=="system")]);
  "orphaned tool pair or changed instructions/model/output budget") |
require(all($main[1:][]; any(.messages[];
    (.role=="tool" and .tool_call_id=="pressure-0" and .content==$tools[0].result.output) or
    (.role=="assistant" and ((.content//"")|contains("Calls that failed") and contains("read {\"path\":\"missing.txt\"} -> "+$tools[0].result.output))))) and
  all($main[]; all(.messages[]|select(.role=="assistant")|.tool_calls[]?;
    . as $call|any($tools[]; .id==$call.id and .name==$call.function.name and (.args|fromjson)==($call.function.arguments|fromjson))));
  "failed-call diagnostic or exact call arguments lost") |
require(all($main[]; all(.messages[]|select(.role=="tool"); . as $result|
    any($tools[]; .id==$result.tool_call_id and (.result.output==$result.content or
      (.id|IN("pressure-1","pressure-2","pressure-3")) and
      $result.content==("read "+(.args|fromjson|.path)+" (281 lines)"))))) and
  all(range(1;4); . as $i|any($main[$i+1].messages[];
    .role=="tool" and .tool_call_id==$tools[$i].id and .content==$tools[$i].result.output));
  "surviving tool output changed or source never delivered") |
require(($main[5]|tojson|length)<($main[4]|tojson|length) and
  ($main[5].messages|tojson|contains("WREN-7429")|not) and
  any($main[6].messages[]; .role=="tool" and .tool_call_id=="recover-fact" and .content==$tools[4].result.output) and
  ($main[6].messages|tojson|contains("WREN-7429")); "no actual reduction or exact history recovery") |
require((verb("layout")|length)>0 and (verb("overflowed")|length)>0 and (verb("scroll")|length)==1 and
  (verb("job_done")|length)==($helpers|length) and all(verb("job_done")[]; contains("answered")) and
  (logs("helpers: summarise job .* ran on evaluation/echo-1, 7 in, 2 out")|length)==($summaries|length) and
  (logs("helpers: retitle job .* ran on evaluation/echo-1, 5 in, 2 out")|length)==1 and
  (logs("casper\\[[0-9]+\\] run: ")|length)==4 and
  (logs("casper\\[[0-9]+\\] run: read with 1 argument jailed=true .* ok in ")|length)==3 and
  (logs("casper\\[[0-9]+\\] run: read with 1 argument jailed=true .* failed in ")|length)==1;
  "missing real input-pressure or tool execution proof") |
require($meter[0]=={schema:2,scope:"offline-provider-admission",event:"start",limit:($ARGS.named.attempt_limit // 64),capture_limit_bytes:8388608,journal_limit_bytes:131072} and
  $meter[-1].event=="terminal" and $meter[-1].status=="STOPPED" and $meter[-1].reason=="stopped" and
  $meter[-1].admitted==$attempts and $meter[-1].responses==$attempts and $meter[-1].rejected==0 and $meter[-1].incomplete==0 and
  $meter[-1].captured_bytes==$meter[-1].reserved_bytes and
  [$meter[]|select(.event=="admit")|.attempt]==[range(1;$attempts+1)] and
  ([$meter[]|select(.event=="response")|.attempt]|sort)==[range(1;$attempts+1)] and
  [$meter[]|select(.event=="response" and .turn>=2)|.turn]==[2,3,4,5,6,7,8] and
  ([$meter[]|select(.event=="response" and .turn==0)]|length)==($summaries|length) and
  ([$meter[]|select(.event=="response" and .turn==1)]|length)==1; "incomplete provider ledger") |
true
