//! HTTP client for the Leapgate API (`/api/leapgate/v1/`).
//!
//! Unlike upstream's `post_request`, there is no fallback that weakens transport security: no
//! accepting invalid certificates, no native-tls retry, no TCP-proxy or WebSocket relay. The
//! `allow-insecure-tls-fallback` option does not apply here.

use crate::sign;
use hbb_common::{
    config::Config,
    proxy::{Proxy, ProxyScheme},
    throttled_log, ResultType,
};
use reqwest::{redirect, Client, ClientBuilder};
use std::time::Duration;

/// Per attempt, connect and TLS handshake included; same as upstream's API requests.
const TIMEOUT: Duration = Duration::from_secs(12);
const LOG_INTERVAL: Duration = Duration::from_secs(60);

pub(crate) struct Resp {
    pub status: u16,
    pub body: Vec<u8>,
    pub server_sig: Option<String>,
}

/// Signs and posts `body` to `{base}/api/leapgate/v1/{endpoint}`. Returns the response and the
/// request's signature, which the response signature is bound to.
pub(crate) async fn post(
    base: &str,
    endpoint: &str,
    body: Vec<u8>,
) -> ResultType<(Resp, [u8; 64])> {
    let (auth, req_sig) = sign::device_auth("POST", endpoint, &body)?;
    let resp = client()?
        .post(format!("{base}/api/leapgate/v1/{endpoint}"))
        .header("Content-Type", "application/json")
        .header(sign::AUTH_HEADER, auth)
        .body(body)
        .timeout(TIMEOUT)
        .send()
        .await?;
    let status = resp.status().as_u16();
    let server_sig = resp
        .headers()
        .get(sign::SIG_HEADER)
        .and_then(|v| v.to_str().ok())
        .map(str::to_owned);
    let body = resp.bytes().await?.to_vec();
    Ok((
        Resp {
            status,
            body,
            server_sig,
        },
        req_sig,
    ))
}

fn builder() -> ClientBuilder {
    // System proxies are ignored as upstream does (rustdesk#11569).
    // Both the system store (for privately imported CAs) and the bundled webpki roots are
    // trusted: Windows downloads a missing root from Microsoft only when its own verifier needs
    // it, rustls reads just the local store, so a fresh install may lack the API's root (e.g.
    // ISRG Root X1).
    // Redirects are not followed: a 3xx comes back as is and counts as a failed request, never
    // as "no Leapgate API" and never as a hop to another host.
    Client::builder()
        .no_proxy()
        .use_rustls_tls()
        .redirect(redirect::Policy::none())
}

/// The proxy part follows upstream's `configure_http_client!`, including falling back to a
/// client without the proxy when it cannot be set up.
fn client() -> ResultType<Client> {
    let Some(conf) = Config::get_socks() else {
        return Ok(builder().build()?);
    };
    let proxy = match Proxy::from_conf(&conf, None) {
        Ok(proxy) => proxy,
        Err(e) => {
            throttled_log!(LOG_INTERVAL, info, "Failed to configure proxy: {}", e);
            return Ok(builder().build()?);
        }
    };
    let proxy_setup = match &proxy.intercept {
        ProxyScheme::Http { host, .. } => reqwest::Proxy::all(format!("http://{}", host)),
        ProxyScheme::Https { host, .. } => reqwest::Proxy::all(format!("https://{}", host)),
        ProxyScheme::Socks5 { addr, .. } => reqwest::Proxy::all(format!("socks5://{}", addr)),
    };
    let mut p = match proxy_setup {
        Ok(p) => p,
        Err(e) => {
            throttled_log!(LOG_INTERVAL, info, "Failed to set up proxy: {}", e);
            return Ok(builder().build()?);
        }
    };
    if let Some(auth) = proxy.intercept.maybe_auth() {
        if !auth.username().is_empty() && !auth.password().is_empty() {
            p = p.basic_auth(auth.username(), auth.password());
        }
    }
    match builder().proxy(p).build() {
        Ok(client) => Ok(client),
        Err(e) => {
            throttled_log!(
                LOG_INTERVAL,
                info,
                "Failed to create a proxied client: {}",
                e
            );
            Ok(builder().build()?)
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use hbb_common::tokio::{
        self,
        io::{AsyncReadExt, AsyncWriteExt},
        net::TcpListener,
    };

    #[hbb_common::tokio::test(crate = "hbb_common::tokio")]
    async fn redirect_is_not_followed() {
        let listener = TcpListener::bind("127.0.0.1:0").await.unwrap();
        let addr = listener.local_addr().unwrap();
        tokio::spawn(async move {
            // Answers every connection with a redirect back to itself.
            while let Ok((mut s, _)) = listener.accept().await {
                // Read the request first: closing with it unread would reset the connection.
                let mut buf = [0u8; 4096];
                let _ = s.read(&mut buf).await;
                let resp = format!(
                    "HTTP/1.1 302 Found\r\nLocation: http://{addr}/elsewhere\r\n\
                     Content-Length: 0\r\nConnection: close\r\n\r\n"
                );
                let _ = s.write_all(resp.as_bytes()).await;
            }
        });
        let resp = builder()
            .build()
            .unwrap()
            .post(format!("http://{addr}/api/leapgate/v1/heartbeat"))
            .send()
            .await
            .unwrap();
        assert_eq!(resp.status().as_u16(), 302);
    }
}
