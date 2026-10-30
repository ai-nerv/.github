def reject($message): error("evaluation JSON: " + $message);
if length == 0 or length > 16384 then reject("empty or excessive stream") else . end |
reduce .[] as $item ({closed:{}, values:0};
  $item[0] as $path |
  if ($path|length) > 24 then reject("nesting exceeds 24")
  elif ($item|length) == 2 then
    .closed as $closed |
    if any(range(0; ($path|length)+1); ($path[0:.]|tojson) as $key | $closed[$key] == true)
    then reject("duplicate member or multiple documents") else . end |
    .closed[($path|tojson)] = true | .values += 1
  else .closed[($path[0:-1]|tojson)] = true end
) | if .values > 0 then true else reject("missing document") end
