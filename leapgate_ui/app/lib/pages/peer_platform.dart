import 'package:flutter_hbb/consts.dart';

import '../widgets/lg_device.dart';

/// A device's platform as Rust reports it (upstream `kPeerPlatform*`), for its icon.
LgPlatform lgPlatformOf(String platform) => switch (platform) {
      kPeerPlatformWindows => LgPlatform.windows,
      kPeerPlatformMacOS => LgPlatform.macos,
      kPeerPlatformLinux => LgPlatform.linux,
      kPeerPlatformAndroid => LgPlatform.android,
      _ => LgPlatform.unknown,
    };
