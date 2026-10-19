use std::fs;
use std::io::{BufRead, BufReader, Read, Write};
use std::os::unix::process::CommandExt;
use std::process::{Child, Command, Stdio};
use std::time::Duration;

extern "C" { fn setsid() -> i32; fn signal(number: i32, handler: usize) -> usize; }

fn wait_for(mut condition: impl FnMut() -> bool) {
    for _ in 0..500 {
        if condition() { return; }
        std::thread::sleep(Duration::from_millis(10));
    }
    panic!("probe deadline exceeded");
}

fn memory(megabytes: usize) -> Vec<u8> {
    let mut bytes = vec![0_u8; megabytes * 1024 * 1024];
    for offset in (0..bytes.len()).step_by(4096) {
        unsafe { bytes.as_mut_ptr().add(offset).write_volatile(1) };
    }
    bytes
}

fn allocator() -> Child {
    let mut child = Command::new(std::env::current_exe().unwrap())
        .args(["allocate", "64"]).stdin(Stdio::piped()).stdout(Stdio::piped())
        .spawn().unwrap();
    let mut ready = String::new();
    BufReader::new(child.stdout.take().unwrap()).read_line(&mut ready).unwrap();
    assert_eq!(ready, "ready\n");
    child
}

fn release(mut child: Child) {
    child.stdin.take().unwrap().write_all(b"x").unwrap();
    assert!(child.wait().unwrap().success());
}

fn main() {
    let args = std::env::args().collect::<Vec<_>>();
    match args[1].as_str() {
        "allocate" => {
            let bytes = memory(args[2].parse().unwrap());
            println!("ready"); std::io::stdout().flush().unwrap();
            let mut release = [0_u8; 1];
            std::io::stdin().read_exact(&mut release).unwrap();
            std::hint::black_box(bytes);
        }
        "brief" => { std::hint::black_box(memory(args.get(2).map_or(256, |n| n.parse().unwrap()))); }
        "closed-exec" => {
            let error = Command::new(&args[2]).args(&args[3..]).stdin(Stdio::null()).exec();
            panic!("closed-owner exec failed: {error}");
        }
        "serial" => { release(allocator()); release(allocator()); }
        "overlap" => { let first = allocator(); let second = allocator(); release(first); release(second); }
        "detached" => {
            let bytes = memory(32);
            fs::write(&args[2], std::process::id().to_string()).unwrap();
            std::thread::sleep(Duration::from_secs(30));
            std::hint::black_box(bytes);
        }
        "tree" => {
            let mut command = Command::new(std::env::current_exe().unwrap());
            command.args(["detached", &args[2]]);
            unsafe { command.pre_exec(|| if setsid() < 0 { Err(std::io::Error::last_os_error()) } else { Ok(()) }); }
            let mut child = command.spawn().unwrap();
            assert!(child.wait().unwrap().success());
        }
        "nested" => {
            for number in 1..=2 {
                let token = format!("{number:032x}");
                let output = format!("{}/cell-{number}", args[3]);
                let mut command = Command::new(&args[2]);
                command.args(["--measure-cgroup", "cell", &token, "10000", &output, "--"])
                    .arg(std::env::current_exe().unwrap()).arg("brief")
                    .arg(if number == 1 { "256" } else { "64" })
                    .stdin(Stdio::piped()).stdout(Stdio::null());
                unsafe { command.pre_exec(|| {
                    if signal(17, 1) == usize::MAX { return Err(std::io::Error::last_os_error()); }
                    Ok(())
                }); }
                let mut child = command.spawn().unwrap();
                let lease = child.stdin.take().unwrap();
                assert!(child.wait().unwrap().success());
                drop(lease);
            }
        }
        "cell-loss" => {
            let token = "00000000000000000000000000000003";
            let output = format!("{}/lost-cell", args[3]);
            let pid_path = format!("{}/lost-cell-descendant", args[3]);
            let mut child = Command::new(&args[2])
                .args(["--measure-cgroup", "cell", token, "20000", &output, "--"])
                .arg(std::env::current_exe().unwrap()).args(["tree", &pid_path])
                .stdin(Stdio::piped()).stdout(Stdio::null()).spawn().unwrap();
            let lease = child.stdin.take().unwrap();
            wait_for(|| fs::metadata(&pid_path).is_ok());
            let started = fs::read_to_string(format!("{output}/started.json")).unwrap();
            let anchor: u32 = started.split("\"anchor_pid\":").nth(1).unwrap()
                .chars().take_while(|c| c.is_ascii_digit()).collect::<String>().parse().unwrap();
            child.kill().unwrap(); assert!(!child.wait().unwrap().success());
            let root = std::env::var("IPSE_MEASURE_ROOT").unwrap();
            let events = format!("{root}/cell-{token}/cgroup.events");
            wait_for(|| fs::read_to_string(&events).unwrap().lines().any(|s| s == "populated 0"));
            wait_for(|| match fs::read_to_string(format!("/proc/{anchor}/status")) {
                Err(e) if e.kind() == std::io::ErrorKind::NotFound => true,
                Ok(s) => s.contains("State:\tZ"),
                _ => false,
            });
            assert!(!std::path::Path::new(&format!("{output}/receipt.json")).exists());
            drop(lease);
            println!("cell collector loss cleaned while application remains alive");
        }
        other => panic!("unknown probe {other}"),
    }
}
