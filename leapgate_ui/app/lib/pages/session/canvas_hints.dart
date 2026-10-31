import 'package:flutter/material.dart';
import 'package:flutter_hbb/leapgate/session.dart';

/// What the input settings put over the image (01 P2 block C, M2b): the relative mouse hint at
/// the top centre and the Android navigation bar. Fills the image area and places itself;
/// where it draws nothing, pointer events reach the image below.
class CanvasHints extends StatelessWidget {
  const CanvasHints({super.key, required this.ffi});

  final FFI ffi;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
