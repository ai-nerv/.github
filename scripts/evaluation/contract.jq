def reject($message): error("evaluation manifest: " + $message);
def exact($names): type == "object" and (keys == ($names|sort));
def whole($low; $high): type == "number" and . >= $low and . <= $high and floor == .;
def identifier: type == "string" and test("\\A[a-z][a-z0-9-]{0,63}\\z");
def inventory: [
  {id:"small-bug-fix", features:["complete_source_edit"], checks:["known-red-to-green","unrelated-bytes"]},
  {id:"read-index-select-edit", features:["complete_source_edit"], checks:["selected-symbol","unrelated-bytes"]},
  {id:"large-file-edit", features:["complete_source_edit"], checks:["whole-file-relation","tail-preserved"]},
  {id:"concurrent-disjoint-edits", features:["file_transactions"], checks:["both-edits-or-stale","no-lost-update"]},
  {id:"repetitive-failure", features:["no_progress"], checks:["bounded-executions","paired-journal"]},
  {id:"output-only-overflow", features:["typed_overflow"], checks:["same-input","lower-output","no-summary"]},
  {id:"input-pressure", features:["cache_contract"], checks:["required-context","paired-journal"]},
  {id:"cache-accounting", features:["usage_accounting"], checks:["both-usage-dialects","exact-charge"]},
  {id:"resume", features:["resume"], checks:["selected-history","no-replayed-mutation","no-cost-recount"]},
  {id:"child-work", features:["child_work","file_transactions","usage_accounting"], checks:["independent-observations","combined-charge","report-owner"]}
];
def selected($suite):
  inventory | if $suite == "full" then .
  elif $suite == "core" then [.[]|select(.id|IN("small-bug-fix","read-index-select-edit","large-file-edit","cache-accounting"))]
  elif $suite == "transaction" then [.[]|select(.id=="concurrent-disjoint-edits")]
  elif $suite == "progress" then [.[]|select(.id=="repetitive-failure")]
  elif $suite == "cache" then [.[]|select(.id|IN("input-pressure","cache-accounting"))]
  elif $suite == "overflow" then [.[]|select(.id=="output-only-overflow")]
  elif $suite == "resume" then [.[]|select(.id=="resume")]
  elif $suite == "child" then [.[]|select(.id=="child-work")]
  else reject("unknown suite") end;
def validate_manifest:
if (exact(["schema","id","kind","suite","fixture_revision","samples_per_variant","warmups","order","startup","permissions_profile","expected_network","live_authorization","limits","tasks"] +
  (if has("event_observer") then ["event_observer"] else [] end))|not)
then reject("unknown or missing top-level fields") else . end |
if has("event_observer") and (.event_observer|exact(["schema","sha256","modes"]) and .schema==1 and
  (.sha256|type=="string" and test("\\A[0-9a-f]{64}\\z")) and .modes=={baseline:"drain",candidate:"stall"}|not)
then reject("invalid paired event observer policy") else . end |
if .schema != 1 or .kind != "offline" or (.id|identifier|not) or .fixture_revision != 1
then reject("unsupported version, kind or identifier") else . end |
if .samples_per_variant != 3 or .warmups != 0 or .order != "alternating" or .startup != "fresh-world"
then reject("sampling policy differs from approved policy") else . end |
if .permissions_profile != "fixture-confined" or .expected_network != "local-fixtures-only" or .live_authorization != null
then reject("offline authority policy required") else . end |
if .limits != {timeout_seconds:60,max_provider_attempts:64,fixture_bytes:16777216,fixture_files:256}
then reject("approved limits required") else . end |
. as $manifest | selected(.suite) as $inventory |
if (.tasks|type) != "array" or (.tasks|length) == 0 or (.tasks|length) > 10
then reject("nonempty bounded task array required") else . end |
if [.tasks[].id] != [$inventory[].id] then reject("suite task inventory or order differs") else . end |
if all(range(0; (.tasks|length)); . as $at | $manifest.tasks[$at] as $task | $inventory[$at] as $known |
  ($task|exact(["id","fixture","prompt_fixture","seed","timeout_seconds","max_provider_attempts","requires_features","checks"])) and
  $task.fixture == ("fixtures/"+$known.id) and $task.prompt_fixture == ("fixtures/"+$known.id+"/prompt.txt") and
  ($task.seed|whole(0;2147483647)) and ($task.timeout_seconds|whole(1;60)) and
  ($task.max_provider_attempts|whole(1;64)) and $task.requires_features == $known.features and $task.checks == $known.checks
) then . else reject("invalid task fields, paths, bounds, features or checks") end;

def planned:
  . as $manifest |
  [range(0; (.tasks|length)) as $task | range(1;4) as $sample |
   (if (($task+$sample-1)%2)==0 then ["baseline","candidate"] else ["candidate","baseline"] end)[] as $variant |
   {id:($manifest.tasks[$task].id+":"+$variant+":"+($sample|tostring)),
    task_id:$manifest.tasks[$task].id, variant:$variant, sample:$sample, seed:$manifest.tasks[$task].seed}
  ];
