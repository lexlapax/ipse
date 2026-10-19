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
    assert!(usage.max_rss > 0);
    #[cfg(target_os = "macos")]
    let bytes = usage.max_rss as u64;
    #[cfg(target_os = "linux")]
    let bytes = usage.max_rss as u64 * 1024;
    bytes
}

fn main() -> ExitCode {
    match std::env::args().nth(1).as_deref() {
        Some("allocate") => {
            let mut memory = vec![0_u8; 64 * 1024 * 1024];
            for i in (0..memory.len()).step_by(4096) {
                unsafe { memory.as_mut_ptr().add(i).write_volatile(1) };
            }
            std::hint::black_box(&memory);
        }
        Some("parent") => {
            let status = Command::new(std::env::current_exe().unwrap()).arg("allocate").status().unwrap();
            assert!(status.success());
        }
        Some("empty") => (),
        _ => {
            let empty = measured("empty");
            let direct = measured("allocate");
            let descendant = measured("parent");
            assert!(direct > empty + 32 * 1024 * 1024);
            assert!(descendant > empty + 32 * 1024 * 1024);
            println!("{{\"empty_process_peak_bytes\":{},\"direct_peak_bytes\":{},\"waited_descendant_peak_bytes\":{},\"allocation_bytes\":67108864,\"sampling_used\":false,\"properly_waited_rollup\":true}}", empty, direct, descendant);
        }
    }
    ExitCode::SUCCESS
}
