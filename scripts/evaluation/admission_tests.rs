use super::*;
use std::sync::atomic::{AtomicUsize, Ordering};

static NEXT: AtomicUsize = AtomicUsize::new(0);

struct Case(std::path::PathBuf);

impl Case {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!(
            "eval-admission-{}-{}",
            std::process::id(),
            NEXT.fetch_add(1, Ordering::Relaxed)
        ));
        fs::create_dir(&path).unwrap();
        Self(path)
    }

    fn broker(&self, limit: u32) -> Broker {
        Broker::new(&self.0.join("socket"), &self.0.join("journal"), limit).unwrap()
    }

    fn client(&self) -> UnixStream {
        let client = UnixStream::connect(self.0.join("socket/admission.sock")).unwrap();
        client.set_nonblocking(true).unwrap();
        client
    }
}

impl Drop for Case {
    fn drop(&mut self) {
        fs::remove_dir_all(&self.0).unwrap();
    }
}

fn frame(body: &[u8]) -> Vec<u8> {
    [(body.len() as u32).to_be_bytes().as_slice(), body].concat()
}

fn answer(broker: &mut Broker, client: &mut UnixStream, body: &[u8]) -> String {
    client.write_all(&frame(body)).unwrap();
    let until = Instant::now() + Duration::from_secs(1);
    let mut result = Vec::new();
    loop {
        broker.poll();
        let mut buffer = [0; 256];
        match client.read(&mut buffer) {
            Ok(count) => result.extend_from_slice(&buffer[..count]),
            Err(why) if why.kind() == io::ErrorKind::WouldBlock => {}
            Err(why) => panic!("{why}"),
        }
        if result.len() >= 4
            && result.len() == 4 + u32::from_be_bytes(result[..4].try_into().unwrap()) as usize
        {
            return String::from_utf8(result[4..].to_vec()).unwrap();
        }
        assert!(Instant::now() < until && !broker.failed());
        std::thread::sleep(Duration::from_millis(1));
    }
}

#[test]
fn persistent_clients_share_durable_nonrefundable_reservations() {
    let case = Case::new();
    let mut broker = case.broker(3);
    let mut one = case.client();
    assert!(answer(&mut broker, &mut one, br#"{"call":"verbs"}"#).contains("reserve"));
    assert_eq!(broker.admitted, 0);
    for expected in 1..=2 {
        assert_eq!(
            answer(&mut broker, &mut one, br#"{"call":"reserve"}"#),
            format!("{{\"ok\":true,\"n\":1,\"result\":[{expected}]}}")
        );
        let journal = fs::read_to_string(case.0.join("journal")).unwrap();
        assert!(journal.contains(&format!(
            "\"attempt\":{expected},\"peer_pid\":{}",
            std::process::id()
        )));
    }
    drop(one);
    let mut two = case.client();
    assert!(answer(&mut broker, &mut two, br#"{"call":"reserve"}"#).contains("[3]"));
    two.write_all(&frame(br#"{"call":"reserve"}"#)).unwrap();
    for _ in 0..5 {
        broker.poll();
    }
    assert!(broker.failed());
    assert_eq!(broker.admitted, 3);
    assert!(!broker.finish().unwrap());
    let log = fs::read_to_string(case.0.join("journal")).unwrap();
    assert!(log.contains("\"reason\":\"attempt_limit\""));
    assert!(log.contains("\"status\":\"FAIL\",\"admitted\":3"));
    assert!(log.len() < JOURNAL);
}

#[test]
fn fragmented_calls_reserve_only_after_the_complete_frame() {
    let case = Case::new();
    let mut broker = case.broker(2);
    let mut client = case.client();
    let message = frame(br#"{"call":"reserve"}"#);
    for byte in &message[..message.len() - 1] {
        client.write_all(&[*byte]).unwrap();
        broker.poll();
        assert_eq!(broker.admitted, 0);
    }
    client.write_all(&message[message.len() - 1..]).unwrap();
    for _ in 0..4 {
        broker.poll();
    }
    assert_eq!(broker.admitted, 1);
    assert!(broker.finish().unwrap());
}

#[test]
fn malformed_frames_and_forged_peer_fields_fail_closed() {
    for bytes in [
        0u32.to_be_bytes().to_vec(),
        129u32.to_be_bytes().to_vec(),
        frame(br#"{"call":"reserve","pid":1}"#),
        frame(br#"{"call":"unknown"}"#),
    ] {
        let case = Case::new();
        let mut broker = case.broker(2);
        case.client().write_all(&bytes).unwrap();
        for _ in 0..5 {
            broker.poll();
        }
        assert!(broker.failed());
        assert_eq!(broker.admitted, 0);
        assert!(!broker.finish().unwrap());
    }
}

#[test]
fn partial_frames_timeout_but_idle_connections_only_close() {
    for active in [false, true] {
        let case = Case::new();
        let mut broker = case.broker(2);
        let mut client = case.client();
        broker.poll();
        if active {
            client.write_all(&[0]).unwrap();
            broker.poll();
        }
        broker.peers[0].started = Instant::now() - DEADLINE;
        broker.poll();
        assert_eq!(broker.failed(), active);
        assert_eq!(broker.finish().unwrap(), !active);
    }
}

#[test]
fn connection_and_call_counts_are_bounded() {
    let case = Case::new();
    let mut broker = case.broker(64);
    let _clients: Vec<_> = (0..=PEERS).map(|_| case.client()).collect();
    broker.poll();
    assert!(broker.failed());
    assert!(broker.peers.len() <= PEERS);
    assert!(!broker.finish().unwrap());
    let case = Case::new();
    let mut broker = case.broker(64);
    let mut client = case.client();
    for _ in 0..CALLS {
        answer(&mut broker, &mut client, br#"{"call":"verbs"}"#);
    }
    client.write_all(&frame(br#"{"call":"verbs"}"#)).unwrap();
    for _ in 0..4 {
        broker.poll();
    }
    assert!(broker.failed());
    assert_eq!(broker.admitted, 0);
}

#[test]
fn shutdown_cannot_hide_partial_frames() {
    let case = Case::new();
    let mut broker = case.broker(1);
    let mut client = case.client();
    client.write_all(&[0]).unwrap();
    for _ in 0..2 {
        broker.poll();
    }
    assert!(!broker.finish().unwrap());
}

#[test]
fn canonical_bounded_control_is_required_and_absence_disables() {
    let case = Case::new();
    let control = case.0.join("control");
    let directory = case.0.join("socket");
    let journal = case.0.join("journal");
    assert!(
        Broker::configured(&control, &directory, &journal)
            .unwrap()
            .is_none()
    );
    for value in ["0\n", "65\n", "01\n", "1", "1\n\n", "-1\n", "1\nxx", "\n"] {
        fs::write(&control, value).unwrap();
        assert!(Broker::configured(&control, &directory, &journal).is_err());
        assert!(!journal.exists());
    }
    fs::write(&control, "64\n").unwrap();
    let broker = Broker::configured(&control, &directory, &journal)
        .unwrap()
        .unwrap();
    assert!(broker.finish().unwrap());
}

#[test]
fn exact_maximum_reservations_finish_with_a_private_bounded_ledger() {
    let case = Case::new();
    let mut broker = case.broker(64);
    let mut client = case.client();
    for expected in 1..=64 {
        assert!(
            answer(&mut broker, &mut client, br#"{"call":"reserve"}"#)
                .ends_with(&format!("[{expected}]}}"))
        );
    }
    drop(client);
    broker.poll();
    assert!(broker.finish().unwrap());
    let path = case.0.join("journal");
    let log = fs::read_to_string(&path).unwrap();
    assert_eq!(log.lines().count(), 66);
    assert!(log.len() < JOURNAL);
    assert!(log.contains("\"status\":\"STOPPED\",\"admitted\":64,\"calls\":64"));
    assert_eq!(
        fs::metadata(path).unwrap().permissions().mode() & 0o777,
        0o600
    );
}

#[test]
fn an_existing_ledger_is_never_replaced() {
    let case = Case::new();
    let path = case.0.join("journal");
    fs::write(&path, "retained\n").unwrap();
    assert!(Broker::new(&case.0.join("socket"), &path, 1).is_err());
    assert_eq!(fs::read_to_string(path).unwrap(), "retained\n");
}
