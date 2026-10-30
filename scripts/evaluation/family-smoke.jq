def source: "pub fn answer() -> u8 { 42 }";
def final: "family-world-complete";
($replay[0].result|map(.raw|fromjson|.entry)) as $entries |
($requests|length)==2 and
all($requests[]; .model=="echo-1" and .stream==true) and
([$requests[1].messages[]|select(.role=="tool")]|length)==1 and
any($requests[1].messages[]; .role=="tool" and .tool_call_id=="call-1" and .content==source) and
$sessions[0].ok==true and $sessions[0].n==1 and ($sessions[0].result|length)==1 and
$sessions[0].result[0].project=="/world/work" and
$replay[0].ok==true and $replay[0].n==4 and
[$replay[0].result[].role]==["user","assistant","tool","assistant"] and
[$replay[0].result[].cursor]==[1,2,3,4] and
[$entries[].type]==["user","assistant","tool","assistant"] and
$entries[0].text=="read sample.rs and report" and
$entries[1].stop_reason=="tool_use" and $entries[1].error==null and
$entries[2].id=="call-1" and $entries[2].name=="read" and
($entries[2].args|fromjson)=={path:"sample.rs"} and
$entries[2].result.is_error==false and $entries[2].result.output==source and
$replay[0].result[2].text==source and
$entries[3].text==final and $replay[0].result[3].text==final and
$entries[3].stop_reason=="end_turn" and $entries[3].error==null and
[$entries[1,3].usage|{input,output,cache_read,cache_write}]==
  [{input:10,output:3,cache_read:0,cache_write:0},{input:20,output:5,cache_read:0,cache_write:0}] and
$meter[0]=={schema:2,scope:"offline-provider-admission",event:"start",limit:2,capture_limit_bytes:8388608,journal_limit_bytes:131072} and
$meter[-1].event=="terminal" and $meter[-1].status=="STOPPED" and $meter[-1].reason=="stopped" and
$meter[-1].admitted==2 and $meter[-1].responses==2 and $meter[-1].rejected==0 and $meter[-1].incomplete==0 and
$meter[-1].captured_bytes==$meter[-1].reserved_bytes and
[$meter[]|select(.event=="admit")|.attempt]==[1,2] and
[$meter[]|select(.event=="response")|[.attempt,.turn]]==[[1,0],[2,1]]
