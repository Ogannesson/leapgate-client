//! ICE signaling (contract 05 §2.5~§2.7): the explicit candidate encoding, the candidate filter
//! without proofs, and the controlled side's checks on a FORWARD from leapgate-server.

use hbb_common::{
    bytes::Bytes,
    config::Config,
    protobuf::Message as _,
    rendezvous_proto::{leapgate_ice, LeapgateIce, LeapgateIceParams, LeapgateIceSealed},
    sodiumoxide::crypto::{sealedbox, sign},
};
use std::{
    collections::BTreeMap,
    net::{IpAddr, Ipv4Addr, Ipv6Addr, SocketAddr},
    sync::Mutex,
};

/// `LeapgateIce.ver`.
pub const ICE_VER: u32 = 1;
pub(super) const SESSION_LEN: usize = 16;
const OFFER_DOMAIN: &[u8] = b"leapgate-ice-offer-v1\0";
const OFFER_TS_WINDOW_SECS: i64 = 40;
pub(super) const MAX_CANDIDATES: usize = 16;
const OFFER_SEEN_MAX: usize = 1024;
const SIG_LEN: usize = 64;
/// A sealed box is 48 bytes longer than its plaintext; FORWARDs stay under 1200 bytes.
const SEALED_LEN: std::ops::RangeInclusive<usize> = 49..=1024;
const UFRAG_LEN: std::ops::RangeInclusive<usize> = 4..=32;
const PWD_LEN: std::ops::RangeInclusive<usize> = 22..=64;

/// FORWARDs seen, by the sealed box's ephemeral public key, with their `ts`.
static SEEN: Mutex<BTreeMap<[u8; 32], u64>> = Mutex::new(BTreeMap::new());

/// A message, or part of one, that breaks the format rules.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Bad;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Kind {
    Host,
    Srflx,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) struct Candidate {
    pub(crate) kind: Kind,
    /// The owner's local preference (§2.10).
    pub(crate) pref: u16,
    pub(crate) addr: SocketAddr,
}

impl Candidate {
    /// §2.6: type ‖ local preference ‖ family ‖ address ‖ port, big endian.
    pub(crate) fn encode(&self) -> Bytes {
        let mut b = vec![match self.kind {
            Kind::Host => 0,
            Kind::Srflx => 1,
        }];
        b.extend_from_slice(&self.pref.to_be_bytes());
        match self.addr.ip() {
            IpAddr::V4(ip) => {
                b.push(4);
                b.extend_from_slice(&ip.octets());
            }
            IpAddr::V6(ip) => {
                b.push(6);
                b.extend_from_slice(&ip.octets());
            }
        }
        b.extend_from_slice(&self.addr.port().to_be_bytes());
        b.into()
    }

    pub(crate) fn decode(b: &[u8]) -> Option<Candidate> {
        let kind = match b.first()? {
            0 => Kind::Host,
            1 => Kind::Srflx,
            _ => return None,
        };
        let ip = match (b.len(), b.get(3)) {
            (10, Some(4)) => IpAddr::V4(Ipv4Addr::new(b[4], b[5], b[6], b[7])),
            (22, Some(6)) => IpAddr::V6(Ipv6Addr::from(<[u8; 16]>::try_from(&b[4..20]).ok()?)),
            _ => return None,
        };
        let n = b.len();
        let port = u16::from_be_bytes([b[n - 2], b[n - 1]]);
        if port == 0 {
            return None;
        }
        Some(Candidate {
            kind,
            pref: u16::from_be_bytes([b[1], b[2]]),
            addr: SocketAddr::new(ip, port),
        })
    }
}

/// §2.7's address classes.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Class {
    PrivateV4,
    PublicV4,
    Ula,
    GlobalV6,
    Drop,
}

pub(crate) fn classify(ip: IpAddr) -> Class {
    match ip {
        IpAddr::V4(ip) if excluded_v4(ip) => Class::Drop,
        IpAddr::V4(ip) if ip.is_private() => Class::PrivateV4,
        IpAddr::V4(_) => Class::PublicV4,
        IpAddr::V6(ip) if excluded_v6(ip) => Class::Drop,
        IpAddr::V6(ip) if is_global(ip) => Class::GlobalV6,
        IpAddr::V6(ip) if is_ula(ip) => Class::Ula,
        IpAddr::V6(_) => Class::Drop,
    }
}

/// `0/8`, loopback, link-local, CGNAT and Tailscale's `100.64/10`, mihomo's `198.18/15`,
/// multicast, and `240/4` with the broadcast address.
fn excluded_v4(ip: Ipv4Addr) -> bool {
    let o = ip.octets();
    o[0] == 0
        || o[0] == 127
        || o[0] >= 224
        || (o[0] == 169 && o[1] == 254)
        || (o[0] == 100 && (o[1] & 0xc0) == 64)
        || (o[0] == 198 && (o[1] & 0xfe) == 18)
}

/// Loopback, unspecified, link-local, multicast, IPv4-mapped, and mihomo's TUN prefix
/// `fdfe:dcba:9876::/48`.
pub(crate) fn excluded_v6(ip: Ipv6Addr) -> bool {
    let s = ip.segments();
    ip.is_loopback()
        || ip.is_unspecified()
        || ip.is_unicast_link_local()
        || ip.is_multicast()
        || ip.to_ipv4_mapped().is_some()
        || s[..3] == [0xfdfe, 0xdcba, 0x9876]
}

pub(crate) fn is_ula(ip: Ipv6Addr) -> bool {
    ip.octets()[0] & 0xfe == 0xfc
}

pub(crate) fn is_global(ip: Ipv6Addr) -> bool {
    ip.segments()[0] & 0xe000 == 0x2000
}

/// §2.7 without proofs: the server already checked them.
pub(crate) fn filter(candidates: &[Bytes]) -> Result<Vec<Candidate>, Bad> {
    if candidates.len() > MAX_CANDIDATES {
        return Err(Bad);
    }
    let mut out: Vec<Candidate> = Vec::new();
    for b in candidates {
        let c = Candidate::decode(b).ok_or(Bad)?;
        if classify(c.addr.ip()) != Class::Drop && !out.iter().any(|o| o.addr == c.addr) {
            out.push(c);
        }
    }
    Ok(out)
}

fn ice_chars(s: &str, len: std::ops::RangeInclusive<usize>) -> bool {
    len.contains(&s.len())
        && s.bytes()
            .all(|c| c.is_ascii_alphanumeric() || c == b'+' || c == b'/')
}

/// The peer's ufrag, pwd and candidates.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AnswerParams {
    pub(crate) ufrag: String,
    pub(crate) pwd: String,
    pub(crate) candidates: Vec<Candidate>,
}

impl AnswerParams {
    /// §2.3 ① rules, then §2.7 without proofs.
    pub fn parse(p: &LeapgateIceParams) -> Result<Self, Bad> {
        if !ice_chars(&p.ufrag, UFRAG_LEN) || !ice_chars(&p.pwd, PWD_LEN) {
            return Err(Bad);
        }
        Ok(AnswerParams {
            ufrag: p.ufrag.clone(),
            pwd: p.pwd.clone(),
            candidates: filter(&p.candidates)?,
        })
    }
}

#[derive(Debug, PartialEq, Eq)]
pub enum Opened {
    /// Failed one of the checks before the session is known: drop it silently.
    Drop,
    /// The plaintext breaks the format rules: answer `REJECT{BAD}` for `session`.
    Bad { session: Bytes },
    Ok {
        session: [u8; SESSION_LEN],
        peer: AnswerParams,
    },
}

/// The controlled side's handling of a `LeapgateIce` from the rendezvous server, contract 05
/// §2.5 steps 0~6, against this device's id and key and the replay table of this process.
pub fn open_forward(m: &LeapgateIce) -> Opened {
    let Ok(Some(server_pk)) = crate::sign::server_pk() else {
        return Opened::Drop;
    };
    let Some((sk, pk)) = Config::get_existing_key_pair() else {
        return Opened::Drop;
    };
    let (Some(sk), Some(pk)) = (
        sign::SecretKey::from_slice(&sk),
        sign::PublicKey::from_slice(&pk),
    ) else {
        return Opened::Drop;
    };
    open(
        m,
        &server_pk,
        (&pk, &sk),
        &Config::get_id(),
        crate::sign::clock_skew,
        &SEEN,
    )
}

fn forward_msg(id: &str, ts: u64, sealed: &[u8]) -> Vec<u8> {
    let mut msg = OFFER_DOMAIN.to_vec();
    msg.extend_from_slice(id.as_bytes());
    msg.push(0);
    msg.extend_from_slice(&ts.to_be_bytes());
    msg.extend_from_slice(sealed);
    msg
}

fn open(
    m: &LeapgateIce,
    server_pk: &sign::PublicKey,
    (pk, sk): (&sign::PublicKey, &sign::SecretKey),
    id: &str,
    skew: impl Fn(i64) -> i64,
    seen: &Mutex<BTreeMap<[u8; 32], u64>>,
) -> Opened {
    let Some(leapgate_ice::Union::Forward(f)) = &m.union else {
        return Opened::Drop;
    };
    if m.ver != ICE_VER || f.sig.len() != SIG_LEN || !SEALED_LEN.contains(&f.sealed.len()) {
        return Opened::Drop;
    }
    let Ok(sig) = sign::Signature::from_bytes(&f.sig) else {
        return Opened::Drop;
    };
    if !sign::verify_detached(&sig, &forward_msg(id, f.ts, &f.sealed), server_pk) {
        return Opened::Drop;
    }
    let fresh = |ts: u64| i64::try_from(ts).map(&skew);
    if !matches!(fresh(f.ts), Ok(s) if s.abs() <= OFFER_TS_WINDOW_SECS) {
        return Opened::Drop;
    }
    let mut key = [0u8; 32];
    key.copy_from_slice(&f.sealed[..32]);
    {
        let mut seen = seen.lock().unwrap();
        if seen.contains_key(&key) {
            return Opened::Drop;
        }
        // An entry lives until its FORWARD can no longer pass the time window. Evicting live
        // ones would let replays back in, so a full table drops the newcomer instead.
        seen.retain(|_, ts| matches!(fresh(*ts), Ok(s) if s >= -OFFER_TS_WINDOW_SECS));
        if seen.len() >= OFFER_SEEN_MAX {
            return Opened::Drop;
        }
        seen.insert(key, f.ts);
    }
    let (Ok(x_pk), Ok(x_sk)) = (sign::to_curve25519_pk(pk), sign::to_curve25519_sk(sk)) else {
        return Opened::Drop;
    };
    let Ok(inner) = sealedbox::open(&f.sealed, &x_pk, &x_sk) else {
        return Opened::Drop;
    };
    let Ok(inner) = LeapgateIceSealed::parse_from_bytes(&inner) else {
        return Opened::Drop;
    };
    let Ok(session) = <[u8; SESSION_LEN]>::try_from(&inner.session[..]) else {
        return Opened::Bad {
            session: inner.session,
        };
    };
    match AnswerParams::parse(inner.params.get_or_default()) {
        Ok(peer) => Opened::Ok { session, peer },
        Err(Bad) => Opened::Bad {
            session: inner.session,
        },
    }
}

#[cfg(test)]
mod tests {
    use super::{super::hex, *};
    use crate::sign::tests::{device_sk, server_keys, DEVICE_SEED, ID, T};

    // Contract 05 §2.6 and §2.5, shared with leapgate-server's tests.
    const C1: &str = "00ffff04c0a8010ac350";
    const C2: &str = "0112340620010db80000000000000000000000010d96";
    const DEVICE_PK: &str = "ea4a6c63e29c520abef5507b132ec5f9954776aebebe7b92421eea691446d22c";
    const SERVER_PK: &str = "fd1724385aa0c75b64fb78cd602fa1d991fdebf76b13c58ed702eac835e9f618";
    const DEVICE_X25519_PK: &str =
        "761d88ec830413919dfe9d4d1d56f17e653c8c994082df5b137b90a0ae6edf74";
    const INNER: &str = "0a10000102030405060708090a0b0c0d0e0f12300a08414141414141414112186161616161616161616161616161616161616161616161611a0a00ffff04c0a8010ac350";
    const SEALED: &str = "1efed8033c4fda7f2ea111068b846a64b9a565c0b24066caad74b4732359b22f1d7cc65bd678b90b11713c25a1acd7fa6e9538b2a54243c19945b13903847822b07aa74c37ac203c5ce2895a753a382fca93611ac14f51be9c6419edb6e4f385ad937c842331da56c74127100cf8ecf84dd61e5e";
    const MSG_HEAD: &str =
        "6c656170676174652d6963652d6f666665722d763100313233343536373839000000000068f9c780";
    const SIG: &str = "af0420c4ff56072b64aa67109baad18b6559c124895c2fc2fffab0f1eea75fde2652d4c0039a4be24ded171ae09174005b34e41415374da44704cd9f746fd90b";

    fn device_pk() -> sign::PublicKey {
        sign::keypair_from_seed(&sign::Seed(DEVICE_SEED)).0
    }

    fn cand(kind: Kind, pref: u16, addr: &str) -> Candidate {
        Candidate {
            kind,
            pref,
            addr: addr.parse().unwrap(),
        }
    }

    fn host(addr: &str) -> Bytes {
        cand(Kind::Host, 1, addr).encode()
    }

    fn forward(ts: u64, sealed: Vec<u8>, sig: Vec<u8>) -> LeapgateIce {
        let mut f = hbb_common::rendezvous_proto::LeapgateIceForward::new();
        f.ts = ts;
        f.sealed = sealed.into();
        f.sig = sig.into();
        let mut m = LeapgateIce::new();
        m.ver = ICE_VER;
        m.set_forward(f);
        m
    }

    /// The FORWARD leapgate-server would build for `inner` at `ts`.
    fn sealed_forward(inner: &LeapgateIceSealed, ts: u64) -> LeapgateIce {
        let x_pk = sign::to_curve25519_pk(&device_pk()).unwrap();
        let sealed = sealedbox::seal(&inner.write_to_bytes().unwrap(), &x_pk);
        let sig = sign::sign_detached(&forward_msg(ID, ts, &sealed), &server_keys().1);
        forward(ts, sealed, sig.to_bytes().to_vec())
    }

    fn vector() -> LeapgateIce {
        forward(T as u64, hex(SEALED), hex(SIG))
    }

    fn open_at(m: &LeapgateIce, now: i64, seen: &Mutex<BTreeMap<[u8; 32], u64>>) -> Opened {
        open(
            m,
            &server_keys().0,
            (&device_pk(), &device_sk()),
            ID,
            |t| t - now,
            seen,
        )
    }

    fn inner(session: &[u8], ufrag: &str) -> LeapgateIceSealed {
        let mut p = LeapgateIceParams::new();
        p.ufrag = ufrag.to_owned();
        p.pwd = "a".repeat(24);
        p.candidates = vec![hex(C1).into()];
        let mut s = LeapgateIceSealed::new();
        s.session = session.to_vec().into();
        s.params = Some(p).into();
        s
    }

    #[test]
    fn candidate_vectors_round_trip() {
        let c1 = cand(Kind::Host, 0xffff, "192.168.1.10:50000");
        let c2 = cand(Kind::Srflx, 0x1234, "[2001:db8::1]:3478");
        assert_eq!(c1.encode().to_vec(), hex(C1));
        assert_eq!(c2.encode().to_vec(), hex(C2));
        assert_eq!(Candidate::decode(&hex(C1)), Some(c1));
        assert_eq!(Candidate::decode(&hex(C2)), Some(c2));
        let mut bad = Vec::new();
        bad.push(hex(C1)[..9].to_vec()); // length outside the whitelist
        let mut v = hex(C1);
        v.push(0);
        bad.push(v);
        let mut v = hex(C1);
        v[3] = 6; // family 6 in 10 bytes
        bad.push(v);
        let mut v = hex(C2);
        v[3] = 4; // family 4 in 22 bytes
        bad.push(v);
        let mut v = hex(C1);
        v[0] = 2; // no such type
        bad.push(v);
        let mut v = hex(C1);
        v[8..10].copy_from_slice(&[0, 0]); // port 0
        bad.push(v);
        bad.push(Vec::new());
        for b in bad {
            assert_eq!(Candidate::decode(&b), None, "{b:02x?}");
            assert_eq!(filter(&[b.into()]), Err(Bad));
        }
    }

    #[test]
    fn filter_without_proofs() {
        let keep = [
            "192.168.1.10:1",
            "10.0.0.1:1",
            "172.16.0.1:1",
            "[fd00::1]:1",
            "[2408:8256::10]:1",
            "203.0.113.7:1",
        ];
        let drop = [
            "127.0.0.1:1",
            "0.1.2.3:1",
            "169.254.1.1:1",
            "100.64.0.1:1",
            "198.19.0.1:1",
            "224.0.0.1:1",
            "255.255.255.255:1",
            "[fdfe:dcba:9876::1]:1",
            "[::1]:1",
            "[::]:1",
            "[fe80::1]:1",
            "[ff02::1]:1",
            "[::ffff:192.168.1.10]:1",
            "[4000::1]:1",
        ];
        // Kept ones in their order, between dropped ones; then a kept address again, as another
        // type, which goes while the first one stays.
        let sent: Vec<Bytes> = drop[..1]
            .iter()
            .chain(keep.iter())
            .chain(drop[1..3].iter())
            .map(|a| host(a))
            .chain([cand(Kind::Srflx, 9, keep[0]).encode()])
            .collect();
        let got: Vec<SocketAddr> = filter(&sent).unwrap().iter().map(|c| c.addr).collect();
        let want: Vec<SocketAddr> = keep.iter().map(|a| a.parse().unwrap()).collect();
        assert_eq!(got, want);
        let dropped: Vec<Bytes> = drop.iter().map(|a| host(a)).collect();
        assert_eq!(filter(&dropped), Ok(Vec::new()));
        assert_eq!(filter(&vec![host("10.0.0.1:1"); 17]), Err(Bad));
        assert_eq!(filter(&vec![host("10.0.0.1:1"); 16]).unwrap().len(), 1);
    }

    #[test]
    fn address_classes() {
        let v6 = |s: &str| s.parse::<Ipv6Addr>().unwrap();
        assert!(is_ula(v6("fc00::1")) && is_ula(v6("fdff::1")) && !is_ula(v6("fe00::1")));
        assert!(is_global(v6("2000::1")) && is_global(v6("3fff::1")) && !is_global(v6("4000::1")));
        for ip in [
            "::",
            "::1",
            "fe80::1",
            "ff02::1",
            "::ffff:10.0.0.1",
            "fdfe:dcba:9876::1",
        ] {
            assert!(excluded_v6(v6(ip)), "{ip}");
        }
        assert!(!excluded_v6(v6("fdfe:dcba:9877::1")));
    }

    #[test]
    fn params_rules() {
        let mut p = LeapgateIceParams::new();
        p.ufrag = "AAAA".to_owned();
        p.pwd = "+/".repeat(11);
        assert!(AnswerParams::parse(&p).is_ok());
        for (ufrag, pwd) in [
            ("AAA", "a".repeat(22)),
            (&*"A".repeat(33), "a".repeat(22)),
            ("AAA-", "a".repeat(22)),
            ("AAAA", "a".repeat(21)),
            ("AAAA", "a".repeat(65)),
            ("AAAA", format!("{}=", "a".repeat(22))),
        ] {
            p.ufrag = ufrag.to_owned();
            p.pwd = pwd;
            assert_eq!(AnswerParams::parse(&p), Err(Bad), "{ufrag}");
        }
    }

    #[test]
    fn forward_vector() {
        assert_eq!(device_pk().0.to_vec(), hex(DEVICE_PK));
        assert_eq!(server_keys().0 .0.to_vec(), hex(SERVER_PK));
        let x_pk = sign::to_curve25519_pk(&device_pk()).unwrap();
        assert_eq!(x_pk.0.to_vec(), hex(DEVICE_X25519_PK));
        let x_sk = sign::to_curve25519_sk(&device_sk()).unwrap();
        assert_eq!(
            sealedbox::open(&hex(SEALED), &x_pk, &x_sk).unwrap(),
            hex(INNER)
        );
        let msg = forward_msg(ID, T as u64, &hex(SEALED));
        assert_eq!(msg.len(), 156);
        assert_eq!(msg[..40], hex(MSG_HEAD)[..]);
        assert_eq!(msg[40..], hex(SEALED)[..]);

        let seen = Mutex::default();
        let session: [u8; 16] = std::array::from_fn(|i| i as u8);
        assert_eq!(
            open_at(&vector(), T, &seen),
            Opened::Ok {
                session,
                peer: AnswerParams {
                    ufrag: "AAAAAAAA".to_owned(),
                    pwd: "a".repeat(24),
                    candidates: vec![cand(Kind::Host, 0xffff, "192.168.1.10:50000")],
                },
            }
        );
    }

    #[test]
    fn forward_drops() {
        let fresh = || Mutex::default();
        let mut m = vector();
        m.ver = 2;
        assert_eq!(open_at(&m, T, &fresh()), Opened::Drop);
        let mut m = vector();
        m.set_offer(Default::default());
        assert_eq!(open_at(&m, T, &fresh()), Opened::Drop);
        for i in [0, 63] {
            let mut sig = hex(SIG);
            sig[i] ^= 1;
            assert_eq!(
                open_at(&forward(T as u64, hex(SEALED), sig), T, &fresh()),
                Opened::Drop
            );
        }
        for i in [0, 115] {
            let mut sealed = hex(SEALED);
            sealed[i] ^= 1;
            assert_eq!(
                open_at(&forward(T as u64, sealed, hex(SIG)), T, &fresh()),
                Opened::Drop
            );
        }
        // Another device's id in the signature.
        let other = open(
            &vector(),
            &server_keys().0,
            (&device_pk(), &device_sk()),
            "123456780",
            |t| t - T,
            &fresh(),
        );
        assert_eq!(other, Opened::Drop);
        // The time window, both ways.
        assert!(matches!(
            open_at(&vector(), T - 40, &fresh()),
            Opened::Ok { .. }
        ));
        assert!(matches!(
            open_at(&vector(), T + 40, &fresh()),
            Opened::Ok { .. }
        ));
        assert_eq!(open_at(&vector(), T - 41, &fresh()), Opened::Drop);
        assert_eq!(open_at(&vector(), T + 41, &fresh()), Opened::Drop);
        // A replay.
        let seen = fresh();
        assert!(matches!(open_at(&vector(), T, &seen), Opened::Ok { .. }));
        assert_eq!(open_at(&vector(), T, &seen), Opened::Drop);
    }

    #[test]
    fn replay_table_expiry_and_limit() {
        let key: [u8; 32] = hex(SEALED)[..32].try_into().unwrap();
        let seen = Mutex::default();
        assert!(matches!(open_at(&vector(), T, &seen), Opened::Ok { .. }));
        // 41 s later the vector can no longer pass the window, and the next insert drops it.
        let later = sealed_forward(&inner(&[1; 16], "BBBBBBBB"), (T + 41) as u64);
        assert!(matches!(open_at(&later, T + 41, &seen), Opened::Ok { .. }));
        assert!(!seen.lock().unwrap().contains_key(&key));
        assert_eq!(seen.lock().unwrap().len(), 1);

        // A full table refuses newcomers and keeps what it has.
        let full: BTreeMap<[u8; 32], u64> = (0..OFFER_SEEN_MAX)
            .map(|i| {
                let mut k = [0u8; 32];
                k[..8].copy_from_slice(&(i as u64).to_be_bytes());
                (k, T as u64)
            })
            .collect();
        let seen = Mutex::new(full.clone());
        assert_eq!(open_at(&vector(), T, &seen), Opened::Drop);
        assert_eq!(*seen.lock().unwrap(), full);
    }

    #[test]
    fn bad_plaintext_names_its_session() {
        let short = sealed_forward(&inner(&[3; 15], "AAAAAAAA"), T as u64);
        assert_eq!(
            open_at(&short, T, &Mutex::default()),
            Opened::Bad {
                session: vec![3; 15].into()
            }
        );
        let bad_params = sealed_forward(&inner(&[3; 16], "AAA"), T as u64);
        assert_eq!(
            open_at(&bad_params, T, &Mutex::default()),
            Opened::Bad {
                session: vec![3; 16].into()
            }
        );
    }
}
