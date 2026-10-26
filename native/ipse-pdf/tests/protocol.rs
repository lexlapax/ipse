use lopdf::{Document, Object, Stream, dictionary};
use std::io::{Read, Write};
use std::process::{Child, Command, Stdio};
use std::time::{Duration, Instant};

fn pdf(contents: &[&[u8]]) -> Vec<u8> {
    let mut document = Document::with_version("1.5");
    let pages = document.new_object_id();
    let font = document
        .add_object(dictionary! {"Type"=>"Font", "Subtype"=>"Type1", "BaseFont"=>"Helvetica"});
    let mut children = Vec::new();
    for content in contents {
        let mut stream = Stream::new(dictionary! {}, content.to_vec());
        stream.compress().unwrap();
        let content = document.add_object(stream);
        let page = document.add_object(dictionary! {"Type"=>"Page", "Parent"=>pages, "Contents"=>content,
            "Resources"=>dictionary! {"Font"=>dictionary! {"F1"=>font}}, "MediaBox"=>vec![0.into(),0.into(),200.into(),100.into()]});
        children.push(page.into());
    }
    document.objects.insert(
        pages,
        Object::Dictionary(
            dictionary! {"Type"=>"Pages", "Kids"=>children, "Count"=>contents.len() as i64},
        ),
    );
    let catalog = document.add_object(dictionary! {"Type"=>"Catalog", "Pages"=>pages});
    document.trailer.set("Root", catalog);
    let mut bytes = Vec::new();
    document.save_to(&mut bytes).unwrap();
    bytes
}

fn command() -> Child {
    Command::new(env!("CARGO_BIN_EXE_ipse-pdf"))
        .env_clear()
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .stderr(Stdio::null())
        .spawn()
        .unwrap()
}

fn send(child: &mut Child, bytes: &[u8], pages: u32, expanded: u32, text: u32) {
    let input = child.stdin.as_mut().unwrap();
    input.write_all(b"IPDF0001").unwrap();
    for value in [pages, expanded, text, bytes.len() as u32] {
        input.write_all(&value.to_be_bytes()).unwrap();
    }
    input.write_all(bytes).unwrap();
}

fn finish(child: &mut Child) -> Vec<u8> {
    let stdout = child.stdout.take().unwrap();
    let reader = std::thread::spawn(move || {
        let mut output = Vec::new();
        stdout.take(2 << 20).read_to_end(&mut output).unwrap();
        output
    });
    let deadline = Instant::now() + Duration::from_secs(7);
    while child.try_wait().unwrap().is_none() {
        if Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            panic!("parser exceeded its wall deadline");
        }
        std::thread::sleep(Duration::from_millis(5));
    }
    reader.join().unwrap()
}

fn run(bytes: &[u8], pages: u32, expanded: u32, text: u32) -> Vec<u8> {
    let mut child = command();
    send(&mut child, bytes, pages, expanded, text);
    finish(&mut child)
}

fn backend_available() -> bool {
    let output = run(
        &pdf(&[b"BT /F1 12 Tf (backend) Tj ET"]),
        256,
        32 << 20,
        1 << 20,
    );
    if cfg!(target_os = "macos") && output.get(8) == Some(&10) {
        assert_eq!(output.len(), 13);
        eprintln!("PDF address-space backend unavailable; fail-closed refusal verified.");
        false
    } else {
        assert_eq!(output[8], 0);
        true
    }
}

#[test]
fn separate_worker_extracts_real_pdf_and_preserves_partial_page_outcomes() {
    if !backend_available() {
        return;
    }
    let output = run(
        &pdf(&[b"BT /F1 12 Tf (retained evidence) Tj ET", b""]),
        256,
        32 << 20,
        1 << 20,
    );
    assert_eq!(&output[..8], b"IPDO0001");
    assert_eq!(output[8], 1);
    assert_eq!(u32::from_be_bytes(output[9..13].try_into().unwrap()), 2);
    assert!(
        output
            .windows(17)
            .any(|bytes| bytes == b"retained evidence")
    );
    assert_eq!(output[output.len() - 5], 1);
}

#[test]
fn malformed_image_only_expansion_text_and_page_ceilings_are_explicit() {
    if !backend_available() {
        return;
    }
    assert_eq!(run(b"not PDF", 256, 32 << 20, 1 << 20)[8], 4);
    assert_eq!(run(&pdf(&[b""]), 256, 32 << 20, 1 << 20)[8], 2);
    assert_eq!(
        run(&pdf(&[b"BT /F1 12 Tf (long text) Tj ET"]), 256, 32 << 20, 1)[8],
        8
    );
    assert_eq!(run(&pdf(&[b"", b""]), 1, 32 << 20, 1 << 20)[8], 7);
    let bomb = vec![b' '; 2 << 20];
    assert_eq!(run(&pdf(&[&bomb]), 256, 1024, 1 << 20)[8], 5);
}

#[test]
fn encrypted_even_with_empty_password_and_embedded_objects_are_refused() {
    if !backend_available() {
        return;
    }
    use lopdf::{EncryptionState, EncryptionVersion, Permissions};
    for password in ["", "secret"] {
        let mut document = Document::load_mem(&pdf(&[b"BT /F1 12 Tf (private) Tj ET"])).unwrap();
        document.trailer.set(
            "ID",
            vec![
                Object::string_literal(b"development-id-1".to_vec()),
                Object::string_literal(b"development-id-1".to_vec()),
            ],
        );
        let state = EncryptionState::try_from(EncryptionVersion::V2 {
            document: &document,
            owner_password: "owner",
            user_password: password,
            key_length: 128,
            permissions: Permissions::all(),
        })
        .unwrap();
        document.encrypt(&state).unwrap();
        let mut bytes = Vec::new();
        document.save_to(&mut bytes).unwrap();
        assert_eq!(run(&bytes, 256, 32 << 20, 1 << 20)[8], 3);
    }
    let mut document = Document::load_mem(&pdf(&[b"BT /F1 12 Tf (evidence) Tj ET"])).unwrap();
    document.add_object(Stream::new(
        dictionary! {"Type"=>"EmbeddedFile"},
        b"attachment".to_vec(),
    ));
    let mut bytes = Vec::new();
    document.save_to(&mut bytes).unwrap();
    assert_eq!(run(&bytes, 256, 32 << 20, 1 << 20)[8], 9);
}

#[test]
fn unfinished_input_has_a_finite_deadline() {
    let mut child = command();
    child.stdin.as_mut().unwrap().write_all(b"IPDF").unwrap();
    assert_eq!(finish(&mut child)[8], 5);
}

#[test]
fn extra_request_bytes_are_a_protocol_refusal() {
    if !backend_available() {
        return;
    }
    let bytes = pdf(&[b"BT /F1 12 Tf (fixture) Tj ET"]);
    let mut child = command();
    send(&mut child, &bytes, 256, 32 << 20, 1 << 20);
    child
        .stdin
        .as_mut()
        .unwrap()
        .write_all(b"unexpected")
        .unwrap();
    assert_eq!(finish(&mut child)[8], 6);
}

#[test]
fn large_output_drains_and_a_nonreading_owner_cannot_keep_the_helper_alive() {
    if !backend_available() {
        return;
    }
    let mut content = b"BT /F1 12 Tf (".to_vec();
    content.extend(vec![b'a'; 150_000]);
    content.extend_from_slice(b") Tj ET");
    let bytes = pdf(&[&content]);
    let output = run(&bytes, 256, 32 << 20, 1 << 20);
    assert_eq!(output[8], 0);
    assert!(output.len() > 150_000);
    let mut child = command();
    send(&mut child, &bytes, 256, 32 << 20, 1 << 20);
    let deadline = Instant::now() + Duration::from_secs(7);
    while child.try_wait().unwrap().is_none() {
        if Instant::now() >= deadline {
            let _ = child.kill();
            let _ = child.wait();
            panic!("unread stdout escaped deadline");
        }
        std::thread::sleep(Duration::from_millis(10));
    }
}

#[test]
fn lease_readiness_precedes_any_job_and_locks_remain_until_exit() {
    let root = std::env::temp_dir().join(format!("ipse-parser-lease-{}", std::process::id()));
    std::fs::create_dir_all(&root).unwrap();
    let lock = root.join("lock");
    let mut child = Command::new(env!("CARGO_BIN_EXE_ipse-pdf"))
        .args(["--lease", lock.to_str().unwrap()])
        .stdin(Stdio::piped())
        .stdout(Stdio::piped())
        .spawn()
        .unwrap();
    let mut marker = [0; 8];
    child
        .stdout
        .as_mut()
        .unwrap()
        .read_exact(&mut marker)
        .unwrap();
    assert_eq!(&marker, b"IPLEASE1");
    let check = || {
        Command::new(env!("CARGO_BIN_EXE_ipse-pdf"))
            .args(["--lease-check", lock.to_str().unwrap()])
            .output()
            .unwrap()
    };
    assert!(!check().status.success());
    drop(child.stdin.take());
    finish(&mut child);
    let output = check();
    assert!(output.status.success());
    assert_eq!(&output.stdout, b"QUIESCENT\n");
    std::fs::remove_dir_all(root).unwrap();
}

#[test]
fn nested_attachments_and_inconsistent_or_duplicate_page_trees_refuse() {
    if !backend_available() {
        return;
    }
    let original = pdf(&[b"BT /F1 12 Tf (retained) Tj ET"]);
    let mut document = Document::load_mem(&original).unwrap();
    let catalog = document
        .trailer
        .get(b"Root")
        .unwrap()
        .as_reference()
        .unwrap();
    document.get_object_mut(catalog).unwrap().as_dict_mut().unwrap().set("Names",
        dictionary! {"EmbeddedFiles"=>dictionary! {"Names"=>vec![Object::string_literal(b"attachment".to_vec()), Object::Dictionary(dictionary! {"Type"=>"Filespec", "EF"=>dictionary! {"F"=>Object::Null}})]}});
    let mut bytes = Vec::new();
    document.save_to(&mut bytes).unwrap();
    assert_eq!(run(&bytes, 256, 32 << 20, 1 << 20)[8], 9);
    for invalid in [0, 1, 2] {
        let mut document = Document::load_mem(&original).unwrap();
        let catalog = document
            .trailer
            .get(b"Root")
            .unwrap()
            .as_reference()
            .unwrap();
        let pages = document
            .get_dictionary(catalog)
            .unwrap()
            .get(b"Pages")
            .unwrap()
            .as_reference()
            .unwrap();
        let page = *document.get_pages().values().next().unwrap();
        let dictionary = document
            .get_object_mut(pages)
            .unwrap()
            .as_dict_mut()
            .unwrap();
        dictionary.set(
            "Kids",
            match invalid {
                0 => vec![Object::Null, page.into()],
                1 => vec![page.into(), page.into()],
                _ => vec![page.into(); 300],
            },
        );
        dictionary.set("Count", if invalid == 2 { 300 } else { 2 });
        let mut bytes = Vec::new();
        document.save_to(&mut bytes).unwrap();
        assert_eq!(
            run(&bytes, 10, 32 << 20, 1 << 20)[8],
            if invalid == 2 { 7 } else { 4 }
        );
    }
}

#[cfg(target_os = "linux")]
fn worker(child: &Child) -> u32 {
    let deadline = Instant::now() + Duration::from_secs(1);
    loop {
        let path = format!("/proc/{}/task/{}/children", child.id(), child.id());
        if let Ok(value) = std::fs::read_to_string(path) {
            if let Some(pid) = value.split_whitespace().next() {
                return pid.parse().unwrap();
            }
        }
        assert!(Instant::now() < deadline, "parser worker did not start");
        std::thread::sleep(Duration::from_millis(1));
    }
}

#[cfg(target_os = "linux")]
fn stopped(pid: u32) {
    let deadline = Instant::now() + Duration::from_secs(1);
    loop {
        let state = std::fs::read_to_string(format!("/proc/{pid}/stat"));
        if state
            .as_ref()
            .map_or(true, |value| value.split_whitespace().nth(2) == Some("Z"))
        {
            return;
        }
        assert!(
            Instant::now() < deadline,
            "parser worker survived owner cancellation"
        );
        std::thread::sleep(Duration::from_millis(5));
    }
}

#[cfg(target_os = "linux")]
#[test]
fn stdin_closure_and_supervisor_death_stop_the_parser_worker() {
    if !backend_available() {
        return;
    }
    let content = b"() Tj ".repeat(700_000);
    let bytes = pdf(&[&content]);
    let mut child = command();
    send(&mut child, &bytes, 256, 32 << 20, 1 << 20);
    let pid = worker(&child);
    let limits = std::fs::read_to_string(format!("/proc/{pid}/limits")).unwrap();
    for (prefix, offset, expected) in [
        ("Max cpu time", 3, "4"),
        ("Max address space", 3, "402653184"),
        ("Max core file size", 4, "0"),
    ] {
        let row: Vec<_> = limits
            .lines()
            .find(|line| line.starts_with(prefix))
            .unwrap()
            .split_whitespace()
            .collect();
        assert_eq!(row[offset], expected);
        assert_eq!(row[offset + 1], expected);
    }
    drop(child.stdin.take());
    let output = finish(&mut child);
    assert!(output.is_empty() || output[8] == 5);
    stopped(pid);

    let mut child = command();
    send(&mut child, &bytes, 256, 32 << 20, 1 << 20);
    let pid = worker(&child);
    child.kill().unwrap();
    child.wait().unwrap();
    stopped(pid);
}
