// Identity colour of a device (docs/新界面/03-实施方案.md §4.1, 01 §2.4).
//
// Every device gets one of the seven identity colour groups from its ID, so the
// same ID always has the same colour on the main window, the connection manager
// (by the visitor's ID) and the phone. The colour values themselves live in the
// app's design tokens; this file only picks the group.

import 'dart:convert';

/// Number of identity colour groups (k1..k7 in the mockups).
const int kIdentityGroups = 7;

/// FNV-1a, 32 bits, over the UTF-8 bytes of [s].
int fnv1a32(String s) {
  var h = 0x811c9dc5;
  for (final b in utf8.encode(s)) {
    h ^= b;
    h = (h * 0x01000193) & 0xffffffff;
  }
  return h;
}

/// The identity colour group of a device ID: 0..6, group k1 is 0.
///
/// Pass the ID as stored, without the display spaces.
int identityGroup(String id) => fnv1a32(id) % kIdentityGroups;
