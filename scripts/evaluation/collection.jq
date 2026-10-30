include "contract";
include "sample";

if exact(["schema","bindings_sha256","collection_id","started_at","finished_at","results"]) and
  .schema==1 and .bindings_sha256==$binding_sha and
  (.collection_id|type=="string" and test("\\A[0-9a-f]{32}\\z")) and
  (.started_at|timestamp) and (.finished_at|timestamp) and .started_at<=.finished_at and
  (.results|type)=="array" and (.results|length)<=64 and
  all(.results[]; exact(["id","result","evidence"]) and
    (.id|type=="string" and test("\\A[a-zA-Z0-9_.:-]{1,160}\\z")) and
    (.result|path) and (.evidence|path))
then . else error("evaluation collection: invalid index, identity, timestamps or paths") end |
. as $index | ($plan[0]|map(.id)) as $ids |
[$index.results[].id as $id | $ids|index($id)|select(.!=null)] as $ranks |
($ranks==($ranks|sort)) as $ordered |
{order_valid:$ordered,results:[$index.results|to_entries[]|. as $row|$row.value+{
  ordinal:$row.key,
  kind:(if ($ids|index($row.value.id))==null then "unexpected_result"
    elif ([$index.results[]|select(.id==$row.value.id)]|length)>1 then "duplicate_result"
    elif $ordered|not then "invalid_result" else null end)
}]}
