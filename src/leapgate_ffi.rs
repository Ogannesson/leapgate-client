//! Leapgate's FFI functions for the UI. New exports go here instead of `flutter_ffi.rs`, so
//! merging upstream never conflicts on the bridge surface. Logic stays in `libs/leapgate`;
//! functions here only forward to it.
#![cfg(any(target_os = "android", target_os = "ios", feature = "flutter"))]
