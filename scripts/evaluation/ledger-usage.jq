include "contract";
def need($ok): if $ok then . else error("evaluation spending ledger differs") end;
def id: type=="string" and test("\\A[a-zA-Z0-9_-]{1,128}\\z");
def amount:
  need(type=="string" and test("\\A(?:0|[1-9][0-9]{0,15})\n\\z")) |
  rtrimstr("\n") | need(length<16 or .<="9007199254740991") | tonumber;
def capture($run;$transcripts;$file):
  {coordination_run:$run,transcripts:$transcripts,source:$file,charged_micros:($files[0][$file]|amount)};
$files[0] as $f | $f["sessions.json"] as $sessions |
need($sessions.family==1 and $sessions.ok==true and ($sessions.result|type)=="array" and
  $sessions.n==($sessions.result|length) and $sessions.n==2 and
  ([$sessions.result[].id]|unique|length)==2) |
(if $task=="resume" then
   $f["phases.jsonl"] as $phases |
   need(($phases|type)=="array" and [$phases[].phase]==["initial","distractor","latest","named"] and
     all($phases[]; exact(["phase","transcript","coordination_run","exit_code"]) and
       (.transcript|id) and (.coordination_run|id) and .exit_code==0) and
     $phases[0].transcript==$phases[0].coordination_run and
     $phases[1].transcript==$phases[1].coordination_run and
     $phases[0].transcript==$phases[3].transcript and $phases[1].transcript==$phases[2].transcript and
     $phases[0].transcript!=$phases[1].transcript) |
   [$phases[]|capture(.coordination_run;[.transcript];"ledger-"+.phase+".txt")]
 elif $task=="cache-accounting" then
   $f["ledger-runs.json"] as $runs |
   need(($runs|exact(["chat","anthropic"])) and ($runs.chat|id) and ($runs.anthropic|id) and
     $f["chat.exit"]=="0\n" and $f["anthropic.exit"]=="0\n") |
   [capture($runs.chat;[$runs.chat];"ledger-0.txt"),capture($runs.anthropic;[$runs.anthropic];"ledger-1.txt")]
 elif $task=="child-work" then
   $f["identities.json"] as $identity |
   need(($identity|exact(["run","parent","child","child_transcript","child_pid","report_file"])) and
     ($identity.run|id) and ($identity.parent|id) and ($identity.child|id) and
     $identity.parent!=$identity.child and ($identity.child_pid|whole(1;2147483647)) and
     $identity.child_transcript==($identity.run+"@"+$identity.child) and
     $identity.report_file==($identity.child+".report") and $f["magi.exit"]=="0\n") |
   [capture($identity.run;[$identity.run,$identity.child_transcript];"ledger.txt")]
 else error("no captured spending ledger for this workload") end) as $captures |
need(($captures|map(.coordination_run)|unique|length)==($captures|length) and
  ($captures|map(.source)|unique|length)==($captures|length) and
  ([$captures[].transcripts[]]|unique|sort)==([$sessions.result[].id]|sort)) |
(reduce $captures[].charged_micros as $value (0;
  need(.<=(9007199254740991-$value)) | .+$value)) as $charged |
{schema:1,scope:"evaluation-captured-spending-ledgers",status:"LEDGERS_EXTRACTED",complete_run:false,
 coverage:"captured-coordination-run-ledgers",settlement_verified:false,
 charged_micros:$charged,reported_micros:null,estimated_micros:null,
 input_tokens:null,output_tokens:null,cache_read_tokens:null,cache_write_tokens:null,captures:$captures}
