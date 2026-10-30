melchior.provider("evaluation-chat", {
  name = "Accounting Chat", api = "openai-completions",
  base_url = "http://127.0.0.1:@PORT@/v1", auth = { kind = "none" },
  models = { { id = "chat-1", name = "Accounting Chat", context_window = 200000, max_tokens = 4096,
    cost = { input = 2, output = 8, cache_read = 0.25, cache_write = 2.5 } } },
})
melchior.provider("evaluation-anthropic", {
  name = "Accounting Anthropic", api = "anthropic-messages",
  base_url = "http://127.0.0.1:@PORT@", auth = { kind = "none" },
  compat = { prompt_cache = "anthropic_ephemeral" },
  models = { { id = "anthropic-1", name = "Accounting Anthropic", context_window = 200000, max_tokens = 4096,
    cost = { input = 2, output = 8, cache_read = 0.25, cache_write = 2.5 } } },
})
