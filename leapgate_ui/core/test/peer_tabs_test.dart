import 'package:flutter_hbb/consts.dart';
import 'package:flutter_hbb/generated_bridge.dart';
import 'package:flutter_hbb/leapgate/options.dart';
import 'package:flutter_hbb/leapgate/peer_list.dart';
import 'package:flutter_hbb/leapgate/peer_tabs.dart';
import 'package:flutter_hbb/leapgate/recent_peers.dart';
import 'package:flutter_hbb/leapgate/ui_mode.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_test/flutter_test.dart';

/// LocalConfig and its Flutter table, as maps.
class _Bind implements RustdeskImpl {
  final local = <String, String>{};
  final flutter = <String, String>{};

  @override
  String mainGetLocalOption({required String key, dynamic hint}) =>
      local[key] ?? '';

  @override
  Future<void> mainSetLocalOption(
          {required String key, required String value, dynamic hint}) async =>
      local[key] = value;

  @override
  String getLocalFlutterOption({required String k, dynamic hint}) =>
      flutter[k] ?? '';

  @override
  Future<void> setLocalFlutterOption(
          {required String k, required String v, dynamic hint}) async =>
      flutter[k] = v;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late _Bind bind;
  setUp(() {
    bind = _Bind();
    platformFFI.setBindingForTesting(bind);
  });

  PeerTabs tabs() => PeerTabs(OptionsModel());

  group('categories (peer_tab_model.dart)', () {
    test('recent, favorites and LAN; the address book and team devices wait',
        () {
      final t = tabs();
      expect(t.shown,
          [PeerCategory.recent, PeerCategory.favorites, PeerCategory.lan]);
      expect(t.current, PeerCategory.recent);
    });

    test('the built-in option hides LAN', () {
      bind.local['disable-discovery-panel'] = 'Y';
      expect(tabs().shown, [PeerCategory.recent, PeerCategory.favorites]);
    });

    test("reads upstream's stored order, visibility and selection", () {
      bind.flutter
        ..[kOptionPeerTabOrder] = '[2,4,0,3,1]'
        ..[kOptionPeerTabVisible] = '[true,false,true,true,true]'
        ..[kOptionPeerTabIndex] = '2';
      final t = tabs();
      expect(t.ordered,
          [PeerCategory.lan, PeerCategory.recent, PeerCategory.favorites]);
      expect(t.shown, [PeerCategory.lan, PeerCategory.recent]);
      expect(t.current, PeerCategory.lan);
    });

    test('hiding the selected category selects the first one shown', () {
      final t = tabs()..select(PeerCategory.favorites);
      t.setVisible(PeerCategory.favorites, false);
      expect(t.current, PeerCategory.recent);
      expect(
          bind.flutter[kOptionPeerTabVisible], '[true,false,true,true,true]');
    });

    test('moving keeps the slots of the categories not in this build', () {
      final t = tabs()..move(PeerCategory.lan, 0);
      expect(t.ordered,
          [PeerCategory.lan, PeerCategory.recent, PeerCategory.favorites]);
      expect(bind.flutter[kOptionPeerTabOrder], '[2,0,1,3,4]');
    });
  });

  group('view', () {
    test('follows the interface mode until the user picks one (01 §2.3)', () {
      final t = tabs();
      expect(t.view, PeerView.cards);
      bind.local[kOptionLeapgateUiMode] = 'detail';
      expect(t.view, PeerView.list);
      t.setView(PeerView.cards);
      expect(t.view, PeerView.cards);
      expect(bind.flutter[kOptionPeerCardUiType], '0');
    });

    test("upstream's two tile sizes are cards", () {
      bind.flutter[kOptionPeerCardUiType] = '1';
      expect(tabs().view, PeerView.cards);
      bind.flutter[kOptionPeerCardUiType] = '2';
      expect(tabs().view, PeerView.list);
    });
  });

  test("sort in upstream's values; ID when unset or unknown", () {
    final t = tabs();
    expect(t.sort, PeerSort.id);
    t.setSort(PeerSort.name);
    expect(bind.flutter[kOptionPeerSorting], 'Remote Host');
    expect(t.sort, PeerSort.name);
    bind.flutter[kOptionPeerSorting] = 'something';
    expect(t.sort, PeerSort.id);
  });
}
