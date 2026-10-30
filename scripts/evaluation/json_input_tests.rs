use super::{EVENTS, MAX_BYTES, REPLAY_EVENTS, validate};

#[test]
fn wire_numbers_do_not_relax_exact_counter_validation() {
    for value in [
        "-1",
        "-0",
        "0.125",
        "1e3",
        "-1.2E-4",
        "1e+9",
        "9007199254740992",
    ] {
        assert!(super::validate_mode(value.as_bytes(), MAX_BYTES, false).is_ok());
        rejected(value);
    }
    for value in [
        "-", "-.1", "01", "-01", "1.", "1e", "1e+", "+1", "NaN", "1e2.0", "--1",
    ] {
        assert!(
            super::validate_mode(value.as_bytes(), MAX_BYTES, false).is_err(),
            "{value}"
        );
    }
    for value in [
        r#"{"a":0.1,"\u0061":2}"#,
        "{}[]",
        "\"\u{0}\"",
        r#""\ud800""#,
    ] {
        assert!(
            super::validate_mode(value.as_bytes(), MAX_BYTES, false).is_err(),
            "{value}"
        );
    }
    assert!(super::validate_mode(&[b'"', 0xff, b'"'], MAX_BYTES, false).is_err());
}

fn accepted(text: &str) {
    assert!(validate(text.as_bytes(), MAX_BYTES).is_ok(), "{text:?}");
}

fn rejected(text: &str) {
    assert!(validate(text.as_bytes(), MAX_BYTES).is_err(), "{text:?}");
}

#[test]
fn accepts_one_complete_json_value() {
    for text in [
        "null",
        "true",
        "false",
        "0",
        "9007199254740991",
        "\"\"",
        "[]",
        "{}",
        " \r\n\t{\"a\":[true,false,null,0,{},[]]} \t\n",
        r#"{"a":{"same":1},"b":{"same":2}}"#,
    ] {
        accepted(text);
    }
}

#[test]
fn refuses_malformed_or_multiple_documents() {
    for text in [
        "",
        " ",
        "[",
        "{",
        "[1,]",
        "{\"a\":0,}",
        "[1 2]",
        "{a:1}",
        "{\"a\" 1}",
        "{\"a\":}",
        "[]{}",
        "null null",
        "truex",
        "[false true]",
        "[1}",
        "/*x*/0",
        "NaN",
        "Infinity",
        "\u{feff}0",
        "0\0",
        "0\u{b}",
    ] {
        rejected(text);
    }
}

#[test]
fn requires_canonical_exact_nonnegative_integers() {
    for text in [
        "-0",
        "-1",
        "+1",
        "01",
        "00",
        "1.0",
        "0.5",
        "1e0",
        "1E+3",
        "9007199254740992",
        "18446744073709551615",
        "99999999999999999999999999999",
    ] {
        rejected(text);
    }
    accepted(r#"{"number_text":"-1e99"}"#);
}

#[test]
fn decodes_keys_before_duplicate_checks() {
    for text in [
        r#"{"a":0,"a":1}"#,
        r#"{"a":{},"\u0061":[]}"#,
        r#"{"é":1,"\u00e9":2}"#,
        r#"{"😀":1,"\ud83d\ude00":2}"#,
        r#"{"\/":0,"/":1}"#,
        r#"{"\n":0,"\u000a":1}"#,
        r#"{"\u0000":0,"\u0000":1}"#,
        r#"{"x":{"a":0,"a":1}}"#,
    ] {
        rejected(text);
    }
    accepted(r#"{"a":0,"A":1,"\u0000":2,"é":3,"e\u0301":4}"#);
}

#[test]
fn validates_escapes_and_unicode_without_replacing_invalid_input() {
    accepted(r#"{"é界😀":"\"\\\/\b\f\n\r\t\u0000\udbff\udfff"}"#);
    for text in [
        r#""\x00""#,
        r#""\u123""#,
        r#""\ug000""#,
        r#""\ud800""#,
        r#""\udc00""#,
        r#""\ud800\u0041""#,
        r#""\ud800x""#,
        r#""\ud800\ud800""#,
        "\"unterminated",
        "\"\n\"",
        "\"\0\"",
        "\"\\",
    ] {
        rejected(text);
    }
    for bytes in [
        &[b'"', 0xff, b'"'][..],
        &[b'"', 0xc0, 0xaf, b'"'],
        &[b'"', 0xed, 0xa0, 0x80, b'"'],
        &[b'"', 0xf4, 0x90, 0x80, 0x80, b'"'],
    ] {
        assert!(validate(bytes, MAX_BYTES).is_err());
    }
}

#[test]
fn preserves_stream_path_depth_bound() {
    let text = format!("{}0{}", "[".repeat(24), "]".repeat(24));
    assert_eq!(validate(text.as_bytes(), MAX_BYTES).unwrap(), (25, 24));
    rejected(&format!("[{text}]"));
    let empty = format!("{}{}", "[".repeat(25), "]".repeat(25));
    assert_eq!(validate(empty.as_bytes(), MAX_BYTES).unwrap(), (25, 24));
    rejected(&format!("[{empty}]"));
}

#[test]
fn preserves_stream_event_count_bound() {
    let text = format!("[{}0]", "0,".repeat(EVENTS - 2));
    for limit in [131072, 1048576] {
        assert_eq!(validate(text.as_bytes(), limit).unwrap().0, EVENTS);
        assert!(
            validate(
                format!("[0,{}]", &text[1..text.len() - 1]).as_bytes(),
                limit
            )
            .is_err()
        );
    }
    assert_eq!(validate(b"{\"a\":[1,2],\"b\":[]}", MAX_BYTES).unwrap().0, 5);
    assert_eq!(validate(b"[]", MAX_BYTES).unwrap().0, 1);
}

#[test]
fn replay_profile_has_a_separate_bounded_event_budget() {
    let text = format!("[{}0]", "0,".repeat(REPLAY_EVENTS - 2));
    assert_eq!(
        validate(text.as_bytes(), MAX_BYTES).unwrap().0,
        REPLAY_EVENTS
    );
    assert!(validate(text.as_bytes(), 1048576).is_err());
    rejected(&format!("[0,{}]", &text[1..text.len() - 1]));
    let prefix = format!("[{}0]", "0,".repeat(EVENTS + 10));
    let duplicate = format!("{{\"a\":{prefix},\"\\u0061\":0}}");
    assert!(
        validate(duplicate.as_bytes(), MAX_BYTES)
            .unwrap_err()
            .to_string()
            .contains("duplicate JSON member")
    );
}

#[test]
fn byte_limits_include_whitespace_and_utf8_octets() {
    for limit in [131072, 1048576, MAX_BYTES] {
        let mut bytes = vec![b' '; limit as usize];
        bytes[0] = b'0';
        assert!(validate(&bytes, limit).is_ok());
        bytes.push(b' ');
        assert!(validate(&bytes, limit).is_err());
    }
    for limit in [0, 1, 131071, MAX_BYTES + 1] {
        assert!(validate(b"0", limit).is_err());
    }
    let text = format!("\"{}\"", "é".repeat(65535));
    assert!(validate(text.as_bytes(), 131072).is_ok());
    assert!(validate(format!("{text} ").as_bytes(), 131072).is_err());
}

#[test]
fn large_escaped_strings_do_not_expand_into_a_value_tree() {
    let text = format!(
        "{{\"raw\":\"{}\"}}",
        r#"\"\\\n\ud83d\ude00é界"#.repeat(100000)
    );
    assert_eq!(validate(text.as_bytes(), MAX_BYTES).unwrap(), (2, 1));
    assert!(validate(text.as_bytes(), 1048576).is_err());
}
