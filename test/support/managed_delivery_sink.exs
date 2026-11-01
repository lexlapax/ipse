defmodule Ipse.Test.ManagedDeliverySink do
  @moduledoc false
  alias Ipse.Extension.Artifact

  def select(data, home, root, role) do
    {capabilities, declarations} = declaration(role)
    source = Path.join(root, "delivery-artifact")
    File.mkdir_p!(Path.join(source, "ebin"))
    module = "Independent.ManagedDelivery#{System.unique_integer([:positive])}"
    file = Path.join(source, "fixture.ex")

    File.write!(file, """
    defmodule #{module} do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(capabilities)}, "subscriptions" => #{inspect(declarations)}}
      def init(options), do: {:ok, options}
      def handle(stage, payload, state) do
        File.write!(state["trace"], IO.iodata_to_binary(:json.encode(%{"stage" => stage, "payload" => payload})) <> "\\n", [:append])
        reply = case stage do
          "event.notify" -> %{"api_version" => 1, "kind" => "ack", "delivery_id" => payload["delivery_id"], "event_id" => payload["event"]["event_id"]}
          "event.feed" -> %{"api_version" => 1, "kind" => "ack", "handle" => payload["handle"], "sequence" => payload["sequence"], "event_id" => payload["event"]["event_id"]}
          "stream.text" -> %{"api_version" => 1, "kind" => "ack", "handle" => payload["handle"], "sequence" => Map.get(payload["frame"], "sequence", 0)}
        end
        {:ok, reply, state}
      end
    end
    """)

    case System.cmd(
           System.find_executable("elixirc"),
           ["-pa", Application.app_dir(:ipse, "ebin"), "-o", Path.join(source, "ebin"), file],
           stderr_to_stdout: true
         ) do
      {"", 0} -> :ok
      failure -> raise "delivery fixture compilation failed: #{inspect(failure)}"
    end

    File.write!(Path.join(source, "LICENSE"), "MIT synthetic fixture")
    File.rm!(file)

    manifest = %{
      "format" => 1,
      "id" => "fixture/managed_delivery",
      "version" => "0.1.0",
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => module,
      "license_file" => "LICENSE",
      "capabilities" => capabilities,
      "subscriptions" => declarations,
      "options_schema" => %{
        "type" => "object",
        "additionalProperties" => false,
        "required" => ["trace"],
        "properties" => %{"trace" => %{"type" => "string"}}
      },
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      },
      "files" =>
        Enum.map(["LICENSE", "ebin/Elixir.#{module}.beam"], fn path ->
          bytes = File.read!(Path.join(source, path))
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
        end)
    }

    File.write!(Path.join(source, "extension.json"), Jason.encode!(manifest))
    {:ok, artifact} = Artifact.import(source, Path.join(home, "extensions/artifacts"))

    data
    |> Map.update!(
      "extension_trust",
      &(&1 ++
          [
            %{
              "artifact" => artifact.digest,
              "capabilities" => capabilities,
              "allow_project" => false,
              "allow_children" => false,
              "text_required" => role == :text_required
            }
          ])
    )
    |> Map.update!(
      "extensions",
      &(&1 ++
          [
            %{
              "instance" => "delivery",
              "artifact" => artifact.digest,
              "enabled" => true,
              "options" => %{"trace" => Path.join(root, "delivery.jsonl")},
              "order" => 20,
              "lifetime" => "persistent"
            }
          ])
    )
  end

  def read(root) do
    case File.read(Path.join(root, "delivery.jsonl")) do
      {:ok, bytes} -> bytes |> String.split("\n", trim: true) |> Enum.map(&Jason.decode!/1)
      {:error, :enoent} -> []
    end
  end

  def await_ack(directory, id, role),
    do: await_ack(directory, id, role, System.monotonic_time(:millisecond) + 5_000)

  defp await_ack(directory, id, role, deadline) do
    {:ok, events} = Ipse.Journal.load(directory, id)

    acknowledged =
      Enum.any?(events, fn event ->
        if role in [:feed, :feed_metadata],
          do: event["type"] == "extension_feed_delivery_result",
          else: event["type"] == "extension_event_result" and event["outcome"] == "acknowledged"
      end)

    cond do
      acknowledged ->
        :ok

      System.monotonic_time(:millisecond) >= deadline ->
        raise "delivery acknowledgement missing"

      true ->
        Process.sleep(10)
        await_ack(directory, id, role, deadline)
    end
  end

  defp declaration(role) when role in [:text, :text_required], do: {["stream.text"], []}

  defp declaration(role) when role in [:notify, :notify_required, :notify_metadata] do
    private = role != :notify_metadata
    caps = ["event.notify"] ++ if(private, do: ["event.answer.original"], else: [])

    {caps,
     [
       %{
         "id" => "answer",
         "event" => "answer.committed",
         "event_version" => 1,
         "view" => if(private, do: "answer.original", else: "metadata"),
         "mode" => "notify",
         "schedule" => "after_turn",
         "required" => role == :notify_required
       }
     ]}
  end

  defp declaration(role) when role in [:feed, :feed_metadata] do
    private = role == :feed

    caps =
      ["event.feed", "lifecycle.record", "lifecycle.tools"] ++
        if(private, do: ["event.tool.result"], else: [])

    {caps,
     [
       %{
         "id" => "tools",
         "event" => "tool.outcome_recorded",
         "event_version" => 1,
         "view" => if(private, do: "tool.result", else: "metadata"),
         "mode" => "feed",
         "queue_events" => 8
       }
     ]}
  end
end
