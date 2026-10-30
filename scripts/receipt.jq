def text: type == "string" and length > 0;
def natural: type == "number" and . >= 0 and floor == .;
def digest: type == "string" and test("^[a-f0-9]{64}$");
def launcher: type == "object" and (.path | text) and (.sha256 | digest);
def unique_ids: map(.id) | length == (unique | length);
def case_status: IN("PASS", "FAIL", "NOT_RUN", "BLOCKED");
def members:
    type == "array" and length == 4 and
    (map(.name) | sort == ["balthasar", "casper", "magi", "melchior"]) and
    all(.[]; (.commit | text) and (.dirty | type == "boolean"));
def command:
    (.id | text) and (.argv | type == "array" and length > 0 and all(.[]; text)) and
    (.argv == ["oslo", "make", ({runner:"test-family-runner",family:"test-family",
                                acceptance:"acceptance",verify:"verify"}[.id])]) and
    (.log | text) and (.elapsed_ms | natural) and
    (.exit_code | natural) and (.interrupted | type == "boolean") and
    (.status | IN("PASS", "FAIL")) and
    (.status == (if .exit_code == 0 and .interrupted == false then "PASS" else "FAIL" end));
def valid:
    .schema == 1 and .phase == "00" and
    (.status | IN("NOT_RUN", "RUNNING", "PASS", "FAIL")) and
    (.root_commit | text) and (.root_dirty | type == "boolean") and
    (.started_at | text) and (.members | members) and
    (.configuration_digest | digest) and
    (.environment | type == "object" and (.fixture_version | IN(1, 2, 3)) and
        (.profile | text) and (.toolchain | text) and
        (.selected_launcher == null or (.selected_launcher | launcher)) and
        (.required_backends == ["bubblewrap", "landlock"])) and
    (.commands | type == "array" and length <= 4 and unique_ids and all(.[]; command)) and
    (.required_cases | type == "array" and length == 4 and unique_ids and
        (map(.id) | sort == ["acceptance", "family", "runner", "verify"]) and
        all(.[]; (.status | case_status))) and
    (.skipped_cases | type == "array" and all(.[];
        (.id | text) and (.required | type == "boolean") and (.reason | text) and (.log | text))) and
    (.unexpected_processes | type == "array") and
    .paid_requests == 0 and (.limitations | type == "array" and all(.[]; text)) and
    (. as $r | all(.required_cases[]; . as $case |
        if .status == "NOT_RUN" then all($r.commands[]; .id != $case.id)
        elif .status == "BLOCKED" then (.detail | text)
        else any($r.commands[]; .id == $case.id and .status == $case.status) end)) and
    (. as $r | all(.commands[]; . as $command |
        any($r.required_cases[]; .id == $command.id and .status == $command.status))) and
    (if .status == "NOT_RUN" then
        .finished_at == null and .active_command == null and (.commands | length == 0) and
        all(.required_cases[]; .status == "NOT_RUN")
    elif .status == "RUNNING" then
        .finished_at == null and (.active_command | IN(null,"runner","family","acceptance","verify"))
    else
        (.finished_at | text) and .active_command == null and
        (if .status == "PASS" then
            (.commands | length == 4) and all(.commands[]; .status == "PASS") and
            all(.required_cases[]; .status == "PASS") and
            all(.skipped_cases[]; .required == false) and (.unexpected_processes | length == 0) and
            (.environment.selected_launcher | launcher) and
            all(.members[]; (.path | text) and (.sha256 | digest) and .profile == "release" and (.target | text))
        else any(.required_cases[]; .status != "PASS") or (.limitations | length > 0) end)
    end);
if valid then . else error("invalid or incomplete Phase 00 receipt") end
