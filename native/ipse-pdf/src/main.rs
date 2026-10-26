use lopdf::{Document, LoadOptions, Object};
use std::io::{Read, Write};
use std::process::{Command, Stdio};
use std::time::{Duration, Instant};

const INPUT: usize = 16 * 1024 * 1024;
const EXPANDED: usize = 32 * 1024 * 1024;
const TEXT: usize = 1024 * 1024;
const PAGES: usize = 256;
const OUTPUT: usize = TEXT + PAGES * 9 + 13;
const MAGIC_IN: &[u8; 8] = b"IPDF0001";
const MAGIC_OUT: &[u8; 8] = b"IPDO0001";
const COMPLETE: u8 = 0;
const PARTIAL: u8 = 1;
const IMAGE_ONLY: u8 = 2;
const ENCRYPTED: u8 = 3;
const MALFORMED: u8 = 4;
const RESOURCE: u8 = 5;
const PROTOCOL: u8 = 6;
const PAGE_LIMIT: u8 = 7;
const TEXT_LIMIT: u8 = 8;
const EMBEDDED: u8 = 9;

#[derive(Clone, Copy)]
struct Limits {
    pages: usize,
    expanded: usize,
    text: usize,
}
struct Request {
    limits: Limits,
    bytes: Vec<u8>,
}

fn error(code: u8) -> Vec<u8> {
    let mut bytes = MAGIC_OUT.to_vec();
    bytes.push(code);
    bytes.extend_from_slice(&0_u32.to_be_bytes());
    bytes
}

fn decode_request(header: &[u8; 24]) -> Result<(Limits, usize), u8> {
    let n = |offset| u32::from_be_bytes(header[offset..offset + 4].try_into().unwrap()) as usize;
    let limits = Limits {
        pages: n(8),
        expanded: n(12),
        text: n(16),
    };
    let size = n(20);
    if &header[..8] != MAGIC_IN
        || size == 0
        || size > INPUT
        || limits.pages == 0
        || limits.pages > PAGES
        || limits.expanded == 0
        || limits.expanded > EXPANDED
        || limits.text == 0
        || limits.text > TEXT
    {
        return Err(PROTOCOL);
    }
    Ok((limits, size))
}

fn extraction(request: &Request) -> Result<Vec<u8>, u8> {
    let mut document = Document::load_mem_with_options(
        &request.bytes,
        LoadOptions {
            strict: true,
            max_decompressed_size: Some(request.limits.expanded),
            ..Default::default()
        },
    )
    .map_err(classify)?;
    if document.was_encrypted() || document.trailer.has(b"Encrypt") {
        return Err(ENCRYPTED);
    }
    if document.objects.len() > 100_000 {
        return Err(RESOURCE);
    }
    // Retained non-image streams are decoded once against an aggregate envelope.
    // Load-time xref/object streams have the library's per-stream cap; the OS
    // address-space and CPU ceilings contain their combined parse cost.
    let mut expanded = 0_usize;
    for object in document.objects.values_mut() {
        let dictionary = match object {
            Object::Dictionary(dictionary) => Some(&*dictionary),
            Object::Stream(stream) => Some(&stream.dict),
            _ => None,
        };
        if let Some(dictionary) = dictionary {
            let kind = dictionary
                .get(b"Type")
                .and_then(Object::as_name)
                .unwrap_or_default();
            if kind == b"EmbeddedFile" || kind == b"Filespec" || dictionary.has(b"EmbeddedFiles") {
                return Err(EMBEDDED);
            }
        }
        if let Object::Stream(stream) = object {
            if stream.dict.get(b"Subtype").and_then(Object::as_name).ok() == Some(b"Image") {
                continue;
            }
            if stream.dict.has(b"Filter") {
                stream
                    .decompress_with_limit(request.limits.expanded.saturating_sub(expanded))
                    .map_err(classify)?;
            }
            expanded = expanded.checked_add(stream.content.len()).ok_or(RESOURCE)?;
            if expanded > request.limits.expanded {
                return Err(RESOURCE);
            }
        }
    }
    let pages = document.get_pages();
    if pages.is_empty() {
        return Err(MALFORMED);
    }
    if pages.len() > request.limits.pages {
        return Err(PAGE_LIMIT);
    }
    let mut rows = Vec::new();
    let mut text_bytes = 0_usize;
    let mut supported = 0_usize;
    let mut failures = 0_usize;
    let mut partial = false;
    for number in pages.keys() {
        let (status, text) =
            match document.extract_text_with_limit(&[*number], request.limits.expanded) {
                Ok(text) if !text.trim().is_empty() => {
                    text_bytes = text_bytes.checked_add(text.len()).ok_or(TEXT_LIMIT)?;
                    if text_bytes > request.limits.text {
                        return Err(TEXT_LIMIT);
                    }
                    supported += 1;
                    (0_u8, text)
                }
                Ok(_) => {
                    partial = true;
                    (1_u8, String::new())
                }
                Err(lopdf::Error::Decompress(lopdf::DecompressError::MemoryLimitExceeded {
                    ..
                })) => return Err(RESOURCE),
                Err(_) => {
                    partial = true;
                    failures += 1;
                    (2_u8, String::new())
                }
            };
        rows.extend_from_slice(&number.to_be_bytes());
        rows.push(status);
        rows.extend_from_slice(&(text.len() as u32).to_be_bytes());
        rows.extend_from_slice(text.as_bytes());
    }
    if supported == 0 {
        return Err(if failures == 0 { IMAGE_ONLY } else { MALFORMED });
    }
    let mut output = MAGIC_OUT.to_vec();
    output.push(if partial { PARTIAL } else { COMPLETE });
    output.extend_from_slice(&(pages.len() as u32).to_be_bytes());
    output.extend_from_slice(&rows);
    Ok(output)
}

fn classify(error: lopdf::Error) -> u8 {
    match error {
        lopdf::Error::Decryption(_)
        | lopdf::Error::InvalidPassword
        | lopdf::Error::UnsupportedSecurityHandler(_) => ENCRYPTED,
        lopdf::Error::Decompress(lopdf::DecompressError::MemoryLimitExceeded { .. }) => RESOURCE,
        _ => MALFORMED,
    }
}

#[cfg(any(target_os = "linux", target_os = "macos"))]
mod platform {
    use super::*;
    use std::ffi::c_int;
    use std::os::fd::FromRawFd;
    use std::os::unix::process::CommandExt;
    #[repr(C)]
    struct Rlimit {
        current: u64,
        maximum: u64,
    }
    #[repr(C)]
    struct Poll {
        fd: c_int,
        events: i16,
        revents: i16,
    }
    unsafe extern "C" {
        fn setrlimit(resource: c_int, value: *const Rlimit) -> c_int;
        fn poll(fds: *mut Poll, count: usize, timeout: c_int) -> c_int;
        fn getppid() -> c_int;
    }
    #[cfg(target_os = "linux")]
    const ADDRESS_SPACE: c_int = 9;
    #[cfg(target_os = "macos")]
    const ADDRESS_SPACE: c_int = 5;

    pub fn restrict() -> std::io::Result<()> {
        for (resource, maximum) in [(0, 4), (ADDRESS_SPACE, 384 * 1024 * 1024), (4, 0)] {
            let value = Rlimit {
                current: maximum,
                maximum,
            };
            if unsafe { setrlimit(resource, &value) } != 0 {
                return Err(std::io::Error::last_os_error());
            }
        }
        Ok(())
    }
    fn read_exact(input: &mut impl Read, bytes: &mut [u8], deadline: Instant) -> Result<(), u8> {
        let mut offset = 0;
        while offset < bytes.len() {
            let remaining = deadline.saturating_duration_since(Instant::now());
            if remaining.is_zero() {
                return Err(RESOURCE);
            }
            let mut descriptor = Poll {
                fd: 0,
                events: 1,
                revents: 0,
            };
            let result =
                unsafe { poll(&mut descriptor, 1, remaining.as_millis().min(100) as c_int) };
            if result < 0 {
                return Err(PROTOCOL);
            }
            if result == 0 {
                continue;
            }
            let count = input.read(&mut bytes[offset..]).map_err(|_| PROTOCOL)?;
            if count == 0 {
                return Err(PROTOCOL);
            }
            offset += count;
        }
        Ok(())
    }
    fn request(deadline: Instant) -> Result<Request, u8> {
        // StdinLock may read ahead: polling fd 0 again would then wait while
        // the requested body already sits in its private buffer. Keep raw fd 0
        // open for the supervisor's subsequent owner-liveness polling.
        let mut input = std::mem::ManuallyDrop::new(unsafe { std::fs::File::from_raw_fd(0) });
        let mut header = [0_u8; 24];
        read_exact(&mut *input, &mut header, deadline)?;
        let (limits, size) = decode_request(&header)?;
        let mut bytes = vec![0; size];
        read_exact(&mut *input, &mut bytes, deadline)?;
        Ok(Request { limits, bytes })
    }
    pub fn worker(parent: u32) -> Vec<u8> {
        if restrict().is_err() {
            return error(RESOURCE);
        }
        if unsafe { getppid() } as u32 != parent {
            return error(RESOURCE);
        }
        std::thread::spawn(move || {
            let deadline = Instant::now() + Duration::from_secs(5);
            loop {
                if unsafe { getppid() } as u32 != parent || Instant::now() >= deadline {
                    std::process::exit(70);
                }
                std::thread::sleep(Duration::from_millis(10));
            }
        });
        match request(Instant::now() + Duration::from_secs(5))
            .and_then(|request| extraction(&request))
        {
            Ok(output) => output,
            Err(code) => error(code),
        }
    }
    pub fn supervisor() -> Vec<u8> {
        let deadline = Instant::now() + Duration::from_secs(5);
        let request = match request(deadline) {
            Ok(request) => request,
            Err(code) => return error(code),
        };
        let executable = match std::env::current_exe() {
            Ok(path) => path,
            Err(_) => return error(RESOURCE),
        };
        let mut command = Command::new(executable);
        command
            .arg("--worker")
            .arg(std::process::id().to_string())
            .env_clear()
            .current_dir("/")
            .stdin(Stdio::piped())
            .stdout(Stdio::piped())
            .stderr(Stdio::null());
        // Limits apply before the parser starts and again in direct worker mode.
        unsafe {
            command.pre_exec(restrict);
        }
        let mut child = match command.spawn() {
            Ok(child) => child,
            Err(_) => return error(RESOURCE),
        };
        let input = child.stdin.take().unwrap();
        let stdout = child.stdout.take().unwrap();
        let writer = std::thread::spawn(move || {
            let mut input = input;
            input.write_all(MAGIC_IN)?;
            for value in [
                request.limits.pages,
                request.limits.expanded,
                request.limits.text,
                request.bytes.len(),
            ] {
                input.write_all(&(value as u32).to_be_bytes())?;
            }
            input.write_all(&request.bytes)
        });
        let reader = std::thread::spawn(move || {
            let mut output = Vec::new();
            stdout
                .take((OUTPUT + 1) as u64)
                .read_to_end(&mut output)
                .map(|_| output)
        });
        let mut good = false;
        loop {
            let mut input = Poll {
                fd: 0,
                events: 1,
                revents: 0,
            };
            let polled = unsafe { poll(&mut input, 1, 10) };
            // EOF/HUP means the owning Port disappeared. Extra bytes are a
            // protocol failure, never another request or an execution command.
            if Instant::now() >= deadline || polled < 0 || input.revents != 0 {
                break;
            }
            match child.try_wait() {
                Ok(Some(status)) => {
                    good = status.success();
                    break;
                }
                Ok(None) => {}
                Err(_) => break,
            }
        }
        if !good {
            let _ = child.kill();
        }
        let _ = child.wait();
        let written = writer.join().ok().is_some_and(|result| result.is_ok());
        let output = reader.join().ok().and_then(Result::ok);
        match output {
            Some(output) if good && written && output.len() <= OUTPUT => output,
            _ => error(RESOURCE),
        }
    }
}

fn main() {
    std::panic::set_hook(Box::new(|_| {}));
    #[cfg(any(target_os = "linux", target_os = "macos"))]
    let output = match std::env::args().nth(1).as_deref() {
        None => platform::supervisor(),
        Some("--worker") if std::env::args().len() == 3 => std::env::args()
            .nth(2)
            .and_then(|value| value.parse::<u32>().ok())
            .map(platform::worker)
            .unwrap_or_else(|| error(PROTOCOL)),
        _ => error(PROTOCOL),
    };
    #[cfg(not(any(target_os = "linux", target_os = "macos")))]
    let output = error(RESOURCE);
    let _ = std::io::stdout().lock().write_all(&output);
}

#[cfg(test)]
mod tests {
    use super::*;
    use lopdf::{Stream, dictionary};
    fn pdf(text: Option<&str>) -> Vec<u8> {
        let mut document = Document::with_version("1.5");
        let pages = document.new_object_id();
        let font = document.add_object(
            dictionary! {"Type" => "Font", "Subtype" => "Type1", "BaseFont" => "Helvetica"},
        );
        let content = text
            .map(|text| format!("BT /F1 12 Tf 20 50 Td ({text}) Tj ET"))
            .unwrap_or_default();
        let content = document.add_object(Stream::new(dictionary! {}, content.into_bytes()));
        let page = document.add_object(dictionary! {"Type"=>"Page", "Parent"=>pages, "Contents"=>content,
            "Resources"=>dictionary! {"Font"=>dictionary! {"F1"=>font}}, "MediaBox"=>vec![0.into(),0.into(),200.into(),100.into()]});
        document.objects.insert(
            pages,
            Object::Dictionary(
                dictionary! {"Type"=>"Pages", "Kids"=>vec![page.into()], "Count"=>1},
            ),
        );
        let catalog = document.add_object(dictionary! {"Type"=>"Catalog", "Pages"=>pages});
        document.trailer.set("Root", catalog);
        let mut bytes = Vec::new();
        document.save_to(&mut bytes).unwrap();
        bytes
    }
    fn request(bytes: Vec<u8>) -> Request {
        Request {
            limits: Limits {
                pages: PAGES,
                expanded: EXPANDED,
                text: TEXT,
            },
            bytes,
        }
    }
    #[test]
    fn actual_pdf_text_and_page_frame() {
        let output = extraction(&request(pdf(Some("independent fixture")))).unwrap();
        assert_eq!(&output[..8], MAGIC_OUT);
        assert_eq!(output[8], COMPLETE);
        assert_eq!(u32::from_be_bytes(output[9..13].try_into().unwrap()), 1);
        assert_eq!(u32::from_be_bytes(output[13..17].try_into().unwrap()), 1);
        assert!(
            std::str::from_utf8(&output[22..])
                .unwrap()
                .contains("independent fixture")
        );
    }
    #[test]
    fn image_only_malformed_and_text_limits_are_explicit() {
        assert_eq!(extraction(&request(pdf(None))).unwrap_err(), IMAGE_ONLY);
        assert_eq!(
            extraction(&request(b"not a PDF".to_vec())).unwrap_err(),
            MALFORMED
        );
        let mut value = request(pdf(Some("too much text")));
        value.limits.text = 1;
        assert_eq!(extraction(&value).unwrap_err(), TEXT_LIMIT);
    }
    #[test]
    fn input_protocol_cannot_raise_limits() {
        let mut header = [0; 24];
        header[..8].copy_from_slice(MAGIC_IN);
        for (offset, value) in [(8, PAGES), (12, EXPANDED), (16, TEXT), (20, 1)] {
            header[offset..offset + 4].copy_from_slice(&(value as u32).to_be_bytes());
        }
        assert!(decode_request(&header).is_ok());
        header[8..12].copy_from_slice(&((PAGES + 1) as u32).to_be_bytes());
        assert!(matches!(decode_request(&header), Err(PROTOCOL)));
    }
}
