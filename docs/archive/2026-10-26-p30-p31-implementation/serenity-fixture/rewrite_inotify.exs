p="/tmp/ipse-serenity-qualification-plan/fixture/inotify_backing.rs"
s=File.read!(p)
[before,rest]=String.split(s,"  let mut bytes=[0u8;8192];let n=self.fd.read(&mut bytes)?;",parts: 2)
[_old,after_]=String.split(rest,"\n }\n fn same",parts: 2)
replacement = ~S"""
  let mut bytes=[0u8;8192];let mut total=0usize;let mut closes=0usize;
  loop {match self.fd.read(&mut bytes) {
   Ok(0)=>return Err(io::ErrorKind::UnexpectedEof.into()),
   Ok(n)=>{total=total.checked_add(n).ok_or(io::ErrorKind::InvalidData)?;if total>131072{return Err(io::ErrorKind::InvalidData.into())}closes+=parse_events(&bytes[..n],self.wd)?;},
   Err(e) if e.kind()==io::ErrorKind::WouldBlock=>break,
   Err(e)=>return Err(e),
  }}
  Ok(closes)
"""
File.write!(p,before<>replacement<>"\n }\n fn same"<>after_)
