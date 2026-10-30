include "contract";
def need($ok): if $ok then . else error("unproven client attempt-limit failure") end;
need(($limit|whole(1;64)) and type=="array" and length==($limit+3)) |
.[0] as $start | .[-1] as $end | .[-2] as $reject | .[1:-2] as $admitted |
need($start=={schema:1,scope:"offline-client-admission",event:"start",limit:$limit,
  max_peers:8,max_frame_bytes:128,max_calls:128,frame_timeout_ms:250}) |
need(all($admitted[]; exact(["event","attempt","peer_pid"]) and .event=="admit" and
  (.attempt|whole(1;64)) and (.peer_pid|whole(1;2147483647))) and
  [$admitted[].attempt]==[range(1;$limit+1)]) |
need(($reject|exact(["event","reason","peer_pid"])) and $reject.event=="reject" and
  $reject.reason=="attempt_limit" and ($reject.peer_pid|whole(1;2147483647))) |
need($end=={event:"terminal",status:"FAIL",admitted:$limit,calls:($limit+1)}) |
{schema:1,scope:"evaluation-client-attempts",status:"ATTEMPT_LIMIT_CONFIRMED",failure:"attempt_limit",
 representation:"nonrefundable-pre-send-reservations",provider_attempts:$limit,
 rejected_reservations:1,limit:$limit,peer_pids:([$admitted[].peer_pid,$reject.peer_pid]|unique),complete_run:false}
