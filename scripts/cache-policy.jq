def blocks: .messages[]?.content[]?;
def normalized: .messages |= map(.content |= map(del(.cache_control)));
def count_markers:
  ([if (.system|type)=="array" then .system[] else empty end, .tools[]?, blocks]
    | map(select(has("cache_control"))) | length);
def legal_markers:
  all((if (.system|type)=="array" then .system[] else empty end, .tools[]?, blocks) | select(has("cache_control")); .cache_control=={type:"ephemeral"}) and
  all(blocks | select(.type=="thinking"); has("cache_control")|not) and
  all(.messages[]; [.content[]|select(has("cache_control"))]|length<=1) and
  ([blocks|select(has("cache_control"))]|length<=2) and (has("cache_control")|not);
def restore_image($image): .messages[0].content[1] = $image;
.requests as $r | .events as $events |
if ($r|length)!=4 then error("four policy requests required")
elif (all($r[]; .model==$r[0].model and legal_markers)|not) then error("model or marker contract changed")
elif ($r|map(count_markers))!=[3,0,0,4] then error("cache opt-out or restoration not reflected")
elif $r[0].system!=$r[3].system or $r[1].system!=$r[0].system[0].text or $r[2].system!=$r[1].system then error("system content changed")
elif (all($r[]; (.tools|map(del(.cache_control)))==($r[0].tools|map(del(.cache_control))))|not) then error("tool frame changed")
elif ($r|map(.messages|length))!=[1,3,5,7] then error("unexpected conversation growth")
elif ($r[0].messages[0].content[1]|del(.cache_control))!={type:"image",source:{type:"base64",media_type:"image/png",data:"iVBORw0KGgo="}} then error("original image changed")
elif ($r[1]|normalized).messages[0]!=($r[0]|normalized).messages[0] then error("cache disable altered history")
elif $r[2].messages[0].content[1]!={type:"text",text:"[Image omitted: the current model does not support images. Switch to a vision-capable model to view it.]"} then error("image adaptation was not exact")
elif ($r[2]|normalized|restore_image($r[1].messages[0].content[1])).messages[0:3]!=($r[1]|normalized).messages then error("image adaptation changed unrelated content")
elif ($r[3]|normalized).messages[0:5]!=($r[2]|normalized|restore_image($r[1].messages[0].content[1])).messages then error("reenable did not restore exact original history")
elif (all($r[1:][]; any(blocks; .type=="thinking" and .thinking=="policy reasoning" and .signature=="policy-signature-v1"))|not) then error("opaque signed content changed")
elif [$events[]|select(.event=="cache_frame")|.reasons]!=[[],[],[],[]] then error("neutral content changed")
elif [$events[]|select(.event=="provider_frame")|.reasons]!=[[],["provider_policy_changed"],["provider_policy_changed","images_adapted"],["provider_policy_changed"]] then error("missing or incorrect provider transition")
elif (all($events[]|select(.event=="provider_frame"); keys==["event","reasons"] )|not) then error("policy fingerprint leaked into diagnostic events")
else {scope:"actual-family-provider-policy",requests:4,markers:[3,0,0,4],same_model:true,
      cache_disable:"PASS",image_adaptation:"PASS",exact_restoration:"PASS",signed_history:"PASS",
      explicit_transitions:"PASS",real_cache_hits_verified:false}
end
