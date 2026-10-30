pub fn within_capacity(value: u32, capacity: u32) -> bool {
    value < capacity
}

pub fn double_saturated(value: u32) -> u32 {
    value.saturating_mul(2)
}
