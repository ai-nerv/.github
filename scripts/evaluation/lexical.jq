. as $raw | ($ARGS.named.max_json_bytes // 131072) as $limit |
if ($limit|IN(131072,1048576,16777216)|not) then error("evaluation JSON: unsupported document bound") else . end |
if utf8bytelength > $limit then error("evaluation JSON: document exceeds bound") else . end |
[scan("\"(?:[^\"\\\\\u0000-\u001f]|\\\\(?:[\"\\\\/bfnrt]|u[0-9a-fA-F]{4}))*\"|true|false|null|-?(?:0|[1-9][0-9]*)(?:\\.[0-9]+)?(?:[eE][+-]?[0-9]+)?|[\\[\\]{},:]|[ \\t\\r\\n]+") ] as $tokens |
if ($tokens|join("")) != $raw then error("evaluation JSON: non-JSON token")
elif ($ARGS.named.safe_integers // false) and
  (all($tokens[]; if test("\\A-?[0-9]") then
    test("\\A(?:0|[1-9][0-9]*)\\z") and length<=16 and (length<16 or .<="9007199254740991")
    else true end)|not)
then error("evaluation JSON: counters require canonical safe integer literals")
else ($tokens|join(" ")|fromjson) | true end
