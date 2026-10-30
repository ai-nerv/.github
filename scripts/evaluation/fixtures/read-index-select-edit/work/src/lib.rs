pub fn retry_delay(attempt: u32) -> u32 {
    attempt.saturating_mul(2)
}

pub fn idle_delay(attempt: u32) -> u32 {
    attempt.saturating_mul(2)
}

pub fn next_attempt(attempt: u32) -> u32 {
    attempt.saturating_add(1)
}
