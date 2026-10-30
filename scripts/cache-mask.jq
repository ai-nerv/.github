def normalized: .messages |= map(.content |= map(del(.cache_control)));
def blocks: .messages[].content[];
def text_message($role; $text): {role:$role,content:[{type:"text",text:$text}]};
def warning: "(this conversation is long enough that earlier turns are being summarised rather than sent word for word)";
def full_output: "// CACHE-MASK-FILE\n" + ([range(1;401)|"pub fn f_\(.)() -> u32 { \(.) } // padding padding padding"]|join("\n"));
def stub: "read mask.rs (401 lines)";
def unit($output): [
  {role:"assistant",content:[{type:"thinking",thinking:"mask reasoning",signature:"mask-signature-v1"},
    {type:"tool_use",id:"mask-read-1",name:"read",input:{path:"mask.rs"}}]},
  {role:"user",content:[{type:"tool_result",tool_use_id:"mask-read-1",content:$output,is_error:false}]}];
[.requests[]|select(any(.tools[]?;.name=="read"))] as $r |
[.replay.result[].raw|fromjson|.entry] as $entries |
(reduce .events[] as $e ({layout:null,frames:[]};
  if $e.event=="context_laid" then .layout=$e
  elif $e.event=="cache_frame" then .frames += [{layout:.layout,reasons:$e.reasons}]
  else . end)|.frames) as $frames |
[text_message("user";"read mask.rs")] as $first |
($first + unit(stub) + [text_message("assistant";"masked answer"),text_message("user";"continue with the selected mask")]) as $fourth |
if ($r|length)!=5 or ($frames|length)!=5 then error("five mask requests and frames required")
elif (all($r[];del(.messages)==($r[0]|del(.messages)))|not) then error("mask changed base request frame")
elif ($r|map(normalized|.messages)) != [
  $first, ($first+unit(full_output)),
  ([{role:"user",content:[{type:"text",text:warning},{type:"text",text:"read mask.rs"}]}]+unit(stub)),
  $fourth, ($fourth+[text_message("assistant";"mask retained"),text_message("user";"keep the same mask")])
] then error("mask changed retained content, signed unit, selected stub or append-only continuation")
elif ($r|map([(.system[]?,.tools[]?,blocks)|select(has("cache_control"))]|length))!=[3,4,4,4,4] or
  (all($r[];all((.system[]?,.tools[]?,blocks)|select(has("cache_control"));.cache_control=={type:"ephemeral"}) and
  all(blocks|select(.type=="thinking");has("cache_control")|not))|not) then error("mask cache marker contract changed")
elif [$frames[].layout|[.slots[]|{kind,cursor}]] != [
  [{kind:"item",cursor:1}],
  [{kind:"item",cursor:1},{kind:"item",cursor:2},{kind:"item",cursor:3}],
  [{kind:"note",cursor:null},{kind:"item",cursor:1},{kind:"item",cursor:2},{kind:"stub",cursor:3}],
  [{kind:"item",cursor:1},{kind:"item",cursor:2},{kind:"stub",cursor:3},{kind:"item",cursor:5},{kind:"item",cursor:6}],
  [{kind:"item",cursor:1},{kind:"item",cursor:2},{kind:"stub",cursor:3},{kind:"item",cursor:5},{kind:"item",cursor:6},{kind:"item",cursor:7},{kind:"item",cursor:8}]
] then error("mask not selected by actual Balthasar layout")
elif (all($frames[].layout; .counts.items==([.slots[]|select(.kind=="item")]|length) and
  .counts.stubs==([.slots[]|select(.kind=="stub")]|length) and .counts.notes==([.slots[]|select(.kind=="note")]|length) and
  .counts.dropped==0 and .counts.summary==0 and .counts.memory==0 and .counts.pinned==0 and
  all(.slots[]|select(.kind=="stub");.text==stub) and
  all(.slots[]|select(.kind=="note");.text==(warning|.[0:90]|rtrimstr(" "))))|not) then error("mask layout counts or presentation changed")
elif [$frames[].reasons]!=[[],[],["layout_changed"],["layout_changed"],[]] then error("mask or warning invalidation missing or repeated on stable growth")
elif [.events[]|select(.event=="provider_frame")|.reasons]!=[[],[],[],[],[]] then error("mask provider policy changed")
elif [.replay.result[].cursor]!=[1,2,3,4,5,6,7,8,9] or
  ($entries|map(.type))!=["user","assistant","tool","assistant","assistant","user","assistant","user","assistant"] then error("durable mask rows dropped or rewritten")
elif $entries[0].text!="read mask.rs" or $entries[1].thinking!="mask reasoning" or $entries[1].signatures.thinking!="mask-signature-v1" or
  $entries[1].stop_reason!="tool_use" or $entries[2].id!="mask-read-1" or $entries[2].name!="read" or
  ($entries[2].args|fromjson)!={path:"mask.rs"} or $entries[2].result.output!=full_output or $entries[2].result.is_error!=false then error("full durable signed native read unit changed")
elif $entries[3].stop_reason!="error" or ($entries[3].error|contains("prompt is too long")|not) or
  $entries[4].text!="masked answer" or $entries[5].text!="continue with the selected mask" or
  $entries[6].text!="mask retained" or $entries[7].text!="keep the same mask" or $entries[8].text!="mask stable" or
  (all([$entries[4],$entries[6],$entries[8]][];.stop_reason=="end_turn")|not) then error("durable recovery or continuation changed")
else {scope:"actual-family-cache-mask",main_requests:5,owner_selected_mask:"PASS",exact_signed_unit:"PASS",durable_full_output:"PASS",warning_transition:"PASS",stable_mask_prefix:"PASS",real_cache_hits_verified:false}
end
