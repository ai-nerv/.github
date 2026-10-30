include "contract";
def need($ok; $message): if $ok then . else error("request bytes: " + $message) end;
def size: whole(0;8388608);
def attempt: whole(1;64);
need(type=="array" and length>=2 and length<=512; "bounded complete ledger required") |
.[0] as $start | .[-1] as $end |
need(($start|exact(["schema","scope","event","limit","capture_limit_bytes","journal_limit_bytes"])) and
  $start.schema==2 and $start.scope=="offline-provider-admission" and $start.event=="start" and
  ($start.limit|whole(1;64)) and ($start.capture_limit_bytes|whole(1;8388608)) and
  $start.journal_limit_bytes==131072; "invalid start") |
reduce .[1:-1][] as $row (
  {admitted:0,reserved:0,captured:0,responses:0,attempts:{},bodies:[]};
  need(($row|type)=="object" and ($row.attempt|attempt); "invalid attempt") |
  ($row.attempt|tostring) as $key |
  if $row.event=="admit" then
    need(($row|exact(["event","attempt"])) and $row.attempt==(.admitted+1) and
      $row.attempt<=$start.limit; "invalid admission") |
    .admitted+=1 | .attempts[$key]={reserved:null,body:false,response:false,barrier:null}
  else
    need(.attempts|has($key); "event without admission") |
    if $row.event=="reserve_capture" then
      need(($row|exact(["event","attempt","bytes","reserved_bytes"])) and
        .attempts[$key].reserved==null and ($row.bytes|size) and
        $row.reserved_bytes==(.reserved+$row.bytes+1) and
        $row.reserved_bytes<=$start.capture_limit_bytes; "invalid reservation") |
      .reserved=$row.reserved_bytes | .attempts[$key].reserved=$row.bytes
    elif $row.event=="body" then
      need(($row|exact(["event","attempt","bytes","sha256"])) and
        .attempts[$key].reserved!=null and (.attempts[$key].body|not) and
        $row.bytes==.attempts[$key].reserved and ($row.sha256|type)=="string" and
        ($row.sha256|test("\\A[0-9a-f]{64}\\z")); "invalid captured body") |
      .bodies += [{attempt:$row.attempt,offset:.captured,bytes:$row.bytes,sha256:$row.sha256}] |
      .captured+=($row.bytes+1) | .attempts[$key].body=true
    elif ($row.event|IN("rendezvous_arrive","rendezvous_release")) then
      need(($row|exact(["event","attempt","turn","group"])) and
        ($row.turn|whole(0;65535)) and ($row.group|type)=="string" and
        ($row.group|test("\\A[a-z-]{1,32}\\z")) and
        .attempts[$key].body and (.attempts[$key].response|not); "invalid rendezvous") |
      if $row.event=="rendezvous_arrive" then
        need(.attempts[$key].barrier==null; "duplicate arrival") |
        .attempts[$key].barrier={group:$row.group,turn:$row.turn,state:"arrived"}
      else
        need(.attempts[$key].barrier=={group:$row.group,turn:$row.turn,state:"arrived"}; "release without arrival") |
        .attempts[$key].barrier.state="released"
      end
    elif $row.event=="response" then
      need(($row|exact(["event","attempt","turn"])) and ($row.turn|whole(0;65535)) and
        .attempts[$key].body and (.attempts[$key].response|not) and
        (.attempts[$key].barrier==null or
          (.attempts[$key].barrier.state=="released" and .attempts[$key].barrier.turn==$row.turn)); "invalid response") |
      .responses+=1 | .attempts[$key].response=true
    else error("request bytes: unsupported or failed event") end
  end
) |
need(($end|exact(["event","status","reason","admitted","rejected","responses","incomplete","reserved_bytes","captured_bytes"])) and
  $end.event=="terminal" and $end.status=="STOPPED" and $end.reason=="stopped" and
  $end.admitted==.admitted and $end.rejected==0 and $end.responses==.responses and
  $end.incomplete==0 and .admitted==.responses and $end.reserved_bytes==.reserved and
  $end.captured_bytes==.captured and .reserved==.captured and .captured==$capture_bytes and
  all(.attempts[]; .body and .response); "incomplete or inconsistent terminal") |
{schema:1,scope:"evaluation-request-bytes",status:"BYTES_MEASURED",complete_run:false,
 representation:"captured-http-body-octets",request_bytes:(.captured-.admitted),
 captured_bytes:.captured,delimiter_bytes:.admitted,provider_received:.admitted,
 provider_attempts:null,stable_prefix_bytes:null,bodies:.bodies}
