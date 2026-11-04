ExUnit.start(autorun: false)
Code.require_file("test/extensions/knowledge/shadow_concurrent_session_test.exs", __DIR__)
result = ExUnit.run()
System.halt(if result.failures == 0, do: 0, else: 1)
