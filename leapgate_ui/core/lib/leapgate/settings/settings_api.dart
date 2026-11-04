// The one place the settings page reaches the M6 exports (`LEAPGATE.md` §10.13, 09 §2.4). Settings
// models and sections call [settingsApi] only; tests set a fake (`core/test/settings_fakes.dart`).
// The calls the page makes to block 1 (`bind.main*`) stay where they are used.
import 'dart:convert';

import '../bridge.dart';

/// `leapgate_set_options` (S9): saved by the service process and copied locally; saved locally
/// only (portable, or the user stopped the service, which imports it at its next start); or not
/// saved (installed, the service should be running and did not answer).
enum SaveResult { saved, savedLocal, failed }

/// One line of the allowed networks text (E5): not an address or network ([invalid], can't be
/// saved), or one the exit node always refuses ([blocked], a warning).
enum NetLineState { invalid, blocked }

/// `leapgate_exit_allow_nets_check`: [lines] are 1-based as typed; [value] is what to store in
/// `leapgate-exit-allow-nets` when [valid]; [count] is how many networks it allows.
class AllowNetsCheck {
  const AllowNetsCheck(
      {required this.valid,
      required this.count,
      this.lines = const {},
      this.value = ''});

  factory AllowNetsCheck.fromJson(Map<String, dynamic> m) => AllowNetsCheck(
        valid: m['valid'] == true,
        count: (m['count'] as num?)?.toInt() ?? 0,
        lines: {
          for (final l in m['lines'] as List? ?? const [])
            ((l as Map)['line'] as num).toInt():
                l['state'] == 'blocked' ? NetLineState.blocked : NetLineState.invalid,
        },
        value: m['value'] as String? ?? '',
      );

  final bool valid;
  final int count;
  final Map<int, NetLineState> lines;
  final String value;
}

/// Where a server value comes from (02 §1.5.2): the program file name, the user, a custom
/// client config (always empty in Leapgate), the cached server (in the built-in list or not),
/// derived from the ID server (API only), the build's default, or nothing.
enum ServerSource { exe, user, custom, cacheDefault, cacheLast, derived, byDefault, none }

ServerSource _source(String? s) => switch (s) {
      'exe' => ServerSource.exe,
      'user' => ServerSource.user,
      'custom' => ServerSource.custom,
      'cache_default' => ServerSource.cacheDefault,
      'cache_last' => ServerSource.cacheLast,
      'derived' => ServerSource.derived,
      'default' => ServerSource.byDefault,
      _ => ServerSource.none,
    };

/// `leapgate_server_summary` (S1): the values in use. [keySource] has no value: the page only
/// says whether a key is set. [relay] is what the user typed, empty when not. [idDefault] is the
/// build's first built-in ID server, empty without one, for the server dialog's "留空时使用默认值".
class ServerSummary {
  const ServerSummary(
      {this.id = '',
      this.idSource = ServerSource.none,
      this.idDefault = '',
      this.api = '',
      this.apiSource = ServerSource.none,
      this.keySource = ServerSource.none,
      this.keyBuiltin = false,
      this.relay = ''});

  factory ServerSummary.fromJson(Map<String, dynamic> m) {
    Map<String, dynamic> part(String k) =>
        (m[k] as Map?)?.cast<String, dynamic>() ?? const {};
    return ServerSummary(
      id: part('id')['value'] as String? ?? '',
      idSource: _source(part('id')['source'] as String?),
      idDefault: part('id')['default'] as String? ?? '',
      api: part('api')['value'] as String? ?? '',
      apiSource: _source(part('api')['source'] as String?),
      keySource: _source(part('key')['source'] as String?),
      keyBuiltin: part('key')['builtin'] == true,
      relay: part('relay')['value'] as String? ?? '',
    );
  }

  final String id;
  final ServerSource idSource;
  final String idDefault;
  final String api;
  final ServerSource apiSource;
  final ServerSource keySource;

  /// The build has a built-in key ("留空时使用内置的 Key" only then, 02 §1.6.8).
  final bool keyBuiltin;
  final String relay;
}

/// `leapgate_server_kind` (S2, R2-Q14).
enum ServerKind { leapgate, compat, checking }

/// `leapgate_key_check` (S3).
enum KeyCheck { empty, valid, invalid }

/// `leapgate_local_addresses` (S4): one physical adapter; temporary IPv6 addresses left out.
class LocalAdapter {
  const LocalAdapter({this.name = '', this.ipv4 = const [], this.ipv6 = const []});

  factory LocalAdapter.fromJson(Map<String, dynamic> m) => LocalAdapter(
        name: m['name'] as String? ?? '',
        ipv4: [for (final a in m['ipv4'] as List? ?? const []) a as String],
        ipv6: [for (final a in m['ipv6'] as List? ?? const []) a as String],
      );

  final String name;
  final List<String> ipv4;
  final List<String> ipv6;
}

/// `leapgate_direct_listen` (S5). Null [state] means no answer: the service isn't running or has
/// not tried yet. Read the `direct-server` option first: the record outlives switching it off.
class DirectListen {
  const DirectListen({this.state, this.port = 0, this.error = ''});

  factory DirectListen.fromJson(Map<String, dynamic> m) => DirectListen(
        state: m['state'] as String?,
        port: (m['port'] as num?)?.toInt() ?? 0,
        error: m['error'] as String? ?? '',
      );

  /// `listening` or `failed`.
  final String? state;
  final int port;

  /// With `failed`: `in_use`, `denied` (Windows 10013, often a port Hyper-V keeps) or `other`.
  final String error;
}

/// `leapgate_bot_lookup`: the chat a bot's latest message came from, to confirm before saving
/// (02 §1.6.4). [result] is `ok` (with the chat), `network`, `invalid_token`, `no_chat` or
/// `other` (the lookup failed otherwise, with Rust's [text]).
class BotLookup {
  const BotLookup(
      {required this.result,
      this.text = '',
      this.chatId = '',
      this.chatType = '',
      this.chatLabel = ''});

  factory BotLookup.fromJson(Map<String, dynamic> m) {
    final chat = (m['chat'] as Map?)?.cast<String, dynamic>() ?? const {};
    return BotLookup(
      result: m['result'] as String? ?? 'other',
      text: m['text'] as String? ?? '',
      chatId: chat['id'] as String? ?? '',
      chatType: chat['type'] as String? ?? '',
      chatLabel: chat['label'] as String? ?? '',
    );
  }

  final String result;
  final String text;
  final String chatId;

  /// `private`, `group`, `supergroup` or `channel`.
  final String chatType;

  /// "@username", or "First Last" without one; the name of a group or channel.
  final String chatLabel;
}

/// `leapgate_verify_2fa`: `ok`, `wrong_code`, or `not_saved` (the code was right but the service
/// did not keep the secret).
typedef TwoFactorCheck = String;

/// The exports of §10.13 as the settings page uses them.
abstract interface class SettingsApi {
  /// S9: writes [changes] (an empty value removes the key) to the service's options, reading
  /// its current table first on the same connection. Not for `stop-service`, which asks for
  /// administrator permission (`bind.mainSetOption`).
  Future<SaveResult> setOptions(Map<String, String> changes);

  /// S9 for the proxy: whether the service kept it.
  Future<bool> setSocks(String proxy, String username, String password);

  AllowNetsCheck allowNetsCheck(String text);

  Future<ServerSummary> serverSummary();

  ServerKind serverKind();

  KeyCheck keyCheck(String key);

  Future<List<LocalAdapter>> localAddresses();

  Future<DirectListen> directListen();

  /// Looks the bot up; saves nothing.
  Future<BotLookup> lookupBot(String token);

  /// Saves the bot and the confirmed chat; whether the service kept them.
  Future<bool> saveBot(String token, String chatId);

  Future<TwoFactorCheck> verify2fa(String code);
}

/// Set by tests; the app keeps the default.
SettingsApi settingsApi = const RustSettingsApi();

/// Block 2.
class RustSettingsApi implements SettingsApi {
  const RustSettingsApi();

  static Map<String, dynamic> _decode(String json) =>
      jsonDecode(json) as Map<String, dynamic>;

  @override
  Future<SaveResult> setOptions(Map<String, String> changes) async =>
      switch (await lgBind.leapgateSetOptions(changes: jsonEncode(changes))) {
        'saved' => SaveResult.saved,
        'saved_local' => SaveResult.savedLocal,
        _ => SaveResult.failed,
      };

  @override
  Future<bool> setSocks(String proxy, String username, String password) =>
      lgBind.leapgateSetSocks(
          proxy: proxy, username: username, password: password);

  @override
  AllowNetsCheck allowNetsCheck(String text) => AllowNetsCheck.fromJson(
      _decode(lgBind.leapgateExitAllowNetsCheck(text: text)));

  @override
  Future<ServerSummary> serverSummary() async =>
      ServerSummary.fromJson(_decode(await lgBind.leapgateServerSummary()));

  @override
  ServerKind serverKind() =>
      switch (_decode(lgBind.leapgateServerKind())['kind']) {
        'leapgate' => ServerKind.leapgate,
        'compat' => ServerKind.compat,
        _ => ServerKind.checking,
      };

  @override
  KeyCheck keyCheck(String key) => switch (lgBind.leapgateKeyCheck(key: key)) {
        'empty' => KeyCheck.empty,
        'valid' => KeyCheck.valid,
        _ => KeyCheck.invalid,
      };

  @override
  Future<List<LocalAdapter>> localAddresses() async => [
        for (final a
            in jsonDecode(await lgBind.leapgateLocalAddresses()) as List)
          LocalAdapter.fromJson(a as Map<String, dynamic>),
      ];

  @override
  Future<DirectListen> directListen() async =>
      DirectListen.fromJson(_decode(await lgBind.leapgateDirectListen()));

  // TODO(M6b 整合): `leapgate_bot_lookup` once block 2's bridge is generated again.
  @override
  Future<BotLookup> lookupBot(String token) => throw UnimplementedError();

  // TODO(M6b 整合): `leapgate_bot_save`, `ok` or `other`.
  @override
  Future<bool> saveBot(String token, String chatId) =>
      throw UnimplementedError();

  @override
  Future<TwoFactorCheck> verify2fa(String code) =>
      lgBind.leapgateVerify2Fa(code: code);
}
