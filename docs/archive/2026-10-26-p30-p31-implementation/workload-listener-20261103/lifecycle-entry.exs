ExUnit.start(autorun: false, seed: 0)
Code.require_file("test/dev/knowledge/synthetic_ollama_lifecycle_test.exs")
result = ExUnit.run()
if result.total != 6 or result.failures != 0 or result.skipped != 0, do: System.halt(1)
