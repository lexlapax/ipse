defmodule NativeRecallFiller do
  import ExUnit.Assertions

  def entries(root, home) do
    source = Path.join(root, "recall-filler-artifact")
    File.mkdir_p!(Path.join(source, "ebin"))
    capabilities = ~w(invoke.command host.actions host.context)

    exports =
      Map.put(Ipse.Extension.Catalog.empty(), "commands", [
        %{
          "id" => "fill",
          "description" => "Publish synthetic competing context",
          "arguments_schema" => %{
            "type" => "object",
            "additionalProperties" => false,
            "required" => ~w(count size),
            "properties" => %{
              "count" => %{"type" => "integer", "minimum" => 1, "maximum" => 8},
              "size" => %{"type" => "integer", "minimum" => 1, "maximum" => 2048}
            }
          },
          "result_schema" => %{"type" => "object"}
        }
      ])

    code = """
    defmodule Synthetic.RecallFiller do
      @behaviour Ipse.Extension
      def describe, do: %{"sdk" => 1, "capabilities" => #{inspect(capabilities)}, "exports" => #{inspect(exports)}}
      def init(options), do: {:ok, options}
      def handle("invoke.command", %{"arguments" => args}, state) do
        items = for i <- 1..args["count"], do: %{
          "id" => "fill" <> Integer.to_string(i), "version" => "1",
          "text" => String.duplicate("F", args["size"]), "priority" => 10,
          "source" => %{"kind" => "assertion", "uri" => "fixture:filler"}
        }
        {:ok, %{"api_version" => 1, "kind" => "host_call", "request" => %{"op" => "context.publish", "items" => items}}, state}
      end
      def handle("host.actions", payload, state), do: {:ok, %{"api_version" => 1, "kind" => "result", "value" => payload["outcome"]}, state}
    end
    """

    [{Synthetic.RecallFiller, beam}] = Code.compile_string(code)
    beam_path = "ebin/Elixir.Synthetic.RecallFiller.beam"
    File.write!(Path.join(source, beam_path), beam)
    File.write!(Path.join(source, "LICENSE"), "MIT synthetic fixture")

    manifest = %{
      "format" => 1,
      "id" => "fixture/recall-filler",
      "version" => "0.1.0",
      "sdk" => 1,
      "protocol" => 1,
      "backend" => "elixir_worker",
      "entrypoint" => "Synthetic.RecallFiller",
      "license_file" => "LICENSE",
      "options_schema" => %{"type" => "object", "additionalProperties" => false},
      "capabilities" => capabilities,
      "exports" => exports,
      "runtime" => %{
        "elixir" => ">= 1.18.0",
        "otp" => [String.to_integer(System.otp_release())],
        "platforms" => [to_string(:erlang.system_info(:system_architecture))]
      },
      "files" =>
        Enum.map(["LICENSE", beam_path], fn path ->
          bytes = File.read!(Path.join(source, path))
          %{"path" => path, "bytes" => byte_size(bytes), "sha256" => Ipse.JSON.sha256(bytes)}
        end)
    }

    File.write!(Path.join(source, "extension.json"), Jason.encode!(manifest))

    {:ok, artifact} =
      Ipse.Extension.Artifact.import(source, Path.join(home, "extensions/artifacts"))

    selection = %{
      scope: "operator",
      path: "/fixture/recall-filler.json",
      data: %{
        "extensions" =>
          for(
            {instance, order} <- [{"fill", 80}, {"spill", 81}],
            do: %{
              "instance" => instance,
              "artifact" => artifact.digest,
              "enabled" => true,
              "options" => %{},
              "order" => order,
              "lifetime" => "persistent"
            }
          ),
        "extension_trust" => [
          %{
            "artifact" => artifact.digest,
            "capabilities" => capabilities,
            "allow_project" => false,
            "allow_children" => false
          }
        ]
      }
    }

    {:ok, selections} = Ipse.Extension.Config.resolve([selection], [])
    {:ok, entries} = Ipse.Extension.Registry.prepare(selections, home)
    {entries, selection.data}
  end

  def items(count, size) do
    for i <- 1..count do
      %{
        "id" => "fill#{i}",
        "version" => "1",
        "text" => String.duplicate("F", size),
        "priority" => 10,
        "source" => %{"kind" => "assertion", "uri" => "fixture:filler"}
      }
    end
  end

  def max_size(contexts, identity, layout, lower \\ 1, upper \\ 2048, best \\ nil)
  def max_size(_contexts, _identity, _layout, lower, upper, best) when lower > upper, do: best

  def max_size(contexts, identity, layout, lower, upper, best) do
    size = div(lower + upper, 2)
    request = %{"op" => "context.publish", "items" => items(2, size)}

    case Ipse.Extension.Context.publish(contexts, identity, request, [], Ipse.Usage.id(), layout) do
      {:ok, _, _} -> max_size(contexts, identity, layout, size + 1, upper, size)
      _ -> max_size(contexts, identity, layout, lower, size - 1, best)
    end
  end

  def invoke(session, instance, count, size) do
    assert :ok =
             Ipse.Session.invoke_export(session, :command, "ext__#{instance}__fill", %{
               "count" => count,
               "size" => size
             })

    assert_receive {:ipse, ^session, {:done, :ok}}, 10_000
    assert Ipse.Session.info(session).extension_result["value"]["status"] == "ok"
  end
end
