melchior.provider("evaluation", {
  name = "Child Fake", api = "openai-completions",
  base_url = "http://127.0.0.1:@PORT@/v1", auth = { kind = "none" },
  models = { { id = "echo-1", name = "Child Fake", context_window = 200000, max_tokens = 4096,
    cost = { input = 2, output = 8 } } },
})
