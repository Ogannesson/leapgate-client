//! One end of the netns NAT test (contract 05 §6.3), on the public ICE API only. The test script
//! does the signaling: each side prints its parameters as `params <hex>` (a serialized
//! `LeapgateIceParams`) and reads the other side's line from stdin.
//!
//! ```text
//! ice_peer --probe <local ip> <stun>...  `mapped <addr>` or `mapped none` per server, in turn
//! ice_peer offer <local ip> <stun>       A: prints its line, reads B's, checks, prints the result
//! ice_peer answer <local ip> <stun>      B: reads A's line, prints its own, waits for A's SYN
//! ```

use hbb_common::{
    bytes::Bytes,
    protobuf::Message as _,
    rendezvous_proto::{leapgate_ice_result::Kind, LeapgateIceParams},
    tokio::{
        self,
        io::{AsyncBufReadExt, BufReader},
    },
    ResultType,
};
use leapgate::ice::{gather_on, probe, Agent, AnswerParams, LocalAddr, Offer};
use std::{
    net::{IpAddr, SocketAddr},
    time::{Duration, Instant},
};

/// Shaped like upstream's first KCP packet, which is what the controlled side waits for.
const SYN: [u8; 14] = [0x2a, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x01, 0x00];
const USAGE: &str = "usage: ice_peer --probe|offer|answer <local ip> <stun addr>...";

fn main() {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let code = match tokio::runtime::Runtime::new() {
        Ok(rt) => match rt.block_on(run(&args)) {
            Ok(()) => 0,
            Err(e) => {
                eprintln!("ice_peer: {e}");
                2
            }
        },
        Err(e) => {
            eprintln!("ice_peer: {e}");
            2
        }
    };
    std::process::exit(code);
}

async fn run(args: &[String]) -> ResultType<()> {
    let [mode, ip, stun @ ..] = args else {
        hbb_common::bail!(USAGE);
    };
    let ip: IpAddr = ip.parse()?;
    let stun = stun
        .iter()
        .map(|s| s.parse())
        .collect::<Result<Vec<SocketAddr>, _>>()?;
    let local = [LocalAddr::new(ip, 0)];
    match mode.as_str() {
        "--probe" => {
            for m in probe(SocketAddr::new(ip, 0), &stun).await {
                match m {
                    Some(m) => println!("mapped {m}"),
                    None => println!("mapped none"),
                }
            }
        }
        "offer" => {
            let offer = Offer::new(gather_on(&local, &stun).await);
            print_params(offer.params());
            let peer = read_params().await?;
            let t0 = Instant::now();
            match offer.run(peer).await {
                Ok(s) => {
                    let ms = t0.elapsed().as_millis();
                    s.socket.connect(s.remote).await?;
                    for _ in 0..3 {
                        s.socket.send(&SYN).await?;
                        tokio::time::sleep(Duration::from_millis(100)).await;
                    }
                    let family = if s.family == 4 { "v4" } else { "v6" };
                    println!(
                        "selected {}/{family} <-> {}/{family} in {ms} ms",
                        kind(s.local_kind),
                        kind(s.remote_kind)
                    );
                }
                Err(_) => println!("no_pair"),
            }
        }
        "answer" => {
            let peer = read_params().await?;
            let agent = Agent::new(gather_on(&local, &stun).await, peer);
            print_params(agent.params());
            match agent.run().await {
                Ok(_) => println!("accepted"),
                Err(_) => println!("timed_out"),
            }
        }
        _ => hbb_common::bail!(USAGE),
    }
    Ok(())
}

fn kind(k: Kind) -> &'static str {
    match k {
        Kind::HOST => "host",
        Kind::SRFLX => "srflx",
        Kind::PRFLX => "prflx",
    }
}

fn print_params((ufrag, pwd, candidates, _proofs): (String, String, Vec<Bytes>, Vec<Bytes>)) {
    let mut p = LeapgateIceParams::new();
    p.ufrag = ufrag;
    p.pwd = pwd;
    p.candidates = candidates;
    let bytes = p.write_to_bytes().unwrap_or_default();
    let hex: String = bytes.iter().map(|b| format!("{b:02x}")).collect();
    println!("params {hex}");
}

async fn read_params() -> ResultType<AnswerParams> {
    let mut lines = BufReader::new(tokio::io::stdin()).lines();
    let line = lines.next_line().await?.unwrap_or_default();
    let hex = line.trim().trim_start_matches("params ");
    if hex.len() % 2 != 0 || !hex.is_ascii() {
        hbb_common::bail!("bad params line");
    }
    let bytes = (0..hex.len())
        .step_by(2)
        .map(|i| u8::from_str_radix(&hex[i..i + 2], 16))
        .collect::<Result<Vec<u8>, _>>()?;
    let p = LeapgateIceParams::parse_from_bytes(&bytes)?;
    AnswerParams::parse(&p).map_err(|_| hbb_common::anyhow::anyhow!("params break the rules"))
}
