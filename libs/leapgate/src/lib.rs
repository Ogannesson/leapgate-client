//! Leapgate's own logic. Upstream files only call into this crate through one-line hooks,
//! so merging upstream releases conflicts on those lines and nowhere else.

pub mod api;
pub mod brand;
pub mod ice;
pub mod lan;
pub mod options;
pub mod rendezvous;
pub mod report;
pub mod route;
pub mod sign;
pub mod update;
