import ExUnit.Assertions
packet=__DIR__
:ok=Application.load(:ipse)
runtime=Path.join(packet,"runtime/lib/ipse")
true=Application.app_dir(:ipse)==runtime
241=length(Application.spec(:ipse,:modules))
for mod<-Application.spec(:ipse,:modules) do
 {:module,^mod}=Code.ensure_loaded(mod)
 true=String.starts_with?(to_string(:code.which(mod)),Path.join(runtime,"ebin/"))
end
true=to_string(:code.priv_dir(:ipse))==Path.join(runtime,"priv")
%{type: :regular,links: 1}=File.lstat!(Path.join(runtime,"priv/ipse-runner"))
{:ok,bundles}=Ipse.Extension.Bundles.inventory()
4=length(bundles)
ExUnit.start(autorun: false)
source=Path.join(packet,"source")
fixture=Path.join(packet,"fixture-ebin-preflight")
File.mkdir_p!(fixture)
{:ok,_,diagnostics}=Kernel.ParallelCompiler.compile_to_path([Path.join(source,"dev/fixtures/knowledge.exs")],fixture,return_diagnostics: true)
true=diagnostics in [[],%{compile_warnings: [],runtime_warnings: []}]
Code.require_file(Path.join(source,"test/support/native_pipe_scope.exs"))
{:__block__,_,items}=Code.string_to_quoted!(File.read!(Path.join(source,"test/support/research_fetch_transfer_session.exs")))
for mod<-Enum.filter(items,&match?({:defmodule,_,_},&1)), do: Code.compile_quoted(mod)
body={:__block__,[],Enum.reject(items,&match?({:defmodule,_,_},&1))}
quoted=quote do
 defmodule FetchTransferDeferred do
  def never_called do
   unquote(body)
  end
 end
end
file=Path.join(packet,"deferred-session.ex")
File.write!(file,Macro.to_string(quoted))
out=Path.join(packet,"deferred-ebin")
File.mkdir_p!(out)
{:ok,_,diagnostics}=Kernel.ParallelCompiler.compile_to_path([file],out,return_diagnostics: true)
true=diagnostics in [[],%{compile_warnings: [],runtime_warnings: []}]
Code.require_file(Path.join(source,"test/extensions/knowledge/research_fetch_transfer_test.exs"))
tests=Ipse.KnowledgeResearchFetchTransferTest.__ex_unit__().tests
[selected]=Enum.filter(tests,& &1.tags[:research_fetch_session])
flagged=System.get_env("IPSE_TEST_RESEARCH_FETCH_SESSION")=="1"
assert selected.tags[:skip]==if(flagged,do: false,else: "explicit Linux protected-storage fetched-transfer Session fixture required")
assert selected.tags.timeout==120_000
false=Enum.any?(Application.started_applications(),fn {app,_,_}->app==:ipse end)
false=Code.ensure_loaded?(IpseKnowledge.Research)
IO.puts("private_Ipse_modules=241 Bootstrap=true helper_regular=true bundles=4 fixture_compiled=true deferred_full_session_strict=true declared_tests=#{length(tests)} session_flag=#{flagged} App_started=false native_calls=0 Input_calls=0 MCP_calls=0 tests_run=0")
