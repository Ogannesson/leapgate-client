// 上游：flutter/lib/common.dart@bd9262397（改写：只留 `ServerConfig` 的编解码和 `setServerConfig` 的修整与校验；`fromOptions` 改成读选项作用域；`encode` 用 utf8 编码（ASCII 时和上游逐字节相同）；保存时先校验全部栏、再向旧服务器退出登录、最后一次写入四个键（09 §4.5）。另含 `flutter/lib/common/widgets/api_server_warning.dart` 的 `_resolveApiServer`、`shouldWarnApiServer`）
// The network and server section (02 §1.5.2, §1.6.8, §1.6.9): the server configuration as the
// dialog edits, imports and exports it, how the summary marks where a value comes from, the save
// flow, and the proxy.
import 'dart:convert';

import '../../models/platform_model.dart';
import '../account.dart';
import '../options.dart';
import 'settings_api.dart';

/// Config: the servers the user typed; empty uses the default. Upstream writes them by these
/// names (`common.dart:3622-3625`) and has no constants for them.
const kOptionCustomRendezvousServer = 'custom-rendezvous-server';
const kOptionRelayServer = 'relay-server';
const kOptionApiServer = 'api-server';
const kOptionKey = 'key';

class ServerConfig {
  ServerConfig(
      {String idServer = '',
      String relayServer = '',
      String apiServer = '',
      String key = ''})
      : idServer = idServer.trim(),
        relayServer = relayServer.trim(),
        apiServer = apiServer.trim(),
        key = key.trim();

  /// What the user typed, as Config holds it.
  ServerConfig.fromOptions(OptionScope config)
      : this(
            idServer: config.get(kOptionCustomRendezvousServer),
            relayServer: config.get(kOptionRelayServer),
            apiServer: config.get(kOptionApiServer),
            key: config.get(kOptionKey));

  final String idServer;
  final String relayServer;
  final String apiServer;
  final String key;

  /// Decodes what the user shared or rustdesk-server generated: plain JSON (older form) or
  /// reversed base64 of it. Null when it is neither.
  static ServerConfig? tryDecode(String msg) {
    try {
      dynamic json;
      try {
        json = jsonDecode(msg);
      } catch (_) {
        final input = msg.split('').reversed.join('');
        final bytes = base64Decode(base64.normalize(input));
        json = jsonDecode(utf8.decode(bytes, allowMalformed: true));
      }
      if (json is! Map) return null;
      return ServerConfig(
        idServer: json['host'] as String? ?? '',
        relayServer: json['relay'] as String? ?? '',
        apiServer: json['api'] as String? ?? '',
        key: json['key'] as String? ?? '',
      );
    } catch (_) {
      return null;
    }
  }

  /// The shared form, see [tryDecode].
  String encode() {
    final config = {
      'host': idServer,
      'relay': relayServer,
      'api': apiServer,
      'key': key,
    };
    return base64UrlEncode(utf8.encode(jsonEncode(config)))
        .split('')
        .reversed
        .join();
  }

  /// Upstream `setServerConfig`: no slash at the end of the three addresses.
  ServerConfig normalized() {
    String removeEndSlash(String input) =>
        input.endsWith('/') ? input.substring(0, input.length - 1) : input;
    return ServerConfig(
      idServer: removeEndSlash(idServer),
      relayServer: removeEndSlash(relayServer),
      apiServer: removeEndSlash(apiServer),
      key: key,
    );
  }

  Map<String, String> toOptions() => {
        kOptionCustomRendezvousServer: idServer,
        kOptionRelayServer: relayServer,
        kOptionApiServer: apiServer,
        kOptionKey: key,
      };
}

/// What "导入" found on the clipboard.
enum ImportResult { empty, invalid, ok }

/// "导入" (upstream `importConfig`): the configuration to prefill the dialog with; an ID server is
/// required, as upstream requires it.
({ImportResult result, ServerConfig? config}) importServerConfig(
    String? clipboard) {
  final text = clipboard?.trim() ?? '';
  if (text.isEmpty) return (result: ImportResult.empty, config: null);
  final config = ServerConfig.tryDecode(text);
  if (config == null || config.idServer.isEmpty) {
    return (result: ImportResult.invalid, config: null);
  }
  return (result: ImportResult.ok, config: config);
}

/// "导出": the configuration in effect (02 §1.5.2), so a default server is exported by its
/// address; the key and the relay as typed.
String exportServerConfig(ServerSummary summary, OptionScope config) =>
    ServerConfig(
      idServer: summary.id,
      relayServer: config.get(kOptionRelayServer),
      apiServer: summary.api,
      key: config.get(kOptionKey),
    ).encode();

/// What the summary writes after a value (02 §1.5.2).
enum ServerMark { none, byDefault, lastUsed, derived }

/// The ID server: from the built-in list, the cached server in it or not, or as given.
ServerMark idServerMark(ServerSource source) => switch (source) {
      ServerSource.byDefault || ServerSource.cacheDefault => ServerMark.byDefault,
      ServerSource.cacheLast => ServerMark.lastUsed,
      _ => ServerMark.none,
    };

ServerMark apiServerMark(ServerSource source) => switch (source) {
      ServerSource.byDefault => ServerMark.byDefault,
      ServerSource.derived => ServerMark.derived,
      _ => ServerMark.none,
    };

/// The key line of the summary: "已设置（默认）", "已设置", "未设置".
enum KeyState { setByDefault, set, notSet }

KeyState keyState(ServerSource source) => switch (source) {
      ServerSource.byDefault => KeyState.setByDefault,
      ServerSource.none => KeyState.notSet,
      _ => KeyState.set,
    };

/// The build's first built-in ID server, what an empty field falls back to; empty without one.
String defaultIdServer(ServerSummary summary) => summary.idDefault;

/// The API server Rust uses for [api] and [idServer] as typed (upstream
/// `api_server_warning.dart` `_resolveApiServer`); empty when there is none.
String resolveApiServer(String api, String idServer) {
  final key = 'resolve-api-server:${jsonEncode([api, idServer])}';
  final response =
      jsonDecode(bind.mainGetCommonSync(key: key)) as Map<String, dynamic>;
  return response['url'] as String? ?? '';
}

/// Plain HTTP to anything but this device (upstream `shouldWarnApiServer`).
bool isPlainHttpApi(String apiServer) {
  final uri = Uri.tryParse(apiServer.trim());
  if (uri == null || uri.host.isEmpty || uri.scheme != 'http') return false;
  return !const {'localhost', '127.0.0.1', '::1'}.contains(uri.host);
}

/// Why a field of the server dialog was not saved.
enum ServerFieldError { unresolvable, apiScheme, keyFormat }

/// What "确定" in the server dialog came to: errors by option key ([detail] is Rust's text for
/// [ServerFieldError.unresolvable]), or the result of saving.
class ServerSaveOutcome {
  const ServerSaveOutcome({this.errors = const {}, this.result});

  final Map<String, ({ServerFieldError error, String detail})> errors;

  /// Null when nothing was saved.
  final SaveResult? result;
}

/// Rust's check of a server address: empty when it is usable, otherwise why not. Through a
/// SOCKS proxy only the form is checked, the proxy resolves the name
/// (`libs/hbb_common/src/socket_client.rs:79-101`).
Future<String> testServerAddress(String host, {bool withProxy = true}) =>
    bind.mainTestIfValidServer(server: host, testWithProxy: withProxy);

/// "确定" in the server dialog (upstream `setServerConfig`, order per 09 §4.5): checks every
/// field, signs out of the old API server when signed in and the API server in effect changes
/// (a failed sign-out does not stop the save), then writes the four keys at once.
Future<ServerSaveOutcome> saveServerConfig(ServerConfig config,
    {required String currentApi, required AccountModel account}) async {
  final c = config.normalized();
  final errors = <String, ({ServerFieldError error, String detail})>{};
  for (final (key, host) in [
    (kOptionCustomRendezvousServer, c.idServer),
    (kOptionRelayServer, c.relayServer),
  ]) {
    if (host.isEmpty) continue;
    final detail = await testServerAddress(host);
    if (detail.isNotEmpty) {
      errors[key] = (error: ServerFieldError.unresolvable, detail: detail);
    }
  }
  if (c.apiServer.isNotEmpty &&
      !c.apiServer.startsWith('http://') &&
      !c.apiServer.startsWith('https://')) {
    errors[kOptionApiServer] = (error: ServerFieldError.apiScheme, detail: '');
  }
  if (settingsApi.keyCheck(c.key) == KeyCheck.invalid) {
    errors[kOptionKey] = (error: ServerFieldError.keyFormat, detail: '');
  }
  if (errors.isNotEmpty) return ServerSaveOutcome(errors: errors);
  if (account.loggedIn &&
      resolveApiServer(c.apiServer, c.idServer) != currentApi) {
    await account.logout();
  }
  return ServerSaveOutcome(result: await settingsApi.setOptions(c.toOptions()));
}

/// The proxy as the service holds it; all empty when none is set.
typedef Socks = ({String proxy, String username, String password});

Future<Socks> readSocks() async {
  final s = await bind.mainGetSocks();
  return s.length == 3
      ? (proxy: s[0], username: s[1], password: s[2])
      : (proxy: '', username: '', password: '');
}

/// The longest proxy password Rust can store (upstream `mainMaxEncryptLen`).
int get maxProxyPasswordLength => bind.mainMaxEncryptLen();

/// What the proxy dialog checks: the address without its scheme (upstream
/// `changeSocks5Proxy`), resolved directly, not through the proxy.
Future<String> testProxyAddress(String proxy) => testServerAddress(
    proxy.contains('://') ? proxy.split('://')[1] : proxy,
    withProxy: false);
