defmodule IpseSessionExample.Provider do
  def complete(config, _messages, _tools, _emit) do
    send(config.example_owner, :provider_called)
    {:ok, %{"role" => "assistant", "content" => "Hello from the session example."}, %{}}
  end
end

root = Path.join(System.tmp_dir!(), "ipse-session-example-#{Ipse.Usage.id()}")
File.mkdir_p!(root)
state = Path.join(root, "sessions")

config = %{
  provider: :demo,
  provider_module: IpseSessionExample.Provider,
  model: "session-example",
  approval: :deny,
  home: Path.join(root, "home"),
  example_owner: self()
}

start = fn id ->
  DynamicSupervisor.start_child(
    Ipse.Sessions,
    {Ipse.Session, config: config, cwd: root, state_dir: state, subscriber: self(), id: id}
  )
end

try do
  {:ok, session} = start.(nil)
  :ok = Ipse.Session.prompt(session, "Say hello")

  receive do
    :provider_called -> :ok
  after
    5_000 -> raise "The example provider was not called"
  end

  receive do
    {:ipse, ^session, {:done, :ok}} -> :ok
  after
    5_000 -> raise "The example turn did not finish"
  end

  id = Ipse.Session.info(session).id
  :ok = Ipse.Session.close_confirmed(session)
  {:ok, events} = Ipse.Journal.load(state, id)

  true =
    Enum.any?(events, &(get_in(&1, ["message", "content"]) == "Hello from the session example."))

  {:ok, resumed} = start.(id)
  :idle = Ipse.Session.info(resumed).phase

  receive do
    :provider_called -> raise "Idle resume called the provider"
  after
    0 -> :ok
  end

  :ok = Ipse.Session.close_confirmed(resumed)
  IO.puts("Session completed, journal retained its answer, and idle resume made no model call.")
after
  File.rm_rf!(root)
end
