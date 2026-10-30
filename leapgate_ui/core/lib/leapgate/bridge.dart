// The second flutter_rust_bridge block, `src/leapgate_ffi.rs` (LEAPGATE.md §10.3). Its generated
// Dart declares classes with the same names as block 1's (`EventToUI`, `wire_uint_8_list`, ...),
// so it is only ever imported with a prefix.
import 'dart:ffi';

import 'package:flutter/foundation.dart';
import 'package:flutter_hbb/generated_bridge_leapgate.dart' as lg;

lg.Leapgate? _lgBind;

/// Leapgate's exports. Built on the core library `PlatformFFI` loads
/// (`models/native_model.dart`); opening a loaded dll again returns the same module.
lg.Leapgate get lgBind =>
    _lgBind ??= lg.LeapgateImpl(DynamicLibrary.open('libleapgate.dll'));

@visibleForTesting
void setLgBindForTesting(lg.Leapgate binding) => _lgBind = binding;
