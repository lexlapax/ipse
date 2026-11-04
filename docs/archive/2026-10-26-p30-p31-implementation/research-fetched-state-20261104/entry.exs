packet=__DIR__
evidence=Path.join(packet,"execution-01")
File.write!(Path.join(evidence,"beam.pid"),System.pid()<>"\n",[:exclusive])
"1"=System.fetch_env!("IPSE_TEST_RESEARCH_FETCH_SESSION")
:ok=Application.load(:ipse)
runtime=Path.join(packet,"runtime/lib/ipse")
true=Application.app_dir(:ipse)==runtime
241=length(Application.spec(:ipse,:modules))
for mod<-Application.spec(:ipse,:modules) do
 {:module,^mod}=Code.ensure_loaded(mod)
 true=String.starts_with?(to_string(:code.which(mod)),Path.join(runtime,"ebin/"))
end
%{type: :regular,links: 1}=File.lstat!(Path.join(runtime,"priv/ipse-runner"))
{:ok,bundles}=Ipse.Extension.Bundles.inventory()
4=length(bundles)
false=Code.ensure_loaded?(IpseKnowledge.Research)
ExUnit.start(autorun: false,max_cases: 1,seed: 0)
ExUnit.configure(include: [research_fetch_session: true],exclude: [:test])
{:ok,_}=Application.ensure_all_started(:ipse)
true=:sys.get_state(Ipse.Session.Input).entries==%{}
Code.require_file(Path.join(packet,"source/test/extensions/knowledge/research_fetch_transfer_test.exs"))
result=ExUnit.run()
File.write!(Path.join(evidence,"result.json"),Jason.encode!(result),[:exclusive,:sync])
true=:sys.get_state(Ipse.Session.Input).entries==%{}
roots=Path.wildcard(Path.join(System.tmp_dir!(),"ipse-research-fetch-transfer-*"))
File.write!(Path.join(evidence,"fixture-roots.txt"),Enum.join(roots,"\n")<>"\n",[:exclusive])
artifacts=for root<-roots, artifact=Path.join(root,"artifact"), File.regular?(Path.join(artifact,"extension.json")) do
 bytes=File.read!(Path.join(artifact,"extension.json"))
 {:ok,_}=Ipse.Extension.Artifact.decode(bytes)
 manifest=Jason.decode!(bytes)
 for item<-manifest["files"] do
  data=File.read!(Path.join(artifact,item["path"]))
  true=byte_size(data)==item["bytes"] and Ipse.JSON.sha256(data)==item["sha256"]
 end
 %{sha256: Ipse.JSON.sha256(bytes),bytes: byte_size(bytes),files: length(manifest["files"]),payloads_match: true}
end
File.write!(Path.join(evidence,"artifacts-safe.json"),Jason.encode!(artifacts),[:exclusive])
IO.puts("private_Input_entries_before_after=0 provider_calls_expected=0 native_operator_used=false")
System.halt(if(result==%{total: 2,failures: 0,excluded: 1,skipped: 0},do: 0,else: 2))
