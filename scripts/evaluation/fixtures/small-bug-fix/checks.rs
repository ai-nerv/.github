#[path = "/world/work/work/src/lib.rs"]
mod subject;

#[test]
fn includes_capacity() {
    for capacity in [0, 1, 17, u32::MAX] {
        assert!(subject::within_capacity(capacity, capacity));
    }
}

#[test]
fn accepts_below_and_rejects_above() {
    assert!(subject::within_capacity(16, 17));
    assert!(!subject::within_capacity(18, 17));
}

#[test]
fn preserves_saturation() {
    assert_eq!(subject::double_saturated(0), 0);
    assert_eq!(subject::double_saturated(21), 42);
    assert_eq!(subject::double_saturated(u32::MAX), u32::MAX);
}
