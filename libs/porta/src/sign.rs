//! Device signatures on Porta API requests and the server's signature on the responses.

use hbb_common::{
    anyhow::anyhow,
    base64::{
        engine::general_purpose::{STANDARD, URL_SAFE_NO_PAD},
        Engine as _,
    },
    config::{Config, RS_PUB_KEY},
    get_time,
    sha2::{Digest, Sha256},
    sodiumoxide::crypto::sign,
    throttled_log, ResultType,
};
use std::{
    sync::atomic::{AtomicI64, Ordering},
    time::Duration,
};

pub(crate) const AUTH_HEADER: &str = "Porta-Device-Auth";
pub(crate) const SIG_HEADER: &str = "Porta-Server-Sig";
const DEVICE_CONTEXT: &[u8] = b"porta-device-v1\0";
const SERVER_CONTEXT: &[u8] = b"porta-server-v1\0";

/// Server time minus local time, in seconds, from the last verified response.
static CLOCK_OFFSET: AtomicI64 = AtomicI64::new(0);

/// The `Porta-Device-Auth` header value for one request, and the signature in it (the server
/// binds its response signature to it). Signs with the key pair registered with the rendezvous
/// server: `get_key_pair` caches it per process, and the reports run in the service process,
/// the same one that registers it.
pub fn device_auth(method: &str, endpoint: &str, body: &[u8]) -> ResultType<(String, [u8; 64])> {
    let sk = Config::get_key_pair().0;
    let sk = sign::SecretKey::from_slice(&sk).ok_or_else(|| anyhow!("no device key"))?;
    let t = get_time() / 1000 + CLOCK_OFFSET.load(Ordering::Relaxed);
    Ok(auth_header(
        &sk,
        &Config::get_id(),
        t,
        method,
        endpoint,
        body,
    ))
}

fn auth_header(
    sk: &sign::SecretKey,
    id: &str,
    t: i64,
    method: &str,
    endpoint: &str,
    body: &[u8],
) -> (String, [u8; 64]) {
    let t = t.to_string();
    let mut msg = DEVICE_CONTEXT.to_vec();
    for part in [method, endpoint, id, &t] {
        msg.extend_from_slice(part.as_bytes());
        msg.push(0);
    }
    msg.extend_from_slice(&Sha256::digest(body));
    let sig = sign::sign_detached(&msg, sk).to_bytes();
    let header = format!(
        "v1 id={}, t={}, s={}",
        URL_SAFE_NO_PAD.encode(id),
        t,
        URL_SAFE_NO_PAD.encode(sig)
    );
    (header, sig)
}

/// Adopts the server's clock from a verified response; later requests are stamped with it.
pub fn set_server_time(t: i64) {
    CLOCK_OFFSET.store(t - get_time() / 1000, Ordering::Relaxed);
}

pub(crate) fn clock_offset() -> i64 {
    CLOCK_OFFSET.load(Ordering::Relaxed)
}

/// The rendezvous server's public key: the `key` option, else the built-in key, as upstream
/// `get_key(true)` picks it (without the Windows license-in-exe-name branch).
/// `Ok(None)`: no key configured. `Err`: a key is configured but invalid, so every response
/// must fail verification.
pub fn server_pk() -> Result<Option<sign::PublicKey>, ()> {
    let mut key = Config::get_option("key");
    if key.is_empty() {
        key = RS_PUB_KEY.to_owned();
    }
    let pk = parse_server_pk(&key);
    if pk.is_err() {
        throttled_log!(
            Duration::from_secs(60),
            warn,
            "porta: the configured key is not a valid public key, rejecting all API responses"
        );
    }
    pk
}

fn parse_server_pk(key: &str) -> Result<Option<sign::PublicKey>, ()> {
    if key.is_empty() {
        return Ok(None);
    }
    let bytes = STANDARD.decode(key).map_err(|_| ())?;
    sign::PublicKey::from_slice(&bytes).map(Some).ok_or(())
}

/// Checks a `Porta-Server-Sig` header against the request's own signature and the response body.
/// There is deliberately no form for an empty request signature (see contract 01 §2.2).
pub fn verify_server_sig(
    server_pk: &sign::PublicKey,
    req_sig: &[u8; 64],
    body: &[u8],
    header: Option<&str>,
) -> bool {
    let Some(sig) = header.and_then(|h| URL_SAFE_NO_PAD.decode(h).ok()) else {
        return false;
    };
    let Ok(sig) = sign::Signature::from_bytes(&sig) else {
        return false;
    };
    let mut msg = SERVER_CONTEXT.to_vec();
    msg.extend_from_slice(req_sig);
    msg.extend_from_slice(&Sha256::digest(body));
    sign::verify_detached(&sig, &msg, server_pk)
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    // Shared with the server's tests (contract 01 §6.1). Expected values computed independently
    // with Python `cryptography` (Ed25519), not with this code.
    pub(crate) const DEVICE_SEED: [u8; 32] = [7; 32];
    pub(crate) const ID: &str = "123456789";
    pub(crate) const T: i64 = 1761200000;
    pub(crate) const BODY: &[u8] = br#"{"uuid":"dGVzdA==","ver":1005010}"#;
    const HEADER: &str = "v1 id=MTIzNDU2Nzg5, t=1761200000, \
        s=yx-Mzyt9ynHD1FCErdyWCz_Kx_iNzF7b4ZfZfJfCQaL2vH3VLHVBadR5BYSAbk5fdqXUHU7ImS9W2Wy46mw9Aw";
    pub(crate) const SERVER_SEED: [u8; 32] = [9; 32];
    const SERVER_PK: &str = "/RckOFqgx1tk+3jNYC+h2ZH96/drE8WO1wLqyDXp9hg=";
    const RESP_BODY: &[u8] = br#"{"api":1,"features":[],"time":1761200000}"#;
    const RESP_SIG: &str =
        "zATBKIx6xPyFbAQVV7koFw0iuqmyvNQwuufqcxG-NNKjaI6BUx0uJiHThezCfpTmtYgZZmR2ApOOgEPNMKdsDA";

    pub(crate) fn device_sk() -> sign::SecretKey {
        sign::keypair_from_seed(&sign::Seed(DEVICE_SEED)).1
    }

    pub(crate) fn server_keys() -> (sign::PublicKey, sign::SecretKey) {
        sign::keypair_from_seed(&sign::Seed(SERVER_SEED))
    }

    /// Signs a response the way porta-server does.
    pub(crate) fn server_sign(req_sig: &[u8; 64], body: &[u8]) -> String {
        let mut msg = SERVER_CONTEXT.to_vec();
        msg.extend_from_slice(req_sig);
        msg.extend_from_slice(&Sha256::digest(body));
        URL_SAFE_NO_PAD.encode(sign::sign_detached(&msg, &server_keys().1).to_bytes())
    }

    #[test]
    fn device_header_matches_vector() {
        let (header, sig) = auth_header(&device_sk(), ID, T, "POST", "heartbeat", BODY);
        assert_eq!(header, HEADER);
        assert_eq!(
            URL_SAFE_NO_PAD.encode(sig),
            HEADER.rsplit("s=").next().unwrap()
        );
    }

    #[test]
    fn server_sig_vector_and_negatives() {
        let (_, req_sig) = auth_header(&device_sk(), ID, T, "POST", "heartbeat", BODY);
        let pk = parse_server_pk(SERVER_PK).unwrap().unwrap();
        assert_eq!(pk, server_keys().0);
        assert_eq!(server_sign(&req_sig, RESP_BODY), RESP_SIG);
        assert!(verify_server_sig(&pk, &req_sig, RESP_BODY, Some(RESP_SIG)));
        // Missing header, another body, another request, another key, padded base64.
        assert!(!verify_server_sig(&pk, &req_sig, RESP_BODY, None));
        assert!(!verify_server_sig(
            &pk,
            &req_sig,
            br#"{"api":1}"#,
            Some(RESP_SIG)
        ));
        let mut other_req = req_sig;
        other_req[0] ^= 1;
        assert!(!verify_server_sig(
            &pk,
            &other_req,
            RESP_BODY,
            Some(RESP_SIG)
        ));
        let other_pk = sign::keypair_from_seed(&sign::Seed([1; 32])).0;
        assert!(!verify_server_sig(
            &other_pk,
            &req_sig,
            RESP_BODY,
            Some(RESP_SIG)
        ));
        assert!(!verify_server_sig(
            &pk,
            &req_sig,
            RESP_BODY,
            Some(&format!("{RESP_SIG}=="))
        ));
    }

    #[test]
    fn server_pk_parsing() {
        assert_eq!(parse_server_pk(""), Ok(None));
        assert_eq!(parse_server_pk("not base64!"), Err(()));
        assert_eq!(parse_server_pk(&STANDARD.encode([1u8; 31])), Err(()));
    }
}
