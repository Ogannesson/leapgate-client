//! Porta's own logic. Upstream files only call into this crate through one-line hooks,
//! so merging upstream releases conflicts on those lines and nowhere else.

pub mod brand;
pub mod update;
