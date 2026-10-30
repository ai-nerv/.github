def acceptance_cases:
  ["basic-coding-loop","multi-client","resume-and-restart","memory-process-loss",
   "memory-absent-at-startup","tool-containment","retry-transport-failures","context-pressure",
   "helper-modes","cross-session-memory","agent-coordination","safety-modes","contradictions","usage-accounting"] +
  (if .fixture_version==3 then ["cache-contract"] else [] end);
def valid_acceptance_receipt:
  . as $receipt |
  .kind=="deterministic" and (.fixture_version|IN(2,3)) and .not_verified==0 and
  (.scope//"full")=="full" and (.selected_scenario//"")=="" and
  (if .fixture_version==3 then .scope=="full" else true end) and
  (.scenarios | type=="array" and all(.[];.verdict=="PASS") and
    (map(.id)|sort)==($receipt|acceptance_cases|sort));
def current_acceptance_receipt:
  .fixture_version==3 and valid_acceptance_receipt;
