def blocks: .messages[]?.content[]?;
def marked: select(has("cache_control"));
def normalized: .messages |= map(.content |= map(del(.cache_control)));
def locations: [.messages|to_entries[] | .key as $m | .value.content|to_entries[] | select(.value.cache_control) | [$m,.key]];
def marker_count: ([.system[]? | marked] | length) + ([.tools[]? | marked] | length) + ([blocks | marked] | length);
def valid_markers:
  all((.system[]?, .tools[]?, blocks) | marked; .cache_control == {type:"ephemeral"}) and
  all(blocks | select(.type=="thinking"); has("cache_control") | not) and
  all(.messages[]?; [.content[]? | marked] | length <= 1) and
  ([blocks | marked] | length <= 2) and marker_count <= 4 and
  (.system | type=="array" and length==1) and .system[0].cache_control=={type:"ephemeral"} and
  (.tools | type=="array" and length>0) and .tools[-1].cache_control=={type:"ephemeral"} and
  all(.tools[0:-1][]; has("cache_control") | not) and
  (has("cache_control") | not);
. as $requests |
if length!=3 then error("expected exactly three real provider requests")
elif (all(.[]; valid_markers) | not) then error("illegal or missing cache markers")
elif map(locations)!=[[[0,0]],[[1,1],[2,0]],[[3,0],[4,0]]] then error("unexpected actual conversation boundaries")
elif (all(.[]; .system==$requests[0].system and .tools==$requests[0].tools) | not) then error("structural cache frame changed")
elif (($requests[0]|normalized).messages as $prefix | ($requests[1]|normalized).messages[0:($prefix|length)]!=$prefix) then error("first normalized prefix changed")
elif (($requests[1]|normalized).messages as $prefix | ($requests[2]|normalized).messages[0:($prefix|length)]!=$prefix) then error("second normalized prefix changed")
elif (any($requests[1]|blocks; .type=="thinking" and .thinking=="cache reasoning\r\n" and .signature=="cache-signature-v1") | not) then error("signed thinking was not replayed")
elif (any($requests[1]|blocks; .type=="tool_use" and .id=="cache-read-1" and .name=="read" and .input=={path:"a.rs"}) | not) then error("tool call unit changed")
elif (any($requests[1]|blocks; .type=="tool_result" and .tool_use_id=="cache-read-1" and .is_error==false and (.content|tostring|contains("pub fn cache_value"))) | not) then error("actual native read result missing")
else {scope:"actual-family-cache-contract",requests:length,markers:map(marker_count),
      structural_frames:"PASS",normalized_prefixes:"PASS",signed_tool_unit:"PASS",actual_read:"PASS",
      usage_source:"synthetic",real_cache_hits_verified:false}
end
