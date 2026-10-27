// Leapgate application exit (phase 4): the exit mapping in the TCP tunneling window.

/// The login target of an exit tunnel; same values as `leapgate::exit` in Rust.
const String kLeapgateExitHost = 'leapgate-exit.invalid';
const int kLeapgateExitPort = 65536;

bool isLeapgateExit(String host, int port) =>
    host == kLeapgateExitHost && port == kLeapgateExitPort;

/// For the connection manager, which gets the normalized `host:port` string.
bool isLeapgateExitAddress(String addr) =>
    addr == '$kLeapgateExitHost:$kLeapgateExitPort';
