import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/session.dart';

import '../../../shell/tab_overlays.dart';

/// Chat and voice calls (01 P2 block F, M2b). The toolbar places [chatToolbarButtons] after the
/// "会话" menu; the session page stacks [ChatLayer] above the notices (01 P2 block C).
List<Widget> chatToolbarButtons(
  BuildContext context,
  FFI ffi,
  TabOverlays overlays,
) => const [];

class ChatLayer extends StatelessWidget {
  const ChatLayer({super.key, required this.ffi});

  final FFI ffi;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
