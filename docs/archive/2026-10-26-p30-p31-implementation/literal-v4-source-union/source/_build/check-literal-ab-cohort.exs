for graph <- ~w(_build/session-header-audit2-sol-20261029/lib/ipse _build/strict-lifetime-followup-sol-20261029/lib/ipse) do
  for module <- ~w(Elixir.Ipse.Session.Invocation Elixir.Ipse.Session.ManagedToolUse Elixir.Ipse.Extension.Collection) do
    path = Path.join([graph,"ebin",module <> ".beam"])
    {:ok,{_,[imports: imports]}}=:beam_lib.chunks(String.to_charlist(path),[:imports])
    IO.inspect({graph,module,Enum.filter(imports,fn {m,f,_}-> m==Ipse.Session.ManagedToolUse or f==:publication_deadline_admission end)})
  end
end
