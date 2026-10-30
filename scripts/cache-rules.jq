def normalized: .messages |= map(.content |= map(del(.cache_control)));
def blocks: .messages[].content[];
[.requests[]|select(any(.tools[]?;.name=="read"))] as $r |
[.replay.result[].raw|fromjson|.entry] as $entries |
if ($r|length)!=3 then error("three rule requests required")
elif (all($r[];.model==$r[0].model and .tools==$r[0].tools and .system==$r[0].system)|not) then error("rule changed base frame")
elif ($r[0]|normalized).messages!=[{role:"user",content:[{type:"text",text:"Always keep diagnostics private."}]}] then error("original directive changed")
elif ($r[1].messages[0].content[0]|del(.cache_control))!={type:"text",text:"Verified project rules:\n- Always keep diagnostics private."} or $r[1].messages[0].role!="user" then error("verified rule missing or wrong authority")
elif ($r[1]|normalized|.messages[0].content |= .[1:]).messages[0]!=($r[0]|normalized).messages[0] then error("rule insertion changed original user content")
elif ($r[2]|normalized).messages[0:3]!=($r[1]|normalized).messages then error("stable rule changed the prefix")
elif ($r|map(.messages|length))!=[1,3,5] then error("unexpected rule history growth")
elif ($r|map([(.system[]?,.tools[]?,blocks)|select(has("cache_control"))]|length))!=[3,4,4] or (all($r[]; all((.system[]?,.tools[]?,blocks)|select(has("cache_control"));.cache_control=={type:"ephemeral"}) and all(blocks|select(.type=="thinking");has("cache_control")|not))|not) then error("rule marker contract changed")
elif $r[1].messages[-1].content[0].text!="apply the standing rule" or $r[2].messages[-1].content[0].text!="continue with the same rule" then error("latest rule prompt changed")
elif ($r[1].messages[1].content|map(del(.cache_control)))!=[{type:"thinking",thinking:"rules reasoning",signature:"rules-signature-v1"},{type:"text",text:"rule recorded"}] or $r[2].messages[3].content[0].text!="rule applied" then error("assistant history changed")
elif (all($r[1:][]; any(blocks;.type=="thinking" and .thinking=="rules reasoning" and .signature=="rules-signature-v1"))|not) then error("signed history changed")
elif [.events[]|select(.event=="cache_frame")|.reasons]!=[[],["rules_changed","layout_changed"],[]] then error("rule invalidation missing or repeated")
elif [.events[]|select(.event=="provider_frame")|.reasons]!=[[],[],[]] then error("provider policy changed")
elif ([.events[]|select(.event=="context_laid")|[.slots[]|select(.kind=="rules")]|length]!=[0,1,1]) then error("rule not selected by Balthasar")
elif ($entries|map(.type))!=["user","assistant","user","assistant","user","assistant"] or $entries[0].text!="Always keep diagnostics private." or $entries[1].signatures.thinking!="rules-signature-v1" or $entries[3].text!="rule applied" or $entries[5].text!="rule retained" then error("durable rule history changed")
elif .note.ok!=true or .note.result[0].text!="Always keep diagnostics private." or .note.result[0].pinned!=true then error("rule not stored by memory owner")
elif .note.result[0].evidence.kind!="user-rule" or .note.result[0].evidence.version!=1 or (.note.result[0].evidence.sources|length)!=1 or (.note.result[0].evidence.sources[0]|{cursor,role,kind,quote,eligible})!={cursor:1,role:"user",kind:"user",quote:"Always keep diagnostics private.",eligible:true} then error("rule lacks verified original user evidence")
else {scope:"actual-family-cache-rules",main_requests:3,verified_rule_projection:"PASS",exact_original_content:"PASS",stable_rule_prefix:"PASS",signed_history:"PASS",invalidation_once:"PASS",real_cache_hits_verified:false}
end
