def message:
  if .case=="output" then "'max_tokens' or 'max_completion_tokens' is too large: 77. This model's maximum context length is 64 tokens and your request has 12 input tokens (77 > 64 - 12)."
  else "prompt is too long: 250000 tokens > 200000 maximum" end;
def verbs($verb): [.log|split("\n")[]|select(test("balthasar\\[[0-9]+\\].*verb: " + $verb + " "))];
. as $capture | message as $message |
[.replay.result[].raw|fromjson|.entry] as $entries |
if (["output","input","unknown"]|index($capture.case))==null then error("unknown routing case")
elif (.requests|length)!=1 or .requests[0].max_tokens!=77 then error("extra request or changed explicit output budget")
elif ([.requests[0].messages[]|select(.role=="user")]|length)!=1 or
  (.requests[0].messages|tostring|contains("overflow routing probe")|not) then error("original prompt missing")
elif (verbs("layout")|length)==0 or (verbs("observe")|length)==0 then error("missing positive Balthasar logging control")
elif (verbs("overflowed")|length)!=(if .case=="output" then 0 else 1 end) then error("wrong overflow routing")
elif (verbs("job_done")|length)!=0 or any((verbs("layout") + verbs("overflowed"))[]; contains(", 0 jobs ")|not) then error("unexpected summary work")
elif [.replay.result[].cursor]!=[1,2,3] or ($entries|map(.type))!=["user","assistant","assistant"] or
  $entries[0].text!="overflow routing probe" or $entries[1].text!="" or
  $entries[1].stop_reason!="error" or $entries[1].error!=("acceptance returned 400 Bad Request (Overflow): " + (if ($message|length)>120 then $message[0:120]+"…" else $message end)) or
  $entries[2].text!="" or $entries[2].stop_reason!="error" then error("durable failure changed")
elif .case=="output" and ($entries[2].error!=($entries[1].error + "; the provider rejected the output budget. Review the output allowance and thinking requirements, or choose a compatible model; input was not compacted and output settings were not changed.")) then error("actionable output refusal changed")
elif .case!="output" and $entries[2].error!="the provider refused this request as too long, and there is nothing left to leave out of it: the instructions, the prompt and what it is working from are all it holds. A model with a larger window, or a new session, is what would fit." then error("input floor refusal missing")
elif ([.events[]|select(.event=="assistant_ended")|{id,stop_reason,error}])!=
  ([$entries[]|select(.type=="assistant")|{id,stop_reason,error}]) then error("failed assistant lifecycle differs from journal")
elif ([.settled[]|select(.event=="session_snapshot" and .status.kind=="idle" and .entries==$entries)]|length)!=1 or
  any(.settled[];.event=="assistant_ended") then error("turn not settled with original history")
else {scope:"actual-family-overflow-routing",case:.case,requests:1,explicit_output:77,
  overflow_calls:(verbs("overflowed")|length),durable_failure:"PASS",settled:"PASS"}
end
