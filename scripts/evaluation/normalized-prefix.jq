def need($ok): if $ok then . else error("unsupported prompt prefix shape") end;
def block: if type=="object" then del(.cache_control) else . end;
def content: if type=="array" then map(block) else . end;
need(type=="object" and (.model|type)=="string" and (.model|length)>0 and
  (.messages|type)=="array" and all(.messages[]; type=="object" and (.role|type)=="string") and
  ((.tools==null) or (.tools|type)=="array") and
  ((.system==null) or (.system|type|IN("string","array")))) |
{identity: [.model, (if has("system") then "system-field" else "messages-only" end)],
 prompt: [((.tools//[])|map(block)), ((.system//[])|content),
   (.messages|map(if has("content") then .content|=content else . end))]}
