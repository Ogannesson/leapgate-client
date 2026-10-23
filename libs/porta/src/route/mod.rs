//! Routing level two (contract 02). Placeholders the heartbeat already calls; contract 02
//! replaces them with the real implementation.

use hbb_common::serde_json::Value;

/// Revision of the routing data last applied, sent in the heartbeat.
pub fn routing_rev() -> i64 {
    0
}

/// Relay measurements to report in the heartbeat.
pub fn probes() -> Option<Value> {
    None
}

/// Called after every successful heartbeat with its `routing` field.
pub fn on_heartbeat_ok(_routing: Option<&Value>) {}

/// Called when the API server changes or turns out not to be a Porta server.
pub fn reset() {}
