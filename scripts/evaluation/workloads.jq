def workload($id):
  (if $id|IN("small-bug-fix","large-file-edit","read-index-select-edit") then
     {driver:"mutation-workload.sh",args:[$id],scorer:"score-mutation.sh",scorer_args:[$id]}
   elif $id|IN("repetitive-failure","output-only-overflow") then
     {driver:"control-workload.sh",args:[$id],scorer:"score-control.sh",scorer_args:[$id]}
   elif $id=="concurrent-disjoint-edits" then
     {driver:"concurrent-workload.sh",args:[],scorer:"score-concurrent.sh",scorer_args:[]}
   elif $id=="cache-accounting" then
     {driver:"accounting-workload.sh",args:[],scorer:"score-accounting.sh",scorer_args:[]}
   elif $id=="input-pressure" then
     {driver:"pressure-workload.sh",args:[],scorer:"score-pressure.sh",scorer_args:[]}
   elif $id=="resume" then
     {driver:"resume-workload.sh",args:[],scorer:"score-resume.sh",scorer_args:[]}
   elif $id=="child-work" then
     {driver:"child-workload.sh",args:[],scorer:"score-child.sh",scorer_args:[]}
   else error("unknown executable workload") end) +
  {models:(if $id=="cache-accounting" then
     [{provider:"evaluation-anthropic",id:"anthropic-1",api:"anthropic-messages"},
      {provider:"evaluation-chat",id:"chat-1",api:"openai-completions"}]
   else [{provider:"evaluation",id:"echo-1",api:"openai-completions"}] end),
   rust_grammar:($id=="read-index-select-edit")};
