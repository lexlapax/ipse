path = "test/support/generation_finalization.exs"
Code.eval_string(File.read!(path), [paged: true], file: path)
