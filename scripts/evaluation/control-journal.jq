def require($condition; $reason): if $condition then . else error($reason) end;
def logs($pattern): [$log|split("\n")[]|select(test($pattern))];
def verb($name): logs("balthasar\\[[0-9]+\\].*verb: "+$name+" ");
($replay[0].result|map(.raw|fromjson|.entry)) as $entries |
(if $task=="repetitive-failure" then 4 else 2 end) as $attempts |
require($sessions[0].ok==true and $sessions[0].n==1 and ($sessions[0].result|length)==1 and
  $sessions[0].result[0].project=="/world/work/work" and $replay[0].ok==true; "missing durable session") |
require($entries[0].type=="user" and $entries[0].text==($prompt|rtrimstr("\n")); "fixture prompt not preserved") |
require(($requests|length)==$attempts and all($requests[]; .model=="echo-1" and .stream==true); "wrong request count or model") |
require($meter[0]=={schema:2,scope:"offline-provider-admission",event:"start",limit:($ARGS.named.attempt_limit // 64),capture_limit_bytes:8388608,journal_limit_bytes:131072} and
  $meter[-1].event=="terminal" and $meter[-1].status=="STOPPED" and $meter[-1].reason=="stopped" and
  $meter[-1].admitted==$attempts and $meter[-1].responses==$attempts and $meter[-1].rejected==0 and $meter[-1].incomplete==0 and
  $meter[-1].captured_bytes==$meter[-1].reserved_bytes and
  [$meter[]|select(.event=="admit")|.attempt]==[range(1;$attempts+1)] and
  [$meter[]|select(.event=="response")|[.attempt,.turn]]==[range(0;$attempts)|[.+1,.]]; "incomplete provider ledger") |
if $task=="repetitive-failure" then
  [$entries[]|select(.type=="tool")] as $tools |
  require($exit==1 and $replay[0].n==10; "wrong guard outcome") |
  require([$replay[0].result[].cursor]==[range(1;11)] and
    [$entries[].type]==["user","assistant","tool","assistant","tool","assistant","tool","assistant","tool","assistant"];
    "unpaired or unordered journal") |
  require([$tools[].id]==["read-1","read-2","read-3","read-4"] and
    all($tools[]; .name=="read" and (.args|fromjson)=={path:"missing.txt"} and .result.is_error==true and (.result.output|type)=="string");
    "wrong tool or incomplete result") |
  require($tools[0].result.output==$tools[1].result.output and
    ($tools[0].result.output|contains("No such file or directory")) and
    ($tools[0].result.output|startswith("Repeated-call guard:")|not) and
    ($tools[2].result.output|startswith("Repeated-call guard: not executed.")) and
    ($tools[3].result.output|startswith("Repeated-call guard: stopped")) and
    $entries[-1].stop_reason=="error" and ($entries[-1].error|startswith("Repeated-call guard: stopped")); "guard stages missing") |
  require(any($requests[3].messages[]; .role=="tool" and .tool_call_id=="read-3" and .content==$tools[2].result.output);
    "repair guidance not delivered") |
  require((logs("casper\\[[0-9]+\\] run: read with 1 argument jailed=true .* failed in ")|length)==2 and
    (logs("casper\\[[0-9]+\\] run: ")|length)==2; "wrong actual dispatch count") |
  require([$entries[]|select(.type=="assistant" and .error==null)|.usage|{input,output,cache_read,cache_write}]==
    [range(0;4)|{input:10,output:3,cache_read:0,cache_write:0}] and
    ($entries[-1]|has("usage")|not); "guard usage changed")
else
  require($exit==0 and [$requests[].max_tokens]==[4096,512] and
    ($requests|map(del(.max_tokens))|unique|length)==1; "input changed or automatic output did not shrink") |
  require(all($requests[]; has("__budget")==false and has("__scratch")==false and has("__output_limit")==false); "private budget metadata leaked") |
  require((verb("layout")|length)>0 and (verb("observe")|length)>0 and
    all(verb("layout")[]; test("with [0-9]+ slots, 0 jobs")) and
    (verb("overflowed")|length)==0 and (verb("job_done")|length)==0; "recovery compacted or missing positive controls") |
  require($replay[0].n==2 and [$replay[0].result[].cursor]==[1,2] and [$entries[].type]==["user","assistant"] and
    $entries[1].text=="Recovered the automatic output budget." and $entries[1].stop_reason=="end_turn" and $entries[1].error==null;
    "wrong recovered journal") |
  require(($entries[1].usage|{input,output,cache_read,cache_write})=={input:512,output:2,cache_read:0,cache_write:0}; "recovered usage changed")
end | true
