import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/bridge.dart';

import 'navigation.dart';

// Links and `--connect`: `leapgate.exe --connect <ID>` (with `--password`, `--relay`) and
// `leapgate://` links. The Rust core hands a later launch's arguments to the running main window
// as a `leapgate://` link (`src/core_main.rs` `core_main_invoke_new_connection`, W1); a launch
// that finds no main window keeps them on its own command line. The parsing follows upstream
// `flutter/lib/common.dart:2256-2523` (`handleUriLink`, `urlLinkToCmdArgs`); M2a opens only a
// remote desktop, the other kinds are logged.

/// A remote desktop to open.
typedef ConnectLink = ({
  String id,
  String password,
  String switchUuid,
  bool forceRelay,
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

/// The remote desktop that [args] ask for (upstream `handleUriLink`'s loop); null for anything
/// else.
ConnectLink? connectLinkOf(List<String> args) {
  String? id;
  var password = '';
  var switchUuid = '';
  var forceRelay = false;
  String? other;
  for (var i = 0; i < args.length; i++) {
    final next = i + 1 < args.length ? args[i + 1] : null;
    switch (args[i]) {
      case '--connect':
      case '--play':
        id = next;
        i++;
      case '--file-transfer':
      case '--view-camera':
      case '--port-forward':
      case '--rdp':
      case '--terminal':
      case '--terminal-admin':
        other = args[i];
        i++;
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
  if (other != null) {
    // M2a opens remote desktops only; the other views come with their blocks.
    lgBind.leapgateLog(level: 3, msg: 'leapgate ui: link not handled: $other');
    return null;
  }
  if (id == null) return null;
  return (
    id: id,
    password: password,
    switchUuid: switchUuid,
    forceRelay: forceRelay
  );
}

/// The arguments of a launch, or of a link handed over by a later launch: opens the remote
/// desktop they ask for and brings the window up. [uriPrefix] is `bind.mainUriPrefixSync()`
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

/// A link that a later launch handed to this window.
bool handleLink(Uri uri) => _open(linkToArgs(uri));

bool _open(List<String>? args) {
  if (args == null) return false;
  if (args.isEmpty) {
    appCore.window.bringToFront();
    return true;
  }
  final link = connectLinkOf(args);
  if (link == null) return false;
  mainNavigation.connect(link.id,
      password: link.password,
      switchUuid: link.switchUuid,
      forceRelay: link.forceRelay);
  appCore.window.bringToFront();
  return true;
}
