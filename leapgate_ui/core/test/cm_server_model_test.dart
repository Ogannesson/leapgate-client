import 'dart:convert';
import 'dart:ui';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_hbb/common.dart';
import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/cm_core.dart';
import 'package:flutter_hbb/models/platform_model.dart';
import 'package:flutter_hbb/models/server_model.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

// The connection manager's copied ServerModel and its events (LEAPGATE.md §10.10, 06 §4.2,
// upstream `server_model.dart:133-190`, `:525-590`, `:696-721`). Device IDs here are made up.

class CmFakeBind extends FakeBind {
  /// `approve-mode` of this device.
  String approveMode = '';

  /// What `cm_check_clients_length` answers: null when the service has as many visitors.
  String? lengthMismatch;

  /// What `cm_get_clients_state` answers.
  String clientsState = '[]';

  @override
  dynamic noSuchMethod(Invocation invocation) {
    switch (invocation.memberName) {
      case #optionSynced:
        calls.add(invocation);
        return Future<bool>.value(false);
      case #cmCheckClientsLength:
        calls.add(invocation);
        return Future<String?>.value(lengthMismatch);
      case #cmGetClientsState:
        calls.add(invocation);
        return Future<String>.value(clientsState);
      case #mainGetOption:
        calls.add(invocation);
        return Future<String>.value(approveMode);
      case #cmLoginRes:
        calls.add(invocation);
        return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

class FakeCmWindow implements CmWindow {
  final calls = <String>[];

  int count(String name) => calls.where((c) => c == name).length;

  @override
  Future<void> show() async => calls.add('show');

  @override
  Future<void> hide() async => calls.add('hide');

  @override
  Future<void> collapse() async => calls.add('collapse');

  @override
  Future<void> close() async => calls.add('close');

  @override
  Future<void> bringToFront() async => calls.add('bringToFront');

  @override
  Future<Rect> getFrame() async => Rect.zero;

  @override
  Future<void> setFullscreen(bool fullscreen) async {}
}

Map<String, dynamic> client(int id,
        {String peerId = '100200300',
        bool authorized = false,
        String portForward = ''}) =>
    {
      'id': id,
      'authorized': authorized,
      'is_file_transfer': false,
      'is_view_camera': false,
      'is_terminal': false,
      'port_forward': portForward,
      'name': 'Visitor $id',
      'peer_id': peerId,
      'keyboard': true,
      'clipboard': true,
      'audio': true,
      'file': true,
      'restart': true,
      'recording': false,
      'block_input': false,
      'privacy_mode': false,
      'disconnected': false,
      'from_switch': false,
      'in_voice_call': false,
      'incoming_voice_call': false,
    };

Map<String, dynamic> added(Map<String, dynamic> c) =>
    {'name': 'add_connection', 'client': jsonEncode(c)};

Map<String, dynamic> removed(int id, {required bool close}) =>
    {'name': 'on_client_remove', 'id': '$id', 'close': '$close'};

void main() {
  late CmFakeBind bind;
  late FakeCmWindow window;

  ServerModel start() {
    final model = ServerModel(window);
    registerCmEvents(model);
    return model;
  }

  void send(FakeAsync async, Map<String, dynamic> evt) {
    appCore.events.dispatch(evt);
    async.flushMicrotasks();
  }

  setUp(() {
    installFakes();
    bind = CmFakeBind();
    platformFFI.setBindingForTesting(bind);
    desktopType = DesktopType.cm;
    window = FakeCmWindow();
  });

  test(
      'one connection, two events: waiting, then authorized by password; it collapses 3 s later',
      () {
    fakeAsync((async) {
      final model = start();
      send(async, added(client(1)));
      async.elapse(Duration.zero);
      expect(model.clients.single.authorized, false);
      expect(window.count('bringToFront'), 1);
      async.elapse(const Duration(seconds: 3));
      expect(window.count('collapse'), 0);

      send(async, added(client(1, authorized: true)));
      expect(model.clients.length, 1);
      expect(model.clients.single.authorized, true);
      async.elapse(const Duration(milliseconds: 2900));
      expect(window.count('collapse'), 0);
      async.elapse(const Duration(milliseconds: 100));
      expect(window.count('collapse'), 1);
      model.dispose();
    });
  });

  test(
      'accepted here: Rust is told and the authorized event that follows starts no collapse',
      () {
    fakeAsync((async) {
      final model = start();
      send(async, added(client(1)));
      model.sendLoginResponse(model.clients.single, true);
      final res = bind.callsTo(#cmLoginRes).single.namedArguments;
      expect((res[#connId], res[#res]), (1, true));
      expect(model.clients.single.authorized, true);

      send(async, added(client(1, authorized: true)));
      async.elapse(const Duration(seconds: 5));
      expect(model.clients.length, 1);
      expect(window.count('collapse'), 0);
      model.dispose();
    });
  });

  test(
      'a disconnected visitor stays until closed; the same device coming back replaces it',
      () {
    fakeAsync((async) {
      final model = start();
      send(async, added(client(1, authorized: true)));
      send(async, removed(1, close: false));
      expect(model.clients.single.disconnected, true);

      send(async, added(client(2, authorized: true)));
      expect([for (final c in model.clients) c.id], [2]);

      send(async, added(client(3, peerId: '400500600')));
      send(async, removed(3, close: false));
      send(async, removed(2, close: true));
      expect([for (final c in model.clients) c.id], [3]);
      expect(window.count('hide'), 0);
      send(async, removed(3, close: true));
      expect(model.clients, isEmpty);
      expect(window.count('hide'), 1);
      model.dispose();
    });
  });

  test('a list that differs from the service is read again', () {
    fakeAsync((async) {
      final model = start();
      bind.lengthMismatch = '';
      bind.clientsState = jsonEncode([client(4, authorized: true)]);
      async.elapse(const Duration(milliseconds: 500));
      expect([for (final c in model.clients) c.id], [4]);
      expect(window.count('show'), greaterThan(0));
      model.dispose();
    });
  });

  test('without visitors the window hides and closes after about 6 s', () {
    fakeAsync((async) {
      final model = start();
      async.elapse(const Duration(milliseconds: 500));
      expect(window.count('hide'), 1);

      // A visitor in between starts the count again.
      async.elapse(const Duration(seconds: 3));
      send(async, added(client(1)));
      async.elapse(const Duration(milliseconds: 500));
      send(async, removed(1, close: true));

      async.elapse(const Duration(seconds: 6));
      expect(window.count('close'), 0);
      async.elapse(const Duration(milliseconds: 500));
      expect(window.count('close'), 1);
      async.elapse(const Duration(seconds: 5));
      expect(window.count('close'), 1);
      model.dispose();
    });
  });

  test('approve mode is read for the waiting visitor', () {
    fakeAsync((async) {
      bind.approveMode = 'password';
      final model = start();
      async.elapse(const Duration(milliseconds: 500));
      expect(model.approveMode, 'password');
      model.dispose();
    });
  });

  test('the elevation event', () {
    fakeAsync((async) {
      final model = start();
      send(async, {'name': 'show_elevation', 'show': 'true'});
      expect(model.showElevation, true);
      model.dispose();
    });
  });

  test('an exit node is a port forward to the exit sentinel', () {
    expect(
        cmSessionKind(Client.fromJson(client(1))), CmSessionKind.remoteDesktop);
    expect(
        cmSessionKind(
            Client.fromJson(client(1, portForward: '192.0.2.10:8080'))),
        CmSessionKind.portForward);
    expect(
        cmSessionKind(Client.fromJson(
            client(1, portForward: 'leapgate-exit.invalid:65536'))),
        CmSessionKind.exit);
  });
}
