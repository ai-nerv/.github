include "contract";

def require($ok; $why): if $ok then . else error("transcript usage: "+$why) end;
def count: whole(0;9007199254740991);
def names: ["input_tokens","output_tokens","cache_read_tokens","cache_write_tokens","reported_micros","estimated_micros","charged_micros"];
def zero: names|map({key:.,value:0})|from_entries;
def unknown: names|map({key:.,value:null})|from_entries;
def plus($a;$b):
  reduce names[] as $key ($a;
    require(.[$key]<=(9007199254740991-$b[$key]); "counter overflow") | .[$key]+=$b[$key]);
def usage:
  require(exact(["input","output","cache_read","cache_write","cost_micros","estimated_micros"]) and all(.[];count); "invalid usage fields") |
  require(.cost_micros<=(9007199254740991-.estimated_micros); "charge overflow") |
  {input_tokens:.input,output_tokens:.output,cache_read_tokens:.cache_read,cache_write_tokens:.cache_write,
   reported_micros:.cost_micros,estimated_micros,charged_micros:(.cost_micros+.estimated_micros)};
def replay:
  require(.family==1 and .ok==true and (.n|whole(1;256)) and (.result|type)=="array" and
    .n==(.result|length) and .more!=true and [.result[].cursor]==[range(1;.n+1)]; "incomplete replay") |
  require(all(.result[]; . as $row | (.raw|fromjson) as $record |
    $row.revisions==0 and $row.truncated!=true and ($row|has("raw_bytes")|not) and
    $record.record=="entry" and $record.cursor==$row.cursor and
      (if $record.entry.type=="from" then ($row.role|IN("user","other","from"))
       else $record.entry.type==$row.role and ($row.role|IN("user","assistant","tool")) end)); "unverifiable or revised replay") |
  .result;
def tally:
  [.[]|.raw|fromjson|.entry|select(.type=="assistant")] as $assistants |
  [$assistants[]|select(.usage!=null)|.usage|usage] as $known |
  ($assistants|length)-($known|length) as $missing |
  (reduce $known[] as $row (zero;plus(.;$row))) as $sum |
  {assistant_records:($assistants|length),usage_records:($known|length),unknown_usage_records:$missing,
   known_totals:$sum,totals:(if $missing==0 then $sum else unknown end)};

require(type=="array" and length>=1 and length<=16; "transcript count") |
require((map(.id)|unique|length)==length and
  all(.[]; exact(["id","snapshots"]) and (.id|type=="string" and test("\\A[a-zA-Z0-9_@-]{1,160}\\z")) and
    (.snapshots|type)=="array" and (.snapshots|length)>=1 and (.snapshots|length)<=8 and
    all(.snapshots[]; exact(["source","reply"]) and (.source|type=="string" and test("\\A[a-zA-Z0-9_.-]+\\.json\\z")))); "transcript identities") |
require(([.[].snapshots[].source]|unique|length)==([.[].snapshots[].source]|length); "source reused across snapshots") |
map(. as $transcript |
  (reduce .snapshots[] as $snapshot ([];
    . as $before | ($snapshot.reply|replay) as $after |
    require(($after|length)>=($before|length) and $after[0:($before|length)]==$before; "rewritten or shortened history") | $after)) as $rows |
  {id,sources:[.snapshots[].source],cursors:($rows|length)}+($rows|tally)) as $transcripts |
(reduce $transcripts[] as $row ({known:zero,missing:0};
  .known=plus(.known;$row.known_totals) | .missing+=$row.unknown_usage_records)) as $all |
{schema:1,scope:"evaluation-transcript-usage",status:"USAGE_EXTRACTED",coverage:"durable-assistant-entries-only",
 complete_run:false,transcripts:$transcripts,unknown_usage_records:$all.missing,
 known_totals:$all.known,totals:(if $all.missing==0 then $all.known else unknown end)}
