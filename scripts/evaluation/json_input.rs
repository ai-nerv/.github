use super::{MAX_BYTES, opened, refused, relative, unchanged};
use std::collections::BTreeSet;
use std::io::{self, Read};
use std::os::unix::fs::MetadataExt;
use std::path::Path;

const DEPTH: usize = 24;
const EVENTS: usize = 16384;
const REPLAY_EVENTS: usize = 131072;
const INTEGER: u64 = 9_007_199_254_740_991;

struct Parser<'a> {
    bytes: &'a [u8],
    at: usize,
    events: usize,
    event_limit: usize,
    deepest: usize,
    safe_integers: bool,
}

impl Parser<'_> {
    fn peek(&self) -> Option<u8> {
        self.bytes.get(self.at).copied()
    }

    fn space(&mut self) {
        while matches!(self.peek(), Some(b' ' | b'\t' | b'\r' | b'\n')) {
            self.at += 1;
        }
    }

    fn take(&mut self, wanted: u8) -> io::Result<()> {
        if self.peek() != Some(wanted) {
            return Err(refused("invalid JSON syntax"));
        }
        self.at += 1;
        Ok(())
    }

    fn event(&mut self) -> io::Result<()> {
        self.events += 1;
        if self.events > self.event_limit {
            return Err(refused("JSON stream exceeds event bound"));
        }
        Ok(())
    }

    fn hex(&mut self) -> io::Result<u32> {
        let mut value = 0;
        for _ in 0..4 {
            let digit = match self.peek() {
                Some(b'0'..=b'9') => u32::from(self.bytes[self.at] - b'0'),
                Some(b'a'..=b'f') => u32::from(self.bytes[self.at] - b'a') + 10,
                Some(b'A'..=b'F') => u32::from(self.bytes[self.at] - b'A') + 10,
                _ => return Err(refused("invalid JSON Unicode escape")),
            };
            self.at += 1;
            value = value * 16 + digit;
        }
        Ok(value)
    }

    fn unicode(&mut self) -> io::Result<char> {
        let mut value = self.hex()?;
        if (0xd800..=0xdbff).contains(&value) {
            self.take(b'\\')?;
            self.take(b'u')?;
            let low = self.hex()?;
            if !(0xdc00..=0xdfff).contains(&low) {
                return Err(refused("invalid JSON surrogate pair"));
            }
            value = 0x10000 + ((value - 0xd800) << 10) + low - 0xdc00;
        }
        char::from_u32(value).ok_or_else(|| refused("unpaired JSON surrogate"))
    }

    fn string(&mut self, key: bool) -> io::Result<String> {
        self.take(b'"')?;
        let mut decoded = String::new();
        let mut start = self.at;
        loop {
            match self.peek() {
                Some(b'"' | b'\\') => {
                    if key {
                        decoded.push_str(
                            std::str::from_utf8(&self.bytes[start..self.at])
                                .map_err(|_| refused("invalid JSON UTF-8"))?,
                        );
                    }
                    let byte = self.bytes[self.at];
                    self.at += 1;
                    if byte == b'"' {
                        return Ok(decoded);
                    }
                    let escape = self
                        .peek()
                        .ok_or_else(|| refused("unfinished JSON escape"))?;
                    self.at += 1;
                    let escaped = match escape {
                        b'"' => '"',
                        b'\\' => '\\',
                        b'/' => '/',
                        b'b' => '\u{8}',
                        b'f' => '\u{c}',
                        b'n' => '\n',
                        b'r' => '\r',
                        b't' => '\t',
                        b'u' => self.unicode()?,
                        _ => return Err(refused("invalid JSON escape")),
                    };
                    if key {
                        decoded.push(escaped);
                    }
                    start = self.at;
                }
                None | Some(0..=0x1f) => {
                    return Err(refused("unfinished or unescaped JSON string"));
                }
                Some(_) => self.at += 1,
            }
        }
    }

    fn number(&mut self) -> io::Result<()> {
        if !self.safe_integers {
            return self.wire_number();
        }
        let start = self.at;
        let mut value = 0u64;
        while let Some(byte @ b'0'..=b'9') = self.peek() {
            if self.at > start && self.bytes[start] == b'0' {
                return Err(refused("noncanonical JSON integer"));
            }
            value = value * 10 + u64::from(byte - b'0');
            if value > INTEGER {
                return Err(refused("JSON integer exceeds exact counter bound"));
            }
            self.at += 1;
        }
        if matches!(self.peek(), Some(b'.' | b'e' | b'E')) {
            return Err(refused("JSON counters require integer literals"));
        }
        self.event()
    }

    fn digits(&mut self) -> io::Result<()> {
        let start = self.at;
        while matches!(self.peek(), Some(b'0'..=b'9')) {
            self.at += 1;
        }
        if self.at == start {
            return Err(refused("JSON number requires digits"));
        }
        Ok(())
    }

    fn wire_number(&mut self) -> io::Result<()> {
        if self.peek() == Some(b'-') {
            self.at += 1;
        }
        if self.peek() == Some(b'0') {
            self.at += 1;
        } else {
            self.digits()?;
        }
        if self.peek() == Some(b'.') {
            self.at += 1;
            self.digits()?;
        }
        if matches!(self.peek(), Some(b'e' | b'E')) {
            self.at += 1;
            if matches!(self.peek(), Some(b'+' | b'-')) {
                self.at += 1;
            }
            self.digits()?;
        }
        self.event()
    }

    fn literal(&mut self, word: &[u8]) -> io::Result<()> {
        for &byte in word {
            self.take(byte)?;
        }
        self.event()
    }

    fn container(&mut self, depth: usize, object: bool) -> io::Result<()> {
        self.at += 1;
        self.space();
        let end = if object { b'}' } else { b']' };
        if self.peek() == Some(end) {
            self.at += 1;
            return self.event();
        }
        let mut keys = BTreeSet::new();
        loop {
            if object {
                let key = self.string(true)?;
                if !keys.insert(key) {
                    return Err(refused("duplicate JSON member"));
                }
                self.space();
                self.take(b':')?;
            }
            self.value(depth + 1)?;
            self.space();
            if self.peek() == Some(end) {
                self.at += 1;
                return self.event();
            }
            self.take(b',')?;
            self.space();
        }
    }

    fn value(&mut self, depth: usize) -> io::Result<()> {
        if depth > DEPTH {
            return Err(refused("JSON nesting exceeds 24"));
        }
        self.deepest = self.deepest.max(depth);
        self.space();
        match self.peek() {
            Some(b'{') => self.container(depth, true),
            Some(b'[') => self.container(depth, false),
            Some(b'"') => {
                self.string(false)?;
                self.event()
            }
            Some(b'0'..=b'9') => self.number(),
            Some(b'-') if !self.safe_integers => self.wire_number(),
            Some(b't') => self.literal(b"true"),
            Some(b'f') => self.literal(b"false"),
            Some(b'n') => self.literal(b"null"),
            _ => Err(refused("invalid JSON value or noncanonical counter")),
        }
    }
}

fn validate(bytes: &[u8], limit: u64) -> io::Result<(usize, usize)> {
    validate_mode(bytes, limit, true)
}

fn validate_mode(bytes: &[u8], limit: u64, safe_integers: bool) -> io::Result<(usize, usize)> {
    if !matches!(limit, 131072 | 1048576 | MAX_BYTES) || bytes.len() as u64 > limit {
        return Err(refused("unsupported or exceeded JSON byte bound"));
    }
    std::str::from_utf8(bytes).map_err(|_| refused("invalid JSON UTF-8"))?;
    let mut parser = Parser {
        bytes,
        at: 0,
        events: 0,
        event_limit: if limit == MAX_BYTES {
            REPLAY_EVENTS
        } else {
            EVENTS
        },
        deepest: 0,
        safe_integers,
    };
    parser.value(0)?;
    parser.space();
    if parser.at != bytes.len() {
        return Err(refused("trailing JSON data or multiple documents"));
    }
    Ok((parser.events, parser.deepest))
}

pub(super) fn run(args: &[String]) -> io::Result<()> {
    if args.len() != 4 || !matches!(args[3].as_str(), "131072" | "1048576" | "16777216") {
        return Err(refused(
            "usage: eval-input json ROOT RELATIVE 131072|1048576|16777216",
        ));
    }
    let limit = args[3]
        .parse::<u64>()
        .map_err(|_| refused("invalid JSON byte bound"))?;
    let root = opened(Path::new(&args[1]), true)?;
    let mut file = relative(&root, &args[2], false)?;
    let before = file.metadata()?;
    if !before.is_file() || before.nlink() != 1 || before.len() > limit {
        return Err(refused(
            "JSON input must be a bounded singly linked regular file",
        ));
    }
    let mut bytes = Vec::new();
    (&mut file).take(limit + 1).read_to_end(&mut bytes)?;
    let safe_integers = args[0] == "json";
    let (events, depth) = if safe_integers {
        validate(&bytes, limit)?
    } else {
        validate_mode(&bytes, limit, false)?
    };
    if !unchanged(&before, &file.metadata()?) {
        return Err(refused("JSON input changed during validation"));
    }
    println!(
        "{{\"status\":\"JSON_VALIDATED\",\"bytes\":{},\"events\":{events},\"max_depth\":{depth},\"safe_integers\":{safe_integers}}}",
        bytes.len()
    );
    Ok(())
}

#[cfg(test)]
#[path = "json_input_tests.rs"]
mod tests;
