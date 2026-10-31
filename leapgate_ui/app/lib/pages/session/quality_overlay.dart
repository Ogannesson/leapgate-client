import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/session.dart';

/// The quality data over the image, top left (01 P2 block C, M2b). Fills the image area and
/// places itself; where it draws nothing, pointer events reach the image below.
class QualityOverlay extends StatelessWidget {
  const QualityOverlay({super.key, required this.ffi});

  final FFI ffi;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
