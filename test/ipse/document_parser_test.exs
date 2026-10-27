defmodule Ipse.DocumentParserTest do
  use ExUnit.Case, async: false

  setup do
    root = Path.join(System.tmp_dir!(), "document-registry-" <> Ipse.Usage.id())
    File.mkdir!(root)
    File.chmod!(root, 0o700)
    for name <- ~w(ebin priv home workspace), do: File.mkdir!(Path.join(root, name))
    File.chmod!(Path.join(root, "home"), 0o700)
    File.write!(Path.join(root, "priv/ipse-pdf"), "independent parser identity fixture")
    File.chmod!(Path.join(root, "priv/ipse-pdf"), 0o500)
    helper = Path.expand("priv/ipse-runner")
    File.cp!(helper, Path.join(root, "priv/ipse-runner"))
    File.chmod!(Path.join(root, "priv/ipse-runner"), 0o500)

    source =
      File.read!("lib/ipse/document_parser.ex")
      |> String.replace(
        "defmodule Ipse.DocumentParser do",
        "defmodule DocumentRegistryFixture do"
      )
      |> String.replace(
        "Path.expand(\"../../priv/ipse-pdf\", __DIR__)",
        inspect(Path.join(root, "priv/ipse-pdf"))
      )
      |> String.replace(
        "Path.expand(\"../../priv/ipse-runner\", __DIR__)",
        inspect(Path.join(root, "priv/ipse-runner"))
      )

    file = Path.join(root, "fixture.ex")
    File.write!(file, source)

    {:ok, _, _} =
      Kernel.ParallelCompiler.compile_to_path([file], Path.join(root, "ebin"),
        return_diagnostics: true
      )

    :code.purge(DocumentRegistryFixture)
    :code.delete(DocumentRegistryFixture)

    {:module, DocumentRegistryFixture} =
      :code.load_abs(String.to_charlist(Path.join(root, "ebin/Elixir.DocumentRegistryFixture")))

    on_exit(fn ->
      :code.purge(DocumentRegistryFixture)
      :code.delete(DocumentRegistryFixture)
      Code.delete_path(Path.join(root, "ebin"))
      refute String.to_charlist(Path.join(root, "ebin")) in :code.get_path()
      File.rm_rf!(root)
    end)

    %{root: root}
  end

  test "protected host descriptor creates no staging directories and ignores helper overrides", %{
    root: root
  } do
    previous = System.get_env("IPSE_RUNNER_PATH")
    System.put_env("IPSE_RUNNER_PATH", "/untrusted/never-execute")

    try do
      assert {:ok, descriptor} =
               apply(DocumentRegistryFixture, :descriptor, [
                 Path.join(root, "home"),
                 Path.join(root, "workspace")
               ])

      assert descriptor.copy_helper.path == Path.join(root, "priv/ipse-runner")
      refute File.exists?(descriptor.staging_root)
      assert File.ls!(Path.join(root, "home")) == []

      assert {:error, :pdf_parser_unavailable} =
               apply(DocumentRegistryFixture, :descriptor, [Path.join(root, "home"), root])
    after
      if previous,
        do: System.put_env("IPSE_RUNNER_PATH", previous),
        else: System.delete_env("IPSE_RUNNER_PATH")
    end
  end

  test "parser-free source builds compile cleanly and report unavailable", %{root: root} do
    source =
      File.read!(Path.join(root, "fixture.ex"))
      |> String.replace("DocumentRegistryFixture", "DocumentRegistryUnavailable")
      |> String.replace(
        inspect(Path.join(root, "priv/ipse-pdf")),
        inspect(Path.join(root, "missing-parser"))
      )

    file = Path.join(root, "unavailable.ex")
    File.write!(file, source)

    assert {:ok, _, warnings} =
             Kernel.ParallelCompiler.compile_to_path([file], Path.join(root, "ebin"),
               return_diagnostics: true
             )

    assert warnings in [[], %{compile_warnings: [], runtime_warnings: []}]
    assert {:error, :pdf_parser_unavailable} = apply(DocumentRegistryUnavailable, :descriptor, [])
    :code.purge(DocumentRegistryUnavailable)
    :code.delete(DocumentRegistryUnavailable)
  end

  test "writable install ancestors refuse before reading or invoking substituted bootstrap bytes",
       %{root: root} do
    sentinel = Path.join(root, "executed")
    helper = Path.join(root, "priv/ipse-runner")
    File.chmod!(helper, 0o700)
    File.write!(helper, "#!/bin/sh\nprintf unsafe > " <> inspect(sentinel) <> "\n")
    File.chmod!(Path.join(root, "priv"), 0o777)

    assert {:error, :pdf_parser_unavailable} =
             apply(DocumentRegistryFixture, :descriptor, [
               Path.join(root, "home"),
               Path.join(root, "workspace")
             ])

    assert {:error, :pdf_parser_unavailable} = apply(DocumentRegistryFixture, :descriptor, [])
    refute File.exists?(sentinel)
  end

  test "metadata discovery refuses a FIFO without opening it", %{root: root} do
    parser = Path.join(root, "priv/ipse-pdf")
    File.rm!(parser)
    assert {_, 0} = System.cmd(System.find_executable("mkfifo"), [parser])
    task = Task.async(fn -> apply(DocumentRegistryFixture, :descriptor, []) end)
    assert {:error, :pdf_parser_unavailable} = Task.await(task, 500)
  end
end
