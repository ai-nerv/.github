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

-- The newest binary a member's build left: magi builds against musl when it can, glibc when not.
local function built(name)
  local ok, path = captured(("ls -t %s/target/*/release/%s %s/target/release/%s 2>/dev/null | head -1")
    :format(name, name, name, name))
  assert(ok and path ~= "", name .. " has not been built; run make build")
  return path
end

make.recipe{ name = "build", desc = "every binary",
             run = function() each(function(name) return BUILD[name] or "build" end) end }
make.alias("b", "build")

make.recipe{
  name = "run",
  desc = "magi, with the other three fresh from their builds rather than installed",
  deps = { "build" },
  params = { { "--args", desc = "what to hand magi: a prompt, or a subcommand such as doctor" } },
  run = function(a)
    local dirs = {}
    for _, name in ipairs(MEMBERS) do
      dirs[#dirs + 1] = "$PWD/" .. built(name):match("^(.*)/[^/]+$")
    end
    sh(('PATH="%s:$PATH" "$PWD/%s" %s'):format(table.concat(dirs, ":"), built("magi"), a.args or ""))
  end,
}
make.alias("r", "run")

make.recipe{ name = "install", desc = "every binary to ~/.local/bin, and each configuration",
             run = function() each(function() return "install" end) end }
make.alias("i", "install")

make.recipe{ name = "test", desc = "every suite",
             run = function() each(function() return "test" end) end }
make.alias("t", "test")

local function family_script(script, mode)
  local bash = os.getenv("NERV_BASH") or (oslo.fs.exists("/bin/bash") and "/bin/bash" or "bash")
  local args = { bash, script }
  if mode then args[#args + 1] = mode end
  assert(oslo.run(args).ok, script .. " failed")
end

make.recipe{ name = "test-family-runner", desc = "family runner failure and isolation fixtures",
             run = function() family_script("scripts/tests/family.sh") end }

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
