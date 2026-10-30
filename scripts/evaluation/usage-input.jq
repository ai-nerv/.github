include "contract";
def need($ok): if $ok then . else error("usage transcript mapping differs") end;
def snapshot($name): {source:$name,reply:$files[0][$name]};
def transcript($id;$names): {id:$id,snapshots:[$names[]|snapshot(.)]};
$files[0]["sessions.json"] as $sessions |
need($sessions.ok==true and $sessions.family==1 and $sessions.n==($sessions.result|length) and
  $sessions.n>=1 and $sessions.n<=16 and ([$sessions.result[].id]|unique|length)==$sessions.n) |
(if $task=="resume" then
   $files[0]["phases.jsonl"] as $phases |
   need([$phases[].phase]==["initial","distractor","latest","named"] and
     all($phases[];.exit_code==0) and ($phases|map(.coordination_run)|unique|length)==4 and
     $phases[0].transcript==$phases[3].transcript and $phases[1].transcript==$phases[2].transcript) |
   [transcript($phases[0].transcript;["replay-initial.json","replay-named.json"]),
    transcript($phases[1].transcript;["replay-distractor.json","replay-latest.json"])]
 elif $task=="child-work" then
   $files[0]["identities.json"] as $id |
   need($id.child_transcript==($id.run+"@"+$id.child)) |
   [transcript($id.run;["replay-parent.json"]),transcript($id.child_transcript;["replay-child.json"])]
 elif $task=="cache-accounting" then
   $files[0]["ledger-runs.json"] as $runs |
   [transcript($runs.chat;["replay-0.json"]),transcript($runs.anthropic;["replay-1.json"])]
 elif $task=="concurrent-disjoint-edits" then
   need($sessions.n==2) |
   [range(0;2) as $i|transcript($sessions.result[$i].id;["replay-"+($i|tostring)+".json"])]
 else need($sessions.n==1) | [transcript($sessions.result[0].id;["replay.json"])] end) |
need((map(.id)|sort)==([$sessions.result[].id]|sort))
