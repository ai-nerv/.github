melchior.provider("evaluation", {
  name = "Pressure Fake", api = "openai-completions",
  base_url = "http://127.0.0.1:@PORT@/v1", auth = { kind = "none" },
  models = { { id = "echo-1", name = "Pressure Fake", context_window = 32000, max_tokens = 4096 } },
})
