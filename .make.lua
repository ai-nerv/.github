-- The four programs, together. Each is a submodule with its own .make.lua; these recipes go into
-- each and call the recipe there, so `make` inside a checkout still means that program alone.
--
--   make build · run · install · test    all four, in the order a person meets them
--   make status · update · push          where each checkout stands, and moving it
--   make release --type minor             a version of each, develop into main, then pinned

local make = oslo.make

local MEMBERS = { "magi", "casper", "melchior", "balthasar" }

-- balthasar's `build` is static against musl and wants a musl compiler its flake provides and a
-- fresh machine does not. `build-host` is the ordinary build its own `install` uses.
local BUILD = { balthasar = "build-host" }

local function sh(command)
  assert(oslo.run{ "sh", "-c", command }.ok, command .. " failed")
end

local function captured(command)
  local done = oslo.run{ "sh", "-c", command, capture = true }
  return done.ok, ((done.out or ""):gsub("%s+$", ""))
end

-- A clone made without --recursive leaves each member an empty directory.
local function checked_out()
  for _, name in ipairs(MEMBERS) do
    if not oslo.fs.stat(name .. "/.make.lua") then
      sh("git submodule update --init")
      return
    end
  end
end

local function each(recipe_for)
  checked_out()
  for _, name in ipairs(MEMBERS) do
    local recipe = recipe_for(name)
    print(oslo.ui.title(("%s · make %s"):format(name, recipe)))
    sh(("cd %s && oslo make %s"):format(name, recipe))
  end
end

make.recipe{ name = "build", desc = "every binary",
             run = function() each(function(name) return BUILD[name] or "build" end) end }
make.alias("b", "build")

-- `--args` as the words a shell would split it into, quotes honoured, handed over without one.
local function words(line)
  local out, word, quote, started = {}, {}, nil, false
  for ch in (line or ""):gmatch(".") do
    if quote then
      if ch == quote then quote = nil else word[#word + 1] = ch end
    elseif ch == "'" or ch == '"' then
      quote, started = ch, true
    elseif ch:match("%s") then
      if started then out[#out + 1], word, started = table.concat(word), {}, false end
    else
      word[#word + 1], started = ch, true
    end
  end
  assert(not quote, "--args has a quote that is never closed")
  if started then out[#out + 1] = table.concat(word) end
  return out
end

make.recipe{
  name = "run",
  desc = "magi, with the other three fresh from their builds rather than installed",
  deps = { "build" },
  params = { { "--args", desc = "what to hand magi: a prompt, or a subcommand such as doctor" } },
  run = function(a)
    local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
    local argv = { bash, "scripts/run-family.sh" }
    for _, word in ipairs(words(a.args)) do argv[#argv + 1] = word end
    assert(oslo.run(argv).ok, "magi exited with a failure")
  end,
}
make.alias("r", "run")

make.recipe{ name = "install", desc = "every binary to ~/.local/bin, and each configuration",
             run = function() each(function() return "install" end) end }
make.alias("i", "install")

make.recipe{ name = "test", desc = "every suite",
             run = function() each(function() return "test" end) end }
make.alias("t", "test")

make.recipe{ name = "test-events", desc = "all four independent local event contracts",
             run = function() each(function() return "test-events" end) end }

make.recipe{ name = "test-cache-contract", desc = "actual Magi/Melchior cache request capture with selected family binaries",
             run = function()
               local ok, root = captured("pwd -P")
               assert(ok and root ~= "", "cannot resolve the family runner")
               assert(oslo.run{ "sh", "-c", 'cd magi && exec oslo make test-cache-contract --runner="$1"',
                                "cache-contract", root .. "/scripts/acceptance.sh" }.ok,
                      "actual family cache contract failed")
             end }

local function family_script(script, mode)
  local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
  local args
  if script == "scripts/family.sh" or script == "scripts/acceptance.sh" or script == "scripts/tests/family.sh" or script == "scripts/acceptance-native-mcp.sh" then
    args = { bash, "scripts/test-context.sh", bash, script }
  else
    args = { bash, script }
  end
  if mode then args[#args + 1] = mode end
  assert(oslo.run(args).ok, script .. " failed")
end

make.recipe{ name = "test-eval-runner", desc = "evaluation manifest contracts and refusal fixtures",
             deps = { "test-eval-input", "test-eval-json", "test-eval-provider", "test-eval-provider-release", "test-eval-world", "test-eval-deadline", "test-eval-provider-world", "test-eval-bindings", "test-eval-pack", "test-eval-aggregate", "test-eval-sample-assembly", "test-eval-metrics", "test-eval-usage", "test-eval-request-bytes", "test-eval-prefix", "test-eval-client-attempts", "test-eval-reconcile-usage", "test-eval-ledger-usage", "test-eval-ipc-record", "test-eval-ipc-pack", "test-eval-ipc-usage" },
             run = function()
               family_script("scripts/tests/evaluation.sh")
               family_script("scripts/tests/evaluation-artifact.sh")
               family_script("scripts/tests/evaluation-report.sh")
             end }

make.recipe{ name = "test-eval-report", desc = "versioned multi-model report and retained evidence contracts",
             deps = { "build-eval-input" },
             run = function() family_script("scripts/tests/evaluation-report.sh") end }

make.recipe{ name = "test-eval-usage", desc = "scoped transcript usage without recounting restored history or guessing missing counters",
             deps = { "build-eval-input" },
             params = { { "--retained", desc = "optional retained transcript-usage receipt for the escaped large-journal regression" } },
             run = function(a) family_script("scripts/tests/evaluation-usage.sh", a.retained) end }

make.recipe{ name = "test-eval-json", desc = "bounded native JSON grammar, exact counters, duplicate keys and confined file inputs",
             deps = { "build-eval-input" },
             run = function() family_script("scripts/tests/evaluation-json.sh") end }

make.recipe{ name = "test-eval-request-bytes", desc = "exact captured body bytes without reserializing payloads or inferring client attempts",
             deps = { "build-eval-input" },
             params = { { "--execution", desc = "optional retained execution test receipt; no workers are started" } },
             run = function(a) family_script("scripts/tests/evaluation-request-bytes.sh", a.execution) end }

make.recipe{ name = "test-eval-prefix", desc = "normalized prompt octets without inferring cached tokens or savings",
             deps = { "build-eval-input" },
             run = function() family_script("scripts/tests/evaluation-prefix.sh") end }

make.recipe{ name = "test-eval-client-attempts", desc = "protected pre-send admission ledger validation",
             deps = { "build-eval-input" },
             run = function() family_script("scripts/tests/evaluation-client-attempts.sh") end }

make.recipe{ name = "test-eval-sample-assembly", desc = "sample status assembly without inventing missing measurements",
             run = function() family_script("scripts/tests/evaluation-sample-assembly.sh") end }

make.recipe{ name = "eval-offline", desc = "run the declared alternating offline samples and retain every result",
             deps = { "build-eval-input", "build-eval-world" },
             params = { { "--bindings", desc = "reviewed frozen binding root" }, { "--sha256", desc = "binding digest" } },
             run = function(a)
               assert(a.bindings and a.sha256, "bindings and sha256 required")
               local bash = os.getenv("NERV_BASH") or "/bin/bash"
               assert(oslo.run{ bash, "scripts/evaluate.sh", a.bindings, a.sha256 }.ok,
                      "offline evaluation did not pass; inspect retained suite report")
             end }

make.recipe{ name = "test-eval-suite", desc = "offline coordinator ordering, retained failures and cancellation",
             deps = { "build-eval-input", "build-eval-world" },
             params = { { "--bindings", desc = "reviewed frozen binding root" }, { "--sha256", desc = "binding digest" } },
             run = function(a)
               assert(a.bindings and a.sha256, "bindings and sha256 required")
               local bash = os.getenv("NERV_BASH") or "/bin/bash"
               assert(oslo.run{ bash, "scripts/tests/evaluation-suite.sh", a.bindings, a.sha256 }.ok,
                      "offline coordinator tests failed")
             end }

make.recipe{ name = "eval-sample", desc = "produce one supervised sample with bounded retained evidence",
             deps = { "build-eval-input", "build-eval-world" },
             params = { { "--bindings", desc = "frozen binding root" }, { "--sha256", desc = "binding digest" },
                        { "--id", desc = "scheduled task:variant:sample id" }, { "--collection", desc = "32-hex collection identity" } },
             run = function(a)
               assert(a.bindings and a.sha256 and a.id and a.collection, "bindings, sha256, id and collection are required")
               local bash = os.getenv("NERV_BASH") or "/bin/bash"
               assert(oslo.run{ bash, "scripts/evaluation/run-sample.sh", a.bindings, a.sha256, a.id, a.collection }.ok,
                      "sample did not pass; inspect the retained sample result")
             end }

make.recipe{ name = "test-eval-sample", desc = "retained sample publication, cap failures and outer deadlines",
             deps = { "build-eval-input", "build-eval-world", "test-eval-sample-assembly" },
             params = { { "--bindings", desc = "reviewed frozen binding root" }, { "--sha256", desc = "binding digest" } },
             run = function(a)
               assert(a.bindings and a.sha256, "bindings and sha256 required")
               local bash = os.getenv("NERV_BASH") or "/bin/bash"
               assert(oslo.run{ bash, "scripts/tests/evaluation-sample.sh", a.bindings, a.sha256 }.ok,
                      "produced sample tests failed")
             end }

make.recipe{ name = "eval-reconcile-usage", desc = "reconcile retained synthetic model usage with durable history and helper calls",
             deps = { "build-eval-input" },
             params = { { "--task", desc = "reviewed workload id" }, { "--root", desc = "retained execution receipt" },
                        { "--world", desc = "relative world receipt directory" } },
             run = function(a)
               assert(a.task and a.root and a.world, "task, root and world are required")
               local bash = os.getenv("NERV_BASH") or "/bin/bash"
               assert(oslo.run{ bash, "scripts/evaluation/reconcile-usage.sh", a.task, a.root, a.world }.ok,
                      "synthetic usage reconciliation failed")
             end }

make.recipe{ name = "test-eval-reconcile-usage", desc = "synthetic usage attribution and refusal contracts",
             deps = { "test-eval-activity" },
             run = function() family_script("scripts/tests/evaluation-reconcile-usage.sh") end }

make.recipe{ name = "eval-activity", desc = "observe retained execution activity without assigning report counter definitions",
             deps = { "build-eval-input" },
             params = { { "--task", desc = "reviewed workload id" }, { "--root", desc = "retained execution receipt" },
                        { "--world", desc = "relative world receipt directory" } },
             run = function(a)
               assert(a.task and a.root and a.world, "task, root and world are required")
               local bash = os.getenv("NERV_BASH") or "/bin/bash"
               assert(oslo.run{ bash, "scripts/evaluation/activity.sh", a.task, a.root, a.world }.ok,
                      "activity observation failed")
             end }

make.recipe{ name = "test-eval-activity", desc = "execution activity observations and refusal contracts",
             run = function() family_script("scripts/tests/evaluation-activity.sh") end }

make.recipe{ name = "test-eval-metrics", desc = "proposed counter mapping, independent of report activation",
             deps = { "build-eval-input" },
             params = { { "--execution", desc = "optional retained execution receipt; no workers are started" } },
             run = function(a) family_script("scripts/tests/evaluation-metrics.sh", a.execution) end }

make.recipe{ name = "eval-prefix", desc = "measure adjacent normalized prompt prefixes in retained captures",
             deps = { "build-eval-input" },
             params = { { "--root", desc = "retained provider evidence root" } },
             run = function(a)
               assert(a.root, "evidence root is required")
               family_script("scripts/evaluation/normalized-prefix.sh", a.root)
             end }

make.recipe{ name = "test-eval-ledger-usage", desc = "captured run charges without recounting child or resumed-session ledgers",
             deps = { "build-eval-input" },
             params = { { "--execution", desc = "optional retained execution test receipt; no workers are started" } },
             run = function(a) family_script("scripts/tests/evaluation-ledger-usage.sh", a.execution) end }

make.recipe{ name = "eval-request-bytes", desc = "measure retained provider body captures without starting workers",
             deps = { "build-eval-input" },
             params = { { "--root", desc = "retained provider evidence root" } },
             run = function(a)
               assert(a.root, "evidence root is required")
               family_script("scripts/evaluation/request-bytes.sh", a.root)
             end }

make.recipe{ name = "test-eval-aggregate", desc = "ordered result collection without discarding failures or inventing missing measurements",
             deps = { "build-eval-input" },
             run = function() family_script("scripts/tests/evaluation-aggregate.sh") end }

make.recipe{ name = "eval-aggregate", desc = "validate and collect retained sample envelopes without starting workers",
             deps = { "build-eval-input" },
             params = {
               { "--root", desc = "trusted result root" },
               { "--index", desc = "relative index in execution order" },
               { "--bindings", desc = "frozen bindings root" },
               { "--sha256", desc = "frozen bindings.json identity" },
             },
             run = function(a)
               assert(a.root and a.index and a.bindings and a.sha256, "all collection parameters are required")
               local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
               assert(oslo.run{ bash, "scripts/evaluation/aggregate.sh", a.root, a.index, a.bindings, a.sha256 }.ok,
                      "evaluation collection or a collected sample failed")
             end }

make.recipe{ name = "test-eval-pack", desc = "lossless raw evidence archives within the remaining sample byte budget",
             deps = { "build-eval-input" },
             run = function() family_script("scripts/tests/evaluation-pack.sh") end }

make.recipe{ name = "eval-pack-raw", desc = "package a bounded raw evidence tree without claiming sample success",
             deps = { "build-eval-input" },
             params = {
               { "--root", desc = "trusted input root" },
               { "--tree", desc = "relative raw tree" },
               { "--reserved", desc = "bytes occupied by other sample evidence" },
             },
             run = function(a)
               assert(a.root and a.tree and a.reserved, "root, tree and reserved bytes are required")
               local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
               assert(oslo.run{ bash, "scripts/evaluation/pack-raw.sh", a.root, a.tree, tostring(a.reserved) }.ok,
                      "raw evidence packaging failed")
             end }

make.recipe{ name = "test-eval-bindings", desc = "frozen workload identities and exact effective configuration checks",
             deps = { "build-eval-world" },
             run = function() family_script("scripts/tests/evaluation-bindings.sh") end }

make.recipe{ name = "eval-check-config", desc = "compare effective workload configuration with its frozen template",
             deps = { "build-eval-input" },
             params = {
               { "--bindings", desc = "frozen binding receipt directory" },
               { "--sha256", desc = "frozen bindings.json digest" },
               { "--task", desc = "reviewed workload id" },
               { "--variant", desc = "baseline or candidate" },
               { "--world", desc = "isolated world receipt directory" },
             },
             run = function(a)
               assert(a.bindings and a.sha256 and a.task and a.variant and a.world, "all configuration check parameters are required")
               local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
               assert(oslo.run{ bash, "scripts/evaluation/check-config.sh", a.bindings, a.sha256, a.task, a.variant, a.world }.ok,
                      "effective evaluation configuration differs")
             end }

make.recipe{ name = "eval-bindings", desc = "freeze paired offline inputs and configuration without starting workers",
             deps = { "build-eval-world" },
             params = {
               { "--root", desc = "trusted input root, default current directory" },
               { "--manifest", desc = "relative manifest path" },
               { "--baseline", desc = "relative retained baseline descriptor" },
               { "--baseline-sha", desc = "approved baseline identity" },
               { "--candidate", desc = "relative candidate descriptor" },
               { "--candidate-sha", desc = "selected candidate identity" },
               { "--provider", desc = "relative release provider path" },
               { "--provider-sha", desc = "provider binary identity" },
               { "--grammar", desc = "relative Rust grammar path" },
               { "--grammar-sha", desc = "Rust grammar identity" },
               { "--observer", desc = "optional separately captured event observer binary" },
             },
             run = function(a)
               for _, key in ipairs({ "manifest", "baseline", "baseline_sha", "candidate", "candidate_sha", "provider", "provider_sha", "grammar", "grammar_sha" }) do
                 assert(a[key], key .. " is required")
               end
               local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
               local args = { bash, "scripts/evaluation/bindings.sh", a.root or ".", a.manifest, a.baseline, a.baseline_sha,
                              a.candidate, a.candidate_sha, a.provider, a.provider_sha, a.grammar, a.grammar_sha }
               if a.observer then args[#args + 1] = a.observer end
               assert(oslo.run(args).ok,
                      "evaluation frozen bindings failed")
             end }

make.recipe{ name = "eval-workload", desc = "execute and independently check one frozen workload without claiming complete measurements",
             deps = { "build-eval-world" },
             params = {
               { "--bindings", desc = "frozen binding receipt directory" },
               { "--sha256", desc = "frozen bindings.json digest" },
               { "--task", desc = "reviewed workload id" },
               { "--variant", desc = "baseline or candidate" },
             },
             run = function(a)
               assert(a.bindings and a.sha256 and a.task and a.variant, "all workload parameters are required")
               local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
               assert(oslo.run{ bash, "scripts/evaluation/run-workload.sh", a.bindings, a.sha256, a.task, a.variant }.ok,
                      "frozen evaluation workload failed")
             end }

make.recipe{ name = "test-eval-execution", desc = "frozen workload execution, identity refusals, limits and cancellation",
             deps = { "build-eval-world" },
             params = {
               { "--bindings", desc = "frozen binding receipt directory" },
               { "--sha256", desc = "frozen bindings.json digest" },
             },
             run = function(a)
               assert(a.bindings and a.sha256, "bindings and sha256 are required")
               local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
               assert(oslo.run{ bash, "scripts/tests/evaluation-execution.sh", a.bindings, a.sha256 }.ok,
                      "frozen evaluation execution tests failed")
             end }

make.recipe{ name = "test-eval-provider", desc = "offline provider cumulative admission and process lifecycle",
             run = function()
               sh("cd melchior && oslo make test-fake-provider && oslo make build-fake-provider")
               family_script("scripts/tests/evaluation-provider.sh")
             end }

make.recipe{ name = "test-eval-provider-release", desc = "bounded release-provider capture and real process checks",
             deps = { "build-eval-input" },
             run = function()
               sh("cd melchior && oslo make build-fake-provider-release")
               family_script("scripts/tests/evaluation-provider.sh", "release")
             end }

make.recipe{ name = "test-eval-provider-world", desc = "selected provider handshake, caps and lifecycle inside an isolated world",
             deps = { "build-eval-world" },
             run = function()
               sh("cd melchior && oslo make build-fake-provider-release")
               family_script("scripts/tests/evaluation-provider-world.sh")
             end }

make.recipe{ name = "test-eval-family-world", desc = "explicit frozen family native-read and durable replay inside an isolated world",
             deps = { "build-eval-world" },
             params = {
               { "--descriptor", desc = "relative frozen artifact descriptor path" },
               { "--sha256", desc = "approved artifact identity" },
               { "--variant", desc = "baseline or candidate" },
             },
             run = function(a)
               assert(a.descriptor and a.sha256 and a.variant, "descriptor, sha256 and variant are required")
               sh("cd melchior && oslo make build-fake-provider-release")
               local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
               assert(oslo.run{ bash, "scripts/tests/evaluation-family-world.sh", a.descriptor, a.sha256, a.variant }.ok,
                      "evaluation family world tests failed")
             end }

make.recipe{ name = "test-eval-event-observer", desc = "paired captured observer inside the isolated native evaluation world",
             deps = { "build-eval-world" },
             params = {
               { "--descriptor", desc = "relative selected family descriptor" },
               { "--sha256", desc = "selected family identity" },
               { "--observer", desc = "relative separately captured observer binary" },
               { "--observer-sha256", desc = "captured observer identity" },
             },
             run = function(a)
               assert(a.descriptor and a.sha256 and a.observer and a.observer_sha256, "family and observer identities are required")
               sh("cd melchior && oslo make build-fake-provider-release")
               family_script("scripts/tests/evaluation.sh")
               local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
               assert(oslo.run{ bash, "scripts/tests/evaluation-event-observer.sh", a.descriptor, a.sha256, a.observer, a.observer_sha256 }.ok,
                      "isolated event observer verification failed")
             end }

make.recipe{ name = "test-eval-mutations", desc = "actual bug-fix and complete large-file mutation workloads",
             deps = { "build-eval-world" },
             params = {
               { "--descriptor", desc = "relative frozen artifact descriptor path" },
               { "--sha256", desc = "approved artifact identity" },
               { "--variant", desc = "baseline or candidate" },
             },
             run = function(a)
               assert(a.descriptor and a.sha256 and a.variant, "descriptor, sha256 and variant are required")
               sh("cd melchior && oslo make build-fake-provider-release")
               local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
               assert(oslo.run{ bash, "scripts/tests/evaluation-mutations.sh", a.descriptor, a.sha256, a.variant }.ok,
                      "evaluation mutation tests failed")
             end }

make.recipe{ name = "test-eval-index", desc = "real parser, targeted read and selected-symbol edit workload",
             deps = { "build-eval-world" },
             params = {
               { "--descriptor", desc = "relative frozen artifact descriptor path" },
               { "--sha256", desc = "approved artifact identity" },
               { "--variant", desc = "baseline or candidate" },
               { "--grammar", desc = "relative retained Rust grammar binary path" },
               { "--grammar-sha256", desc = "selected Rust grammar digest" },
             },
             run = function(a)
               assert(a.descriptor and a.sha256 and a.variant and a.grammar and a.grammar_sha256, "explicit artifact and grammar selection required")
               sh("cd melchior && oslo make build-fake-provider-release")
               local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
               assert(oslo.run{ bash, "scripts/tests/evaluation-mutations.sh", a.descriptor, a.sha256, a.variant,
                                a.grammar, a.grammar_sha256 }.ok, "evaluation index tests failed")
             end }

make.recipe{ name = "test-eval-concurrent", desc = "concurrent same-revision disjoint edits through two real sessions",
             deps = { "build-eval-world" },
             params = {
               { "--descriptor", desc = "relative frozen artifact descriptor path" },
               { "--sha256", desc = "approved artifact identity" },
               { "--variant", desc = "baseline or candidate" },
             },
             run = function(a)
               assert(a.descriptor and a.sha256 and a.variant, "explicit artifact selection required")
               sh("cd melchior && oslo make build-fake-provider-release")
               local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
               assert(oslo.run{ bash, "scripts/tests/evaluation-concurrent.sh", a.descriptor, a.sha256, a.variant }.ok,
                      "evaluation concurrent tests failed")
             end }

make.recipe{ name = "test-eval-live-history", desc = "selected live writer and independent CLI replay visibility",
             deps = { "build-eval-world" },
             params = {
               { "--descriptor", desc = "relative frozen artifact descriptor path" },
               { "--sha256", desc = "selected artifact identity" },
               { "--variant", desc = "baseline or candidate" },
             },
             run = function(a)
               assert(a.descriptor and a.sha256 and a.variant, "explicit artifact selection required")
               sh("cd melchior && oslo make build-fake-provider-release")
               local bash = os.getenv("NERV_BASH") or "/bin/bash"
               assert(oslo.run{ bash, "scripts/tests/evaluation-live-history.sh", a.descriptor, a.sha256, a.variant }.ok,
                      "selected live history test failed")
             end }

make.recipe{ name = "test-eval-accounting", desc = "both usage dialects and exact persisted synthetic charges",
             deps = { "build-eval-world" },
             params = {
               { "--descriptor", desc = "relative frozen artifact descriptor path" },
               { "--sha256", desc = "approved artifact identity" },
               { "--variant", desc = "baseline or candidate" },
             },
             run = function(a)
               assert(a.descriptor and a.sha256 and a.variant, "explicit artifact selection required")
               sh("cd melchior && oslo make build-fake-provider-release")
               local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
               assert(oslo.run{ bash, "scripts/tests/evaluation-accounting.sh", a.descriptor, a.sha256, a.variant }.ok,
                      "evaluation accounting tests failed")
             end }

make.recipe{ name = "test-eval-resume", desc = "selected history without repeated mutations or restored charges",
             deps = { "build-eval-world" },
             params = {
               { "--descriptor", desc = "relative frozen artifact descriptor path" },
               { "--sha256", desc = "approved artifact identity" },
               { "--variant", desc = "baseline or candidate" },
               { "--legacy", desc = "optional retained Melchior for creating pre-upgrade histories" },
               { "--legacy-sha", desc = "required digest of the retained legacy Melchior" },
             },
             run = function(a)
               assert(a.descriptor and a.sha256 and a.variant, "explicit artifact selection required")
               sh("cd melchior && oslo make build-fake-provider-release")
               local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
               local args = { bash, "scripts/tests/evaluation-resume.sh", a.descriptor, a.sha256, a.variant }
               if a.legacy or a.legacy_sha then
                 assert(a.legacy and a.legacy_sha and a.variant == "candidate", "legacy resume requires a pinned binary and candidate")
                 args[#args + 1] = a.legacy
                 args[#args + 1] = a.legacy_sha
               end
               assert(oslo.run(args).ok,
                      "evaluation resume tests failed")
             end }

make.recipe{ name = "test-eval-pressure", desc = "real input reduction with required context and paired history",
             deps = { "build-eval-world" },
             params = {
               { "--descriptor", desc = "relative frozen artifact descriptor path" },
               { "--sha256", desc = "approved artifact identity" },
               { "--variant", desc = "baseline or candidate" },
             },
             run = function(a)
               assert(a.descriptor and a.sha256 and a.variant, "explicit artifact selection required")
               sh("cd melchior && oslo make build-fake-provider-release")
               local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
               assert(oslo.run{ bash, "scripts/tests/evaluation-pressure.sh", a.descriptor, a.sha256, a.variant }.ok,
                      "evaluation pressure tests failed")
             end }

make.recipe{ name = "test-eval-child", desc = "actual child observations, shared charges and report ownership",
             deps = { "build-eval-world" },
             params = {
               { "--descriptor", desc = "relative frozen artifact descriptor path" },
               { "--sha256", desc = "approved artifact identity" },
               { "--variant", desc = "baseline or candidate" },
             },
             run = function(a)
               assert(a.descriptor and a.sha256 and a.variant, "explicit artifact selection required")
               sh("cd melchior && oslo make build-fake-provider-release")
               local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
               assert(oslo.run{ bash, "scripts/tests/evaluation-child.sh", a.descriptor, a.sha256, a.variant }.ok,
                      "evaluation child tests failed")
             end }

make.recipe{ name = "test-eval-controls", desc = "actual repeated-call guard and output-only recovery workloads",
             deps = { "build-eval-world" },
             params = {
               { "--descriptor", desc = "relative frozen artifact descriptor path" },
               { "--sha256", desc = "approved artifact identity" },
               { "--variant", desc = "baseline or candidate" },
             },
             run = function(a)
               assert(a.descriptor and a.sha256 and a.variant, "descriptor, sha256 and variant are required")
               sh("cd melchior && oslo make build-fake-provider-release")
               local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
               assert(oslo.run{ bash, "scripts/tests/evaluation-controls.sh", a.descriptor, a.sha256, a.variant }.ok,
                      "evaluation control tests failed")
             end }

make.recipe{ name = "build-eval-world", desc = "isolated evaluation world supervisor and refusal probes",
             deps = { "build-eval-input" },
             run = function()
               for _, source in ipairs({ "world", "world_probe" }) do
                 local binary = source == "world" and "eval-world" or "eval-world-probe"
                 assert(oslo.run{ "rustc", "--edition=2024", "-Dwarnings", "-O", "scripts/evaluation/" .. source .. ".rs",
                                  "-o", "target/evaluation/bin/" .. binary }.ok, "evaluation world build failed")
               end
             end }

make.recipe{ name = "test-eval-ipc-record", desc = "bounded model IPC capture, concurrency, failure and cancellation",
             deps = { "build-eval-world" },
             run = function() family_script("scripts/tests/evaluation-ipc-record.sh") end }

make.recipe{ name = "test-eval-ipc-bootstrap", desc = "bounded event bootstrap relay and descriptor ownership",
             deps = { "build-eval-world" },
             run = function()
               assert(oslo.run{ "rustfmt", "--edition", "2024", "--check", "scripts/evaluation/world.rs" }.ok,
                      "evaluation world format failed")
               assert(oslo.run{ "rustc", "--edition=2024", "-Dwarnings", "--test", "scripts/evaluation/world.rs",
                                "-o", "target/evaluation/bin/eval-world-tests" }.ok, "evaluation world test build failed")
               assert(oslo.run{ "target/evaluation/bin/eval-world-tests", "ipc_record::bootstrap::" }.ok,
                      "evaluation bootstrap tests failed")
             end }

make.recipe{ name = "test-eval-ipc-native", desc = "selected native model capture with event forwarding",
             deps = { "test-eval-ipc-bootstrap" },
             run = function()
               assert(os.getenv("MELCHIOR_TEST_BINARY"), "explicit MELCHIOR_TEST_BINARY required")
               assert(oslo.run{ "target/evaluation/bin/eval-world-tests", "--ignored", "--exact",
                                "ipc_record::bootstrap::tests::native::selected_model_capture_preserves_bootstrap", "--nocapture" }.ok,
                      "selected native IPC bootstrap test failed")
             end }

make.recipe{ name = "test-eval-ipc-helper", desc = "record retained background and tool-requested helper model streams",
             deps = { "build-eval-world" },
             params = { { "--descriptor", desc = "retained baseline descriptor" }, { "--sha256", desc = "approved baseline identity" } },
             run = function(a)
               assert(a.descriptor and a.sha256, "explicit retained baseline required")
               sh("cd melchior && oslo make build-fake-provider-release")
               local bash = os.getenv("NERV_BASH") or "bash"
               assert(oslo.run{ bash, "scripts/tests/evaluation-ipc-helper.sh", a.descriptor, a.sha256 }.ok, "retained helper recorder tests failed")
             end }

make.recipe{ name = "test-eval-ipc-pack", desc = "lossless bounded model IPC archives and refusal cases",
             deps = { "build-eval-world" },
             run = function() family_script("scripts/tests/evaluation-ipc-pack.sh") end }

make.recipe{ name = "test-eval-ipc-usage", desc = "exact cumulative model IPC usage without guessing incomplete counters",
             deps = { "build-eval-input" },
             params = { { "--retained", desc = "optional retained helper test receipt; no workers" } },
             run = function(a) family_script("scripts/tests/evaluation-ipc-usage.sh", a.retained) end }

make.recipe{ name = "eval-ipc-usage", desc = "extract scoped usage from retained model IPC files",
             deps = { "build-eval-input" },
             params = { { "--root", desc = "retained input root" }, { "--capture", desc = "relative recorder directory" } },
             run = function(a)
               assert(a.root and a.capture, "input root and relative capture required")
               local bash = os.getenv("NERV_BASH") or "bash"
               assert(oslo.run{ bash, "scripts/evaluation/ipc-usage.sh", a.root, a.capture }.ok, "IPC usage extraction failed")
             end }

make.recipe{ name = "test-eval-admission", desc = "retained runtime client-attempt admission and fail-closed endpoint callbacks",
             deps = { "build-eval-world" },
             params = {
               { "--descriptor", desc = "relative frozen artifact descriptor path" },
               { "--sha256", desc = "approved artifact identity" },
               { "--variant", desc = "baseline or candidate" },
             },
             run = function(a)
               assert(a.descriptor and a.sha256 and a.variant, "explicit artifact selection required")
               sh("cd melchior && oslo make build-fake-provider-release")
               local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
               assert(oslo.run{ bash, "scripts/tests/evaluation-admission.sh", a.descriptor, a.sha256, a.variant }.ok,
                      "client attempt admission tests failed")
             end }

make.recipe{ name = "fmt-eval-world", desc = "format the evaluation world supervisor and probes",
             run = function()
               assert(oslo.run{ "rustfmt", "--edition", "2024", "scripts/evaluation/world.rs", "scripts/evaluation/world_probe.rs" }.ok,
                      "evaluation world format failed")
             end }

make.recipe{ name = "test-eval-world", desc = "isolated world, deadline and leaked-child refusal cases",
             deps = { "build-eval-world" },
             run = function()
               assert(oslo.run{ "rustfmt", "--edition", "2024", "--check", "scripts/evaluation/world.rs", "scripts/evaluation/world_probe.rs" }.ok,
                      "evaluation world format failed")
               assert(oslo.run{ "rustc", "--edition=2024", "-Dwarnings", "--test", "scripts/evaluation/world.rs",
                                "-o", "target/evaluation/bin/eval-world-tests" }.ok, "evaluation world test build failed")
               assert(oslo.run{ "target/evaluation/bin/eval-world-tests" }.ok, "evaluation world tests failed")
               family_script("scripts/tests/evaluation-world.sh")
             end }

make.recipe{ name = "test-eval-deadline", desc = "whole controller deadline, adopted process cleanup and cancellation",
             deps = { "build-eval-world" },
             run = function() family_script("scripts/tests/evaluation-deadline.sh") end }

make.recipe{ name = "test-eval-artifact", desc = "explicit evaluation artifact selection and feature refusal checks",
             deps = { "build-eval-input" },
             run = function()
               family_script("scripts/tests/evaluation-artifact.sh")
             end }

make.recipe{ name = "eval-artifact", desc = "snapshot an explicit offline artifact selection without executing it",
             deps = { "build-eval-input" },
             params = {
               { "--root", desc = "trusted selection root, default current directory" },
               { "--descriptor", desc = "relative artifact descriptor path" },
               { "--manifest", desc = "relative evaluation manifest path" },
               { "--variant", desc = "baseline or candidate" },
               { "--source-mode", desc = "retained (default) or explicit build-output capture" },
             },
             run = function(a)
               assert(a.descriptor and a.manifest and a.variant, "descriptor, manifest and variant are required")
               local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
               assert(oslo.run{ bash, "scripts/evaluation/artifact.sh", a.root or ".", a.descriptor, a.manifest, a.variant, a.source_mode or "retained" }.ok,
                      "evaluation artifact preflight failed")
             end }

make.recipe{ name = "build-eval-input", desc = "bounded offline evaluation input snapshot helper",
             run = function()
               sh("mkdir -p target/evaluation/bin")
               assert(oslo.run{ "rustc", "--edition=2024", "-Dwarnings", "-O", "scripts/evaluation/input.rs", "-o", "target/evaluation/bin/eval-input" }.ok,
                      "evaluation input build failed")
             end }

make.recipe{ name = "test-eval-input", desc = "descriptor-confined evaluation input fixtures",
             deps = { "build-eval-input" },
             run = function()
               assert(oslo.run{ "rustfmt", "--edition", "2024", "--check", "scripts/evaluation/input.rs" }.ok, "evaluation input format failed")
               assert(oslo.run{ "rustc", "--edition=2024", "-Dwarnings", "--test", "scripts/evaluation/input.rs", "-o", "target/evaluation/bin/eval-input-tests" }.ok,
                      "evaluation input test build failed")
               assert(oslo.run{ "target/evaluation/bin/eval-input-tests" }.ok, "evaluation input tests failed")
             end }

make.recipe{ name = "fmt-eval-runner", desc = "format evaluation input helper",
             run = function()
               assert(oslo.run{ "rustfmt", "--edition", "2024", "scripts/evaluation/input.rs" }.ok, "evaluation input format failed")
             end }

make.recipe{ name = "eval-preflight", desc = "snapshot and validate offline evaluation inputs without workers",
             deps = { "build-eval-input" },
             params = { { "--manifest", desc = "reviewed relative manifest path" } },
             run = function(a)
               family_script("scripts/evaluation/preflight.sh", a.manifest or "manifests/offline.json")
             end }

-- Opt-in, and never a dependency of `verify` or CI: each needs a fixture or a Blender of its own.
make.recipe{
  name = "test-mcp-blender",
  desc = "read-only Magi/Casper MCP round-trip against an existing Blender addon",
  deps = { "build" },
  run = function()
    sh("cd melchior && oslo make build-fake-provider")
    family_script("scripts/acceptance-mcp.sh")
  end,
}

make.recipe{
  name = "test-images",
  desc = "native user, read, MCP and resumed image delivery to a local provider fixture",
  deps = { "build" },
  run = function()
    sh("cd melchior && oslo make build-fake-provider")
    family_script("scripts/acceptance-images.sh")
  end,
}

make.recipe{
  name = "test-images-blender",
  desc = "image delivery including a read-only screenshot from an existing Blender addon",
  deps = { "build" },
  run = function()
    sh("cd melchior && oslo make build-fake-provider")
    family_script("scripts/acceptance-images.sh", "--blender")
  end,
}

make.recipe{
  name = "test-images-openrouter",
  desc = "opt-in capped visual interpretation through Magi, tools and resume",
  deps = { "build" },
  run = function()
    sh("cd melchior && oslo make build-metered-proxy")
    family_script("scripts/acceptance-vision-live.sh")
  end,
}

make.recipe{ name = "test-receipts", desc = "baseline receipt validation failure fixtures",
             run = function() family_script("scripts/tests/receipt.sh") end }

make.recipe{ name = "test-tool-assets", desc = "selected shipped declaration digests and rejection fixtures",
             run = function() family_script("scripts/tests/tool-assets.sh") end }

make.recipe{ name = "test-context", desc = "private registry namespace and lifecycle fixtures",
             run = function() family_script("scripts/tests/test-context.sh") end }

make.recipe{ name = "prepare-advisories", desc = "prepare pinned audit inputs in workspace-only storage",
             run = function() family_script("scripts/prepare-advisories.sh") end }

make.recipe{ name = "test-launch-selection", desc = "authoritative launch selection and argv fixtures",
             run = function() family_script("scripts/tests/launch-selection.sh") end }

make.recipe{ name = "test-advisory-inputs", desc = "workspace-only pinned advisory input fixtures",
             run = function() family_script("scripts/tests/advisories.sh") end }

make.recipe{ name = "baseline", desc = "record the offline roadmap baseline and command outcomes",
             run = function() family_script("scripts/baseline.sh") end }

make.recipe{ name = "test-family-runner", desc = "family runner failure and isolation fixtures",
             deps = { "test-receipts", "test-launch-selection", "test-advisory-inputs", "test-tool-assets", "test-context", "test-preserved-binaries" },
             run = function() family_script("scripts/tests/family.sh") end }

make.recipe{ name = "test-family-cleanup", desc = "actual TERM-resistant family leak cleanup",
             run = function() family_script("scripts/tests/family.sh", "--leak-only") end }

make.recipe{ name = "test-family-selection", desc = "preserved selected artifacts and integrity refusal",
             deps = { "test-preserved-binaries" },
             run = function() family_script("scripts/tests/family.sh", "--selection-only") end }

make.recipe{ name = "test-preserved-binaries", desc = "selected executable snapshot and integrity contract",
             run = function() family_script("scripts/tests/preserve-binary.sh") end }

make.recipe{ name = "test-native-mcp-selected", desc = "nested native MCP through the selected Casper release",
             run = function()
               sh("cd casper && oslo make build")
               family_script("scripts/acceptance-native-mcp.sh")
             end }

make.recipe{ name = "test-family", desc = "required integration tests against this family",
             deps = { "test-family-runner" },
             run = function() family_script("scripts/family.sh", "test") end }

make.recipe{ name = "verify", desc = "member gates and required family integration",
             deps = { "test-family-runner" },
             run = function() family_script("scripts/family.sh", "verify") end }

make.recipe{ name = "acceptance", desc = "deterministic reliability scenarios, no credentials",
             run = function() family_script("scripts/acceptance.sh") end }

-- Opt-in and never a dependency of anything: every choice is the caller's, by name, each run.
make.recipe{ name = "acceptance-live", desc = "live acceptance; needs NERV_LIVE_MODEL, NERV_LIVE_CAP_USD, NERV_LIVE_SEND=yes",
             run = function()
               local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
               assert(oslo.run({ bash, "scripts/acceptance-live.sh",
                 "--provider", os.getenv("NERV_LIVE_PROVIDER") or "openrouter",
                 "--model", os.getenv("NERV_LIVE_MODEL") or "",
                 "--cap-usd", os.getenv("NERV_LIVE_CAP_USD") or "",
                 "--small-model", os.getenv("NERV_LIVE_SMALL_MODEL") or "",
                 "--judge-model", os.getenv("NERV_LIVE_JUDGE_MODEL") or "",
                 "--send-synthetic", os.getenv("NERV_LIVE_SEND") or "no" }).ok,
                 "scripts/acceptance-live.sh failed")
             end }

local STATUS = [[
for name in MEMBERS; do
  git -C "$name" fetch -q origin 2>/dev/null
  branch=$(git -C "$name" branch --show-current); [ -n "$branch" ] || branch=detached
  printf '%-10s %-9s ahead %-3s behind %-3s changed %s\n' "$name" "$branch" \
    "$(git -C "$name" rev-list --count '@{u}..HEAD' 2>/dev/null || echo -)" \
    "$(git -C "$name" rev-list --count 'HEAD..@{u}' 2>/dev/null || echo -)" \
    "$(git -C "$name" status --porcelain | wc -l)"
done
]]

make.recipe{ name = "status", desc = "each checkout: its branch, commits not pushed, changes not committed",
             run = function() sh((STATUS:gsub("MEMBERS", table.concat(MEMBERS, " ")))) end }
make.alias("s", "status")

make.recipe{ name = "update", desc = "every checkout to the tip of develop",
             run = function() sh("git submodule update --init --remote --merge") end }

-- Checked for all four before any is touched: a release or push that stops halfway leaves the
-- members disagreeing about what was shipped.
local function ready(what)
  for _, name in ipairs(MEMBERS) do
    local _, branch = captured(("git -C %s branch --show-current"):format(name))
    local _, changed = captured(("git -C %s status --porcelain"):format(name))
    assert(branch == "develop", ("%s is not on develop; nothing was %s"):format(name, what))
    assert(changed == "", ("%s has uncommitted changes; nothing was %s"):format(name, what))
  end
end

-- Pin here whatever the members now point at. Only after they are pushed: a pin to a commit GitHub
-- has never seen is a clone that fails for everybody but you.
local function pin()
  local _, moved = captured("git diff --name-only -- " .. table.concat(MEMBERS, " "))
  if moved == "" then
    print("every pin is already where its checkout is")
    return
  end
  local names = {}
  for line in moved:gmatch("[^\n]+") do names[#names + 1] = line end
  local listed = table.concat(names, " ")
  sh(("git commit -q -m 'chore(pin): %s' -- %s"):format(table.concat(names, ", "), listed))
  sh("git push -q origin HEAD")
end

make.recipe{
  name = "push",
  desc = "push each checkout's develop, then pin what was pushed here",
  run = function()
    ready("pushed")
    for _, name in ipairs(MEMBERS) do
      sh(("git -C %s push -q origin develop"):format(name))
    end
    pin()
  end,
}

-- Each member's own `release`: a version, its changelog and tag, develop merged into main, and a
-- GitHub release. One after another, stopping at the first that fails, then pinned here.
make.recipe{
  name = "release",
  desc = "release every checkout: --type patch | minor | major | M.m.p, then pin",
  params = { { "--type", desc = "patch | minor | major | M.m.p" } },
  run = function(a)
    assert(type(a.type) == "string",
           "which release? make release --type patch|minor|major|M.m.p")
    assert(a.type:match("^%a+$") or a.type:match("^%d+%.%d+%.%d+$"),
           "--type is patch, minor, major or M.m.p")
    checked_out()
    ready("released")
    for _, name in ipairs(MEMBERS) do
      print(oslo.ui.title(("%s · make release --type %s"):format(name, a.type)))
      assert(oslo.run{ "sh", "-c", ("cd %s && oslo make release --type %s"):format(name, a.type) }.ok,
             ("%s did not release; the ones before it did, and nothing is pinned yet"):format(name))
    end
    pin()
  end,
}
