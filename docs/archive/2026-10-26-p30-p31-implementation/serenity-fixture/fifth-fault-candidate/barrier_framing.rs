//! Bounded parser for private helper's diagnostic socket. No IO or entrypoint.
#[derive(Debug,PartialEq,Eq)] pub(super) enum Frame { Ready, Write(i32), Sync(i32) }
#[derive(Clone,Copy,Debug,PartialEq,Eq)] enum State { Start, Gate, Write, Sync, End, Failed }
pub(super) struct Decoder { state: State, pending: Vec<u8> }
impl Decoder {
 pub(super) fn new()->Self{Self{state:State::Start,pending:Vec::new()}}
 pub(super) fn feed(&mut self, input:&[u8])->Result<Vec<Frame>,()> {
  if self.state == State::Failed || input.len()>16 || self.pending.len()+input.len()>16 {self.state=State::Failed;return Err(())}
  self.pending.extend_from_slice(input); let mut frames=Vec::new();
  loop { let required=match self.state {State::Start=>1,State::Gate=>{if self.pending.is_empty(){break}else{self.state=State::Failed;return Err(())}},State::Write|State::Sync=>5,State::End=>{if self.pending.is_empty(){break}else{self.state=State::Failed;return Err(())}},State::Failed=>return Err(())};
   if self.pending.len()<required {break}
   let bytes:Vec<u8>=self.pending.drain(..required).collect();
   let frame=match self.state {
    State::Start if bytes[0]==b'R' => {self.state=State::Gate;Frame::Ready},
    State::Write if bytes[0]==b'W' => {let errno=i32::from_be_bytes(bytes[1..5].try_into().map_err(|_|())?);self.state=if errno==0 {State::Sync}else{State::End};Frame::Write(errno)},
    State::Sync if bytes[0]==b'S' => {let errno=i32::from_be_bytes(bytes[1..5].try_into().map_err(|_|())?);self.state=State::End;Frame::Sync(errno)},
    _ => {self.state=State::Failed;return Err(())}
   }; frames.push(frame);
  } Ok(frames)
 }
 pub(super) fn gate_sent(&mut self)->Result<(),()> {if self.state==State::Gate && self.pending.is_empty(){self.state=State::Write;Ok(())}else{self.state=State::Failed;Err(())}}
 pub(super) fn eof(&mut self)->Result<(),()> {if self.state==State::End && self.pending.is_empty(){Ok(())}else{self.state=State::Failed;Err(())}}
}
#[cfg(test)] mod tests {use super::*;
 #[test] fn accepts_every_fragment_boundary_after_gate(){let bytes=b"W\0\0\0\0S\0\0\0\x05";for split in 0..=bytes.len(){let mut d=Decoder::new();assert_eq!(d.feed(b"R").unwrap(),vec![Frame::Ready]);assert_eq!(d.gate_sent(),Ok(()));let mut f=d.feed(&bytes[..split]).unwrap();f.extend(d.feed(&bytes[split..]).unwrap());assert_eq!(f,vec![Frame::Write(0),Frame::Sync(5)]);assert_eq!(d.eof(),Ok(()));}}
 #[test] fn write_error_finishes_without_sync(){let mut d=Decoder::new();d.feed(b"R").unwrap();d.gate_sent().unwrap();assert_eq!(d.feed(b"W\0\0\0\x05").unwrap(),vec![Frame::Write(5)]);assert_eq!(d.eof(),Ok(()));}
 #[test] fn frames_before_gate_and_replayed_gate_are_refused(){let mut d=Decoder::new();assert!(d.feed(b"RW").is_err());let mut d=Decoder::new();d.feed(b"R").unwrap();d.gate_sent().unwrap();assert!(d.gate_sent().is_err());}
 #[test] fn partial_wrong_order_trailing_and_oversize_fail_closed(){for bytes in [&b"WoopsS"[..],&b"S\0\0\0\0"[..],&b"W\0\0\0\x05X"[..],&[0;17][..]] {let mut d=Decoder::new();d.feed(b"R").unwrap();d.gate_sent().unwrap();assert!(d.feed(bytes).is_err() || d.eof().is_err());assert!(d.feed(b"R").is_err());}let mut d=Decoder::new();d.feed(b"R").unwrap();d.gate_sent().unwrap();assert!(d.feed(b"W\0\0").unwrap().is_empty());assert_eq!(d.eof(),Err(()));}
}
