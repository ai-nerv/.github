#[path = "/world/work/work/src/lib.rs"]
mod subject;

#[test]
fn retry_delay_is_capped_exponential() {
    for (attempt, expected) in [(0, 1), (1, 2), (2, 4), (3, 8), (6, 64), (7, 64), (40, 64), (u32::MAX, 64)] {
        assert_eq!(subject::retry_delay(attempt), expected);
    }
}

#[test]
fn preserves_other_symbols() {
    for attempt in [0, 3, 5, u32::MAX] {
        assert_eq!(subject::idle_delay(attempt), attempt.saturating_mul(2));
        assert_eq!(subject::next_attempt(attempt), attempt.saturating_add(1));
    }
}

#[test]
fn retry_delay_stays_within_bounds() {
    for attempt in 1..128 {
        assert!((1..=64).contains(&subject::retry_delay(attempt)));
    }
}
