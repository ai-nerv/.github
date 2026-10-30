local blocked = "evaluation-blocked|"
local selected = assert(melchior.evaluation_providers, "evaluation provider selection required")
assert(type(selected) == "table")
melchior.evaluation_providers = nil
local provider = melchior.provider
melchior.provider = function(name, spec)
  if selected[name] ~= true then return end
  assert(spec.api == "openai-completions" or spec.api == "anthropic-messages",
    "evaluation provider API is unsupported")
  assert(spec.auth and spec.auth.kind == "none", "evaluation provider authentication must be none")
  assert(type(spec.base_url) == "string" and
    (spec.base_url:match("^http://127%.0%.0%.1:%d+$") or spec.base_url:match("^http://127%.0%.0%.1:%d+/v1$")),
    "evaluation provider needs a loopback base URL")
  spec.base_url = blocked .. spec.base_url
  provider(name, spec)
end

for _, name in ipairs({ "openai-completions", "anthropic-messages" }) do
  local api = assert(melchior.apis[name])
  local endpoint = assert(api.endpoint)
  api.endpoint = function(base, model)
    assert(base:sub(1, #blocked) == blocked)
    local handle = assert(melchior.stream.connect("/world/runtime/melchior/.evaluation-admission/admission.sock", 250))
    local reply = handle:call({ call = "reserve" }, { deadline_ms = 250 })
    handle:close()
    assert(reply and reply.ok == true and reply.n == 1 and type(reply.result) == "table")
    local attempt = reply.result[1]
    assert(type(attempt) == "number" and attempt >= 1 and attempt <= 64 and attempt % 1 == 0)
    return endpoint(base:sub(#blocked + 1), model)
  end
end
