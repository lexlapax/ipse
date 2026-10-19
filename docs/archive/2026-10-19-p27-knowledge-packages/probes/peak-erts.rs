use std::os::raw::{c_int, c_long};
use std::process::{Command, ExitCode};

#[repr(C)]
#[derive(Default)]
struct Timeval { seconds: c_long, micros: c_long }
#[repr(C)]
#[derive(Default)]
struct Rusage { user: Timeval, system: Timeval, max_rss: c_long, rest: [c_long; 13] }
unsafe extern "C" {
    fn wait4(pid: c_int, status: *mut c_int, options: c_int, usage: *mut Rusage) -> c_int;
}
fn measured(mode: &str) -> u64 {
    let child = Command::new(std::env::current_exe().unwrap()).arg(mode).spawn().unwrap();
    let pid = child.id() as c_int;
    let mut status = 0;
    let mut usage = Rusage::default();
    assert_eq!(unsafe { wait4(pid, &mut status, 0, &mut usage) }, pid);
    assert_eq!(status, 0);
    #[cfg(target_os = "macos")]
    let bytes = usage.max_rss as u64;
    #[cfg(target_os = "linux")]
    let bytes = usage.max_rss as u64 * 1024;
    bytes
}
fn main() -> ExitCode {
    match std::env::args().nth(1).as_deref() {
        Some("allocate") => {
            let mut memory = vec![0_u8; 256 * 1024 * 1024];
            for i in (0..memory.len()).step_by(4096) {
                unsafe { memory.as_mut_ptr().add(i).write_volatile(1) };
            }
            std::hint::black_box(&memory);
        }
        Some("through-beam") => {
            let exe = std::env::current_exe().unwrap();
            let code = "{_, 0} = System.cmd(hd(System.argv()), [\"allocate\"])";
            assert!(Command::new("elixir").args(["-e", code, "--"]).arg(exe).status().unwrap().success());
        }
        _ => {
            let direct = measured("allocate");
            let through_beam = measured("through-beam");
            assert!(direct > 200 * 1024 * 1024);
            assert!(through_beam > 0);
            println!("{{\"allocation_bytes\":268435456,\"direct_peak_bytes\":{},\"through_beam_waited_chain_peak_bytes\":{},\"large_port_child_peak_missing\":{},\"sampling_used\":false,\"inference_requests\":0}}", direct, through_beam, direct > through_beam + 64 * 1024 * 1024);
        }
    }
    ExitCode::SUCCESS
}
