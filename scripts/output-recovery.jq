def verbs($verb): [.log|split("\n")[]|select(test("balthasar\\[[0-9]+\\].*verb: " + $verb + " "))];
[.replay.result[].raw|fromjson|.entry] as $entries |
if [.requests[].max_tokens] != [4096,512] then error("wrong automatic allowance or attempt count")
elif (.requests|map(del(.max_tokens))|unique|length)!=1 then error("non-budget request change")
elif any(.requests[];has("__budget") or has("__scratch") or has("__output_limit")) then error("private metadata leaked")
elif (.requests[0].messages|tostring|contains("automatic output probe")|not) then error("original input missing")
elif (verbs("layout")|length)==0 or (verbs("observe")|length)==0 then error("missing positive Balthasar controls")
elif (verbs("overflowed")|length)!=0 or (verbs("job_done")|length)!=0 then error("output recovery compacted input")
elif [.replay.result[].cursor]!=[1,2] or ($entries|map(.type))!=["user","assistant"] or
  $entries[0].text!="automatic output probe" or $entries[1].text!="default recovered" or
  $entries[1].stop_reason!="end_turn" or $entries[1].error!=null then error("durable recovery changed")
elif ([.events[]|select(.event=="assistant_ended")|{id,stop_reason,error}])!=
  ([$entries[]|select(.type=="assistant")|{id,stop_reason,error}]) then error("wrong terminal lifecycle")
elif ([.settled[]|select(.event=="session_snapshot" and .status.kind=="idle" and .entries==$entries)]|length)!=1 or
  any(.settled[];.event=="assistant_ended") then error("recovery not settled")
else {scope:"actual-family-output-recovery",requests:2,automatic_output:[4096,512],
  unchanged_input:"PASS",overflow_calls:0,durable_answer:"PASS",settled:"PASS"}
end
