def require($ok; $reason): if $ok then . else error($reason) end;
[$replay0[0],$replay1[0]] as $replays |
[$replays[]|{raw:.,entries:[.result[].raw|fromjson|.entry]}] as $runs |
require($sessions[0].ok and $sessions[0].n==2 and ($sessions[0].result|length)==2 and
  ($sessions[0].result|map(.id)|unique|length)==2 and
  all($sessions[0].result[]; .project=="/world/work/work"); "two independent sessions missing") |
require(all($runs[]; .raw.ok and .raw.n==6 and [.raw.result[].cursor]==[1,2,3,4,5,6] and
  [.entries[].type]==["user","assistant","tool","assistant","tool","assistant"] and
  [.raw.result[].role]==["user","assistant","tool","assistant","tool","assistant"]); "unpaired session journal") |
require(($requests|length)==6 and all($requests[]; .model=="echo-1" and .stream==true); "wrong provider count or model") |
require(all($runs[];
  .entries as $e |
  ($e[2].id|ltrimstr("read-")) as $lane |
  ($prompt|rtrimstr("\n"))+" EVAL_LANE_"+($lane|ascii_upcase)+": assigned region "+$lane+"." as $text |
  ($lane=="left" or $lane=="right") and $e[0].text==$text and
  $e[2].name=="read" and $e[2].result.is_error==false and $e[2].result.output==($original|rtrimstr("\n")) and
  ($e[2].args|fromjson)=={path:"shared.txt"} and
  $e[4].id=="edit-"+$lane and $e[4].name=="edit" and
  ($e[4].args|fromjson)=={path:"shared.txt",old:$lane+"=old",new:$lane+"=new"} and
  [$e[1,3,5].stop_reason]==["tool_use","tool_use","end_turn"] and
  all($e[1,3,5]; .error==null) and
  [$e[1,3,5].usage|{input,output,cache_read,cache_write}]==
    [{input:10,output:3,cache_read:0,cache_write:0},{input:20,output:5,cache_read:0,cache_write:0},{input:30,output:7,cache_read:0,cache_write:0}] and
  ([$requests[]|select(any(.messages[]; .role=="user" and .content==$text))]|length)==3 and
  any($requests[]; any(.messages[]; .role=="tool" and .tool_call_id=="read-"+$lane and .content==($original|rtrimstr("\n")))) and
  any($requests[]; any(.messages[]; .role=="tool" and .tool_call_id=="edit-"+$lane and .content==$e[4].result.output))
); "wrong read, edit, prompt, usage or provider history") |
require(([$runs[].entries[2].id]|sort)==["read-left","read-right"]; "same lane replayed twice") |
[$runs[].entries[4]] as $edits |
require(([$edits[]|select(.result.is_error==false)]|length)==1 and
  ([$edits[]|select(.result.is_error==true and (.result.output|contains("stale")))]|length)==1;
  "expected one commit and one explicit stale refusal") |
require($meter[0]=={schema:2,scope:"offline-provider-admission",event:"start",limit:($ARGS.named.attempt_limit // 64),capture_limit_bytes:8388608,journal_limit_bytes:131072} and
  $meter[-1].event=="terminal" and $meter[-1].status=="STOPPED" and $meter[-1].reason=="stopped" and
  $meter[-1].admitted==6 and $meter[-1].responses==6 and $meter[-1].rejected==0 and $meter[-1].incomplete==0 and
  $meter[-1].captured_bytes==$meter[-1].reserved_bytes and
  [$meter[]|select(.event=="admit")|.attempt]==[1,2,3,4,5,6] and
  ([$meter[]|select(.event=="response")|.attempt]|sort)==[1,2,3,4,5,6] and
  ([$meter[]|select(.event=="response")|.turn]|sort)==[0,1,2,3,4,5]; "incomplete provider ledger") |
[$meter[]|select(.event|startswith("rendezvous_"))] as $barrier |
require([$barrier[].event]==["rendezvous_arrive","rendezvous_arrive","rendezvous_release","rendezvous_release"] and
  all($barrier[]; .group=="both-read") and
  ([$barrier[0:2][].turn]|sort)==[1,4] and
  ([$barrier[0:2][]|{attempt,turn}]|sort_by(.attempt))==([$barrier[2:4][]|{attempt,turn}]|sort_by(.attempt));
  "both observed revisions must rendezvous before edits are released") |
require(all($barrier[2:4][]; . as $release |
  ([$meter|to_entries[]|select(.value==$release)|.key][0]) <
  ([$meter|to_entries[]|select(.value.event=="response" and .value.attempt==$release.attempt and .value.turn==$release.turn)|.key][0]));
  "edit response preceded its barrier release") |
$edits[]|select(.result.is_error==false)|.id|ltrimstr("edit-")
