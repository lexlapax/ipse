# Read-only runtime inventory of this isolated Mix graph. No device helper is
# opened. This samples current executable mappings and loaded BEAM module files;
# later code paths and dlopen operations can add more dependencies.
:ok = Application.ensure_all_started(:crypto) |> case do {:ok,_}->:ok; other->raise inspect(other) end
_ = :crypto.strong_rand_bytes(32)
for module <- [Ipse.Runner.Transaction, Ipse.Runner.Transaction.Controller, Ipse.Session.Resources] do
  {:module,^module} = Code.ensure_loaded(module)
end
sha = fn path ->
  case File.read(path) do
    {:ok,bytes} when byte_size(bytes)<=33_554_432 -> Base.encode16(:crypto.hash(:sha256,bytes),case: :lower)
    _ -> "unavailable"
  end
end
maps=File.read!("/proc/self/maps") |> String.split("\n",trim: true) |> Enum.flat_map(fn row ->
  case Regex.run(~r/\s(\/[^\s]+)$/,row) do [_,path]->[path]; _->[] end
end) |> Enum.uniq() |> Enum.sort()
for path <- maps, do: IO.puts("MAPPED\t#{path}\t#{sha.(path)}")
for {module,path} <- :code.all_loaded() |> Enum.sort(), is_list(path) do
  file=List.to_string(path)
  if Path.type(file)==:absolute, do: IO.puts("BEAM\t#{module}\t#{file}\t#{sha.(file)}")
end
