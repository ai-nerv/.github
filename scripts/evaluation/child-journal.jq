include "log-word";
def require($ok; $reason): if $ok then . else error($reason) end;
def entries: [.result[].raw|fromjson|.entry];
def logs($pattern): [$log|split("\n")[]|select(test($pattern))];
def seat($heading): any(.messages[]; .role=="system" and (.content|contains($heading)));
def coherent:
  reduce .messages[] as $m ({pending:[],seen:[],ok:true};
    if $m.role=="assistant" then
      .ok=(.ok and (.pending|length)==0) | .pending=[$m.tool_calls[]?.id] |
      .ok=(.ok and (.pending|unique|length)==(.pending|length) and ([.pending[]]-.seen|length)==(.pending|length)) |
      .seen+=.pending
    elif $m.role=="tool" then
      .ok=(.ok and .pending[0]==$m.tool_call_id) | .pending=.pending[1:]
    else .ok=(.ok and (.pending|length)==0) end) | .ok and (.pending|length)==0;
def supplied($tools): all(.messages[]|select(.role=="tool"); . as $result|
  any($tools[]; .id==$result.tool_call_id and .result.output==$result.content)) and
  all(.messages[]|select(.role=="assistant")|.tool_calls[]?; . as $call|
  any($tools[]; .id==$call.id and .name==$call.function.name and (.args|fromjson)==($call.function.arguments|fromjson)));
($parent[0]|entries) as $p | ($child[0]|entries) as $c |
[$p[]|select(.type=="tool")] as $pt | [$c[]|select(.type=="tool")] as $ct |
[$p[]|select(.type=="assistant")] as $pa | [$c[]|select(.type=="assistant")] as $ca |
[$requests[]|select(seat("# Working with other agents"))] as $pr |
[$requests[]|select(seat("# Working as a subagent"))] as $cr |
($requests|length) as $attempts |
$identities[0] as $id | ($original|sub("child=old";"child=new")|rtrimstr("\n")) as $edited |
require($sessions[0].ok and $sessions[0].n==2 and ($sessions[0].result|length)==2 and
  ($sessions[0].result|map(.id)|sort)==([$id.run,$id.child_transcript]|sort) and
  $id.child_transcript==($id.run+"@"+$id.child) and $id.parent!= $id.child and
  $id.report_file==($id.child+".report") and all($sessions[0].result[]; .project=="/world/work/work"); "missing parent/child identities") |
require(($id.parent|test("^[a-z]+-[a-z]+$")) and ($id.child|test("^[a-z]+-[a-z]+$")) and
  ($id.run|test("^"+$id.parent+"-[0-9]+$")) and $id.child_pid>1 and
  (logs("magi\\[[0-9]+\\] session: "+($id.run|magi_log_pattern)+" as agent "+$id.parent+" serving in /world/work/work, model evaluation/echo-1, memory reached")|length)==1 and
  (logs("magi\\["+($id.child_pid|tostring)+"\\] session: "+($id.run|magi_log_pattern)+" as agent "+$id.child+" serving in /world/work/work, model evaluation/echo-1, memory reached")|length)==1;
  "selected run identities do not match actual hosts") |
require(all(($parent[0],$child[0]); .ok and .n==(.result|length) and [.result[].cursor]==[range(1;.n+1)]) and
  $p[0].type=="user" and $p[0].text==($prompt|rtrimstr("\n")) and $c[0].type=="user" and
  ($c[0].text|startswith($child_prompt|rtrimstr("\n"))) and
  [$c[].type]==["user","assistant","tool","assistant","tool","assistant","tool","assistant","tool","assistant"];
  "incomplete durable parent/child history") |
require([$pt[].id]==["parent-read","start-child","parent-stale","parent-verify"] and
  [$pt[].name]==["read","spawn","edit","read"] and
  ($pt[0].args|fromjson)=={path:"shared.txt"} and ($pt[3].args|fromjson)=={path:"shared.txt"} and
  ($pt[1].args|fromjson)=={prompt:($child_prompt|rtrimstr("\n")),role:"worker",delegate:false} and
  $pt[1].result.output==$id.child and $pt[1].result.is_error==false and
  ($pt[2].args|fromjson)=={path:"shared.txt",old:"parent=old",new:"parent=new"} and
  $pt[2].result.is_error and ($pt[2].result.output|contains("stale")) and
  $pt[0].result.is_error==false and $pt[0].result.output==($original|rtrimstr("\n")) and
  $pt[3].result.is_error==false and $pt[3].result.output==$edited; "parent lost its independent observation or verification") |
require([$ct[].id]==["child-blind","child-read","child-edit","child-report"] and
  [$ct[].name]==["edit","read","edit","agent"] and
  ($ct[0].args|fromjson)=={path:"shared.txt",old:"child=old",new:"child=new"} and $ct[0].args==$ct[2].args and
  $ct[0].result.is_error and ($ct[0].result.output|contains("requires a delivered observation in this agent session; reread first")) and
  ($ct[1].args|fromjson)=={path:"shared.txt"} and $ct[1].result.is_error==false and
  $ct[1].result.output==($original|rtrimstr("\n")) and $ct[2].result.is_error==false and
  ($ct[3].args|fromjson)=={verb:"report",message:($report_text|rtrimstr("\n"))} and $ct[3].result.is_error==false;
  "child inherited an observation or did not complete its own mutation/report") |
require(($pa|length)>=5 and ($pa|length)<=8 and ($ca|length)==5 and
  [$pa[0:4][].stop_reason]==["tool_use","tool_use","tool_use","tool_use"] and
  [$ca[].stop_reason]==["tool_use","tool_use","tool_use","tool_use","end_turn"] and
  all($pa[4:][]; .stop_reason=="end_turn" and .text=="PARENT_FINAL: Child work verified; the stale parent edit was refused and the tail is unchanged.") and
  $ca[-1].text=="CHILD_FINAL: The assigned edit is complete." and all(($pa[],$ca[]); .error==null);
  "unexpected parent/child turn outcome") |
require([$pa[].usage|{input,output,estimated_micros}]==([
  {input:10,output:3,estimated_micros:44},{input:20,output:5,estimated_micros:80},
  {input:30,output:7,estimated_micros:116},{input:40,output:9,estimated_micros:152}]+
  [range(4;($pa|length))|{input:50,output:11,estimated_micros:188}]) and
  [$ca[].usage|{input,output,estimated_micros}]==[
  {input:11,output:3,estimated_micros:46},{input:21,output:5,estimated_micros:82},
  {input:31,output:7,estimated_micros:118},{input:41,output:9,estimated_micros:154},{input:51,output:11,estimated_micros:190}] and
  all(($pa[],$ca[]); .usage.cache_read==0 and .usage.cache_write==0 and .usage.cost_micros==0) and
  $ledger==((982+188*(($pa|length)-4))|tostring)+"\n";
  "child or parent cost omitted, recounted or misattributed") |
require($report[0].format=="melchior-report-v1" and ($report[0].revision|test("^[0-9a-f]{64}$")) and
  $report[0].parent==$id.parent and $report[0].session==$id.run and
  ($report[0].report|startswith("Outcome: completed with tool errors\n")) and
  ($report[0].report|contains($report_text|rtrimstr("\n"))) and ($report[0].report|contains($ca[-1].text)) and
  any($p|to_entries[]; .value.type=="from" and .value.sort=="report_body" and (.value.who|split("/")[-1])==$id.child and
    (.value.text|contains($report[0].revision) and contains($report[0].report)) and
    any($p[(.key+1):][]; .type=="assistant" and .stop_reason=="end_turn" and (.text|startswith("PARENT_FINAL:"))));
  "final child report was not delivered to its owner before finalization") |
require(all($p[]; .type|IN("user","assistant","tool","from")) and
  ([$p[]|select(.type=="user")]|length)==1 and
  ([$p[]|select(.type=="from")]|unique_by({who,sort,text})|length)==([$p[]|select(.type=="from")]|length) and
  all($p[]|select(.type=="from");
    if .sort=="attention" then .who=="melchior" and (.text|contains($id.child) and contains("reported a finished turn"))
    else (.sort|IN("report","report_body")) and .who==("work/worker/"+$id.child) end) and
  ([$p[]|select(.type=="from" and .sort=="attention")]|length)==1 and
  (reduce $p[] as $entry ({settled:false,fresh:false,ok:true};
    if $entry.type=="from" then .fresh=true
    elif $entry.type=="assistant" and $entry.stop_reason=="end_turn" then
      .ok=(.ok and ((.settled|not) or .fresh))|.settled=true|.fresh=false
    else . end)|.ok) and $p[-1].type=="assistant" and $p[-1].stop_reason=="end_turn";
  "idle repeated turn or report attributed to an unrelated agent") |
require(($pr|length)==($pa|length) and ($cr|length)==5 and $attempts==(($pr|length)+($cr|length)) and
  all($pr[]; coherent and supplied($pt) and .tools==$pr[0].tools and
    any(.messages[]; .role=="user" and .content==(($prompt|rtrimstr("\n"))+"\n\n---\n"+($parent_aside|rtrimstr("\n")))) and
    [.messages[]|select(.role=="system")]==[$pr[0].messages[]|select(.role=="system")]) and
  all($cr[]; coherent and supplied($ct) and .tools==$cr[0].tools and
    any(.messages[]; .role=="user" and .content==$c[0].text) and
    [.messages[]|select(.role=="system")]==[$cr[0].messages[]|select(.role=="system")]) and
  all(range(1;5); . as $i|any($pr[$i].messages[]; .role=="tool" and .tool_call_id==$pt[$i-1].id and .content==$pt[$i-1].result.output)) and
  all(range(1;5); . as $i|any($cr[$i].messages[]; .role=="tool" and .tool_call_id==$ct[$i-1].id and .content==$ct[$i-1].result.output)) and
  any($pr[-1].messages[]; ((.content//"")|contains($report[0].revision) and contains($report[0].report))) and
  all($cr[]; (.messages|tojson|contains("PARENT_WORK:")|not)); "provider history crossed owners or omitted observed results") |
require(($requests|length)==(($pa|length)+5) and all($requests[]; .model=="echo-1" and .stream and .max_tokens==4096) and
  (logs("casper\\[[0-9]+\\] run: read with 1 argument jailed=true .* ok in ")|length)==3 and
  (logs("casper\\[[0-9]+\\] run: edit with 3 arguments jailed=true .* ok in ")|length)==1 and
  (logs("casper\\[[0-9]+\\] run: edit with 3 arguments jailed=true .* failed in ")|length)==1 and
  (logs("casper\\[[0-9]+\\] run: ")|length)==5; "unexpected dispatch or provider count") |
require($meter[0]=={schema:2,scope:"offline-provider-admission",event:"start",limit:($ARGS.named.attempt_limit // 64),capture_limit_bytes:8388608,journal_limit_bytes:131072} and
  $meter[-1].event=="terminal" and $meter[-1].status=="STOPPED" and $meter[-1].reason=="stopped" and
  $meter[-1].admitted==$attempts and $meter[-1].responses==$attempts and $meter[-1].rejected==0 and $meter[-1].incomplete==0 and
  $meter[-1].captured_bytes==$meter[-1].reserved_bytes and
  [$meter[]|select(.event=="admit")|.attempt]==[range(1;$attempts+1)] and
  ([$meter[]|select(.event=="response")|.attempt]|sort)==[range(1;$attempts+1)] and
  ([$meter[]|select(.event=="response" and .turn!=9)|.turn]|sort)==[range(0;9)] and
  ([$meter[]|select(.event=="response" and .turn==9)]|length)==(($pa|length)-4); "incomplete provider ledger") |
[$meter[]|select(.event|startswith("rendezvous_"))] as $barrier |
require([$barrier[].event]==["rendezvous_arrive","rendezvous_arrive","rendezvous_release","rendezvous_release"] and
  all($barrier[]; .group=="child-committed") and ([$barrier[0:2][].turn]|sort)==[4,7] and
  ([$barrier[0:2][]|{attempt,turn}]|sort_by(.attempt))==([$barrier[2:4][]|{attempt,turn}]|sort_by(.attempt));
  "parent stale edit did not wait for the child's commit/report") |
require(all($barrier[2:4][]; . as $release |
  ([$meter|to_entries[]|select(.value==$release)|.key][0]) <
  ([$meter|to_entries[]|select(.value.event=="response" and .value.attempt==$release.attempt and .value.turn==$release.turn)|.key][0]));
  "response preceded barrier release") |
true
