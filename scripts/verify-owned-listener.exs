unless match?({:unix, :linux}, :os.type()),
  do: raise("owned listener verification requires Linux")

[] = System.argv()

Code.require_file("../test/support/owned_listener_verification.exs", __DIR__)

root =
  Path.join(
    System.tmp_dir!(),
    "ipse-owned-listener-" <> Base.encode16(:crypto.strong_rand_bytes(16), case: :lower)
  )

File.mkdir!(root)
File.chmod!(root, 0o700)
fixture = Path.join(root, "probe")

{_, 0} =
  System.cmd(
    "rustc",
    [
      "--edition=2021",
      "-D",
      "warnings",
      Path.expand("../test/support/owned_listener_probe.rs", __DIR__),
      "-o",
      fixture
    ],
    stderr_to_stdout: true
  )

OwnedListenerVerification.verify(fixture, root)
|> JSON.encode!()
|> IO.puts()
