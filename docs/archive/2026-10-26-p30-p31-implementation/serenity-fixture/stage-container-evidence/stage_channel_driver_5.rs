#![allow(dead_code)]
#[path="diagnostic_stage_channel.rs"]mod diagnostic_stage_channel;
#[path="peer_channel.rs"]mod peer_channel;
use std::io;use std::process::{Command,Stdio};
fn main()->io::Result<()> {let base="/tmp/ipse-stage-gate-review";let mut peer=peer_channel::Channel::start(&format!("{base}/container-run-5"))?;let child=Command::new("/usr/lib/elixir/bin/elixir").args(["-pa","/tmp/ipse-serenity-barrier-graph/build/lib/*/ebin","-pa","/tmp/ipse-stage-gate-review/build/lib/ipse/ebin","-e","Application.ensure_all_started(:ipse); Code.eval_file(\"/tmp/ipse-stage-gate-review/stage-channel-5.exs\")"]).stdin(Stdio::piped()).stdout(Stdio::piped()).stderr(Stdio::null()).spawn()?;let mut stage=diagnostic_stage_channel::Stage::from_child(child).map_err(|(_,e)|e)?;let pid=stage.start()?;peer.ready()?;peer.authorize(pid)?;let report=peer.release()?;peer.finish()?;stage.finish(&report)?;println!("RUST_STAGE_ADAPTER_OK {report}");Ok(())}
