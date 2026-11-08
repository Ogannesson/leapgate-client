import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/bridge.dart';

import 'navigation.dart';

// Links and `--connect`: `leapgate.exe --connect <ID>` (with `--password`, `--relay`) and
// `leapgate://` links. The Rust core hands a later launch's arguments to the running main window
// as a `leapgate://` link (`src/core_main.rs` `core_main_invoke_new_connection`, W1); a launch
// that finds no main window keeps them on its own command line. The parsing follows upstream
// `flutter/lib/common.dart:2256-2523` (`handleUriLink`, `urlLinkToCmdArgs`). A remote desktop and
// a file transfer open (M8-7); the third round's kinds are logged and say so in a toast.

/// What a link or `--<kind>` asks to open (`LEAPGATE.md` §10.18).
enum LinkKind {
  remoteDesktop,
  fileTransfer,
  terminal,
  terminalAdmin,
  camera,
  tcpTunnel,
  rdp,
}

/// A device to open as [kind].
typedef ConnectLink = ({
  String id,
  String password,
  String switchUuid,
  bool forceRelay,
  LinkKind kind,
});

/// Upstream `urlLinkToCmdArgs` without the phone-only parts (`config`, `password`, the direct
/// connect on mobile): the link as command line arguments; empty for a bare `leapgate://`, which
/// only brings the window up; null for a link that is not a connection.
List<String>? linkToArgs(Uri uri) {
  String? command;
  String? id;
  const options = [
    'connect',
    'play',
    'file-transfer',
    'view-camera',
    'port-forward',
    'rdp',
    'terminal',
    'terminal-admin',
  ];
  if (uri.authority.isEmpty &&
      uri.path.split('').every((char) => char == '/')) {
    return [];
  } else if (uri.authority == 'config' || uri.authority == 'password') {
    // Phone-only upstream; never a device ID here.
    return null;
  } else if (uri.authority == 'connection' && uri.path.startsWith('/new/')) {
    // For compatibility
    command = '--connect';
    id = uri.path.substring('/new/'.length);
  } else if (options.contains(uri.authority)) {
    command = '--${uri.authority}';
    if (uri.path.length > 1) {
      id = uri.path.substring(1);
    }
  } else if (uri.authority.length > 2 &&
      (uri.path.length <= 1 ||
          (uri.path == '/r' || uri.path.startsWith('/r@')))) {
    // leapgate://<connect-id>, leapgate://<connect-id>/r, leapgate://<connect-id>/r@<server>
    command = '--connect';
    id = uri.authority;
    if (uri.path.length > 1) {
      id = id + uri.path;
    }
  }
  if (command == null || id == null) return null;

  final param = uri.queryParameters.map((k, v) => MapEntry(k.toLowerCase(), v));
  final key = param['key'];
  if (key != null) id = '$id?key=$key';
  return [
    command,
    id,
    if (param['password'] != null) ...['--password', param['password']!],
    if (param['switch_uuid'] != null) ...['--switch_uuid', param['switch_uuid']!],
    if (param['relay'] != null) '--relay',
  ];
}

/// What [args] ask to open (upstream `handleUriLink`'s loop: the last kind given counts); null
/// without a device.
ConnectLink? connectLinkOf(List<String> args) {
  String? id;
  var password = '';
  var switchUuid = '';
  var forceRelay = false;
  var kind = LinkKind.remoteDesktop;
  for (var i = 0; i < args.length; i++) {
    final next = i + 1 < args.length ? args[i + 1] : null;
    final given = switch (args[i]) {
      '--connect' || '--play' => LinkKind.remoteDesktop,
      '--file-transfer' => LinkKind.fileTransfer,
      '--terminal' => LinkKind.terminal,
      '--terminal-admin' => LinkKind.terminalAdmin,
      '--view-camera' => LinkKind.camera,
      '--port-forward' => LinkKind.tcpTunnel,
      '--rdp' => LinkKind.rdp,
      _ => null,
    };
    if (given != null) {
      id = next;
      kind = given;
      i++;
      continue;
    }
    switch (args[i]) {
      case '--password':
        password = next ?? '';
        i++;
      case '--switch_uuid':
        switchUuid = next ?? '';
        i++;
      case '--relay':
        forceRelay = true;
    }
  }
  if (id == null) return null;
  return (
    id: id,
    password: password,
    switchUuid: switchUuid,
    forceRelay: forceRelay,
    kind: kind,
  );
}

/// The arguments of a launch, or of a link handed over by a later launch: opens the remote
/// desktop or file transfer they ask for and brings the window up. [uriPrefix] is `bind.mainUriPrefixSync()`
/// (`leapgate://`). Returns whether there was something to handle.
bool handleLaunchArgs(List<String> args, String uriPrefix) {
  if (args.isEmpty) return false;
  List<String>? linkArgs = args;
  if (args.isNotEmpty && args.first.startsWith(uriPrefix)) {
    final uri = Uri.tryParse(args.first);
    linkArgs = uri == null ? null : linkToArgs(uri);
  }
  return _open(linkArgs);
}

/// A link that a later launch handed to this window: a remote desktop or a file transfer opens,
/// the third round's kinds get a toast. A link that is not a connection is only logged, by
/// scheme and host: the path or the query may hold a password.
bool handleLink(Uri uri) {
  final args = linkToArgs(uri);
  if (args == null) {
    lgBind.leapgateLog(
        level: 3,
        msg: 'leapgate ui: link not handled: ${uri.scheme}://${uri.host}');
    return false;
  }
  return _open(args);
}

bool _open(List<String>? args) {
  if (args == null) return false;
  if (args.isEmpty) {
    appCore.window.bringToFront();
    return true;
  }
  final link = connectLinkOf(args);
  if (link == null) return false;
  switch (link.kind) {
    case LinkKind.remoteDesktop:
      mainNavigation.connect(link.id,
          password: link.password,
          switchUuid: link.switchUuid,
          forceRelay: link.forceRelay);
    case LinkKind.fileTransfer:
      mainNavigation.openFileTransfer(link.id,
          password: link.password, forceRelay: link.forceRelay);
    // TODO(M9b): the terminals and the camera. TODO(M9c): the TCP tunnel and RDP
    // (`LEAPGATE.md` §10.18). Until then they are logged and say so in a toast.
    case LinkKind.terminal ||
          LinkKind.terminalAdmin ||
          LinkKind.camera ||
          LinkKind.tcpTunnel ||
          LinkKind.rdp:
      return _unsupported(link.kind);
  }
  appCore.window.bringToFront();
  return true;
}

bool _unsupported(LinkKind kind) {
  lgBind.leapgateLog(
      level: 3, msg: 'leapgate ui: link not handled: ${kind.name}');
  appCore.toasts.show(switch (kind) {
    LinkKind.tcpTunnel => 'linkUnsupportedPortForward',
    LinkKind.rdp => 'linkUnsupportedRdp',
    LinkKind.camera => 'linkUnsupportedCamera',
    _ => 'linkUnsupportedTerminal',
  });
  appCore.window.bringToFront();
  return false;
}
