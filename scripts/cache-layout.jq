def blocks: .messages[].content[];
def normalized: .messages |= map(.content |= map(del(.cache_control)));
def warning: "(this conversation is long enough that earlier turns are being summarised rather than sent word for word)";
def summary($failed): "Here is a summary of the earlier part of this conversation:\n\nCache layout summary. The person asked: read the layout files. The files were inspected.\n\nCalls that failed in the turns summarised above, as they were made and answered (not the summariser's words):\n- [3] read {\"path\":\"missing.rs\"} -> " + $failed;
def file($n): "// CACHE-LAYOUT-FILE-\($n)\n" + ([range(1;251)|"pub fn f\($n)_\(.)() -> u32 { \(.) } // padding padding padding"]|join("\n"));
def text_slots($rows; $summary):
  [.slots[] | if .kind=="note" then {role:"user",text:warning}
   elif .kind=="summary" then {role:"assistant",text:$summary}
   elif .kind=="item" then $rows[(.cursor|tostring)] |
     if .type=="user" or (.type=="assistant" and (.text|length)>0) then {role:.type,text:.text} else empty end
   else error("unexpected slot kind in drop/summary fixture") end];
. as $capture |
[.requests[]|select(any(.tools[]?; .name=="read"))] as $r |
([.replay.result[]|{key:(.cursor|tostring),value:(.raw|fromjson|.entry)}]|from_entries) as $rows |
[.replay.result[].raw|fromjson|.entry] as $entries |
(reduce .events[] as $e ({layout:null,frames:[]};
  if $e.event=="context_laid" then .layout=$e
  elif $e.event=="cache_frame" then .frames += [{layout:.layout,reasons:$e.reasons}]
  else . end)|.frames) as $frames |
summary($rows["3"].result.output) as $summary |
if ($r|length)!=7 or ($frames|length)!=7 then error("seven main requests and frames required")
elif (all($frames[]; (.layout.id|startswith("L-")) and (.layout.slots|length)>0)|not) then error("missing actual Balthasar layout")
elif (all($frames[].layout; .counts.items==([.slots[]|select(.kind=="item")]|length) and .counts.summary==([.slots[]|select(.kind=="summary")]|length))|not) then error("layout slot counts differ")
elif (any($frames[];.layout.counts.dropped>0)|not) or (any($frames[];.layout.counts.summary>0)|not) then error("no actual drop or summary activation")
elif (any(.events[];.event=="request_admitted" and .outcome=="replanned")|not) then error("no input-boundary reduction")
elif (any(range(1;7); . as $i | ([$r[$i-1]|blocks|select(.type=="tool_use")|.id] - [$r[$i]|blocks|select(.type=="tool_use")|.id])|length>0)|not) then error("no actual old tool group dropped")
elif (all($r[];.system==$r[0].system and .tools==$r[0].tools and .model==$r[0].model)|not) then error("layout changed base request frame")
elif ($r|map([(.system[]?,.tools[]?,blocks)|select(has("cache_control"))]|length))!=[3,4,4,4,4,4,4] then error("layout cache markers changed")
elif (all($r[]; all((.system[]?,.tools[]?,blocks)|select(has("cache_control")); .cache_control=={type:"ephemeral"}) and all(blocks|select(.type=="thinking");has("cache_control")|not))|not) then error("illegal layout marker")
elif (all(range(0;7); . as $i |
  [$frames[$i].layout.slots[]|select(.kind=="item")|$rows[(.cursor|tostring)]] as $items |
  [$r[$i]|blocks|select(.type=="tool_use")|{id,name,input}] == [$items[]|select(.type=="tool")|{id,name,input:(.args|fromjson)}] and
  [$r[$i]|blocks|select(.type=="tool_result")|{tool_use_id,content,is_error}] == [$items[]|select(.type=="tool")|{tool_use_id:.id,content:.result.output,is_error:.result.is_error}] and
  [$r[$i]|blocks|select(.type=="thinking")|{thinking,signature}] == [$items[]|select(.type=="assistant" and (.thinking|length)>0)|{thinking,signature:.signatures.thinking}] and
  [$r[$i].messages[] as $m|$m.content[]|select(.type=="text")|{role:$m.role,text}] == ($frames[$i].layout|text_slots($rows;$summary)))|not) then error("request differs from actual owner-selected slots or durable content")
elif (all(range(1;7); . as $i |
  (($r[$i]|normalized).messages[0:($r[$i-1].messages|length)]==($r[$i-1]|normalized).messages) or
  any($frames[$i].reasons[]; .=="layout_changed" or .=="layout_reduced"))|not) then error("unexplained prefix change")
elif (all(range(0;7); . as $i |
  ($frames[$i].layout.counts.summary>0 and ($i==0 or $frames[$i-1].layout.counts.summary==0)) ==
  any($frames[$i].reasons[];.=="summary_activated"))|not) then error("summary activation reason differs from selected layout")
elif (all($frames[].reasons[]; IN("layout_changed","layout_reduced","summary_activated"))|not) then error("unrelated frame change")
elif [.events[]|select(.event=="provider_frame")|.reasons]!=[[],[],[],[],[],[],[]] then error("main provider policy changed")
elif ($entries|map(.type))!=["user","assistant","tool","assistant","tool","assistant","tool","assistant","tool","assistant","tool","assistant","user","assistant"] then error("durable rows dropped or rewritten")
elif $rows["1"].text!="read the layout files" or $rows["2"].thinking!="layout reasoning" or $rows["2"].signatures.thinking!="layout-signature-v1" or $rows["3"].result.is_error!=true or ($rows["3"].result.output|contains("missing.rs")|not) then error("original signed failure unit changed")
elif (all(range(1;5); . as $n|$rows[((3+2*$n)|tostring)]|.id=="layout-\($n)" and (.args|fromjson)=={path:"big\($n).rs"} and .result.is_error==false and .result.output==file($n))|not) then error("complete native file history changed")
elif $rows["12"].text!="layout answer" or $rows["13"].text!="continue the layout history" or $rows["14"].text!="layout continued" then error("continuation not retained")
else {scope:"actual-family-cache-layout",main_requests:7,owner_selected_slots:"PASS",exact_surviving_content:"PASS",durable_full_history:"PASS",input_reduction:"PASS",summary_activation:"PASS",failed_call_guard:"PASS",real_cache_hits_verified:false}
end
