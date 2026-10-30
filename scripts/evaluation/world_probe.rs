use std::fs::{self, OpenOptions};
use std::io::{self, Read, Write};
use std::net::{SocketAddr, TcpListener, TcpStream};
use std::os::unix::net::UnixStream;
use std::time::Duration;

unsafe extern "C" {
    fn mount(
        source: *const u8,
        target: *const u8,
        kind: *const u8,
        flags: usize,
        data: *const u8,
    ) -> i32;
}

fn run() -> io::Result<()> {
    let args: Vec<_> = std::env::args().skip(1).collect();
    match args.first().map(String::as_str) {
        Some("reserve") | Some("admission-partial") => {
            let path = "/world/runtime/melchior/.evaluation-admission/admission.sock";
            let mut stream = UnixStream::connect(path)?;
            stream.set_read_timeout(Some(Duration::from_secs(1)))?;
            stream.set_write_timeout(Some(Duration::from_secs(1)))?;
            if args[0] == "admission-partial" {
                stream.write_all(&[0])?;
                std::thread::sleep(Duration::from_secs(2));
                return Err(io::Error::other(
                    "partial admission request did not stop world",
                ));
            }
            if fs::remove_file(path).is_ok() || fs::read("/receipt/client-attempts.jsonl").is_ok() {
                return Err(io::Error::other("admission ownership exposed"));
            }
            let count: u32 = args
                .get(1)
                .ok_or_else(|| io::Error::other("reserve count"))?
                .parse()
                .map_err(io::Error::other)?;
            if !(1..=65).contains(&count) {
                return Err(io::Error::other("reserve count limit"));
            }
            for _ in 0..count {
                let body = br#"{"call":"reserve"}"#;
                stream.write_all(&(body.len() as u32).to_be_bytes())?;
                stream.write_all(body)?;
                let mut header = [0; 4];
                stream.read_exact(&mut header)?;
                let len = u32::from_be_bytes(header) as usize;
                if len > 256 {
                    return Err(io::Error::other("admission reply size"));
                }
                let mut reply = vec![0; len];
                stream.read_exact(&mut reply)?;
                let reply = String::from_utf8(reply).map_err(io::Error::other)?;
                if !reply.starts_with("{\"ok\":true,") {
                    return Err(io::Error::other("admission refused"));
                }
                println!("{reply}");
            }
        }
        Some("listen") => {
            let server = TcpListener::bind("127.0.0.1:0")?;
            fs::write(
                args.get(1).ok_or_else(|| io::Error::other("port file"))?,
                server.local_addr()?.port().to_string(),
            )?;
            for socket in server.incoming() {
                drop(socket?);
            }
        }
        Some("network") => {
            let port: u16 = args
                .get(1)
                .ok_or_else(|| io::Error::other("port"))?
                .parse()
                .map_err(io::Error::other)?;
            if TcpStream::connect_timeout(
                &SocketAddr::from(([127, 0, 0, 1], port)),
                Duration::from_millis(200),
            )
            .is_ok()
            {
                return Err(io::Error::other("host listener reachable"));
            }
            let local = TcpListener::bind("127.0.0.1:0")?;
            let _client = TcpStream::connect(local.local_addr()?)?;
            println!("private-loopback-ok");
        }
        Some("ancestors") => {
            let mut paths = vec![b"/input\0".as_slice(), b"/runner\0".as_slice()];
            if fs::metadata("/family").is_ok() {
                paths.extend([b"/family\0".as_slice(), b"/opt/evaluation\0".as_slice()]);
            }
            if fs::metadata("/opt/evaluation/grammars/bin/rust").is_ok() {
                paths.push(b"/opt/evaluation/grammars/bin/rust\0".as_slice());
                if OpenOptions::new()
                    .write(true)
                    .open("/opt/evaluation/grammars/bin/rust")
                    .is_ok()
                {
                    return Err(io::Error::other("selected grammar is writable"));
                }
            }
            for path in paths {
                if unsafe {
                    mount(
                        std::ptr::null(),
                        path.as_ptr(),
                        std::ptr::null(),
                        32 | 4096,
                        std::ptr::null(),
                    )
                } == 0
                {
                    return Err(io::Error::other(
                        "read-only parent input can be remounted writable",
                    ));
                }
            }
            for entry in fs::read_dir("/proc")? {
                let entry = entry?;
                let Some(pid) = entry
                    .file_name()
                    .to_str()
                    .and_then(|s| s.parse::<u32>().ok())
                else {
                    continue;
                };
                if pid == std::process::id() {
                    continue;
                }
                if fs::read_dir(format!("/proc/{pid}/root/receipt")).is_ok() {
                    return Err(io::Error::other(
                        "protected receipt is reachable through proc",
                    ));
                }
            }
            if OpenOptions::new().write(true).open("/proc/1/fd/1").is_ok() {
                return Err(io::Error::other("supervisor control fd reachable"));
            }
            println!("protected-supervisor-ok");
        }
        Some("orphan") => {
            let _child = std::process::Command::new("/runner/bin/setsid")
                .args(["/runner/bin/sleep", "60"])
                .spawn()?;
            std::thread::sleep(Duration::from_millis(40));
        }
        Some("nested-orphan") => {
            let _child = std::process::Command::new("/runner/bin/bwrap")
                .args([
                    "--unshare-pid",
                    "--ro-bind",
                    "/",
                    "/",
                    "--proc",
                    "/proc",
                    "--",
                    "/runner/bin/sleep",
                    "60",
                ])
                .spawn()?;
            std::thread::sleep(Duration::from_millis(40));
        }
        Some("flood") => {
            for _ in 0..64 {
                io::stdout().write_all(&[b'x'; 65536])?;
            }
        }
        _ => return Err(io::Error::other("unknown world probe")),
    }
    Ok(())
}

fn main() {
    if let Err(error) = run() {
        eprintln!("world probe: {error}");
        std::process::exit(1);
    }
}
