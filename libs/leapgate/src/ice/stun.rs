//! STUN for ICE (contract 05 §2.9): the Binding exchange with the rendezvous server and the
//! connectivity checks, on `stun_codec` plus two attributes of our own.

use bytecodec::{
    bytes::{BytesEncoder, RemainingBytesDecoder},
    ByteCount, Decode, DecodeExt, Encode, EncodeExt, Eos, Result as CodecResult, SizedEncode,
    TryTaggedDecode,
};
use hbb_common::{rand, sodiumoxide::utils::memcmp};
use std::{mem::discriminant, net::SocketAddr};
use stun_codec::{
    rfc5245::attributes::{IceControlled, IceControlling, Priority, UseCandidate},
    rfc5389::{
        attributes::{Fingerprint, MessageIntegrity, Username, XorMappedAddress},
        methods::BINDING,
    },
    AttributeType, Message, MessageClass, MessageDecoder, MessageEncoder, TransactionId,
};

pub(super) type TxId = [u8; 12];

const MAGIC: [u8; 4] = [0x21, 0x12, 0xA4, 0x42];
const BINDING_REQUEST_LEN: usize = 100;

macro_rules! raw_attribute {
    ($name:ident, $decoder:ident, $encoder:ident, $codepoint:expr) => {
        #[derive(Debug, Clone, PartialEq, Eq, Hash)]
        pub struct $name(pub Vec<u8>);

        impl $name {
            pub const CODEPOINT: u16 = $codepoint;
        }

        impl stun_codec::Attribute for $name {
            type Decoder = $decoder;
            type Encoder = $encoder;

            fn get_type(&self) -> AttributeType {
                AttributeType::new(Self::CODEPOINT)
            }
        }

        #[derive(Debug, Default)]
        pub struct $decoder(RemainingBytesDecoder);

        impl Decode for $decoder {
            type Item = $name;

            fn decode(&mut self, buf: &[u8], eos: Eos) -> CodecResult<usize> {
                self.0.decode(buf, eos)
            }

            fn finish_decoding(&mut self) -> CodecResult<$name> {
                self.0.finish_decoding().map($name)
            }

            fn requiring_bytes(&self) -> ByteCount {
                self.0.requiring_bytes()
            }

            fn is_idle(&self) -> bool {
                self.0.is_idle()
            }
        }

        impl TryTaggedDecode for $decoder {
            type Tag = AttributeType;

            fn try_start_decoding(&mut self, tag: AttributeType) -> CodecResult<bool> {
                Ok(tag.as_u16() == $name::CODEPOINT)
            }
        }

        #[derive(Debug, Default)]
        pub struct $encoder(BytesEncoder);

        impl Encode for $encoder {
            type Item = $name;

            fn encode(&mut self, buf: &mut [u8], eos: Eos) -> CodecResult<usize> {
                self.0.encode(buf, eos)
            }

            fn start_encoding(&mut self, item: $name) -> CodecResult<()> {
                self.0.start_encoding(item.0)
            }

            fn requiring_bytes(&self) -> ByteCount {
                ByteCount::Finite(self.exact_requiring_bytes())
            }

            fn is_idle(&self) -> bool {
                self.0.is_idle()
            }
        }

        impl SizedEncode for $encoder {
            fn exact_requiring_bytes(&self) -> u64 {
                self.0.exact_requiring_bytes()
            }
        }
    };
}

// RFC 5780 PADDING, only in the Binding requests to leapgate-server.
raw_attribute!(Padding, PaddingDecoder, PaddingEncoder, 0x0026);
// leapgate-server's reflexive address proof (§2.8); opaque here, forwarded as is.
raw_attribute!(
    LeapgateProof,
    LeapgateProofDecoder,
    LeapgateProofEncoder,
    0xC1E9
);

stun_codec::define_attribute_enums!(
    Attribute,
    AttributeDecoder,
    AttributeEncoder,
    [
        Username,
        MessageIntegrity,
        XorMappedAddress,
        Fingerprint,
        Priority,
        UseCandidate,
        IceControlled,
        IceControlling,
        Padding,
        LeapgateProof
    ]
);

/// Random, with byte 4 (offset 12 of the packet, KCP's flag byte) zero: a late check that
/// reaches KCP then carries no flag, so KCP neither bounces it nor takes it for a SYN (§2.9.5).
pub(super) fn new_txid() -> TxId {
    let mut id: TxId = rand::random();
    id[4] = 0;
    id
}

/// The STUN test of the ICE sockets' receive path (§2.9.2).
pub(super) fn is_stun(buf: &[u8]) -> bool {
    buf.len() >= 20 && buf[0] & 0xC0 == 0 && buf[4..8] == MAGIC && {
        let len = u16::from_be_bytes([buf[2], buf[3]]) as usize;
        len % 4 == 0 && 20 + len == buf.len()
    }
}

/// Upstream's first KCP packet (`KcpStream::connect` with both session ids 0): SYN set, ACK,
/// FIN, DATA, RST and PING clear (§2.9.5).
pub(super) fn is_kcp_syn(buf: &[u8]) -> bool {
    buf.len() >= 14 && buf[12] & 0x3F == 0x01 && buf[4..12] == [0u8; 8]
}

/// A Binding request to leapgate-server, padded to the 100 bytes the server requires so that its
/// response is never larger (§2.9.3).
pub(super) fn binding_request(txid: &TxId) -> [u8; BINDING_REQUEST_LEN] {
    let mut b = [0u8; BINDING_REQUEST_LEN];
    b[..2].copy_from_slice(&[0x00, 0x01]);
    b[2..4].copy_from_slice(&((BINDING_REQUEST_LEN - 20) as u16).to_be_bytes());
    b[4..8].copy_from_slice(&MAGIC);
    b[8..20].copy_from_slice(txid);
    b[20..22].copy_from_slice(&Padding::CODEPOINT.to_be_bytes());
    b[22..24].copy_from_slice(&((BINDING_REQUEST_LEN - 24) as u16).to_be_bytes());
    b
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub(super) struct Mapped {
    pub(super) addr: SocketAddr,
    pub(super) proof: Option<Vec<u8>>,
}

/// leapgate-server's answer to the request `txid` sent from the socket at `local`. Matched on the
/// transaction id alone, not the source: a multi-address server may answer from another one.
pub(super) fn read_binding_response(buf: &[u8], txid: &TxId, local: SocketAddr) -> Option<Mapped> {
    let msg = decode(buf)?;
    if msg.class() != MessageClass::SuccessResponse
        || msg.method() != BINDING
        || msg.transaction_id().as_bytes() != txid
    {
        return None;
    }
    let attrs: Vec<&Attribute> = msg.attributes().collect();
    let [head @ .., Attribute::Fingerprint(_)] = attrs.as_slice() else {
        return None;
    };
    let (mut addr, mut proof) = (None, None);
    for a in head {
        match a {
            Attribute::XorMappedAddress(x) if addr.is_none() => addr = Some(x.address()),
            Attribute::LeapgateProof(p) if proof.is_none() => proof = Some(p.0.clone()),
            _ => return None,
        }
    }
    let addr = addr.filter(|a| a.is_ipv4() == local.is_ipv4())?;
    Some(Mapped { addr, proof })
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) enum Role {
    Controlling,
    Controlled,
}

/// One agent's view of the session's ICE credentials, for building and checking its checks.
pub(super) struct Creds {
    pub(super) local_ufrag: String,
    pub(super) local_pwd: String,
    pub(super) remote_ufrag: String,
    pub(super) remote_pwd: String,
    pub(super) role: Role,
    /// The ICE-CONTROLLING / ICE-CONTROLLED value, random per agent.
    pub(super) tie: u64,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(super) struct Request {
    pub(super) txid: TxId,
    pub(super) priority: u32,
    pub(super) nominate: bool,
}

impl Creds {
    /// A check request (§2.9.4). `None` only for credentials `AnswerParams::parse` would refuse.
    pub(super) fn request(&self, txid: &TxId, priority: u32, nominate: bool) -> Option<Vec<u8>> {
        let mut m = Message::new(MessageClass::Request, BINDING, TransactionId::new(*txid));
        m.add_attribute(Username::new(format!("{}:{}", self.remote_ufrag, self.local_ufrag)).ok()?);
        m.add_attribute(Priority::new(priority));
        match self.role {
            Role::Controlling => m.add_attribute(IceControlling::new(self.tie)),
            Role::Controlled => m.add_attribute(IceControlled::new(self.tie)),
        }
        if nominate {
            m.add_attribute(UseCandidate::new());
        }
        seal(m, &self.remote_pwd)
    }

    /// The success response to the check request `txid` that came from `mapped`.
    pub(super) fn response(&self, txid: &TxId, mapped: SocketAddr) -> Option<Vec<u8>> {
        let mut m = Message::new(
            MessageClass::SuccessResponse,
            BINDING,
            TransactionId::new(*txid),
        );
        m.add_attribute(XorMappedAddress::new(mapped));
        seal(m, &self.local_pwd)
    }

    /// A check request from the peer, if it passes every rule of §2.9.4.
    pub(super) fn read_request(&self, buf: &[u8]) -> Option<Request> {
        let msg = decode(buf)?;
        if msg.class() != MessageClass::Request || msg.method() != BINDING {
            return None;
        }
        if !integrity_ok(&msg, &self.local_pwd) {
            return None;
        }
        let username = msg.get_attribute::<Username>()?;
        if username.name() != format!("{}:{}", self.local_ufrag, self.remote_ufrag) {
            return None;
        }
        let controlling = msg.get_attribute::<IceControlling>().is_some();
        let controlled = msg.get_attribute::<IceControlled>().is_some();
        let nominate = msg.get_attribute::<UseCandidate>().is_some();
        let role_ok = match self.role {
            Role::Controlling => controlled && !controlling && !nominate,
            Role::Controlled => controlling && !controlled,
        };
        if !role_ok {
            return None;
        }
        Some(Request {
            txid: *msg.transaction_id().as_bytes(),
            priority: msg.get_attribute::<Priority>()?.prio(),
            nominate,
        })
    }

    /// The peer's response to a check: its transaction id and the mapped address. Whether it
    /// answers a pending check, and came from where that check went, is the kernel's to tell.
    pub(super) fn read_response(&self, buf: &[u8]) -> Option<(TxId, SocketAddr)> {
        let msg = decode(buf)?;
        if msg.class() != MessageClass::SuccessResponse || msg.method() != BINDING {
            return None;
        }
        let attrs: Vec<&Attribute> = msg.attributes().collect();
        let [Attribute::XorMappedAddress(mapped), Attribute::MessageIntegrity(_), Attribute::Fingerprint(_)] =
            attrs.as_slice()
        else {
            return None;
        };
        if !integrity_ok(&msg, &self.remote_pwd) {
            return None;
        }
        Some((*msg.transaction_id().as_bytes(), mapped.address()))
    }
}

/// A fresh decoder per datagram: it keeps state, and whether it is clean after an error was
/// never checked. Messages with any attribute outside `Attribute` are refused (§2.9.4 rule 1).
fn decode(buf: &[u8]) -> Option<Message<Attribute>> {
    if !is_stun(buf) {
        return None;
    }
    let msg = MessageDecoder::<Attribute>::new()
        .decode_from_bytes(buf)
        .ok()?
        .ok()?;
    if msg.unknown_attributes().next().is_some() {
        return None;
    }
    Some(msg)
}

fn seal(mut m: Message<Attribute>, pwd: &str) -> Option<Vec<u8>> {
    let mi = MessageIntegrity::new_short_term_credential(&m, pwd).ok()?;
    m.add_attribute(mi);
    let fp = Fingerprint::new(&m).ok()?;
    m.add_attribute(fp);
    MessageEncoder::new().encode_into_bytes(m).ok()
}

/// §2.9.4 rules 2 and 3: exactly one MESSAGE-INTEGRITY, second to last, then the FINGERPRINT the
/// decoder already checked; no attribute twice; the HMAC recomputed over the attributes before it
/// with zero padding, and compared in constant time. `check_short_term_credential` compares with
/// `==`, and the library hands back the first matching attribute wherever it sits.
fn integrity_ok(msg: &Message<Attribute>, pwd: &str) -> bool {
    let attrs: Vec<&Attribute> = msg.attributes().collect();
    let [head @ .., Attribute::MessageIntegrity(mi), Attribute::Fingerprint(_)] = attrs.as_slice()
    else {
        return false;
    };
    for (i, a) in head.iter().enumerate() {
        if matches!(
            a,
            Attribute::MessageIntegrity(_) | Attribute::Fingerprint(_)
        ) || head[..i]
            .iter()
            .any(|b| discriminant(*b) == discriminant(*a))
        {
            return false;
        }
    }
    let mut preceding = Message::<Attribute>::new(msg.class(), msg.method(), msg.transaction_id());
    for a in head {
        preceding.add_attribute((*a).clone());
    }
    match MessageIntegrity::new_short_term_credential(&preceding, pwd) {
        Ok(expected) => memcmp(&expected.hmac_sha1(), &mi.hmac_sha1()),
        Err(_) => false,
    }
}

#[cfg(test)]
mod tests {
    use super::{super::hex, *};

    // RFC 5769 §2.1~§2.3, copied from stun_codec 0.3.5's own tests (not exported).
    const RFC5769_REQUEST: [u8; 108] = [
        0x00, 0x01, 0x00, 0x58, 0x21, 0x12, 0xa4, 0x42, 0xb7, 0xe7, 0xa7, 0x01, 0xbc, 0x34, 0xd6,
        0x86, 0xfa, 0x87, 0xdf, 0xae, 0x80, 0x22, 0x00, 0x10, 0x53, 0x54, 0x55, 0x4e, 0x20, 0x74,
        0x65, 0x73, 0x74, 0x20, 0x63, 0x6c, 0x69, 0x65, 0x6e, 0x74, 0x00, 0x24, 0x00, 0x04, 0x6e,
        0x00, 0x01, 0xff, 0x80, 0x29, 0x00, 0x08, 0x93, 0x2f, 0xf9, 0xb1, 0x51, 0x26, 0x3b, 0x36,
        0x00, 0x06, 0x00, 0x09, 0x65, 0x76, 0x74, 0x6a, 0x3a, 0x68, 0x36, 0x76, 0x59, 0x20, 0x20,
        0x20, 0x00, 0x08, 0x00, 0x14, 0x9a, 0xea, 0xa7, 0x0c, 0xbf, 0xd8, 0xcb, 0x56, 0x78, 0x1e,
        0xf2, 0xb5, 0xb2, 0xd3, 0xf2, 0x49, 0xc1, 0xb5, 0x71, 0xa2, 0x80, 0x28, 0x00, 0x04, 0xe5,
        0x7a, 0x3b, 0xcf,
    ];
    const RFC5769_IPV4_RESPONSE: [u8; 80] = [
        0x01, 0x01, 0x00, 0x3c, 0x21, 0x12, 0xa4, 0x42, 0xb7, 0xe7, 0xa7, 0x01, 0xbc, 0x34, 0xd6,
        0x86, 0xfa, 0x87, 0xdf, 0xae, 0x80, 0x22, 0x00, 0x0b, 0x74, 0x65, 0x73, 0x74, 0x20, 0x76,
        0x65, 0x63, 0x74, 0x6f, 0x72, 0x20, 0x00, 0x20, 0x00, 0x08, 0x00, 0x01, 0xa1, 0x47, 0xe1,
        0x12, 0xa6, 0x43, 0x00, 0x08, 0x00, 0x14, 0x2b, 0x91, 0xf5, 0x99, 0xfd, 0x9e, 0x90, 0xc3,
        0x8c, 0x74, 0x89, 0xf9, 0x2a, 0xf9, 0xba, 0x53, 0xf0, 0x6b, 0xe7, 0xd7, 0x80, 0x28, 0x00,
        0x04, 0xc0, 0x7d, 0x4c, 0x96,
    ];
    const RFC5769_IPV6_RESPONSE: [u8; 92] = [
        0x01, 0x01, 0x00, 0x48, 0x21, 0x12, 0xa4, 0x42, 0xb7, 0xe7, 0xa7, 0x01, 0xbc, 0x34, 0xd6,
        0x86, 0xfa, 0x87, 0xdf, 0xae, 0x80, 0x22, 0x00, 0x0b, 0x74, 0x65, 0x73, 0x74, 0x20, 0x76,
        0x65, 0x63, 0x74, 0x6f, 0x72, 0x20, 0x00, 0x20, 0x00, 0x14, 0x00, 0x02, 0xa1, 0x47, 0x01,
        0x13, 0xa9, 0xfa, 0xa5, 0xd3, 0xf1, 0x79, 0xbc, 0x25, 0xf4, 0xb5, 0xbe, 0xd2, 0xb9, 0xd9,
        0x00, 0x08, 0x00, 0x14, 0xa3, 0x82, 0x95, 0x4e, 0x4b, 0xe6, 0x7b, 0xf1, 0x17, 0x84, 0xc9,
        0x7c, 0x82, 0x92, 0xc2, 0x75, 0xbf, 0xe3, 0xed, 0x41, 0x80, 0x28, 0x00, 0x04, 0xc8, 0xfb,
        0x0b, 0x4c,
    ];
    const RFC5769_PWD: &str = "VOkJxbRl1RmTxUk/WvJxBt";

    // Contract 05 §2.9.3 and §2.9.4, shared with leapgate-server's tests.
    const BINDING_TXID: &str = "0102030400060708090a0b0c";
    const BINDING_REQUEST_HEAD: &str = "000100502112a4420102030400060708090a0b0c0026004c";
    const BINDING_RESPONSE_V4: &str = "010100342112a4420102030400060708090a0b0c002000080001bd52ea12d545c1e9001c0168f9c78004cb0071079c4019f16eb06b0d075a34e2cabc1d3347bd802800044a994370";
    const PROOF_V4: &str = "0168f9c78004cb0071079c4019f16eb06b0d075a34e2cabc1d3347bd";
    const CHECK_TXID: &str = "a1a2a3a400a6a7a8a9aaabac";
    const CHECK_REQUEST: &str = "000100502112a442a1a2a3a400a6a7a8a9aaabac0006001142424242424242423a4141414141414141000000002400046effffff802a0008010203040506070800250000000800149a69e7da9c992b547c2657aaabeb4234ef00d79880280004be2aae67";
    const CHECK_RESPONSE: &str = "0101002c2112a442a1a2a3a400a6a7a8a9aaabac002000080001e242e1baa548000800140396113d058210523292f34adddce596e64ae414802800041adeaeb8";

    fn txid(s: &str) -> TxId {
        hex(s).try_into().unwrap()
    }

    fn addr(s: &str) -> SocketAddr {
        s.parse().unwrap()
    }

    /// A's credentials (controlling), or B's with `b` set.
    fn creds(b: bool) -> Creds {
        let (a_ufrag, a_pwd) = ("AAAAAAAA".to_owned(), "a".repeat(24));
        let (b_ufrag, b_pwd) = ("BBBBBBBB".to_owned(), "b".repeat(24));
        if b {
            Creds {
                local_ufrag: b_ufrag,
                local_pwd: b_pwd,
                remote_ufrag: a_ufrag,
                remote_pwd: a_pwd,
                role: Role::Controlled,
                tie: 0x0807060504030201,
            }
        } else {
            Creds {
                local_ufrag: a_ufrag,
                local_pwd: a_pwd,
                remote_ufrag: b_ufrag,
                remote_pwd: b_pwd,
                role: Role::Controlling,
                tie: 0x0102030405060708,
            }
        }
    }

    fn encode(m: Message<Attribute>) -> Vec<u8> {
        MessageEncoder::new().encode_into_bytes(m).unwrap()
    }

    #[test]
    fn rfc5769_vectors_round_trip() {
        for input in [
            &RFC5769_REQUEST[..],
            &RFC5769_IPV4_RESPONSE[..],
            &RFC5769_IPV6_RESPONSE[..],
        ] {
            let msg = MessageDecoder::<Attribute>::new()
                .decode_from_bytes(input)
                .unwrap()
                .unwrap();
            assert_eq!(encode(msg.clone()), input);
            msg.get_attribute::<MessageIntegrity>()
                .unwrap()
                .check_short_term_credential(RFC5769_PWD)
                .unwrap();
        }
        let request = MessageDecoder::<Attribute>::new()
            .decode_from_bytes(&RFC5769_REQUEST)
            .unwrap()
            .unwrap();
        assert_eq!(
            request.get_attribute::<Priority>().unwrap().prio(),
            0x6e0001ff
        );
        assert!(request.get_attribute::<IceControlled>().is_some());
    }

    #[test]
    fn binding_request_matches_vector() {
        let mut want = hex(BINDING_REQUEST_HEAD);
        want.resize(BINDING_REQUEST_LEN, 0);
        let id = txid(BINDING_TXID);
        assert_eq!(binding_request(&id).to_vec(), want);
        let mut m = Message::new(MessageClass::Request, BINDING, TransactionId::new(id));
        m.add_attribute(Padding(vec![0; 76]));
        assert_eq!(encode(m), want);
    }

    #[test]
    fn binding_response_vector() {
        let id = txid(BINDING_TXID);
        let resp = hex(BINDING_RESPONSE_V4);
        let local = addr("192.168.1.10:50000");
        assert_eq!(
            read_binding_response(&resp, &id, local),
            Some(Mapped {
                addr: addr("203.0.113.7:40000"),
                proof: Some(hex(PROOF_V4)),
            })
        );
        // Our attribute set encodes it byte for byte.
        let mut m = Message::new(
            MessageClass::SuccessResponse,
            BINDING,
            TransactionId::new(id),
        );
        m.add_attribute(XorMappedAddress::new(addr("203.0.113.7:40000")));
        m.add_attribute(LeapgateProof(hex(PROOF_V4)));
        let fp = Fingerprint::new(&m).unwrap();
        m.add_attribute(fp);
        assert_eq!(encode(m), resp);
        // Another transaction, or a mapped address of the other family.
        let mut other = id;
        other[11] ^= 1;
        assert_eq!(read_binding_response(&resp, &other, local), None);
        assert_eq!(
            read_binding_response(&resp, &id, addr("[2001:db8::1]:5000")),
            None
        );
        // A proof is optional, anything else is not.
        let mut m = Message::new(
            MessageClass::SuccessResponse,
            BINDING,
            TransactionId::new(id),
        );
        m.add_attribute(XorMappedAddress::new(addr("203.0.113.7:40000")));
        let fp = Fingerprint::new(&m).unwrap();
        m.add_attribute(fp);
        let got = read_binding_response(&encode(m), &id, local).unwrap();
        assert_eq!(got.proof, None);
        let mut m = Message::new(
            MessageClass::SuccessResponse,
            BINDING,
            TransactionId::new(id),
        );
        m.add_attribute(XorMappedAddress::new(addr("203.0.113.7:40000")));
        m.add_attribute(Priority::new(1));
        let fp = Fingerprint::new(&m).unwrap();
        m.add_attribute(fp);
        assert_eq!(read_binding_response(&encode(m), &id, local), None);
    }

    #[test]
    fn check_vectors() {
        let (a, b) = (creds(false), creds(true));
        let id = txid(CHECK_TXID);
        let request = hex(CHECK_REQUEST);
        assert_eq!(a.request(&id, 0x6effffff, true).unwrap(), request);
        assert_eq!(
            b.read_request(&request),
            Some(Request {
                txid: id,
                priority: 0x6effffff,
                nominate: true,
            })
        );
        let mut wrong_pwd = creds(true);
        wrong_pwd.local_pwd.replace_range(0..1, "c");
        assert_eq!(wrong_pwd.read_request(&request), None);

        let response = hex(CHECK_RESPONSE);
        let a_addr = addr("192.168.1.10:50000");
        assert_eq!(b.response(&id, a_addr).unwrap(), response);
        assert_eq!(a.read_response(&response), Some((id, a_addr)));
        assert_eq!(b.read_response(&response), None);
    }

    /// A's check, assembled from `attrs` and closed with MESSAGE-INTEGRITY under B's password
    /// and FINGERPRINT, then whatever `tail` adds before the FINGERPRINT.
    fn assemble(attrs: Vec<Attribute>, tail: Vec<Attribute>) -> Vec<u8> {
        let id = txid(CHECK_TXID);
        let mut m = Message::new(MessageClass::Request, BINDING, TransactionId::new(id));
        for a in attrs {
            m.add_attribute(a);
        }
        let mi = MessageIntegrity::new_short_term_credential(&m, &"b".repeat(24)).unwrap();
        m.add_attribute(mi);
        for a in tail {
            m.add_attribute(a);
        }
        let fp = Fingerprint::new(&m).unwrap();
        m.add_attribute(fp);
        encode(m)
    }

    fn check_attrs() -> Vec<Attribute> {
        vec![
            Username::new("BBBBBBBB:AAAAAAAA".to_owned())
                .unwrap()
                .into(),
            Priority::new(0x6effffff).into(),
            IceControlling::new(0x0102030405060708).into(),
        ]
    }

    #[test]
    fn request_structure_rules() {
        let b = creds(true);
        assert!(b.read_request(&assemble(check_attrs(), vec![])).is_some());
        // Something after MESSAGE-INTEGRITY, which it does not cover.
        let after = assemble(check_attrs(), vec![UseCandidate::new().into()]);
        assert_eq!(b.read_request(&after), None);
        // A second MESSAGE-INTEGRITY, valid over everything before it, right before the
        // FINGERPRINT.
        let mut m = Message::<Attribute>::new(
            MessageClass::Request,
            BINDING,
            TransactionId::new(txid(CHECK_TXID)),
        );
        for a in check_attrs() {
            m.add_attribute(a);
        }
        let mi = MessageIntegrity::new_short_term_credential(&m, &"b".repeat(24)).unwrap();
        m.add_attribute(mi);
        let second = MessageIntegrity::new_short_term_credential(&m, &"b".repeat(24)).unwrap();
        assert_eq!(
            b.read_request(&assemble(check_attrs(), vec![second.into()])),
            None
        );
        // A known attribute twice, with a valid MESSAGE-INTEGRITY over both.
        let mut twice = check_attrs();
        twice.push(Priority::new(0x7effffff).into());
        assert_eq!(b.read_request(&assemble(twice, vec![])), None);
    }

    #[test]
    fn unknown_attribute_is_refused() {
        use stun_codec::rfc5389::attributes::Software;
        stun_codec::define_attribute_enums!(
            WithSoftware,
            WithSoftwareDecoder,
            WithSoftwareEncoder,
            [
                Username,
                Priority,
                IceControlling,
                Software,
                MessageIntegrity,
                Fingerprint
            ]
        );
        let mut m = Message::<WithSoftware>::new(
            MessageClass::Request,
            BINDING,
            TransactionId::new(txid(CHECK_TXID)),
        );
        m.add_attribute(Username::new("BBBBBBBB:AAAAAAAA".to_owned()).unwrap());
        m.add_attribute(Priority::new(0x6effffff));
        m.add_attribute(IceControlling::new(1));
        m.add_attribute(Software::new_static("x"));
        let mi = MessageIntegrity::new_short_term_credential(&m, &"b".repeat(24)).unwrap();
        m.add_attribute(mi);
        let fp = Fingerprint::new(&m).unwrap();
        m.add_attribute(fp);
        let bytes = MessageEncoder::new().encode_into_bytes(m).unwrap();
        assert_eq!(creds(true).read_request(&bytes), None);
    }

    #[test]
    fn requests_with_the_wrong_role_are_dropped() {
        let (a, b) = (creds(false), creds(true));
        let id = txid(CHECK_TXID);
        // B sends A a check claiming to be controlling, and A a check carrying USE-CANDIDATE.
        let mut as_controlling = creds(true);
        as_controlling.role = Role::Controlling;
        assert_eq!(
            a.read_request(&as_controlling.request(&id, 1, false).unwrap()),
            None
        );
        assert!(a.read_request(&b.request(&id, 1, false).unwrap()).is_some());
        assert_eq!(a.read_request(&nominating_check(&b, &id)), None);
        // A sends B a check claiming to be controlled.
        let mut as_controlled = creds(false);
        as_controlled.role = Role::Controlled;
        assert_eq!(
            b.read_request(&as_controlled.request(&id, 1, true).unwrap()),
            None
        );
    }

    /// B's check to A with USE-CANDIDATE added, which only A may send.
    fn nominating_check(b: &Creds, id: &TxId) -> Vec<u8> {
        let mut m = Message::new(MessageClass::Request, BINDING, TransactionId::new(*id));
        m.add_attribute(Username::new(format!("{}:{}", b.remote_ufrag, b.local_ufrag)).unwrap());
        m.add_attribute(Priority::new(1));
        m.add_attribute(IceControlled::new(b.tie));
        m.add_attribute(UseCandidate::new());
        seal(m, &b.remote_pwd).unwrap()
    }

    #[test]
    fn junk_never_panics() {
        let (a, b) = (creds(false), creds(true));
        let id = txid(CHECK_TXID);
        let local = addr("192.168.1.10:50000");
        let feed = |buf: &[u8]| {
            let _ = MessageDecoder::<Attribute>::new().decode_from_bytes(buf);
            let _ = read_binding_response(buf, &id, local);
            let _ = a.read_request(buf);
            let _ = b.read_request(buf);
            let _ = a.read_response(buf);
        };
        for valid in [
            hex(CHECK_REQUEST),
            hex(CHECK_RESPONSE),
            hex(BINDING_RESPONSE_V4),
            RFC5769_REQUEST.to_vec(),
        ] {
            for n in 0..valid.len() {
                feed(&valid[..n]);
                // The same prefix with its length field fixed up, so it passes `is_stun`.
                let mut cut = valid[..n & !3].to_vec();
                if cut.len() >= 20 {
                    let len = (cut.len() - 20) as u16;
                    cut[2..4].copy_from_slice(&len.to_be_bytes());
                    feed(&cut);
                }
            }
        }
        for _ in 0..4000 {
            let len = 24 + 4 * (rand::random::<usize>() % 40);
            let mut buf: Vec<u8> = (0..len).map(|_| rand::random()).collect();
            feed(&buf);
            buf[0] &= 0x01;
            buf[2..4].copy_from_slice(&((len - 20) as u16).to_be_bytes());
            buf[4..8].copy_from_slice(&MAGIC);
            feed(&buf);
            // Plausible attribute headers, to get past the first attribute.
            buf[20..22].copy_from_slice(&[0x00, 0x06]);
            buf[22..24].copy_from_slice(&(rand::random::<u16>() % 64).to_be_bytes());
            feed(&buf);
        }
    }

    #[test]
    fn txid_and_kcp_syn() {
        for _ in 0..1000 {
            let id = new_txid();
            assert_eq!(id[4], 0);
            assert!(!is_kcp_syn(&binding_request(&id)));
        }
        // Upstream's SYN: conv, both session ids 0, SYN.
        let syn = [0x2a, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01, 0x00];
        assert!(is_kcp_syn(&syn));
        for flag in [0x00, 0x02, 0x03, 0x05, 0x09, 0x11, 0x21] {
            let mut p = syn;
            p[12] = flag;
            assert!(!is_kcp_syn(&p), "{flag:#x}");
        }
        // RFC 5769's request has 0xbc (PING among others) at offset 12.
        assert!(!is_kcp_syn(&RFC5769_REQUEST));
        // KCP's RST echo of one of our checks: its first 12 bytes, then RST.
        let mut rst = hex(CHECK_REQUEST)[..14].to_vec();
        rst[12] = 0x10;
        rst[13] = 0;
        assert!(!is_kcp_syn(&rst));
        assert!(!is_stun(&rst));
    }
}
