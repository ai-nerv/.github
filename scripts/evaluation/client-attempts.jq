include "contract";
def need($ok): if $ok then . else error("invalid client admission ledger") end;
need(type=="array" and length>=2 and length<=66) |
.[0] as $start | .[-1] as $end | .[1:-1] as $rows |
need($start=={schema:1,scope:"offline-client-admission",event:"start",limit:$limit,
  max_peers:8,max_frame_bytes:128,max_calls:128,frame_timeout_ms:250}) |
need(($limit|whole(1;64)) and ($rows|length)<=$limit and
  all($rows[]; exact(["event","attempt","peer_pid"]) and .event=="admit" and
    (.attempt|whole(1;64)) and (.peer_pid|whole(1;2147483647))) and
  [$rows[].attempt]==[range(1;($rows|length)+1)]) |
need($end=={event:"terminal",status:"STOPPED",admitted:($rows|length),calls:($rows|length)}) |
{schema:1,scope:"evaluation-client-attempts",status:"ATTEMPTS_MEASURED",
 representation:"nonrefundable-pre-send-reservations",provider_attempts:($rows|length),
 limit:$limit,peer_pids:([$rows[].peer_pid]|unique)}
