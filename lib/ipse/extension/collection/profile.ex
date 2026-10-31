defmodule Ipse.Extension.Collection.Profile do
  @moduledoc """
  Fixed host storage budgets. A profile grants no caller or filesystem authority.

  The document allocation reserves the complete existing notes envelope instead
  of adding 256 MiB beside it. Only a protected operator binding may select it.
  Native allocation, typed data limits, rebuild peak and population qualification
  remain separate checks; these constants do not establish a capacity pass.
  """
  @key {__MODULE__, :selected}
  @notes "notes-v1"
  @documents "document_graph_v1"
  @mib 1024 * 1024

  def notes, do: @notes
  def documents, do: @documents

  def fetch(@notes) do
    {:ok,
     %{
       "id" => @notes,
       "value_bytes" => 6 * 1024,
       "data_bytes" => 24 * @mib,
       "total_bytes" => 64 * @mib,
       "reserved_bytes" => 22 * @mib,
       "control_reserved_bytes" => 22 * @mib,
       "notes_reserved_bytes" => 0,
       "manifest_bytes" => 8 * @mib,
       "records" => 8192,
       "operations" => 32_768
     }}
  end

  def fetch(@documents) do
    {:ok,
     %{
       "id" => @documents,
       "value_bytes" => 64 * 1024,
       "data_bytes" => 160 * @mib,
       "total_bytes" => 256 * @mib,
       "reserved_bytes" => 64 * @mib,
       "control_reserved_bytes" => 0,
       "notes_reserved_bytes" => 64 * @mib,
       "manifest_bytes" => 8 * @mib,
       "records" => 8192,
       "operations" => 32_768
     }}
  end

  def fetch(_), do: {:error, :unknown_collection_profile}

  @doc false
  def fence(pointer) when is_map(pointer) do
    if selected() == @notes, do: pointer, else: Map.put(pointer, "storage_profile", selected())
  end

  @doc false
  def unfence(pointer, expected) when is_map(pointer) do
    case {expected, pointer["storage_profile"]} do
      {@notes, nil} ->
        if Map.has_key?(pointer, "storage_profile"),
          do: {:error, :collection_profile_mismatch},
          else: {:ok, pointer}

      {@documents, @documents} ->
        {:ok, Map.delete(pointer, "storage_profile")}

      _ ->
        {:error, :collection_profile_mismatch}
    end
  end

  def unfence(_, _), do: {:error, :collection_profile_mismatch}

  @doc "Frozen logical targets; no target is an observed or automatic admission."
  def targets(@documents) do
    {:ok,
     %{
       "sources" => 1000,
       "extracted_bytes" => 20 * @mib,
       "chunks" => 10_000,
       "entities" => 5000,
       "assertions" => 20_000,
       "total_bytes" => 256 * @mib,
       "rebuild_includes_old_and_staged" => true,
       "qualified" => false
     }}
  end

  def targets(_), do: {:error, :unknown_collection_targets}

  @doc false
  def selected, do: Process.get(@key, @notes)

  @doc false
  def limit(name) do
    {:ok, profile} = fetch(selected())
    Map.fetch!(profile, Atom.to_string(name))
  end

  @doc false
  def run(profile, fun) when is_function(fun, 0) do
    with {:ok, _} <- fetch(profile) do
      previous = Process.get(@key)
      Process.put(@key, profile)

      try do
        fun.()
      after
        if is_nil(previous), do: Process.delete(@key), else: Process.put(@key, previous)
      end
    end
  end
end
