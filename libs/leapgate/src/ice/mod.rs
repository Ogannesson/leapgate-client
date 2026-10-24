//! Leapgate's own ICE (phase 3 contract 05): host and srflx candidates on physical adapters,
//! signaling relayed by leapgate-server, STUN connectivity checks, then upstream's KCP on the
//! selected pair. The protocol constants and wire formats are those of contract 05 §2.

#[allow(dead_code)] // driven by this module once the driver lands
mod check;
mod sig;
mod stun;

pub use sig::{open_forward, AnswerParams, Bad, Opened};

#[cfg(test)]
fn hex(s: &str) -> Vec<u8> {
    (0..s.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&s[i..i + 2], 16).unwrap())
        .collect()
}
