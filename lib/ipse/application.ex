defmodule Ipse.Application do
  use Application

  def start(_type, _args) do
    Supervisor.start_link(
      [
        {Registry, keys: :unique, name: Ipse.Registry},
        {Task.Supervisor, name: Ipse.Tasks},
        {DynamicSupervisor, strategy: :one_for_one, name: Ipse.Sessions}
      ],
      strategy: :one_for_one,
      name: Ipse.Supervisor
    )
  end
end
