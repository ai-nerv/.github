def normalized: .messages |= map(.content |= map(del(.cache_control)));
def marked: (.system[]?, .tools[]?, .messages[]?.content[]?) | select(has("cache_control"));
def legal_markers:
  all(marked; .cache_control=={type:"ephemeral"}) and
  all(.messages[].content[]|select(.type=="thinking"); has("cache_control")|not) and
  all(.messages[]; [.content[]|select(has("cache_control"))]|length<=1);
def entries: [.result[].raw|fromjson|.entry];
.requests as $r | .events as $events | (.before|entries) as $before | (.after|entries) as $after |
if ($r|length)!=4 then error("four resume requests required")
elif ($r|map([marked]|length))!=[3,4,4,4] or (all($r[]; legal_markers)|not) then error("resume marker boundary changed")
elif ($r|map(.messages|length))!=[1,3,5,7] then error("resume history growth changed")
elif (all($r[]; .model==$r[0].model and .system==$r[0].system and .tools==$r[0].tools)|not) then error("resume changed model or base frame")
elif (all(range(1;4); . as $i | ($r[$i]|normalized).messages[0:($r[$i-1].messages|length)]==($r[$i-1]|normalized).messages)|not) then error("resume changed an existing prefix")
elif ($r[0].messages[0].content[1]|del(.cache_control))!={type:"image",source:{type:"base64",media_type:"image/png",data:"iVBORw0KGgo="}} then error("initial image changed")
elif (all($r[1:][]; any(.messages[].content[]; .type=="thinking" and .thinking=="resume reasoning" and .signature=="resume-signature-v1"))|not) then error("signed reasoning lost")
elif (all($r[1:][]; any(.messages[].content[]; .type=="tool_use" and .id=="resume-read-1" and .name=="read" and .input=={path:"resume.rs"}) and any(.messages[].content[]; .type=="tool_result" and .tool_use_id=="resume-read-1" and (.content|tostring|contains("pub fn resume_value"))))|not) then error("native tool unit changed")
elif [$events[]|select(.event=="cache_frame")|.reasons]!=[[],[],["resume_incompatible"],[]] then error("resume invalidation missing or repeated")
elif [$events[]|select(.event=="provider_frame")|.reasons]!=[[],[],[],[]] then error("unexpected provider policy change")
elif any($events[]; .event=="refused") then error("successful resume was refused")
elif ($before|map(.type))!=["user","assistant","tool","assistant"] or $before[3].text!="before resume" then error("unexpected original transcript")
elif $after[0:4]!=$before or ($after|map(.type))!=["user","assistant","tool","assistant","user","assistant","user","assistant"] then error("resume rewrote durable history")
elif $after[4].text!="continue restored history" or $after[5].text!="after resume" or $after[6].text!="continue once more" or $after[7].text!="continued after resume" then error("resumed history not stored in original session")
elif ($after|tostring|contains("request_frame")) then error("observation leaked into transcript")
else {scope:"actual-family-cache-resume",requests:4,exact_prefixes:"PASS",native_tool_unit:"PASS",image:"PASS",signed_history:"PASS",durable_history:"PASS",invalidation_once:"PASS",real_cache_hits_verified:false}
end
