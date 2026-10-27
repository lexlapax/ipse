defmodule BuildId do
 def parse(<<namesz::little-32,descsz::little-32,type::little-32,rest::binary>>) when namesz <= 256 and descsz <= 256 do
  npad=div(namesz+3,4)*4;dpad=div(descsz+3,4)*4
  case rest do
   <<name::binary-size(^npad),desc::binary-size(^dpad),tail::binary>> ->
    if type==3 and binary_part(name,0,namesz)==<<"GNU",0>> do
      IO.puts(Base.encode16(binary_part(desc,0,descsz),case: :lower))
    else parse(tail) end
   _ -> raise "truncated kernel note"
  end
 end
 def parse(<<>>),do: raise("GNU build ID unavailable")
 def parse(_),do: raise("malformed kernel note")
end
BuildId.parse(File.read!("/sys/kernel/notes"))
