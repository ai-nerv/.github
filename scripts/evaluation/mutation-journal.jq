($replay[0].result|map(.raw|fromjson|.entry)) as $entries |
$entries[0].text==($prompt|rtrimstr("\n")) and
($requests|length)==3 and all($requests[]; .model=="echo-1" and .stream==true) and
$sessions[0].ok==true and $sessions[0].n==1 and ($sessions[0].result|length)==1 and
$sessions[0].result[0].project=="/world/work/work" and
$replay[0].ok==true and $replay[0].n==6 and
[$replay[0].result[].cursor]==[1,2,3,4,5,6] and
[$replay[0].result[].role]==["user","assistant","tool","assistant","tool","assistant"] and
[$entries[].type]==["user","assistant","tool","assistant","tool","assistant"] and
[$entries[2,4]|[.id,.name,.result.is_error]]==[["read-1","read",false],["edit-1","edit",false]] and
($entries[2].args|fromjson)=={path:"src/lib.rs"} and
($entries[4].args|fromjson)=={path:"src/lib.rs",old:$old,new:$new} and
any($requests[1].messages[]; .role=="tool" and .tool_call_id=="read-1" and (.content|contains($old))) and
any($requests[2].messages[]; .role=="tool" and .tool_call_id=="edit-1" and .content==$entries[4].result.output) and
[$entries[1,3,5].stop_reason]==["tool_use","tool_use","end_turn"] and
all($entries[1,3,5]; .error==null) and
[$entries[1,3,5].usage|{input,output,cache_read,cache_write}]==
  [{input:10,output:3,cache_read:0,cache_write:0},{input:20,output:5,cache_read:0,cache_write:0},{input:30,output:7,cache_read:0,cache_write:0}] and
$meter[0]=={schema:2,scope:"offline-provider-admission",event:"start",limit:($ARGS.named.attempt_limit // 64),capture_limit_bytes:8388608,journal_limit_bytes:131072} and
$meter[-1].event=="terminal" and $meter[-1].status=="STOPPED" and $meter[-1].reason=="stopped" and
$meter[-1].admitted==3 and $meter[-1].responses==3 and $meter[-1].rejected==0 and $meter[-1].incomplete==0 and
$meter[-1].captured_bytes==$meter[-1].reserved_bytes and
[$meter[]|select(.event=="admit")|.attempt]==[1,2,3] and
[$meter[]|select(.event=="response")|[.attempt,.turn]]==[[1,0],[2,1],[3,2]]
