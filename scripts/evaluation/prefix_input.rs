use super::{opened, refused, relative, unchanged};
use std::io::{self, Read};
use std::os::unix::fs::MetadataExt;
use std::path::Path;

const LIMIT: u64 = 8 * 1024 * 1024;

fn measure(bytes: &[u8]) -> io::Result<Vec<(usize, usize)>> {
    if bytes.len() as u64 > LIMIT || (!bytes.is_empty() && !bytes.ends_with(b"\n")) {
        return Err(refused(
            "prefix input exceeds bound or lacks final delimiter",
        ));
    }
    std::str::from_utf8(bytes).map_err(|_| refused("invalid prefix UTF-8"))?;
    let mut result = Vec::new();
    let mut previous: Option<(&[u8], &[u8])> = None;
    if bytes.is_empty() {
        return Ok(result);
    }
    for row in bytes[..bytes.len() - 1].split(|b| *b == b'\n') {
        if result.len() == 64
            || row.len() < 66
            || row[64] != b'\t'
            || !row[..64]
                .iter()
                .all(|b| b.is_ascii_digit() || (b'a'..=b'f').contains(b))
            || row[65..].iter().any(|b| *b < 32)
        {
            return Err(refused("invalid or excessive prefix record"));
        }
        let (key, value) = (&row[..64], &row[65..]);
        let shared = match previous {
            Some((old_key, old)) if old_key == key => {
                old.iter().zip(value).take_while(|(a, b)| a == b).count()
            }
            _ => 0,
        };
        result.push((value.len(), shared));
        previous = Some((key, value));
    }
    Ok(result)
}

pub(super) fn run(args: &[String]) -> io::Result<()> {
    if args.len() != 3 {
        return Err(refused("usage: eval-input prefix ROOT RELATIVE"));
    }
    let root = opened(Path::new(&args[1]), true)?;
    let mut file = relative(&root, &args[2], false)?;
    let before = file.metadata()?;
    if !before.is_file() || before.nlink() != 1 || before.len() > LIMIT {
        return Err(refused(
            "prefix input must be a bounded singly linked regular file",
        ));
    }
    let mut bytes = Vec::new();
    (&mut file).take(LIMIT + 1).read_to_end(&mut bytes)?;
    let rows = measure(&bytes)?;
    if !unchanged(&before, &file.metadata()?) {
        return Err(refused("prefix input changed during measurement"));
    }
    let values: Vec<_> = rows
        .iter()
        .enumerate()
        .map(|(index, (size, shared))| {
            format!("{{\"index\":{index},\"normalized_bytes\":{size},\"shared_bytes\":{shared}}}")
        })
        .collect();
    println!(
        "{{\"normalized_bytes\":{},\"stable_prefix_bytes\":{},\"bodies\":[{}]}}",
        rows.iter().map(|r| r.0).sum::<usize>(),
        rows.iter().map(|r| r.1).sum::<usize>(),
        values.join(",")
    );
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn row(key: char, value: &str) -> String {
        format!("{}\t{value}\n", key.to_string().repeat(64))
    }

    #[test]
    fn adjacent_same_identity_only() {
        let input = row('a', "abc") + &row('a', "abcd") + &row('b', "abcd") + &row('a', "abcd");
        assert_eq!(
            measure(input.as_bytes()).unwrap(),
            vec![(3, 0), (4, 3), (4, 0), (4, 0)]
        );
        assert_eq!(measure(b"").unwrap(), vec![]);
    }

    #[test]
    fn counts_octets_including_partial_utf8_sequences() {
        let input = row('a', "é界") + &row('a', "é男");
        assert_eq!(measure(input.as_bytes()).unwrap(), vec![(5, 0), (5, 3)]);
        let input = row('a', "é") + &row('a', "ê");
        assert_eq!(measure(input.as_bytes()).unwrap(), vec![(2, 0), (2, 1)]);
    }

    #[test]
    fn bounded_rows_and_bytes() {
        assert!(measure(row('a', "{}").repeat(64).as_bytes()).is_ok());
        assert!(measure(row('a', "{}").repeat(65).as_bytes()).is_err());
        let exact = row('a', &"x".repeat(LIMIT as usize - 66));
        assert_eq!(exact.len(), LIMIT as usize);
        assert!(measure(exact.as_bytes()).is_ok());
        assert!(measure((exact + &row('a', "x")).as_bytes()).is_err());
    }

    #[test]
    fn refuses_malformed_records() {
        for value in [
            row('g', "{}"),
            row('a', ""),
            row('a', "a\tb"),
            row('a', "a\rb"),
            row('a', "a\0b"),
            "\n".into(),
            row('a', "{}").trim_end().into(),
        ] {
            assert!(measure(value.as_bytes()).is_err(), "{value:?}");
        }
        assert!(measure(&[0xff, b'\n']).is_err());
    }
}
