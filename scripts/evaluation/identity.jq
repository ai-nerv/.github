include "contract";

def digest: type=="string" and test("\\A[0-9a-f]{64}\\z");
def model:
  exact(["provider","id","api"]) and (.provider|identifier) and
  (.id|type=="string" and length>0 and length<=128 and test("\\A[a-zA-Z0-9_./-]+\\z")) and
  (.api|IN("openai-completions","anthropic-messages"));
def models:
  type=="array" and length>=1 and length<=16 and all(.[]; model) and
  .==sort_by([.provider,.id,.api]) and (unique_by([.provider,.id])|length)==length;
def validate_bindings($manifest; $sha):
  if exact(["schema","manifest_sha256","runner_sha256","artifacts","tasks"] +
      (if $manifest|has("event_observer") then ["event_observer"] else [] end)) and .schema==2 and
    (.manifest_sha256|digest) and .manifest_sha256==$sha and (.runner_sha256|digest) and
    (.artifacts|exact(["baseline","candidate"]) and all(.[]; digest)) and
    (.tasks|type)=="array" and [.tasks[].id]==[$manifest.tasks[].id] and
    all(.tasks[]; exact(["id","fixture_sha256","config_sha256","models"]) and (.fixture_sha256|digest) and
      (.config_sha256|exact(["baseline","candidate"]) and all(.[]; digest)) and (.models|models)) and
    (if $manifest|has("event_observer") then .event_observer==$manifest.event_observer and
       .artifacts.baseline==.artifacts.candidate and all(.tasks[]; .config_sha256.baseline==.config_sha256.candidate)
     else true end)
  then . else error("evaluation identities: invalid frozen binding") end;
