import 'package:flutter_hbb/leapgate/connect_box.dart';
import 'package:flutter_hbb/models/peer_model.dart';
import 'package:flutter_test/flutter_test.dart';

Peer peer(String id,
        {String alias = '',
        String hostname = '',
        String username = '',
        String note = ''}) =>
    Peer.fromJson({
      'id': id,
      'alias': alias,
      'hostname': hostname,
      'username': username,
      'note': note,
    });

void main() {
  group('looksLikeAddress (01 P1 block E)', () {
    const addresses = {
      'numeric ID': '123456789',
      'numeric ID in groups': '123 456 789',
      'numeric ID with /r': '123456789/r',
      r'numeric ID with \r': r'123456789\r',
      'IPv4': '192.0.2.10',
      'IPv4 with port': '192.0.2.10:21118',
      'IPv4 with /r': '192.0.2.10/r',
      'IPv6': '2001:db8::1',
      'IPv6 with port': '[2001:db8::1]:21118',
      'domain:port': 'pc.example.com:21118',
      'ID@server': '123456789@example.com',
      'ID@server with key': '123456789@198.51.100.7:21116?key=abc',
      'custom ID@server': 'office-pc@example.com',
      'ID/r@server': '123456789/r@example.com',
      'ID@public': '123456789@public',
    };
    const names = {
      'a name': '书房',
      'a name with /r': '书房/r',
      'a host name': 'DESKTOP-SHUFANG',
      'domain without port': 'pc.example.com',
      'out-of-range IPv4': '192.0.2.300',
      'user@host as shown on a row': 'zhangsan@',
      'nothing before @': '@example.com',
      'name before @': '书房@example.com',
      'only /r': '/r',
      'empty': '',
    };
    addresses.forEach((what, input) {
      test('$what: $input', () => expect(looksLikeAddress(input), isTrue));
    });
    names.forEach((what, input) {
      test('not $what: $input', () => expect(looksLikeAddress(input), isFalse));
    });
  });

  group('peerMatches', () {
    final p = peer('123456789',
        alias: '书房台式机',
        hostname: 'DESKTOP-SHUFANG',
        username: 'zhangsan',
        note: '家里');
    test('ID, alias, host name, user name and note, ignoring case', () {
      for (final q in ['6789', '书房', 'shufang', 'ZhangSan', '家里']) {
        expect(peerMatches(p, q), isTrue, reason: q);
      }
      expect(peerMatches(p, '办公室'), isFalse);
    });
    test('the ID is compared without spaces', () {
      expect(peerMatches(p, '123 456'), isTrue);
    });
  });

  group('ConnectBoxSearch default row (01 P1 block E, Q2)', () {
    final peers = [
      peer('123456789', alias: '书房台式机'),
      peer('234567891', hostname: 'LAPTOP-MAMA'),
      peer('345678912', alias: '书房笔记本'),
    ];

    test('an ID equal to a device ID: that device', () {
      final s = ConnectBoxSearch('234 567 891', peers);
      expect(s.matches.map((p) => p.id), ['234567891']);
      expect(s.defaultRow, 1);
    });

    test('an exact ID wins over earlier partial matches', () {
      final s = ConnectBoxSearch('345678912', peers);
      expect(s.defaultRow, s.matches.indexWhere((p) => p.id == '345678912') + 1);
    });

    test('looks like an address: "Connect to" even with matches', () {
      final s = ConnectBoxSearch('6789', peers);
      expect(s.matches, hasLength(3));
      expect(s.defaultRow, 0);
    });

    test('a name with matches: the first match', () {
      final s = ConnectBoxSearch('书房', peers);
      expect(s.matches.map((p) => p.id), ['123456789', '345678912']);
      expect(s.defaultRow, 1);
    });

    test('a name without matches: "Connect to"', () {
      final s = ConnectBoxSearch('办公桌', peers);
      expect(s.matches, isEmpty);
      expect(s.rowCount, 1);
      expect(s.defaultRow, 0);
    });

    test('an ID with /r is not the exact device but an address', () {
      final s = ConnectBoxSearch('123456789/r', peers);
      expect(s.defaultRow, 0);
    });
  });
}
