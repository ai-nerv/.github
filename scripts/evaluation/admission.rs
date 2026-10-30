use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::fd::AsRawFd;
use std::os::unix::fs::{OpenOptionsExt, PermissionsExt};
use std::os::unix::net::{UnixListener, UnixStream};
use std::path::Path;
use std::time::{Duration, Instant};

const PEERS: usize = 8;
const FRAME: usize = 128;
const CALLS: u32 = 128;
const JOURNAL: usize = 65536;
const DEADLINE: Duration = Duration::from_millis(250);

#[repr(C)]
struct Credentials {
    pid: i32,
    uid: u32,
    gid: u32,
}

unsafe extern "C" {
    fn getsockopt(
        fd: i32,
        level: i32,
        option: i32,
        value: *mut std::ffi::c_void,
        len: *mut u32,
    ) -> i32;
    fn getuid() -> u32;
}

fn error(message: &str) -> io::Error {
    io::Error::other(message)
}

struct Peer {
    stream: UnixStream,
    pid: i32,
    input: Vec<u8>,
    output: Vec<u8>,
    started: Instant,
}

impl Peer {
    fn new(stream: UnixStream) -> io::Result<Self> {
        let mut peer = Credentials {
            pid: 0,
            uid: 0,
            gid: 0,
        };
        let mut size = std::mem::size_of::<Credentials>() as u32;
        if unsafe {
            getsockopt(
                stream.as_raw_fd(),
                1,
                17,
                (&mut peer as *mut Credentials).cast(),
                &mut size,
            )
        } != 0
            || size != std::mem::size_of::<Credentials>() as u32
            || peer.uid != unsafe { getuid() }
            || peer.pid <= 0
        {
            return Err(error("admission peer identity refused"));
        }
        stream.set_nonblocking(true)?;
        Ok(Self {
            stream,
            pid: peer.pid,
            input: Vec::new(),
            output: Vec::new(),
            started: Instant::now(),
        })
    }

    fn reply(&mut self, body: &str) {
        self.output
            .extend_from_slice(&(body.len() as u32).to_be_bytes());
        self.output.extend_from_slice(body.as_bytes());
        self.input.clear();
    }

    fn active(&self) -> bool {
        !self.input.is_empty() || !self.output.is_empty()
    }
}

pub struct Broker {
    listener: UnixListener,
    peers: Vec<Peer>,
    journal: File,
    bytes: usize,
    limit: u32,
    admitted: u32,
    calls: u32,
    failed: bool,
}

impl Broker {
    pub fn configured(
        control: &Path,
        directory: &Path,
        journal: &Path,
    ) -> io::Result<Option<Self>> {
        let file = match File::open(control) {
            Ok(file) => file,
            Err(why) if why.kind() == io::ErrorKind::NotFound => return Ok(None),
            Err(why) => return Err(why),
        };
        let mut text = String::new();
        file.take(4).read_to_string(&mut text)?;
        let limit: u32 = text
            .trim_end_matches('\n')
            .parse()
            .map_err(|_| error("invalid client attempt limit"))?;
        if !(1..=64).contains(&limit) || text != format!("{limit}\n") {
            return Err(error("invalid client attempt limit"));
        }
        Self::new(directory, journal, limit).map(Some)
    }

    fn new(directory: &Path, journal: &Path, limit: u32) -> io::Result<Self> {
        fs::create_dir_all(directory)?;
        fs::set_permissions(directory, fs::Permissions::from_mode(0o700))?;
        let path = directory.join("admission.sock");
        let listener = UnixListener::bind(&path)?;
        fs::set_permissions(path, fs::Permissions::from_mode(0o600))?;
        listener.set_nonblocking(true)?;
        let journal = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(0o600)
            .open(journal)?;
        let mut broker = Self {
            listener,
            peers: Vec::new(),
            journal,
            bytes: 0,
            limit,
            admitted: 0,
            calls: 0,
            failed: false,
        };
        broker.record(&format!("{{\"schema\":1,\"scope\":\"offline-client-admission\",\"event\":\"start\",\"limit\":{limit},\"max_peers\":{PEERS},\"max_frame_bytes\":{FRAME},\"max_calls\":{CALLS},\"frame_timeout_ms\":250}}"))?;
        Ok(broker)
    }

    fn record(&mut self, line: &str) -> io::Result<()> {
        if self.bytes + line.len() + 1 > JOURNAL - 1024 {
            return Err(error("client admission journal limit"));
        }
        writeln!(self.journal, "{line}")?;
        self.journal.sync_data()?;
        self.bytes += line.len() + 1;
        Ok(())
    }

    fn request(&mut self, peer: &mut Peer) -> io::Result<()> {
        self.calls += 1;
        if self.calls > CALLS {
            return Err(error("client admission call limit"));
        }
        match &peer.input[4..] {
            b"{\"call\":\"verbs\"}" => {
                peer.reply("{\"ok\":true,\"n\":1,\"result\":[[\"reserve\",\"verbs\"]]}")
            }
            b"{\"call\":\"reserve\"}" => {
                if self.admitted == self.limit {
                    self.record(&format!(
                        "{{\"event\":\"reject\",\"reason\":\"attempt_limit\",\"peer_pid\":{}}}",
                        peer.pid
                    ))?;
                    self.failed = true;
                    peer.reply("{\"ok\":false,\"error\":\"attempt_limit\"}");
                } else {
                    self.admitted += 1;
                    self.record(&format!(
                        "{{\"event\":\"admit\",\"attempt\":{},\"peer_pid\":{}}}",
                        self.admitted, peer.pid
                    ))?;
                    peer.reply(&format!(
                        "{{\"ok\":true,\"n\":1,\"result\":[{}]}}",
                        self.admitted
                    ));
                }
            }
            _ => return Err(error("unsupported client admission frame")),
        }
        Ok(())
    }

    fn advance(&mut self, peer: &mut Peer) -> io::Result<bool> {
        if peer.started.elapsed() >= DEADLINE {
            return if peer.active() {
                Err(error("partial client admission frame timed out"))
            } else {
                Ok(false)
            };
        }
        if !peer.output.is_empty() {
            match peer.stream.write(&peer.output) {
                Ok(0) => return Err(error("client admission reply closed")),
                Ok(count) => {
                    peer.output.drain(..count);
                }
                Err(why) if why.kind() == io::ErrorKind::WouldBlock => {}
                Err(why) => return Err(why),
            }
            if peer.output.is_empty() {
                peer.started = Instant::now();
            }
            return Ok(true);
        }
        let expected = if peer.input.len() < 4 {
            4
        } else {
            let size = u32::from_be_bytes(peer.input[..4].try_into().unwrap()) as usize;
            if size == 0 || size > FRAME {
                return Err(error("client admission frame size"));
            }
            size + 4
        };
        let mut buffer = [0; FRAME + 4];
        match peer.stream.read(&mut buffer[..expected - peer.input.len()]) {
            Ok(0) if peer.input.is_empty() => return Ok(false),
            Ok(0) => return Err(error("partial client admission frame closed")),
            Ok(count) => {
                if peer.input.is_empty() {
                    peer.started = Instant::now();
                }
                peer.input.extend_from_slice(&buffer[..count]);
            }
            Err(why) if why.kind() == io::ErrorKind::WouldBlock => return Ok(true),
            Err(why) => return Err(why),
        }
        if expected > 4 && peer.input.len() == expected {
            self.request(peer)?;
        }
        Ok(true)
    }

    fn poll_inner(&mut self) -> io::Result<()> {
        for mut peer in std::mem::take(&mut self.peers) {
            if self.advance(&mut peer)? {
                self.peers.push(peer);
            }
            if self.failed {
                return Ok(());
            }
        }
        for _ in 0..=PEERS {
            match self.listener.accept() {
                Ok((stream, _)) => {
                    if self.peers.len() == PEERS {
                        return Err(error("client admission connection limit"));
                    }
                    self.peers.push(Peer::new(stream)?);
                }
                Err(why) if why.kind() == io::ErrorKind::WouldBlock => break,
                Err(why) => return Err(why),
            }
        }
        Ok(())
    }

    pub fn poll(&mut self) {
        if !self.failed {
            if let Err(why) = self.poll_inner() {
                eprintln!("evaluation client admission: {why}");
                self.failed = true;
            }
        }
    }

    pub fn failed(&self) -> bool {
        self.failed
    }

    pub fn finish(mut self) -> io::Result<bool> {
        self.failed |= self.peers.iter().any(Peer::active);
        let status = if self.failed { "FAIL" } else { "STOPPED" };
        self.record(&format!(
            "{{\"event\":\"terminal\",\"status\":\"{status}\",\"admitted\":{},\"calls\":{}}}",
            self.admitted, self.calls
        ))?;
        Ok(!self.failed)
    }
}

#[cfg(test)]
#[path = "admission_tests.rs"]
mod tests;
