import 'package:flutter_hbb/leapgate/identity_color.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('fnv1a32 matches the published FNV-1a test vectors', () {
    expect(fnv1a32(''), 0x811c9dc5);
    expect(fnv1a32('a'), 0xe40c292c);
    expect(fnv1a32('foobar'), 0xbf9cf968);
  });

  test('identityGroup is the hash modulo 7', () {
    // Values cross-checked with an independent implementation.
    expect(identityGroup('123456789'), 1); // 0xbb86b11c
    expect(identityGroup('234567891'), 3); // 0x3f1914f4
    expect(identityGroup('135792468'), 0); // 0x84d0d244
    expect(identityGroup('987654321'), 4); // 0x854ba54c
    expect(identityGroup('abc-def'), 5); // 0x9f6db3f9
  });

  test('identityGroup stays in range and is stable', () {
    for (var i = 0; i < 1000; i++) {
      final id = '${100000000 + i * 7919}';
      final g = identityGroup(id);
      expect(g, inInclusiveRange(0, kIdentityGroups - 1));
      expect(identityGroup(id), g);
    }
  });
}
