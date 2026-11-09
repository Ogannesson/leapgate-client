import 'dart:convert';

import 'package:flutter_hbb/leapgate/tunnel_api.dart';
import 'package:flutter_test/flutter_test.dart';

// The saved port forwards a TCP tunnel card starts with (`LEAPGATE.md` §10.18). Addresses are
// from the documentation ranges.
void main() {
  test('the saved forwards, without the old UI\'s exit mapping and ports ≤ 0',
      () {
    final json = jsonEncode({
      'port_forwards': [
        [8080, '192.0.2.10', 80],
        [21180, 'leapgate-exit.invalid', 65536],
        [0, '192.0.2.11', 22],
        [2222, '192.0.2.12', 0],
        [3390, 'localhost', 3389],
      ],
    });
    expect(parseSavedForwards(json), [
      (localPort: 8080, host: '192.0.2.10', remotePort: 80),
      (localPort: 3390, host: 'localhost', remotePort: 3389),
    ]);
  });

  test('no forwards when the answer is not of that shape', () {
    expect(parseSavedForwards('{}'), isEmpty);
    expect(parseSavedForwards(''), isEmpty);
    expect(parseSavedForwards('{"port_forwards": 1}'), isEmpty);
  });
}
