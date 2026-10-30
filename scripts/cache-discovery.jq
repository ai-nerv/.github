def normalized: .messages |= map(.content |= map(del(.cache_control)));
def tools: .tools|map(del(.cache_control));
def blocks: .messages[].content[];
def marked: (.system[]?, .tools[]?, blocks)|select(has("cache_control"));
.requests as $r | .events as $events | [.replay.result[].raw|fromjson|.entry] as $entries |
if ($r|length)!=3 then error("three discovery requests required")
elif ($r|map(.messages|length))!=[1,3,5] then error("discovery conversation growth changed")
elif any($r[0].tools[]; .name=="dino") or (all($r[1:][]; [.tools[]|select(.name=="dino")]|length==1)|not) then error("tool not activated at the next request")
elif ($r[1]|tools|map(select(.name!="dino")))!=($r[0]|tools) or ($r[1]|tools)!=($r[2]|tools) then error("activation changed unrelated tools or schema order")
elif (all($r[]; .system==$r[0].system and .model==$r[0].model)|not) then error("activation changed model or system")
elif (all(range(1;3); . as $i|($r[$i]|normalized).messages[0:($r[$i-1].messages|length)]==($r[$i-1]|normalized).messages)|not) then error("discovery rewrote a prefix")
elif ($r|map([marked]|length))!=[3,4,4] or (all($r[]; all(marked; .cache_control=={type:"ephemeral"}) and all(blocks|select(.type=="thinking"); has("cache_control")|not))|not) then error("discovery markers changed")
elif (all($r[1:][]; any(blocks; .type=="thinking" and .thinking=="discovery reasoning" and .signature=="discovery-signature-v1") and any(blocks; .type=="tool_use" and .id=="discover-1" and .name=="tools" and .input=={path:"games/dino"}) and any(blocks; .type=="tool_result" and .tool_use_id=="discover-1" and (.content|tostring|contains("now one of your tools"))))|not) then error("signed discovery tool unit changed")
elif [$events[]|select(.event=="cache_frame")|.reasons]!=[[],["tools_changed"],[]] then error("missing or repeated tool invalidation")
elif [$events[]|select(.event=="provider_frame")|.reasons]!=[[],[],[]] then error("provider policy changed during discovery")
elif ($entries|map(.type))!=["user","assistant","tool","assistant","user","assistant"] or $entries[1].signatures.thinking!="discovery-signature-v1" or $entries[2].id!="discover-1" or $entries[2].name!="tools" or $entries[2].result.is_error!=false or $entries[3].text!="manual discovered" or $entries[5].text!="tool frame retained" then error("unexpected durable discovery history")
else {scope:"actual-family-cache-discovery",requests:3,activation_next_round:"PASS",unchanged_base_tools:"PASS",exact_prefixes:"PASS",signed_unit:"PASS",invalidation_once:"PASS",game_executed:false,real_cache_hits_verified:false}
end
