include "contract";

def invalid($reason): error("evaluation artifact: "+$reason);
def digest: type=="string" and test("\\A[0-9a-f]{64}\\z");
def relative_path: type=="string" and length<=256 and
  test("\\A[a-zA-Z0-9_. -]+(?:/[a-zA-Z0-9_. -]+)*\\z") and
  (split("/")|length<=16 and all(.[]; .!="." and .!=".."));
def source_identity:
  exact(["commit","dirty"]) and (.commit|type=="string" and test("\\A[0-9a-f]{40}\\z")) and
  (.dirty|type=="boolean");
def build_identity:
  exact(["status","profile","rustc","target"]) and
  (if .status=="RECORDED" then (.profile|IN("release","debug")) and
    (.rustc|type=="string" and length<=256 and test("\\Arustc [ -~]+\\z")) and
    (.target|IN("x86_64-unknown-linux-gnu","x86_64-unknown-linux-musl"))
   else .=={status:"NOT_RECORDED",profile:null,rustc:null,target:null} end);
def assets: [
  {owner:"magi",name:"init.lua"},{owner:"magi",name:"tools.lua"},
  {owner:"casper",name:"tools.lua"},{owner:"melchior",name:"apis.lua"},
  {owner:"melchior",name:"providers.lua"},{owner:"balthasar",name:"init.lua"},
  {owner:"balthasar",name:"sections.lua"},{owner:"balthasar",name:"sources/magi.lua"}
];

if exact(["schema","kind","platform","source","features","members","assets"])
then . else invalid("unknown or missing fields") end |
if .schema!=1 or .kind!="offline-artifact" or .platform!="linux-x86_64" or (.source|source_identity|not)
then invalid("unsupported artifact or source identity") else . end |
(inventory|map(.features[])|unique) as $known |
if (.features|type)!="array" or .features!=(.features|unique) or
  (all(.features[]; . as $feature|any($known[]; .==$feature))|not)
then invalid("unknown or duplicate feature declarations") else . end |
if (.members|type)!="array" or [.members[].name]!=["magi","casper","melchior","balthasar"] or
  (all(.members[]; exact(["name","path","sha256","source","build"]) and
    (.path|relative_path) and (.sha256|digest) and (.source|source_identity) and (.build|build_identity))|not)
then invalid("family selection must explicitly identify all four members") else . end |
if (.assets|type)!="array" or [.assets[]|{owner,name}]!=assets or
  (all(.assets[]; exact(["owner","name","path","sha256"]) and (.path|relative_path) and (.sha256|digest))|not)
then invalid("public configuration selection differs") else . end |
if ([.members[].path,.assets[].path]|unique|length)!=(4+(assets|length))
then invalid("duplicate source paths") else . end
