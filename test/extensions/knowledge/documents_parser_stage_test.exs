defmodule Ipse.KnowledgeDocumentsParserStageTest do
  use ExUnit.Case, async: false
  @root Path.expand("../../..", __DIR__)
  @parser System.get_env("IPSE_TEST_PDF_PARSER") || Path.join(@root, "priv/ipse-pdf")
  @moduletag skip: not File.regular?(@parser)

  defp pure(body) do
    files = ~w(documents/zip documents/docx documents/parser_stage documents/pdf documents)
    args = Enum.flat_map(files, &["-r", Path.join(@root, "extensions/knowledge/src/#{&1}.ex")])

    setup =
      "import ExUnit.Assertions\nalias IpseKnowledge.Documents, as: D\nparser=#{inspect(@parser)}\n" <>
        ~S'''
        root=Path.join(System.tmp_dir!(),"ipse-stage-case-"<>Base.encode16(:crypto.strong_rand_bytes(8)))
        File.mkdir!(root); File.chmod!(root,0o700)
        home=Path.join(root,"home"); File.mkdir!(home); File.chmod!(home,0o700)
        {uid,0}=System.cmd("id",["-u"]); uid=String.to_integer(String.trim(uid))
        digest=fn path -> Base.encode16(:crypto.hash(:sha256,File.read!(path)),case: :lower) end
        copy=Path.expand("priv/ipse-runner")
        descriptor=%{path: parser,sha256: digest.(parser),uid: uid,workspace: Path.join(root,"workspace"),
          staging_root: Path.join(home,"document-parsers"),copy_helper: %{path: copy,sha256: digest.(copy)}}
        active=fn -> Path.wildcard(descriptor.staging_root<>"/slot-*/active") end
        wait=fn wait,function,n -> if function.() or n==0,do: function.(),else: (Process.sleep(10); wait.(wait,function,n-1)) end
        System.at_exit(fn _ -> File.rm_rf!(root) end)
        '''

    {output, status} =
      System.cmd(System.find_executable("elixir"), args ++ ["-e", setup <> body],
        stderr_to_stdout: true
      )

    assert status == 0, output
    refute output =~ "warning:"
  end

  test "protected roots, symlinks, hardlinks and writable parser images refuse" do
    pure(~S'''
    assert {:error,:unsafe_pdf_staging_root}=D.extract_pdf("bad",%{descriptor|staging_root: "/tmp/document-parsers"})
    File.chmod!(home,0o770)
    assert {:error,:unsafe_pdf_staging_root}=D.extract_pdf("bad",descriptor)
    File.chmod!(home,0o700)
    File.ln_s!(home,descriptor.staging_root)
    assert {:error,:unsafe_pdf_staging_root}=D.extract_pdf("bad",descriptor)
    File.rm!(descriptor.staging_root)
    source=Path.join(root,"source"); File.cp!(parser,source); File.chmod!(source,0o755)
    link=Path.join(root,"linked"); File.ln_s!(source,link)
    assert {:error,:pdf_parser_identity_unavailable}=D.extract_pdf("bad",%{descriptor|path: link})
    File.rm!(link); File.ln!(source,link)
    assert {:error,:pdf_parser_identity_unavailable}=D.extract_pdf("bad",%{descriptor|path: source})
    File.rm!(link); File.chmod!(source,0o777)
    assert {:error,:pdf_parser_identity_unavailable}=D.extract_pdf("bad",%{descriptor|path: source})
    assert active.()==[]
    ''')
  end

  test "four admitted slots precede source IO and retained lock inodes survive cleanup" do
    pure(~S'''
    assert {:error,:malformed_pdf}=D.extract_pdf("bad",descriptor)
    assert active.()==[]
    lock=Path.join(descriptor.staging_root,"slot-0/lock"); inode=File.lstat!(lock).inode
    assert {:error,:malformed_pdf}=D.extract_pdf("bad",descriptor)
    assert File.lstat!(lock).inode==inode
    for n<-0..3 do
      slot=Path.join(descriptor.staging_root,"slot-#{n}"); File.mkdir_p!(slot); File.chmod!(slot,0o700)
      File.mkdir!(Path.join(slot,"active")); File.chmod!(Path.join(slot,"active"),0o700)
    end
    assert {:error,:pdf_parser_slots_busy}=D.extract_pdf("bad",%{descriptor|path: "/missing/never-open"})
    assert length(active.())==4
    ''')
  end

  @tag skip: not match?({:unix, :linux}, :os.type())
  test "a paused pre-lease startup retains its slot on owner death and original path replacement never executes" do
    pure(~S'''
    for cancelled? <- [false,true] do
      control=Path.join(root,if(cancelled?,do: "cancel",else: "swap")); File.mkdir!(control)
      source=Path.join(control,"source"); pid_file=Path.join(control,"pid"); sentinel=Path.join(control,"unverified-ran")
      # The admitted fixture pauses before the real parser's lease acquisition.
      # Only this test fixture invokes a shell; production uses its compiled image.
      script="#!/bin/sh\nif [ \"$1\" = --lease ]; then\n  printf '%s' \"$$\" > "<>inspect(pid_file)<>"\n  kill -STOP \"$$\"\nfi\nexec "<>inspect(parser)<>" \"$@\"\n"
      File.write!(source,script); File.chmod!(source,0o755)
      selected=%{descriptor|path: source,sha256: digest.(source)}
      parent=self()
      caller=spawn(fn -> send(parent,{:result,D.extract_pdf("notPDF",selected)}) end)
      assert wait.(wait,fn -> File.regular?(pid_file) end,200)
      pid=File.read!(pid_file)
      assert wait.(wait,fn -> case File.read("/proc/"<>pid<>"/status") do {:ok,s}->String.contains?(s,"State:\tT"); _->false end end,100)
      try do
        assert length(active.())==1
        if cancelled?, do: Process.exit(caller,:kill)
        File.write!(source,"#!/bin/sh\nprintf bad > "<>inspect(sentinel)<>"\n"); File.chmod!(source,0o755)
        Process.sleep(50)
        assert length(active.())==1
      after
        System.cmd("kill",["-CONT",pid])
      end
      unless cancelled? do
        receive do {:result,result}->assert result=={:error,:malformed_pdf} after 3000->flunk("staged job did not finish") end
      end
      assert wait.(wait,fn -> active.()==[] end,600)
      refute File.exists?(sentinel)
    end
    ''')
  end
end
