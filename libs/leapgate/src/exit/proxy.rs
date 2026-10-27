//! Controller: the local SOCKS5 / HTTP CONNECT handshake (contract 03).
//!
//! Only CONNECT to a TCP destination, without authentication. The destination goes to the exit
//! as given: a domain is not lowercased, converted or resolved here, and a fake-ip literal is not
//! filtered (C12), the exit judges both.

use hbb_common::tokio::{
    io::{AsyncRead, AsyncReadExt, AsyncWrite, AsyncWriteExt},
    time::timeout,
};
use std::{
    io,
    net::{IpAddr, Ipv4Addr, Ipv6Addr},
    time::Duration,
};

pub const HANDSHAKE_TIMEOUT: Duration = Duration::from_secs(10);
/// Request line and headers of an HTTP CONNECT, up to and including the blank line.
pub const MAX_HEAD: usize = 8 * 1024;

#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Kind {
    Socks5,
    Http,
}

#[derive(Debug, PartialEq)]
pub struct Request {
    pub kind: Kind,
    pub host: String,
    pub port: u16,
    /// Bytes after the HTTP head, for the channel to send first.
    pub leftover: Vec<u8>,
}

#[derive(Debug, PartialEq)]
pub enum Refused {
    Socks4,
    NoMethod,
    Command,
    AddressType,
    BadTarget,
    NotConnect,
    BadRequest,
    Timeout,
    Io,
}

const SOCKS4_REJECT: [u8; 8] = [0x00, 0x5B, 0, 0, 0, 0, 0, 0];
const REP_FAILURE: u8 = 0x01;
const REP_COMMAND: u8 = 0x07;
const REP_ADDRESS_TYPE: u8 = 0x08;
const HTTP_OK: &[u8] = b"HTTP/1.1 200 Connection established\r\n\r\n";
const HTTP_502: &[u8] =
    b"HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
const HTTP_501: &[u8] =
    b"HTTP/1.1 501 Not Implemented\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
const HTTP_400: &[u8] =
    b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";

fn socks5_reply(rep: u8) -> [u8; 10] {
    [0x05, rep, 0x00, 0x01, 0, 0, 0, 0, 0, 0]
}

/// Reads one request within HANDSHAKE_TIMEOUT. On refusal the refusal reply is already written;
/// on timeout nothing is.
pub async fn accept<S: AsyncRead + AsyncWrite + Unpin>(s: &mut S) -> Result<Request, Refused> {
    timeout(HANDSHAKE_TIMEOUT, handshake(s))
        .await
        .unwrap_or(Err(Refused::Timeout))
}

/// The answer to a request `accept` returned: whether its channel is being opened.
pub async fn reply<S: AsyncWrite + Unpin>(s: &mut S, kind: Kind, ok: bool) -> io::Result<()> {
    match (kind, ok) {
        (Kind::Socks5, true) => s.write_all(&socks5_reply(0x00)).await,
        (Kind::Socks5, false) => s.write_all(&socks5_reply(REP_FAILURE)).await,
        (Kind::Http, true) => s.write_all(HTTP_OK).await,
        (Kind::Http, false) => s.write_all(HTTP_502).await,
    }
}

async fn handshake<S: AsyncRead + AsyncWrite + Unpin>(s: &mut S) -> Result<Request, Refused> {
    match read_u8(s).await? {
        0x05 => socks5(s).await,
        0x04 => refuse(s, &SOCKS4_REJECT, Refused::Socks4).await,
        first => http(s, first).await,
    }
}

async fn refuse<S: AsyncWrite + Unpin>(
    s: &mut S,
    reply: &[u8],
    why: Refused,
) -> Result<Request, Refused> {
    s.write_all(reply).await.map_err(|_| Refused::Io)?;
    Err(why)
}

async fn read_u8<S: AsyncRead + Unpin>(s: &mut S) -> Result<u8, Refused> {
    s.read_u8().await.map_err(|_| Refused::Io)
}

async fn read_exact<S: AsyncRead + Unpin, const N: usize>(s: &mut S) -> Result<[u8; N], Refused> {
    let mut buf = [0u8; N];
    s.read_exact(&mut buf).await.map_err(|_| Refused::Io)?;
    Ok(buf)
}

/// RFC 1928, after the version byte. Reads exactly the request, so nothing is left over.
async fn socks5<S: AsyncRead + AsyncWrite + Unpin>(s: &mut S) -> Result<Request, Refused> {
    let n = read_u8(s).await?;
    let mut methods = vec![0u8; n as usize];
    s.read_exact(&mut methods).await.map_err(|_| Refused::Io)?;
    if !methods.contains(&0x00) {
        return refuse(s, &[0x05, 0xFF], Refused::NoMethod).await;
    }
    s.write_all(&[0x05, 0x00]).await.map_err(|_| Refused::Io)?;
    let [ver, cmd, _rsv, atyp] = read_exact::<_, 4>(s).await?;
    if ver != 0x05 {
        return Err(Refused::BadRequest);
    }
    if cmd != 0x01 {
        return refuse(s, &socks5_reply(REP_COMMAND), Refused::Command).await;
    }
    let host = match atyp {
        0x01 => Some(IpAddr::from(Ipv4Addr::from(read_exact::<_, 4>(s).await?)).to_string()),
        0x04 => Some(IpAddr::from(Ipv6Addr::from(read_exact::<_, 16>(s).await?)).to_string()),
        0x03 => {
            let len = read_u8(s).await?;
            let mut name = vec![0u8; len as usize];
            s.read_exact(&mut name).await.map_err(|_| Refused::Io)?;
            String::from_utf8(name).ok().filter(|n| !n.is_empty())
        }
        _ => return refuse(s, &socks5_reply(REP_ADDRESS_TYPE), Refused::AddressType).await,
    };
    let port = u16::from_be_bytes(read_exact::<_, 2>(s).await?);
    match host {
        Some(host) if port != 0 => Ok(Request {
            kind: Kind::Socks5,
            host,
            port,
            leftover: Vec::new(),
        }),
        _ => refuse(s, &socks5_reply(REP_FAILURE), Refused::BadTarget).await,
    }
}

async fn http<S: AsyncRead + AsyncWrite + Unpin>(s: &mut S, first: u8) -> Result<Request, Refused> {
    let mut buf = vec![first];
    let end = loop {
        if let Some(i) = buf.windows(4).position(|w| w == b"\r\n\r\n") {
            break i + 4;
        }
        if buf.len() >= MAX_HEAD {
            return refuse(s, HTTP_400, Refused::BadRequest).await;
        }
        let mut chunk = [0u8; 2048];
        let n = s.read(&mut chunk).await.map_err(|_| Refused::Io)?;
        if n == 0 {
            return Err(Refused::Io);
        }
        buf.extend_from_slice(&chunk[..n]);
    };
    if end > MAX_HEAD {
        return refuse(s, HTTP_400, Refused::BadRequest).await;
    }
    match parse_connect(&buf[..end]) {
        Ok((host, port)) => Ok(Request {
            kind: Kind::Http,
            host,
            port,
            leftover: buf.split_off(end),
        }),
        Err(Refused::NotConnect) => refuse(s, HTTP_501, Refused::NotConnect).await,
        Err(why) => refuse(s, HTTP_400, why).await,
    }
}

/// The CONNECT target from an HTTP head. Every header is ignored, `Host` included.
fn parse_connect(head: &[u8]) -> Result<(String, u16), Refused> {
    let line = head
        .split(|&b| b == b'\n')
        .next()
        .and_then(|l| l.strip_suffix(b"\r"))
        .and_then(|l| std::str::from_utf8(l).ok())
        .ok_or(Refused::BadRequest)?;
    let parts: Vec<&str> = line.split(' ').collect();
    let [method, authority, version] = parts[..] else {
        return Err(Refused::BadRequest);
    };
    if method != "CONNECT" {
        return Err(Refused::NotConnect);
    }
    if !version.starts_with("HTTP/1.") {
        return Err(Refused::BadRequest);
    }
    let (host, port) = match authority.strip_prefix('[') {
        Some(rest) => {
            let (host, port) = rest.split_once("]:").ok_or(Refused::BadRequest)?;
            if host.parse::<Ipv6Addr>().is_err() {
                return Err(Refused::BadRequest);
            }
            (host, port)
        }
        None => match authority.rsplit_once(':') {
            Some((host, port)) if !host.contains(':') => (host, port),
            _ => return Err(Refused::BadRequest),
        },
    };
    if host.is_empty() || port.is_empty() || !port.bytes().all(|b| b.is_ascii_digit()) {
        return Err(Refused::BadRequest);
    }
    match port.parse::<u16>() {
        Ok(port) if port != 0 => Ok((host.to_owned(), port)),
        _ => Err(Refused::BadRequest),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::tokio::{self, io::duplex};

    /// What the local program reads back, and what `accept` made of `input`.
    async fn handshake_with(input: &[u8]) -> (Vec<u8>, Result<Request, Refused>) {
        let (mut client, mut proxy) = duplex(64 * 1024);
        client.write_all(input).await.unwrap();
        let res = accept(&mut proxy).await;
        drop(proxy);
        let mut out = Vec::new();
        client.read_to_end(&mut out).await.unwrap();
        (out, res)
    }

    fn socks5_connect(atyp: u8, addr: &[u8], port: u16) -> Vec<u8> {
        let mut v = vec![0x05, 0x01, 0x00, 0x05, 0x01, 0x00, atyp];
        v.extend_from_slice(addr);
        v.extend_from_slice(&port.to_be_bytes());
        v
    }

    fn domain(name: &[u8]) -> Vec<u8> {
        let mut v = vec![name.len() as u8];
        v.extend_from_slice(name);
        v
    }

    fn target(res: Result<Request, Refused>) -> (Kind, String, u16, Vec<u8>) {
        let r = res.unwrap();
        (r.kind, r.host, r.port, r.leftover)
    }

    #[tokio::test(crate = "hbb_common::tokio")]
    async fn socks5_domain_connect() {
        let (out, res) = handshake_with(&socks5_connect(0x03, &domain(b"example.com"), 443)).await;
        assert_eq!(out, [0x05, 0x00]);
        assert_eq!(
            target(res),
            (Kind::Socks5, "example.com".to_owned(), 443, vec![])
        );
        let (mut client, mut proxy) = duplex(64);
        reply(&mut proxy, Kind::Socks5, true).await.unwrap();
        reply(&mut proxy, Kind::Socks5, false).await.unwrap();
        drop(proxy);
        let mut out = Vec::new();
        client.read_to_end(&mut out).await.unwrap();
        assert_eq!(
            out,
            [
                0x05, 0x00, 0x00, 0x01, 0, 0, 0, 0, 0, 0, //
                0x05, 0x01, 0x00, 0x01, 0, 0, 0, 0, 0, 0,
            ]
        );
    }

    #[tokio::test(crate = "hbb_common::tokio")]
    async fn socks5_refusals() {
        let (out, res) = handshake_with(&[0x05, 0x01, 0x02]).await;
        assert_eq!((out, res), (vec![0x05, 0xFF], Err(Refused::NoMethod)));
        for cmd in [0x02, 0x03] {
            let (out, res) = handshake_with(&[0x05, 0x01, 0x00, 0x05, cmd, 0x00, 0x01]).await;
            assert_eq!(out[2..], socks5_reply(REP_COMMAND));
            assert_eq!(res, Err(Refused::Command));
        }
        let (out, res) = handshake_with(&[0x05, 0x01, 0x00, 0x05, 0x01, 0x00, 0x05]).await;
        assert_eq!(out[2..], socks5_reply(REP_ADDRESS_TYPE));
        assert_eq!(res, Err(Refused::AddressType));
        for input in [
            socks5_connect(0x03, &domain(b"example.com"), 0),
            socks5_connect(0x03, &domain(b""), 443),
            socks5_connect(0x03, &domain(&[0xff, 0xfe]), 443),
        ] {
            let (out, res) = handshake_with(&input).await;
            assert_eq!(out[2..], socks5_reply(REP_FAILURE));
            assert_eq!(res, Err(Refused::BadTarget));
        }
    }

    #[tokio::test(crate = "hbb_common::tokio")]
    async fn socks5_ip_targets_keep_their_literal() {
        let (_, res) = handshake_with(&socks5_connect(0x01, &[192, 0, 2, 1], 80)).await;
        assert_eq!(target(res).1, "192.0.2.1");
        let v6: Ipv6Addr = "2001:db8::1".parse().unwrap();
        let (_, res) = handshake_with(&socks5_connect(0x04, &v6.octets(), 80)).await;
        assert_eq!(target(res).1, "2001:db8::1");
    }

    #[tokio::test(crate = "hbb_common::tokio")]
    async fn socks4_is_rejected() {
        let (out, res) = handshake_with(&[0x04, 0x01, 0x01, 0xbb, 192, 0, 2, 1, 0x00]).await;
        assert_eq!((out, res), (SOCKS4_REJECT.to_vec(), Err(Refused::Socks4)));
    }

    #[tokio::test(crate = "hbb_common::tokio")]
    async fn http_connect() {
        let (out, res) =
            handshake_with(b"CONNECT example.com:443 HTTP/1.1\r\nHost: other.test:80\r\n\r\nXYZ")
                .await;
        assert!(out.is_empty());
        assert_eq!(
            target(res),
            (Kind::Http, "example.com".to_owned(), 443, b"XYZ".to_vec())
        );
        let (_, res) = handshake_with(b"CONNECT [2001:db8::1]:443 HTTP/1.1\r\n\r\n").await;
        assert_eq!(target(res).1, "2001:db8::1");
        let (mut client, mut proxy) = duplex(256);
        reply(&mut proxy, Kind::Http, true).await.unwrap();
        reply(&mut proxy, Kind::Http, false).await.unwrap();
        drop(proxy);
        let mut out = Vec::new();
        client.read_to_end(&mut out).await.unwrap();
        assert_eq!(
            out,
            b"HTTP/1.1 200 Connection established\r\n\r\n\
              HTTP/1.1 502 Bad Gateway\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
        );
    }

    #[tokio::test(crate = "hbb_common::tokio")]
    async fn http_refusals() {
        let not_implemented =
            b"HTTP/1.1 501 Not Implemented\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
        let bad_request =
            b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n";
        for head in [
            &b"GET / HTTP/1.1\r\nHost: example.com\r\n\r\n"[..],
            b"GET http://example.com/ HTTP/1.1\r\n\r\n",
        ] {
            let (out, res) = handshake_with(head).await;
            assert_eq!(
                (out, res),
                (not_implemented.to_vec(), Err(Refused::NotConnect))
            );
        }
        for head in [
            &b"CONNECT example.com HTTP/1.1\r\n\r\n"[..],
            b"CONNECT 2001:db8::1:443 HTTP/1.1\r\n\r\n",
            b"CONNECT [example.com]:443 HTTP/1.1\r\n\r\n",
            b"CONNECT example.com:0 HTTP/1.1\r\n\r\n",
            b"CONNECT example.com:65536 HTTP/1.1\r\n\r\n",
        ] {
            let (out, res) = handshake_with(head).await;
            assert_eq!((out, res), (bad_request.to_vec(), Err(Refused::BadRequest)));
        }
        let mut long = b"CONNECT example.com:443 HTTP/1.1\r\n".to_vec();
        long.resize(MAX_HEAD, b'a');
        let (out, res) = handshake_with(&long).await;
        assert_eq!((out, res), (bad_request.to_vec(), Err(Refused::BadRequest)));
    }
}
