import 'package:flutter_hbb/leapgate/settings/settings_api.dart';

/// [SettingsApi] for tests: answers what the test sets and records what was asked.
class FakeSettingsApi implements SettingsApi {
  SaveResult saveResult = SaveResult.saved;
  final saved = <Map<String, String>>[];

  bool socksResult = true;
  final socks = <({String proxy, String username, String password})>[];

  AllowNetsCheck Function(String text) onAllowNets =
      (_) => const AllowNetsCheck(valid: true, count: 0);
  ServerSummary summary = const ServerSummary();
  ServerKind kind = ServerKind.leapgate;
  KeyCheck Function(String key) onKey =
      (key) => key.isEmpty ? KeyCheck.empty : KeyCheck.valid;
  List<LocalAdapter> adapters = const [];
  DirectListen listen = const DirectListen();
  BotCheck bot = (result: 'ok', text: '');
  TwoFactorCheck twoFactor = 'ok';

  @override
  Future<SaveResult> setOptions(Map<String, String> changes) async {
    saved.add(Map.of(changes));
    return saveResult;
  }

  @override
  Future<bool> setSocks(String proxy, String username, String password) async {
    socks.add((proxy: proxy, username: username, password: password));
    return socksResult;
  }

  @override
  AllowNetsCheck allowNetsCheck(String text) => onAllowNets(text);

  @override
  Future<ServerSummary> serverSummary() async => summary;

  @override
  ServerKind serverKind() => kind;

  @override
  KeyCheck keyCheck(String key) => onKey(key);

  @override
  Future<List<LocalAdapter>> localAddresses() async => adapters;

  @override
  Future<DirectListen> directListen() async => listen;

  @override
  Future<BotCheck> verifyBot(String token) async => bot;

  @override
  Future<TwoFactorCheck> verify2fa(String code) async => twoFactor;
}
