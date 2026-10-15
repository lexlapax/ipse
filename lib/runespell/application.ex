defmodule Runespell.Application do
  use Application

  def start(_type, _args) do
    Supervisor.start_link(
      [
        {Registry, keys: :unique, name: Runespell.Registry},
        {Task.Supervisor, name: Runespell.Tasks},
        {DynamicSupervisor, strategy: :one_for_one, name: Runespell.Sessions}
      ],
      strategy: :one_for_one,
      name: Runespell.Supervisor
    )
  end
end
