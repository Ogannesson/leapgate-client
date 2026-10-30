import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/options.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:uuid/uuid.dart';

/// Keeps each store in a map the way Rust does: an empty value removes the key.
class _FakeBind implements RustdeskImpl {
  final config = <String, String>{};
  final local = <String, String>{};
  final peers = <String, Map<String, String>>{};
  final fixed = <String>{};
  final sessionOptions = <String, Map<String, String>>{};
  final sessionToggles = <String, Set<String>>{};

  static void _put(Map<String, String> m, String k, String v) =>
      v.isEmpty ? m.remove(k) : m[k] = v;

  @override
  String mainGetOptionSync({required String key, dynamic hint}) =>
      config[key] ?? '';

  @override
  Future<void> mainSetOption(
          {required String key, required String value, dynamic hint}) async =>
      _put(config, key, value);

  @override
  String mainGetLocalOption({required String key, dynamic hint}) =>
      local[key] ?? '';

  @override
  Future<void> mainSetLocalOption(
          {required String key, required String value, dynamic hint}) async =>
      _put(local, key, value);

  @override
  String mainGetPeerOptionSync(
          {required String id, required String key, dynamic hint}) =>
      peers[id]?[key] ?? '';

  @override
  Future<void> mainSetPeerOption(
          {required String id,
          required String key,
          required String value,
          dynamic hint}) async =>
      _put(peers.putIfAbsent(id, () => {}), key, value);

  @override
  bool mainIsOptionFixed({required String key, dynamic hint}) =>
      fixed.contains(key);

  @override
  bool mainIsInstalled({dynamic hint}) => true;

  @override
  Future<String?> sessionGetOption(
          {required UuidValue sessionId,
          required String arg,
          dynamic hint}) async =>
      sessionOptions[sessionId.toString()]?[arg] ?? '';

  @override
  Future<void> sessionPeerOption(
          {required UuidValue sessionId,
          required String name,
          required String value,
          dynamic hint}) async =>
      _put(sessionOptions.putIfAbsent(sessionId.toString(), () => {}), name,
          value);

  @override
  bool sessionGetToggleOptionSync(
          {required UuidValue sessionId, required String arg, dynamic hint}) =>
      sessionToggles[sessionId.toString()]?.contains(arg) ?? false;

  @override
  Future<void> sessionToggleOption(
      {required UuidValue sessionId,
      required String value,
      dynamic hint}) async {
    final s = sessionToggles.putIfAbsent(sessionId.toString(), () => {});
    if (!s.remove(value)) s.add(value);
  }

  final flutter = <String, String>{};

  @override
  String getLocalFlutterOption({required String k, dynamic hint}) =>
      flutter[k] ?? '';

  @override
  Future<void> setLocalFlutterOption(
          {required String k, required String v, dynamic hint}) async =>
      _put(flutter, k, v);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Counts how often [listenable] fires.
int Function() _count(Listenable listenable) {
  var n = 0;
  listenable.addListener(() => n++);
  return () => n;
}

void main() {
  late _FakeBind fake;
  late OptionsModel options;

  setUp(() {
    fake = _FakeBind();
    platformFFI.setBindingForTesting(fake);
    options = OptionsModel();
  });

  test('each scope reads and writes its own store', () async {
    expect(await options.config.set('k', 'c'), isTrue);
    expect(await options.local.set('k', 'l'), isTrue);
    expect(await options.peer('100').set('k', 'p'), isTrue);

    expect(fake.config, {'k': 'c'});
    expect(fake.local, {'k': 'l'});
    expect(fake.peers, {
      '100': {'k': 'p'}
    });
    expect(options.config.get('k'), 'c');
    expect(options.local.get('k'), 'l');
    expect(options.peer('100').get('k'), 'p');
    expect(options.peer('200').get('k'), '');

    await options.config.set('k', '');
    expect(fake.config, isEmpty);
  });

  test('the Flutter UI table of LocalConfig is a scope of its own', () async {
    await options.flutter.set('remoteMenubarState', '{"pin":true}');
    expect(fake.flutter, {'remoteMenubarState': '{"pin":true}'});
    expect(fake.local, isEmpty);
    expect(options.flutter.get('remoteMenubarState'), '{"pin":true}');
  });

  test('a write notifies listeners of that key in that scope only', () async {
    final configK = _count(options.config.listenable('k'));
    final configOther = _count(options.config.listenable('other'));
    final localK = _count(options.local.listenable('k'));
    final peerK = _count(options.peer('100').listenable('k'));

    await options.config.set('k', 'v');
    await options.config.setBool('k', false);
    expect(configK(), 2);
    expect(configOther(), 0);
    expect(localK(), 0);

    // peer() hands out one object per device, so a later lookup reaches the same listeners.
    await options.peer('100').set('k', 'v');
    await options.peer('200').set('k', 'v');
    expect(peerK(), 1);
  });

  test('boolean options follow upstream option2bool', () async {
    expect(option2bool('enable-x', ''), isTrue);
    expect(option2bool('enable-x', 'N'), isFalse);
    expect(option2bool('allow-x', ''), isFalse);
    expect(option2bool('allow-x', 'Y'), isTrue);
    expect(option2bool('stop-service', ''), isFalse);
    expect(option2bool('direct-server', ''), isFalse);
    expect(option2bool('force-always-relay', ''), isFalse);
    expect(option2bool('other', ''), isTrue);
    expect(option2bool('other', 'N'), isFalse);

    await options.config.setBool('enable-x', true);
    await options.config.setBool('allow-x', false);
    await options.local.setBool('other', false);
    expect(fake.config, {'enable-x': 'Y', 'allow-x': 'N'});
    expect(fake.local, {'other': 'N'});
    expect(options.config.getBool('enable-x'), isTrue);
    expect(options.config.getBool('allow-x'), isFalse);
    expect(options.local.getBool('other'), isFalse);
  });

  test('fixed options and the installed flag come from the bridge', () {
    fake.fixed.add('custom-rendezvous-server');
    expect(options.isFixed('custom-rendezvous-server'), isTrue);
    expect(options.isFixed('relay-server'), isFalse);
    expect(options.isInstalled, isTrue);
  });

  test('session options go to that session and notify', () async {
    final a = SessionOptions(const Uuid().v4obj());
    final b = SessionOptions(const Uuid().v4obj());
    final fps = _count(a.listenable('custom-fps'));
    final viewOnly = _count(a.listenable('view-only'));

    expect(await a.set('custom-fps', '30'), isTrue);
    expect(await a.get('custom-fps'), '30');
    expect(await b.get('custom-fps'), '');
    expect(fake.peers, isEmpty);

    expect(await a.toggle('view-only'), isTrue);
    expect(a.getToggle('view-only'), isTrue);
    expect(b.getToggle('view-only'), isFalse);
    await a.toggle('view-only');
    expect(a.getToggle('view-only'), isFalse);

    expect(fps(), 1);
    expect(viewOnly(), 2);
  });
}
