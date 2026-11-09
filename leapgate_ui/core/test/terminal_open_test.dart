import 'package:flutter_hbb/leapgate/app_core.dart';
import 'package:flutter_hbb/leapgate/session.dart';
import 'package:flutter_hbb/leapgate/terminal/terminals.dart';
import 'package:flutter_test/flutter_test.dart';

import 'fakes.dart';

// Which terminal a device's tab has (R3-Q9, `LEAPGATE.md` §10.18). Device IDs here are made up.
void main() {
  test('no terminal view, a normal one or the administrator\'s', () {
    installFakes();
    final registry = appCore.sessions;
    expect(terminalOpenState('100200300'), TerminalOpen.none);

    registry.open('100200300', ConnType.defaultConn);
    expect(terminalOpenState('100200300'), TerminalOpen.none);

    final normal = registry.open('100200300', ConnType.terminal);
    expect(normal.terminalAdmin, isFalse);
    expect(terminalOpenState('100200300'), TerminalOpen.normal);

    final admin =
        registry.open('400500600', ConnType.terminal, terminalAdmin: true);
    expect(admin.terminalAdmin, isTrue);
    expect(terminalOpenState('400500600'), TerminalOpen.admin);
    // A device's terminal view is made once: asking for the other kind returns it.
    expect(registry.open('400500600', ConnType.terminal), same(admin));
  });

  test('closing the terminal view leaves none', () async {
    installFakes();
    final registry = appCore.sessions;
    registry.open('100200300', ConnType.defaultConn);
    final terminal = registry.open('100200300', ConnType.terminal);

    await registry.close(terminal);

    expect(terminalOpenState('100200300'), TerminalOpen.none);
  });

  test(
      'tokenOf: any view\'s connection token of the device, null without a tab',
      () {
    final fakes = installFakes();
    final registry = appCore.sessions;
    expect(registry.tokenOf('100200300'), isNull);

    final desktop = registry.open('100200300', ConnType.defaultConn);
    expect(registry.tokenOf('100200300'), isNull);
    fakes.bind.tokens[desktop.sessionId] = 'token-1';

    expect(registry.tokenOf('100200300'), 'token-1');
    expect(registry.tokenOf('400500600'), isNull);
  });
}
